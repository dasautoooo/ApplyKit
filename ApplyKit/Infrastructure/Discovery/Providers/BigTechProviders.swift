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
                // Amazon reports a written-out date ("August 6, 2026"), not a timestamp.
                postedAt: DiscoveryHTTP.longDate(item["posted_date"]),
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
            // `transformedPostingTitle` is the URL slug ("in-business-expert"), not a
            // display title — it belongs in the path, and `postingTitle` on the row.
            let title = (item["postingTitle"] as? String)?.trimmed ?? ""
            let slug = (item["transformedPostingTitle"] as? String)?.trimmed ?? ""
            let path = slug.isEmpty ? positionID : "\(positionID)/\(slug)"
            return DiscoveredPosting(
                externalID: positionID,
                title: title,
                location: locations.trimmed,
                url: "https://jobs.apple.com/en-us/details/\(path)",
                // `postingDate` is a localized string ("Aug 06, 2026") that no ISO parser
                // accepts; `postDateInGMT` is the real timestamp.
                postedAt: DiscoveryHTTP.isoDate(item["postDateInGMT"])
                    ?? DiscoveryHTTP.longDate(item["postingDate"]),
                descriptionText: DiscoveryHTTP.plainText(item["jobSummary"] as? String))
        }
    }
}

// MARK: - Uber

enum UberProvider: JobBoardProvider {
    static let id = "uber"
    static let displayName = "Uber"
    static let isSingleCompany = true

    // Uber's board runs on Oracle Recruiting Cloud; jobs.uber.com is just a front end
    // that links there. The legacy www.uber.com/api/loadSearchJobsResults endpoint still
    // answers, but a large share of what it returns are requisitions with no public page
    // at all — 171 of 400 sampled — so it can't be used as the listing.
    private static let oracleHost = "https://iaziqy.fa.ocs.oraclecloud.com"
    private static let oracleSite = "UberCareers"
    private static let oracleSiteNumber = "CX_1"
    /// The service caps a page at 200 however large a `limit` we ask for.
    private static let pageSize = 200

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased() else { return nil }
        let isUberCareers = host == "jobs.uber.com"
            || (host.hasSuffix("uber.com") && url.path.lowercased().contains("careers"))
        let isOracleBoard = host.hasSuffix("oraclecloud.com")
            && url.path.contains(oracleSite)
        guard isUberCareers || isOracleBoard else { return nil }
        return TrackedBoard(kindRaw: id, slug: id, companyName: displayName)
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        var results: [DiscoveredPosting] = []
        var offset = 0
        var total = Int.max
        while offset < total, offset < 5_000 {
            let url = try ProviderSupport.url(
                "\(oracleHost)/hcmRestApi/resources/latest/recruitingCEJobRequisitions"
                + "?onlyData=true&expand=requisitionList.secondaryLocations"
                + "&finder=findReqs;siteNumber=\(oracleSiteNumber),limit=\(pageSize),offset=\(offset)"
                + ",sortBy=POSTING_DATES_DESC")
            let json = try await DiscoveryHTTP.getJSON(url)
            if let reported = reportedTotal(json) { total = reported }
            let batch = parse(json)
            guard !batch.isEmpty else { break }
            results.append(contentsOf: batch)
            offset += pageSize
        }
        return results
    }

    private static func reportedTotal(_ json: Any?) -> Int? {
        guard let root = json as? [String: Any],
              let items = root["items"] as? [[String: Any]],
              let count = (items.first?["TotalJobsCount"] as? NSNumber)?.intValue else { return nil }
        return count
    }

    static func jobURL(id identifier: String) -> String {
        "\(oracleHost)/hcmUI/CandidateExperience/en/sites/\(oracleSite)/job/\(identifier)"
    }

    static func parse(_ json: Any?) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any],
              let items = root["items"] as? [[String: Any]],
              let requisitions = items.first?["requisitionList"] as? [[String: Any]] else { return [] }
        return requisitions.compactMap { item in
            guard let identifier = DiscoveryHTTP.stringID(item["Id"]) else { return nil }
            // Roles are frequently open in several offices at once; keeping only the
            // primary one makes a city filter miss them.
            let secondary = (item["secondaryLocations"] as? [[String: Any]])?
                .compactMap { $0["Name"] as? String } ?? []
            let offices = ([item["PrimaryLocation"] as? String] + secondary.map { Optional($0) })
                .compactMap { $0?.trimmed }.filter { !$0.isEmpty }
            return DiscoveredPosting(
                externalID: identifier,
                title: (item["Title"] as? String ?? "").trimmed,
                location: offices.joined(separator: " | "),
                url: jobURL(id: identifier),
                // Plain calendar dates ("2026-08-06").
                postedAt: DiscoveryHTTP.longDate(item["PostedDate"]))
            // The listing carries no body — Oracle keeps it on the requisition detail,
            // so the description is left to the lazy on-open render.
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
            // Qualify the city with its parent region, so "Singapore" or "London"
            // still matches a country-level location filter.
            let cityInfo = item["city_info"] as? [String: Any]
            let city = (cityInfo?["en_name"] as? String)?.trimmed ?? ""
            let region = ((cityInfo?["parent"] as? [String: Any])?["en_name"] as? String)?.trimmed ?? ""
            let location = region.isEmpty || region == city ? city : "\(city), \(region)"
            let description = [item["description"] as? String, item["requirement"] as? String]
                .compactMap { $0 }.joined(separator: "\n\n")
            return DiscoveredPosting(
                externalID: identifier,
                title: (item["title"] as? String ?? "").trimmed,
                location: location,
                url: "\(jobURLPrefix)\(identifier)",
                // This backend exposes no posting date — the payload carries only an
                // (always null) `expiry_time`. Left nil rather than faked.
                postedAt: nil,
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

    private static let maximumPages = 20
    /// Each extra location keyword costs a full pagination sweep, so cap the fan-out.
    private static let maximumLocationQueries = 4

    /// Google publishes no JSON API, but its results page ships the whole result set
    /// as an `AF_initDataCallback` payload — locations, posting timestamps, and the
    /// full description included. Reading that is both richer and steadier than
    /// scraping markup whose class names are obfuscated.
    ///
    /// The page caps out around 20 pages of 20, so a board filtered to one city can
    /// never be reached by paging alone; `location=` narrows the query server-side
    /// first. That filter is fuzzy (it ranks rather than restricts), so
    /// `locationVerified` stays false and `passesFilters` remains the authority.
    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let queries = board.locationKeywords
            .map { $0.trimmed }.filter { !$0.isEmpty }
            .prefix(maximumLocationQueries)
        var collected: [String: DiscoveredPosting] = [:]
        for location in (queries.isEmpty ? [""] : Array(queries)) {
            for page in 1...maximumPages {
                var query = "hl=en_US&page=\(page)"
                if !location.isEmpty,
                   let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    query += "&location=\(encoded)"
                }
                let url = try ProviderSupport.url(
                    "https://www.google.com/about/careers/applications/jobs/results?\(query)")
                guard let html = try await DiscoveryHTTP.getText(url) else { break }
                let batch = parse(html: html)
                guard !batch.isEmpty else { break }
                for posting in batch where collected[posting.url] == nil {
                    collected[posting.url] = posting
                }
            }
        }
        return Array(collected.values)
    }

    static func parse(html: String) -> [DiscoveredPosting] {
        jobRecords(in: html).compactMap(posting(from:))
    }

    /// Pulls the job array out of the page's embedded data callbacks.
    ///
    /// The page ships several such blocks — one of them is a short list of Google's sub-brands
    /// (DeepMind, GFiber, …) with the same outer shape as the jobs block, so a block is chosen
    /// by whether its records actually look like jobs rather than by position or key name.
    private static func jobRecords(in html: String) -> [[Any]] {
        let pattern = #"(?s)AF_initDataCallback\((\{.*?\})\);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let blockRange = Range(match.range(at: 1), in: html) else { continue }
            let block = String(html[blockRange])
            guard let payload = dataArray(in: block),
                  let jobs = payload.first as? [Any] else { continue }
            let records = jobs.compactMap { $0 as? [Any] }
            if records.contains(where: looksLikeJob) { return records }
        }
        return []
    }

    /// A job record is long enough to hold the fields we read and carries a locations array;
    /// the sub-brand records are three fields long with no locations.
    private static func looksLikeJob(_ record: [Any]) -> Bool {
        record.count > Field.posted
            && record[safe: Field.locations] is [Any]
            && ((record[safe: Field.title] as? String)?.trimmed.isEmpty == false)
    }

    /// Extracts the `data:` value of a callback block. Scans for the matching bracket
    /// rather than regexing, since the array contains nested brackets and quoted HTML.
    private static func dataArray(in block: String) -> [Any]? {
        guard let marker = block.range(of: "data:") else { return nil }
        guard let start = block[marker.upperBound...].firstIndex(of: "[") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < block.endIndex {
            let character = block[index]
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" { inString.toggle() }
            else if !inString {
                if character == "[" { depth += 1 }
                else if character == "]" {
                    depth -= 1
                    if depth == 0 {
                        let json = String(block[start...index])
                        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any]
                    }
                }
            }
            index = block.index(after: index)
        }
        return nil
    }

    /// Field positions in a job record. Named because bare indices into a 21-element
    /// array are unreadable, and this is the one place the payload's shape is asserted.
    private enum Field {
        static let id = 0, title = 1, responsibilities = 3, qualifications = 4
        static let locations = 9, summary = 10, posted = 12
    }

    private static func posting(from record: [Any]) -> DiscoveredPosting? {
        guard let identifier = DiscoveryHTTP.stringID(record[safe: Field.id]),
              let title = (record[safe: Field.title] as? String)?.trimmed, !title.isEmpty
        else { return nil }

        let locations = ((record[safe: Field.locations] as? [Any]) ?? [])
            .compactMap { ($0 as? [Any])?[safe: 0] as? String }
            .map { $0.trimmed }.filter { !$0.isEmpty }
            .joined(separator: " | ")

        // Each HTML blob is wrapped as [null, "<html>"].
        func markup(_ index: Int) -> String? { (record[safe: index] as? [Any])?[safe: 1] as? String }
        let body = [markup(Field.summary), markup(Field.responsibilities), markup(Field.qualifications)]
            .compactMap { $0 }.joined(separator: "\n\n")

        // Timestamps arrive as [seconds, nanoseconds].
        let posted = ((record[safe: Field.posted] as? [Any])?[safe: 0] as? NSNumber)
            .flatMap { DiscoveryHTTP.epochDate($0) }

        return DiscoveredPosting(
            externalID: identifier,
            title: title,
            location: locations,
            url: "https://www.google.com/about/careers/applications/jobs/results/\(identifier)",
            postedAt: posted,
            descriptionText: DiscoveryHTTP.plainText(body))
    }
}

private extension Array {
    /// Bounds-checked lookup, so a shortened record degrades to nil fields instead of trapping.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
