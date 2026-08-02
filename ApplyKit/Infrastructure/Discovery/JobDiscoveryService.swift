//
//  JobDiscoveryService.swift
//  ApplyKit
//
//  Polls tracked boards (AI-free) via `ATSBoardResolver`, keyword-filters and
//  dedupes the postings, and returns fresh `DiscoveredJob` inbox rows. The
//  expensive AI path runs only later, when the user imports a specific posting.
//

import Foundation

@MainActor
final class JobDiscoveryService {

    struct RefreshOutcome {
        var boards: [TrackedBoard]      // input boards with lastPolledAt updated
        var newJobs: [DiscoveredJob]    // brand-new, filtered, deduped postings
        var errors: [String]            // per-board failures, human-readable
        /// Every live posting key per board that polled successfully *and*
        /// returned a non-empty listing. Callers use this to spot postings that
        /// have since disappeared. Boards that errored or came back empty are
        /// deliberately absent: an outage or a partial crawl must never be read
        /// as "every job is gone".
        var liveKeysByBoard: [UUID: Set<String>] = [:]
    }

    /// Poll every board sequentially. `existingApplicationKeys` are the normalized
    /// URL keys of current applications; `existingDiscovered` are prior inbox rows
    /// (any state). A posting is emitted only when its dedup key is unseen in both.
    func refresh(boards: [TrackedBoard],
                 existingApplicationKeys: Set<String>,
                 existingDiscovered: [DiscoveredJob]) async -> RefreshOutcome {
        var seenKeys = existingApplicationKeys
        seenKeys.formUnion(existingDiscovered.map(\.dedupeKey))

        var updatedBoards = boards
        var newJobs: [DiscoveredJob] = []
        var errors: [String] = []
        var liveKeysByBoard: [UUID: Set<String>] = [:]

        for (index, board) in boards.enumerated() {
            do {
                let postings = try await JobBoardProviders.listJobs(for: board)
                // Record keys from the *unfiltered* listing: a posting the board
                // still lists but the board's keywords now reject is still open,
                // and must not be mistaken for one that was taken down.
                if !postings.isEmpty {
                    liveKeysByBoard[board.id] = Set(
                        postings.compactMap { JobURLNormalizer.duplicateKey(for: $0.url) })
                }
                newJobs.append(contentsOf: Self.filterAndDedupe(postings: postings, board: board, seenKeys: &seenKeys))
                updatedBoards[index].lastPolledAt = Date()
            } catch {
                errors.append("\(board.displayName): \(error.localizedDescription)")
            }
        }

        return RefreshOutcome(boards: updatedBoards, newJobs: newJobs,
                              errors: errors, liveKeysByBoard: liveKeysByBoard)
    }

    /// Postings still marked `new` on a successfully-polled board that no longer
    /// appear in its listing — i.e. filled or withdrawn. Returns the ids to close.
    static func closedJobIDs(in jobs: [DiscoveredJob],
                             liveKeysByBoard: [UUID: Set<String>]) -> Set<UUID> {
        var ids: Set<UUID> = []
        for job in jobs where job.state == .new {
            guard let liveKeys = liveKeysByBoard[job.boardID] else { continue }
            if !liveKeys.contains(job.dedupeKey) { ids.insert(job.id) }
        }
        return ids
    }

    // MARK: - Filtering & dedup (pure, network-free, unit-tested)

    /// Keyword-filter and dedupe `postings` for one board, appending each surviving
    /// key to `seenKeys` so later boards in the same refresh don't re-emit it.
    static func filterAndDedupe(postings: [DiscoveredPosting], board: TrackedBoard,
                                seenKeys: inout Set<String>) -> [DiscoveredJob] {
        var result: [DiscoveredJob] = []
        for posting in postings {
            guard passesFilters(posting, board: board) else { continue }
            guard let key = JobURLNormalizer.duplicateKey(for: posting.url) else { continue }
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            result.append(DiscoveredJob(
                boardID: board.id, externalID: posting.externalID, dedupeKey: key,
                title: posting.title, companyName: board.displayName, location: posting.location,
                url: posting.url, postedAt: posting.postedAt,
                jobDescription: posting.descriptionText,
                jobDescriptionFetchedAt: posting.descriptionText.isEmpty ? nil : Date()))
        }
        return result
    }

    /// Catch-all "talent pool" postings (Greenhouse evergreen reqs, general
    /// applications, etc.) that are real API entries but not actual openings.
    /// Filtered out of discovery regardless of a board's keyword settings.
    private static let catchAllTitleMarkers = [
        "don't see what you're looking for", "dont see what you're looking for",
        "didn't find", "didnt find", "can't find", "cant find",
        "general application", "general interest", "general submission",
        "open application", "spontaneous application", "speculative application",
        "future opportunit", "other opportunit", "interested in",
        "talent community", "talent network", "talent pool", "join our talent"
    ]

    static func isCatchAllPosting(title: String) -> Bool {
        let trimmed = title.trimmed
        // Talent-pool reqs are near-universally phrased as questions ("Interested in
        // an internship?", "Don't see what you're looking for?"); real job titles
        // essentially never end in a question mark.
        if trimmed.hasSuffix("?") { return true }
        let lowered = trimmed.lowercased()
        return catchAllTitleMarkers.contains { lowered.contains($0) }
    }

    static func passesFilters(_ posting: DiscoveredPosting, board: TrackedBoard) -> Bool {
        let title = posting.title.lowercased()
        let location = posting.location.lowercased()

        if isCatchAllPosting(title: posting.title) { return false }

        if board.excludeKeywords.contains(where: { title.contains($0.lowercased()) }) { return false }

        let includes = board.titleKeywords.filter { !$0.trimmed.isEmpty }
        if !includes.isEmpty, !includes.contains(where: { title.contains($0.lowercased()) }) { return false }

        let locations = board.locationKeywords.filter { !$0.trimmed.isEmpty }
        if !locations.isEmpty,
           !posting.locationVerified,
           !isAmbiguousLocation(posting.location),
           !locations.contains(where: { location.contains($0.lowercased()) }) { return false }

        return true
    }

    /// True when a posting's location can't be meaningfully matched — empty, or a
    /// count placeholder like Workday's "11 Locations" for multi-site roles. Such
    /// postings bypass the location filter (included rather than wrongly dropped),
    /// since the real cities aren't in the list response.
    static func isAmbiguousLocation(_ text: String) -> Bool {
        let trimmed = text.trimmed
        if trimmed.isEmpty { return true }
        return trimmed.range(of: #"^\d+\s+locations?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
