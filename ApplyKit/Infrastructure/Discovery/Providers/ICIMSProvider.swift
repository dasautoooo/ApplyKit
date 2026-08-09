//
//  ICIMSProvider.swift
//  ApplyKit
//
//  iCIMS career sites are HTML only — no public JSON. Each tenant lives on
//  `careers-{slug}.icims.com` (sometimes `uscareers-{slug}.icims.com`). The
//  visible careers page embeds an iframe with the actual listing; hitting
//  that iframe URL directly skips the wrapper:
//
//      GET https://careers-{slug}.icims.com/jobs/search?ss=1&pr={page}&in_iframe=1
//
//  Each posting is one `<li class="iCIMS_JobCardItem">` card holding the
//  title anchor, a location span, and a relative-time span whose `title`
//  attribute is the absolute posting date.
//
//  Adapted from the MIT-licensed `kalil0321/ats-scrapers`
//  (src/ats_scrapers/scrapers/icims.py). See THIRD_PARTY_NOTICES.md. The
//  Python version also enriches each posting from a schema.org JSON-LD block
//  on its detail page; that per-job fetch isn't ported here — descriptions
//  stay empty, matching how JazzHR's listing-only scrape already behaves.
//

import Foundation

enum ICIMSProvider: JobBoardProvider {
    static let id = "icims"
    static let displayName = "iCIMS"

    private static let maxPages = 200

    private static let cardRegex = try! NSRegularExpression(
        pattern: #"(?is)<li[^>]+class="[^"]*iCIMS_JobCardItem[^"]*"[^>]*>(.*?)</li>"#)
    private static let anchorRegex = try! NSRegularExpression(
        pattern: #"(?is)<a[^>]+href="(https?://[^"]*?/jobs/(\d+)/[^"]*?/job[^"]*)"[^>]*class="[^"]*iCIMS_Anchor[^"]*"[^>]*>(.*?)</a>"#)
    private static let titleRegex = try! NSRegularExpression(pattern: #"(?is)<h3[^>]*>(.*?)</h3>"#)
    private static let locationRegex = try! NSRegularExpression(
        pattern: #"(?is)<span[^>]+class="[^"]*sr-only[^"]*field-label[^"]*"[^>]*>\s*Job Locations\s*</span>\s*<span[^>]*>\s*([^<]*?)\s*</span>"#)
    private static let dateTitleRegex = try! NSRegularExpression(
        pattern: #"<span[^>]+title="(\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}\s*(?:AM|PM)?)""#, options: [.caseInsensitive])

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(), host.hasSuffix(".icims.com") else { return nil }
        let prefix = host.hasPrefix("careers-") ? "careers-"
            : host.hasPrefix("uscareers-") ? "uscareers-" : nil
        guard let prefix else { return nil }
        let slug = String(host.dropFirst(prefix.count)).split(separator: ".").first.map(String.init) ?? ""
        guard ProviderSupport.isValidSlug(slug) else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, host: host, companyName: ProviderSupport.humanize(slug))
    }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let host = board.host ?? "careers-\(board.slug).icims.com"
        var collected: [String: DiscoveredPosting] = [:]
        for page in 0..<maxPages {
            let url = try ProviderSupport.url("https://\(host)/jobs/search?ss=1&pr=\(page)&in_iframe=1")
            guard let html = try await DiscoveryHTTP.getText(url) else { break }
            let postings = parse(html: html)
            let before = collected.count
            for posting in postings { collected[posting.externalID] = posting }
            if postings.isEmpty || collected.count == before { break }
        }
        return Array(collected.values)
    }

    static func parse(html: String) -> [DiscoveredPosting] {
        let full = html as NSString
        let cards = cardRegex.matches(in: html, range: NSRange(location: 0, length: full.length))
        var seen = Set<String>()
        var results: [DiscoveredPosting] = []
        for card in cards {
            guard card.numberOfRanges > 1 else { continue }
            let body = full.substring(with: card.range(at: 1))
            let bodyNS = body as NSString
            guard let anchor = anchorRegex.firstMatch(in: body, range: NSRange(location: 0, length: bodyNS.length)),
                  anchor.numberOfRanges > 3 else { continue }
            let href = bodyNS.substring(with: anchor.range(at: 1))
            let jobID = bodyNS.substring(with: anchor.range(at: 2))
            guard !seen.contains(jobID) else { continue }
            let inner = bodyNS.substring(with: anchor.range(at: 3))
            guard let titleMatch = titleRegex.firstMatch(in: inner, range: NSRange(location: 0, length: (inner as NSString).length)),
                  titleMatch.numberOfRanges > 1 else { continue }
            let title = DiscoveryHTTP.plainText((inner as NSString).substring(with: titleMatch.range(at: 1))).trimmed
            guard !title.isEmpty else { continue }
            seen.insert(jobID)

            let location = firstCapture(locationRegex, in: body)?.trimmed ?? ""
            let postedAt = firstCapture(dateTitleRegex, in: body).flatMap(parseICIMSDate)
            results.append(DiscoveredPosting(
                externalID: jobID, title: title, location: location,
                url: href.replacingOccurrences(of: "&amp;", with: "&"), postedAt: postedAt))
        }
        return results
    }

    private static func firstCapture(_ regex: NSRegularExpression, in value: String) -> String? {
        let ns = value as NSString
        guard let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "M/d/yyyy h:mm a"
        return f
    }()

    private static func parseICIMSDate(_ text: String) -> Date? {
        dateFormatter.date(from: text.trimmed)
    }
}
