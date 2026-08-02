//
//  BrowserBackedProviders.swift
//  ApplyKit
//
//  Tesla and Meta can't be fetched with URLSession: Tesla's catalog endpoint is
//  behind Akamai bot management (403s a plain client) and Meta's board is a
//  React app whose data arrives via token-authenticated GraphQL. The Python
//  reference project reaches for a stealth Chromium here; on macOS we already
//  have a real browser engine in WebKit, which carries a genuine TLS
//  fingerprint and runs the JS challenge.
//
//  These two are the most fragile providers in the app. Both fail soft —
//  returning [] rather than throwing — so one broken scraper never aborts a
//  refresh across every other board.
//
//  Adapted from the MIT-licensed `kalil0321/ats-scrapers`. See
//  THIRD_PARTY_NOTICES.md.
//

import Foundation
import WebKit

/// Loads a URL in an offscreen WKWebView and returns the resulting document
/// text, letting bot-management challenges resolve first.
@MainActor
final class BrowserFetcher: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private let settleDelay: Duration

    init(settleDelay: Duration = .seconds(2)) {
        self.settleDelay = settleDelay
    }

    /// JavaScript evaluated once the page has settled. Defaults to the document
    /// text; providers can supply an extraction script instead.
    var script = "document.body ? document.body.innerText : ''"

    func text(from url: URL) async throws -> String {
        if continuation != nil {
            finish(.failure(JobImportError.renderedPageFailed("Another page is already loading.")))
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: 30))
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(35))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(JobImportError.renderedPageFailed("The page timed out.")))
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Let client-side rendering / bot challenges settle before reading.
            try? await Task.sleep(for: settleDelay)
            webView.evaluateJavaScript(self.script) { [weak self] result, error in
                guard let self else { return }
                if let error {
                    self.finish(.failure(JobImportError.renderedPageFailed(error.localizedDescription)))
                    return
                }
                self.finish(.success(result as? String ?? ""))
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume(with: result)
    }
}

// MARK: - Tesla

enum TeslaProvider: JobBoardProvider {
    static let id = "tesla"
    static let displayName = "Tesla"
    static let isSingleCompany = true

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(), host.hasSuffix("tesla.com"),
              url.path.lowercased().contains("careers") else { return nil }
        return TrackedBoard(kindRaw: id, slug: id, companyName: displayName)
    }

    /// `cua-api/apps/careers/state` returns the entire catalog as one JSON
    /// document, but Akamai rejects non-browser clients — so load it in WebKit
    /// and parse the rendered body text as JSON.
    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url("https://www.tesla.com/cua-api/apps/careers/state")
        let text = await MainActor.run { BrowserFetcher() }
        guard let body = try? await text.text(from: url), !body.isEmpty,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return parse(json)
    }

    static func parse(_ json: Any?) -> [DiscoveredPosting] {
        guard let root = json as? [String: Any] else { return [] }
        // Listings live under `sitedata.listings`; locations/departments are
        // lookup tables keyed by id.
        let listings = ((root["listings"] as? [[String: Any]])
            ?? ((root["sitedata"] as? [String: Any])?["listings"] as? [[String: Any]])) ?? []
        let lookups = (root["lookup"] as? [String: Any]) ?? [:]
        let locations = (lookups["locations"] as? [String: Any]) ?? [:]

        return listings.compactMap { item in
            guard let identifier = DiscoveryHTTP.stringID(item["id"]) else { return nil }
            let locationID = DiscoveryHTTP.stringID(item["l"] ?? item["location"]) ?? ""
            let locationName = (locations[locationID] as? [String: Any])?["name"] as? String
                ?? (item["location"] as? String ?? "")
            return DiscoveredPosting(
                externalID: identifier,
                title: (item["t"] as? String ?? item["title"] as? String ?? "").trimmed,
                location: locationName.trimmed,
                url: "https://www.tesla.com/careers/search/job/\(identifier)",
                postedAt: nil)
        }
    }
}

// MARK: - Meta

enum MetaProvider: JobBoardProvider {
    static let id = "meta"
    static let displayName = "Meta"
    static let isSingleCompany = true

    static func board(for url: URL) -> TrackedBoard? {
        guard let host = url.host?.lowercased(),
              host.contains("metacareers.com") else { return nil }
        return TrackedBoard(kindRaw: id, slug: id, companyName: displayName)
    }

    /// Meta's board is a React SPA fed by token-authenticated GraphQL, so there
    /// is no endpoint to call directly. We render the results page and pull the
    /// job anchors straight out of the DOM — `/jobs/{id}/` links are the one
    /// stable contract. Most breakage-prone provider in the app; fails soft.
    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting] {
        let url = try ProviderSupport.url("https://www.metacareers.com/jobs")
        let fetcher = await MainActor.run { () -> BrowserFetcher in
            let fetcher = BrowserFetcher(settleDelay: .seconds(4))
            fetcher.script = """
            (() => JSON.stringify(
              Array.from(document.querySelectorAll('a[href*="/jobs/"]'))
                .map(a => ({ href: a.href, text: (a.innerText || '').trim() }))
                .filter(x => /\\/jobs\\/\\d+/.test(x.href) && x.text.length > 2)
            ))()
            """
            return fetcher
        }
        guard let body = try? await fetcher.text(from: url), !body.isEmpty else { return [] }
        return parse(json: body)
    }

    static func parse(json: String) -> [DiscoveredPosting] {
        guard let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let href = (entry["href"] as? String)?.trimmed, !href.isEmpty,
                  let text = (entry["text"] as? String)?.trimmed, !text.isEmpty,
                  !seen.contains(href) else { return nil }
            seen.insert(href)
            // The title is the anchor's first line; later lines are metadata.
            let title = text.split(separator: "\n").first.map(String.init)?.trimmed ?? text
            let identifier = href.split(separator: "/").last(where: { Int($0) != nil }).map(String.init) ?? href
            return DiscoveredPosting(externalID: identifier, title: title, location: "",
                                     url: href, postedAt: nil)
        }
    }
}
