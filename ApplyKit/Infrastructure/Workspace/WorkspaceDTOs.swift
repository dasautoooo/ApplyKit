import Foundation

struct WorkspaceManifestDTO: Codable {
    var name: String; var schemaVersion: Int; var managedDirectories: [String]; var updatedAt: String
    enum CodingKeys: String, CodingKey {
        case name; case schemaVersion = "schema_version"; case managedDirectories = "managed_directories"; case updatedAt = "updated_at"
    }
}

struct WorkspaceSettingsDTO: Codable {
    var codexCLIPath: String; var claudeCLIPath: String?; var preferredAIBackend: String?
    var latexBuildCommand: String; var externalEditorPath: String
    var resumeTemplatePath: String; var coverLetterTemplatePath: String; var updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case codexCLIPath = "codex_cli_path"; case claudeCLIPath = "claude_cli_path"
        case preferredAIBackend = "preferred_ai_backend"; case latexBuildCommand = "latex_build_command"
        case externalEditorPath = "external_editor_path"; case resumeTemplatePath = "resume_template_path"
        case coverLetterTemplatePath = "cover_letter_template_path"; case updatedAt = "updated_at"
    }
}

struct ApplicationPathsDTO: Codable {
    var jobDescription: String; var notes: String; var jdAnalysis: String?
    enum CodingKeys: String, CodingKey {
        case jobDescription = "job_description"; case notes; case jdAnalysis = "jd_analysis"
    }
}

struct ApplicationDocumentLinkDTO: Codable {
    var kind: String; var manifestPath: String; var texPath: String; var pdfPath: String; var status: String
    enum CodingKeys: String, CodingKey {
        case kind; case manifestPath = "manifest_path"; case texPath = "tex_path"
        case pdfPath = "pdf_path"; case status
    }
}

struct ApplicationFileDTO: Codable {
    var id: String; var companyName: String; var jobTitle: String; var jobURL: String; var location: String
    var workMode: String; var employmentType: String; var source: String; var status: String; var priority: String
    var dateSaved: String?; var dateApplied: String?; var deadline: String?
    var referralContact: String; var recruiterContact: String; var nextAction: String; var coverLetterNeeded: Bool
    var selectedExperienceIDs: [String]; var selectedProjectIDs: [String]?; var selectedVariantIDs: [String: String]?
    var selectedRoleDescriptions: [String: String]?
    var hiddenRoleDescriptions: [String]?
    var experienceOrder: [String]?
    var sectionOrder: [String]?
    var skillsBlock: String?; var summary: String?
    var archivedAt: String?; var createdAt: String?; var updatedAt: String?
    var paths: ApplicationPathsDTO; var documents: [ApplicationDocumentLinkDTO]
    enum CodingKeys: String, CodingKey {
        case id; case companyName = "company_name"; case jobTitle = "job_title"; case jobURL = "job_url"
        case location; case workMode = "work_mode"; case employmentType = "employment_type"; case source; case status; case priority
        case dateSaved = "date_saved"; case dateApplied = "date_applied"; case deadline
        case referralContact = "referral_contact"; case recruiterContact = "recruiter_contact"; case nextAction = "next_action"
        case coverLetterNeeded = "cover_letter_needed"; case selectedExperienceIDs = "selected_experience_ids"
        case selectedProjectIDs = "selected_project_ids"; case selectedVariantIDs = "selected_variant_ids"
        case selectedRoleDescriptions = "role_descriptions"
        case hiddenRoleDescriptions = "hidden_role_descriptions"
        case experienceOrder = "experience_order"
        case sectionOrder = "section_order"
        case skillsBlock = "skills_block"; case summary
        case archivedAt = "archived_at"; case createdAt = "created_at"; case updatedAt = "updated_at"
        case paths; case documents
    }
}

struct GeneratedDocumentManifestDTO: Codable {
    var id: String; var kind: String; var sourceApplicationID: String; var jobDescriptionPath: String
    var selectedExperienceIDs: [String]; var selectedProjectIDs: [String]?; var selectedVariantIDs: [String: String]?
    var texPath: String; var pdfPath: String; var buildStatus: String; var buildLogPath: String?
    var createdAt: String?; var updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case id; case kind; case sourceApplicationID = "source_application_id"; case jobDescriptionPath = "job_description_path"
        case selectedExperienceIDs = "selected_experience_ids"; case selectedProjectIDs = "selected_project_ids"
        case selectedVariantIDs = "selected_variant_ids"; case texPath = "tex_path"; case pdfPath = "pdf_path"
        case buildStatus = "build_status"; case buildLogPath = "build_log_path"
        case createdAt = "created_at"; case updatedAt = "updated_at"
    }
}

struct ExperienceFileDTO: Codable {
    var id: String; var experienceType: String; var company: String; var role: String; var projectName: String
    var bulletText: String; var variations: [ExperienceVariationDTO]; var skills: [String]
    var roleCategory: String; var impactLevel: String; var usableInResume: Bool; var usableInCoverLetter: Bool
    var referenceURL: String; var resumeDisplayName: String?; var notes: String?; var employmentID: String?; var createdAt: String?; var updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case id; case experienceType = "experience_type"; case company; case role; case projectName = "project_name"
        case bulletText = "bullet_text"; case variations; case skills; case roleCategory = "role_category"
        case impactLevel = "impact_level"; case usableInResume = "usable_in_resume"
        case usableInCoverLetter = "usable_in_cover_letter"; case referenceURL = "reference_url"
        case resumeDisplayName = "resume_display_name"; case notes
        case employmentID = "employment_id"; case createdAt = "created_at"; case updatedAt = "updated_at"
    }
}

struct ExperienceVariationDTO: Codable {
    var id: String; var name: String; var bulletText: String; var notes: String; var createdAt: String?; var updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case id; case name; case bulletText = "bullet_text"; case notes; case createdAt = "created_at"; case updatedAt = "updated_at"
    }
    init(id: String, name: String, bulletText: String, notes: String, createdAt: String?, updatedAt: String?) {
        self.id = id; self.name = name; self.bulletText = bulletText; self.notes = notes
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Variant"
        bulletText = try c.decode(String.self, forKey: .bulletText)
        notes = try c.decode(String.self, forKey: .notes)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(bulletText, forKey: .bulletText); try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(createdAt, forKey: .createdAt); try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct EmploymentFileDTO: Codable {
    var id: String; var companyName: String; var role: String; var location: String
    var startDate: String?; var endDate: String?; var displayOrder: Int; var experienceType: String
    var referenceURL: String; var notes: String; var roleDescription: String?; var createdAt: String?; var updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case id; case companyName = "company_name"; case role; case location
        case startDate = "start_date"; case endDate = "end_date"; case displayOrder = "display_order"
        case experienceType = "experience_type"; case referenceURL = "reference_url"; case notes
        case roleDescription = "role_description"; case createdAt = "created_at"; case updatedAt = "updated_at"
    }
}

struct EmploymentBankIndexDTO: Codable {
    var updatedAt: String; var entries: [EmploymentBankIndexEntryDTO]
    enum CodingKeys: String, CodingKey { case updatedAt = "updated_at"; case entries }
}

struct EmploymentBankIndexEntryDTO: Codable {
    var id: String; var companyName: String; var role: String; var dateRange: String; var path: String
    enum CodingKeys: String, CodingKey {
        case id; case companyName = "company_name"; case role; case dateRange = "date_range"; case path
    }
}

struct ExperienceBankIndexDTO: Codable {
    var updatedAt: String; var entries: [ExperienceBankIndexEntryDTO]
    enum CodingKeys: String, CodingKey { case updatedAt = "updated_at"; case entries }
}

struct ExperienceBankIndexEntryDTO: Codable {
    var id: String; var title: String; var company: String; var category: String; var path: String
}

struct MasterResumeFileDTO: Codable {
    var id: String; var name: String; var notes: String?
    var selectedExperienceIDs: [String]; var selectedProjectIDs: [String]?; var selectedVariantIDs: [String: String]?
    var selectedRoleDescriptions: [String: String]?
    var hiddenRoleDescriptions: [String]?
    var experienceOrder: [String]?
    var sectionOrder: [String]?
    var skillsBlock: String?; var summary: String?
    var createdAt: String?; var updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case id; case name; case notes
        case selectedExperienceIDs = "selected_experience_ids"
        case selectedProjectIDs = "selected_project_ids"; case selectedVariantIDs = "selected_variant_ids"
        case selectedRoleDescriptions = "role_descriptions"
        case hiddenRoleDescriptions = "hidden_role_descriptions"
        case experienceOrder = "experience_order"
        case sectionOrder = "section_order"
        case skillsBlock = "skills_block"; case summary
        case createdAt = "created_at"; case updatedAt = "updated_at"
    }
}

struct PromptTemplateFileDTO: Codable {
    var id: String; var name: String; var purpose: String; var templateText: String; var isDefault: Bool
    var createdAt: String?; var updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case id; case name; case purpose; case templateText = "template_text"
        case isDefault = "is_default"; case createdAt = "created_at"; case updatedAt = "updated_at"
    }
}

struct AIRunFileDTO: Codable {
    var id: String; var applicationID: String; var backend: String; var purpose: String; var promptPath: String
    var responsePath: String; var errorText: String; var exitCode: Int; var createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id; case applicationID = "application_id"; case backend; case purpose; case promptPath = "prompt_path"
        case responsePath = "response_path"; case errorText = "error_text"; case exitCode = "exit_code"
        case createdAt = "created_at"
    }
}

struct ActivityRecordDTO: Codable {
    var id: String; var timestamp: String?; var message: String; var succeeded: Bool
    enum CodingKeys: String, CodingKey { case id, timestamp, message, succeeded }
}

struct ActivityLogDTO: Codable {
    var updatedAt: String?; var entries: [ActivityRecordDTO]
    enum CodingKeys: String, CodingKey { case updatedAt = "updated_at"; case entries }
}

struct ResumeProfileDTO: Codable {
    var fullName: String; var city: String; var phone: String; var email: String
    var linkedin: String; var github: String; var website: String
    var educationBlock: String; var skillsBlock: String; var updatedAt: String?
    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"; case city; case phone; case email
        case linkedin; case github; case website
        case educationBlock = "education_block"; case skillsBlock = "skills_block"
        case updatedAt = "updated_at"
    }
}
