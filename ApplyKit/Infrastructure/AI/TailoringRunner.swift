//
//  TailoringRunner.swift
//  ApplyKit
//
//  Runs the Resume Tailor's AI work for any number of applications at once.
//
//  These runs used to live in `ApplicationEditorView`'s `@State`, which meant
//  they died with the view: selecting another application tears the editor down
//  (`.id(application.id)`), so an in-flight run would write its result into a
//  discarded view — or flush that view's stale snapshot over newer data. Owning
//  the work here instead lets you start a run on one application, switch to the
//  next, and start another; each lands in the store and on disk when it
//  finishes, whether or not its editor is on screen.
//

import Foundation
import Observation

@MainActor
@Observable
final class TailoringRunner {
    enum Job: String, CaseIterable {
        case brief, clarify, build, reconcile, review

        var startMessage: String {
            switch self {
            case .brief: "Judging fit"
            case .clarify: "Working through answers"
            case .build: "Building the tailored résumé"
            case .reconcile: "Reconciling tailoring suggestion"
            case .review: "Reviewing the rendered résumé"
            }
        }
    }

    /// Jobs in flight per application.
    private(set) var jobs: [UUID: Set<Job>] = [:]

    /// Set once at app start; the runner outlives every view, so it holds the
    /// store rather than receiving one per call.
    var store: AppDataStore?
    var settings: AppSettings?
    var monitor: AppActivityMonitor?

    func isRunning(_ job: Job, for applicationID: UUID) -> Bool {
        jobs[applicationID]?.contains(job) ?? false
    }

    func isBusy(_ applicationID: UUID) -> Bool {
        !(jobs[applicationID]?.isEmpty ?? true)
    }

    var busyApplicationIDs: Set<UUID> {
        Set(jobs.filter { !$0.value.isEmpty }.keys)
    }

    // MARK: - Stage 1

    func analyzeFit(applicationID: UUID) async {
        guard let context = context(for: applicationID), !isRunning(.brief, for: applicationID) else { return }
        let canResearch = context.backend.canResearch && (settings?.researchEnabled ?? true)
        let prompt = PromptBuilder.tailoringBriefPrompt(
            application: context.application,
            allExperiences: context.experiences,
            employments: context.employments,
            masterResume: context.masterResume,
            globalSkillsBlock: context.profile.skillsBlock,
            canResearch: canResearch
        )

        await run(.brief, for: applicationID,
                  message: canResearch ? "Judging fit (reading the posting and guidance)" : "Judging fit") { backend in
            let attempt = try await backend.runStructured(
                prompt: prompt,
                schema: PromptBuilder.briefSchemaSummary,
                allowWebTools: canResearch,
                parse: TailoringBrief.parse(from:)
            )
            guard var brief = attempt.value else {
                return .failure(self.unparseableMessage(attempt.raw, label: "tailoring-brief",
                                                        application: context.application,
                                                        what: "the tailoring brief"))
            }
            brief.dropLogisticalQuestions()
            // Re-analysing must not throw away what the user typed last time.
            var carried = 0
            self.mutate(applicationID) { application in
                if let previous = application.tailoringBrief {
                    brief.carryOverAnswers(from: previous)
                    carried = previous.answeredQuestions.count
                }
                application.setTailoringBrief(brief)
            }

            var message = "Brief ready\(brief.fitScoreText.map { " — fit \($0)" } ?? "")."
            let questions = brief.unansweredQuestions.count
            if questions > 0 { message += " \(questions) question\(questions == 1 ? "" : "s") to answer." }
            if carried > 0 { message += " Kept \(carried) earlier answer\(carried == 1 ? "" : "s")." }
            return .success(message)
        }
    }

    // MARK: - Clarify loop

    func clarify(applicationID: UUID, probeGaps: Bool) async {
        guard let context = context(for: applicationID),
              let brief = context.application.tailoringBrief,
              !isRunning(.clarify, for: applicationID) else { return }
        let answered = probeGaps ? brief.answeredQuestions : brief.pendingAnswers
        guard probeGaps || !answered.isEmpty else { return }
        guard brief.canClarifyFurther || probeGaps else { return }

        let prompt = PromptBuilder.tailoringClarifyPrompt(
            brief: brief,
            answered: answered,
            application: context.application,
            allExperiences: context.experiences,
            employments: context.employments,
            probeGaps: probeGaps
        )
        let answeredIDs = answered.map(\.id)

        await run(.clarify, for: applicationID,
                  message: probeGaps ? "Looking for experience the bank is missing" : "Working through your answers") { backend in
            let attempt = try await backend.runStructured(
                prompt: prompt,
                schema: PromptBuilder.clarificationSchemaSummary,
                parse: TailoringClarification.parse(from:)
            )

            guard let clarification = attempt.value, !clarification.isEmpty else {
                // Still record the round, and mark these answers as seen, so an
                // unhelpful pass can't be repeated forever.
                self.mutate(applicationID) { application in
                    guard var current = application.tailoringBrief else { return }
                    current.markAnswersSent(answeredIDs)
                    current.apply(TailoringClarification())
                    application.setTailoringBrief(current)
                    self.appendAnswersToNotes(answeredIDs, brief: current, on: &application)
                }
                return .failure("The tailor had nothing to add. Your answers are still saved.")
            }

            var result = TailoringBrief.ClarifyResult()
            self.mutate(applicationID) { application in
                guard var current = application.tailoringBrief else { return }
                current.markAnswersSent(answeredIDs)
                result = current.apply(clarification)
                application.setTailoringBrief(current)
                self.appendAnswersToNotes(answeredIDs, brief: current, on: &application)
            }

            var parts: [String] = []
            if result.recordedFacts > 0 {
                parts.append("\(result.recordedFacts) fact\(result.recordedFacts == 1 ? "" : "s") recorded")
            }
            if result.appendedQuestions > 0 {
                parts.append("\(result.appendedQuestions) follow-up question\(result.appendedQuestions == 1 ? "" : "s")")
            }
            var message = parts.isEmpty ? "Brief updated — nothing new to ask." : parts.joined(separator: " and ") + "."
            let refused = result.skippedDuplicates + result.skippedLogistical
            if refused > 0 {
                message += " Skipped \(refused) off-target question\(refused == 1 ? "" : "s")."
            }
            return .success(message)
        }
    }

    // MARK: - Stage 2

    func build(applicationID: UUID) async {
        guard let context = context(for: applicationID),
              let brief = context.application.tailoringBrief,
              !isRunning(.build, for: applicationID) else { return }

        let prompt = PromptBuilder.tailoringBuildPrompt(
            brief: brief,
            application: context.application,
            allExperiences: context.experiences,
            employments: context.employments,
            globalSkillsBlock: context.profile.skillsBlock
        )
        await runPlan(.build, applicationID: applicationID, prompt: prompt,
                      message: "Building the tailored résumé", label: "tailoring-plan",
                      failure: "Couldn't read a plan from that run",
                      success: { "Built \($0) change\($0 == 1 ? "" : "s") to review." },
                      application: context.application)
    }

    func reconcile(applicationID: UUID, pastedReply: String) async {
        guard let context = context(for: applicationID),
              !pastedReply.trimmed.isEmpty,
              !isRunning(.reconcile, for: applicationID) else { return }

        let prompt = PromptBuilder.tailoringReconciliationPrompt(
            pastedReply: pastedReply.trimmed,
            application: context.application,
            allExperiences: context.experiences,
            employments: context.employments
        )
        await runPlan(.reconcile, applicationID: applicationID, prompt: prompt,
                      message: "Reconciling tailoring suggestion", label: "tailoring-reconcile",
                      failure: "Couldn't extract any changes from that suggestion",
                      success: { "Found \($0) change\($0 == 1 ? "" : "s") to review." },
                      application: context.application,
                      pastedText: pastedReply)
    }

    private func runPlan(_ job: Job, applicationID: UUID, prompt: String, message: String, label: String,
                         failure: String, success: @escaping (Int) -> String,
                         application: JobApplication, pastedText: String? = nil) async {
        await run(job, for: applicationID, message: message) { backend in
            let attempt = try await backend.runStructured(
                prompt: prompt,
                schema: PromptBuilder.planSchemaSummary,
                parse: TailoringPlan.parse(from:)
            )
            guard let plan = attempt.value, !plan.isEmpty else {
                return .failure(self.unparseableMessage(attempt.raw, label: label,
                                                        application: application, what: failure))
            }
            var count = 0
            self.mutate(applicationID) { target in
                // Applied markers belong to the plan they were recorded against,
                // so a fresh plan starts with none.
                let session = TailoringSession(
                    pastedText: pastedText ?? TailoringSession.decode(target.tailoringPlanData)?.pastedText ?? "",
                    plan: plan,
                    appliedChangeIDs: []
                )
                target.tailoringPlanData = session.encoded()
                count = plan.replacements?.count ?? 0
            }
            return .success(success(count))
        }
    }

    // MARK: - Reviewing the rendered PDF

    /// Checks the résumé that was actually produced. Until a PDF exists the
    /// skill treats the two-page fit as an estimate; this is where it stops
    /// being one.
    func reviewRenderedResume(applicationID: UUID) async {
        guard let store, let context = context(for: applicationID),
              !isRunning(.review, for: applicationID) else { return }
        guard let document = store.documents.first(where: {
            $0.applicationID == applicationID && $0.kindRaw == GeneratedDocumentKind.resume.rawValue
        }) else {
            monitor?.fail("Generate the résumé PDF first.")
            return
        }
        guard let rendered = ResumePDFInspector.inspect(path: document.pdfPath) else {
            monitor?.fail("Couldn't read \(document.pdfPath.isEmpty ? "the résumé PDF" : document.pdfPath). Build it again.")
            return
        }

        // Only what the document actually contains. A check on the rendered file
        // has no business rewriting a bullet that isn't on it — that is the
        // build's job, with the whole pool in view.
        let selected = context.application.selectedExperienceIDs
            .union(context.application.selectedProjectIDs)
        let prompt = PromptBuilder.tailoringReviewPrompt(
            application: context.application,
            brief: context.application.tailoringBrief,
            rendered: rendered,
            renderedExperiences: context.experiences.filter { selected.contains($0.id) },
            employments: context.employments,
            globalSkillsBlock: context.profile.skillsBlock
        )
        let path = document.pdfPath
        // Checking is meant to be repeated until the document is sound.
        let round = (context.application.tailoringReview?.round ?? 0) + 1

        await run(.review, for: applicationID, message: "Reviewing the rendered résumé") { backend in
            let attempt = try await backend.runStructured(
                prompt: prompt,
                schema: PromptBuilder.reviewSchemaSummary,
                parse: { TailoringReview.parse(from: $0, pageCount: rendered.pageCount,
                                               documentPath: path, round: round) }
            )
            guard let review = attempt.value else {
                return .failure(self.unparseableMessage(attempt.raw, label: "tailoring-review",
                                                        application: context.application,
                                                        what: "the résumé review"))
            }
            self.mutate(applicationID) { application in
                application.tailoringReviewData = review.encoded()
            }
            return review.isClean ? .success(review.summary) : .failure(review.summary)
        }
    }

    // MARK: - Running

    private enum Outcome {
        case success(String)
        case failure(String)
    }

    private func run(_ job: Job, for applicationID: UUID, message: String,
                     work: @escaping (AIBackend) async throws -> Outcome) async {
        guard let backend = AIBackend.resolve(settings: settings) else { return }
        let key = "\(job.rawValue):\(applicationID.uuidString)"
        let label = applicationLabel(applicationID)
        begin(job, for: applicationID)
        monitor?.start("\(message) — \(label)…", key: key)
        do {
            switch try await work(backend) {
            case .success(let text): monitor?.succeed("\(label): \(text)", key: key)
            case .failure(let text): monitor?.fail("\(label): \(text)", key: key)
            }
        } catch {
            monitor?.fail("\(label): \(error.localizedDescription)", key: key)
        }
        end(job, for: applicationID)
    }

    private func begin(_ job: Job, for applicationID: UUID) {
        jobs[applicationID, default: []].insert(job)
    }

    private func end(_ job: Job, for applicationID: UUID) {
        jobs[applicationID]?.remove(job)
        if jobs[applicationID]?.isEmpty == true { jobs.removeValue(forKey: applicationID) }
    }

    /// Exposed so tests can exercise the per-application bookkeeping without a
    /// CLI on the other end.
    func beginForTesting(_ job: Job, for applicationID: UUID) { begin(job, for: applicationID) }
    func endForTesting(_ job: Job, for applicationID: UUID) { end(job, for: applicationID) }

    // MARK: - Store access

    private struct Context {
        let application: JobApplication
        let experiences: [ExperienceBullet]
        let employments: [Employment]
        let masterResume: MasterResume?
        let profile: ResumeProfile
        let backend: AIBackend
    }

    private func context(for applicationID: UUID) -> Context? {
        guard let store,
              let application = store.applications.first(where: { $0.id == applicationID }),
              let backend = AIBackend.resolve(settings: settings) else { return nil }
        return Context(
            application: application,
            experiences: ExperienceScope.visible(store.experiences, to: applicationID),
            employments: store.employments,
            masterResume: application.sourceMasterResumeID.flatMap { id in
                store.masterResumes.first { $0.id == id }
            },
            profile: store.profile,
            backend: backend
        )
    }

    /// Applies a change to the *current* record — never to a snapshot taken when
    /// the run started, which may be minutes stale by now — then writes it out.
    private func mutate(_ applicationID: UUID, _ body: (inout JobApplication) -> Void) {
        guard let store, let index = store.applications.firstIndex(where: { $0.id == applicationID }) else { return }
        var application = store.applications[index]
        body(&application)
        application.updatedAt = Date()
        store.applications[index] = application
        persist(application)
    }

    private func persist(_ application: JobApplication) {
        guard let store, let settings,
              let root = try? WorkspaceService.workspaceURL(settings: settings) else { return }
        let documents = store.documents.filter { $0.applicationID == application.id }
        let monitor = monitor
        Task.detached(priority: .utility) {
            do {
                try WorkspaceSyncService.writeApplicationFiles(application, documents: documents, root: root)
            } catch {
                let message = error.localizedDescription
                await MainActor.run { monitor?.fail(message) }
            }
        }
    }

    private func applicationLabel(_ applicationID: UUID) -> String {
        store?.applications.first { $0.id == applicationID }?.displayTitle ?? "Application"
    }

    private func unparseableMessage(_ raw: String, label: String,
                                    application: JobApplication, what: String) -> String {
        guard !raw.trimmed.isEmpty else {
            return "The AI CLI returned nothing. Check Settings → Tools, then try again."
        }
        let saved = AIResponseArchive.saveUnparseable(raw, label: label, application: application, settings: settings)
        let suffix = saved.map { " — raw reply saved to ai-responses/\($0)" } ?? ""
        return "Couldn't read \(what)\(suffix)."
    }

    /// Records the Q&A in the application's notes so the facts are visible
    /// outside the tailor and travel with Copy Context.
    private func appendAnswersToNotes(_ questionIDs: [UUID], brief: TailoringBrief,
                                      on application: inout JobApplication) {
        let sent = Set(questionIDs)
        let answered = brief.questions.filter { sent.contains($0.id) && $0.isAnswered }
        guard !answered.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let body = answered
            .map { "**Q:** \($0.question)\n**A:** \($0.answer.trimmed)" }
            .joined(separator: "\n\n")
        let block = "## Tailoring Q&A — \(formatter.string(from: Date()))\n\(body)"
        application.notes = application.notes.trimmed.isEmpty ? block : "\(application.notes)\n\n\(block)"
    }
}

/// Shared encoding for the curated-suggestion sidecar, used by both the editor
/// and the runner.
enum CuratedSuggestionCodec {
    static func encode(_ suggestions: [CuratedBulletSuggestion]) -> String {
        guard let data = try? JSONEncoder().encode(suggestions),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    static func decode(_ json: String) -> [CuratedBulletSuggestion] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let suggestions = try? JSONDecoder().decode([CuratedBulletSuggestion].self, from: data) else { return [] }
        return suggestions
    }
}
