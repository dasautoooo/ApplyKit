//
//  BigTechProviders.swift
//  ApplyKit
//
//  Large employers that run bespoke career backends instead of a multi-tenant
//  ATS. Each is a single fixed company, so `TrackedBoard.slug` is just the
//  company id and URL recognition matches their careers host.
//
//  Endpoint patterns adapted from the MIT-licensed `kalil0321/ats-scrapers`.
//  See THIRD_PARTY_NOTICES.md.
//

import Foundation

// MARK: - Amazon

enum AmazonProvider: JobBoardProvider {
    static let id = "amazon"
    static let displayName = "Amazon"
    static let isSingleCompany = true

    private static let pageSize = 100
    /// Amazon stops returning hits once offset + limit passes 10k.
    private static let paginationCap = 10_000

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(),
              host == "amazon.jobs" || host == "www.amazon.jobs" else { return nil }
        return TrackedBoard(kindRaw: id, slug: id, companyName: displayName)
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        var results: [DiscoveredPosting] = []
        var offset = 0
        while offset < paginationCap {
            let url = try ProviderSupport.url(
                "https://www.amazon.jobs/en/search.json?result_limit=\(pageSize)&offset=\(offset)&sort=recent")
            guard let root = try await DiscoveryHTTP.getJSON(url) as? [String: Any] else { break }
            let page = parse(root)
            guard !page.isEmpty else { break }
            results.append(contentsOf: page)
            offset += pageSize
            if let hits = (root["hits"] as? NSNumber)?.intValue, offset >= hits { break }
            if page.count < pageSize { break }
        }
        return results
    }

    static func parse(_ json: Any?) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any], let jobs = root["jobs"] as? [[String: Any]] else { return [] }
        return jobs.compactMap { item in
            guard let path = (item["job_path"] as? String)?.trimmed, !path.isEmpty else { return nil }
            let identifier = DiscoveryHTTP.stringID(item["id_icims"] ?? item["id"]) ?? path
            return DiscoveredPosting(
                externalID: identifier,
                title: (item["title"] as? String ?? "").trimmed,
                location: (item["normalized_location"] as? String ?? item["location"] as? String ?? "").trimmed,
                url: "https://www.amazon.jobs\(path)",
                postedAt: nil,
                descriptionText: DiscoveryHTTP.plainText(item["description"] as? String))
        }
    }
}

// MARK: - Apple

enum AppleProvider: JobBoardProvider {
    static let id = "apple"
    static let displayName = "Apple"
    static let isSingleCompany = true

    static func board(for url: URL) -> TrackedBoard? {
        guard url.host?.lowercased() == "jobs.apple.com" else { return nil }
        return TrackedBoard(kindRaw: id, slug: id, companyName: displayName)
    }

    /// Apple gates search behind a CSRF token: GET the token endpoint, then send
    /// it back as a header on each search POST. Both calls must share a session
    /// so the accompanying cookie sticks.
    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let session = DiscoveryHTTP.makeSession()
        let tokenURL = try ProviderSupport.url("https://jobs.apple.com/api/v1/CSRFToken")
        let headers = try await DiscoveryHTTP.head(tokenURL, session: session)
        guard let token = headerValue(headers, name: "X-Apple-CSRF-Token") else { return [] }

        let searchURL = try ProviderSupport.url("https://jobs.apple.com/api/v1/search")
        var results: [DiscoveredPosting] = []
        var page = 1
        while page <= 250 {
            let body: [String: Any] = [
                "query": "", "filters": [:], "page": page, "locale": "en-us", "sort": "",
                "format": ["longDate": "MMMM D, YYYY", "mediumDate": "MMM D, YYYY"]
            ]
            let json = try await DiscoveryHTTP.postJSON(
                searchURL, body: body,
                headers: ["X-Apple-CSRF-Token": token, "Referer": "https://jobs.apple.com/en-us/search"],
                session: session)
            let batch = parse(json)
            guard !batch.isEmpty else { break }
            results.append(contentsOf: batch)
            page += 1
        }
        return results
    }

    private static func headerValue(_ headers: [AnyHashable: Any], name: String) -> String? {
        for (key, value) in headers where (key as? String)?.caseInsensitiveCompare(name) == .orderedSame {
            return value as? String
        }
        return nil
    }

    static func parse(_ json: Any?) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any],
              let res = root["res"] as? [String: Any],
              let results = res["searchResults"] as? [[String: Any]] else { return [] }
        return results.compactMap { item in
            guard let positionID = DiscoveryHTTP.stringID(item["positionId"]) else { return nil }
            let locations = (item["locations"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String }.joined(separator: " | ") ?? ""
            let transformed = (item["transformedPostingTitle"] as? String) ?? (item["postingTitle"] as? String) ?? ""
            return DiscoveredPosting(
                externalID: positionID,
                title: transformed.trimmed,
                location: locations.trimmed,
                url: "https://jobs.apple.com/en-us/details/\(positionID)",
                postedAt: DiscoveryHTTP.isoDate(item["postingDate"]),
                descriptionText: DiscoveryHTTP.plainText(item["jobSummary"] as? String))
        }
    }
}

// MARK: - Uber

enum UberProvider: JobBoardProvider {
    static let id = "uber"
    static let displayName = "Uber"
    static let isSingleCompany = true

    private static let pageSize = 100

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(), host.hasSuffix("uber.com"),
              url.path.lowercased().contains("careers") else { return nil }
        return TrackedBoard(kindRaw: id, slug: id, companyName: displayName)
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url("https://www.uber.com/api/loadSearchJobsResults?localeCode=en")
        var results: [DiscoveredPosting] = []
        var page = 0
        while page < 60 {
            // `limit` and `page` must sit at the top level, not inside `params`.
            let body: [String: Any] = [
                "limit": pageSize, "page": page,
                "params": ["department": [], "location": []]
            ]
            let json = try await DiscoveryHTTP.postJSON(
                url, body: body, headers: ["x-csrf-token": "x"])
            let batch = parse(json)
            guard !batch.isEmpty else { break }
            results.append(contentsOf: batch)
            page += 1
            if batch.count < pageSize { break }
        }
        return results
    }

    static func parse(_ json: Any?) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any],
              let data = root["data"] as? [String: Any],
              let results = data["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { item in
            guard let identifier = DiscoveryHTTP.stringID(item["id"]) else { return nil }
            let location = item["location"] as? [String: Any]
            let text = [location?["city"] as? String, location?["region"] as? String,
                        location?["countryName"] as? String]
                .compactMap { $0?.trimmed }.filter { !$0.isEmpty }.joined(separator: ", ")
            return DiscoveredPosting(
                externalID: identifier,
                title: (item["title"] as? String ?? "").trimmed,
                location: text,
                url: "https://www.uber.com/global/en/careers/list/\(identifier)/",
                postedAt: DiscoveryHTTP.epochDate(item["creationDate"] ?? item["updatedDate"]),
                descriptionText: DiscoveryHTTP.plainText(item["description"] as? String))
        }
    }
}

// MARK: - TikTok / ByteDance (shared backend)

/// TikTok and ByteDance run the same recruiting backend behind different hosts
/// and a `website-path` header, so they share one parser.
enum ATSxCareers {
    static func fetch(apiURL: String, websitePath: String, origin: String,
                      jobURLPrefix: String) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url(apiURL)
        var results: [DiscoveredPosting] = []
        var offset = 0
        let pageSize = 100
        while offset < 5000 {
            let body: [String: Any] = [
                "keyword": "", "limit": pageSize, "offset": offset,
                "job_category_id_list": [], "location_code_list": []
            ]
            let json = try await DiscoveryHTTP.postJSON(url, body: body, headers: [
                "website-path": websitePath,
                "origin": origin,
                "referer": origin + "/"
            ])
            let batch = parse(json, jobURLPrefix: jobURLPrefix)
            guard !batch.isEmpty else { break }
            results.append(contentsOf: batch)
            offset += pageSize
            if batch.count < pageSize { break }
        }
        return results
    }

    static func parse(_ json: Any?, jobURLPrefix: String) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any],
              let data = root["data"] as? [String: Any],
              let posts = data["job_post_list"] as? [[String: Any]] else { return [] }
        return posts.compactMap { item in
            guard let identifier = DiscoveryHTTP.stringID(item["id"]) else { return nil }
            let city = (item["city_info"] as? [String: Any])?["en_name"] as? String ?? ""
            let description = [item["description"] as? String, item["requirement"] as? String]
                .compactMap { $0 }.joined(separator: "\n\n")
            return DiscoveredPosting(
                externalID: identifier,
                title: (item["title"] as? String ?? "").trimmed,
                location: city.trimmed,
                url: "\(jobURLPrefix)\(identifier)",
                postedAt: DiscoveryHTTP.epochDate(item["publish_time"]),
                descriptionText: DiscoveryHTTP.plainText(description))
        }
    }
}

enum TikTokProvider: JobBoardProvider {
    static let id = "tiktok"
    static let displayName = "TikTok"
    static let isSingleCompany = true

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(),
              host.contains("lifeattiktok.com") || host.contains("careers.tiktok.com") else { return nil }
        return TrackedBoard(kindRaw: id, slug: id, companyName: displayName)
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        try await ATSxCareers.fetch(
            apiURL: "https://api.lifeattiktok.com/api/v1/public/supplier/search/job/posts",
            websitePath: "tiktok",
            origin: "https://lifeattiktok.com",
            jobURLPrefix: "https://lifeattiktok.com/search/")
    }
}

enum ByteDanceProvider: JobBoardProvider {
    static let id = "bytedance"
    static let displayName = "ByteDance"
    static let isSingleCompany = true

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(),
              host.contains("bytedance.com") || host.contains("joinbytedance.com") else { return nil }
        return TrackedBoard(kindRaw: id, slug: id, companyName: displayName)
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        // `website-path: en` is required — other values are refused with 400.
        try await ATSxCareers.fetch(
            apiURL: "https://jobs.bytedance.com/api/v1/public/supplier/search/job/posts",
            websitePath: "en",
            origin: "https://joinbytedance.com",
            jobURLPrefix: "https://jobs.bytedance.com/en/position/")
    }
}

// MARK: - Google

enum GoogleProvider: JobBoardProvider {
    static let id = "google"
    static let displayName = "Google"
    static let isSingleCompany = true

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(), host.hasSuffix("google.com"),
              url.path.lowercased().contains("careers") else { return nil }
        return TrackedBoard(kindRaw: id, slug: id, companyName: displayName)
    }

    /// Google publishes no JSON API and its CSS class names are obfuscated, so we
    /// target the stable accessibility contract instead: every job link carries
    /// `aria-label="Learn more about <Title>"`.
    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        var results: [DiscoveredPosting] = []
        for page in 1...20 {
            let url = try ProviderSupport.url(
                "https://www.google.com/about/careers/applications/jobs/results?hl=en_US&page=\(page)")
            guard let html = try await DiscoveryHTTP.getText(url) else { break }
            let batch = parse(html: html)
            guard !batch.isEmpty else { break }
            results.append(contentsOf: batch)
        }
        return results
    }

    static func parse(html: String) -> [DiscoveredPosting] {
        let pattern = #"(?is)<a[^>]+href=["']([^"']*jobs/results/[^"']+)["'][^>]*aria-label=["']Learn more about ([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges > 2,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { return nil }
            var href = String(html[hrefRange])
            if href.hasPrefix("/") { href = "https://www.google.com\(href)" }
            else if !href.hasPrefix("http") { href = "https://www.google.com/about/careers/applications/\(href)" }
            guard !seen.contains(href) else { return nil }
            seen.insert(href)
            let title = String(html[titleRange]).trimmed
            let identifier = href.split(separator: "/").last.map(String.init) ?? href
            return DiscoveredPosting(externalID: identifier, title: title, location: "",
                                     url: href, postedAt: nil)
        }
    }
}
