//
//  InterviewStepViews.swift
//  ApplyKit
//

import AppKit
import SwiftUI

/// The foldable editor under an interview step: logistics, prep, and debrief in tabs. The
/// step's title, time, and result live on the row above it, so they aren't repeated here.
struct InterviewStepEditor: View {
    @Binding var step: ApplicationEvent
    let onDelete: () -> Void

    @AppStorage("interviewStep.tab") private var tab: InterviewStepTab = .logistics
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Section", selection: $tab) {
                ForEach(InterviewStepTab.allCases) { tab in
                    Text(tab.label(for: step.interview)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            switch tab {
            case .logistics: InterviewLogisticsForm(step: $step)
            case .prep: InterviewPrepForm(step: $step)
            case .debrief: InterviewDebriefForm(step: $step)
            }

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete Step", systemImage: "trash")
            }
            .controlSize(.small)
        }
        .confirmationDialog("Delete this step?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Its prep and debrief notes are deleted with it.")
        }
    }
}

enum InterviewStepTab: String, CaseIterable, Identifiable {
    case logistics, prep, debrief
    var id: String { rawValue }

    func label(for details: InterviewDetails) -> String {
        switch self {
        case .logistics: return "Logistics"
        case .prep:
            let progress = details.prepProgress
            return progress.total == 0 ? "Prep" : "Prep \(progress.done)/\(progress.total)"
        case .debrief: return "Debrief"
        }
    }
}

// MARK: - Logistics

private struct InterviewLogisticsForm: View {
    @Binding var step: ApplicationEvent

    private static let durations = [15, 30, 45, 60, 90, 120, 180, 240, 300, 360, 480]

    var body: some View {
        Form {
            InterviewTypePicker(step: $step)

            if step.hasScheduledTime {
                DatePicker("When", selection: $step.date, displayedComponents: [.date, .hourAndMinute])
            } else {
                LabeledContent("When") {
                    HStack(spacing: 10) {
                        Text("Not scheduled yet")
                            .foregroundStyle(.secondary)
                        Button("Set Time") {
                            step.schedule(at: ApplicationEvent.suggestedInterviewTime())
                        }
                        .controlSize(.small)
                        .help("Pick the agreed time; the step moves to Scheduled")
                    }
                }
            }

            Picker("Duration", selection: $step.interview.durationMinutes) {
                Text("—").tag(Int?.none)
                ForEach(durationOptions, id: \.self) { minutes in
                    Text(Self.durationText(minutes)).tag(Int?.some(minutes))
                }
            }

            Picker("Format", selection: $step.interview.formatRaw) {
                ForEach(InterviewFormat.allCases) { format in
                    Label(format.rawValue, systemImage: format.systemImage).tag(format.rawValue)
                }
            }
            .pickerStyle(.segmented)

            TextField("Link or place", text: $step.interview.location,
                      prompt: Text("Meeting link or address"))

            TextField("Interviewers", text: $step.interview.interviewers,
                      prompt: Text("Names and roles"))

            TextField("Label", text: $step.title, prompt: Text("Optional, e.g. with the iOS team"))
        }
        .formStyle(.columns)
    }

    /// The presets, plus a stored value that isn't one of them so it stays selectable.
    private var durationOptions: [Int] {
        guard let current = step.interview.durationMinutes, !Self.durations.contains(current) else {
            return Self.durations
        }
        return (Self.durations + [current]).sorted()
    }

    static func durationText(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

// MARK: - Prep

private struct InterviewPrepForm: View {
    @Binding var step: ApplicationEvent
    @State private var newItem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach($step.interview.prepChecklist) { $item in
                    HStack(spacing: 8) {
                        Toggle("Done", isOn: $item.isDone)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        TextField("Item", text: $item.text)
                            .textFieldStyle(.plain)
                            .strikethrough(item.isDone)
                            .foregroundStyle(item.isDone ? .secondary : .primary)
                        Button {
                            step.interview.prepChecklist.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tertiary)
                        .help("Remove")
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                    TextField("Add a prep item and press Return", text: $newItem)
                        .textFieldStyle(.plain)
                        .onSubmit(addItem)
                }

                let suggestions = step.interviewType.prepSuggestions
                    .filter { suggestion in !step.interview.prepChecklist.contains { $0.text == suggestion } }
                if !suggestions.isEmpty {
                    Button {
                        step.interview.prepChecklist += suggestions.map { InterviewChecklistItem(text: $0) }
                    } label: {
                        Label("Add suggested items for \(step.interviewType.rawValue.lowercased())",
                              systemImage: "sparkles")
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.top, 2)
                }
            }

            InterviewTextArea(title: "Prep notes", text: $step.interview.prepNotes,
                              prompt: "What to review, stories to tell, questions to ask them")
        }
    }

    private func addItem() {
        let text = newItem.trimmed
        guard !text.isEmpty else { return }
        step.interview.prepChecklist.append(InterviewChecklistItem(text: text))
        newItem = ""
    }
}

// MARK: - Debrief

private struct InterviewDebriefForm: View {
    @Binding var step: ApplicationEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("How it went")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                RatingControl(rating: $step.interview.selfRating)
            }

            InterviewTextArea(title: "Questions they asked", text: $step.interview.questionsAsked,
                              prompt: "Worth keeping for the next round, and the next company")

            InterviewTextArea(title: "Notes", text: $step.note,
                              prompt: "How it went, what to follow up on, what they said about next steps")
        }
    }
}

/// Five stars; clicking the current rating clears it.
private struct RatingControl: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = rating == value ? nil : value
                } label: {
                    Image(systemName: value <= (rating ?? 0) ? "star.fill" : "star")
                        .foregroundStyle(value <= (rating ?? 0) ? Color.orange : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(rating == value ? "Clear rating" : "\(value) of 5")
            }
        }
    }
}

private struct InterviewTextArea: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField(title, text: $text, prompt: Text(prompt), axis: .vertical)
                .lineLimit(3...12)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
    }
}

// MARK: - Shared pieces

/// The result as a colored pill that opens a menu to change it — no editor needed.
struct InterviewResultMenu: View {
    @Binding var step: ApplicationEvent

    var body: some View {
        Menu {
            Picker("Result", selection: $step.interviewResultRaw) {
                ForEach(InterviewResult.allCases) { result in
                    Label(result.rawValue, systemImage: result.systemImage).tag(result.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(step.interviewResult.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(step.interviewResult.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(step.interviewResult.tint.opacity(0.12), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change the result")
    }
}

/// A round's type. The recruiter screen is its own kind of step rather than a round type, so
/// it shows as a fixed label instead. Keeps a value from a newer build selectable instead of
/// blanking it.
struct InterviewTypePicker: View {
    @Binding var step: ApplicationEvent

    var body: some View {
        if step.isRecruiterScreenStep {
            LabeledContent("Type", value: InterviewType.recruiterScreen.rawValue)
        } else {
            Picker("Type", selection: $step.interviewTypeRaw) {
                ForEach(InterviewType.roundTypes) { type in
                    Text(type.rawValue).tag(type.rawValue)
                }
                if InterviewType(rawValue: step.interviewTypeRaw) == nil {
                    Text(step.interviewTypeRaw).tag(step.interviewTypeRaw)
                }
            }
        }
    }
}

struct InterviewResultPicker: View {
    @Binding var step: ApplicationEvent

    var body: some View {
        Picker("Result", selection: $step.interviewResultRaw) {
            ForEach(InterviewResult.allCases) { result in
                Text(result.rawValue).tag(result.rawValue)
            }
            if InterviewResult(rawValue: step.interviewResultRaw) == nil {
                Text(step.interviewResultRaw).tag(step.interviewResultRaw)
            }
        }
    }
}

extension ApplicationEvent {
    /// Date and time, with how far off it is: "Oct 14, 2:00 PM · in 3 days".
    var whenText: String {
        let absolute = date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        let relative = date.formatted(.relative(presentation: .named))
        return "\(absolute) · \(relative)"
    }
}

extension InterviewType {
    /// Starter prep items, kept short on purpose; anything more specific belongs to the user.
    var prepSuggestions: [String] {
        switch self {
        case .recruiterScreen:
            ["Research the company and role", "Prepare a one-minute intro", "Know your salary expectations",
             "Questions about the team, process, and timeline"]
        case .onlineAssessment, .phoneScreen, .coding:
            ["Review common patterns and data structures", "Practice a few problems in your interview language",
             "Check your setup: editor, mic, camera"]
        case .systemDesign:
            ["Review a design framework: requirements, API, data, scale", "Walk through one relevant design end to end",
             "Prepare real trade-offs you've made"]
        case .behavioral, .hiringManager, .teamMatch:
            ["Prepare STAR stories: impact, conflict, failure, leadership", "Map your stories to the job description",
             "Questions for them about the team and role"]
        case .takeHome:
            ["Confirm the scope and time limit", "Plan tests and a README", "Leave time to review before submitting"]
        case .onsite:
            ["Confirm the schedule and interviewers", "Review stories and technical topics",
             "Sort out travel or setup and breaks"]
        case .other:
            []
        }
    }
}

extension InterviewResult {
    var tint: Color {
        switch self {
        case .scheduling: .orange
        case .passed: .green
        case .didNotAdvance: .red
        case .scheduled, .awaiting: .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .scheduling: "calendar.badge.clock"
        case .scheduled: "calendar"
        case .awaiting: "hourglass"
        case .passed: "checkmark.circle.fill"
        case .didNotAdvance: "xmark.circle.fill"
        }
    }
}
