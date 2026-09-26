//
//  ApplicationEditorInterviewSection.swift
//  ApplyKit
//

import AppKit
import SwiftUI

extension ApplicationEditorView {
    var interviewProcessSection: some View {
        InterviewProcessSection(application: $application)
    }
}

/// The recruiter screen and interview rounds of one application, one row per step. Each row
/// reads at a glance — result, when, format, prep progress — and folds open to edit the step.
struct InterviewProcessSection: View {
    @Binding var application: JobApplication
    @State private var expandedStepIDs: Set<UUID> = []
    @AppStorage("interviewStep.tab") private var stepTab: InterviewStepTab = .logistics

    var body: some View {
        DetailPanel("Interview Process", collapseKey: "applicationEditor.collapsed.interviews") {
            addMenu
        } content: {
            let steps = application.interviewSteps
            if steps.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        if index > 0 { Divider() }
                        stepRow(step)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                }
            }
        }
        // Steps can appear from outside this section — picking Recruiter Screen or
        // Interviewing in the status picker adds one — and a new step opens for its date.
        .onChange(of: application.interviewSteps.map(\.id)) { old, new in
            let added = Set(new).subtracting(old)
            guard !added.isEmpty else { return }
            expandedStepIDs.formUnion(added)
            // A new step needs a time first, and that's on Logistics.
            stepTab = .logistics
        }
    }

    // MARK: - Rows

    private func stepRow(_ step: ApplicationEvent) -> some View {
        let isExpanded = expandedStepIDs.contains(step.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)

                Image(systemName: step.interviewResult.systemImage)
                    .foregroundStyle(step.interviewResult.tint)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(application.stepTitle(for: step))
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(glanceLine(for: step))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let url = step.interview.meetingURL, step.hasScheduledTime, !isSettled(step) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Join", systemImage: "video")
                    }
                    .controlSize(.small)
                    .help(url.absoluteString)
                }

                InterviewResultMenu(step: binding(for: step))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture { toggle(step) }
            .help(isExpanded ? "Collapse" : "Expand to edit")
            .contextMenu {
                Button(isExpanded ? "Collapse" : "Edit") { toggle(step) }
                Divider()
                Button("Delete Step", role: .destructive) { delete(step) }
            }

            if offersRejection(for: step) {
                HStack(spacing: 10) {
                    Text("Didn't advance — set the status to Rejected?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Mark Rejected") {
                        application.setStatus(rawValue: ApplicationStatus.rejected.rawValue)
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 60)
                .padding(.bottom, 9)
            }

            if isExpanded {
                InterviewStepEditor(step: binding(for: step), onDelete: { delete(step) })
                    // Lines the editor up under the title, past the chevron and result icon.
                    .padding(.leading, 60)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                    .padding(.top, 2)
            }
        }
    }

    /// "Sep 27 at 22:36 · in 2 days · 1 hr · Video · Prep 1/3 · ★4", or "Time not set · …" for a
    /// step still being arranged — whose date is only when it was added, so it isn't shown.
    private func glanceLine(for step: ApplicationEvent) -> String {
        var parts = [step.hasScheduledTime ? step.whenText : "Time not set"]
        if let minutes = step.interview.durationMinutes {
            parts.append(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        }
        if let format = step.interview.format { parts.append(format.rawValue) }
        let prep = step.interview.prepProgress
        if prep.total > 0 { parts.append("Prep \(prep.done)/\(prep.total)") }
        if let rating = step.interview.selfRating { parts.append("★\(rating)") }
        return parts.joined(separator: " · ")
    }

    /// On the latest step that didn't advance, while the application is still open.
    private func offersRejection(for step: ApplicationEvent) -> Bool {
        guard step.interviewResult == .didNotAdvance,
              let status = ApplicationStatus(rawValue: application.statusRaw), !status.isClosed else { return false }
        return application.interviewSteps.last { $0.interviewResult == .didNotAdvance }?.id == step.id
    }

    private func isSettled(_ step: ApplicationEvent) -> Bool {
        [.passed, .didNotAdvance].contains(step.interviewResult)
    }

    // MARK: - Adding and removing

    private var addMenu: some View {
        Menu {
            Button {
                add(.recruiterScreen)
            } label: {
                Label("Recruiter Screen", systemImage: "phone")
            }
            Button {
                add(.coding)
            } label: {
                Label("Interview Round", systemImage: "person.2")
            }
        } label: {
            Label("Add Step", systemImage: "plus")
        }
        .menuStyle(.button)
        .fixedSize()
        .controlSize(.small)
        .help("Add a recruiter screen or interview round")
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Text("No interviews yet.")
                .foregroundStyle(.secondary)
            Button("Add Recruiter Screen") { add(.recruiterScreen) }
            Button("Add Interview Round") { add(.coding) }
        }
        .controlSize(.small)
    }

    private func toggle(_ step: ApplicationEvent) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expandedStepIDs.contains(step.id) {
                expandedStepIDs.remove(step.id)
            } else {
                expandedStepIDs.insert(step.id)
            }
        }
    }

    /// Reads through to the live entry, so an edit that re-sorts the timeline isn't lost.
    private func binding(for step: ApplicationEvent) -> Binding<ApplicationEvent> {
        Binding(
            get: { application.timeline.first { $0.id == step.id } ?? step },
            set: { application.updateEvent($0) }
        )
    }

    private func add(_ type: InterviewType) {
        let step = ApplicationEvent.newInterviewStep(type, formatLike: application.interviewRounds.last)
        application.recordInterviewStep(step)
        // Opens straight into the new step, since it needs a date and details either way.
        expandedStepIDs.insert(step.id)
    }

    private func delete(_ step: ApplicationEvent) {
        expandedStepIDs.remove(step.id)
        application.removeEvent(id: step.id)
    }
}
