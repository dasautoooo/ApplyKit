//
//  EightfoldProvider.swift
//  ApplyKit
//
//  Eightfold AI ("PCSX") powers the careers sites of many large enterprises —
//  Microsoft, Cisco, Nvidia, and others — behind one shared search endpoint:
//
//      GET {tenant}/api/pcsx/search?domain={company_domain}&query=&start=N&sort_by=timestamp
//
//  `tenant` is usually `https://{slug}.eightfold.ai`; some tenants (Microsoft)
//  sit on a custom domain instead, which `TrackedBoard.host` carries.
//
//  Adapted from the MIT-licensed `kalil0321/ats-scrapers`
//  (src/ats_scrapers/scrapers/eightfold.py). See THIRD_PARTY_NOTICES.md. The
//  Python version also falls back to a browser-fingerprint client when a
//  tenant's WAF 403s a plain request, and to a separate "SmartApply" endpoint
//  for tenants where PCSX itself is disabled — neither is ported here; those
//  tenants surface as a per-board polling error instead of silently working.
//

import Foundation

enum EightfoldProvider: JobBoardProvider {
    static let id = "eightfold"
    static let displayName = "Eightfold AI"

    private static let pageSize = 10

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased() else { return nil }
        if let slug = ProviderSupport.subdomainSlug(url, suffix: ".eightfold.ai") {
            return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
        }
        // Custom-domain tenants (e.g. Microsoft's `apply.careers.microsoft.com`)
        // carry no recognizable host suffix, so this half only recognizes the
        // `.eightfold.ai` shape; custom domains are added as a `BuiltInCompany`
        // entry instead, which constructs the `TrackedBoard` directly.
        _ = host
        return nil
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let base = "https://\(board.host ?? "\(board.slug).eightfold.ai")"
        let domain = board.host ?? "\(board.slug).com"
        let endpoint = try ProviderSupport.url("\(base)/api/pcsx/search")

        var collected: [String: DiscoveredPosting] = [:]
        guard let first = try await requestPage(endpoint, domain: domain, start: 0) else { return [] }
        absorb(first, base: base, into: &collected)

        let count = (first["count"] as? NSNumber)?.intValue ?? 0
        var offset = pageSize
        while offset < count {
            guard let page = try await requestPage(endpoint, domain: domain, start: offset) else { break }
            let before = collected.count
            absorb(page, base: base, into: &collected)
            offset += pageSize
            // A page that added nothing new means the tenant's count is stale.
            if collected.count == before { break }
        }
        return Array(collected.values)
    }

    private static func absorb(_ payload: [String: Any], base: String,
                               into collected: inout [String: DiscoveredPosting]) {
        for posting in parse(payload, base: base) {
            collected[posting.externalID] = posting
        }
    }

    private static func requestPage(_ endpoint: URL, domain: String, start: Int) async throws -> [String: Any]? {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "domain", value: domain),
            URLQueryItem(name: "query", value: ""),
            URLQueryItem(name: "location", value: ""),
            URLQueryItem(name: "start", value: String(start)),
            URLQueryItem(name: "sort_by", value: "timestamp")
        ]
        guard let requestURL = components?.url else { return nil }
        guard let root = try await DiscoveryHTTP.getJSON(requestURL) as? [String: Any] else { return nil }
        return root["data"] as? [String: Any]
    }

    static func parse(_ payload: Any?, base: String) -> [DiscoveredPosting] {
        guard let root = payload as? [String: Any],
              let positions = root["positions"] as? [[String: Any]] else { return [] }
        return positions.compactMap { item in
            let id = DiscoveryHTTP.stringID(item["displayJobId"] ?? item["id"] ?? item["atsJobId"])
            guard let id else { return nil }
            let position = (item["canonicalPositionUrl"] as? String) ?? (item["positionUrl"] as? String)
            let url: String
            if let position, position.hasPrefix("/") { url = base + position }
            else if let position, !position.isEmpty { url = position }
            else { url = "\(base)/careers/job/\(id)" }
            return DiscoveredPosting(
                externalID: id,
                title: (item["name"] as? String ?? item["title"] as? String ?? "").trimmed,
                location: location(item) ?? "",
                url: url,
                postedAt: DiscoveryHTTP.epochDate(item["postedTs"] ?? item["creationTs"] ?? item["t_create"])
                    ?? DiscoveryHTTP.isoDate(item["postedTs"]))
        }
    }

    /// `standardizedLocations` / `locations` are string lists like
    /// `"United States, Washington, Redmond"`; older tenants use dicts.
    private static func location(_ item: [String: Any]) -> String? {
        for key in ["standardizedLocations", "locations"] {
            guard let list = item[key] as? [Any], let first = list.first else { continue }
            if let text = (first as? String)?.trimmed, !text.isEmpty { return text }
            if let dict = first as? [String: Any] {
                return (dict["city"] as? String) ?? (dict["country"] as? String) ?? (dict["name"] as? String)
            }
        }
        return nil
    }
}
