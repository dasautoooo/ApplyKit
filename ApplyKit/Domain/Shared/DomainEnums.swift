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
    /// The interview phase, kept in step with the Interview Process: a logged recruiter screen
    /// and nothing further is Recruiter Screen, any round is Interviewing. Which round, and how
    /// it went, lives on the steps.
    case recruiterScreen = "Recruiter Screen"
    case interviewing = "Interviewing"
    case offer = "Offer"
    case rejected = "Rejected"
    case ghosted = "Ghosted"
    case withdrawn = "Withdrawn"
}

extension ApplicationStatus {
    /// Statuses older workspaces used for interview rounds, before rounds became steps.
    static let legacyRoundRawValues: Set<String> = ["Technical Interview", "Final Interview"]

    /// Parses a status read from disk. The legacy round statuses fold into `.interviewing`
    /// so those applications aren't silently reset to Saved. Only the current status is
    /// migrated: the timeline keeps old values verbatim, since that is what the status was.
    static func stored(_ raw: String) -> ApplicationStatus? {
        legacyRoundRawValues.contains(raw) ? .interviewing : ApplicationStatus(rawValue: raw)
    }

    /// Position along the open pipeline; nil for the closed-out statuses (Offer and the exits),
    /// which interview steps never move an application out of.
    private var pipelineRank: Int? {
        switch self {
        case .saved, .interested, .preparing, .applied, .referralRequested: 0
        case .recruiterScreen: 1
        case .interviewing: 2
        case .offer, .rejected, .ghosted, .withdrawn: nil
        }
    }

    /// Whether logging a step that implies `later` should advance this status to it.
    func precedes(_ later: ApplicationStatus) -> Bool {
        guard let rank = pipelineRank, let target = later.pipelineRank else { return false }
        return rank < target
    }

    /// Recruiter Screen or Interviewing: the statuses that mirror the Interview Process.
    var isInterviewPhase: Bool { self == .recruiterScreen || self == .interviewing }

    /// Offer and the exits: settled, so nothing automatic changes them.
    var isClosed: Bool { pipelineRank == nil }
}

enum InterviewType: String, StoredStringEnum {
    /// Marks the recruiter's call. A step like the rest, but not numbered as a round and
    /// counted as the Screen stage; added as its own kind of step, never picked as a round type.
    case recruiterScreen = "Recruiter Screen"
    case onlineAssessment = "Online Assessment"
    case phoneScreen = "Phone Screen"
    case coding = "Coding"
    case systemDesign = "System Design"
    case takeHome = "Take-home"
    case behavioral = "Behavioral"
    case hiringManager = "Hiring Manager"
    case teamMatch = "Team Match"
    case onsite = "Onsite / Loop"
    case other = "Other"
}

extension InterviewType {
    /// What a round can be — everything but the recruiter screen.
    static var roundTypes: [InterviewType] { allCases.filter { $0 != .recruiterScreen } }
}

enum InterviewFormat: String, StoredStringEnum {
    case video = "Video"
    case phone = "Phone"
    case onsite = "Onsite"
    case other = "Other"

    var systemImage: String {
        switch self {
        case .video: "video"
        case .phone: "phone"
        case .onsite: "building.2"
        case .other: "ellipsis.circle"
        }
    }
}

enum InterviewResult: String, StoredStringEnum {
    /// They've reached out and a time is being arranged. The step's date is when it was
    /// logged, not when it happens — there is no time yet.
    case scheduling = "Scheduling"
    case scheduled = "Scheduled"
    case awaiting = "Awaiting"
    case passed = "Passed"
    case didNotAdvance = "Didn't Advance"
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
