//
//  ApplyTailoringSuggestionView.swift
//  ApplyKit
//
//  The Resume Tailor sheet. Two ways in: an external chat (copy the context,
//  paste back a Resume Edit Plan, review, optionally have the chat check the
//  PDF) laid out as numbered steps, or the in-app AI building from the Stage 1
//  brief. Both end in the same reviewable change list. Logic lives in
//  ApplicationEditorTailoring.swift; Stage 1 and its clarify loop live in
//  ApplicationEditorTailorBrief.swift.
//

import AppKit
import SwiftUI

/// Where the Resume Tailor sheet's edits come from. Remembered across
/// applications, since it's a habit rather than a per-role choice.
enum TailoringSourceMode: String, CaseIterable, Identifiable {
    case externalChat
    case inApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .externalChat: "External Chat"
        case .inApp: "In-App AI"
        }
    }
}

extension ApplicationEditorView {
    var tailoringSource: TailoringSourceMode {
        TailoringSourceMode(rawValue: tailoringSourceRaw) ?? .externalChat
    }

    var tailoringSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            tailoringSheetHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tailoringSource {
                    case .externalChat:
                        externalChatFlow
                    case .inApp:
                        tailoringBriefSummary
                        Divider()
                        tailoringBuildSection
                        if !tailoringChanges.isEmpty {
                            Divider()
                            tailoringChangesSection(showsHeading: true)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 520, idealHeight: 720)
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
            Picker("Source", selection: $tailoringSourceRaw) {
                ForEach(TailoringSourceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Tailor in ChatGPT, Claude or another chat and paste the plan back, or let the in-app AI build it from the brief")
            Spacer()
            Button("Done") { showTailoringSheet = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - External chat

    /// The step the external flow is waiting on — its main button is the
    /// prominent one.
    private var externalStep: Int {
        guard tailoringPlan != nil else { return tailoringContextCopiedAt == nil ? 1 : 2 }
        return tailoringProgress.pendingChanges > 0 ? 3 : 4
    }

    private func stepState(_ number: Int, done: Bool) -> TailorStepStatus {
        if done, number != externalStep { return .done }
        return number == externalStep ? .current : .upcoming
    }

    private var externalChatFlow: some View {
        VStack(alignment: .leading, spacing: 22) {
            TailorStep(number: 1, title: "Send the context to your chat",
                       status: stepState(1, done: tailoringContextCopiedAt != nil || tailoringPlan != nil)) {
                sendContextStep
            }
            TailorStep(number: 2, title: "Paste back the edit plan",
                       status: stepState(2, done: tailoringPlan != nil)) {
                pastePlanStep
            }
            TailorStep(number: 3, title: "Review and apply",
                       status: stepState(3, done: tailoringPlan != nil && tailoringProgress.pendingChanges == 0)) {
                if tailoringChanges.isEmpty {
                    Text("The plan's changes appear here, each with Apply and Revert.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    tailoringChangesSection(showsHeading: false)
                }
            }
            TailorStep(number: 4, title: "Check the rendered PDF (optional)",
                       status: stepState(4, done: tailoringProgress.review.map { $0.isClean && !tailoringProgress.isReviewStale } ?? false)) {
                reviewPDFStep
            }
        }
    }

    private var sendContextStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Copies the job description, your résumé with bullet ids, and the edit plan format the reply must follow. Paste it into a new chat.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    copyTailoringContext()
                } label: {
                    Label(tailoringContextCopiedAt == nil ? "Copy Context" : "Copy Again", systemImage: "doc.on.clipboard")
                }
                .prominent(externalStep == 1)

                Menu {
                    ForEach(ExternalChat.allCases) { chat in
                        Button(chat.title) { NSWorkspace.shared.open(chat.url) }
                    }
                } label: {
                    Label("Open ChatGPT", systemImage: "arrow.up.forward.app")
                } primaryAction: {
                    NSWorkspace.shared.open(ExternalChat.chatGPT.url)
                }
                .menuStyle(.button)
                .fixedSize()

                if let copiedAt = tailoringContextCopiedAt {
                    Label {
                        Text("Copied ") + Text(copiedAt, style: .relative) + Text(" ago")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var pastePlanStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copy the chat's whole reply and paste it here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    pasteAndImportTailoringPlan()
                } label: {
                    Label(tailoringPlan == nil ? "Paste Reply & Import" : "Paste New Reply & Import",
                          systemImage: "square.and.arrow.down.on.square")
                }
                .prominent(externalStep == 2)
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .help("Import the reply on the clipboard (⇧⌘V)")
                .disabled(isReconcilingTailoring)

                Spacer()
                if !tailoringChanges.isEmpty || !tailoringPastedText.isEmpty {
                    Button(role: .destructive) {
                        clearTailoringSession()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }

            if let status = importStatus {
                Label(status, systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            if !tailoringImportIssues.isEmpty {
                tailoringImportIssueList
            }

            DisclosureGroup("Pasted reply", isExpanded: $showPastedPlanText) {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $tailoringPastedText)
                        .font(.body.monospaced())
                        .frame(minHeight: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(nsColor: .separatorColor))
                        )
                    Button {
                        importTailoringPlan(pasted: tailoringPastedText)
                    } label: {
                        Label("Import Edited Text", systemImage: "arrow.clockwise")
                    }
                    .disabled(isReconcilingTailoring || tailoringPastedText.trimmed.isEmpty)
                }
                .padding(.top, 6)
            }
            .font(.callout)
        }
    }

    /// "Imported · fit 8.5/10 · 4 changes to review", once a plan is in.
    private var importStatus: String? {
        guard tailoringPlan != nil, !tailoringImportIssues.contains(where: \.isError) else { return nil }
        var parts = ["Plan imported"]
        if let fit = tailoringBrief?.fitScoreText { parts.append("fit \(fit)") }
        let pending = tailoringProgress.pendingChanges
        parts.append(pending == 0 ? "everything applied" : "\(pending) change\(pending == 1 ? "" : "s") to review")
        return parts.joined(separator: " · ")
    }

    private var reviewPDFStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generate the PDF, copy the text it actually extracts, and ask the chat to review it. Its fixes land in the list above.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    Task { await generateDocument(.resume, replacingExisting: hasGeneratedDocument(.resume)) }
                } label: {
                    Label(documentActionTitle(for: .resume), systemImage: "doc.badge.plus")
                }
                .prominent(externalStep == 4 && !tailoringProgress.hasRenderedPDF)
                .disabled(generatingDocumentKind != nil)

                Button {
                    copyRenderedResumeText()
                } label: {
                    Label("Copy PDF Text", systemImage: "doc.on.clipboard")
                }
                .disabled(!tailoringProgress.hasRenderedPDF)

                Button {
                    pasteAndReadReview()
                } label: {
                    Label(isReviewingResume ? "Reading…" : "Paste Review & Read", systemImage: "text.magnifyingglass")
                }
                .disabled(isReviewingResume || aiBackend == nil)
                .help(aiBackend == nil
                      ? "Reading a review uses the in-app AI — configure one in Settings → Tools"
                      : "Read the review on the clipboard into the same check the app runs")
                Spacer()
            }

            if let review = tailoringProgress.review {
                Label(review.summary + (tailoringProgress.isReviewStale ? " — checked before the latest build" : ""),
                      systemImage: review.isClean ? "checkmark.seal.fill" : "exclamationmark.bubble")
                    .font(.callout)
                    .foregroundStyle(review.isClean && !tailoringProgress.isReviewStale ? .green : .secondary)
            }

            DisclosureGroup("Pasted review", isExpanded: $showPastedReviewText) {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $pastedReviewText)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(nsColor: .separatorColor))
                        )
                    Button {
                        Task { await reconcilePastedReview(pastedReviewText) }
                    } label: {
                        Label("Read Edited Text", systemImage: "arrow.clockwise")
                    }
                    .disabled(isReviewingResume || pastedReviewText.trimmed.isEmpty || aiBackend == nil)
                }
                .padding(.top, 6)
            }
            .font(.callout)
        }
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
                Text("Run **Analyze Fit** in the Job Context panel first, or switch to **External Chat** to tailor in ChatGPT.")
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

    private func tailoringChangesSection(showsHeading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let pending = tailoringChanges.filter { !$0.isBlocked && !$0.applied && !$0.isInformational }.count
            HStack {
                if showsHeading {
                    Text("Proposed changes")
                        .font(.headline)
                } else {
                    Text(pending == 0 ? "All applied." : "\(pending) to review")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    applyAllTailoring()
                } label: {
                    Label("Apply All", systemImage: "checkmark.circle")
                }
                .prominent(tailoringSource == .externalChat && externalStep == 3)
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
                    TailoringChangeRow(
                        change: change,
                        canRevert: canRevertTailoringChange(change),
                        onApply: { applyTailoringChange(change) },
                        onApplyAlternate: {
                            // A new bullet is applied one of two ways; the row's
                            // second button keeps it out of the shared bank.
                            guard case .newBullet(let bullet, _) = change.action else { return }
                            var scoped = change
                            scoped.action = .newBullet(bullet, toBank: false)
                            applyTailoringChange(scoped)
                        },
                        onRevert: { revertTailoringChange(change) }
                    )
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

    /// Errors first — any one of them stops the import — then warnings, which
    /// don't.
    private var tailoringImportIssueList: some View {
        let issues = tailoringImportIssues.filter(\.isError) + tailoringImportIssues.filter { !$0.isError }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(issues) { issue in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: issue.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.isError ? .red : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        if !issue.path.isEmpty {
                            Text(issue.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(issue.message)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

/// Chats the context can be taken to. ChatGPT is the default target.
private enum ExternalChat: String, CaseIterable, Identifiable {
    case chatGPT
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        }
    }

    var url: URL {
        switch self {
        case .chatGPT: URL(string: "https://chatgpt.com/")!
        case .claude: URL(string: "https://claude.ai/new")!
        }
    }
}

/// One numbered step of the external flow: a badge that turns into a check
/// once done, and the step's own controls beside it.
private enum TailorStepStatus {
    case done
    case current
    case upcoming
}

private struct TailorStep<Content: View>: View {
    let number: Int
    let title: String
    let status: TailorStepStatus
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(badgeFill)
                    .frame(width: 24, height: 24)
                if status == .done {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(status == .current ? Color.white : Color.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(status == .upcoming ? .secondary : .primary)
                    .padding(.top, 2)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var badgeFill: Color {
        switch status {
        case .done: .green
        case .current: .accentColor
        case .upcoming: Color(nsColor: .quaternaryLabelColor)
        }
    }
}

private extension View {
    /// The one button a step is waiting on is prominent; the rest stay bordered.
    @ViewBuilder
    func prominent(_ isProminent: Bool) -> some View {
        if isProminent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

private struct TailoringChangeRow: View {
    let change: TailoringChange
    var canRevert = false
    let onApply: () -> Void
    var onApplyAlternate: (() -> Void)? = nil
    var onRevert: (() -> Void)? = nil

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
                    let descriptions = TailoringSignal.descriptions(signal)
                    if !descriptions.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Why this change")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(descriptions, id: \.self) { description in
                                Text(description)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let confirmation = change.confirmationNeeded {
                    Label("Confirm before submitting: \(confirmation)", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let caution = change.caution {
                    Label(caution, systemImage: "arrow.down.right.circle.fill")
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
            HStack(spacing: 8) {
                Label("Applied", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                if canRevert, let onRevert {
                    Button("Revert", action: onRevert)
                        .controlSize(.small)
                        .help("Put back what this change replaced")
                }
            }
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
