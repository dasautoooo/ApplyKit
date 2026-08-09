//
//  AvatureProvider.swift
//  ApplyKit
//
//  Avature powers career sites for enterprises like Bloomberg and IBM.
//  There's no public JSON API — every tenant serves a server-rendered search
//  page at `https://{slug}.avature.net/careers/SearchJobs/` (or a custom
//  domain, e.g. IBM's `careers.ibm.com/en_US`), and many tenants 406-block
//  any client whose TLS/HTTP2 fingerprint isn't a real browser. `BrowserFetcher`
//  (see BrowserBackedProviders.swift, already used for Tesla/Meta) sidesteps
//  that the same way it does there — WebKit carries a genuine fingerprint.
//
//  Markup varies per tenant (Bloomberg uses `article.job`, IBM uses
//  `div.job-item`, others use table rows), so rather than a fixed selector
//  this walks every job-detail anchor and reads title/location from its
//  nearest sensible container — done here as an in-page JS query, the same
//  technique Meta's provider already uses for the same "arbitrary tenant
//  markup" problem.
//
//  Adapted from the MIT-licensed `kalil0321/ats-scrapers`
//  (src/ats_scrapers/scrapers/avature.py). See THIRD_PARTY_NOTICES.md.
//

import Foundation
import WebKit

enum AvatureProvider: JobBoardProvider {
    static let id = "avature"
    static let displayName = "Avature"

    static func board(for url: URL) -> TrackedBoard? {
        guard let slug = ProviderSupport.subdomainSlug(url, suffix: ".avature.net") else { return nil }
        return TrackedBoard(kindRaw: id, slug: slug, companyName: ProviderSupport.humanize(slug))
    }

    /// Custom-domain tenants (IBM's `careers.ibm.com/en_US`) have no
    /// recognizable URL pattern, so they're added as a `BuiltInCompany` entry
    /// instead, which constructs the `TrackedBoard` directly (`host` holds the
    /// domain, `site` the locale path prefix).
    ///
    /// Fails soft — an empty result, not a thrown error — matching Tesla/Meta:
    /// this is the most tenant-variable provider in the app, and one broken
    /// tenant must never abort a refresh across every other board.
    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let base = board.host.map { "https://\($0)\(board.site ?? "")" } ?? "https://\(board.slug).avature.net"
        let searchPath = (board.site?.isEmpty == false) ? "/careers/SearchJobs/" : "/SearchJobs/"
        guard let url = URL(string: base + searchPath) ?? URL(string: base) else { return [] }

        let fetcher = await MainActor.run { () -> BrowserFetcher in
            let fetcher = BrowserFetcher(settleDelay: .seconds(3))
            fetcher.script = Self.extractionScript
            return fetcher
        }
        guard let body = try? await fetcher.text(from: url), !body.isEmpty else { return [] }
        return parse(json: body, base: base)
    }

    private static let extractionScript = """
    (() => JSON.stringify(
      Array.from(document.querySelectorAll(
        'a[href*="/JobDetail/"], a[href*="/ProjectDetail/"], a[href*="/PipelineDetail/"]'
      )).map(a => {
        const container = a.closest('article, li, tr, div[class*="job" i], div[class*="result" i], div[class*="listing" i]') || a;
        const titleEl = container.querySelector('h2, h3, [class*="title" i]');
        const locEl = container.querySelector('[class*="location" i]');
        return {
          href: a.href,
          title: ((titleEl ? titleEl.innerText : a.innerText) || '').trim(),
          location: (locEl ? locEl.innerText : '').trim()
        };
      })
    ))()
    """

    private static let pseudoTitles: Set<String> = [
        "apply", "apply now", "apply online", "learn more", "view job",
        "view all", "see job", "more info", "details"
    ]

    static func parse(json: String, base: String) -> [DiscoveredPosting] {
        guard let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return entries.compactMap { entry -> DiscoveredPosting? in
            guard let href = (entry["href"] as? String)?.trimmed, !href.isEmpty else { return nil }
            var title = (entry["title"] as? String ?? "").trimmed
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard !title.isEmpty, !pseudoTitles.contains(title.lowercased()) else { return nil }
            let id = jobID(from: href)
            guard !id.isEmpty, !seen.contains(id) else { return nil }
            seen.insert(id)
            let location = (entry["location"] as? String ?? "").trimmed
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            title = title
            return DiscoveredPosting(externalID: id, title: title, location: location, url: href, postedAt: nil)
        }
    }

    /// `pipelineId` on the SearchJobsMaps/PipelineDetail variant, else the
    /// path's trailing segment.
    private static func jobID(from href: String) -> String {
        guard let url = URL(string: href) else { return "" }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let pipelineID = components.queryItems?.first(where: { $0.name == "pipelineId" })?.value,
           !pipelineID.isEmpty {
            return pipelineID
        }
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        return path.split(separator: "/").last.map(String.init) ?? ""
    }
}
