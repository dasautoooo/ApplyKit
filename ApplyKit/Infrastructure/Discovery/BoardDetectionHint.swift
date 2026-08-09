//
//  BoardDetectionHint.swift
//  ApplyKit
//
//  When `JobBoardProviders.detect` returns nothing, some URLs are near misses
//  with a specific fix — a Workday tenant root that names no career site, or a
//  `.jobs` mirror that has no API behind it. Saying so beats repeating the list
//  of supported platforms at someone who pasted a supported platform.
//

import Foundation

enum BoardDetectionHint {
    /// A specific reason this URL wasn't recognized, when there is one.
    static func hint(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }

        // A Workday tenant is pollable only per career site, and the site id
        // lives in the path. The tenant root can't supply it — it answers 406
        // with no redirect, so there's nothing to follow either.
        if host.hasSuffix(".myworkdayjobs.com") {
            return segments.isEmpty
                ? "That's a Workday tenant, but the URL doesn't say which career site to watch. Open the job list or any job on that site and paste that URL instead."
                : nil
        }

        // `.jobs` domains are usually SEO mirrors of a board hosted elsewhere,
        // and typically sit behind bot protection with no API to poll.
        if host.hasSuffix(".jobs") {
            return "A \".jobs\" address is usually a mirror rather than the real board. Open a posting there, follow it to the company's actual careers site, and paste that URL."
        }

        return nil
    }
}
