//
//  CornerstoneProvider.swift
//  ApplyKit
//
//  Cornerstone OnDemand career sites live at:
//      https://{slug}.csod.com/ux/ats/careersite/{site_id}/home?c={slug}
//
//  The flow is two-step: GET the career-site HTML and pull a JWT
//  (`csod.context.token`) plus the regional API host out of it, then POST to
//  `{api_host}/rec-job-search/external/jobs` with that JWT as a bearer token
//  to get the paginated listing.
//
//  Adapted from the MIT-licensed `kalil0321/ats-scrapers`
//  (src/ats_scrapers/scrapers/cornerstone.py). See THIRD_PARTY_NOTICES.md.
//

import Foundation

enum CornerstoneProvider: JobBoardProvider {
    static let id = "cornerstone"
    static let displayName = "Cornerstone OnDemand"

    private static let pageSize = 25
    private static let defaultAPIHost = "https://na.api.csod.com"

    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"csod\.context\.token\s*=\s*['"]([^'"]+)['"]"#)
    private static let tokenFallbackRegex = try! NSRegularExpression(pattern: #""token"\s*:\s*"([^"]+)""#)
    private static let apiHostRegex = try! NSRegularExpression(pattern: #"(https?://[a-z0-9-]+\.api\.csod\.com)"#)

    static func board(for url: URL) -> TrackedBoard? {
        guard let slug = ProviderSupport.subdomainSlug(url, suffix: ".csod.com") else { return nil }
        let siteID = url.pathComponents.first { Int($0) != nil } ?? "1"
        return TrackedBoard(kindRaw: id, slug: slug, site: siteID, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let siteID = board.site ?? "1"
        let careerURL = try ProviderSupport.url(
            "https://\(board.slug).csod.com/ux/ats/careersite/\(siteID)/home?c=\(board.slug)")
        guard let html = try await DiscoveryHTTP.getText(careerURL) else { return [] }
        guard let token = firstCapture(tokenRegex, in: html) ?? firstCapture(tokenFallbackRegex, in: html) else {
            throw JobImportError.requestFailed("Couldn't find a session token on the Cornerstone career page.")
        }
        let apiHost = firstCapture(apiHostRegex, in: html) ?? defaultAPIHost
        let origin = "https://\(board.slug).csod.com"

        var collected: [String: DiscoveredPosting] = [:]
        guard let first = try await search(apiHost: apiHost, token: token, origin: origin, siteID: siteID, page: 1)
        else { return [] }
        let data = (first["data"] as? [String: Any]) ?? [:]
        let total = (data["totalCount"] as? NSNumber)?.intValue ?? 0
        absorb(data["requisitions"], slug: board.slug, origin: origin, siteID: siteID, into: &collected)

        let firstPageCount = (data["requisitions"] as? [[String: Any]])?.count ?? 0
        if total > firstPageCount, firstPageCount > 0 {
            let lastPage = Int(ceil(Double(total) / Double(pageSize)))
            for page in 2...max(lastPage, 2) {
                guard let payload = try await search(apiHost: apiHost, token: token, origin: origin,
                                                     siteID: siteID, page: page) else { break }
                let pageData = (payload["data"] as? [String: Any]) ?? [:]
                absorb(pageData["requisitions"], slug: board.slug, origin: origin, siteID: siteID, into: &collected)
            }
        }
        return Array(collected.values)
    }

    private static func absorb(_ raw: Any?, slug: String, origin: String, siteID: String,
                               into collected: inout [String: DiscoveredPosting]) {
        for posting in parse(raw, slug: slug, origin: origin, siteID: siteID) {
            collected[posting.externalID] = posting
        }
    }

    private static func search(apiHost: String, token: String, origin: String, siteID: String,
                               page: Int) async throws -> [String: Any]? {
        let url = try ProviderSupport.url("\(apiHost)/rec-job-search/external/jobs")
        let body: [String: Any] = [
            "careerSiteId": Int(siteID) ?? 1, "careerSitePageId": Int(siteID) ?? 1,
            "pageNumber": page, "pageSize": pageSize, "cultureId": 1, "cultureName": "en-US"
        ]
        let headers = ["Authorization": "Bearer \(token)", "Origin": origin, "Referer": origin + "/"]
        return try await DiscoveryHTTP.postJSON(url, body: body, headers: headers) as? [String: Any]
    }

    static func parse(_ raw: Any?, slug: String, origin: String, siteID: String) -> [DiscoveredPosting] {
        guard let requisitions = raw as? [[String: Any]] else { return [] }
        return requisitions.compactMap { item in
            guard let id = DiscoveryHTTP.stringID(item["requisitionId"]) else { return nil }
            let title = (item["displayJobTitle"] as? String)?.trimmed ?? "Untitled"
            return DiscoveredPosting(
                externalID: id, title: title, location: location(item["locations"]) ?? "",
                url: "\(origin)/ux/ats/careersite/\(siteID)/job/\(id)?c=\(slug)",
                postedAt: DiscoveryHTTP.isoDate(item["postingEffectiveDate"]))
        }
    }

    private static func location(_ raw: Any?) -> String? {
        guard let list = raw as? [Any], let first = list.first else { return nil }
        if let text = (first as? String)?.trimmed, !text.isEmpty { return text }
        guard let dict = first as? [String: Any] else { return nil }
        let parts = ["city", "state", "country"].compactMap { (dict[$0] as? String)?.trimmed }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: ", ") }
        return (dict["name"] as? String) ?? (dict["displayName"] as? String)
    }

    private static func firstCapture(_ regex: NSRegularExpression, in value: String) -> String? {
        let ns = value as NSString
        guard let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
