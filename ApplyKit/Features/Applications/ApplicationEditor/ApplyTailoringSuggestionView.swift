//
//  ApplyTailoringSuggestionView.swift
//  ApplyKit
//
//  The Resume Tailor sheet: build the tailored résumé from the Stage 1 brief (or
//  reconcile a pasted ChatGPT reply), then apply the resulting changes one-by-one
//  or all at once. Logic lives in ApplicationEditorTailoring.swift; Stage 1 and
//  its clarify loop live in ApplicationEditorTailorBrief.swift.
//

import SwiftUI

extension ApplicationEditorView {
    var tailoringSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            tailoringSheetHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tailoringBriefSummary
                    Divider()
                    tailoringBuildSection
                    if !tailoringChanges.isEmpty {
                        Divider()
                        tailoringChangesSection
                    }
                    Divider()
                    tailoringPasteSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 520, idealHeight: 680)
        .onAppear { restoreTailoringSession() }
    }

    private var tailoringSheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Resume Tailor")
                    .font(.headline)
                Text(application.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { showTailoringSheet = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Brief

    @ViewBuilder
    private var tailoringBriefSummary: some View {
        if let brief = tailoringBrief {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    if let fit = brief.fitScoreText {
                        Text(fit).font(.title3.weight(.semibold))
                    }
                    Text([brief.investmentTier.map { "\($0) tailoring" }, brief.investmentTime]
                        .compactMap { $0?.trimmed }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await runTailoringBrief() }
                    } label: {
                        Label(isRunningBrief ? "Analyzing…" : "Re-analyze Fit", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(isRunningBrief || aiBackend == nil)
                    .help("Judge the role again from scratch. Your answers are carried over to any question it asks again.")
                }
                if let story = brief.candidateStory?.trimmed, !story.isEmpty {
                    Text(story)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let unanswered = brief.unansweredQuestions.count
                if unanswered > 0 {
                    Label("\(unanswered) unanswered question\(unanswered == 1 ? "" : "s") in the Job Context panel — answering them first gives the build more to work with.",
                          systemImage: "questionmark.circle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No tailoring brief yet")
                    .font(.subheadline.weight(.semibold))
                Text("Run **Analyze Fit** in the Job Context panel first, or paste a reply from ChatGPT below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await runTailoringBrief() }
                } label: {
                    Label(isRunningBrief ? "Analyzing…" : "Analyze Fit", systemImage: "scope")
                }
                .disabled(isRunningBrief || aiBackend == nil || application.jobDescription.trimmed.isEmpty)
            }
        }
    }

    // MARK: - Build

    private var tailoringBuildSection: some View {
        HStack(spacing: 10) {
            Button {
                Task { await buildTailoringPlan() }
            } label: {
                if isReconcilingTailoring {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Working…")
                    }
                } else {
                    Label(tailoringChanges.isEmpty ? "Build from Brief" : "Rebuild from Brief",
                          systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isReconcilingTailoring || tailoringBrief == nil || aiBackend == nil)

            if aiBackend == nil {
                Text("Configure an AI CLI in Settings → Tools")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Changes

    private var tailoringChangesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let pending = tailoringChanges.filter { !$0.isBlocked && !$0.applied && !$0.isInformational }.count
            HStack {
                Text("Proposed changes")
                    .font(.headline)
                Spacer()
                Button {
                    applyAllTailoring()
                } label: {
                    Label("Apply All", systemImage: "checkmark.circle")
                }
                .disabled(pending == 0)
            }

            // Grouped, because the two runs mean different things: one tailors
            // to the role, the other fixes what the rendered file showed.
            ForEach(changeGroups, id: \.heading) { group in
                if changeGroups.count > 1 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.heading)
                            .font(.subheadline.weight(.semibold))
                        Text(group.caption)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                ForEach(group.changes) { change in
                    TailoringChangeRow(change: change) {
                        applyTailoringChange(change)
                    } onApplyAlternate: {
                    // A new bullet is applied one of two ways; the row's second
                    // button keeps it out of the shared bank.
                        guard case .newBullet(let bullet, _) = change.action else { return }
                        var scoped = change
                        scoped.action = .newBullet(bullet, toBank: false)
                        applyTailoringChange(scoped)
                    }
                }
            }
        }
    }

    /// Changes split by which run proposed them, build first.
    private var changeGroups: [(heading: String, caption: String, changes: [TailoringChange])] {
        let build = tailoringChanges.filter { $0.source == .build }
        let checks = tailoringChanges.filter { $0.source != .build }
        var groups: [(heading: String, caption: String, changes: [TailoringChange])] = []
        if !build.isEmpty {
            groups.append((TailoringChange.Source.build.heading,
                           TailoringChange.Source.build.caption, build))
        }
        for source in Set(checks.map(\.source)).sorted(by: { $0.heading < $1.heading }) {
            groups.append((source.heading, source.caption, checks.filter { $0.source == source }))
        }
        return groups
    }

    // MARK: - Paste fallback

    private var tailoringPasteSection: some View {
        DisclosureGroup("Paste a reply from ChatGPT instead") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        copyTailoringContext()
                    } label: {
                        Label("Copy context for ChatGPT", systemImage: "doc.on.clipboard")
                    }
                    Spacer()
                    if !tailoringChanges.isEmpty || !tailoringPastedText.isEmpty {
                        Button(role: .destructive) {
                            clearTailoringSession()
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                    }
                }

                Text("Paste the reply below to reconcile it into the same reviewable changes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextEditor(text: $tailoringPastedText)
                    .font(.body.monospaced())
                    .frame(minHeight: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    )

                Button {
                    Task { await reconcileTailoring(pastedReply: tailoringPastedText) }
                } label: {
                    Label(tailoringChanges.isEmpty ? "Reconcile" : "Re-reconcile", systemImage: "sparkles")
                }
                .disabled(isReconcilingTailoring || tailoringPastedText.trimmed.isEmpty || aiBackend == nil)
            }
            .padding(.top, 10)
        }
        .font(.subheadline)
    }
}

private struct TailoringChangeRow: View {
    let change: TailoringChange
    let onApply: () -> Void
    var onApplyAlternate: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .imageScale(.small)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.title).font(.subheadline.weight(.semibold))
                    if !change.detail.isEmpty {
                        Text(change.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                actionControl
            }

            if let blocked = change.blockedReason {
                Text(blocked)
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                diffView
                if let signal = change.signal {
                    Text("Signal improved: \(signal)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let confirmation = change.confirmationNeeded {
                    Label("Confirm before submitting: \(confirmation)", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                rationaleTable
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        .opacity(change.applied ? 0.6 : 1)
    }

    private var iconName: String {
        if change.isBlocked { return "exclamationmark.triangle.fill" }
        return change.isInformational ? "flag.checkered" : "circle"
    }

    private var iconColor: Color {
        change.isBlocked ? .orange : .secondary
    }

    @ViewBuilder private var actionControl: some View {
        if change.isBlocked || change.isInformational {
            EmptyView()
        } else if change.applied {
            Label("Applied", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        } else if change.newBullet != nil, let onApplyAlternate {
            HStack(spacing: 6) {
                Button("Add to Bank", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("This Application Only", action: onApplyAlternate)
                    .controlSize(.small)
                    .help("Put it on this résumé without filing it in the experience bank")
            }
        } else {
            Button("Apply", action: onApply)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    @ViewBuilder private var diffView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let before = change.before, !before.trimmed.isEmpty {
                labeledText("Current", before, color: .secondary)
            }
            if let after = change.after, !after.trimmed.isEmpty {
                labeledText(change.before == nil ? "New" : "Tailored", after, color: .primary)
            }
        }
    }

    /// "Why this summary": each phrase traced to its evidence and the need it serves.
    @ViewBuilder private var rationaleTable: some View {
        if !change.rationale.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHY THIS SUMMARY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(Array(change.rationale.enumerated()), id: \.offset) { _, claim in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(claim.phrase)
                            .font(.callout.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        let support = [claim.evidence?.trimmed, claim.signal?.trimmed, claim.whyItEarnsSpace?.trimmed]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                        if !support.isEmpty {
                            Text(support.joined(separator: " · "))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func labeledText(_ label: String, _ text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
