import Foundation

/// One dated entry in an application's timeline.
///
/// Status changes, creation, and archive/restore are recorded automatically; entries with
/// kind `.note` or `.interview` are written by hand. Every entry is editable, so an auto-recorded date can
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
    /// On an interview it's an optional label for detail the type doesn't capture.
    var title: String
    var note: String
    /// Reconstructed from surrounding dates rather than observed as it happened.
    /// Surfaced in the UI as "approximate" so an inferred date is never mistaken for a real one.
    var isInferred: Bool
    /// Both empty unless `kind == .interview`. Kept raw so a value this build doesn't know
    /// survives a load/save round trip.
    var interviewTypeRaw: String
    var interviewResultRaw: String
    /// Logistics, prep, and debrief for an interview step. Its free-form debrief notes are
    /// `note`, so they show under the entry on the timeline like any other entry's details.
    var interview: InterviewDetails

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: ApplicationEventKind,
        fromStatusRaw: String = "",
        toStatusRaw: String = "",
        title: String = "",
        note: String = "",
        isInferred: Bool = false,
        interviewTypeRaw: String = "",
        interviewResultRaw: String = "",
        interview: InterviewDetails = InterviewDetails()
    ) {
        self.id = id
        self.date = date
        self.kindRaw = kind.rawValue
        self.fromStatusRaw = fromStatusRaw
        self.toStatusRaw = toStatusRaw
        self.title = title
        self.note = note
        self.isInferred = isInferred
        self.interviewTypeRaw = interviewTypeRaw
        self.interviewResultRaw = interviewResultRaw
        self.interview = interview
    }
}

/// Everything about an interview step beyond its type, result, and date.
struct InterviewDetails: Codable, Hashable {
    var durationMinutes: Int?
    var formatRaw: String = ""
    /// Meeting link or address.
    var location: String = ""
    var interviewers: String = ""
    var prepChecklist: [InterviewChecklistItem] = []
    var prepNotes: String = ""
    var questionsAsked: String = ""
    /// How it went, 1–5, by the candidate's own reckoning.
    var selfRating: Int?

    var isEmpty: Bool { self == InterviewDetails() }

    var format: InterviewFormat? { InterviewFormat(rawValue: formatRaw) }

    /// The link, when `location` is one — worth a Join button.
    var meetingURL: URL? {
        let trimmed = location.trimmed
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return nil }
        return URL(string: trimmed)
    }

    var prepProgress: (done: Int, total: Int) {
        (prepChecklist.filter(\.isDone).count, prepChecklist.count)
    }
}

struct InterviewChecklistItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var isDone = false
}

enum ApplicationEventKind: String, StoredStringEnum {
    case created = "Created"
    case statusChanged = "Status Changed"
    case archived = "Archived"
    case restored = "Restored"
    case note = "Note"
    case interview = "Interview"
}

extension ApplicationEvent {
    var kind: ApplicationEventKind {
        get { ApplicationEventKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var isStatusChange: Bool { kind == .statusChanged }

    var isInterview: Bool { kind == .interview }

    var isRecruiterScreenStep: Bool { isInterview && interviewType == .recruiterScreen }

    /// A freshly added step, still being arranged: a step usually gets logged well before a
    /// time is agreed. Dated now only to place it; that is when it was added, not when they
    /// reached out, so nothing reads it as an event date until a time is set. A screen
    /// defaults to a 30-minute call; a round to an hour, in the format of `formatLike` when
    /// given (rounds at one company tend to share one).
    static func newInterviewStep(_ type: InterviewType, formatLike previous: ApplicationEvent? = nil,
                                 now: Date = Date()) -> ApplicationEvent {
        let isScreen = type == .recruiterScreen
        let format = isScreen ? InterviewFormat.phone : (previous?.interview.format ?? .video)
        return ApplicationEvent(
            date: now,
            kind: .interview,
            interviewTypeRaw: type.rawValue,
            interviewResultRaw: InterviewResult.scheduling.rawValue,
            interview: InterviewDetails(durationMinutes: isScreen ? 30 : 60, formatRaw: format.rawValue)
        )
    }

    /// Whether a time has been set. A step still being arranged has only the date it was logged.
    var hasScheduledTime: Bool { interviewResult != .scheduling }

    /// Sets the agreed time, moving a step that was being arranged to Scheduled.
    mutating func schedule(at date: Date) {
        self.date = date
        if interviewResult == .scheduling { interviewResult = .scheduled }
    }

    /// A starting point for the time picker: tomorrow at 10:00.
    static func suggestedInterviewTime(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    var interviewType: InterviewType {
        get { InterviewType(rawValue: interviewTypeRaw) ?? .other }
        set { interviewTypeRaw = newValue.rawValue }
    }

    var interviewResult: InterviewResult {
        get { InterviewResult(rawValue: interviewResultRaw) ?? .scheduled }
        set { interviewResultRaw = newValue.rawValue }
    }

    /// The headline shown in the timeline. Automatic entries describe themselves; a manual
    /// entry falls back to "Note" so an untitled one is never blank.
    var displayTitle: String {
        switch kind {
        case .created: "Saved to ApplyKit"
        case .statusChanged: toStatusRaw.isEmpty ? "Status changed" : toStatusRaw
        case .archived: "Archived"
        case .restored: "Restored"
        case .note: title.trimmed.isEmpty ? "Note" : title.trimmed
        case .interview: title.trimmed.isEmpty ? interviewTypeLabel : "\(interviewTypeLabel): \(title.trimmed)"
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
        case .interview: "person.2"
        }
    }

    /// The stored type verbatim when this build doesn't recognize it, rather than "Other".
    private var interviewTypeLabel: String {
        interviewTypeRaw.isEmpty ? InterviewType.other.rawValue : interviewTypeRaw
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
