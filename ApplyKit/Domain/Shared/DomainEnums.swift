import Foundation

protocol StoredStringEnum: RawRepresentable, CaseIterable, Identifiable where RawValue == String {}

extension StoredStringEnum {
    var id: String { rawValue }
}

enum ApplicationStatus: String, StoredStringEnum {
    case saved = "Saved"
    case interested = "Interested"
    case preparing = "Preparing"
    case applied = "Applied"
    case referralRequested = "Referral Requested"
    case recruiterScreen = "Recruiter Screen"
    case technicalInterview = "Technical Interview"
    case finalInterview = "Final Interview"
    case offer = "Offer"
    case rejected = "Rejected"
    case ghosted = "Ghosted"
    case withdrawn = "Withdrawn"
}

enum ApplicationPriority: String, StoredStringEnum {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

enum WorkMode: String, StoredStringEnum {
    case unknown = "Unknown"
    case remote = "Remote"
    case hybrid = "Hybrid"
    case onsite = "Onsite"
}

enum EmploymentType: String, StoredStringEnum {
    case unknown = "Unknown"
    case fullTime = "Full-time"
    case contract = "Contract"
    case internship = "Internship"
    case coOp = "Co-op"
}

enum ExperienceCategory: String, StoredStringEnum {
    case work = "Work"
    case education = "Education"
    case project = "Project"
    case openSource = "Open Source"
    case other = "Other"
}

enum ApplicationSource: String, StoredStringEnum {
    case linkedin = "LinkedIn"
    case companyWebsite = "Company Website"
    case referral = "Referral"
    case recruiter = "Recruiter"
    case other = "Other"
}

enum RoleCategory: String, StoredStringEnum {
    case generalSoftware = "General Software Engineering"
    case backendPlatform = "Backend / Platform"
    case aiTooling = "AI Tooling"
    case dataWorkflow = "Data / Workflow"
    case systemsCpp = "Systems / C++"
    case mobileIOS = "Mobile / iOS"
    case developerTools = "Developer Tools"
    case cloudInfrastructure = "Cloud / Infrastructure"
    case graphics = "Graphics"
    case research = "Research"
}

enum ImpactLevel: String, StoredStringEnum {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

enum ClaimLevel: String, StoredStringEnum {
    case strong = "Safe to claim strongly"
    case contextual = "Safe with context"
    case avoidEmphasis = "Do not emphasize"
}

enum SensitivityLevel: String, StoredStringEnum {
    case publicInfo = "Public"
    case internalSafe = "Internal-safe"
    case sensitive = "Sensitive"
}

enum GeneratedDocumentKind: String, StoredStringEnum {
    case resume = "Resume"
    case coverLetter = "Cover Letter"
}

enum GeneratedDocumentStatus: String, StoredStringEnum {
    case draft = "Draft"
    case built = "Built"
    case failed = "Failed"
    case final = "Final"
}

enum ResumeSectionKind: String, StoredStringEnum {
    case summary = "Summary"
    case education = "Education"
    case experience = "Experience"
    case projects = "Selected Projects"
    case skills = "Skills"

    static let defaultOrder: [ResumeSectionKind] = [.summary, .education, .experience, .projects, .skills]
}

enum PromptPurpose: String, StoredStringEnum {
    case analyzeJob = "Analyze Job"
    case tailorResume = "Tailor Resume"
    case coverLetterAngle = "Cover Letter Angle"
    case keywordReview = "Keyword Review"
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var commaSeparatedValues: [String] {
        split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }
}
