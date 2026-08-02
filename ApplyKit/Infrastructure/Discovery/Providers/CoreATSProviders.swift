//
//  CoreATSProviders.swift
//  ApplyKit
//
//  Greenhouse / Lever / Ashby — the three simplest multi-tenant ATS boards:
//  one unauthenticated GET returns the company's entire posting list.
//  (Workday is complex enough to warrant its own file.)
//
//  Endpoint patterns adapted from the MIT-licensed `kalil0321/ats-scrapers`.
//  See THIRD_PARTY_NOTICES.md.
//

import Foundation

// MARK: - Greenhouse

enum GreenhouseProvider: JobBoardProvider {
    static let id = "greenhouse"
    static let displayName = "Greenhouse"

    private static let hosts: Set<String> = [
        "boards.greenhouse.io", "job-boards.greenhouse.io",
        "boards.eu.greenhouse.io", "job-boards.eu.greenhouse.io"
    ]

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
        // `/embed/job_board?for={slug}` is the embedded variant of the same board.
        if let embedded = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "for" })?.value,
           ProviderSupport.isValidSlug(embedded) {
            return TrackedBoard(kindRaw: id, slug: embedded, companyName: ProviderSupport.humanize(embedded))
        }
        guard let slug = url.pathComponents.filter({ $0 != "/" }).first,
              slug != "embed", ProviderSupport.isValidSlug(slug) else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url("https://boards-api.greenhouse.io/v1/boards/\(board.slug)/jobs")
        return parse(try await DiscoveryHTTP.getJSON(url))
    }

    static func parse(_ json: Any?) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any], let jobs = root["jobs"] as? [[String: Any]] else { return [] }
        return jobs.compactMap { item in
            guard let id = DiscoveryHTTP.stringID(item["id"]),
                  let link = (item["absolute_url"] as? String)?.trimmed, !link.isEmpty else { return nil }
            let location = (item["location"] as? [String: Any])?["name"] as? String ?? ""
            return DiscoveredPosting(externalID: id, title: (item["title"] as? String ?? "").trimmed,
                                     location: location.trimmed, url: link,
                                     postedAt: DiscoveryHTTP.isoDate(item["updated_at"]))
        }
    }
}

// MARK: - Lever

enum LeverProvider: JobBoardProvider {
    static let id = "lever"
    static let displayName = "Lever"

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(),
              ["jobs.lever.co", "jobs.eu.lever.co"].contains(host),
              let slug = url.pathComponents.filter({ $0 != "/" }).first,
              ProviderSupport.isValidSlug(slug) else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, host: host, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let apiHost = (board.host?.contains(".eu.") == true) ? "api.eu.lever.co" : "api.lever.co"
        let url = try ProviderSupport.url("https://\(apiHost)/v0/postings/\(board.slug)?mode=json")
        return parse(try await DiscoveryHTTP.getJSON(url))
    }

    static func parse(_ json: Any?) -> [DiscoveredPosting] {
        guard let postings = json as? [[String: Any]] else { return [] }
        return postings.compactMap { item in
            guard let id = DiscoveryHTTP.stringID(item["id"]),
                  let link = (item["hostedUrl"] as? String)?.trimmed, !link.isEmpty else { return nil }
            let location = (item["categories"] as? [String: Any])?["location"] as? String ?? ""
            return DiscoveredPosting(externalID: id, title: (item["text"] as? String ?? "").trimmed,
                                     location: location.trimmed, url: link,
                                     postedAt: DiscoveryHTTP.epochDate(item["createdAt"]))
        }
    }
}

// MARK: - Ashby

enum AshbyProvider: JobBoardProvider {
    static let id = "ashby"
    static let displayName = "Ashby"

    static func board(for url: URL) -> TrackedBoard? {
        guard url.host?.lowercased() == "jobs.ashbyhq.com",
              let slug = url.pathComponents.filter({ $0 != "/" }).first,
              ProviderSupport.isValidSlug(slug) else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url(
            "https://api.ashbyhq.com/posting-api/job-board/\(board.slug)?includeCompensation=false")
        return parse(try await DiscoveryHTTP.getJSON(url))
    }

    static func parse(_ json: Any?) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any], let jobs = root["jobs"] as? [[String: Any]] else { return [] }
        return jobs.compactMap { item in
            guard let id = DiscoveryHTTP.stringID(item["id"]),
                  let link = ((item["jobUrl"] as? String) ?? (item["applyUrl"] as? String))?.trimmed,
                  !link.isEmpty else { return nil }
            return DiscoveredPosting(externalID: id, title: (item["title"] as? String ?? "").trimmed,
                                     location: (item["location"] as? String ?? "").trimmed, url: link,
                                     postedAt: DiscoveryHTTP.isoDate(item["publishedAt"]))
        }
    }
}
