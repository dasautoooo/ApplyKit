//
//  BoardSlugProber.swift
//  ApplyKit
//
//  Finds a trackable board from a company *name* alone. No AI and no
//  inference: most multi-tenant ATS platforms address a company by a slug
//  that is simply its name lowercased, so this tries the handful of spellings
//  a name implies and asks the same public APIs the poller uses. A match is
//  only reported when one of them actually returns postings — so "ready to
//  track" means proven, not guessed.
//
//  Deliberately limited to slug-addressable platforms. Workday, Phenom, iCIMS,
//  Cornerstone, Avature, Eightfold and SuccessFactors are keyed by a tenant
//  host that no company name implies, so probing them would be guesswork.
//

import Foundation

enum BoardSlugProber {
    /// Platforms whose entire board is one unauthenticated GET away, keyed by
    /// a bare company slug. Order is the order results are preferred in.
    static let providers: [any JobBoardProvider.Type] = [
        GreenhouseProvider.self,
        LeverProvider.self,
        AshbyProvider.self,
        SmartRecruitersProvider.self
    ]

    /// Company-name noise that never appears in a board slug.
    private static let legalSuffixes: Set<String> = [
        "inc", "llc", "ltd", "limited", "corp", "corporation", "plc", "gmbh", "ab", "nv", "bv"
    ]

    /// Slug spellings worth trying for a company name — the name with spaces
    /// closed up, and the hyphenated form.
    ///
    /// Deliberately conservative: no truncation to a first word. "Magnet" is a
    /// different company from "Magnet Forensics", and a probe that hit its
    /// board would hand back the wrong employer with nothing to reveal the
    /// mistake.
    static func candidateSlugs(for name: String) -> [String] {
        // "theScore / PENN Entertainment" — take the first alternative only.
        let primary = name.split(separator: "/").first.map(String.init) ?? name
        let folded = primary
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let separated = String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
        var words = separated.split(separator: " ").map(String.init)
        while let last = words.last, legalSuffixes.contains(last) { words.removeLast() }
        guard !words.isEmpty else { return [] }

        var slugs: [String] = []
        for candidate in [words.joined(), words.joined(separator: "-")]
        where !slugs.contains(candidate) && ProviderSupport.isValidSlug(candidate)
            && candidate.count >= 2 && candidate.count <= 40 {
            slugs.append(candidate)
        }
        return slugs
    }

    /// The first provider/slug pair that returns postings, or nil when the name
    /// resolves to nothing. Every pair is tried concurrently; the winner is
    /// picked by `providers` order rather than by whichever answered first, so
    /// the same name always resolves the same way.
    static func probe(name: String) async -> TrackedBoard? {
        let slugs = candidateSlugs(for: name)
        guard !slugs.isEmpty else { return nil }

        var attempts: [(rank: Int, slug: String, providerID: String)] = []
        for slug in slugs {
            for provider in providers {
                attempts.append((attempts.count, slug, provider.id))
            }
        }

        let hits = await withTaskGroup(of: (Int, String, String)?.self) { group in
            for attempt in attempts {
                group.addTask {
                    guard let provider = JobBoardProviders.provider(id: attempt.providerID) else { return nil }
                    let candidate = TrackedBoard(kindRaw: attempt.providerID, slug: attempt.slug)
                    guard let postings = try? await provider.listJobs(candidate), !postings.isEmpty else { return nil }
                    return (attempt.rank, attempt.slug, attempt.providerID)
                }
            }
            var found: [(Int, String, String)] = []
            for await result in group { if let result { found.append(result) } }
            return found
        }

        guard let best = hits.min(by: { $0.0 < $1.0 }) else { return nil }
        return TrackedBoard(kindRaw: best.2, slug: best.1, companyName: name)
    }
}
