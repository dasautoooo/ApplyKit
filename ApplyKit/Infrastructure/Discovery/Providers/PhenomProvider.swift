//
//  PhenomProvider.swift
//  ApplyKit
//
//  Phenom People powers the careers sites of Cisco, Bell, T-Mobile, GE
//  Healthcare and others. Every tenant shares one search endpoint:
//
//      POST {base}/widgets   { ddoKey: "refineSearch", pageName: "search-results", from, size }
//
//  which 403s without a CSRF token seeded by a prior GET of the search page:
//
//      GET {base}/{country}/{lang}/search-results
//
//  Tenants live on their own domains (careers.cisco.com, jobs.bell.ca), so
//  there's no host pattern to match — detection keys off the path shape and
//  the `jobSeqNo` parameter, both of which are Phenom's own.
//
//  Adapted from the MIT-licensed `kalil0321/ats-scrapers`
//  (src/ats_scrapers/scrapers/phenom.py). See THIRD_PARTY_NOTICES.md. Verified
//  against careers.cisco.com: the token arrives in the page HTML rather than a
//  cookie there, so both are read.
//

import Foundation

enum PhenomProvider: JobBoardProvider {
    static let id = "phenom"
    static let displayName = "Phenom"

    /// Phenom's own cap — larger values are ignored.
    private static let pageSize = 100
    /// Guard against a tenant reporting a total it never serves.
    private static let maxPages = 60

    private static let csrfRegex = try! NSRegularExpression(pattern: #""csrfToken"\s*:\s*"([^"]+)""#)

    /// `/{country}/{lang}/{search-results|job|apply}` — the shape every Phenom
    /// tenant serves, whatever domain it sits on.
    private static let pathRegex = try! NSRegularExpression(
        pattern: #"^/([a-z]{2,10})/([a-z]{2})/(search-results|job|jobs|apply)(/|$)"#, options: [.caseInsensitive])

    // MARK: - URL recognition

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.isEmpty ? "/" : url.path
        let range = NSRange(path.startIndex..., in: path)

        var country = "us"
        var lang = "en"
        if let match = pathRegex.firstMatch(in: path, range: range), match.numberOfRanges > 2,
           let countryRange = Range(match.range(at: 1), in: path),
           let langRange = Range(match.range(at: 2), in: path) {
            country = String(path[countryRange]).lowercased()
            lang = String(path[langRange]).lowercased()
        } else {
            // No Phenom-shaped path: only a `jobSeqNo` query param is proof
            // enough, and it carries no locale, so the defaults stand.
            let hasJobSeqNo = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.contains { $0.name.lowercased() == "jobseqno" } ?? false
            guard hasJobSeqNo else { return nil }
        }

        return TrackedBoard(kindRaw: id, slug: host, host: host, site: "\(country)/\(lang)",
                            companyName: companyName(fromHost: host))
    }

    /// `careers.cisco.com` → `Cisco`. The listing payload never names the
    /// employer, so the host is the only source.
    static func companyName(fromHost host: String) -> String {
        let dropped: Set<String> = ["careers", "career", "jobs", "job", "www", "com", "net", "org", "ca", "co", "uk"]
        let parts = host.split(separator: ".").map(String.init).filter { !dropped.contains($0) }
        guard let name = parts.first, !name.isEmpty else { return host }
        return ProviderSupport.humanize(name)
    }

    // MARK: - Listing

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let host = board.host ?? board.slug
        let base = "https://\(host)"
        let (country, lang) = locale(from: board.site)
        let searchURL = try ProviderSupport.url("\(base)/\(country)/\(lang)/search-results")

        // One session throughout: the token is only accepted alongside the
        // cookies the search page sets.
        let session = DiscoveryHTTP.makeSession()
        guard let html = try await DiscoveryHTTP.getText(searchURL, session: session) else { return [] }
        let token = csrfToken(in: html, session: session, url: searchURL)

        var collected: [String: DiscoveredPosting] = [:]
        var total = Int.max
        for page in 0..<maxPages {
            let offset = page * pageSize
            guard offset < total else { break }
            guard let payload = try await search(base: base, country: country, lang: lang,
                                                 token: token, offset: offset, session: session) else { break }
            if let reported = self.total(in: payload) { total = reported }
            let postings = parse(payload, base: base, country: country, lang: lang)
            let before = collected.count
            for posting in postings { collected[posting.externalID] = posting }
            // A page that returned nothing, or nothing new, is the end of the
            // list whatever `totalHits` claims.
            if postings.isEmpty || collected.count == before { break }
        }
        return Array(collected.values)
    }

    static func locale(from site: String?) -> (country: String, lang: String) {
        let parts = (site ?? "").split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return ("us", "en") }
        return (parts[0], parts[1])
    }

    /// The token is a cookie on most tenants and inline JSON on others
    /// (Cisco), so both are tried.
    private static func csrfToken(in html: String, session: URLSession, url: URL) -> String? {
        if let cookies = session.configuration.httpCookieStorage?.cookies(for: url),
           let cookie = cookies.first(where: { $0.name.lowercased().contains("csrf") }) {
            return cookie.value
        }
        let ns = html as NSString
        guard let match = csrfRegex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func search(base: String, country: String, lang: String, token: String?,
                               offset: Int, session: URLSession) async throws -> [String: Any]? {
        let url = try ProviderSupport.url("\(base)/widgets")
        let body: [String: Any] = [
            "lang": "\(lang)_\(country)", "deviceType": "desktop", "country": country,
            "pageName": "search-results", "ddoKey": "refineSearch", "sortBy": "", "subsearch": "",
            "from": offset, "jobs": true, "counts": true,
            "all_fields": ["category", "country", "state", "city"],
            "size": pageSize, "clearAll": false, "jdsource": "facets", "isSliderEnable": false,
            "pageId": "page20", "siteType": "external", "keywords": "", "global": true,
            "selected_fields": [String: String](), "locationData": [String: String]()
        ]
        var headers = [
            "Origin": base,
            "Referer": "\(base)/\(country)/\(lang)/search-results",
            "Accept": "*/*"
        ]
        if let token { headers["x-csrf-token"] = token }
        return try await DiscoveryHTTP.postJSON(url, body: body, headers: headers, session: session) as? [String: Any]
    }

    // MARK: - Parsing

    /// Phenom's envelope varies by tenant version; these are the known shapes.
    static func jobs(in payload: [String: Any]) -> [[String: Any]] {
        let refine = payload["refineSearch"] as? [String: Any]
        if let data = refine?["data"] as? [String: Any], let jobs = data["jobs"] as? [[String: Any]] { return jobs }
        if let jobs = refine?["jobs"] as? [[String: Any]] { return jobs }
        if let hits = refine?["hits"] as? [[String: Any]] { return hits }
        return (payload["jobs"] as? [[String: Any]]) ?? []
    }

    static func total(in payload: [String: Any]) -> Int? {
        guard let refine = payload["refineSearch"] as? [String: Any] else { return nil }
        if let total = (refine["totalHits"] as? NSNumber)?.intValue { return total }
        if let data = refine["data"] as? [String: Any],
           let total = (data["totalHits"] as? NSNumber)?.intValue { return total }
        return (refine["hitsCount"] as? NSNumber)?.intValue
    }

    static func parse(_ payload: [String: Any], base: String, country: String, lang: String) -> [DiscoveredPosting] {
        jobs(in: payload).compactMap { item in
            guard let id = DiscoveryHTTP.stringID(item["jobId"] ?? item["id"]) else { return nil }
            let title = (item["title"] as? String ?? item["jobTitle"] as? String ?? "").trimmed
            guard !title.isEmpty else { return nil }
            return DiscoveredPosting(
                externalID: id,
                title: title,
                location: location(item) ?? "",
                // The careers site the candidate actually browses. `applyUrl`
                // often points at the ATS behind Phenom (Cisco's is Workday),
                // which is not where the posting is read.
                url: jobURL(item, id: id, base: base, country: country, lang: lang, title: title),
                postedAt: DiscoveryHTTP.isoDate(item["postedDate"] ?? item["dateCreated"]))
        }
    }

    private static func jobURL(_ item: [String: Any], id: String, base: String,
                               country: String, lang: String, title: String) -> String {
        if let link = (item["jobUrl"] as? String ?? item["url"] as? String)?.trimmed, !link.isEmpty {
            return link.hasPrefix("http") ? link : base + (link.hasPrefix("/") ? link : "/\(link)")
        }
        let key = DiscoveryHTTP.stringID(item["jobSeqNo"]) ?? id
        let slug = title.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(base)/\(country)/\(lang)/job/\(key)/\(slug)"
    }

    private static func location(_ item: [String: Any]) -> String? {
        let parts = ["city", "state", "country"].compactMap { (item[$0] as? String)?.trimmed }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: ", ") }
        for key in ["location", "cityStateCountry", "cityState"] {
            if let text = (item[key] as? String)?.trimmed, !text.isEmpty { return text }
        }
        return nil
    }
}
