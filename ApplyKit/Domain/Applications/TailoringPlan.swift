//
//  TailoringPlan.swift
//  ApplyKit
//

import Foundation

/// A structured set of resume edits distilled from a pasted ChatGPT tailoring
/// suggestion. Produced by the local AI reconciler (`PromptBuilder
/// .tailoringReconciliationPrompt` → `runAI`), which maps the freeform prose —
/// including truncated `"…"` quotes — onto the application's real bullet UUIDs.
/// Every field is optional; an omitted field means "leave the current value
/// unchanged".
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

    struct Replacement: Codable, Equatable {
        var experienceID: UUID
        var text: String
        var name: String?
        var reason: String?

        enum CodingKeys: String, CodingKey {
            case experienceID = "experience_id"
            case text
            case name
            case reason
        }
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case skillsLatex = "skills_latex"
        case sectionOrder = "section_order"
        case orderedExperienceIDs = "ordered_experience_ids"
        case orderedProjectIDs = "ordered_project_ids"
        case replacements
    }
}

extension TailoringPlan {
    /// Decode a plan from a raw AI response, tolerating code fences and leading/
    /// trailing prose around the JSON object (mirrors `CoverLetterRenderer`).
    /// Returns `nil` when no decodable object is present.
    static func parse(from response: String) -> TailoringPlan? {
        let jsonText = extractJSONObject(from: stripCodeFence(response))
        guard let data = jsonText.data(using: .utf8),
              let plan = try? JSONDecoder().decode(TailoringPlan.self, from: data) else {
            return nil
        }
        return plan
    }

    /// True when the plan carries nothing actionable.
    var isEmpty: Bool {
        summary == nil && skillsLatex == nil && sectionOrder == nil
            && orderedExperienceIDs == nil && orderedProjectIDs == nil
            && (replacements?.isEmpty ?? true)
    }

    private static func stripCodeFence(_ value: String) -> String {
        let trimmed = value.trimmed
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.trimmed == "```" { lines.removeLast() }
        return lines.joined(separator: "\n").trimmed
    }

    private static func extractJSONObject(from value: String) -> String {
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end else {
            return value
        }
        return String(value[start...end])
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

    init(pastedText: String = "", plan: TailoringPlan? = nil, appliedChangeIDs: [String] = []) {
        self.pastedText = pastedText
        self.plan = plan
        self.appliedChangeIDs = appliedChangeIDs
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
