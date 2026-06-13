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
}
