//
//  MasterResumesWorkspaceView.swift
//  ApplyKit
//

import AppKit
import SwiftUI

struct MasterResumesWorkspaceView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var selectedMasterResumeID: UUID?
    @State private var masterResumePendingDeletion: MasterResume?
    @State private var sidebarWidth: CGFloat = 300

    var body: some View {
        StableSidebarSplit(
            sidebarWidth: $sidebarWidth,
            minWidth: 260,
            maxWidth: 400
        ) {
            VStack(spacing: 0) {
                List(selection: $selectedMasterResumeID) {
                    ForEach(store.masterResumes) { masterResume in
                        MasterResumeRow(masterResume: masterResume)
                            .tag(masterResume.id)
                            .contextMenu {
                                Button {
                                    duplicate(masterResume)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    masterResumePendingDeletion = masterResume
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        } detail: {
            if let selectedMasterResume {
                MasterResumeEditorView(masterResume: selectedMasterResume, settings: settings)
                    .id(selectedMasterResume.id)
            } else {
                ContentUnavailableView(
                    "Select a master resume",
                    systemImage: "doc.on.doc",
                    description: Text("Master resumes are reusable presets for one role direction. Build one here, then apply it to applications.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: add) {
                    Label("New Master Resume", systemImage: "plus")
                }
            }
        }
        .confirmationDialog(
            "Delete this master resume?",
            isPresented: Binding(
                get: { masterResumePendingDeletion != nil },
                set: { if !$0 { masterResumePendingDeletion = nil } }
            ),
            presenting: masterResumePendingDeletion
        ) { masterResume in
            Button("Delete", role: .destructive) {
                delete(masterResume, deletingSourceFile: false)
            }
            Button("Delete and Source File", role: .destructive) {
                delete(masterResume, deletingSourceFile: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: { masterResume in
            Text("\"\(masterResume.displayTitle)\" will be removed. Applications that already applied it keep their content. \"Delete\" keeps the YAML file in the workspace; \"Delete and Source File\" removes it too.")
        }
    }

    private var selectedMasterResume: MasterResume? {
        guard let selectedMasterResumeID else { return nil }
        return store.masterResumes.first { $0.id == selectedMasterResumeID }
    }

    private func add() {
        let masterResume = MasterResume(name: "New Master Resume")
        store.masterResumes.append(masterResume)
        store.masterResumes.sort { $0.name < $1.name }
        try? WorkspaceSyncService.persistMasterResume(masterResume, settings: settings)
        selectedMasterResumeID = masterResume.id
    }

    private func duplicate(_ masterResume: MasterResume) {
        var copy = masterResume
        copy.id = UUID()
        copy.name = masterResume.name.trimmed.isEmpty ? "Master Resume (Copy)" : "\(masterResume.name) (Copy)"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        store.masterResumes.append(copy)
        store.masterResumes.sort { $0.name < $1.name }
        try? WorkspaceSyncService.persistMasterResume(copy, settings: settings)
        selectedMasterResumeID = copy.id
    }

    private func delete(_ masterResume: MasterResume, deletingSourceFile: Bool) {
        if deletingSourceFile {
            WorkspaceSyncService.deleteMasterResumeFile(masterResume, settings: settings)
        }
        store.masterResumes.removeAll { $0.id == masterResume.id }
        if selectedMasterResumeID == masterResume.id {
            selectedMasterResumeID = nil
        }
        masterResumePendingDeletion = nil
    }
}

private struct MasterResumeRow: View {
    let masterResume: MasterResume

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(masterResume.displayTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        let bulletCount = masterResume.selectedExperienceIDs.count + masterResume.selectedProjectIDs.count
        let bullets = "\(bulletCount) bullet\(bulletCount == 1 ? "" : "s")"
        let updated = masterResume.updatedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(bullets) · updated \(updated)"
    }
}
