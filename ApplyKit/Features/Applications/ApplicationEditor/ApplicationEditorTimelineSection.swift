//
//  ApplicationEditorTimelineSection.swift
//  ApplyKit
//

import SwiftUI

extension ApplicationEditorView {
    var timelineSection: some View {
        ApplicationTimelineSection(application: $application)
    }
}

/// Dated history of an application: automatic status/lifecycle entries plus hand-written notes.
///
/// A standalone view rather than another extension on the editor because it owns editing state,
/// and extensions can't add stored properties.
struct ApplicationTimelineSection: View {
    @Binding var application: JobApplication
    @State private var editingEventID: UUID?

    var body: some View {
        DetailPanel("Timeline", collapseKey: "applicationEditor.collapsed.timeline") {
            Button(action: addEntry) {
                Label("Add Entry", systemImage: "plus")
            }
            .controlSize(.small)
            .help("Record something that happened — a call, an email, a follow-up")
        } content: {
            if application.timeline.isEmpty {
                Text("No timeline entries yet.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(application.timeline.enumerated()), id: \.element.id) { index, event in
                        ApplicationTimelineRow(
                            event: binding(for: event),
                            isLast: index == application.timeline.count - 1,
                            isEditing: editingEventID == event.id,
                            onToggleEdit: {
                                editingEventID = editingEventID == event.id ? nil : event.id
                            },
                            onDelete: {
                                editingEventID = nil
                                application.removeEvent(id: event.id)
                            }
                        )
                    }
                }
            }
        }
    }

    /// Reads through to the live entry so an edit isn't lost when the list reorders.
    private func binding(for event: ApplicationEvent) -> Binding<ApplicationEvent> {
        Binding(
            get: { application.timeline.first { $0.id == event.id } ?? event },
            set: { application.updateEvent($0) }
        )
    }

    private func addEntry() {
        let event = ApplicationEvent(kind: .note)
        application.recordEvent(event)
        editingEventID = event.id
    }
}

private struct ApplicationTimelineRow: View {
    @Binding var event: ApplicationEvent
    let isLast: Bool
    let isEditing: Bool
    let onToggleEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            rail
            VStack(alignment: .leading, spacing: 6) {
                summary
                if isEditing {
                    editor
                } else if !event.note.trimmed.isEmpty {
                    Text(event.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
    }

    /// Dot plus connector line. Status changes read as milestones (filled); everything else
    /// is a lighter marker.
    private var rail: some View {
        VStack(spacing: 0) {
            Group {
                if event.isStatusChange {
                    Circle().fill(Color.accentColor)
                } else {
                    Circle()
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1.5)
                        .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                }
            }
            .frame(width: 9, height: 9)
            .padding(.top, 5)

            if !isLast {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.6))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 9)
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: event.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(event.displayTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            if let detail = event.transitionDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(event.date.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(dateHelp)

            Button(action: onToggleEdit) {
                Image(systemName: isEditing ? "checkmark" : "pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isEditing ? "Done" : "Edit this entry")
        }
    }

    /// Reconstructed dates carry their caveat in the tooltip rather than as a badge on the row —
    /// on an application imported before timelines existed, every entry would wear one.
    private var dateHelp: String {
        let absolute = event.date.formatted(date: .abbreviated, time: .shortened)
        return event.isInferred
            ? "\(absolute) — approximate, reconstructed from this application's saved dates"
            : absolute
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if event.kind == .note {
                TextField("What happened", text: $event.title)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Details (optional)", text: $event.note)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { event.date },
                        // Correcting the date is the point of editing an inferred entry, so
                        // the approximate flag comes off once a real one is supplied.
                        set: { event.date = $0; event.isInferred = false }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .controlSize(.small)

                Spacer(minLength: 0)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
