import Foundation

/// A named, reusable resume preset targeting one role direction (e.g. "iOS
/// Engineer"). Carries the same resume-content fields as `JobApplication`;
/// applying a master resume to an application copies them wholesale.
struct MasterResume: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var notes: String
    var selectedExperienceIDsText: String
    var selectedProjectIDsText: String
    var selectedVariantIDsText: String
    var employmentRoleDescriptionsText: String
    var hiddenRoleDescriptionIDsText: String
    var experienceOrderText: String
    var sectionOrderText: String
    var skillsBlockText: String
    var summaryText: String
    var createdAt: Date
    var updatedAt: Date

    init(name: String = "New Master Resume") {
        self.id = UUID()
        self.name = name
        self.notes = ""
        self.selectedExperienceIDsText = ""
        self.selectedProjectIDsText = ""
        self.selectedVariantIDsText = ""
        self.employmentRoleDescriptionsText = ""
        self.hiddenRoleDescriptionIDsText = ""
        self.experienceOrderText = ""
        self.sectionOrderText = ""
        self.skillsBlockText = ""
        self.summaryText = ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension MasterResume: ResumeContentModel {}

extension MasterResume {
    var displayTitle: String {
        let trimmed = name.trimmed
        return trimmed.isEmpty ? "Untitled Master Resume" : trimmed
    }
}
