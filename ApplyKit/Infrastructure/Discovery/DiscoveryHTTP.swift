//
//  DiscoveryHTTP.swift
//  ApplyKit
//
//  Shared networking for discovery providers. Beyond a plain URLSession call
//  these need per-provider headers, a cookie-bearing session (Apple's CSRF
//  handshake), and retry-with-backoff — several ATS backends throttle bursts
//  with 403/429 rather than failing outright.
//

import Foundation

enum DiscoveryHTTP {
    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private static let maximumResponseBytes = 12_000_000
    private static let maxRetries = 3
    private static let retryBackoff = 1.5
    private static let maxRetryDelay: TimeInterval = 8
    private static let retryableStatuses: Set<Int> = [403, 429, 502, 503, 504]

    /// Session with its own cookie jar so multi-step handshakes (CSRF token →
    /// search) keep their cookies together and don't leak into other providers.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = HTTPCookieStorage()
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 25
        return URLSession(configuration: config)
    }

    // MARK: - Requests

    static func getJSON(_ url: URL, headers: [String: String] = [:],
                        session: URLSession? = nil) async throws -> Any? {
        try await send(request(url, method: "GET", headers: headers), session: session).json
    }

    static func postJSON(_ url: URL, body: [String: Any], headers: [String: String] = [:],
                         session: URLSession? = nil) async throws -> Any? {
        var req = request(url, method: "POST", headers: headers)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req, session: session).json
    }

    static func getText(_ url: URL, headers: [String: String] = [:],
                        session: URLSession? = nil) async throws -> String? {
        var merged = headers
        if merged["Accept"] == nil { merged["Accept"] = "text/html,application/xhtml+xml" }
        let result = try await send(request(url, method: "GET", headers: merged), session: session)
        guard let data = result.data else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// Returns response headers alongside the body — used by Apple's CSRF step,
    /// where the token arrives as a response header rather than in the payload.
    @discardableResult
    static func head(_ url: URL, headers: [String: String] = [:],
                     session: URLSession) async throws -> [AnyHashable: Any] {
        try await send(request(url, method: "GET", headers: headers), session: session).headers
    }

    // MARK: - Core

    private static func request(_ url: URL, method: String, headers: [String: String]) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = method
        req.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        return req
    }

    private struct Result {
        var data: Data?
        var headers: [AnyHashable: Any]
        var json: Any? {
            guard let data else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    private static func send(_ request: URLRequest, session: URLSession?) async throws -> Result {
        let session = session ?? .shared
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw JobImportError.requestFailed("The server did not return an HTTP response.")
                }
                if http.statusCode == 404 {
                    throw JobImportError.requestFailed("Not found (HTTP 404).")
                }
                if (200...299).contains(http.statusCode) {
                    guard data.count <= maximumResponseBytes else { throw JobImportError.oversizedResponse }
                    return Result(data: data, headers: http.allHeaderFields)
                }
                if retryableStatuses.contains(http.statusCode), attempt < maxRetries - 1 {
                    let retryAfter = (http.allHeaderFields["Retry-After"] as? String).flatMap(Double.init)
                    try await sleep(retryAfter ?? pow(retryBackoff, Double(attempt)))
                    continue
                }
                throw JobImportError.requestFailed("The board returned HTTP \(http.statusCode).")
            } catch let error as JobImportError {
                throw error
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    try await sleep(pow(retryBackoff, Double(attempt)))
                    continue
                }
            }
        }
        throw lastError ?? JobImportError.requestFailed("The request failed.")
    }

    private static func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(min(seconds, maxRetryDelay) * 1_000_000_000))
    }

    // MARK: - Shared parsing helpers

    static func stringID(_ value: Any?) -> String? {
        if let number = value as? NSNumber { return number.stringValue }
        if let string = value as? String { return string.trimmed.isEmpty ? nil : string.trimmed }
        return nil
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func isoDate(_ value: Any?) -> Date? {
        guard let text = (value as? String)?.trimmed, !text.isEmpty else { return nil }
        return isoFractional.date(from: text) ?? isoPlain.date(from: text)
    }

    static func epochDate(_ value: Any?) -> Date? {
        guard let number = (value as? NSNumber)?.doubleValue, number > 0 else { return nil }
        // Heuristic: values beyond ~year 2300 in seconds are milliseconds.
        return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
    }

    /// Strips HTML tags/entities from a description snippet.
    static func plainText(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        return HTMLJobExtractor.extract(html: html,
                                        url: URL(string: "https://example.com")!,
                                        wasRendered: false).visibleText
    }
}
