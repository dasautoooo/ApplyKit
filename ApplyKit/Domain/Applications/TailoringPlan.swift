//
//  TailoringPlan.swift
//  ApplyKit
//

import Foundation

/// A structured set of resume edits. Produced either by the in-app Stage 2
/// builder (`PromptBuilder.tailoringBuildPrompt`) or by the local AI reconciler
/// (`PromptBuilder.tailoringReconciliationPrompt`), which maps a pasted ChatGPT
/// reply — including truncated `"…"` quotes — onto the application's real bullet
/// UUIDs. Both routes emit this same schema so they share
/// `buildTailoringChanges`.
///
/// Every field is optional; an omitted field means "leave the current value
/// unchanged". The explanatory fields (`summaryRationale`, `drops`, `readiness`,
/// `uncertainties`) are advisory: they are shown during review and never change
/// résumé content on their own.
struct TailoringPlan: Codable, Equatable {
    /// Tailored professional summary → `summaryText`.
    var summary: String?
    /// Tailored LaTeX skills block → `skillsBlockText` (raw LaTeX, not escaped).
    var skillsLatex: String?
    /// Resume section order as `ResumeSectionKind` raw values.
    var sectionOrder: [String]?
    /// Final ordered list of selected work-experience bullet ids.
    var orderedExperienceIDs: [UUID]?
    /// Final ordered list of selected project bullet ids.
    var orderedProjectIDs: [UUID]?
    /// Per-bullet tailored rewrites, applied as selected variants.
    var replacements: [Replacement]?
    /// Per-employment role-description decisions: whether to show the line and/or
    /// reword it.
    var roleDescriptions: [RoleDescription]?
    /// Clause-by-clause justification for `summary`, shown under the summary change.
    var summaryRationale: [SummaryClaim]?
    /// The strongest emphasis deliberately left out of the summary, and why.
    var deliberatelyOmitted: String?
    /// Bullets the plan drops, with an application-specific reason each. Dropping
    /// is already implied by absence from the ordered lists; this makes it reviewable.
    var drops: [Drop]?
    /// Bullets to create from facts confirmed during clarification. Only for
    /// facts that stand alone — one that strengthens existing evidence arrives
    /// as a `Replacement` instead.
    var newBullets: [NewBullet]?
    /// Submission-readiness verdict (see `TailoringReadiness`).
    var readiness: String?
    /// Facts that still need confirming before submitting.
    var uncertainties: [String]?

    struct Replacement: Codable, Equatable {
        var experienceID: UUID
        var text: String
        var name: String?
        var reason: String?
        /// Which hiring signal the rewrite improves (Relevance, Technical depth,
        /// Impact, Clarity, ATS terminology, Concision, Ownership).
        var signal: String?
        /// A fact the rewrite leans on that the user should verify, if any.
        var confirmationNeeded: String?

        enum CodingKeys: String, CodingKey {
            case experienceID = "experience_id"
            case text
            case name
            case reason
            case signal
            case confirmationNeeded = "confirmation_needed"
        }
    }

    /// One meaningful phrase of the tailored summary traced back to its evidence.
    struct SummaryClaim: Codable, Equatable {
        var phrase: String
        var evidence: String?
        var signal: String?
        var whyItEarnsSpace: String?

        enum CodingKeys: String, CodingKey {
            case phrase
            case evidence
            case signal
            case whyItEarnsSpace = "why_it_earns_space"
        }
    }

    /// A bullet the plan wants to add. It has no pool id yet — applying it is
    /// what creates one, and the user chooses whether it joins the shared bank
    /// or stays with this application.
    struct NewBullet: Codable, Equatable {
        var text: String
        var employmentID: UUID?
        var reason: String?
        var confirmationNeeded: String?

        enum CodingKeys: String, CodingKey {
            case text
            case employmentID = "employment_id"
            case reason
            case confirmationNeeded = "confirmation_needed"
        }

        init(text: String, employmentID: UUID? = nil, reason: String? = nil, confirmationNeeded: String? = nil) {
            self.text = text
            self.employmentID = employmentID
            self.reason = reason
            self.confirmationNeeded = confirmationNeeded
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = try c.decode(String.self, forKey: .text)
            employmentID = try? c.decodeIfPresent(UUID.self, forKey: .employmentID)
            reason = LossyDecode.string(from: c, forKey: .reason)
            confirmationNeeded = LossyDecode.string(from: c, forKey: .confirmationNeeded)
        }
    }

    struct Drop: Codable, Equatable {
        var experienceID: UUID
        var reason: String?

        enum CodingKeys: String, CodingKey {
            case experienceID = "experience_id"
            case reason
        }
    }

    /// A decision about an employment's role-description line. `include` toggles
    /// visibility (omit = leave as-is); `text` supplies a tailored override
    /// (omit = keep current wording).
    struct RoleDescription: Codable, Equatable {
        var employmentID: UUID
        var include: Bool?
        var text: String?

        enum CodingKeys: String, CodingKey {
            case employmentID = "employment_id"
            case include
            case text
        }
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case skillsLatex = "skills_latex"
        case sectionOrder = "section_order"
        case orderedExperienceIDs = "ordered_experience_ids"
        case orderedProjectIDs = "ordered_project_ids"
        case replacements
        case roleDescriptions = "role_descriptions"
        case summaryRationale = "summary_rationale"
        case deliberatelyOmitted = "deliberately_omitted"
        case drops
        case newBullets = "new_bullets"
        case readiness
        case uncertainties
    }

    init(summary: String? = nil, skillsLatex: String? = nil, sectionOrder: [String]? = nil,
         orderedExperienceIDs: [UUID]? = nil, orderedProjectIDs: [UUID]? = nil,
         replacements: [Replacement]? = nil, roleDescriptions: [RoleDescription]? = nil,
         summaryRationale: [SummaryClaim]? = nil, deliberatelyOmitted: String? = nil,
         drops: [Drop]? = nil, newBullets: [NewBullet]? = nil,
         readiness: String? = nil, uncertainties: [String]? = nil) {
        self.summary = summary
        self.skillsLatex = skillsLatex
        self.sectionOrder = sectionOrder
        self.orderedExperienceIDs = orderedExperienceIDs
        self.orderedProjectIDs = orderedProjectIDs
        self.replacements = replacements
        self.roleDescriptions = roleDescriptions
        self.summaryRationale = summaryRationale
        self.deliberatelyOmitted = deliberatelyOmitted
        self.drops = drops
        self.newBullets = newBullets
        self.readiness = readiness
        self.uncertainties = uncertainties
    }

    /// Read leniently, like `TailoringBrief`: one malformed replacement or one
    /// unparseable id must not cost the entire plan, since everything else in it
    /// is still applyable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = LossyDecode.string(from: c, forKey: .summary)
        skillsLatex = LossyDecode.string(from: c, forKey: .skillsLatex)
        let sections = LossyDecode.array(String.self, from: c, forKey: .sectionOrder)
        sectionOrder = sections.isEmpty ? nil : sections
        orderedExperienceIDs = Self.idList(from: c, forKey: .orderedExperienceIDs)
        orderedProjectIDs = Self.idList(from: c, forKey: .orderedProjectIDs)
        replacements = Self.nilIfEmpty(LossyDecode.array(Replacement.self, from: c, forKey: .replacements))
        roleDescriptions = Self.nilIfEmpty(LossyDecode.array(RoleDescription.self, from: c, forKey: .roleDescriptions))
        summaryRationale = Self.nilIfEmpty(LossyDecode.array(SummaryClaim.self, from: c, forKey: .summaryRationale))
        deliberatelyOmitted = LossyDecode.string(from: c, forKey: .deliberatelyOmitted)
        drops = Self.nilIfEmpty(LossyDecode.array(Drop.self, from: c, forKey: .drops))
        newBullets = Self.nilIfEmpty(LossyDecode.array(NewBullet.self, from: c, forKey: .newBullets))
        readiness = LossyDecode.string(from: c, forKey: .readiness)
        uncertainties = Self.nilIfEmpty(LossyDecode.array(String.self, from: c, forKey: .uncertainties))
    }

    private static func nilIfEmpty<T>(_ values: [T]) -> [T]? { values.isEmpty ? nil : values }

    /// An ordered id list, keeping only ids that actually parse.
    ///
    /// A missing key means "leave this selection alone". An explicitly empty
    /// list means "select nothing" and is honoured. But a list that had entries
    /// of which *none* parsed reads as unknown rather than empty — deselecting
    /// every bullet because the reply garbled its ids would be a destructive
    /// misreading.
    private static func idList(from container: KeyedDecodingContainer<CodingKeys>,
                               forKey key: CodingKeys) -> [UUID]? {
        guard container.contains(key) else { return nil }
        let raw = LossyDecode.array(String.self, from: container, forKey: key)
        if raw.isEmpty { return [] }
        let ids = raw.compactMap { UUID(uuidString: $0.trimmed) }
        return ids.isEmpty ? nil : ids
    }
}

/// The skill's submission-readiness verdicts. Stored as a raw string on the plan
/// so an unexpected value from the model degrades to "shown as written" rather
/// than failing the whole decode.
enum TailoringReadiness: String, StoredStringEnum {
    case ready = "Ready to submit"
    case minorCorrections = "Ready after minor corrections"
    case needsConfirmation = "Needs factual confirmation"
    case needsLayoutCheck = "Needs layout verification"
}

extension TailoringPlan {
    /// Decode a plan from a raw AI response, tolerating code fences and leading/
    /// trailing prose around the JSON object (mirrors `CoverLetterRenderer`).
    /// Returns `nil` when no decodable object is present.
    static func parse(from response: String) -> TailoringPlan? {
        AIJSONResponse.decodeObject(TailoringPlan.self, from: response)
    }

    /// True when the plan carries nothing actionable. Explanation-only fields
    /// (rationale, readiness, uncertainties) don't count — a plan that carries
    /// nothing but commentary has no edits to review.
    var isEmpty: Bool {
        summary == nil && skillsLatex == nil && sectionOrder == nil
            && orderedExperienceIDs == nil && orderedProjectIDs == nil
            && (replacements?.isEmpty ?? true) && (roleDescriptions?.isEmpty ?? true)
            && (newBullets?.isEmpty ?? true)
    }
}

/// Shared tolerance for AI replies that wrap their JSON in a code fence or in
/// leading/trailing prose. Used by every structured tailoring response.
enum AIJSONResponse {
    static func decodeObject<T: Decodable>(_ type: T.Type, from response: String) -> T? {
        for candidate in objectCandidates(in: stripCodeFence(response)) {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(type, from: data) { return decoded }
        }
        return nil
    }

    static func stripCodeFence(_ value: String) -> String {
        var text = value.trimmed
        // A reply can open with prose and *then* fence the JSON, so drop fence
        // lines wherever they are rather than only at the ends.
        guard text.contains("```") else { return text }
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmed.hasPrefix("```") }
        text = lines.joined(separator: "\n").trimmed
        return text
    }

    /// Every balanced `{…}` span in the text, largest-scope first. Braces inside
    /// strings don't count, so prose like `use {"a": 1} here` still yields the
    /// object — and a reply that emits two objects gives two candidates to try
    /// instead of one unparseable span from the first `{` to the last `}`.
    static func objectCandidates(in value: String) -> [String] {
        var candidates: [String] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for index in value.indices {
            let character = value[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                guard depth > 0 else { break }
                depth -= 1
                if depth == 0, let start {
                    candidates.append(String(value[start...index]))
                }
            default:
                break
            }
        }

        // An unterminated object (truncated reply) still deserves an attempt.
        if candidates.isEmpty, let start = value.firstIndex(of: "{") {
            candidates.append(String(value[start...]))
        }
        return candidates.sorted { $0.count > $1.count }
    }
}

/// Tolerant readers for AI-produced JSON. One malformed entry in a long reply
/// should cost that entry, not the whole brief or plan.
enum LossyDecode {
    /// Decodes an array element-by-element, dropping any element that fails.
    /// Returns an empty array when the key is missing or isn't an array at all.
    static func array<Element: Decodable, Key: CodingKey>(
        _ type: Element.Type, from container: KeyedDecodingContainer<Key>, forKey key: Key
    ) -> [Element] {
        guard var nested = try? container.nestedUnkeyedContainer(forKey: key) else { return [] }
        var elements: [Element] = []
        while !nested.isAtEnd {
            if let element = try? nested.decode(Element.self) {
                elements.append(element)
            } else if (try? nested.decode(SkippedElement.self)) == nil {
                // Can't even step over it — stop rather than spin.
                break
            }
        }
        return elements
    }

    /// Reads a number a model may have quoted (`"7.5"`) or dressed up (`"7.5/10"`).
    static func double<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
        guard let text = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        let head = text.replacingOccurrences(of: ",", with: ".")
            .split(separator: "/").first.map(String.init) ?? text
        return Double(head.trimmed)
    }

    /// Reads a string field that a model may have emitted as a number or bool.
    static func string<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return "\(value)" }
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) { return "\(value)" }
        return nil
    }

    /// Consumes one element of any shape so a lossy decode can move past it.
    /// Decoding advances the unkeyed container's cursor regardless of what this
    /// initializer does.
    private struct SkippedElement: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

/// Persisted per-application tailoring workflow state (a sidecar JSON file,
/// like curated suggestions). Survives sheet close / relaunch so multi-round
/// suggestions keep their applied progress. This is workflow state, not resume
/// content — it is deliberately excluded from `copyResumeContent`.
struct TailoringSession: Codable, Equatable {
    var pastedText: String
    var plan: TailoringPlan?
    var appliedChangeIDs: [String]
    /// The wording each applied change replaced, keyed by change id.
    ///
    /// Applying a change updates the bullet, and the review list is rebuilt from
    /// the stored record — so without this, an applied rewrite would show its own
    /// result as the "current" text and read as a no-op diff.
    var appliedBefore: [String: String]

    init(pastedText: String = "", plan: TailoringPlan? = nil, appliedChangeIDs: [String] = [],
         appliedBefore: [String: String] = [:]) {
        self.pastedText = pastedText
        self.plan = plan
        self.appliedChangeIDs = appliedChangeIDs
        self.appliedBefore = appliedBefore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pastedText = try c.decodeIfPresent(String.self, forKey: .pastedText) ?? ""
        plan = try? c.decodeIfPresent(TailoringPlan.self, forKey: .plan)
        appliedChangeIDs = try c.decodeIfPresent([String].self, forKey: .appliedChangeIDs) ?? []
        appliedBefore = try c.decodeIfPresent([String: String].self, forKey: .appliedBefore) ?? [:]
    }

    static func decode(_ json: String) -> TailoringSession? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TailoringSession.self, from: data)
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }
}
