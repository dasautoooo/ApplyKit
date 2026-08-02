//
//  MoreATSProviders.swift
//  ApplyKit
//
//  The second tier of multi-tenant ATS platforms. Each is the same shape as the
//  core three: recognize `{slug}` from the board URL, then one (or a few
//  paginated) unauthenticated requests return the company's open roles.
//
//  Endpoint patterns adapted from the MIT-licensed `kalil0321/ats-scrapers`.
//  See THIRD_PARTY_NOTICES.md.
//

import Foundation

// MARK: - SmartRecruiters

enum SmartRecruitersProvider: JobBoardProvider {
    static let id = "smartrecruiters"
    static let displayName = "SmartRecruiters"

    private static let pageSize = 100

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased() else { return nil }
        guard host == "jobs.smartrecruiters.com" || host == "careers.smartrecruiters.com" else { return nil }
        guard let slug = url.pathComponents.filter({ $0 != "/" }).first,
              ProviderSupport.isValidSlug(slug) else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        var results: [DiscoveredPosting] = []
        var offset = 0
        while offset < 5000 {
            let url = try ProviderSupport.url(
                "https://api.smartrecruiters.com/v1/companies/\(board.slug)/postings?limit=\(pageSize)&offset=\(offset)")
            guard let root = try await DiscoveryHTTP.getJSON(url) as? [String: Any] else { break }
            let page = parse(root, slug: board.slug)
            results.append(contentsOf: page)
            let count = (root["content"] as? [[String: Any]])?.count ?? 0
            guard count > 0 else { break }
            offset += pageSize
            if let total = (root["totalFound"] as? NSNumber)?.intValue, offset >= total { break }
            if count < pageSize { break }
        }
        return results
    }

    static func parse(_ json: Any?, slug: String) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any], let content = root["content"] as? [[String: Any]] else { return [] }
        return content.compactMap { item in
            guard let id = DiscoveryHTTP.stringID(item["id"]) else { return nil }
            let location = item["location"] as? [String: Any]
            let text = (location?["fullLocation"] as? String)
                ?? [location?["city"] as? String, location?["region"] as? String]
                    .compactMap { $0 }.joined(separator: ", ")
            return DiscoveredPosting(externalID: id, title: (item["name"] as? String ?? "").trimmed,
                                     location: text.trimmed,
                                     url: "https://jobs.smartrecruiters.com/\(slug)/\(id)",
                                     postedAt: DiscoveryHTTP.isoDate(item["releasedDate"]))
        }
    }
}

// MARK: - Workable

enum WorkableProvider: JobBoardProvider {
    static let id = "workable"
    static let displayName = "Workable"

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "apply.workable.com" {
            guard let slug = url.pathComponents.filter({ $0 != "/" }).first,
                  ProviderSupport.isValidSlug(slug) else { return nil }
            return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
        }
        guard let slug = ProviderSupport.subdomainSlug(url, suffix: ".workable.com") else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url(
            "https://apply.workable.com/api/v1/widget/accounts/\(board.slug)?details=true")
        return parse(try await DiscoveryHTTP.getJSON(url), slug: board.slug)
    }

    static func parse(_ json: Any?, slug: String) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any], let jobs = root["jobs"] as? [[String: Any]] else { return [] }
        return jobs.compactMap { item in
            guard let shortcode = DiscoveryHTTP.stringID(item["shortcode"] ?? item["id"]) else { return nil }
            let link = (item["url"] as? String)?.trimmed
            let city = [item["city"] as? String, item["state"] as? String, item["country"] as? String]
                .compactMap { $0?.trimmed }.filter { !$0.isEmpty }.joined(separator: ", ")
            return DiscoveredPosting(
                externalID: shortcode,
                title: (item["title"] as? String ?? "").trimmed,
                location: (item["location"] as? String)?.trimmed ?? city,
                url: (link?.isEmpty == false) ? link! : "https://apply.workable.com/\(slug)/j/\(shortcode)/",
                postedAt: DiscoveryHTTP.isoDate(item["published_on"] ?? item["created_at"]))
        }
    }
}

// MARK: - Recruitee

enum RecruiteeProvider: JobBoardProvider {
    static let id = "recruitee"
    static let displayName = "Recruitee"

    static func board(for url: URL) -> TrackedBoard? {
        guard let slug = ProviderSupport.subdomainSlug(url, suffix: ".recruitee.com") else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url("https://\(board.slug).recruitee.com/api/offers/")
        return parse(try await DiscoveryHTTP.getJSON(url), slug: board.slug)
    }

    static func parse(_ json: Any?, slug: String) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any], let offers = root["offers"] as? [[String: Any]] else { return [] }
        return offers.compactMap { item in
            guard let id = DiscoveryHTTP.stringID(item["id"]) else { return nil }
            let link = (item["careers_url"] as? String ?? item["careers_apply_url"] as? String)?.trimmed
            let location = [item["city"] as? String, item["country"] as? String]
                .compactMap { $0?.trimmed }.filter { !$0.isEmpty }.joined(separator: ", ")
            let slugPath = (item["slug"] as? String) ?? id
            return DiscoveredPosting(
                externalID: id,
                title: (item["title"] as? String ?? "").trimmed,
                location: (item["location"] as? String)?.trimmed ?? location,
                url: (link?.isEmpty == false) ? link! : "https://\(slug).recruitee.com/o/\(slugPath)",
                postedAt: DiscoveryHTTP.isoDate(item["published_at"] ?? item["created_at"]))
        }
    }
}

// MARK: - Personio

enum PersonioProvider: JobBoardProvider {
    static let id = "personio"
    static let displayName = "Personio"

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased() else { return nil }
        for suffix in [".jobs.personio.com", ".jobs.personio.de"] where host.hasSuffix(suffix) {
            let slug = String(host.dropLast(suffix.count))
            guard ProviderSupport.isValidSlug(slug) else { return nil }
            return TrackedBoard(kindRaw: id, slug: slug, host: host,
                                companyName: ProviderSupport.humanize(slug))
        }
        return nil
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let host = board.host ?? "\(board.slug).jobs.personio.com"
        let url = try ProviderSupport.url("https://\(host)/search.json")
        return parse(try await DiscoveryHTTP.getJSON(url), host: host)
    }

    static func parse(_ json: Any?, host: String) -> [DiscoveredPosting] {
        // Personio returns either a bare array or `{ "jobs": [...] }`.
        let items: [[String: Any]]
        if let array = json as? [[String: Any]] { items = array }
        else if let root = json as? [String: Any], let jobs = root["jobs"] as? [[String: Any]] { items = jobs }
        else { return [] }

        return items.compactMap { item in
            guard let id = DiscoveryHTTP.stringID(item["id"]) else { return nil }
            let office = (item["office"] as? String) ?? (item["office"] as? [String: Any])?["name"] as? String
            return DiscoveredPosting(
                externalID: id,
                title: (item["name"] as? String ?? item["title"] as? String ?? "").trimmed,
                location: (office ?? "").trimmed,
                url: "https://\(host)/job/\(id)",
                postedAt: DiscoveryHTTP.isoDate(item["createdAt"] ?? item["created_at"]))
        }
    }
}

// MARK: - BambooHR

enum BambooHRProvider: JobBoardProvider {
    static let id = "bamboohr"
    static let displayName = "BambooHR"

    static func board(for url: URL) -> TrackedBoard? {
        guard let slug = ProviderSupport.subdomainSlug(url, suffix: ".bamboohr.com") else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url("https://\(board.slug).bamboohr.com/careers/list")
        return parse(try await DiscoveryHTTP.getJSON(url), slug: board.slug)
    }

    static func parse(_ json: Any?, slug: String) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any] else { return [] }
        let items = (root["result"] as? [[String: Any]]) ?? (root["jobs"] as? [[String: Any]]) ?? []
        return items.compactMap { item in
            guard let id = DiscoveryHTTP.stringID(item["id"]) else { return nil }
            let location = item["location"] as? [String: Any]
            let text = [location?["city"] as? String, location?["state"] as? String]
                .compactMap { $0?.trimmed }.filter { !$0.isEmpty }.joined(separator: ", ")
            return DiscoveredPosting(
                externalID: id,
                title: (item["jobOpeningName"] as? String ?? item["title"] as? String ?? "").trimmed,
                location: text,
                url: "https://\(slug).bamboohr.com/careers/\(id)",
                postedAt: DiscoveryHTTP.isoDate(item["datePosted"]))
        }
    }
}

// MARK: - Breezy

enum BreezyProvider: JobBoardProvider {
    static let id = "breezy"
    static let displayName = "Breezy HR"

    static func board(for url: URL) -> TrackedBoard? {
        guard let slug = ProviderSupport.subdomainSlug(url, suffix: ".breezy.hr") else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url("https://\(board.slug).breezy.hr/json")
        return parse(try await DiscoveryHTTP.getJSON(url), slug: board.slug)
    }

    static func parse(_ json: Any?, slug: String) -> [DiscoveredPosting] {
        guard let items = json as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = DiscoveryHTTP.stringID(item["id"]) else { return nil }
            let location = item["location"] as? [String: Any]
            let city = (location?["city"] as? String)
                ?? ((location?["name"] as? String) ?? "")
            let link = (item["url"] as? String)?.trimmed
            return DiscoveredPosting(
                externalID: id,
                title: (item["name"] as? String ?? "").trimmed,
                location: city.trimmed,
                url: (link?.isEmpty == false) ? link! : "https://\(slug).breezy.hr/p/\(id)",
                postedAt: DiscoveryHTTP.isoDate(item["published_date"] ?? item["creation_date"]))
        }
    }
}

// MARK: - JazzHR

enum JazzHRProvider: JobBoardProvider {
    static let id = "jazzhr"
    static let displayName = "JazzHR"

    static func board(for url: URL) -> TrackedBoard? {
        guard let slug = ProviderSupport.subdomainSlug(url, suffix: ".applytojob.com") else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url("https://\(board.slug).applytojob.com/apply/jobs")
        guard let html = try await DiscoveryHTTP.getText(url) else { return [] }
        return parse(html: html, slug: board.slug)
    }

    /// JazzHR has no public JSON list, so scrape the detail links out of the
    /// listing page: `/apply/jobs/details/{id}` anchors carry the title text.
    static func parse(html: String, slug: String) -> [DiscoveredPosting] {
        let pattern = #"(?is)<a[^>]+href=["'][^"']*/apply/([A-Za-z0-9]+)/?[^"']*["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges > 2,
                  let idRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { return nil }
            let id = String(html[idRange])
            guard !seen.contains(id) else { return nil }
            let title = DiscoveryHTTP.plainText(String(html[titleRange])).trimmed
            guard !title.isEmpty else { return nil }
            seen.insert(id)
            return DiscoveredPosting(externalID: id, title: title, location: "",
                                     url: "https://\(slug).applytojob.com/apply/\(id)", postedAt: nil)
        }
    }
}

// MARK: - Teamtailor

enum TeamtailorProvider: JobBoardProvider {
    static let id = "teamtailor"
    static let displayName = "Teamtailor"

    static func board(for url: URL) -> TrackedBoard? {
        guard let slug = ProviderSupport.subdomainSlug(url, suffix: ".teamtailor.com") else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url("https://\(board.slug).teamtailor.com/jobs.rss")
        guard let xml = try await DiscoveryHTTP.getText(url, headers: ["Accept": "application/rss+xml, text/xml"])
        else { return [] }
        return parse(rss: xml)
    }

    /// Teamtailor exposes an RSS feed rather than JSON — a minimal `<item>` parse
    /// is enough for title/link/pubDate.
    static func parse(rss xml: String) -> [DiscoveredPosting] {
        let items = capture(#"(?is)<item>(.*?)</item>"#, in: xml)
        return items.compactMap { item in
            let title = capture(#"(?is)<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>"#, in: item).first?.trimmed ?? ""
            let link = capture(#"(?is)<link>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</link>"#, in: item).first?.trimmed ?? ""
            guard !title.isEmpty, !link.isEmpty else { return nil }
            let location = capture(#"(?is)<location>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</location>"#, in: item).first?.trimmed ?? ""
            return DiscoveredPosting(externalID: link, title: title, location: location,
                                     url: link, postedAt: nil)
        }
    }

    private static func capture(_ pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[r])
        }
    }
}
