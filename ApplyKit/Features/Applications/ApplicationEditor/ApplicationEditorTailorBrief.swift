//
//  ApplicationEditorTailorBrief.swift
//  ApplyKit
//
//  Stage 1 of the Resume Tailor, in the Job Context inspector: run the fit and
//  effort judgment, answer the questions it asks, and probe the gaps it found.
//  Answers are recorded in the application's notes and fed to Stage 2
//  (ApplicationEditorTailoring.swift). Prompts live in TailoringPrompts.swift.
//

import AppKit
import SwiftUI

extension ApplicationEditorView {

    // MARK: - Panel

    var tailorBriefSection: some View {
        DetailPanel("Resume Tailor", collapseKey: "applicationEditor.collapsed.tailorBrief") {
            HStack(spacing: 8) {
                Button {
                    Task { await runTailoringBrief() }
                } label: {
                    Label(
                        isRunningBrief ? "Analyzing…" : (tailoringBrief == nil ? "Analyze Fit" : "Re-analyze"),
                        systemImage: "scope"
                    )
                }
                .disabled(isRunningBrief || application.jobDescription.trimmed.isEmpty || aiBackend == nil)
                .help(aiBackend == nil
                    ? "Configure an AI CLI in Settings → Tools"
                    : application.jobDescription.trimmed.isEmpty
                        ? "Paste a job description first"
                        : "Judge fit, application priority, and how much tailoring is worth doing")

                HStack(spacing: 4) {
                    if canResearch {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(backendSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(backendSummaryHelp)
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                if let brief = tailoringBrief {
                    TailoringBriefView(
                        brief: brief,
                        experiences: experiences,
                        isClarifying: isClarifying,
                        canRunAI: aiBackend != nil,
                        answerBinding: answerBinding(for:),
                        buildNotesBinding: buildNotesBinding,
                        progress: tailoringProgress,
                        onSendAnswers: { Task { await sendTailoringAnswers() } },
                        onProbeGaps: { Task { await probeTailoringGaps() } },
                        onDismissQuestion: dismissTailoringQuestion,
                        onBuild: { showTailoringSheet = true },
                        onReviewPDF: { Task { await reviewRenderedResume() } }
                    )
                } else if !isRunningBrief {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Three steps: judge the role, answer what the tailor asks, then build the résumé.")
                            .font(.callout.weight(.medium))
                        Text("**Analyze Fit** reads the job description against your experience bank and reports how well you fit, how much tailoring is worth doing, and what the résumé should say. Nothing is changed until you review and apply the edits at the end.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                legacyJDAnalysisDisclosure
            }
        }
    }

    /// Old freeform JD analyses are kept readable (and discardable) but never
    /// regenerated — the brief replaced them.
    @ViewBuilder
    private var legacyJDAnalysisDisclosure: some View {
        if !application.jdAnalysisText.trimmed.isEmpty {
            DisclosureGroup("Previous JD analysis") {
                VStack(alignment: .leading, spacing: 10) {
                    Button(role: .destructive) {
                        application.jdAnalysisText = ""
                        persistApplicationChanges()
                    } label: {
                        Label("Discard", systemImage: "trash")
                    }
                    .controlSize(.small)
                    JDAnalysisView(text: application.jdAnalysisText)
                }
                .padding(.top, 8)
            }
            .font(.caption)
        }
    }

    private func answerBinding(for questionID: UUID) -> Binding<String> {
        Binding(
            get: { tailoringBrief?.questions.first { $0.id == questionID }?.answer ?? "" },
            set: { newValue in
                updateTailoringBrief { $0.setAnswer(newValue, for: questionID) }
            }
        )
    }

    private var buildNotesBinding: Binding<String> {
        Binding(
            get: { tailoringBrief?.buildNotes ?? "" },
            set: { newValue in updateTailoringBrief { $0.buildNotes = newValue } }
        )
    }

    /// Edits the working copy and defers the expensive part. Encoding the brief,
    /// writing it to the store, and persisting it are all debounced, so typing
    /// costs a struct mutation rather than a JSON round-trip plus a disk write.
    func updateTailoringBrief(_ body: (inout TailoringBrief) -> Void) {
        guard var brief = tailoringBrief else { return }
        body(&brief)
        editingBrief = brief
        briefSaveDebouncer.schedule { commitTailoringBrief() }
    }

    /// Flushes the working copy into the stored record — the runner may be
    /// mid-flight on this same application, and the store is the one copy both
    /// sides agree on. The editor's snapshot is kept in step so its autosave
    /// can't undo it.
    func commitTailoringBrief() {
        guard let brief = editingBrief else { return }
        application.setTailoringBrief(brief)
        committedBriefData = application.tailoringBriefData
        if let index = store.applications.firstIndex(where: { $0.id == application.id }) {
            store.applications[index].setTailoringBrief(brief)
        }
        persistApplicationChanges()
    }

    /// Drops a question from the brief. Any bullet it already produced stays —
    /// the draft is the valuable part, the question was only how it got asked.
    func dismissTailoringQuestion(_ questionID: UUID) {
        updateTailoringBrief { $0.questions.removeAll { $0.id == questionID } }
    }

    /// What has happened after the brief, for the step list.
    var tailoringProgress: TailoringProgress {
        let resume = documents.first { $0.kindRaw == GeneratedDocumentKind.resume.rawValue }
        let pdfPath = resume?.pdfPath.trimmed ?? ""
        let hasPDF = !pdfPath.isEmpty && FileManager.default.fileExists(atPath: pdfPath)
        let review = storedApplication?.tailoringReview
        let actionable = tailoringChanges.filter { !$0.isBlocked && !$0.isInformational }

        // A PDF built after the review was taken makes its findings historical.
        var stale = false
        if let review, hasPDF,
           let built = try? FileManager.default.attributesOfItem(atPath: pdfPath)[.modificationDate] as? Date {
            stale = built > review.checkedAt
        }

        let pending = actionable.filter { !$0.applied }
        return TailoringProgress(
            hasPlan: tailoringPlan != nil,
            appliedChanges: actionable.filter(\.applied).count,
            pendingChanges: pending.count,
            pendingFromBuild: pending.filter { $0.source == .build }.count,
            pendingFromCheck: pending.filter { $0.source != .build }.count,
            hasRenderedPDF: hasPDF,
            isReviewing: tailoringRunner.isRunning(.review, for: application.id),
            review: review,
            isReviewStale: stale
        )
    }

    func reviewRenderedResume() async {
        await tailoringRunner.reviewRenderedResume(applicationID: application.id)
    }

    var isReviewingResume: Bool { tailoringRunner.isRunning(.review, for: application.id) }

    /// Reads a review done in ChatGPT into the same check the app runs.
    func reconcilePastedReview(_ text: String) async {
        await tailoringRunner.reconcileReview(applicationID: application.id, pastedReview: text)
    }

    /// The text the rendered PDF actually extracts — what an ATS would see, and
    /// what a reviewer needs to judge the artifact rather than the plan.
    func copyRenderedResumeText() {
        guard let resume = documents.first(where: { $0.kindRaw == GeneratedDocumentKind.resume.rawValue }),
              let rendered = ResumePDFInspector.inspect(path: resume.pdfPath) else {
            activityMonitor.fail("Generate the résumé PDF first.")
            return
        }
        let header = """
        Résumé for \(application.companyName) — \(application.jobTitle)
        \(rendered.pageCount) page\(rendered.pageCount == 1 ? "" : "s"), as extracted from the rendered PDF.

        """
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(header + rendered.text, forType: .string)
        activityMonitor.succeed("Copied the rendered résumé's text. Paste it into ChatGPT for review.")
    }

    // MARK: - Runs
    //
    // All four hand off to `TailoringRunner`, which owns them for as long as they
    // take. Leaving this application — or closing its editor — no longer cancels
    // or orphans the work, so several applications can tailor at once.

    func runTailoringBrief() async {
        briefSaveDebouncer.flush { commitTailoringBrief() }
        await tailoringRunner.analyzeFit(applicationID: application.id)
    }

    func sendTailoringAnswers() async {
        briefSaveDebouncer.flush { commitTailoringBrief() }
        await tailoringRunner.clarify(applicationID: application.id, probeGaps: false)
    }

    func probeTailoringGaps() async {
        briefSaveDebouncer.flush { commitTailoringBrief() }
        await tailoringRunner.clarify(applicationID: application.id, probeGaps: true)
    }

    /// Whether this run will read the web. Both CLIs can, once asked; the
    /// posting is only part of what gets read (see `tailoringResearchBlock`).
    var canResearch: Bool {
        (aiBackend?.canResearch ?? false) && (settings?.researchEnabled ?? true)
    }

    /// What the next run will use, shown next to the button so an expensive
    /// model isn't a surprise. Kept short — the full story is in the tooltip.
    var backendSummary: String {
        guard let aiBackend else { return "No AI CLI configured" }
        return "\(aiBackend.name) · \(aiBackend.effectiveModel) · \(aiBackend.effectiveEffort)"
    }

    var backendSummaryHelp: String {
        guard let aiBackend else { return "Configure an AI CLI in Settings → Tools" }
        let research = canResearch
            ? "Reads the live posting and the résumé guidance."
            : "Works from the pasted job description alone."
        return "\(aiBackend.name), model \(aiBackend.effectiveModel), \(aiBackend.effectiveEffort) effort. \(research) Change these in Settings → Tools."
    }

    var appliedMasterResume: MasterResume? {
        guard let id = application.sourceMasterResumeID else { return nil }
        return store.masterResumes.first { $0.id == id }
    }

    // MARK: - Adopting background results

    /// Changes any tailoring run makes to this application: the brief, the plan,
    /// the recall drafts, and the Q&A the clarify pass appends to notes.
    ///
    /// Sizes and a timestamp rather than the payloads themselves — this is
    /// evaluated on every body pass, and joining several kilobytes of JSON per
    /// keystroke was its own source of lag.
    var storedTailoringFingerprint: String {
        guard let stored = storedApplication else { return "" }
        return [
            stored.tailoringBriefData.count,
            stored.tailoringPlanData.count,
            stored.tailoringReviewData.count,
            stored.curatedSuggestionsData.count,
            stored.notes.count,
            Int(stored.updatedAt.timeIntervalSince1970 * 1000)
        ].map(String.init).joined(separator: "\u{1F}")
    }

    /// Pulls a finished run's output into this editor's snapshot. Without it the
    /// editor's debounced autosave would write its pre-run copy back over the
    /// result — the same hazard `adoptExternalTimelineEvents` guards against.
    func adoptExternalTailoringState() {
        guard let stored = storedApplication else { return }
        // Only take the stored brief when it is genuinely someone else's work.
        // Adopting our own just-committed copy would revert anything typed since.
        if stored.tailoringBriefData != committedBriefData {
            editingBrief = stored.tailoringBrief
            committedBriefData = stored.tailoringBriefData
        }
        application.tailoringBriefData = stored.tailoringBriefData
        application.fitScore = stored.fitScore
        application.tailoringPlanData = stored.tailoringPlanData
        application.tailoringReviewData = stored.tailoringReviewData
        application.curatedSuggestionsData = stored.curatedSuggestionsData
        curatedSuggestions = decodeCuratedSuggestions(stored.curatedSuggestionsData)
        if let session = TailoringSession.decode(stored.tailoringPlanData) {
            appliedBeforeText.merge(session.appliedBefore) { current, _ in current }
        }
        tailoringChanges = allTailoringChanges()

        // Notes are user-editable here and appended to there, so take only what
        // was added rather than overwriting whatever is being typed.
        if stored.notes != application.notes, stored.notes.hasPrefix(adoptedNotes) {
            let appended = String(stored.notes.dropFirst(adoptedNotes.count))
            if !appended.isEmpty { application.notes += appended }
        }
        adoptedNotes = stored.notes
    }
}
