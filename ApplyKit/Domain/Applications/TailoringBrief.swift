//
//  TailoringBrief.swift
//  ApplyKit
//
//  Stage 1 of the Resume Tailor: the decision brief. Judges fit, application
//  priority, and how much tailoring time is worth spending, then proposes the
//  content plan Stage 2 turns into a `TailoringPlan`. Produced by
//  `PromptBuilder.tailoringBriefPrompt` → `runAI`, refined by the clarify loop
//  (`PromptBuilder.tailoringClarifyPrompt`).
//

import Foundation

struct TailoringBrief: Codable, Equatable {
    /// Approximate fit out of 10 in 0.5 increments. A judgment aid, never a
    /// probability of interview.
    var fitScore: Double?
    /// `low` | `medium` | `high`.
    var fitConfidence: String?
    /// `High` | `Normal` | `Low` | `Skip` — see `TailoringPriority`.
    var recommendedPriority: String?
    /// `Minimal` | `Standard` | `Deep` — see `TailoringInvestment`.
    var investmentTier: String?
    /// Human-readable time range for the recommended tier, e.g. "20–35 minutes".
    var investmentTime: String?
    /// Whether extra tailoring can change the outcome for this role.
    var effortRationale: String?
    /// The single positioning thesis the résumé should communicate.
    var candidateStory: String?
    var strongMatches: [Match]
    var gaps: [Gap]
    var plan: ProposedPlan
    /// Factual and recall questions, answered in the brief panel. Ids are minted
    /// locally on parse so answers survive re-decoding.
    var questions: [TailoringQuestion]
    /// Facts the clarify loop established from the candidate's answers. Stage 2
    /// decides how they reach the résumé.
    var recalledFacts: [RecalledFact]
    /// Free-form direction for the build, written by the candidate — e.g. "fold
    /// the Protocol Buffers fact into the Tuya bullet rather than adding one".
    var buildNotes: String
    /// Only present when Stage 1 ran with web research enabled.
    var researchNotes: [ResearchNote]?
    var generatedAt: Date
    /// How many clarify passes have run. Capped by `maxClarifyRounds`.
    var clarifyRound: Int

    static let maxClarifyRounds = 5

    struct Match: Codable, Equatable {
        var claim: String
        var evidence: String?
        /// Set when the match is grounded in a specific bullet, so the UI can
        /// show its title instead of a bare id.
        var experienceID: UUID?

        enum CodingKeys: String, CodingKey {
            case claim
            case evidence
            case experienceID = "experience_id"
        }

        init(claim: String, evidence: String? = nil, experienceID: UUID? = nil) {
            self.claim = claim
            self.evidence = evidence
            self.experienceID = experienceID
        }

        /// A match with no claim is worthless, so that stays required; an id the
        /// model garbled is dropped rather than failing the match.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            claim = try c.decode(String.self, forKey: .claim)
            evidence = LossyDecode.string(from: c, forKey: .evidence)
            experienceID = try? c.decodeIfPresent(UUID.self, forKey: .experienceID)
        }
    }

    struct Gap: Codable, Equatable, Identifiable {
        /// Model-supplied slug, stable across clarify rounds so answers can
        /// retire the gap they resolve.
        var id: String
        /// `genuine` | `presentation` | `unknown` — see `TailoringGapKind`.
        var kind: String
        var text: String
        var mitigation: String?

        var gapKind: TailoringGapKind { TailoringGapKind(rawValue: kind) ?? .unknown }

        init(id: String, kind: TailoringGapKind = .unknown, text: String, mitigation: String? = nil) {
            self.id = id
            self.kind = kind.rawValue
            self.text = text
            self.mitigation = mitigation
        }

        /// Only `text` really matters: a missing id is derived from it, and an
        /// unrecognized kind degrades to `unknown` at read time.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = try c.decode(String.self, forKey: .text)
            kind = LossyDecode.string(from: c, forKey: .kind) ?? TailoringGapKind.unknown.rawValue
            mitigation = LossyDecode.string(from: c, forKey: .mitigation)
            if let supplied = LossyDecode.string(from: c, forKey: .id)?.trimmed, !supplied.isEmpty {
                id = supplied
            } else {
                id = Self.slug(from: text)
            }
        }

        /// Stable fallback id so a gap without one still survives clarify rounds.
        private static func slug(from text: String) -> String {
            let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.prefix(4)
            let slug = words.joined(separator: "-")
            return slug.isEmpty ? UUID().uuidString : slug
        }
    }

    struct ProposedPlan: Codable, Equatable {
        var summaryDirection: String?
        var skillsDirection: String?
        var selections: [Item]
        var rewrites: [Item]
        var exclusions: [Item]

        var hasContent: Bool {
            summaryDirection != nil || skillsDirection != nil
                || !selections.isEmpty || !rewrites.isEmpty || !exclusions.isEmpty
        }

        struct Item: Codable, Equatable {
            var experienceID: UUID?
            /// Fallback label when the model couldn't resolve an id.
            var label: String?
            var reason: String?

            enum CodingKeys: String, CodingKey {
                case experienceID = "experience_id"
                case label
                case reason
            }
        }

        enum CodingKeys: String, CodingKey {
            case summaryDirection = "summary_direction"
            case skillsDirection = "skills_direction"
            case selections
            case rewrites
            case exclusions
        }

        init(summaryDirection: String? = nil, skillsDirection: String? = nil,
             selections: [Item] = [], rewrites: [Item] = [], exclusions: [Item] = []) {
            self.summaryDirection = summaryDirection
            self.skillsDirection = skillsDirection
            self.selections = selections
            self.rewrites = rewrites
            self.exclusions = exclusions
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            summaryDirection = LossyDecode.string(from: c, forKey: .summaryDirection)
            skillsDirection = LossyDecode.string(from: c, forKey: .skillsDirection)
            selections = LossyDecode.array(Item.self, from: c, forKey: .selections)
            rewrites = LossyDecode.array(Item.self, from: c, forKey: .rewrites)
            exclusions = LossyDecode.array(Item.self, from: c, forKey: .exclusions)
        }
    }

    struct ResearchNote: Codable, Equatable {
        var claim: String
        var sourceURL: String?
        /// True when the model inferred rather than sourced the claim.
        var isInference: Bool?

        enum CodingKeys: String, CodingKey {
            case claim
            case sourceURL = "source_url"
            case isInference = "inference"
        }
    }

    enum CodingKeys: String, CodingKey {
        case fitScore = "fit_score"
        case fitConfidence = "fit_confidence"
        case recommendedPriority = "recommended_priority"
        case investmentTier = "investment_tier"
        case investmentTime = "investment_time"
        case effortRationale = "effort_rationale"
        case candidateStory = "candidate_story"
        case strongMatches = "strong_matches"
        case gaps
        case plan
        case questions
        case recalledFacts = "recalled_facts"
        case buildNotes = "build_notes"
        case researchNotes = "research_notes"
        case generatedAt = "generated_at"
        case clarifyRound = "clarify_round"
    }

    /// An empty brief, to merge a pasted reply's judgment into when the
    /// application has never run Stage 1.
    init() {
        strongMatches = []
        gaps = []
        plan = ProposedPlan()
        questions = []
        recalledFacts = []
        buildNotes = ""
        generatedAt = Date()
        clarifyRound = 0
    }

    /// Every field is read leniently: a model that quotes its score, invents a
    /// field, or malforms one list entry still yields a usable brief. Only a
    /// reply with no recognizable content at all is rejected (see `hasContent`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fitScore = LossyDecode.double(from: c, forKey: .fitScore)
        fitConfidence = LossyDecode.string(from: c, forKey: .fitConfidence)
        recommendedPriority = LossyDecode.string(from: c, forKey: .recommendedPriority)
        investmentTier = LossyDecode.string(from: c, forKey: .investmentTier)
        investmentTime = LossyDecode.string(from: c, forKey: .investmentTime)
        effortRationale = LossyDecode.string(from: c, forKey: .effortRationale)
        candidateStory = LossyDecode.string(from: c, forKey: .candidateStory)
        strongMatches = LossyDecode.array(Match.self, from: c, forKey: .strongMatches)
        gaps = LossyDecode.array(Gap.self, from: c, forKey: .gaps)
        plan = (try? c.decodeIfPresent(ProposedPlan.self, forKey: .plan)) ?? ProposedPlan()
        questions = LossyDecode.array(TailoringQuestion.self, from: c, forKey: .questions)
        recalledFacts = LossyDecode.array(RecalledFact.self, from: c, forKey: .recalledFacts)
        buildNotes = LossyDecode.string(from: c, forKey: .buildNotes) ?? ""
        let notes = LossyDecode.array(ResearchNote.self, from: c, forKey: .researchNotes)
        researchNotes = notes.isEmpty ? nil : notes
        // Absent on a fresh model reply; only the persisted sidecar carries them.
        generatedAt = (try? c.decodeIfPresent(Date.self, forKey: .generatedAt)) ?? Date()
        clarifyRound = (try? c.decodeIfPresent(Int.self, forKey: .clarifyRound)) ?? 0
    }
}

/// One question the tailor asks before drafting: either verifying an ambiguous
/// fact, or probing for experience that never made it into the bank.
struct TailoringQuestion: Codable, Equatable, Identifiable {
    var id: UUID
    /// 1 for Stage 1's questions, 2+ for each clarify round's follow-ups.
    var round: Int
    /// `fact` | `recall` — see `TailoringQuestionKind`.
    var kind: String
    /// The `Gap.id` a recall question probes, when it targets one.
    var gapID: String?
    var question: String
    var answer: String
    var answeredAt: Date?
    /// The `CuratedBulletSuggestion` the clarify pass drafted from this answer.
    var draftID: UUID?
    /// When this answer was last handed to a clarify pass. Answers are queued by
    /// this, not by round number — you can answer an early question late, and it
    /// still gets sent.
    var sentAt: Date?

    var questionKind: TailoringQuestionKind { TailoringQuestionKind(rawValue: kind) ?? .fact }
    var isAnswered: Bool { !answer.trimmed.isEmpty }

    enum CodingKeys: String, CodingKey {
        case id
        case round
        case kind
        case gapID = "gap_id"
        case question
        case answer
        case answeredAt = "answered_at"
        case draftID = "draft_id"
        case sentAt = "sent_at"
    }

    init(id: UUID = UUID(), round: Int = 1, kind: TailoringQuestionKind = .fact,
         gapID: String? = nil, question: String, answer: String = "",
         answeredAt: Date? = nil, draftID: UUID? = nil, sentAt: Date? = nil) {
        self.id = id
        self.round = round
        self.kind = kind.rawValue
        self.gapID = gapID
        self.question = question
        self.answer = answer
        self.answeredAt = answeredAt
        self.draftID = draftID
        self.sentAt = sentAt
    }

    /// The model returns questions without ids or rounds; both are filled in
    /// locally so a typed answer stays attached across re-decodes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        round = try c.decodeIfPresent(Int.self, forKey: .round) ?? 1
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? TailoringQuestionKind.fact.rawValue
        gapID = try c.decodeIfPresent(String.self, forKey: .gapID)
        question = try c.decode(String.self, forKey: .question)
        answer = try c.decodeIfPresent(String.self, forKey: .answer) ?? ""
        answeredAt = try c.decodeIfPresent(Date.self, forKey: .answeredAt)
        draftID = try c.decodeIfPresent(UUID.self, forKey: .draftID)
        sentAt = try? c.decodeIfPresent(Date.self, forKey: .sentAt)
    }
}

enum TailoringQuestionKind: String, StoredStringEnum {
    /// Verifies something ambiguous in the existing evidence.
    case fact
    /// Probes for experience the bank doesn't cover.
    case recall
}

enum TailoringGapKind: String, StoredStringEnum {
    /// A real experience or qualification gap wording cannot fix.
    case genuine
    /// The evidence exists but the résumé doesn't show it.
    case presentation
    /// Unresolved — one focused question could settle it.
    case unknown
}

/// The skill's application-priority scale. Judged and stored because it shapes
/// the recommended tailoring effort, but not shown or applied to the
/// application's own Priority field.
enum TailoringPriority: String, StoredStringEnum {
    case high = "High"
    case normal = "Normal"
    case low = "Low"
    case skip = "Skip"
}

enum TailoringInvestment: String, StoredStringEnum {
    case minimal = "Minimal"
    case standard = "Standard"
    case deep = "Deep"
}

extension TailoringBrief {
    /// True when the decode found something worth showing. Guards against
    /// latching onto a stray `{}` in the reply's prose now that every field is
    /// optional.
    var hasContent: Bool {
        fitScore != nil || recommendedPriority != nil || investmentTier != nil
            || candidateStory != nil || effortRationale != nil
            || !strongMatches.isEmpty || !gaps.isEmpty || !questions.isEmpty
            || !recalledFacts.isEmpty || !buildNotes.trimmed.isEmpty
            || plan.summaryDirection != nil || plan.skillsDirection != nil
            || !plan.selections.isEmpty || !plan.rewrites.isEmpty || !plan.exclusions.isEmpty
    }

    static func parse(from response: String) -> TailoringBrief? {
        for candidate in AIJSONResponse.objectCandidates(in: AIJSONResponse.stripCodeFence(response)) {
            guard let data = candidate.data(using: .utf8),
                  let brief = try? JSONDecoder().decode(TailoringBrief.self, from: data),
                  brief.hasContent else { continue }
            return brief
        }
        return nil
    }

    static func decode(_ json: String) -> TailoringBrief? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TailoringBrief.self, from: data)
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    var unansweredQuestions: [TailoringQuestion] { questions.filter { !$0.isAnswered } }

    var answeredQuestions: [TailoringQuestion] { questions.filter(\.isAnswered) }

    /// Answers no clarify pass has seen yet — the ones it should react to.
    /// Keyed off `sentAt` rather than the round, so answering an earlier
    /// question after a later round still queues it.
    var pendingAnswers: [TailoringQuestion] {
        questions.filter { $0.isAnswered && $0.sentAt == nil }
    }

    /// Marks answers as handed to a clarify pass so they aren't sent twice.
    mutating func markAnswersSent(_ ids: [UUID]) {
        let sent = Set(ids)
        let now = Date()
        for index in questions.indices where sent.contains(questions[index].id) && questions[index].isAnswered {
            questions[index].sentAt = now
        }
    }

    var canClarifyFurther: Bool { clarifyRound < Self.maxClarifyRounds }

    var genuineGaps: [Gap] { gaps.filter { $0.gapKind == .genuine } }

    var priority: TailoringPriority? { recommendedPriority.flatMap(TailoringPriority.init) }

    /// Score rendered the way the skill states it, e.g. "7.5/10".
    var fitScoreText: String? { FitScore.text(fitScore) }

    mutating func setAnswer(_ text: String, for questionID: UUID) {
        guard let index = questions.firstIndex(where: { $0.id == questionID }) else { return }
        guard questions[index].answer != text else { return }
        questions[index].answer = text
        questions[index].answeredAt = text.trimmed.isEmpty ? nil : Date()
        // Edited after being sent? It's pending again.
        questions[index].sentAt = nil
    }

    /// What folding a clarify pass into the brief actually changed.
    struct ClarifyResult: Equatable {
        var appendedQuestions = 0
        /// Follow-ups that restated something already asked, and were refused.
        var skippedDuplicates = 0
        /// Follow-ups about logistics rather than evidence, and were refused.
        var skippedLogistical = 0
        /// Facts the answers established, for Stage 2 to use.
        var recordedFacts = 0
    }

    /// Drops questions about things no answer could change on the résumé. The
    /// prompt forbids them; this is what makes it stick.
    mutating func dropLogisticalQuestions() {
        questions.removeAll { QuestionRelevance.isLogistical($0.question) }
    }

    /// Folds a clarify pass into the brief: replaces the gaps it revised, appends
    /// its follow-up questions at the next round, and advances the round counter.
    ///
    /// A question that restates one already asked is dropped. Models re-derive
    /// the same probe from the same gap, and asking the user to answer it twice
    /// is worse than asking nothing.
    @discardableResult
    mutating func apply(_ clarification: TailoringClarification) -> ClarifyResult {
        for updated in clarification.updatedGaps ?? [] {
            if let index = gaps.firstIndex(where: { $0.id == updated.id }) {
                gaps[index] = updated
            } else {
                gaps.append(updated)
            }
        }
        clarifyRound += 1

        var result = ClarifyResult()
        for fact in clarification.recalledFacts ?? [] where !fact.fact.trimmed.isEmpty {
            // A later pass re-reads the same answers and restates what it
            // learned, so without this the same fact accumulates a copy per
            // round — and each copy argues for itself in the build.
            if let index = recalledFacts.firstIndex(where: { RecalledFact.areEquivalent($0, fact) }) {
                recalledFacts[index] = fact
                continue
            }
            recalledFacts.append(fact)
            result.recordedFacts += 1
        }

        let nextRound = (questions.map(\.round).max() ?? 1) + 1
        for question in clarification.newQuestions ?? [] {
            let text = question.question.trimmed
            guard !text.isEmpty else { continue }
            guard !QuestionRelevance.isLogistical(text) else {
                result.skippedLogistical += 1
                continue
            }
            // Compare against everything asked so far, including the ones added
            // by this same pass.
            guard !questions.contains(where: { QuestionSimilarity.areEquivalent($0.question, text) }) else {
                result.skippedDuplicates += 1
                continue
            }
            var appended = question
            appended.round = nextRound
            questions.append(appended)
            result.appendedQuestions += 1
        }
        return result
    }

    /// Moves answers from a previous brief onto a freshly judged one.
    ///
    /// Re-analysing re-derives its own questions, but what the user typed is
    /// theirs: a question asked again keeps its answer, and answered questions
    /// the new brief didn't re-ask are kept as history so the clarify loop
    /// won't put them a second time.
    mutating func carryOverAnswers(from previous: TailoringBrief) {
        var unmatched = previous.answeredQuestions
        guard !unmatched.isEmpty else { return }

        for index in questions.indices {
            guard let match = unmatched.firstIndex(where: {
                QuestionSimilarity.areEquivalent($0.question, questions[index].question)
            }) else { continue }
            let previousAnswer = unmatched.remove(at: match)
            questions[index].answer = previousAnswer.answer
            questions[index].answeredAt = previousAnswer.answeredAt
            questions[index].sentAt = previousAnswer.sentAt
            questions[index].draftID = previousAnswer.draftID
        }

        // History first, new questions last — the same direction the clarify loop
        // appends in. Putting carried-over answers after the fresh questions
        // made a re-analysis look like it had reordered the conversation.
        questions.insert(contentsOf: unmatched.map { carried in
            var question = carried
            question.round = 1
            return question
        }, at: 0)
    }

    /// Gap ids some question already probes.
    var probedGapIDs: Set<String> {
        Set(questions.compactMap { $0.gapID?.trimmed }.filter { !$0.isEmpty })
    }

    /// Genuine gaps nothing has asked about yet — the ones worth probing.
    var unprobedGenuineGaps: [Gap] {
        let probed = probedGapIDs
        return genuineGaps.filter { !probed.contains($0.id) }
    }
}

/// Screens out questions the tailor has no business asking. Work authorization,
/// location, pay, and timing are things the candidate already knows and has
/// already decided; no answer to any of them changes a line of the résumé, so a
/// question spent there is one of three wasted.
enum QuestionRelevance {
    /// Phrases rather than bare words: "remote" alone appears in perfectly good
    /// technical questions ("remote debugging"), so matching it would cost real
    /// ones.
    private static let logisticalPhrases = [
        "work authorization", "authorized to work", "authorised to work", "legally eligible",
        "eligible to work", "right to work", "work permit", "visa", "sponsorship", "sponsor you",
        "relocate", "relocation", "willing to move",
        "onsite requirement", "on-site requirement", "hybrid requirement", "return to office",
        "willing to work onsite", "willing to work on-site", "willing to work hybrid",
        "willing to commute", "commute to", "based in", "located in", "reside in",
        "salary", "compensation expectation", "pay range", "notice period", "start date",
        "when could you start", "how interested", "how excited", "would you accept"
    ]

    static func isLogistical(_ question: String) -> Bool {
        let text = question.lowercased()
        return logisticalPhrases.contains { text.contains($0) }
    }
}

/// Decides whether two questions are asking the same thing. Deliberately blunt:
/// light stemming, stopwords dropped, then token overlap. A false positive costs
/// one skipped follow-up; a false negative costs the user answering a duplicate.
enum QuestionSimilarity {
    static func areEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let left = tokens(lhs)
        let right = tokens(rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return lhs.trimmed.lowercased() == rhs.trimmed.lowercased()
        }
        let shared = left.intersection(right).count
        guard shared >= 3 else { return false }
        return Double(shared) / Double(min(left.count, right.count)) >= 0.5
    }

    private static let stopWords: Set<String> = [
        "have", "you", "your", "any", "the", "and", "for", "with", "did", "does", "was", "were",
        "are", "that", "this", "there", "them", "they", "then", "than", "ever", "yes", "which",
        "what", "when", "who", "how", "why", "into", "from", "been", "being", "its", "it's",
        "about", "also", "even", "just", "own", "not", "but", "can", "could", "would", "should",
        "please", "describe", "tell", "detail", "details", "specific", "specifically", "used"
    ]

    private static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { stem(String($0)) }
            .filter { $0.count > 2 && !stopWords.contains($0) })
    }

    /// Crude suffix stripping so "triaged"/"triage" and "releases"/"release" match.
    private static func stem(_ word: String) -> String {
        for suffix in ["ing", "ed", "es", "s"] where word.count > suffix.count + 2 && word.hasSuffix(suffix) {
            return String(word.dropLast(suffix.count))
        }
        return word
    }
}

/// One clarify pass: what the answers changed, what still needs asking, and the
/// facts they established.
///
/// It deliberately does not draft bullets. Wording belongs to Stage 2, which
/// sees the whole résumé, the page budget, and the writing rules — a fact
/// drafted here in isolation becomes a standalone bullet even when it belongs
/// inside an existing one.
struct TailoringClarification: Codable, Equatable {
    var updatedGaps: [TailoringBrief.Gap]?
    var newQuestions: [TailoringQuestion]?
    var recalledFacts: [RecalledFact]?

    enum CodingKeys: String, CodingKey {
        case updatedGaps = "updated_gaps"
        case newQuestions = "new_questions"
        case recalledFacts = "recalled_facts"
    }

    static func parse(from response: String) -> TailoringClarification? {
        AIJSONResponse.decodeObject(TailoringClarification.self, from: response)
    }

    var isEmpty: Bool {
        (updatedGaps?.isEmpty ?? true) && (newQuestions?.isEmpty ?? true) && (recalledFacts?.isEmpty ?? true)
    }
}

enum FitScore {
    /// "7.5/10", or "8/10" for a whole number.
    ///
    /// Shown exactly as judged. Rounding to the nearest half-point here made
    /// the panel disagree with the model's own prose beside it — a 7.7 judgment
    /// displayed as "7.5" next to a finding that said "the 7.7 fit judgment".
    /// The half-point convention is asked for in the prompt instead.
    static func text(_ value: Double?) -> String? {
        guard let value else { return nil }
        let text = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(text)/10"
    }
}

/// Something true the candidate confirmed, in plain terms. Stage 2 decides
/// whether it becomes a new bullet or strengthens an existing one.
struct RecalledFact: Codable, Equatable, Identifiable {
    var id: UUID
    /// The answer this came from.
    var questionID: UUID?
    /// The bullet it belongs with, when it refines one already in the bank.
    var relatedBulletID: UUID?
    var fact: String
    /// Why it matters for this role.
    var relevance: String?
    /// Anything the candidate should double-check before it reaches a résumé.
    var confirmationNeeded: String?

    enum CodingKeys: String, CodingKey {
        case id
        case questionID = "question_id"
        case relatedBulletID = "related_bullet_id"
        case fact
        case relevance
        case confirmationNeeded = "confirmation_needed"
    }

    init(id: UUID = UUID(), questionID: UUID? = nil, relatedBulletID: UUID? = nil,
         fact: String, relevance: String? = nil, confirmationNeeded: String? = nil) {
        self.id = id
        self.questionID = questionID
        self.relatedBulletID = relatedBulletID
        self.fact = fact
        self.relevance = relevance
        self.confirmationNeeded = confirmationNeeded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        questionID = try? c.decodeIfPresent(UUID.self, forKey: .questionID)
        relatedBulletID = try? c.decodeIfPresent(UUID.self, forKey: .relatedBulletID)
        fact = try c.decode(String.self, forKey: .fact)
        relevance = LossyDecode.string(from: c, forKey: .relevance)
        confirmationNeeded = LossyDecode.string(from: c, forKey: .confirmationNeeded)
    }

    /// Two records of the same thing. A later clarify pass re-reads the same
    /// answers and restates what it learned, usually reworded — so identity is
    /// the answer it came from, or failing that the wording of the fact itself,
    /// compared the same way repeated questions are.
    static func areEquivalent(_ lhs: RecalledFact, _ rhs: RecalledFact) -> Bool {
        if let left = lhs.questionID, let right = rhs.questionID { return left == right }
        return QuestionSimilarity.areEquivalent(lhs.fact, rhs.fact)
    }
}
