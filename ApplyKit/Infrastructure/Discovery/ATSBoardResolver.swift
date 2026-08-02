//
//  ATSBoardResolver.swift
//  ApplyKit
//
//  Thin compatibility shim over `JobBoardProviders`. The per-platform logic now
//  lives in Providers/ — see JobBoardProvider.swift for the registry.
//

import Foundation

enum ATSBoardResolver {
    /// Derive a `TrackedBoard` from any board-root or job-detail URL, trying
    /// every registered provider.
    static func board(for url: URL) -> TrackedBoard? {
        JobBoardProviders.detect(url: url)
    }

    static func listJobs(board: TrackedBoard) async throws -> [DiscoveredPosting] {
        try await JobBoardProviders.listJobs(for: board)
    }
}
