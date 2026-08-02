import Foundation

struct JobPageContent: Sendable {
    var sourceURL: URL
    var pageTitle: String
    var metadataDescription: String
    var jobPostingJSON: String
    var visibleText: String
    var wasRendered: Bool
    /// The posting body when it arrived already clean — an ATS API's own
    /// description field, or text the user pasted. Non-empty means the AI is
    /// asked to classify the posting *without* re-emitting the description,
    /// which is by far the slowest part of the import (it otherwise has to
    /// generate several thousand tokens of text we already hold verbatim).
    var canonicalDescription: String = ""

    var isLikelyUsable: Bool {
        jobPostingJSON.localizedCaseInsensitiveContains("JobPosting")
            || visibleText.count >= 500
    }
}

struct MasterResumeMatch: Identifiable, Hashable, Sendable {
    var id: UUID { masterResumeID }
    var masterResumeID: UUID
    var confidence: Double
    var rationale: String
}

struct JobImportDraft: Sendable {
    var jobURL: String
    var companyName: String
    var jobTitle: String
    var location: String
    var workModeRaw: String
    var employmentTypeRaw: String
    var sourceRaw: String
    var deadline: Date?
    var jobDescription: String
    var matches: [MasterResumeMatch]
    var selectedMasterResumeID: UUID?
    var wasRendered: Bool

    var recommendedMatch: MasterResumeMatch? { matches.first }

    var hasHighConfidenceRecommendation: Bool {
        guard let first = matches.first, first.confidence >= 0.75 else { return false }
        guard matches.count > 1 else { return true }
        return first.confidence - matches[1].confidence >= 0.15
    }
}

enum JobImportError: LocalizedError {
    case invalidURL
    case unsupportedURL
    case requestFailed(String)
    case oversizedResponse
    case unsupportedContent
    case noUsableJobContent
    case renderedPageFailed(String)
    case missingAIBackend
    case invalidAIResponse
    case noMasterResumes

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a complete job URL, including https://."
        case .unsupportedURL:
            "Only public HTTP and HTTPS job URLs are supported."
        case .requestFailed(let detail):
            "The job page could not be loaded. \(detail)"
        case .oversizedResponse:
            "The job page was too large to import safely."
        case .unsupportedContent:
            "The URL did not return an HTML job page."
        case .noUsableJobContent:
            "ApplyKit could not find a usable job description on this page."
        case .renderedPageFailed(let detail):
            "The rendered page could not be read. \(detail)"
        case .missingAIBackend:
            "Configure Claude Code or Codex in Settings → Tools before importing."
        case .invalidAIResponse:
            "The AI response did not contain valid job details. Try again or paste the job description manually."
        case .noMasterResumes:
            "Create at least one Master Resume before importing a job."
        }
    }
}

enum JobURLNormalizer {
    static func validatedURL(from value: String) throws -> URL {
        let trimmed = value.trimmed
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            throw trimmed.contains("://") ? JobImportError.unsupportedURL : JobImportError.invalidURL
        }
        return url
    }

    static func duplicateKey(for value: String) -> String? {
        guard let url = try? validatedURL(from: value),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        let trackingNames = Set(["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "gclid", "fbclid"])
        components.queryItems = components.queryItems?
            .filter { !trackingNames.contains($0.name.lowercased()) }
            .sorted { $0.name == $1.name ? ($0.value ?? "") < ($1.value ?? "") : $0.name < $1.name }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        return components.string
    }
}
