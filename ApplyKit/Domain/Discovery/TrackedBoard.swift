//
//  TrackedBoard.swift
//  ApplyKit
//
//  A company job board the user watches for new postings. Derived from a pasted
//  URL via `ATSBoardResolver.board(for:)`, then polled (AI-free) by
//  `JobDiscoveryService`. See DiscoveredJob.swift for the postings it produces.
//

import Foundation

struct TrackedBoard: Identifiable, Codable, Hashable {
    var id: UUID
    /// `JobBoardProvider.id` — the registry key for this board's fetcher.
    var kindRaw: String
    /// Company slug (Greenhouse/Lever/Ashby) or Workday company/tenant identifier.
    var slug: String
    /// Workday tenant host, e.g. `acme.wd5.myworkdayjobs.com`. Nil for other providers.
    var host: String?
    /// Workday site id. Nil for other providers.
    var site: String?
    var companyName: String
    /// Include filter (any-match, case-insensitive substring on title); empty = allow all.
    var titleKeywords: [String]
    /// Reject a posting if any keyword matches its title.
    var excludeKeywords: [String]
    /// Include filter (any-match on location); empty = allow all.
    var locationKeywords: [String]
    var addedAt: Date
    var lastPolledAt: Date?

    init(id: UUID = UUID(), kindRaw: String, slug: String, host: String? = nil, site: String? = nil,
         companyName: String = "", titleKeywords: [String] = [], excludeKeywords: [String] = [],
         locationKeywords: [String] = [], addedAt: Date = Date(), lastPolledAt: Date? = nil) {
        self.id = id
        self.kindRaw = kindRaw
        self.slug = slug
        self.host = host
        self.site = site
        self.companyName = companyName
        self.titleKeywords = titleKeywords
        self.excludeKeywords = excludeKeywords
        self.locationKeywords = locationKeywords
        self.addedAt = addedAt
        self.lastPolledAt = lastPolledAt
    }

    var provider: (any JobBoardProvider.Type)? { JobBoardProviders.provider(id: kindRaw) }

    /// Human label for the platform, e.g. "Greenhouse" or "Amazon".
    var providerName: String { JobBoardProviders.displayName(for: kindRaw) }

    var displayName: String {
        companyName.trimmed.isEmpty ? slug : companyName
    }
}
