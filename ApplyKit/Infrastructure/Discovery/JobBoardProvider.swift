//
//  JobBoardProvider.swift
//  ApplyKit
//
//  Discovery is provider-pluggable: each ATS or company career site is a small
//  self-contained type that knows how to recognize its URLs and list its open
//  roles. The registry is the only lookup mechanism — `TrackedBoard.kindRaw`
//  stores a provider `id`, so persisted boards survive provider changes.
//
//  Endpoint patterns and the Workday pagination algorithm are adapted from the
//  MIT-licensed `kalil0321/ats-scrapers` project. See THIRD_PARTY_NOTICES.md.
//

import Foundation

protocol JobBoardProvider {
    /// Stable identifier persisted in `TrackedBoard.kindRaw`. Never rename.
    static var id: String { get }
    static var displayName: String { get }
    /// True for fixed single-employer providers (Amazon, Apple…) as opposed to
    /// multi-tenant ATS platforms addressed by company slug.
    static var isSingleCompany: Bool { get }

    /// Recognize a pasted board/job URL, or return nil if it isn't ours.
    static func board(for url: URL) -> TrackedBoard?
    /// Every currently open posting on the board.
    static func listJobs(_ board: TrackedBoard) async throws -> [DiscoveredPosting]
}

extension JobBoardProvider {
    static var isSingleCompany: Bool { false }
}

enum JobBoardProviders {
    /// Registration order matters for URL detection: single-company providers are
    /// checked first so a bespoke careers host wins over a generic ATS pattern.
    static let all: [any JobBoardProvider.Type] = [
        // Big tech (fixed employers)
        AmazonProvider.self,
        AppleProvider.self,
        UberProvider.self,
        TikTokProvider.self,
        ByteDanceProvider.self,
        GoogleProvider.self,
        TeslaProvider.self,
        MetaProvider.self,
        // Multi-tenant ATS platforms
        GreenhouseProvider.self,
        LeverProvider.self,
        AshbyProvider.self,
        WorkdayProvider.self,
        SmartRecruitersProvider.self,
        WorkableProvider.self,
        RecruiteeProvider.self,
        PersonioProvider.self,
        BambooHRProvider.self,
        BreezyProvider.self,
        JazzHRProvider.self,
        TeamtailorProvider.self
    ]

    static func provider(id: String) -> (any JobBoardProvider.Type)? {
        all.first { $0.id == id }
    }

    static func detect(url: URL) -> TrackedBoard? {
        for provider in all {
            if let board = provider.board(for: url) { return board }
        }
        return nil
    }

    static func displayName(for id: String) -> String {
        provider(id: id)?.displayName ?? id.capitalized
    }

    static func listJobs(for board: TrackedBoard) async throws -> [DiscoveredPosting] {
        guard let provider = provider(id: board.kindRaw) else {
            throw JobImportError.unsupportedURL
        }
        return try await provider.listJobs(board)
    }
}

// MARK: - Shared helpers for providers

enum ProviderSupport {
    static func isValidSlug(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return !value.isEmpty && value.unicodeScalars.allSatisfy(allowed.contains)
    }

    static func humanize(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func url(_ string: String) throws -> URL {
        guard let url = URL(string: string) else { throw JobImportError.unsupportedURL }
        return url
    }

    /// Subdomain-style ATS detection: `{slug}.host.tld` → slug.
    static func subdomainSlug(_ url: URL, suffix: String) -> String? {
        guard let host = url.host?.lowercased(), host.hasSuffix(suffix) else { return nil }
        let slug = String(host.dropLast(suffix.count))
        return isValidSlug(slug) ? slug : nil
    }
}
