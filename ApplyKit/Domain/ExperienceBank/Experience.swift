//
//  Experience.swift
//  ApplyKit
//

import Foundation

struct ExperienceBullet: Identifiable, Codable, Hashable {
    var id: UUID
    var experienceType: String
    var company: String
    var role: String
    var projectName: String
    var bulletText: String
    var variationsText: String
    var tagsText: String
    var skillsText: String
    var roleCategoryRaw: String
    var impactLevelRaw: String
    var usableInResume: Bool
    var usableInCoverLetter: Bool
    var claimLevelRaw: String
    var sensitivityRaw: String
    var referenceURL: String
    var resumeDisplayName: String
    var notes: String
    var employmentID: UUID?
    /// Set when the bullet belongs to one application rather than the shared
    /// bank — a fact recalled during tailoring that the user chose not to file
    /// away. It still lives in `store.experiences` and renders normally; only
    /// its visibility is scoped (see `ExperienceScope`).
    var owningApplicationID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        experienceType: String = "Work",
        company: String = "",
        role: String = "",
        projectName: String = "",
        bulletText: String = "",
        variations: [ExperienceVariation] = [],
        tagsText: String = "",
        skillsText: String = "",
        roleCategory: RoleCategory = .generalSoftware,
        impactLevel: ImpactLevel = .medium,
        usableInResume: Bool = true,
        usableInCoverLetter: Bool = true,
        claimLevel: ClaimLevel = .strong,
        sensitivity: SensitivityLevel = .internalSafe,
        referenceURL: String = "",
        resumeDisplayName: String = "",
        notes: String = "",
        employmentID: UUID? = nil,
        owningApplicationID: UUID? = nil
    ) {
        self.id = UUID()
        self.experienceType = experienceType
        self.company = company
        self.role = role
        self.projectName = projectName
        self.bulletText = bulletText
        self.variationsText = ExperienceVariation.encode(variations)
        self.tagsText = tagsText
        self.skillsText = skillsText
        self.roleCategoryRaw = roleCategory.rawValue
        self.impactLevelRaw = impactLevel.rawValue
        self.usableInResume = usableInResume
        self.usableInCoverLetter = usableInCoverLetter
        self.claimLevelRaw = claimLevel.rawValue
        self.sensitivityRaw = sensitivity.rawValue
        self.referenceURL = referenceURL
        self.resumeDisplayName = resumeDisplayName
        self.notes = notes
        self.employmentID = employmentID
        self.owningApplicationID = owningApplicationID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct ExperienceVariation: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var bulletText: String
    var notes: String
    /// Set when this wording belongs to one application rather than the shared
    /// bullet — the variant of a bank bullet that a tailoring answer produced
    /// but the user kept application-only.
    var owningApplicationID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        bulletText: String = "",
        notes: String = "",
        owningApplicationID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bulletText = bulletText
        self.notes = notes
        self.owningApplicationID = owningApplicationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bulletText
        case notes
        case owningApplicationID
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Variant"
        bulletText = try container.decode(String.self, forKey: .bulletText)
        notes = try container.decode(String.self, forKey: .notes)
        owningApplicationID = try container.decodeIfPresent(UUID.self, forKey: .owningApplicationID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(bulletText, forKey: .bulletText)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(owningApplicationID, forKey: .owningApplicationID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    static func encode(_ variations: [ExperienceVariation]) -> String {
        guard !variations.isEmpty,
              let data = try? JSONEncoder().encode(variations),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func decode(_ text: String) -> [ExperienceVariation] {
        guard let data = text.data(using: .utf8),
              let variations = try? JSONDecoder().decode([ExperienceVariation].self, from: data) else {
            return []
        }
        return variations
    }
}

extension ExperienceVariation {
    var displayName: String {
        name.trimmed.isEmpty ? "Untitled Variant" : name.trimmed
    }

    static func defaultName(existing variations: [ExperienceVariation]) -> String {
        let names = Set(variations.map { $0.displayName })
        var index = variations.count + 1
        while names.contains("Variant \(index)") {
            index += 1
        }
        return "Variant \(index)"
    }

    /// An existing variant with the same title and wording, compared after
    /// normalizing whitespace (case and punctuation still count). Importing the
    /// same edit plan twice reuses it instead of adding a duplicate.
    static func matching(name: String, text: String, in variations: [ExperienceVariation]) -> ExperienceVariation? {
        let key = (normalized(name), normalized(text))
        return variations.first { (normalized($0.name), normalized($0.bulletText)) == key }
    }

    /// Trimmed, CRLF → LF, and runs of spaces or tabs collapsed to one space.
    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmed
    }
}

extension ExperienceBullet {
    var displayTitle: String {
        if !projectName.trimmed.isEmpty { return projectName }
        if !company.trimmed.isEmpty { return company }
        return "Untitled Experience"
    }

    var sourceTitle: String {
        if isPersonalProject { return "Personal Projects" }
        return company.trimmed.isEmpty ? "Unassigned Source" : company
    }

    var parsedSkills: [String] {
        skillsText.commaSeparatedValues
    }

    var parsedTags: [String] {
        tagsText.commaSeparatedValues
    }

    var experienceCategory: ExperienceCategory {
        ExperienceCategory(rawValue: experienceType) ?? .work
    }

    var isProjectLike: Bool {
        experienceCategory == .project || experienceCategory == .openSource
    }

    var isPersonalProject: Bool {
        isProjectLike && employmentID == nil && company.trimmed.isEmpty
    }

    var variations: [ExperienceVariation] {
        get { ExperienceVariation.decode(variationsText) }
        set { variationsText = ExperienceVariation.encode(newValue) }
    }

    /// Variations this application may choose between: the shared ones plus any
    /// it owns. Another application's private wording stays hidden.
    func variations(visibleTo applicationID: UUID?) -> [ExperienceVariation] {
        variations.filter { ExperienceScope.isVisible(owner: $0.owningApplicationID, to: applicationID) }
    }

    var isApplicationScoped: Bool { owningApplicationID != nil }

    func bulletText(variantID: UUID?) -> String {
        guard let variantID,
              let variation = variations.first(where: { $0.id == variantID }),
              !variation.bulletText.trimmed.isEmpty else {
            return bulletText
        }
        return variation.bulletText
    }

    func promptSummary(variantID: UUID?) -> String {
        """
        - Type: \(experienceType)
          Source: \(company) \(role)
          Project: \(projectName)
          Bullet: \(bulletText(variantID: variantID))
          Skills: \(skillsText)
        """
    }
}
