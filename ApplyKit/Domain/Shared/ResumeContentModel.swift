import Foundation

/// The resume-content fields shared by `JobApplication` and `MasterResume`.
/// All list/dict data is stored as flattened strings (CSV or JSON) with the
/// computed accessors below; a master resume is a reusable preset of exactly
/// these fields, and applying one to an application is a wholesale copy.
protocol ResumeContentModel {
    var selectedExperienceIDsText: String { get set }
    var selectedProjectIDsText: String { get set }
    var selectedVariantIDsText: String { get set }
    var employmentRoleDescriptionsText: String { get set }
    var hiddenRoleDescriptionIDsText: String { get set }
    var experienceOrderText: String { get set }
    var sectionOrderText: String { get set }
    var skillsBlockText: String { get set }
    var summaryText: String { get set }
    var updatedAt: Date { get set }
}

enum ResumeFieldCodec {
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

extension ResumeContentModel {
    /// Skills override. When blank, resumes fall back to the global
    /// `ResumeProfile.skillsBlock`.
    var hasSkillsOverride: Bool { !skillsBlockText.trimmed.isEmpty }

    func effectiveSkillsBlock(default globalBlock: String) -> String {
        hasSkillsOverride ? skillsBlockText : globalBlock
    }

    /// Summary text. When blank, the Summary section is omitted entirely.
    var hasSummary: Bool { !summaryText.trimmed.isEmpty }

    var selectedExperienceIDs: Set<UUID> {
        Set(selectedExperienceIDsText.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    var selectedProjectIDs: Set<UUID> {
        Set(selectedProjectIDsText.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    var selectedVariantIDs: [UUID: UUID] {
        ResumeFieldCodec.decodeVariantSelections(selectedVariantIDsText)
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
        selectedVariantIDsText = ResumeFieldCodec.encodeVariantSelections(selections)
        if updatingTimestamp { updatedAt = Date() }
    }

    var employmentRoleDescriptions: [UUID: String] {
        ResumeFieldCodec.decodeRoleDescriptions(employmentRoleDescriptionsText)
    }

    /// Role-description override for an employment, or nil when blank
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
        employmentRoleDescriptionsText = ResumeFieldCodec.encodeRoleDescriptions(overrides)
        updatedAt = Date()
    }

    /// Employments whose role-description line is omitted from the generated resume.
    var hiddenRoleDescriptionEmploymentIDs: Set<UUID> {
        Set(hiddenRoleDescriptionIDsText.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    func isRoleDescriptionHidden(for employmentID: UUID) -> Bool {
        hiddenRoleDescriptionEmploymentIDs.contains(employmentID)
    }

    mutating func setRoleDescriptionHidden(_ hidden: Bool, for employmentID: UUID) {
        var ids = hiddenRoleDescriptionEmploymentIDs
        if hidden { ids.insert(employmentID) } else { ids.remove(employmentID) }
        hiddenRoleDescriptionIDsText = ids.map(\.uuidString).sorted().joined(separator: ",")
        updatedAt = Date()
    }

    /// Bullet ordering: a flat, ordered list of selected experience IDs. May also contain
    /// employment IDs, marking where that employment's role-description line sits among
    /// its bullets (absent = first). Grouping is applied separately by callers.
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

    /// Resume section order. Always returns every `ResumeSectionKind`, appending
    /// any kind missing from the stored order (e.g. unset, or a newly added kind)
    /// in the default order.
    var sectionOrder: [ResumeSectionKind] {
        let stored = sectionOrderText.split(separator: ",").compactMap { ResumeSectionKind(rawValue: String($0)) }
        let missing = ResumeSectionKind.defaultOrder.filter { !stored.contains($0) }
        return stored + missing
    }

    mutating func setSectionOrder(_ order: [ResumeSectionKind]) {
        sectionOrderText = order.map(\.rawValue).joined(separator: ",")
        updatedAt = Date()
    }

    /// Replace this model's resume content with another's. Used when applying a
    /// master resume to an application, saving an application as a master resume,
    /// and creating an application from a preset.
    mutating func copyResumeContent(from other: some ResumeContentModel) {
        selectedExperienceIDsText = other.selectedExperienceIDsText
        selectedProjectIDsText = other.selectedProjectIDsText
        selectedVariantIDsText = other.selectedVariantIDsText
        employmentRoleDescriptionsText = other.employmentRoleDescriptionsText
        hiddenRoleDescriptionIDsText = other.hiddenRoleDescriptionIDsText
        experienceOrderText = other.experienceOrderText
        sectionOrderText = other.sectionOrderText
        skillsBlockText = other.skillsBlockText
        summaryText = other.summaryText
        updatedAt = Date()
    }
}
