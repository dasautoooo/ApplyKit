//
//  ApplicationEditorView.swift
//  ApplyKit
//

import AppKit
import SwiftUI

struct ApplicationEditorView: View {
    @Environment(AppDataStore.self) var store
    @State var application: JobApplication

    let settings: AppSettings?
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onDeleteRequest: () -> Void

    @Environment(AppActivityMonitor.self) var activityMonitor
    @Environment(TailoringRunner.self) var tailoringRunner
    @State var isSuggestingExperiences = false
    @State var isCuratingBullets = false
    /// Both growth suggestions (gap panel) and recall drafts from the clarify
    /// loop; `origin` tells them apart. Persisted together in
    /// `curatedSuggestionsData`.
    @State var curatedSuggestions: [CuratedBulletSuggestion] = []

    /// The brief being edited, held decoded. Typing an answer used to decode and
    /// re-encode the whole brief, write it into the store, and kick off a disk
    /// write on every keystroke; this is the working copy, and it is committed on
    /// a debounce instead.
    @State var editingBrief: TailoringBrief?
    @State var briefSaveDebouncer = Debouncer()
    /// The encoded brief this editor last wrote or adopted, so it can tell a
    /// background run's result from the echo of its own save.
    @State var committedBriefData: String = ""

    @State var showTailoringSheet = false
    @State var tailoringPastedText = ""
    @State var tailoringChanges: [TailoringChange] = []
    /// Errors and warnings from the last pasted edit plan import.
    @State var tailoringImportIssues: [ResumeEditPlanIssue] = []
    @AppStorage("resumeTailor.source") var tailoringSourceRaw = TailoringSourceMode.externalChat.rawValue
    /// When the context was last copied for an external chat — step 1's check.
    @State var tailoringContextCopiedAt: Date?
    @State var showPastedPlanText = false
    @State var showPastedReviewText = false
    /// A PDF review pasted from ChatGPT, awaiting reconciliation.
    @State var pastedReviewText = ""
    /// Wording each applied rewrite replaced, so the diff doesn't collapse into
    /// "current == tailored" once the bullet has been updated.
    @State var appliedBeforeText: [String: String] = [:]
    /// State to put back when an applied change is reverted, keyed by change id.
    @State var revertPoints: [String: TailoringRevertPoint] = [:]

    @State var generatingDocumentKind: GeneratedDocumentKind?
    @State var masterResumePendingApply: MasterResume?
    @State var showSaveAsMasterResume = false
    @State var saveAsMasterResumeName = ""
    /// Timeline entries this editor has already accounted for. Lets `adoptExternalTimelineEvents`
    /// tell "recorded elsewhere while I wasn't looking" from "the user just deleted this".
    @State var knownTimelineEventIDs: Set<UUID> = []
    /// The notes text this editor and the store last agreed on, so a background
    /// run appending Q&A can be merged without clobbering local typing.
    @State var adoptedNotes: String = ""
    @State private var scrollModel = EditorScrollModel()
    @State private var saveDebouncer = Debouncer()
    @AppStorage("applicationEditor.inspectorVisible") private var isInspectorVisible = true
    @AppStorage("applicationEditor.inspectorWidth") private var inspectorWidth = 380.0

    private let scrollSpace = "applicationEditorScroll"

    var documents: [GeneratedDocument] { store.documents.filter { $0.applicationID == application.id } }
    /// The shared bank plus any bullets kept private to this application. Every
    /// selection list, wording group, AI prompt, and generated document reads
    /// this rather than `store.experiences`, so another application's private
    /// bullets can never leak in.
    var experiences: [ExperienceBullet] {
        ExperienceScope.visible(store.experiences, to: application.id)
    }
    var employments: [Employment] { store.employments }
    var applications: [JobApplication] { store.applications }

    /// Reads curated suggestions data directly from the store so that post-bootstrap
    /// updates flow into the view even if @State was initialized before the store loaded.
    var storeCuratedSuggestionsData: String {
        store.applications.first(where: { $0.id == application.id })?.curatedSuggestionsData ?? ""
    }

    /// Tailoring state lives on the stored record, not in this view: a run can
    /// finish while another application is on screen, and must not be lost when
    /// this editor is rebuilt.
    var storedApplication: JobApplication? {
        store.applications.first { $0.id == application.id }
    }

    var storeTailoringBriefData: String { storedApplication?.tailoringBriefData ?? "" }

    var tailoringBrief: TailoringBrief? { editingBrief ?? storedApplication?.tailoringBrief }

    var tailoringPlan: TailoringPlan? {
        TailoringSession.decode(storedApplication?.tailoringPlanData ?? "")?.plan
    }

    var isRunningBrief: Bool { tailoringRunner.isRunning(.brief, for: application.id) }
    var isClarifying: Bool { tailoringRunner.isRunning(.clarify, for: application.id) }
    var isReconcilingTailoring: Bool {
        tailoringRunner.isRunning(.build, for: application.id)
    }

    /// Timeline as the store currently holds it. Archive and restore are recorded by the
    /// applications list, not here, so this editor's snapshot can fall behind — and its
    /// autosave would then write those entries back out of existence.
    var storeTimeline: [ApplicationEvent] {
        store.applications.first(where: { $0.id == application.id })?.timeline ?? []
    }

    var body: some View {
        StableInspectorSplit(
            inspectorWidth: Binding(
                get: { CGFloat(inspectorWidth) },
                set: { inspectorWidth = Double($0) }
            ),
            isVisible: $isInspectorVisible
        ) {
            resumeBuildingPane
        } inspector: {
            jobContextInspector
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(application.displayTitle)
        .onChange(of: storeCuratedSuggestionsData, initial: true) { _, newValue in
            guard curatedSuggestions.isEmpty, !newValue.isEmpty else { return }
            let decoded = decodeCuratedSuggestions(newValue)
            // Clarify used to draft bullets here; it records facts on the brief
            // now, so any left over are dead records rather than hidden ones.
            curatedSuggestions = decoded.filter { $0.origin == .growth }
            if curatedSuggestions.count != decoded.count {
                application.curatedSuggestionsData = encodeCuratedSuggestions(curatedSuggestions)
                persistApplicationChanges()
            }
        }
        .onChange(of: storedTailoringFingerprint) { _, _ in
            adoptExternalTailoringState()
        }
        .onAppear {
            knownTimelineEventIDs = Set(application.timeline.map(\.id))
            adoptedNotes = application.notes
            adoptExternalTailoringState()
        }
        .onChange(of: storeTimeline.map(\.id)) { _, _ in
            adoptExternalTimelineEvents(into: &application)
        }
        .onChange(of: applicationPersistenceFingerprint) { _, _ in
            saveDebouncer.schedule { persistApplicationChanges() }
        }
        .onDisappear {
            briefSaveDebouncer.flush { commitTailoringBrief() }
            saveDebouncer.flush { persistApplicationChanges() }
        }
    }

    private var resumeBuildingPane: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                EditorSectionRail(
                    model: scrollModel,
                    isInspectorVisible: isInspectorVisible,
                    onToggleInspector: { isInspectorVisible.toggle() }
                ) { section in
                    scrollModel.isAutoScrolling = true
                    scrollModel.active = section
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(section, anchor: .top)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        scrollModel.isAutoScrolling = false
                    }
                }
                .padding(.top, 24)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                            .editorSection(.roleDetails, space: scrollSpace)
                        DetailPanel("Role Details", collapseKey: "applicationEditor.collapsed.roleDetails") {
                            roleForm
                        }
                        interviewProcessSection
                            .editorSection(.interviews, space: scrollSpace)
                        timelineSection
                            .editorSection(.timeline, space: scrollSpace)
                        masterResumePanel
                            .editorSection(.masterResume, space: scrollSpace)
                        documentActions
                            .editorSection(.documents, space: scrollSpace)
                        sectionOrderSection
                            .editorSection(.sectionOrder, space: scrollSpace)
                        summarySection
                            .editorSection(.summary, space: scrollSpace)
                        HStack(alignment: .top, spacing: 16) {
                            selectedExperienceSection
                            selectedProjectSection
                        }
                        .editorSection(.experience, space: scrollSpace)
                        selectedBulletWordingSection
                            .editorSection(.tailorExperience, space: scrollSpace)
                        skillsSection
                            .editorSection(.skills, space: scrollSpace)
                        notesSection
                            .editorSection(.notes, space: scrollSpace)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 1160, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .coordinateSpace(name: scrollSpace)
                .onPreferenceChange(SectionOffsetKey.self) { offsets in
                    updateActiveSection(offsets)
                }
            }
        }
    }

    /// Highlights the lowest section whose top has scrolled to/above the viewport top.
    private func updateActiveSection(_ offsets: [EditorSection: CGFloat]) {
        guard !scrollModel.isAutoScrolling, !offsets.isEmpty else { return }
        let threshold: CGFloat = 40
        let passed = offsets.filter { $0.value <= threshold }
        let next = passed.max(by: { $0.value < $1.value })?.key
            ?? offsets.min(by: { $0.value < $1.value })?.key
        if let next, next != scrollModel.active {
            scrollModel.active = next
        }
    }
}
