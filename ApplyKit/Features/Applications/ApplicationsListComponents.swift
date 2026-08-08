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
    let hasResume: Bool
    let hasCoverLetter: Bool
    /// A tailoring run is in flight for this application — it may have been
    /// started here and left to finish while you moved on to another role.
    var isTailoring: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(application.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                // Top-right, clear of the metadata line: this is about the row as
                // a whole, not about any one field in it.
                if isTailoring {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                        .help("Resume Tailor is working on this application")
                }
            }

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
                if let fit = application.fitScore {
                    Text(fitText(fit))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(fitColor(fit))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(fitColor(fit).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .help(fitHelp(fit))
                }
                // Last real activity, not `updatedAt` — that gets re-stamped by every autosave,
                // so a stray keystroke would make a stalled application look fresh.
                if let changed = application.lastTimelineChange {
                    Text(changed.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help("Last timeline entry: \(changed.formatted(date: .abbreviated, time: .shortened))")
                }
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

    private var priorityColor: Color {
        switch application.priorityRaw {
        case ApplicationPriority.high.rawValue: .red
        case ApplicationPriority.low.rawValue: .secondary
        default: .orange
        }
    }

    /// Fit score from the Resume Tailor's brief, e.g. "8.5". A judgment aid, so
    /// the banding stays coarse.
    private func fitText(_ score: Double) -> String {
        score == score.rounded() ? String(Int(score)) : String(format: "%.1f", score)
    }

    private func fitColor(_ score: Double) -> Color {
        switch score {
        case 7...: .green
        case 5..<7: .orange
        default: .secondary
        }
    }

    private func fitHelp(_ score: Double) -> String {
        "Resume Tailor fit: \(fitText(score))/10"
    }
}

struct DeleteApplicationDialog: View {
    let application: JobApplication
    /// Bullets the Resume Tailor kept private to this application; they are
    /// deleted with it, so the count is called out before confirming.
    var applicationOnlyBulletCount: Int = 0
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

            if applicationOnlyBulletCount > 0 {
                Text("\(applicationOnlyBulletCount) application-only bullet\(applicationOnlyBulletCount == 1 ? "" : "s") belong\(applicationOnlyBulletCount == 1 ? "s" : "") to this role and will be deleted with it. Move one to the experience bank first to keep it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
