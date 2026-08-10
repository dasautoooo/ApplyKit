//
//  TailoringBriefView.swift
//  ApplyKit
//
//  Renders the Resume Tailor's Stage 1 brief: the fit and effort judgment, the
//  candidate story, matches and gaps, the proposed content plan, and the
//  question cards that drive the clarify loop.
//

import AppKit
import SwiftUI

struct TailoringBriefView: View {
    let brief: TailoringBrief
    let experiences: [ExperienceBullet]
    let isClarifying: Bool
    let canRunAI: Bool
    let answerBinding: (UUID) -> Binding<String>
    let buildNotesBinding: Binding<String>
    /// What has happened after the brief: the plan, what's been applied, the
    /// rendered PDF, and the last review of it.
    let progress: TailoringProgress
    let onSendAnswers: () -> Void
    let onProbeGaps: () -> Void
    let onDismissQuestion: (UUID) -> Void
    let onBuild: () -> Void
    let onReviewPDF: () -> Void

    private var experiencesByID: [UUID: ExperienceBullet] {
        Dictionary(uniqueKeysWithValues: experiences.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Where you are, then the judgement, then the evidence behind it,
            // then your inputs, then what the rendered file came back with —
            // and the next action last, where reading ends.
            workflowStrip
            Divider()
            verdictHeader
            if let story = brief.candidateStory?.trimmed, !story.isEmpty {
                briefBlock("Candidate story") { bodyText(story) }
            }
            matchesBlock
            gapsBlock
            planBlock
            researchBlock
            questionsBlock
            factsBlock
            buildNotesBlock
            reviewBlock
            nextStepFooter
        }
    }

    // MARK: - Workflow

    /// The three steps, in order, with the one action that moves you forward.
    /// Without this the flow is scattered: judge here, answer questions further
    /// down, build from a button somewhere else.
    private var workflowStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            stepRow(number: 1, title: "Fit judged", detail: fitStepDetail, state: .done)
            stepRow(number: 2, title: "Questions", detail: questionStepDetail, state: questionStepState)
            stepRow(number: 3, title: "Build the tailored résumé", detail: buildStepDetail,
                    state: buildStepState)
            stepRow(number: 4, title: "Check the rendered PDF", detail: reviewStepDetail,
                    state: reviewStepState)

            actionRow(controlSize: .small)
                .padding(.leading, 26)
        }
    }

    private var buildStepState: StepState {
        guard progress.hasPlan else { return .todo }
        return progress.pendingChanges == 0 ? .done : .current
    }

    private var buildStepDetail: String {
        guard progress.hasPlan else {
            return "Turns this brief into résumé edits you review one by one."
        }
        if progress.appliedChanges == 0 {
            return "\(progress.pendingChanges) change\(progress.pendingChanges == 1 ? "" : "s") proposed, none applied yet."
        }
        return progress.pendingChanges == 0
            ? "All \(progress.appliedChanges) change\(progress.appliedChanges == 1 ? "" : "s") applied."
            : "\(progress.appliedChanges) applied, \(progress.pendingChanges) still to review."
    }

    private var reviewStepState: StepState {
        guard progress.hasRenderedPDF else { return .todo }
        if let review = progress.review, !progress.isReviewStale {
            // Anything above a note is still outstanding, blocking or not.
            return review.isClean ? .done : .current
        }
        return progress.pendingChanges == 0 ? .current : .todo
    }

    private var reviewStepDetail: String {
        guard progress.hasRenderedPDF else {
            return "Generate the résumé PDF in Documents, then the tailor can check what actually rendered."
        }
        guard let review = progress.review else {
            return "The two-page fit is only an estimate until the rendered file is checked."
        }
        if progress.isReviewStale {
            return "\(review.summary) — checked before the latest build, so run it again."
        }
        let outstanding = review.actionable.count
        return outstanding == 0
            ? review.summary
            : "\(review.summary). \(outstanding) still to address — check again after rebuilding."
    }

    /// The step list and the footer share these buttons so they can't offer
    /// differently-worded versions of the same action.
    @ViewBuilder
    private func actionRow(controlSize: ControlSize) -> some View {
        HStack(spacing: 8) {
            switch progress.nextStep {
            case .build, .reviewChanges:
                Button(action: onBuild) {
                    Label(progress.hasPlan ? "Review Changes" : "Build Tailored Résumé",
                          systemImage: progress.hasPlan ? "checklist" : "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(controlSize)
                .disabled(!canRunAI)
            case .generatePDF, .done:
                EmptyView()
            case .checkPDF:
                EmptyView()
            }

            if progress.hasRenderedPDF {
                let check = Button(action: onReviewPDF) {
                    Label(progress.isReviewing ? "Checking…" : checkButtonLabel,
                          systemImage: "doc.viewfinder")
                }
                .controlSize(controlSize)
                .disabled(!canRunAI || progress.isReviewing)
                .help("Reads the generated PDF: real page count, ordering, and whether the text extracts cleanly")

                if isCheckPrimary {
                    check.buttonStyle(.borderedProminent)
                } else {
                    check.buttonStyle(.bordered)
                }
            }

            if progress.hasPlan, progress.pendingChanges == 0, progress.nextStep != .generatePDF {
                Button(action: onBuild) {
                    Label("Open Changes", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
                .controlSize(controlSize)
            }
        }
    }

    private var checkButtonLabel: String {
        progress.review == nil ? "Check Rendered PDF" : "Check Again"
    }

    private var isCheckPrimary: Bool {
        if case .checkPDF = progress.nextStep { return true }
        return false
    }

    private enum StepState { case done, current, todo }

    private func stepRow(number: Int, title: String, detail: String, state: StepState) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: state == .done ? "checkmark.circle.fill" : "\(number).circle\(state == .current ? ".fill" : "")")
                .foregroundStyle(state == .done ? Color.green : (state == .current ? Color.accentColor : Color.secondary))
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(state == .current ? .semibold : .regular))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fitStepDetail: String {
        [brief.fitScoreText.map { "Fit \($0)" }, brief.investmentTier.map { "\($0.lowercased()) effort" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var questionStepState: StepState {
        brief.questions.isEmpty || brief.unansweredQuestions.isEmpty ? .done : .current
    }

    private var questionStepDetail: String {
        if brief.questions.isEmpty {
            return "None asked — the tailor had everything it needed."
        }
        let unanswered = brief.unansweredQuestions.count
        return unanswered == 0
            ? "All \(brief.questions.count) answered."
            : "\(unanswered) still unanswered. Answering sharpens what the résumé can claim."
    }

    // MARK: - Verdict

    /// Score and effort tier are the labels; the reasoning underneath is the
    /// content, so it gets body weight and colour while they stay metadata.
    private var verdictHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let fit = brief.fitScoreText {
                    Text(fit)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(fitColor)
                }
                Text(verdictMetaLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rationale = brief.effortRationale?.trimmed, !rationale.isEmpty {
                bodyText(rationale)
            }
        }
    }

    /// "medium confidence · Standard tailoring, 20–35 minutes" — everything that
    /// qualifies the score, on one quiet line.
    private var verdictMetaLine: String {
        var parts: [String] = []
        if let confidence = brief.fitConfidence?.trimmed, !confidence.isEmpty {
            parts.append("\(confidence) confidence")
        }
        if let tier = brief.investmentTier?.trimmed, !tier.isEmpty {
            let time = brief.investmentTime?.trimmed
            parts.append(time.map { "\(tier) tailoring, \($0)" } ?? "\(tier) tailoring")
        }
        return parts.joined(separator: " · ")
    }

    private var fitColor: Color {
        switch brief.fitScore ?? 0 {
        case 7...: .green
        case 5..<7: .orange
        default: .secondary
        }
    }

    // MARK: - Matches, gaps, plan

    @ViewBuilder
    private var matchesBlock: some View {
        if !brief.strongMatches.isEmpty {
            briefBlock("Strong matches") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(brief.strongMatches.enumerated()), id: \.offset) { index, match in
                        if index > 0 { Divider().padding(.vertical, 10) }
                        VStack(alignment: .leading, spacing: 4) {
                            bodyText(match.claim)
                            if let evidence = evidenceText(match) {
                                detailText(evidence)
                            }
                        }
                    }
                }
            }
        }
    }

    private func evidenceText(_ match: TailoringBrief.Match) -> String? {
        let title = match.experienceID.flatMap { experiencesByID[$0]?.displayTitle }
        let parts = [title, match.evidence?.trimmed].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    @ViewBuilder
    private var gapsBlock: some View {
        if !brief.gaps.isEmpty {
            briefBlock("Gaps") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(TailoringGapKind.allCases, id: \.rawValue) { kind in
                        let gaps = brief.gaps.filter { $0.gapKind == kind }
                        if !gaps.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(gapHeading(kind))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(gapColor(kind))
                                    .fixedSize(horizontal: false, vertical: true)
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(gaps.enumerated()), id: \.element.id) { index, gap in
                                        if index > 0 { Divider().padding(.vertical, 10) }
                                        VStack(alignment: .leading, spacing: 4) {
                                            bodyText(gap.text)
                                            if let mitigation = gap.mitigation?.trimmed, !mitigation.isEmpty {
                                                detailText(mitigation)
                                            }
                                        }
                                    }
                                }
                                // Boxed so it reads as an action about the group
                                // above, not as one more gap in the list.
                                if kind == .genuine { genuineGapPrompt }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Genuine gaps are judged from the experience bank, which is often behind
    /// what the candidate has actually done. This explains that and offers the
    /// clarify pass as the way to correct it.
    private var genuineGapPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailText("Missing from your experience bank isn't the same as missing from your career.")

            HStack(spacing: 8) {
                Button(action: onProbeGaps) {
                    Label(isClarifying ? "Thinking of questions…" : "Ask Me About These",
                          systemImage: "questionmark.bubble")
                }
                .controlSize(.regular)
                .disabled(isClarifying || !canRunAI || brief.unprobedGenuineGaps.isEmpty)

                if !canRunAI {
                    detailText("Configure an AI CLI in Settings → Tools")
                }
            }

            Text(probeHint)
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var probeHint: String {
        brief.unprobedGenuineGaps.isEmpty
            ? "Already asked about each of these."
            : "Adds questions below. Real experience you recall becomes a bullet you can keep."
    }

    private func gapHeading(_ kind: TailoringGapKind) -> String {
        switch kind {
        case .genuine: "Genuine — wording can't fix these"
        case .presentation: "Presentation — the evidence exists, the résumé doesn't show it"
        case .unknown: "Unresolved"
        }
    }

    private func gapColor(_ kind: TailoringGapKind) -> Color {
        switch kind {
        case .genuine: .orange
        case .presentation: .blue
        case .unknown: .secondary
        }
    }

    @ViewBuilder
    private var planBlock: some View {
        let plan = brief.plan
        let hasPlan = plan.summaryDirection?.trimmed.isEmpty == false
            || plan.skillsDirection?.trimmed.isEmpty == false
            || !plan.selections.isEmpty || !plan.rewrites.isEmpty || !plan.exclusions.isEmpty
        if hasPlan {
            briefBlock("Proposed plan") {
                VStack(alignment: .leading, spacing: 10) {
                    if let summary = plan.summaryDirection?.trimmed, !summary.isEmpty {
                        labelledLine("Summary", summary)
                    }
                    if let skills = plan.skillsDirection?.trimmed, !skills.isEmpty {
                        labelledLine("Skills", skills)
                    }
                    planItems("Select", plan.selections)
                    planItems("Rewrite", plan.rewrites)
                    planItems("Drop", plan.exclusions)
                }
            }
        }
    }

    @ViewBuilder
    private func planItems(_ label: String, _ items: [TailoringBrief.ProposedPlan.Item]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let title = item.experienceID.flatMap { experiencesByID[$0]?.displayTitle }
                        ?? item.label
                        ?? "Unmatched bullet"
                    VStack(alignment: .leading, spacing: 1) {
                        bodyText(title)
                        if let reason = item.reason?.trimmed, !reason.isEmpty {
                            detailText(reason)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var researchBlock: some View {
        if let notes = brief.researchNotes, !notes.isEmpty {
            briefBlock("Research") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        VStack(alignment: .leading, spacing: 2) {
                            bodyText(note.isInference == true ? "\(note.claim) (inferred)" : note.claim)
                            if let source = note.sourceURL?.trimmed, !source.isEmpty, let url = URL(string: source) {
                                Link(source, destination: url)
                                    .font(.callout)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Questions and drafts

    @ViewBuilder
    private var questionsBlock: some View {
        if !brief.questions.isEmpty {
            briefBlock("Questions") {
                VStack(alignment: .leading, spacing: 12) {
                    detailText("The tailor asks before drafting. Answer what you can — every answer feeds the résumé build, and anything that turns out to be real experience becomes a bullet.")

                    ForEach(brief.questions) { question in
                        questionCard(question)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Button(action: onSendAnswers) {
                                Label(isClarifying ? "Working…" : "Send Answers", systemImage: "arrow.up.circle")
                            }
                            .controlSize(.small)
                            .disabled(isClarifying || !canRunAI || brief.pendingAnswers.isEmpty || !brief.canClarifyFurther)
                            Spacer()
                        }
                        Text(sendAnswersHint)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Says what pressing Send does, or why it can't be pressed yet.
    private var sendAnswersHint: String {
        if !brief.canClarifyFurther {
            return "Question rounds are capped at \(TailoringBrief.maxClarifyRounds). Build the résumé from what you have."
        }
        if !brief.pendingAnswers.isEmpty {
            let count = brief.pendingAnswers.count
            return "Sends \(count) answer\(count == 1 ? "" : "s"). The tailor updates the gaps, drafts bullets from anything new, and may ask a follow-up."
        }
        return brief.unansweredQuestions.isEmpty
            ? "All answered. You can build the résumé, or use \"Ask Me About These\" above to dig into a gap."
            : "Type an answer above, then send."
    }

    private func questionCard(_ question: TailoringQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                if question.round > 1 {
                    Text("Follow-up")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text(question.questionKind == .recall ? "Recall" : "Verify")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(question.questionKind == .recall ? Color.purple : Color.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((question.questionKind == .recall ? Color.purple : Color.blue).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(question.question)
                    .font(.body)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if question.isAnswered {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                }
                Button {
                    onDismissQuestion(question.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove this question — use it for anything you'd rather not answer, or a repeat")
            }

            TextEditor(text: answerBinding(question.id))
                .font(.body)
                .frame(minHeight: 54)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
                )
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// What the answers established, as facts — not bullets. Stage 2 decides
    /// whether each one becomes a line of its own or strengthens an existing
    /// bullet, because only it can see the whole résumé and the page budget.
    @ViewBuilder
    private var factsBlock: some View {
        if !brief.recalledFacts.isEmpty {
            briefBlock("Confirmed from your answers") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(brief.recalledFacts.enumerated()), id: \.element.id) { index, fact in
                        if index > 0 { Divider().padding(.vertical, 10) }
                        VStack(alignment: .leading, spacing: 4) {
                            bodyText(fact.fact)
                            if let related = fact.relatedBulletID.flatMap({ experiencesByID[$0]?.displayTitle }) {
                                detailText("Belongs with \(related)")
                            }
                            if let relevance = fact.relevance?.trimmed, !relevance.isEmpty {
                                detailText(relevance)
                            }
                            if let confirm = fact.confirmationNeeded?.trimmed, !confirm.isEmpty {
                                Label("Check before submitting: \(confirm)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The candidate's own instruction to the build — the place to say "fold
    /// that into the Tuya bullet" rather than watching it become its own line.
    private var buildNotesBlock: some View {
        briefBlock("Direction for the build") {
            VStack(alignment: .leading, spacing: 6) {
                detailText("Anything the tailor should know before it writes: what to emphasise, what to leave out, which facts belong together.")
                TextEditor(text: buildNotesBinding)
                    .font(.system(size: 14))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
                    )
            }
        }
    }

    /// The panel is long, and answering questions leaves you at the bottom of it
    /// — a long way from the step list at the top. This is the same next action,
    /// where you actually end up.
    private var nextStepFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text(progress.nextStepTitle)
                .font(.system(size: 15, weight: .semibold))

            Text(.init(footerExplanation))
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            actionRow(controlSize: .regular)
        }
        .padding(.top, 4)
    }

    private var footerExplanation: String {
        switch progress.nextStep {
        case .generatePDF:
            return "Every proposed change is applied. Generate the résumé PDF in the Documents section above, then the tailor can check the file itself."
        case .checkPDF(let isRecheck):
            return isRecheck
                ? "The PDF has been rebuilt since the last check, so those findings describe a file that no longer exists. Check it again."
                : "Reads the generated PDF: its real page count, whether sections and dates stay together, and whether the text extracts in an order a parser can follow. Until this runs, the two-page fit is only an estimate."
        case .done:
            return "The rendered PDF checks out and every proposed change is applied. Re-run any step if you keep editing — checking is meant to be repeated."
        case .reviewChanges(let count) where count == 0:
            return "The last check left findings to address, but none of them can be fixed by changing content. Adjust the résumé yourself, rebuild the PDF, then check again."
        case .reviewChanges(let count):
            // A bare count can't be reconciled with what you see, since the list
            // holds two runs' worth of changes. Say which is which.
            var text = "\(count) change\(count == 1 ? " is" : "s are") waiting in **Review Changes**"
            switch (progress.pendingFromBuild, progress.pendingFromCheck) {
            case let (build, check) where build > 0 && check > 0:
                text += " — \(build) from the build, \(check) from the PDF check."
            case let (_, check) where check > 0:
                text += " — all from the PDF check."
            default:
                text += " — from the build."
            }
            return text + " Each shows its current and tailored wording, and applies on its own\u{2E}"
        case .build:
            break
        }

        var lines = ["Turns this brief, your answers, and the facts above into résumé edits — a new summary, skills, bullet selection and order, and rewrites — which you review and apply one at a time. Nothing changes until you do."]
        let unanswered = brief.unansweredQuestions.count
        if unanswered > 0 {
            lines.append("\(unanswered) question\(unanswered == 1 ? " is" : "s are") still unanswered. You can build without answering — the résumé simply won't be able to claim what they'd establish.")
        }
        if brief.recalledFacts.contains(where: { $0.confirmationNeeded?.trimmed.isEmpty == false }) {
            lines.append("Facts marked \"check before submitting\" are used as written. Correct them in an answer above if they're wrong, or leave them and verify before you send the résumé.")
        }
        return lines.joined(separator: "\n\n")
    }

    /// The rendered-PDF findings, once there are any.
    @ViewBuilder
    private var reviewBlock: some View {
        if let review = progress.review {
            briefBlock("Rendered PDF") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let scoreText = review.scoreText {
                            Text(scoreText)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(reviewScoreColor(review.score ?? 0))
                        }
                        if let confidence = review.fitConfidence?.trimmed, !confidence.isEmpty {
                            Text("\(confidence) confidence")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(review.pageCount) page\(review.pageCount == 1 ? "" : "s")")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(review.isOverPageBudget ? Color.orange : Color.primary)
                        if let verdict = review.verdict?.trimmed, !verdict.isEmpty {
                            Text(verdict)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("Check #\(review.round)")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    if progress.isReviewStale {
                        detailText("Checked before the latest build — run it again for a current answer.")
                    }
                    if let checks = review.checksSummary {
                        detailText("\(checks). The score above is a separate judgment — how well this document fits the role, on the same rubric Stage 1 used.")
                    }
                    if let note = review.extractionNote?.trimmed, !note.isEmpty {
                        detailText(note)
                    }
                    checklistBlock(review)
                    ForEach(review.findings) { finding in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: finding.findingSeverity == .note
                                      ? "info.circle" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(severityColor(finding.findingSeverity))
                                    .imageScale(.small)
                                    .padding(.top, 2)
                                bodyText(readable(finding.text))
                            }
                            if let fix = finding.fix?.trimmed, !fix.isEmpty {
                                detailText(readable(fix)).padding(.leading, 22)
                            }
                        }
                    }
                    if review.findings.isEmpty {
                        detailText("No problems found in the rendered file.")
                    }
                    if progress.pendingFromCheck > 0 {
                        detailText(progress.pendingFromCheck == 1
                            ? "One of these can be fixed by changing content — that edit is waiting in Review Changes."
                            : "\(progress.pendingFromCheck) of these can be fixed by changing content — those edits are waiting in Review Changes.")
                    } else if review.edits != nil {
                        detailText("The edits this check proposed have all been applied.")
                    }
                }
            }
        }
    }

    /// Swaps any bullet id the reviewer wrote into prose for the bullet's name.
    /// A raw UUID in a sentence is unreadable, and the prompt asks for names —
    /// this is the safety net for when it uses one anyway.
    private func readable(_ text: String) -> String {
        guard text.contains("-") else { return text }
        var result = text
        for (id, bullet) in experiencesByID {
            let uuid = id.uuidString
            for variant in [uuid, uuid.lowercased()] where result.contains(variant) {
                result = result.replacingOccurrences(of: variant, with: "\u{201C}\(bullet.displayTitle)\u{201D}")
            }
        }
        return result
    }

    /// The skill's own pre-submission checklist, run against the rendered file.
    ///
    /// It answers a different question from the findings below it: a finding is
    /// something to do, whereas a check is a question about the document that
    /// may have no action attached — "are the JD's most important
    /// responsibilities supported by evidence?" can fail because of what the
    /// candidate hasn't done, which no edit fixes. Both are worth seeing, so
    /// the difference is spelled out rather than left to be inferred.
    @ViewBuilder
    private func checklistBlock(_ review: TailoringReview) -> some View {
        let unresolved = review.failedChecks + review.unclearChecks
        if !unresolved.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    detailText("These are the skill's pre-submission questions, asked of the rendered file. A \"no\" is not always something to fix — some are statements about fit that only different experience would change. Anything that can be fixed by editing appears as a finding below.")
                    ForEach(unresolved) { check in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(check.checkStatus == .fail ? "No" : "Unclear")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(check.checkStatus == .fail ? Color.orange : Color.secondary)
                                    .frame(width: 52, alignment: .leading)
                                bodyText(check.question)
                            }
                            if let note = check.note?.trimmed, !note.isEmpty {
                                detailText(note).padding(.leading, 58)
                            }
                            if let section = check.section?.trimmed, !section.isEmpty {
                                Text(section)
                                    .font(.caption).foregroundStyle(.tertiary)
                                    .padding(.leading, 58)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(checklistLabel(review))
                    .font(.system(size: 13, weight: .medium))
            }
        }
    }

    private func checklistLabel(_ review: TailoringReview) -> String {
        var parts: [String] = []
        if !review.failedChecks.isEmpty { parts.append("\(review.failedChecks.count) answered no") }
        if !review.unclearChecks.isEmpty { parts.append("\(review.unclearChecks.count) unclear") }
        return "Skill checklist — " + parts.joined(separator: ", ")
    }

    /// Same bands as `fitColor` — this is the same fit score, re-checked
    /// against the rendered document.
    private func reviewScoreColor(_ score: Double) -> Color {
        switch score {
        case 7...: .green
        case 5..<7: .orange
        default: .secondary
        }
    }

    private func severityColor(_ severity: TailoringFindingSeverity) -> Color {
        switch severity {
        case .blocker: .red
        case .fix: .orange
        case .note: .secondary
        }
    }

    // MARK: - Layout helpers

    /// A section of the brief. The heading is a real heading, not a micro-label —
    /// at inspector width these are the only signposts.
    private func briefBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Everything the tailor actually concluded reads at this size, colour, and
    /// leading. Supporting detail uses `detailText` so it never competes.
    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .lineSpacing(5)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labelledLine(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            bodyText(text)
        }
    }
}

#Preview {
    // Inspector-width sample so the reading hierarchy can be checked without
    // spending an AI run.
    let brief = TailoringBrief.parse(from: """
    {
      "fit_score": 8,
      "fit_confidence": "medium",
      "investment_tier": "Standard",
      "investment_time": "20–35 minutes",
      "effort_rationale": "The candidate already has unusually relevant evidence in MCP-based agent tooling, Claude Code integration, independent feature delivery, release automation, documentation, security controls, and a successful public open-source project. A standard pass can expose those strengths and remove less relevant systems material. Deeper tailoring cannot manufacture the main missing qualification: direct experience shipping IDE extensions or agent hooks.",
      "candidate_story": "A systems-leaning product engineer who ships developer tooling end to end and operates it in public.",
      "strong_matches": [
        { "claim": "Builds and operates agent tooling in the open", "evidence": "Parma — public repository with external contributors" }
      ],
      "gaps": [
        { "id": "ide", "kind": "genuine", "text": "No shipped IDE extension or editor integration", "mitigation": "State the adjacent tooling work plainly rather than implying editor experience." },
        { "id": "impact", "kind": "presentation", "text": "Release automation impact is buried in a scope bullet", "mitigation": "Lead the role with the automation outcome." }
      ],
      "plan": {
        "summary_direction": "Open with developer-tooling identity, then the public open-source operation.",
        "skills_direction": "Lead with languages and agent tooling; prune the graphics material."
      },
      "questions": [
        { "kind": "recall", "gap_id": "ide", "question": "Have you built or shipped an extension or agent hook for any editor, even internally?" }
      ]
    }
    """)!
    return ScrollView {
        TailoringBriefView(
            brief: brief,
            experiences: [],
            isClarifying: false,
            canRunAI: true,
            answerBinding: { _ in .constant("") },
            buildNotesBinding: .constant(""),
            progress: TailoringProgress(),
            onSendAnswers: {},
            onProbeGaps: {},
            onDismissQuestion: { _ in },
            onBuild: {},
            onReviewPDF: {}
        )
        .padding(16)
    }
    .frame(width: 380, height: 900)
}
