//
//  TailoringReview.swift
//  ApplyKit
//
//  The skill's last step, which the app could not run until now: checking the
//  résumé that was actually rendered.
//
//  `references/output-and-validation.md` is explicit that the two-page fit is an
//  estimate until a PDF exists, and that a rendered file should be inspected for
//  pagination, wrapping, orphaned headings, spacing, broken links, and whether
//  extracted text preserves content and reading order. Page count is measured
//  locally (see `ResumePDFInspector`); everything else is judged from the text
//  the PDF actually yields.
//

import Foundation

struct TailoringReview: Codable, Equatable {
    /// Measured from the file, never taken from the model.
    var pageCount: Int
    /// The skill's own final-validation checklist, run against the rendered
    /// document. Feeds `findings` and `edits`; the headline score comes from
    /// `fitScore` instead — see its doc comment.
    var checks: [Check]
    /// Fit re-judged against what actually ended up on the rendered résumé,
    /// using the same 0–10 rubric as the Stage 1 brief (`TailoringBrief.fitScore`).
    /// The build can drift from the plan the brief judged — a rewrite softened,
    /// a bullet dropped for space — so this is asked for again here rather than
    /// carried over.
    var fitScore: Double?
    /// `low` | `medium` | `high`, same meaning as the brief's.
    var fitConfidence: String?
    /// `TailoringReadiness` raw value.
    var verdict: String?
    var findings: [Finding]
    /// What the extracted text suggests about ATS readability.
    var extractionNote: String?
    var checkedAt: Date
    /// The PDF this refers to, so a stale review can be spotted.
    var documentPath: String
    /// Which pass this was. Checking is meant to be repeated until the document
    /// is sound, so the count is worth showing.
    var round: Int
    /// The findings, expressed as résumé edits you can apply — same shape as a
    /// tailoring plan, so they review and apply through the same list. A finding
    /// about layout or extraction usually has no edit; one about duplicated
    /// content usually does.
    var edits: TailoringPlan?

    /// One question from `references/output-and-validation.md`'s final
    /// validation, and how the rendered document answers it.
    struct Check: Codable, Equatable, Identifiable {
        var id: UUID
        /// Which part of the checklist it came from.
        var section: String?
        /// The checklist question, as the skill words it.
        var question: String
        /// `pass` | `fail` | `unclear`
        var status: String
        var note: String?

        var checkStatus: Status { Status(rawValue: status) ?? .unclear }

        enum Status: String, StoredStringEnum { case pass, fail, unclear }

        enum CodingKeys: String, CodingKey { case id, section, question, status, note }

        init(id: UUID = UUID(), section: String? = nil, question: String,
             status: Status = .unclear, note: String? = nil) {
            self.id = id
            self.section = section
            self.question = question
            self.status = status.rawValue
            self.note = note
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
            section = LossyDecode.string(from: c, forKey: .section)
            question = try c.decode(String.self, forKey: .question)
            status = LossyDecode.string(from: c, forKey: .status) ?? Status.unclear.rawValue
            note = LossyDecode.string(from: c, forKey: .note)
        }
    }

    struct Finding: Codable, Equatable, Identifiable {
        var id: UUID
        /// `blocker` | `fix` | `note` — see `TailoringFindingSeverity`.
        var severity: String
        var text: String
        /// What to do about it, when the reviewer can say.
        var fix: String?

        var findingSeverity: TailoringFindingSeverity {
            TailoringFindingSeverity(rawValue: severity) ?? .note
        }

        enum CodingKeys: String, CodingKey {
            case id, severity, text, fix
        }

        init(id: UUID = UUID(), severity: TailoringFindingSeverity = .note, text: String, fix: String? = nil) {
            self.id = id
            self.severity = severity.rawValue
            self.text = text
            self.fix = fix
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
            severity = LossyDecode.string(from: c, forKey: .severity) ?? TailoringFindingSeverity.note.rawValue
            text = try c.decode(String.self, forKey: .text)
            fix = LossyDecode.string(from: c, forKey: .fix)
        }
    }

    enum CodingKeys: String, CodingKey {
        case pageCount = "page_count"
        case checks
        case fitScore = "fit_score"
        case fitConfidence = "fit_confidence"
        case verdict
        case findings
        case extractionNote = "extraction_note"
        case checkedAt = "checked_at"
        case documentPath = "document_path"
        case round
        case edits
    }

    init(pageCount: Int, checks: [Check] = [], fitScore: Double? = nil, fitConfidence: String? = nil,
         verdict: String? = nil, findings: [Finding] = [], extractionNote: String? = nil,
         checkedAt: Date = Date(), documentPath: String = "", round: Int = 1, edits: TailoringPlan? = nil) {
        self.pageCount = pageCount
        self.checks = checks
        self.fitScore = fitScore
        self.fitConfidence = fitConfidence
        self.verdict = verdict
        self.findings = findings
        self.extractionNote = extractionNote
        self.checkedAt = checkedAt
        self.documentPath = documentPath
        self.round = round
        self.edits = edits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pageCount = (try? c.decodeIfPresent(Int.self, forKey: .pageCount)) ?? 0
        checks = LossyDecode.array(Check.self, from: c, forKey: .checks)
        fitScore = LossyDecode.double(from: c, forKey: .fitScore)
        fitConfidence = LossyDecode.string(from: c, forKey: .fitConfidence)
        verdict = LossyDecode.string(from: c, forKey: .verdict)
        findings = LossyDecode.array(Finding.self, from: c, forKey: .findings)
        extractionNote = LossyDecode.string(from: c, forKey: .extractionNote)
        checkedAt = (try? c.decodeIfPresent(Date.self, forKey: .checkedAt)) ?? Date()
        documentPath = LossyDecode.string(from: c, forKey: .documentPath) ?? ""
        round = (try? c.decodeIfPresent(Int.self, forKey: .round)) ?? 1
        edits = try? c.decodeIfPresent(TailoringPlan.self, forKey: .edits)
    }
}

enum TailoringFindingSeverity: String, StoredStringEnum {
    /// Do not submit like this.
    case blocker
    /// Worth fixing before sending.
    case fix
    /// Observation only.
    case note
}

extension TailoringReview {
    static func parse(from response: String, pageCount: Int, documentPath: String,
                      round: Int) -> TailoringReview? {
        guard var review = AIJSONResponse.decodeObject(TailoringReview.self, from: response) else { return nil }
        // The file is the authority on length, and the app on which pass this is.
        review.pageCount = pageCount
        review.documentPath = documentPath
        review.checkedAt = Date()
        review.round = round
        if review.edits?.isEmpty == true { review.edits = nil }
        return review
    }

    static func decode(_ json: String) -> TailoringReview? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TailoringReview.self, from: data)
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    var blockers: [Finding] { findings.filter { $0.findingSeverity == .blocker } }

    /// Anything asking to be changed — a `note` is an observation, not a task.
    var actionable: [Finding] { findings.filter { $0.findingSeverity != .note } }

    var isOverPageBudget: Bool { pageCount > 2 }

    /// Nothing left to fix in the document itself.
    var isClean: Bool { actionable.isEmpty && !isOverPageBudget }

    /// One line for the step list.
    var passedChecks: [Check] { checks.filter { $0.checkStatus == .pass } }
    var failedChecks: [Check] { checks.filter { $0.checkStatus == .fail } }
    var unclearChecks: [Check] { checks.filter { $0.checkStatus == .unclear } }

    /// The headline number is `fitScore` itself — the same fit check as Stage 1,
    /// re-run against what actually ended up on the rendered résumé. `score` is
    /// kept as the name the UI already reads (mirrors `TailoringBrief.fitScore`).
    var score: Double? { fitScore }

    /// "8.5/10", in the same form as the brief's `fitScoreText`.
    var scoreText: String? {
        guard let score else { return nil }
        let rounded = (score * 2).rounded() / 2
        let whole = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "\(whole)/10"
    }

    /// "7 of 9 checks pass", the sentence behind the findings — no longer what
    /// the score is computed from, but still worth showing alongside it.
    var checksSummary: String? {
        let decided = passedChecks.count + failedChecks.count
        guard decided > 0 else { return nil }
        var text = "\(passedChecks.count) of \(decided) skill check\(decided == 1 ? "" : "s") pass"
        if !unclearChecks.isEmpty { text += ", \(unclearChecks.count) unclear" }
        return text
    }

    var summary: String {
        var parts = ["Check #\(round)"]
        if let scoreText { parts.append(scoreText) }
        parts.append("\(pageCount) page\(pageCount == 1 ? "" : "s")")
        if isOverPageBudget { parts.append("over the two-page cap") }
        if !findings.isEmpty {
            let blockers = blockers.count
            parts.append(blockers > 0
                ? "\(findings.count) finding\(findings.count == 1 ? "" : "s"), \(blockers) blocking"
                : "\(findings.count) finding\(findings.count == 1 ? "" : "s")")
        }
        if let verdict = verdict?.trimmed, !verdict.isEmpty { parts.append(verdict) }
        return parts.joined(separator: " · ")
    }
}

/// Everything after the brief, gathered for the step list: what the plan
/// proposed, how much of it has been applied, whether a PDF exists, and what the
/// last check of that PDF found.
struct TailoringProgress {
    var hasPlan = false
    var appliedChanges = 0
    var pendingChanges = 0
    /// Split of `pendingChanges` by where they came from, so a count in the
    /// panel can be reconciled with what the sheet shows.
    var pendingFromBuild = 0
    var pendingFromCheck = 0
    var hasRenderedPDF = false
    var isReviewing = false
    var review: TailoringReview?
    /// True when the PDF has been rebuilt since the review ran, so its findings
    /// describe a file that no longer exists.
    var isReviewStale = false

    /// What to do now. The step list and the footer both read this, so they
    /// cannot disagree about where you are — which they did when each decided
    /// for itself.
    enum NextStep: Equatable {
        case build
        case reviewChanges(Int)
        case generatePDF
        case checkPDF(isRecheck: Bool)
        case done

        var title: String {
            switch self {
            case .build: "Next: build the tailored résumé"
            case .reviewChanges(let count): "Next: review \(count) proposed change\(count == 1 ? "" : "s")"
            case .generatePDF: "Next: generate the résumé PDF"
            case .checkPDF(let isRecheck): isRecheck ? "Next: check the rebuilt PDF" : "Next: check the rendered PDF"
            case .done: "Ready to submit"
            }
        }

        /// Nil when the action lives elsewhere in the editor (the Documents
        /// section owns PDF generation).
        var actionLabel: String? {
            switch self {
            case .build: "Build Tailored Résumé"
            case .reviewChanges: "Review Changes"
            case .generatePDF: nil
            case .checkPDF: "Check Rendered PDF"
            case .done: nil
            }
        }
    }

    var nextStep: NextStep {
        if !hasPlan { return .build }
        if pendingChanges > 0 { return .reviewChanges(pendingChanges) }
        if !hasRenderedPDF { return .generatePDF }
        if review == nil { return .checkPDF(isRecheck: false) }
        if isReviewStale { return .checkPDF(isRecheck: true) }
        return review?.isClean == true ? .done : .reviewChanges(0)
    }

    var nextStepTitle: String { nextStep.title }
}
