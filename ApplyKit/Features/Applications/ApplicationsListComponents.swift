//
//  ApplicationsListComponents.swift
//  ApplyKit
//

import SwiftUI

enum ApplicationListScope: String, CaseIterable, Identifiable {
    case active = "Active"
    case archived = "Archived"
    case all = "All"

    var id: String { rawValue }
}

struct ApplicationRow: View {
    let application: JobApplication
    let documents: [GeneratedDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(application.displayTitle)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 8) {
                if application.isArchived {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.secondary)
                        .help("Archived")
                }
                Text(application.statusRaw)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(application.priorityRaw)
                    .font(.caption)
                    .foregroundStyle(priorityColor)
                Spacer()
                if hasResume {
                    Image(systemName: "doc.text")
                        .help("Resume exists")
                }
                if hasCoverLetter {
                    Image(systemName: "envelope")
                        .help("Cover letter exists")
                }
                if !application.jobURL.trimmed.isEmpty {
                    Image(systemName: "link")
                        .help("Job URL saved")
                }
            }

            if !application.nextAction.trimmed.isEmpty {
                Text(application.nextAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var hasResume: Bool {
        documents.contains { $0.kindRaw == GeneratedDocumentKind.resume.rawValue }
    }

    private var hasCoverLetter: Bool {
        documents.contains { $0.kindRaw == GeneratedDocumentKind.coverLetter.rawValue }
    }

    private var priorityColor: Color {
        switch application.priorityRaw {
        case ApplicationPriority.high.rawValue: .red
        case ApplicationPriority.low.rawValue: .secondary
        default: .orange
        }
    }
}

struct DeleteApplicationDialog: View {
    let application: JobApplication
    @Binding var shouldDeleteSourceFiles: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Delete this role?")
                        .font(.headline)
                    Text(application.displayTitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Toggle("Also delete source files", isOn: $shouldDeleteSourceFiles)

            Text(sourceFileMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Delete", role: .destructive) {
                    onDelete()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private var sourceFileMessage: String {
        if shouldDeleteSourceFiles {
            "This removes the role from the local cache and deletes its managed workspace folder, including application.yml, job-description.md, notes.md, generated documents, prompts, and AI responses."
        } else {
            "This removes the role from the local cache. Managed source files in the selected workspace are left untouched."
        }
    }
}
