//
//  DiscoveredJob.swift
//  ApplyKit
//
//  A job posting surfaced by auto-discovery. `DiscoveredPosting` is the transient
//  shape returned by an ATS list endpoint; `DiscoveredJob` is the persisted inbox
//  record produced after keyword-filtering and dedup (see JobDiscoveryService).
//

import Foundation

enum DiscoveryState: String, Codable {
    case new        // awaiting review in the inbox
    case dismissed  // user rejected it
    case imported   // turned into a JobApplication
    case closed     // vanished from its board — filled or withdrawn
}

/// One posting as returned by an ATS list endpoint, before dedup/persistence.
struct DiscoveredPosting: Sendable, Hashable {
    var externalID: String
    var title: String
    var location: String
    var url: String
    var postedAt: Date?
    /// Some providers hand back the full description during listing (e.g. the
    /// Workday detail fetch, TikTok/ByteDance). When present it seeds
    /// `DiscoveredJob.jobDescription` so opening the posting needs no scrape.
    var descriptionText: String = ""
    /// True when the provider already constrained the query to the board's
    /// location keywords server-side. The client-side location filter is then
    /// skipped — it would wrongly drop multi-office roles whose `location` is a
    /// rollup ("4 Locations") or names a sibling office rather than the match.
    var locationVerified: Bool = false
}

struct DiscoveredJob: Identifiable, Codable, Hashable {
    var id: UUID
    var boardID: UUID
    var externalID: String
    /// `JobURLNormalizer.duplicateKey(for: url)` — the dedup anchor against
    /// applications and prior discoveries.
    var dedupeKey: String
    var title: String
    var companyName: String
    var location: String
    var url: String
    var postedAt: Date?
    var discoveredAt: Date
    var stateRaw: String
    var importedApplicationID: UUID?
    /// Cached job description, scraped on first open so the posting can be read
    /// (and later imported) without re-fetching. Empty until loaded.
    var jobDescription: String
    var jobDescriptionFetchedAt: Date?

    init(id: UUID = UUID(), boardID: UUID, externalID: String, dedupeKey: String,
         title: String, companyName: String, location: String, url: String,
         postedAt: Date? = nil, discoveredAt: Date = Date(),
         state: DiscoveryState = .new, importedApplicationID: UUID? = nil,
         jobDescription: String = "", jobDescriptionFetchedAt: Date? = nil) {
        self.id = id
        self.boardID = boardID
        self.externalID = externalID
        self.dedupeKey = dedupeKey
        self.title = title
        self.companyName = companyName
        self.location = location
        self.url = url
        self.postedAt = postedAt
        self.discoveredAt = discoveredAt
        self.stateRaw = state.rawValue
        self.importedApplicationID = importedApplicationID
        self.jobDescription = jobDescription
        self.jobDescriptionFetchedAt = jobDescriptionFetchedAt
    }

    var state: DiscoveryState {
        get { DiscoveryState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    var displayTitle: String {
        let company = companyName.trimmed
        let role = title.trimmed
        if company.isEmpty && role.isEmpty { return "Untitled Posting" }
        if company.isEmpty { return role }
        if role.isEmpty { return company }
        return "\(company) — \(role)"
    }
}
