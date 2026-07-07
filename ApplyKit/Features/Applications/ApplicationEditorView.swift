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
    @State var isAnalyzingJD = false
    @State var isSuggestingExperiences = false
    @State var isCuratingBullets = false
    @State var curatedSuggestions: [CuratedBulletSuggestion] = []

    @State var generatingDocumentKind: GeneratedDocumentKind?
    @State private var scrollModel = EditorScrollModel()
    @State private var saveDebouncer = Debouncer()

    private let scrollSpace = "applicationEditorScroll"

    var documents: [GeneratedDocument] { store.documents.filter { $0.applicationID == application.id } }
    var experiences: [ExperienceBullet] { store.experiences }
    var employments: [Employment] { store.employments }
    var applications: [JobApplication] { store.applications }

    /// Reads curated suggestions data directly from the store so that post-bootstrap
    /// updates flow into the view even if @State was initialized before the store loaded.
    var storeCuratedSuggestionsData: String {
        store.applications.first(where: { $0.id == application.id })?.curatedSuggestionsData ?? ""
    }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                EditorSectionRail(model: scrollModel) { section in
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
                        DetailPanel("Role Details") {
                            roleForm
                        }
                        documentActions
                            .editorSection(.documents, space: scrollSpace)
                        sectionOrderSection
                            .editorSection(.sectionOrder, space: scrollSpace)
                        HStack(alignment: .top, spacing: 16) {
                            selectedExperienceSection
                            selectedProjectSection
                        }
                        .editorSection(.experience, space: scrollSpace)
                        selectedBulletWordingSection
                            .editorSection(.tailorExperience, space: scrollSpace)
                        summarySection
                            .editorSection(.summary, space: scrollSpace)
                        skillsSection
                            .editorSection(.skills, space: scrollSpace)
                        jobDescriptionSection
                            .editorSection(.jobDescription, space: scrollSpace)
                        jdAnalysisSection
                            .editorSection(.jdAnalysis, space: scrollSpace)
                        curatedBulletsSection
                            .editorSection(.gapSuggestions, space: scrollSpace)
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
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(application.displayTitle)
        .onChange(of: storeCuratedSuggestionsData, initial: true) { _, newValue in
            guard curatedSuggestions.isEmpty, !newValue.isEmpty else { return }
            curatedSuggestions = decodeCuratedSuggestions(newValue)
        }
        .onChange(of: applicationPersistenceFingerprint) { _, _ in
            saveDebouncer.schedule { persistApplicationChanges() }
        }
        .onDisappear {
            saveDebouncer.flush { persistApplicationChanges() }
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
