//
//  SuccessFactorsProvider.swift
//  ApplyKit
//
//  SAP SuccessFactors Recruiting Marketing sites expose a credential-free RSS
//  feed at the canonical (typo-included, undocumented but stable) path:
//
//      GET https://{recruiting-marketing-host}/sitemal.xml
//
//  Adapted from the MIT-licensed `kalil0321/ats-scrapers`
//  (src/ats_scrapers/scrapers/successfactors.py). See THIRD_PARTY_NOTICES.md.
//  The Python version also supports the legacy `career?company=…&resultType=XML`
//  feed some older tenants still run; that path isn't ported here since it
//  isn't needed for any tenant this app currently tracks.
//

import Foundation

enum SuccessFactorsProvider: JobBoardProvider {
    static let id = "successfactors"
    static let displayName = "SAP SuccessFactors"

    /// No public URL pattern reliably identifies a SuccessFactors recruiting-
    /// marketing host (it's typically a plain custom domain, e.g. `jobs.sap.com`),
    /// so this provider is never auto-detected — only added as a
    /// `BuiltInCompany` entry, which constructs the `TrackedBoard` directly.
    static func board(for url: URL) -> TrackedBoard? { nil }

    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let host = board.host ?? board.slug
        let url = try ProviderSupport.url("https://\(host)/sitemal.xml")
        guard let xml = try await DiscoveryHTTP.getText(
            url, headers: ["Accept": "application/rss+xml, application/xml, text/xml"]
        ) else { return [] }
        return parse(rss: xml)
    }

    static func parse(rss xml: String) -> [DiscoveredPosting] {
        let items = capture(#"(?is)<item>(.*?)</item>"#, in: xml)
        var seen = Set<String>()
        return items.compactMap { item -> DiscoveredPosting? in
            let link = capture(#"(?is)<link>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</link>"#, in: item).first?.trimmed ?? ""
            guard !link.isEmpty else { return nil }
            // Prefer the Google Merchant namespace id; fall back to the link's
            // trailing path segment.
            let gid = capture(#"(?is)<g:id>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</g:id>"#, in: item).first?.trimmed
            let id = (gid.flatMap { $0.isEmpty ? nil : $0 })
                ?? link.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").last.map(String.init)
                ?? link
            guard !seen.contains(id) else { return nil }
            seen.insert(id)

            let rawTitle = DiscoveryHTTP.plainText(
                capture(#"(?is)<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>"#, in: item).first
            ).trimmed
            let (title, titleLocation) = splitTitleLocation(rawTitle)
            let gLocation = capture(#"(?is)<g:location>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</g:location>"#, in: item)
                .first?.trimmed
            let location = (gLocation?.isEmpty == false ? gLocation : nil) ?? titleLocation ?? ""

            let published = capture(#"(?is)<pubDate>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</pubDate>"#, in: item).first?.trimmed
            return DiscoveredPosting(
                externalID: id, title: title.isEmpty ? "Untitled" : title, location: location, url: link,
                postedAt: DiscoveryHTTP.rfc822Date(published) ?? DiscoveryHTTP.isoDate(published))
        }
    }

    /// Some tenants format titles as `"Title (City, State, Country)"`; strip
    /// the trailing parens into a separate location when present.
    private static func splitTitleLocation(_ raw: String) -> (String, String?) {
        guard let range = raw.range(of: #"^(.+?)\s*\(([^()]+)\)\s*$"#, options: .regularExpression) else {
            return (raw, nil)
        }
        let match = String(raw[range])
        guard let openParen = match.lastIndex(of: "("), let closeParen = match.lastIndex(of: ")"),
              openParen < closeParen else { return (raw, nil) }
        let title = String(match[match.startIndex..<openParen]).trimmed
        let location = String(match[match.index(after: openParen)..<closeParen]).trimmed
        return (title.isEmpty ? raw : title, location.isEmpty ? nil : location)
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
