//
//  ApplicationEditorMasterResume.swift
//  ApplyKit
//
//  Apply a master resume preset to this application (one-time copy of its
//  resume-content fields), and the reverse: snapshot this application's resume
//  setup as a new master resume.
//

import AppKit
import SwiftUI

extension ApplicationEditorView {
    var masterResumePanel: some View {
        DetailPanel("Master Resume") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if !store.masterResumes.isEmpty {
                        Menu {
                            ForEach(store.masterResumes) { preset in
                                Button(preset.displayTitle) {
                                    masterResumePendingApply = preset
                                }
                            }
                        } label: {
                            Label("Apply Master Resume", systemImage: "square.and.arrow.down.on.square")
                        }
                        .fixedSize()
                        .disabled(activityMonitor.state == .running)
                        .help("Replace this application's resume content with a master resume preset")
                    }

                    Button {
                        saveAsMasterResumeName = application.jobTitle.trimmed
                        showSaveAsMasterResume = true
                    } label: {
                        Label("Save as Master Resume", systemImage: "square.and.arrow.up.on.square")
                    }
                    .help("Snapshot this application's resume setup as a reusable master resume")

                    Spacer()
                }

                Text("Applying a master resume replaces this application's selections, wording, ordering, skills, summary, and role overrides with the preset. Saving does the reverse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "Apply this master resume?",
            isPresented: Binding(
                get: { masterResumePendingApply != nil },
                set: { if !$0 { masterResumePendingApply = nil } }
            ),
            presenting: masterResumePendingApply
        ) { preset in
            Button("Apply \(preset.displayTitle)", role: .destructive) {
                applyMasterResume(preset)
            }
            Button("Cancel", role: .cancel) {}
        } message: { preset in
            Text("This replaces the application's experience selections, bullet wording and order, section order, skills, summary, and role overrides with \"\(preset.displayTitle)\". This cannot be undone.")
        }
        .alert("Save as Master Resume", isPresented: $showSaveAsMasterResume) {
            TextField("Name", text: $saveAsMasterResumeName)
            Button("Save") {
                saveAsMasterResume(named: saveAsMasterResumeName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves this application's experience selections, wording, ordering, skills, summary, and role overrides as a reusable preset.")
        }
    }

    func applyMasterResume(_ preset: MasterResume) {
        application.copyResumeContent(from: preset)
        persistApplicationChanges()
        masterResumePendingApply = nil
        activityMonitor.succeed("Applied \"\(preset.displayTitle)\" to this application.")
    }

    func saveAsMasterResume(named name: String) {
        var preset = MasterResume(name: name.trimmed.isEmpty ? "New Master Resume" : name.trimmed)
        preset.copyResumeContent(from: application)
        store.masterResumes.append(preset)
        store.masterResumes.sort { $0.name < $1.name }
        if let settings {
            try? WorkspaceSyncService.persistMasterResume(preset, settings: settings)
        }
        activityMonitor.succeed("Saved master resume \"\(preset.displayTitle)\".")
    }
}
