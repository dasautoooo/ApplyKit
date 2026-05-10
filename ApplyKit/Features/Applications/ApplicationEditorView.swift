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
    @State var generatingDocumentKind: GeneratedDocumentKind?

    var documents: [GeneratedDocument] { store.documents.filter { $0.applicationID == application.id } }
    var experiences: [ExperienceBullet] { store.experiences }
    var employments: [Employment] { store.employments }
    var applications: [JobApplication] { store.applications }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                DetailPanel("Role Details") {
                    roleForm
                }
                documentActions
                HStack(alignment: .top, spacing: 16) {
                    selectedExperienceSection
                    selectedProjectSection
                }
                selectedBulletWordingSection
                jobDescriptionSection
                jdAnalysisSection
                notesSection
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1160, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(application.displayTitle)
        .onChange(of: applicationPersistenceFingerprint) { _, _ in
            persistApplicationChanges()
        }
    }
}
