//
//  ResumeEditPlan.swift
//  ApplyKit
//
//  The Resume Edit Plan v1.0 contract: the JSON object a pasted ChatGPT reply
//  carries (schema in ResumeEditPlanPrompt.swift). These are transport
//  types only — `ResumeEditPlanImporter` validates them and adapts them into a
//  `TailoringPlan`, which is what the review list applies.
//

import Foundation

struct ResumeEditPlanDTO: Decodable, Equatable {
    let schemaVersion: String
    let fitScore: Double
    let sectionOrder: [ResumeSectionKey]
    let summary: SummaryEditDTO
    let skills: SkillsEditDTO
    let experience: [BulletEditDTO]
    let projects: [BulletEditDTO]
    let roleDescriptions: [RoleDescriptionEditDTO]

    static let supportedVersion = "1.0"
    static let skillsContentWidth = "0.74\\textwidth"
    static let skillsRowCount = 3
}

/// Section keys as the plan spells them. `kind` is the app's own section.
enum ResumeSectionKey: String, Decodable, CaseIterable {
    case summary
    case education
    case skills
    case experience
    case projects

    var kind: ResumeSectionKind {
        switch self {
        case .summary: .summary
        case .education: .education
        case .skills: .skills
        case .experience: .experience
        case .projects: .projects
        }
    }
}

struct SummaryEditDTO: Decodable, Equatable {
    let action: SummaryAction
    let text: String?
}

enum SummaryAction: String, Decodable, CaseIterable {
    case keep
    case replace
    case drop
}

struct SkillsEditDTO: Decodable, Equatable {
    let action: SkillsAction
    let contentWidth: String
    let rows: [SkillRowDTO]
}

enum SkillsAction: String, Decodable, CaseIterable {
    case replace
}

struct SkillRowDTO: Decodable, Equatable {
    let label: String
    let items: [String]
}

struct BulletEditDTO: Decodable, Equatable {
    let id: String
    let action: BulletAction
    let order: Int?
    let variantTitle: String?
    let text: String?

    /// Kept and rewritten bullets render; dropped ones don't.
    var isRetained: Bool { action != .drop }
}

enum BulletAction: String, Decodable, CaseIterable {
    case keep
    case rewrite
    case drop
}

/// The one-line role description under an employer. An employer the plan
/// doesn't list keeps its line exactly as it is.
struct RoleDescriptionEditDTO: Decodable, Equatable {
    let employmentID: String
    let action: RoleDescriptionAction
    /// The line's slot among its employer's lines, numbered together with that
    /// employer's bullets. Nil leaves it where it is.
    let order: Int?
    let text: String?

    /// `.convertFromSnakeCase` turns `employment_id` into `employmentId`.
    enum CodingKeys: String, CodingKey {
        case employmentID = "employmentId"
        case action
        case order
        case text
    }
}

enum RoleDescriptionAction: String, Decodable, CaseIterable {
    /// Show the current wording — also how a hidden line is brought back.
    case keep
    case rewrite
    case hide
}

/// One problem found while importing a plan. `path` is a JSON Pointer into the
/// pasted object (`/experience/2/variant_title`), empty for the whole payload.
struct ResumeEditPlanIssue: Identifiable, Equatable {
    enum Severity: Equatable {
        case error
        case warning
    }

    let id = UUID()
    let severity: Severity
    let code: String
    let path: String
    let message: String

    init(_ severity: Severity, _ code: String, path: String, _ message: String) {
        self.severity = severity
        self.code = code
        self.path = path
        self.message = message
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.severity == rhs.severity && lhs.code == rhs.code
            && lhs.path == rhs.path && lhs.message == rhs.message
    }

    var isError: Bool { severity == .error }
}
