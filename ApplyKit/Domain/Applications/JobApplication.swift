import Foundation

struct JobApplication: Identifiable, Codable, Hashable {
    var id: UUID
    var companyName: String
    var jobTitle: String
    var jobURL: String
    var location: String
    var workModeRaw: String
    var employmentTypeRaw: String
    var sourceRaw: String
    var statusRaw: String
    var priorityRaw: String
    var dateSaved: Date
    var dateApplied: Date?
    var deadline: Date?
    var referralContact: String
    var recruiterContact: String
    var nextAction: String
    var notes: String
    var jobDescription: String
    var jdAnalysisText: String
    var curatedSuggestionsData: String
    var coverLetterNeeded: Bool
    var selectedExperienceIDsText: String
    var selectedProjectIDsText: String
    var selectedVariantIDsText: String
    var employmentRoleDescriptionsText: String
    var experienceOrderText: String
    var sectionOrderText: String
    var skillsBlockText: String
    var summaryText: String
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        companyName: String = "",
        jobTitle: String = "",
        status: ApplicationStatus = .saved,
        priority: ApplicationPriority = .medium
    ) {
        self.id = UUID()
        self.companyName = companyName
        self.jobTitle = jobTitle
        self.jobURL = ""
        self.location = ""
        self.workModeRaw = WorkMode.unknown.rawValue
        self.employmentTypeRaw = EmploymentType.fullTime.rawValue
        self.sourceRaw = ApplicationSource.linkedin.rawValue
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.dateSaved = Date()
        self.referralContact = ""
        self.recruiterContact = ""
        self.nextAction = ""
        self.notes = ""
        self.jobDescription = ""
        self.jdAnalysisText = ""
        self.curatedSuggestionsData = ""
        self.coverLetterNeeded = false
        self.selectedExperienceIDsText = ""
        self.selectedProjectIDsText = ""
        self.selectedVariantIDsText = ""
        self.employmentRoleDescriptionsText = ""
        self.experienceOrderText = ""
        self.sectionOrderText = ""
        self.skillsBlockText = ""
        self.summaryText = ""
        self.archivedAt = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension JobApplication {
    var displayTitle: String {
        let title = jobTitle.trimmed
        let company = companyName.trimmed
        if company.isEmpty && title.isEmpty { return "Untitled Application" }
        if company.isEmpty { return title }
        if title.isEmpty { return company }
        return "\(company) - \(title)"
    }

    var isArchived: Bool { archivedAt != nil }

    /// Per-application skills override. When blank, resumes fall back to the global
    /// `ResumeProfile.skillsBlock`.
    var hasSkillsOverride: Bool { !skillsBlockText.trimmed.isEmpty }

    func effectiveSkillsBlock(default globalBlock: String) -> String {
        hasSkillsOverride ? skillsBlockText : globalBlock
    }

    /// Per-application summary. When blank, the Summary section is omitted entirely.
    var hasSummary: Bool { !summaryText.trimmed.isEmpty }

    var selectedExperienceIDs: Set<UUID> {
        Set(selectedExperienceIDsText.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    var selectedProjectIDs: Set<UUID> {
        Set(selectedProjectIDsText.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    var selectedVariantIDs: [UUID: UUID] {
        JobApplication.decodeVariantSelections(selectedVariantIDsText)
    }

    func selectedVariantID(for experienceID: UUID) -> UUID? { selectedVariantIDs[experienceID] }

    mutating func setExperience(_ id: UUID, selected: Bool) {
        var ids = selectedExperienceIDs
        if selected { ids.insert(id) } else {
            ids.remove(id)
            setVariant(nil, for: id, updatingTimestamp: false)
        }
        selectedExperienceIDsText = ids.map(\.uuidString).sorted().joined(separator: ",")
        updatedAt = Date()
    }

    mutating func setProject(_ id: UUID, selected: Bool) {
        var ids = selectedProjectIDs
        if selected { ids.insert(id) } else {
            ids.remove(id)
            setVariant(nil, for: id, updatingTimestamp: false)
        }
        selectedProjectIDsText = ids.map(\.uuidString).sorted().joined(separator: ",")
        updatedAt = Date()
    }

    mutating func setVariant(_ variantID: UUID?, for experienceID: UUID, updatingTimestamp: Bool = true) {
        var selections = selectedVariantIDs
        selections[experienceID] = variantID
        selectedVariantIDsText = JobApplication.encodeVariantSelections(selections)
        if updatingTimestamp { updatedAt = Date() }
    }

    static func encodeVariantSelections(_ selections: [UUID: UUID]) -> String {
        guard !selections.isEmpty,
              let data = try? JSONEncoder().encode(
                Dictionary(uniqueKeysWithValues: selections.map { ($0.key.uuidString, $0.value.uuidString) })
              ),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func decodeVariantSelections(_ text: String) -> [UUID: UUID] {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard let eID = UUID(uuidString: key), let vID = UUID(uuidString: value) else { return nil }
            return (eID, vID)
        })
    }

    var employmentRoleDescriptions: [UUID: String] {
        JobApplication.decodeRoleDescriptions(employmentRoleDescriptionsText)
    }

    /// Per-application role-description override for an employment, or nil when blank
    /// (callers fall back to the employment's default `roleDescription`).
    func roleDescription(for employmentID: UUID) -> String? {
        let text = employmentRoleDescriptions[employmentID]?.trimmed ?? ""
        return text.isEmpty ? nil : text
    }

    mutating func setRoleDescription(_ text: String, for employmentID: UUID) {
        var overrides = employmentRoleDescriptions
        if text.trimmed.isEmpty {
            overrides.removeValue(forKey: employmentID)
        } else {
            overrides[employmentID] = text
        }
        employmentRoleDescriptionsText = JobApplication.encodeRoleDescriptions(overrides)
        updatedAt = Date()
    }

    static func encodeRoleDescriptions(_ overrides: [UUID: String]) -> String {
        guard !overrides.isEmpty,
              let data = try? JSONEncoder().encode(
                Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.uuidString, $0.value) })
              ),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func decodeRoleDescriptions(_ text: String) -> [UUID: String] {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard let eID = UUID(uuidString: key) else { return nil }
            return (eID, value)
        })
    }

    /// Per-application bullet ordering: a flat, ordered list of selected experience IDs.
    /// Grouping (by employment / project bucket) is applied separately by callers.
    var experienceOrder: [UUID] {
        experienceOrderText.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    mutating func setExperienceOrder(_ ids: [UUID]) {
        experienceOrderText = ids.map(\.uuidString).joined(separator: ",")
        updatedAt = Date()
    }

    /// Sort bullets by their position in `experienceOrder`, falling back to `createdAt`
    /// for any bullet not present in the stored order. Single source of truth for
    /// within-group ordering, reused by the renderer and the editor UI.
    func orderedExperiences(_ bullets: [ExperienceBullet]) -> [ExperienceBullet] {
        let index = Dictionary(uniqueKeysWithValues: experienceOrder.enumerated().map { ($0.element, $0.offset) })
        return bullets.sorted { lhs, rhs in
            let li = index[lhs.id] ?? Int.max
            let ri = index[rhs.id] ?? Int.max
            return li != ri ? li < ri : lhs.createdAt < rhs.createdAt
        }
    }

    /// Per-application resume section order. Always returns every `ResumeSectionKind`,
    /// appending any kind missing from the stored order (e.g. unset, or a newly added
    /// kind) in the default order.
    var sectionOrder: [ResumeSectionKind] {
        let stored = sectionOrderText.split(separator: ",").compactMap { ResumeSectionKind(rawValue: String($0)) }
        let missing = ResumeSectionKind.defaultOrder.filter { !stored.contains($0) }
        return stored + missing
    }

    mutating func setSectionOrder(_ order: [ResumeSectionKind]) {
        sectionOrderText = order.map(\.rawValue).joined(separator: ",")
        updatedAt = Date()
    }
}
