import AppKit
import Foundation
import WebKit

@MainActor
enum AIBackendRunner {
    static func run(prompt: String, settings: AppSettings) async throws -> String {
        let prefersClaude = settings.preferredAIBackendRaw != "Codex"
        let claude = settings.claudeCLIPath.trimmed.isEmpty ? nil : settings.claudeCLIPath
        let codex = settings.codexCLIPath.trimmed.isEmpty ? nil : settings.codexCLIPath

        if prefersClaude, let claude {
            return try await ClaudeService.run(prompt: prompt, claudePath: claude, workingDirectory: nil)
        }
        if let codex {
            return try await CodexService.run(prompt: prompt, codexPath: codex, workingDirectory: nil)
                .standardOutput.trimmed
        }
        if let claude {
            return try await ClaudeService.run(prompt: prompt, claudePath: claude, workingDirectory: nil)
        }
        throw JobImportError.missingAIBackend
    }

    static func isConfigured(_ settings: AppSettings) -> Bool {
        !settings.claudeCLIPath.trimmed.isEmpty || !settings.codexCLIPath.trimmed.isEmpty
    }
}

@MainActor
final class JobPageScraper {
    private let renderedLoader = RenderedJobPageLoader()
    private let maximumResponseBytes = 2_000_000

    func scrape(url: URL) async throws -> JobPageContent {
        let atsContent = try? await ATSJobAPIResolver.resolve(url: url)
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 Safari/605.1.15 ApplyKit/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        var staticFailure: Error?
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JobImportError.requestFailed("The server did not return an HTTP response.")
            }
            guard (200...299).contains(http.statusCode) else {
                throw JobImportError.requestFailed("The server returned HTTP \(http.statusCode).")
            }
            guard data.count <= maximumResponseBytes else { throw JobImportError.oversizedResponse }
            let mime = (http.mimeType ?? "").lowercased()
            guard mime.isEmpty || mime.contains("html") || mime.contains("xhtml") else {
                throw JobImportError.unsupportedContent
            }
            guard let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                throw JobImportError.unsupportedContent
            }
            let resolvedURL = http.url ?? url
            let content = merge(
                page: HTMLJobExtractor.extract(html: html, url: resolvedURL, wasRendered: false),
                ats: atsContent
            )
            if content.isLikelyUsable { return content }
            staticFailure = JobImportError.noUsableJobContent
        } catch {
            staticFailure = error
        }

        if let atsContent, atsContent.isLikelyUsable {
            return atsContent
        }

        do {
            let rendered = try await renderedLoader.load(url: url)
            let content = merge(page: rendered, ats: atsContent)
            guard content.isLikelyUsable else { throw JobImportError.noUsableJobContent }
            return content
        } catch {
            if let importFailure = staticFailure as? JobImportError,
               case .oversizedResponse = importFailure {
                throw JobImportError.oversizedResponse
            }
            let detail = error.localizedDescription
            throw JobImportError.renderedPageFailed(detail)
        }
    }

    private func merge(page: JobPageContent, ats: JobPageContent?) -> JobPageContent {
        guard let ats else { return page }
        var merged = page
        merged.jobPostingJSON = String(
            ([ats.jobPostingJSON, page.jobPostingJSON]
                .filter { !$0.trimmed.isEmpty }
                .joined(separator: "\n\n"))
                .prefix(80_000)
        )
        if ats.visibleText.count > page.visibleText.count / 2 {
            merged.visibleText = ats.visibleText
        }
        // The scraped page never yields a canonical body; only the ATS does.
        merged.canonicalDescription = ats.canonicalDescription
        return merged
    }
}

/// ATS endpoint patterns and field mappings are adapted from the MIT-licensed
/// `kalil0321/ats-scrapers` project. See THIRD_PARTY_NOTICES.md.
enum ATSJobAPIResolver {
    enum Kind: String, Sendable {
        case greenhouse
        case lever
        case ashby
        case workday
    }

    struct APIRequest: Sendable {
        var kind: Kind
        var sourceURL: URL
        var apiURL: URL
        var companySlug: String
        var jobID: String
    }

    static func resolve(url: URL) async throws -> JobPageContent? {
        guard let apiRequest = request(for: url) else { return nil }
        var request = URLRequest(url: apiRequest.apiURL, timeoutInterval: 18)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) ApplyKit/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              data.count <= 5_000_000,
              let payload = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return content(from: payload, request: apiRequest)
    }

    static func request(for url: URL) -> APIRequest? {
        guard let host = url.host?.lowercased() else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }

        let greenhouseHosts = Set([
            "boards.greenhouse.io", "job-boards.greenhouse.io",
            "boards.eu.greenhouse.io", "job-boards.eu.greenhouse.io"
        ])
        if greenhouseHosts.contains(host),
           let slug = segments.first,
           let jobsIndex = segments.firstIndex(of: "jobs"),
           segments.indices.contains(jobsIndex + 1) {
            let id = segments[jobsIndex + 1]
            return makeRequest(
                kind: .greenhouse,
                sourceURL: url,
                api: "https://boards-api.greenhouse.io/v1/boards/\(slug)/jobs/\(id)",
                slug: slug,
                jobID: id
            )
        }

        if ["jobs.lever.co", "jobs.eu.lever.co"].contains(host),
           segments.count >= 2 {
            let slug = segments[0]
            let id = segments[1]
            let apiHost = host.contains(".eu.") ? "api.eu.lever.co" : "api.lever.co"
            return makeRequest(
                kind: .lever,
                sourceURL: url,
                api: "https://\(apiHost)/v0/postings/\(slug)/\(id)",
                slug: slug,
                jobID: id
            )
        }

        if host == "jobs.ashbyhq.com", segments.count >= 2 {
            let slug = segments[0]
            let id = segments[1]
            return makeRequest(
                kind: .ashby,
                sourceURL: url,
                api: "https://api.ashbyhq.com/posting-api/job-board/\(slug)?includeCompensation=true",
                slug: slug,
                jobID: id
            )
        }

        let hostParts = host.split(separator: ".").map(String.init)
        if hostParts.count >= 4,
           hostParts[1].hasPrefix("wd"),
           hostParts[1].dropFirst(2).allSatisfy(\.isNumber),
           host.hasSuffix(".myworkdayjobs.com"),
           segments.count >= 3 {
            let company = hostParts[0]
            let hasLocalePrefix = segments[0].range(
                of: #"^[A-Za-z]{2}(?:-[A-Za-z]{2})?$"#,
                options: .regularExpression
            ) != nil
            let siteIndex = hasLocalePrefix ? 1 : 0
            guard segments.indices.contains(siteIndex) else { return nil }
            let site = segments[siteIndex]
            let externalPath = segments.dropFirst(siteIndex + 1).joined(separator: "/")
            return makeRequest(
                kind: .workday,
                sourceURL: url,
                api: "https://\(host)/wday/cxs/\(company)/\(site)/\(externalPath)",
                slug: company,
                jobID: segments.last ?? externalPath
            )
        }

        return nil
    }

    static func content(from payload: Any, request: APIRequest) -> JobPageContent? {
        switch request.kind {
        case .greenhouse:
            guard let item = payload as? [String: Any] else { return nil }
            return makeContent(
                item: item,
                request: request,
                title: item["title"] as? String,
                descriptions: [item["content"] as? String],
                companyHint: request.companySlug
            )

        case .lever:
            guard let item = payload as? [String: Any] else { return nil }
            var descriptions = [item["description"] as? String]
            for section in (item["lists"] as? [[String: Any]]) ?? [] {
                let heading = section["text"] as? String ?? ""
                let body = section["content"] as? String ?? ""
                descriptions.append(heading.isEmpty ? body : "<h3>\(heading)</h3>\(body)")
            }
            if descriptions.compactMap({ $0 }).allSatisfy({ $0.trimmed.isEmpty }) {
                descriptions.append(item["descriptionPlain"] as? String)
            }
            return makeContent(
                item: item,
                request: request,
                title: item["text"] as? String,
                descriptions: descriptions,
                companyHint: request.companySlug
            )

        case .ashby:
            guard let root = payload as? [String: Any],
                  let jobs = root["jobs"] as? [[String: Any]],
                  let item = jobs.first(where: {
                      ($0["id"] as? String) == request.jobID
                          || urlsMatch($0["jobUrl"] as? String, request.sourceURL)
                          || urlsMatch($0["applyUrl"] as? String, request.sourceURL)
                  }) else { return nil }
            return makeContent(
                item: item,
                request: request,
                title: item["title"] as? String,
                descriptions: [
                    item["descriptionHtml"] as? String,
                    item["descriptionPlain"] as? String
                ],
                companyHint: request.companySlug
            )

        case .workday:
            guard let root = payload as? [String: Any],
                  let item = root["jobPostingInfo"] as? [String: Any] else { return nil }
            return makeContent(
                item: item,
                request: request,
                title: item["title"] as? String,
                descriptions: [item["jobDescription"] as? String],
                companyHint: item["company"] as? String ?? request.companySlug
            )
        }
    }

    private static func makeRequest(
        kind: Kind,
        sourceURL: URL,
        api: String,
        slug: String,
        jobID: String
    ) -> APIRequest? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !slug.isEmpty, !jobID.isEmpty,
              slug.unicodeScalars.allSatisfy(allowed.contains),
              jobID.unicodeScalars.allSatisfy(allowed.contains),
              let apiURL = URL(string: api) else { return nil }
        return APIRequest(
            kind: kind,
            sourceURL: sourceURL,
            apiURL: apiURL,
            companySlug: slug,
            jobID: jobID
        )
    }

    private static func makeContent(
        item: [String: Any],
        request: APIRequest,
        title: String?,
        descriptions: [String?],
        companyHint: String
    ) -> JobPageContent? {
        guard JSONSerialization.isValidJSONObject(item),
              let data = try? JSONSerialization.data(withJSONObject: item),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let descriptionHTML = descriptions.compactMap { $0 }
            .filter { !$0.trimmed.isEmpty }
            .joined(separator: "\n\n")
            .decodingBasicHTMLEntities()
        let description = HTMLJobExtractor.extract(
            html: descriptionHTML,
            url: request.sourceURL,
            wasRendered: false
        ).visibleText
        return JobPageContent(
            sourceURL: request.sourceURL,
            pageTitle: title ?? "",
            metadataDescription: "ATS: \(request.kind.rawValue); company identifier: \(companyHint)",
            jobPostingJSON: String(json.prefix(70_000)),
            visibleText: String(description.prefix(80_000)),
            wasRendered: false,
            // The ATS handed us the posting body directly, so it needs no
            // AI cleanup — only the surrounding chrome-free HTML strip above.
            canonicalDescription: String(description.prefix(80_000))
        )
    }

    private static func urlsMatch(_ value: String?, _ sourceURL: URL) -> Bool {
        guard let value,
              let lhs = JobURLNormalizer.duplicateKey(for: value),
              let rhs = JobURLNormalizer.duplicateKey(for: sourceURL.absoluteString) else { return false }
        return lhs == rhs
    }
}

enum HTMLJobExtractor {
    static func extract(html: String, url: URL, wasRendered: Bool) -> JobPageContent {
        let limitedHTML = String(html.prefix(2_000_000))
        let jsonBlocks = captures(
            pattern: #"(?is)<script\b[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#,
            in: limitedHTML
        )
        let title = firstCapture(pattern: #"(?is)<title[^>]*>(.*?)</title>"#, in: limitedHTML) ?? ""
        let metaDescription = metaContent(named: "description", in: limitedHTML)
        let withoutNoise = limitedHTML
            .replacing(pattern: #"(?is)<script\b[^>]*>.*?</script>"#, with: " ")
            .replacing(pattern: #"(?is)<style\b[^>]*>.*?</style>"#, with: " ")
            .replacing(pattern: #"(?is)<noscript\b[^>]*>.*?</noscript>"#, with: " ")
        let text = withoutNoise
            // Turn block-level boundaries into newlines so paragraphs, list items,
            // and headings survive tag-stripping (readable text + better AI input).
            .replacing(pattern: #"(?is)</?(?:br|p|div|li|ul|ol|h[1-6]|tr|table|section|article|header|footer)[^>]*>"#, with: "\n")
            .replacing(pattern: #"(?s)<[^>]+>"#, with: " ")
            .decodingBasicHTMLEntities()
            .collapsingWhitespace(preservingNewlines: true)

        return JobPageContent(
            sourceURL: url,
            pageTitle: title.decodingBasicHTMLEntities().collapsingWhitespace(),
            metadataDescription: metaDescription.decodingBasicHTMLEntities().collapsingWhitespace(),
            jobPostingJSON: String(jsonBlocks.joined(separator: "\n").prefix(60_000)),
            visibleText: String(text.prefix(80_000)),
            wasRendered: wasRendered
        )
    }

    private static func metaContent(named name: String, in html: String) -> String {
        for tag in captures(pattern: #"(?is)(<meta\b[^>]*>)"#, in: html) {
            var attributes: [String: String] = [:]
            for pair in captures(
                pattern: #"(?is)([a-zA-Z_:.-]+)\s*=\s*["'](.*?)["']"#,
                in: tag,
                captureGroups: 2
            ) {
                let pieces = pair.split(separator: "\u{1E}", maxSplits: 1).map(String.init)
                if pieces.count == 2 {
                    attributes[pieces[0].lowercased()] = pieces[1]
                }
            }
            let key = (attributes["name"] ?? attributes["property"] ?? "").lowercased()
            if key == name.lowercased() || key == "og:\(name.lowercased())" {
                return attributes["content"] ?? ""
            }
        }
        return ""
    }

    private static func firstCapture(pattern: String, in value: String) -> String? {
        captures(pattern: pattern, in: value).first
    }

    private static func captures(
        pattern: String,
        in value: String,
        captureGroups: Int = 1
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            if captureGroups == 1 {
                guard match.numberOfRanges > 1,
                      let swiftRange = Range(match.range(at: 1), in: value) else { return nil }
                return String(value[swiftRange])
            }
            var values: [String] = []
            for index in 1...captureGroups {
                guard match.numberOfRanges > index,
                      let swiftRange = Range(match.range(at: index), in: value) else { return nil }
                values.append(String(value[swiftRange]))
            }
            return values.joined(separator: "\u{1E}")
        }
    }
}

@MainActor
private final class RenderedJobPageLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<JobPageContent, Error>?
    private var timeoutTask: Task<Void, Never>?

    func load(url: URL) async throws -> JobPageContent {
        if continuation != nil {
            finish(with: .failure(JobImportError.renderedPageFailed("Another page is already loading.")))
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: url, timeoutInterval: 25))
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { return }
                self?.finish(with: .failure(JobImportError.renderedPageFailed("The page timed out.")))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = """
        (() => JSON.stringify({
          title: document.title || "",
          description: document.querySelector('meta[name="description"]')?.content
            || document.querySelector('meta[property="og:description"]')?.content || "",
          jsonLD: Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
            .map(node => node.textContent || ""),
          text: document.body?.innerText || ""
        }))()
        """
        webView.evaluateJavaScript(script) { [weak self, weak webView] result, error in
            guard let self else { return }
            if let error {
                self.finish(with: .failure(JobImportError.renderedPageFailed(error.localizedDescription)))
                return
            }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let resolvedURL = webView?.url else {
                self.finish(with: .failure(JobImportError.noUsableJobContent))
                return
            }
            let content = JobPageContent(
                sourceURL: resolvedURL,
                pageTitle: (object["title"] as? String ?? "").collapsingWhitespace(),
                metadataDescription: (object["description"] as? String ?? "").collapsingWhitespace(),
                jobPostingJSON: String(((object["jsonLD"] as? [String]) ?? []).joined(separator: "\n").prefix(60_000)),
                visibleText: String((object["text"] as? String ?? "").collapsingWhitespace(preservingNewlines: true).prefix(80_000)),
                wasRendered: true
            )
            self.finish(with: .success(content))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<JobPageContent, Error>) {
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

private extension String {
    func replacing(pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        return regex.stringByReplacingMatches(
            in: self,
            range: NSRange(startIndex..., in: self),
            withTemplate: replacement
        )
    }

    func decodingBasicHTMLEntities() -> String {
        replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacing(pattern: #"&#(\d+);"#, with: " ")
    }

    func collapsingWhitespace(preservingNewlines: Bool = false) -> String {
        if preservingNewlines {
            return components(separatedBy: .newlines)
                .map { $0.replacing(pattern: #"[ \t]+"#, with: " ").trimmed }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        return replacing(pattern: #"\s+"#, with: " ").trimmed
    }
}
