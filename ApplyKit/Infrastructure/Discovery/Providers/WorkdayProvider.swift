//
//  WorkdayProvider.swift
//  ApplyKit
//
//  Workday is the awkward one, and its quirks are load-bearing:
//
//  * `limit` is hard-capped at 20 — larger values return an error/empty page.
//  * Capped tenants report `total` as exactly 2000 and *wrap back to page 1*
//    past offset 2000, so naive pagination silently re-reads page 1 forever.
//    The fix is to subdivide the query by facet until each slice is under the
//    cap, then paginate each slice.
//  * Some tenants (e.g. NVIDIA) report `total: 0` while serving full pages, so
//    a zero/absent total must never be trusted as "no more results".
//  * Multi-office reqs collapse `locationsText` to a rollup like "3 Locations";
//    the real cities only exist on the per-job detail endpoint.
//
//  This algorithm is ported from the MIT-licensed `kalil0321/ats-scrapers`
//  (src/ats_scrapers/scrapers/workday.py). See THIRD_PARTY_NOTICES.md.
//

import Foundation

enum WorkdayProvider: JobBoardProvider {
    static let id = "workday"
    static let displayName = "Workday"

    /// Workday rejects larger page sizes outright.
    static let pageLimit = 20
    /// Capped tenants report exactly this total; past it, offsets wrap to page 1.
    static let queryTotalCap = 2000
    static let maxSubdivisionDepth = 4
    /// Facets to partition on, in priority order. `workerSubType` is multi-tag —
    /// its slices overlap, but dedup absorbs that, so it's a useful last resort.
    static let subdivisionFacets = ["jobFamilyGroup", "timeType", "locations", "workerSubType"]

    private static let locationRollup = #"^\s*\d+\s+Locations?\s*$"#

    // MARK: - URL recognition

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(), host.hasSuffix(".myworkdayjobs.com") else { return nil }
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 4, parts[1].hasPrefix("wd"), parts[1].dropFirst(2).allSatisfy(\.isNumber) else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }
        guard !segments.isEmpty else { return nil }
        let company = parts[0]
        // An optional `en-US`-style locale prefix precedes the site name.
        let hasLocale = segments[0].range(of: #"^[A-Za-z]{2}(?:-[A-Za-z]{2})?$"#, options: .regularExpression) != nil
        let siteIndex = hasLocale ? 1 : 0
        guard segments.indices.contains(siteIndex) else { return nil }
        let site = segments[siteIndex]
        guard ProviderSupport.isValidSlug(company), ProviderSupport.isValidSlug(site) else { return nil }
        return TrackedBoard(kindRaw: id, slug: company, host: host, site: site,
                            companyName: ProviderSupport.humanize(company))
    }

    // MARK: - Listing

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        guard let host = board.host, let site = board.site else { return [] }
        let endpoint = try ProviderSupport.url("https://\(host)/wday/cxs/\(board.slug)/\(site)/jobs")
        let detailPrefix = "https://\(host)/wday/cxs/\(board.slug)/\(site)"

        // Let Workday do the location filtering: it knows every office a
        // multi-site req covers, which the listing payload never reveals.
        let locationFacets = try await resolveLocationFacets(
            endpoint: endpoint, keywords: board.locationKeywords)

        var collected: [String: DiscoveredPosting] = [:]
        try await exhaust(endpoint: endpoint, host: host, site: site,
                          appliedFacets: locationFacets, depth: 0, into: &collected)

        var postings = Array(collected.values)
        if !locationFacets.isEmpty {
            for index in postings.indices { postings[index].locationVerified = true }
        }
        await enrichRollupLocations(&postings, detailPrefix: detailPrefix)
        return postings
    }

    // MARK: - Server-side location filtering

    struct LocationFacetValue { let parameter: String; let id: String; let descriptor: String }

    /// Map the board's location keywords onto Workday location facet ids.
    ///
    /// Country-level facets (`locationHierarchy1`) are present on an unfiltered
    /// query, but city-level "Sites" (`locations`) only appear once the query is
    /// narrowed — so if a keyword like "toronto" matches no country we run a
    /// second probe with it as `searchText` to surface them.
    static func resolveLocationFacets(endpoint: URL, keywords: [String]) async throws -> [String: [String]] {
        let wanted = keywords.map { $0.trimmed.lowercased() }.filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return [:] }

        var matched: [LocationFacetValue] = []
        if let probe = try await requestPage(endpoint, facets: [:], offset: 0) {
            matched = match(collectLocationFacets(probe["facets"]), keywords: wanted)
        }
        if matched.isEmpty {
            for keyword in wanted {
                guard let probe = try await requestPage(endpoint, facets: [:], offset: 0,
                                                        searchText: keyword) else { continue }
                matched = match(collectLocationFacets(probe["facets"]), keywords: wanted)
                if !matched.isEmpty { break }
            }
        }
        // Prefer the most specific level available: a city "Sites" match beats a
        // whole-country match when both resolved.
        if matched.contains(where: { $0.parameter == "locations" }) {
            matched = matched.filter { $0.parameter == "locations" }
        }
        return matched.reduce(into: [String: [String]]()) { result, value in
            result[value.parameter, default: []].append(value.id)
        }
    }

    /// Flatten Workday's facet tree. Location facets are nested one level deep
    /// under `locationMainGroup`, whose own values are facet groups rather than
    /// selectable values.
    static func collectLocationFacets(_ raw: Any?) -> [LocationFacetValue] {
        guard let facets = raw as? [[String: Any]] else { return [] }
        var found: [LocationFacetValue] = []

        func walk(_ node: [String: Any]) {
            let parameter = node["facetParameter"] as? String
            guard let values = node["values"] as? [[String: Any]] else { return }
            for value in values {
                if value["values"] is [[String: Any]] {
                    walk(value)          // nested group (e.g. locationMainGroup)
                } else if let parameter, isLocationParameter(parameter),
                          let id = value["id"] as? String,
                          let descriptor = value["descriptor"] as? String {
                    found.append(LocationFacetValue(parameter: parameter, id: id, descriptor: descriptor))
                }
            }
        }
        for facet in facets { walk(facet) }
        return found
    }

    static func isLocationParameter(_ parameter: String) -> Bool {
        parameter == "locations" || parameter.hasPrefix("locationHierarchy")
            || parameter.lowercased().contains("location")
    }

    private static func match(_ values: [LocationFacetValue], keywords: [String]) -> [LocationFacetValue] {
        values.filter { value in
            let descriptor = value.descriptor.lowercased()
            // Skip the Office/Remote "Location Type" axis — it isn't a place.
            guard descriptor != "office", descriptor != "remote" else { return false }
            return keywords.contains { descriptor.contains($0) }
        }
    }

    /// Recursively exhaust one facet combination:
    /// - total under the cap → paginate normally
    /// - total at the cap and a spare facet exists → subdivide
    /// - otherwise → take what this capped query can give (bounded at the cap)
    private static func exhaust(endpoint: URL, host: String, site: String,
                                appliedFacets: [String: [String]], depth: Int,
                                into collected: inout [String: DiscoveredPosting]) async throws {
        guard let first = try await requestPage(endpoint, facets: appliedFacets, offset: 0) else { return }
        absorb(first, host: host, site: site, into: &collected)

        let rawCount = (first["jobPostings"] as? [[String: Any]])?.count ?? 0
        guard rawCount > 0 else { return }
        let total = (first["total"] as? NSNumber)?.intValue ?? 0

        // A short first page means that's everything, whatever `total` claims.
        if rawCount < pageLimit { return }

        if total == queryTotalCap, depth < maxSubdivisionDepth,
           let facet = pickFacet(first["facets"], alreadyApplied: Set(appliedFacets.keys)) {
            for value in facet.values {
                var child = appliedFacets
                child[facet.parameter] = [value]
                try await exhaust(endpoint: endpoint, host: host, site: site,
                                  appliedFacets: child, depth: depth + 1, into: &collected)
            }
            return
        }

        // Paginate this slice. Never walk past the cap — offsets wrap there.
        let ceiling = total > 0 ? min(total, queryTotalCap) : queryTotalCap
        var offset = pageLimit
        while offset < ceiling {
            guard let page = try await requestPage(endpoint, facets: appliedFacets, offset: offset) else { break }
            let count = (page["jobPostings"] as? [[String: Any]])?.count ?? 0
            guard count > 0 else { break }
            absorb(page, host: host, site: site, into: &collected)
            offset += pageLimit
            if count < pageLimit { break }
        }
    }

    private static func absorb(_ payload: [String: Any], host: String, site: String,
                               into collected: inout [String: DiscoveredPosting]) {
        for posting in parse(payload, host: host, site: site) {
            collected[posting.url] = posting
        }
    }

    private static func requestPage(_ endpoint: URL, facets: [String: [String]],
                                    offset: Int, searchText: String = "") async throws -> [String: Any]? {
        let body: [String: Any] = ["appliedFacets": facets, "limit": pageLimit,
                                   "offset": offset, "searchText": searchText]
        return try await DiscoveryHTTP.postJSON(endpoint, body: body) as? [String: Any]
    }

    // MARK: - Facet selection

    struct Facet { let parameter: String; let values: [String] }

    /// Best facet to partition on: prefer the priority list, else the one with the
    /// most values. Facets already applied are skipped — reapplying one just hits
    /// the same cap again.
    static func pickFacet(_ raw: Any?, alreadyApplied: Set<String>) -> Facet? {
        guard let facets = raw as? [[String: Any]] else { return nil }
        var byParameter: [String: [String]] = [:]
        for facet in facets {
            guard let parameter = facet["facetParameter"] as? String,
                  !alreadyApplied.contains(parameter),
                  let values = facet["values"] as? [[String: Any]], values.count >= 2 else { continue }
            let ids = values.compactMap { value -> String? in
                guard let id = value["id"] as? String,
                      ((value["count"] as? NSNumber)?.intValue ?? 0) > 0 else { return nil }
                return id
            }
            if !ids.isEmpty { byParameter[parameter] = ids }
        }
        for preferred in subdivisionFacets where byParameter[preferred] != nil {
            return Facet(parameter: preferred, values: byParameter[preferred]!)
        }
        guard let best = byParameter.max(by: { $0.value.count < $1.value.count }) else { return nil }
        return Facet(parameter: best.key, values: best.value)
    }

    // MARK: - Detail enrichment

    static func isRollupLocation(_ text: String) -> Bool {
        text.range(of: locationRollup, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Replace "N Locations" placeholders with the real city list from the detail
    /// endpoint, and pick up the full description while we're there. Best-effort:
    /// a failed detail fetch leaves the listing row untouched.
    private static func enrichRollupLocations(_ postings: inout [DiscoveredPosting],
                                              detailPrefix: String) async {
        let targets = postings.indices.filter { isRollupLocation(postings[$0].location) }
        guard !targets.isEmpty else { return }

        // Enrichment is one request per rollup, so cap the fan-out on unfiltered
        // boards. When a location filter narrowed the set server-side the result
        // is small and worth resolving in full.
        let budget = postings.count <= 400 ? targets.count : 60
        let resolved = await withTaskGroup(of: (Int, String, String)?.self) { group in
            for index in targets.prefix(budget) {
                let path = externalPath(from: postings[index].url)
                guard let path else { continue }
                group.addTask {
                    guard let url = URL(string: detailPrefix + path),
                          let root = try? await DiscoveryHTTP.getJSON(url) as? [String: Any],
                          let info = root["jobPostingInfo"] as? [String: Any] else { return nil }
                    let location = formatLocations(primary: info["location"],
                                                   additional: info["additionalLocations"])
                    let description = DiscoveryHTTP.plainText(info["jobDescription"] as? String)
                    guard !location.isEmpty || !description.isEmpty else { return nil }
                    return (index, location, description)
                }
            }
            var output: [(Int, String, String)] = []
            for await result in group { if let result { output.append(result) } }
            return output
        }

        for (index, location, description) in resolved {
            if !location.isEmpty { postings[index].location = location }
            if !description.isEmpty { postings[index].descriptionText = description }
        }
    }

    /// Workday job URLs are `{base}/{site}{externalPath}` where externalPath
    /// starts with `/job/`; grep for that prefix to stay tenant-independent.
    static func externalPath(from url: String) -> String? {
        guard let range = url.range(of: "/job/") else { return nil }
        return String(url[range.lowerBound...])
    }

    static func formatLocations(primary: Any?, additional: Any?) -> String {
        var locations: [String] = []
        if let primary = (primary as? String)?.trimmed, !primary.isEmpty { locations.append(primary) }
        if let additional = additional as? [Any] {
            for value in additional {
                if let text = (value as? String)?.trimmed, !text.isEmpty { locations.append(text) }
            }
        }
        return locations.joined(separator: " | ")
    }

    // MARK: - Parsing

    static func parse(_ json: Any?, host: String, site: String) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any],
              let postings = root["jobPostings"] as? [[String: Any]] else { return [] }
        return postings.compactMap { item in
            guard let path = (item["externalPath"] as? String)?.trimmed, !path.isEmpty else { return nil }
            let normalized = path.hasPrefix("/") ? path : "/\(path)"
            let external = (item["bulletFields"] as? [String])?.first?.trimmed
            return DiscoveredPosting(
                externalID: (external?.isEmpty == false) ? external! : normalized,
                title: (item["title"] as? String ?? "").trimmed,
                location: (item["locationsText"] as? String ?? "").trimmed,
                url: "https://\(host)/\(site)\(normalized)",
                postedAt: postedDate(item["postedOn"]))
        }
    }

    /// Workday reports post age as relative text ("Posted 5 Days Ago") rather
    /// than a timestamp, so approximate a date for display and sorting.
    static func postedDate(_ value: Any?, now: Date = Date()) -> Date? {
        guard let raw = (value as? String)?.lowercased() else { return nil }
        if raw.contains("today") { return now }
        if raw.contains("yesterday") { return Calendar.current.date(byAdding: .day, value: -1, to: now) }
        if let range = raw.range(of: #"\d+"#, options: .regularExpression), let days = Int(raw[range]) {
            return Calendar.current.date(byAdding: .day, value: -days, to: now)
        }
        return nil
    }
}
