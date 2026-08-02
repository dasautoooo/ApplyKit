//
//  BuiltInCompanies.swift
//  ApplyKit
//
//  Catalog backing the "Browse Companies" panel. Big-tech employers run bespoke
//  career backends rather than a slug-addressable ATS, so they can't be added by
//  pasting a board URL the way Greenhouse/Lever boards can — this catalog gives
//  them a one-click entry point instead.
//

import Foundation

struct BuiltInCompany: Identifiable, Hashable {
    /// Matches the `JobBoardProvider.id` that fetches this company.
    var id: String
    var name: String
    /// Public careers page — shown in the panel and used for "Open".
    var careersURL: String
    /// Short note on coverage or known fragility, surfaced in the UI.
    var note: String

    func makeBoard() -> TrackedBoard {
        TrackedBoard(kindRaw: id, slug: id, companyName: name)
    }
}

enum BuiltInCompanies {
    static let all: [BuiltInCompany] = [
        BuiltInCompany(id: AmazonProvider.id, name: "Amazon",
                       careersURL: "https://www.amazon.jobs",
                       note: "Full catalog via the public search API."),
        BuiltInCompany(id: AppleProvider.id, name: "Apple",
                       careersURL: "https://jobs.apple.com",
                       note: "Full catalog; uses Apple's CSRF-protected search API."),
        BuiltInCompany(id: UberProvider.id, name: "Uber",
                       careersURL: "https://www.uber.com/us/en/careers/list/",
                       note: "Full catalog via the public careers API."),
        BuiltInCompany(id: TikTokProvider.id, name: "TikTok",
                       careersURL: "https://lifeattiktok.com/search",
                       note: "Full catalog, including job descriptions."),
        BuiltInCompany(id: ByteDanceProvider.id, name: "ByteDance",
                       careersURL: "https://jobs.bytedance.com/en/position",
                       note: "Full catalog, including job descriptions."),
        BuiltInCompany(id: GoogleProvider.id, name: "Google",
                       careersURL: "https://www.google.com/about/careers/applications/jobs/results",
                       note: "Scraped from the careers site — titles and links only."),
        BuiltInCompany(id: TeslaProvider.id, name: "Tesla",
                       careersURL: "https://www.tesla.com/careers/search/",
                       note: "Loaded in a browser view to pass bot protection; may be slow."),
        BuiltInCompany(id: MetaProvider.id, name: "Meta",
                       careersURL: "https://www.metacareers.com/jobs",
                       note: "Best-effort browser scrape; may return nothing if the site changes.")
    ]

    static func company(id: String) -> BuiltInCompany? {
        all.first { $0.id == id }
    }

    static func search(_ query: String) -> [BuiltInCompany] {
        let text = query.trimmed.lowercased()
        guard !text.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(text) || $0.id.contains(text) }
    }
}
