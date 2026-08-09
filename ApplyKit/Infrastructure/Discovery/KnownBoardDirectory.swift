//
//  KnownBoardDirectory.swift
//  ApplyKit
//
//  A bundled name → board index for the platforms a company name cannot imply.
//
//  `BoardSlugProber` can find a company on Greenhouse, Lever, Ashby or
//  SmartRecruiters because those are addressed by a bare slug it can try. The
//  enterprise platforms are addressed by a tenant *host* and often a site id
//  — `clio.wd3.myworkdayjobs.com/cliocareersite` — which no amount of guessing
//  from the word "Clio" will produce. Those tenants are catalogued instead.
//
//  Rows come from the MIT-licensed `kalil0321/ats-scrapers` dataset
//  (`ats-companies/*.csv`); see THIRD_PARTY_NOTICES.md. Names that mapped to
//  more than one company were dropped at generation time — an ambiguous answer
//  is worse than none, since the user would have no way to spot the mix-up.
//

import Foundation

enum KnownBoardDirectory {
    /// Keyed by `BuiltInCompanies.nameKey`, so lookup ignores case and
    /// punctuation the way the rest of the name matching does.
    private static let index: [String: TrackedBoard] = load()

    static func board(named name: String) -> TrackedBoard? {
        let key = BuiltInCompanies.nameKey(name)
        guard !key.isEmpty, var board = index[key] else { return nil }
        // The catalog's own spelling is replaced by the user's: it's their list.
        board.companyName = name.trimmed
        return board
    }

    static var count: Int { index.count }

    private static func load() -> [String: TrackedBoard] {
        guard let url = Bundle.main.url(forResource: "known-boards", withExtension: "tsv",
                                        subdirectory: "Resources")
                ?? Bundle.main.url(forResource: "known-boards", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        var index: [String: TrackedBoard] = [:]
        for line in text.split(separator: "\n") {
            guard !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { continue }
            let (name, kind, slug, host, site) = (fields[0], fields[1], fields[2], fields[3], fields[4])
            let key = BuiltInCompanies.nameKey(name)
            guard !key.isEmpty, !slug.isEmpty, JobBoardProviders.provider(id: kind) != nil else { continue }
            index[key] = TrackedBoard(kindRaw: kind, slug: slug,
                                      host: host.isEmpty ? nil : host,
                                      site: site.isEmpty ? nil : site,
                                      companyName: name)
        }
        return index
    }
}
