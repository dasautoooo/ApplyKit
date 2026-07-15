//
//  MasterResumeEditorView.swift
//  ApplyKit
//

import AppKit
import SwiftUI

struct MasterResumeEditorView: View {
    @Environment(AppDataStore.self) var store
    @Environment(AppActivityMonitor.self) var activityMonitor
    @State var masterResume: MasterResume

    let settings: AppSettings?

    @State var isGeneratingPreview = false
    @State var previewPDFPath: String?
    @State var previewTexPath: String?
    @State var previewBuildLog = ""
    @State private var saveDebouncer = Debouncer()

    var experiences: [ExperienceBullet] { store.experiences }
    var employments: [Employment] { store.employments }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                previewSection
                ResumeSectionOrderSection(content: $masterResume)
                ResumeSummarySection(content: $masterResume)
                HStack(alignment: .top, spacing: 16) {
                    ResumeExperienceSelectionSection(content: $masterResume, experiences: experiences, employments: employments) {
                        EmptyView()
                    }
                    ResumeProjectSelectionSection(content: $masterResume, experiences: experiences, employments: employments)
                }
                ResumeWordingSection(
                    content: $masterResume,
                    experiences: experiences,
                    employments: employments,
                    applications: store.applications,
                    settings: settings,
                    refinePrompt: nil,
                    experienceBinding: experienceBinding(for:),
                    onPersistExperience: persistExperienceChanges,
                    onPersistApplication: persistApplicationChanges,
                    onPersistContent: persistMasterResumeChanges
                )
                ResumeSkillsSection(content: $masterResume, globalSkillsBlock: store.profile.skillsBlock)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1160, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(masterResume.displayTitle)
        .onChange(of: masterResumePersistenceFingerprint) { _, _ in
            saveDebouncer.schedule { persistMasterResumeChanges() }
        }
        .onDisappear {
            saveDebouncer.flush { persistMasterResumeChanges() }
        }
        .onAppear(perform: locateExistingPreview)
    }

    private var header: some View {
        DetailPanel("Master Resume") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledControl("Name") {
                    TextField("e.g. iOS Engineer", text: $masterResume.name)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledControl("Notes") {
                    TextEditor(text: $masterResume.notes)
                        .font(.body)
                        .frame(minHeight: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                        )
                }
                Text("A master resume is a reusable preset for one role direction. Apply it from an application's Documents panel to start that application pre-filled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Persistence

    var masterResumePersistenceFingerprint: String {
        [
            masterResume.id.uuidString,
            masterResume.name,
            masterResume.notes,
            masterResume.selectedExperienceIDsText,
            masterResume.selectedProjectIDsText,
            masterResume.selectedVariantIDsText,
            masterResume.employmentRoleDescriptionsText,
            masterResume.hiddenRoleDescriptionIDsText,
            masterResume.experienceOrderText,
            masterResume.sectionOrderText,
            masterResume.skillsBlockText,
            masterResume.summaryText
        ].joined(separator: "\u{1F}")
    }

    func persistMasterResumeChanges() {
        persistMasterResumeChanges(masterResume)
    }

    func persistMasterResumeChanges(_ targetMasterResume: MasterResume) {
        var target = targetMasterResume
        target.updatedAt = Date()
        guard let settings else { return }

        // Update the in-memory store synchronously (cheap) so the sidebar reflects
        // the edit immediately...
        if let idx = store.masterResumes.firstIndex(where: { $0.id == target.id }) {
            store.masterResumes[idx] = target
        }
        if target.id == masterResume.id {
            masterResume = target
        }

        // ...then write the file to disk off the main thread so typing never blocks on I/O.
        guard let root = try? WorkspaceService.workspaceURL(settings: settings) else { return }
        let snapshot = target
        let monitor = activityMonitor
        Task.detached(priority: .utility) {
            do {
                try WorkspaceSyncService.writeMasterResumeFile(snapshot, root: root)
            } catch {
                let message = error.localizedDescription
                await MainActor.run { monitor.fail(message) }
            }
        }
    }

    func persistExperienceChanges(_ experience: ExperienceBullet) {
        var updated = experience
        updated.updatedAt = Date()
        guard let settings else { return }
        do {
            try WorkspaceSyncService.persistExperience(updated, allExperiences: store.experiences, settings: settings)
            if let idx = store.experiences.firstIndex(where: { $0.id == updated.id }) {
                store.experiences[idx] = updated
            }
        } catch {
            activityMonitor.fail(error.localizedDescription)
        }
    }

    /// Persists another application whose variant selection was reset when a
    /// variant is deleted from this editor.
    func persistApplicationChanges(_ application: JobApplication) {
        var updated = application
        updated.updatedAt = Date()
        guard let settings else { return }
        if let idx = store.applications.firstIndex(where: { $0.id == updated.id }) {
            store.applications[idx] = updated
        }
        let documents = store.documents.filter { $0.applicationID == updated.id }
        try? WorkspaceSyncService.persistApplication(updated, documents: documents, settings: settings)
    }

    func experienceBinding(for id: UUID) -> Binding<ExperienceBullet> {
        Binding(
            get: { store.experiences.first { $0.id == id } ?? ExperienceBullet() },
            set: { updated in
                if let idx = store.experiences.firstIndex(where: { $0.id == updated.id }) {
                    store.experiences[idx] = updated
                }
            }
        )
    }
}
