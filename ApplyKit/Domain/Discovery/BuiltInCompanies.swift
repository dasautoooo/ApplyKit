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
    /// Unique catalog key. For single-company providers this is the
    /// `JobBoardProvider.id` itself (there's only one tenant); for a
    /// multi-tenant enterprise ATS (Eightfold, Avature, SuccessFactors) it's
    /// `"{providerID}:{slug}"`, since several companies here can share the
    /// same provider.
    var id: String
    /// The `JobBoardProvider.id` that fetches this company — `makeBoard()`'s
    /// `kindRaw`. Equal to `id` for single-company providers.
    var providerID: String
    /// Tenant slug passed to the provider. Equal to `providerID` for
    /// single-company providers, which have no per-company identifier.
    var slug: String
    /// Tenant host override, for providers keyed by a custom domain rather
    /// than a `{slug}.provider.com` subdomain (e.g. Microsoft on Eightfold).
    var host: String?
    /// Tenant site/locale-path override — `AvatureProvider` reads this as the
    /// custom-domain tenant's path prefix (e.g. IBM's `/en_US`).
    var site: String?
    var name: String
    /// Public careers page — shown in the panel and used for "Open".
    var careersURL: String
    /// Short note on coverage or known fragility, surfaced in the UI.
    var note: String

    init(id: String? = nil, providerID: String, slug: String? = nil, host: String? = nil,
         site: String? = nil, name: String, careersURL: String, note: String) {
        self.providerID = providerID
        self.slug = slug ?? providerID
        self.host = host
        self.site = site
        self.id = id ?? "\(providerID):\(self.slug)"
        self.name = name
        self.careersURL = careersURL
        self.note = note
    }

    func makeBoard() -> TrackedBoard {
        TrackedBoard(kindRaw: providerID, slug: slug, host: host, site: site, companyName: name)
    }

    /// Matches `TrackedBoard.trackingKey`, so the catalog can tell which of its
    /// entries are already being tracked.
    var trackingKey: String { TrackedBoard.trackingKey(kindRaw: providerID, slug: slug) }
}

enum BuiltInCompanies {
    static let all: [BuiltInCompany] = [
        BuiltInCompany(providerID: AmazonProvider.id, name: "Amazon",
                       careersURL: "https://www.amazon.jobs",
                       note: "Full catalog via the public search API."),
        BuiltInCompany(providerID: AppleProvider.id, name: "Apple",
                       careersURL: "https://jobs.apple.com",
                       note: "Full catalog; uses Apple's CSRF-protected search API."),
        BuiltInCompany(providerID: UberProvider.id, name: "Uber",
                       careersURL: "https://www.uber.com/us/en/careers/list/",
                       note: "Full catalog via the public careers API."),
        BuiltInCompany(providerID: TikTokProvider.id, name: "TikTok",
                       careersURL: "https://lifeattiktok.com/search",
                       note: "Full catalog, including job descriptions."),
        BuiltInCompany(providerID: ByteDanceProvider.id, name: "ByteDance",
                       careersURL: "https://jobs.bytedance.com/en/position",
                       note: "Full catalog, including job descriptions."),
        BuiltInCompany(providerID: GoogleProvider.id, name: "Google",
                       careersURL: "https://www.google.com/about/careers/applications/jobs/results",
                       note: "Scraped from the careers site — titles and links only."),
        BuiltInCompany(providerID: TeslaProvider.id, name: "Tesla",
                       careersURL: "https://www.tesla.com/careers/search/",
                       note: "Loaded in a browser view to pass bot protection; may be slow."),
        BuiltInCompany(providerID: MetaProvider.id, name: "Meta",
                       careersURL: "https://www.metacareers.com/jobs",
                       note: "Best-effort browser scrape; may return nothing if the site changes."),
        // Enterprise ATS tenants — several companies can share one provider,
        // so each needs its own slug/host rather than reusing the provider id.
        BuiltInCompany(providerID: EightfoldProvider.id, slug: "microsoft", name: "Microsoft",
                       careersURL: "https://microsoft.eightfold.ai/careers",
                       note: "Full catalog via the public Eightfold AI search API."),
        BuiltInCompany(providerID: SuccessFactorsProvider.id, slug: "jobs.sap.com", host: "jobs.sap.com",
                       name: "SAP", careersURL: "https://jobs.sap.com",
                       note: "Full catalog via SAP's public SuccessFactors RSS feed."),
        BuiltInCompany(providerID: AvatureProvider.id, slug: "ibm", host: "careers.ibm.com", site: "/en_US",
                       name: "IBM", careersURL: "https://careers.ibm.com/en_US",
                       note: "Loaded in a browser view to pass Avature's client check; may be slow."),
        BuiltInCompany(providerID: PhenomProvider.id, slug: "careers.cisco.com", host: "careers.cisco.com",
                       site: "global/en", name: "Cisco", careersURL: "https://careers.cisco.com/global/en/search-results",
                       note: "Full catalog via Cisco's public Phenom search API.")
    ]

    static func company(id: String) -> BuiltInCompany? {
        all.first { $0.id == id }
    }

    /// Lookup by display name, ignoring case and punctuation, so a watchlist
    /// line ("1Password", "Motorola Solutions") finds its catalog entry.
    static func company(named name: String) -> BuiltInCompany? {
        let key = nameKey(name)
        guard !key.isEmpty else { return nil }
        return all.first { nameKey($0.name) == key }
    }

    /// The form two spellings of the same company name have in common.
    static func nameKey(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    static func search(_ query: String) -> [BuiltInCompany] {
        let text = query.trimmed.lowercased()
        guard !text.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(text) || $0.id.contains(text) }
    }
}
