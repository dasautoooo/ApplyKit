import Foundation

/// One dated entry in an application's timeline.
///
/// Status changes, creation, and archive/restore are recorded automatically; entries with
/// kind `.note` are written by hand. Every entry is editable, so an auto-recorded date can
/// be corrected after the fact.
struct ApplicationEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var kindRaw: String
    /// Both empty unless `kind == .statusChanged`. `fromStatusRaw` is also empty for an
    /// inferred status change, where the previous status is unknowable.
    var fromStatusRaw: String
    var toStatusRaw: String
    /// Manual entries only. Automatic entries derive their title from the kind and status.
    var title: String
    var note: String
    /// Reconstructed from surrounding dates rather than observed as it happened.
    /// Surfaced in the UI as "approximate" so an inferred date is never mistaken for a real one.
    var isInferred: Bool

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: ApplicationEventKind,
        fromStatusRaw: String = "",
        toStatusRaw: String = "",
        title: String = "",
        note: String = "",
        isInferred: Bool = false
    ) {
        self.id = id
        self.date = date
        self.kindRaw = kind.rawValue
        self.fromStatusRaw = fromStatusRaw
        self.toStatusRaw = toStatusRaw
        self.title = title
        self.note = note
        self.isInferred = isInferred
    }
}

enum ApplicationEventKind: String, StoredStringEnum {
    case created = "Created"
    case statusChanged = "Status Changed"
    case archived = "Archived"
    case restored = "Restored"
    case note = "Note"
}

extension ApplicationEvent {
    var kind: ApplicationEventKind {
        get { ApplicationEventKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var isStatusChange: Bool { kind == .statusChanged }

    /// The headline shown in the timeline. Automatic entries describe themselves; a manual
    /// entry falls back to "Note" so an untitled one is never blank.
    var displayTitle: String {
        switch kind {
        case .created: "Saved to ApplyKit"
        case .statusChanged: toStatusRaw.isEmpty ? "Status changed" : toStatusRaw
        case .archived: "Archived"
        case .restored: "Restored"
        case .note: title.trimmed.isEmpty ? "Note" : title.trimmed
        }
    }

    /// Secondary line describing the transition, when the previous status is known.
    var transitionDetail: String? {
        guard isStatusChange, !fromStatusRaw.isEmpty else { return nil }
        return "from \(fromStatusRaw)"
    }

    var icon: String {
        switch kind {
        case .created: "plus.circle"
        case .statusChanged: "arrow.triangle.branch"
        case .archived: "archivebox"
        case .restored: "arrow.uturn.backward"
        case .note: "text.bubble"
        }
    }
}

enum ApplicationTimeline {
    /// Rebuilds a plausible history for an application saved before timelines existed, using
    /// the only evidence available — the dates already stored on the record. Every entry is
    /// flagged `isInferred` because none of them were actually observed.
    ///
    /// Pure by design: the loader calls this when no `timeline.yml` sidecar is present, and it
    /// must produce the same result on every launch so an untouched application doesn't drift.
    static func backfilled(for application: JobApplication) -> [ApplicationEvent] {
        var events: [ApplicationEvent] = []

        events.append(
            ApplicationEvent(
                date: application.dateSaved,
                kind: .created,
                isInferred: true
            )
        )

        if let applied = application.dateApplied {
            events.append(
                ApplicationEvent(
                    date: applied,
                    kind: .statusChanged,
                    toStatusRaw: ApplicationStatus.applied.rawValue,
                    isInferred: true
                )
            )
        }

        // The current status is worth an entry unless it's the default, or unless the
        // dateApplied entry above already represents it.
        let isDefaultStatus = application.statusRaw == ApplicationStatus.saved.rawValue
        let coveredByAppliedDate = application.statusRaw == ApplicationStatus.applied.rawValue
            && application.dateApplied != nil
        if !isDefaultStatus, !coveredByAppliedDate {
            events.append(
                ApplicationEvent(
                    date: application.updatedAt,
                    kind: .statusChanged,
                    toStatusRaw: application.statusRaw,
                    isInferred: true
                )
            )
        }

        if let archived = application.archivedAt {
            events.append(ApplicationEvent(date: archived, kind: .archived, isInferred: true))
        }

        // Built oldest-first above; reversed before sorting so that entries sharing a
        // timestamp — a same-day save and status change, say — still read in causal order.
        return sortedNewestFirst(events.reversed())
    }

    /// Newest first, stable: entries sharing a timestamp keep the order they arrived in.
    /// Timestamps persist at millisecond resolution, so ties are common enough that a
    /// reordering sort here would scramble a stored timeline on every load.
    static func sortedNewestFirst(_ events: [ApplicationEvent]) -> [ApplicationEvent] {
        events.enumerated()
            .sorted { lhs, rhs in
                lhs.element.date == rhs.element.date
                    ? lhs.offset < rhs.offset
                    : lhs.element.date > rhs.element.date
            }
            .map(\.element)
    }
}
