import Foundation

struct JobApplication: Identifiable, Codable, Hashable {
    var id: UUID
    var companyName: String
    var jobTitle: String
    var jobURL: String
    var sourceMasterResumeID: UUID?
    var location: String
    var workModeRaw: String
    var employmentTypeRaw: String
    var sourceRaw: String
    var statusRaw: String
    var priorityRaw: String
    var dateSaved: Date
    var dateApplied: Date?
    var deadline: Date?
    var referralContact: String
    var recruiterContact: String
    var nextAction: String
    var notes: String
    var jobDescription: String
    /// Legacy freeform "JD Analysis" markdown. No longer generated — the Resume
    /// Tailor's brief replaced it — but kept so older applications can still show
    /// (and discard) what they had.
    var jdAnalysisText: String
    var curatedSuggestionsData: String
    var tailoringPlanData: String
    /// Encoded `TailoringBrief` (Stage 1 of the Resume Tailor).
    var tailoringBriefData: String
    /// Encoded `TailoringReview` — the check against the rendered PDF.
    var tailoringReviewData: String
    /// Fit score the brief gave, mirrored out of `tailoringBriefData` so the
    /// applications list can show it without decoding the JSON per row.
    var fitScore: Double?
    var coverLetterNeeded: Bool
    var selectedExperienceIDsText: String
    var selectedProjectIDsText: String
    var selectedVariantIDsText: String
    var employmentRoleDescriptionsText: String
    var hiddenRoleDescriptionIDsText: String
    var experienceOrderText: String
    var sectionOrderText: String
    var skillsBlockText: String
    var summaryText: String
    /// Body font size for the rendered résumé, in points. The document class
    /// only accepts 10, 11 or 12 — see `ResumePageLayout`.
    var resumeFontSizePt: Int
    /// Page margin in inches, applied on all four sides.
    var resumeMarginInches: Double
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    /// Dated history of what happened to this application, newest first. Mutate it only
    /// through `setStatus`/`recordEvent`/`updateEvent`/`removeEvent` so ordering holds.
    var timeline: [ApplicationEvent]

    init(
        companyName: String = "",
        jobTitle: String = "",
        status: ApplicationStatus = .saved,
        priority: ApplicationPriority = .low
    ) {
        self.id = UUID()
        self.companyName = companyName
        self.jobTitle = jobTitle
        self.jobURL = ""
        self.sourceMasterResumeID = nil
        self.location = ""
        self.workModeRaw = WorkMode.unknown.rawValue
        self.employmentTypeRaw = EmploymentType.fullTime.rawValue
        self.sourceRaw = ApplicationSource.linkedin.rawValue
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.dateSaved = Date()
        self.referralContact = ""
        self.recruiterContact = ""
        self.nextAction = ""
        self.notes = ""
        self.jobDescription = ""
        self.jdAnalysisText = ""
        self.curatedSuggestionsData = ""
        self.tailoringPlanData = ""
        self.tailoringBriefData = ""
        self.tailoringReviewData = ""
        self.tailoringReviewData = ""
        self.fitScore = nil
        self.coverLetterNeeded = false
        self.selectedExperienceIDsText = ""
        self.selectedProjectIDsText = ""
        self.selectedVariantIDsText = ""
        self.employmentRoleDescriptionsText = ""
        self.hiddenRoleDescriptionIDsText = ""
        self.experienceOrderText = ""
        self.sectionOrderText = ""
        self.skillsBlockText = ""
        self.summaryText = ""
        self.resumeFontSizePt = ResumePageLayout.defaultFontSizePt
        self.resumeMarginInches = ResumePageLayout.defaultMarginInches
        self.archivedAt = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        // Seeded here rather than at each creation site so no path can produce an
        // application without an origin entry. The workspace loader overwrites this
        // wholesale with the stored (or backfilled) timeline.
        self.timeline = [ApplicationEvent(date: self.dateSaved, kind: .created)]
    }
}

extension JobApplication {
    /// The stored Stage 1 brief, or nil when the tailor hasn't run here yet.
    var tailoringBrief: TailoringBrief? { TailoringBrief.decode(tailoringBriefData) }

    /// The last review of the rendered PDF, or nil when none has run.
    var tailoringReview: TailoringReview? { TailoringReview.decode(tailoringReviewData) }

    /// Fields written only by a background run. The editor holds a snapshot that
    /// can predate the run and never edits these itself, so the stored copy wins
    /// whenever that snapshot is saved — otherwise applying one suggested change
    /// would erase the review that suggested it, unapplied siblings and all.
    mutating func preserveRunOwnedState(from stored: JobApplication) {
        tailoringReviewData = stored.tailoringReviewData
    }

    /// Stores a brief and mirrors the score the applications list reads directly.
    mutating func setTailoringBrief(_ brief: TailoringBrief?) {
        guard let brief else {
            tailoringBriefData = ""
            fitScore = nil
            return
        }
        tailoringBriefData = brief.encoded()
        fitScore = brief.fitScore
    }

    var displayTitle: String {
        let title = jobTitle.trimmed
        let company = companyName.trimmed
        if company.isEmpty && title.isEmpty { return "Untitled Application" }
        if company.isEmpty { return title }
        if title.isEmpty { return company }
        return "\(company) - \(title)"
    }

    var isArchived: Bool { archivedAt != nil }

    // MARK: - Timeline

    /// Date of the most recent timeline entry. Preferred over `updatedAt` when showing how
    /// long an application has been quiet, since `updatedAt` is re-stamped by every autosave.
    var lastTimelineChange: Date? { timeline.first?.date }

    /// Change signal for the editor's debounced autosave. Without this in the fingerprint,
    /// manual entries and note edits would never reach disk.
    var timelineFingerprint: String {
        timeline.map { event in
            [
                event.id.uuidString,
                String(event.date.timeIntervalSinceReferenceDate),
                event.kindRaw,
                event.fromStatusRaw,
                event.toStatusRaw,
                event.title,
                event.note,
                String(event.isInferred)
            ].joined(separator: "\u{1E}")
        }
        .joined(separator: "\u{1D}")
    }

    /// Sets the status and records the transition. A no-op when the status is unchanged, so
    /// re-picking the current value doesn't litter the timeline.
    ///
    /// Moving to Applied also stamps `dateApplied`, but only when it is blank — a date the
    /// user set by hand is never overwritten.
    mutating func setStatus(rawValue: String) {
        guard rawValue != statusRaw else { return }
        let previous = statusRaw
        statusRaw = rawValue
        recordEvent(
            ApplicationEvent(kind: .statusChanged, fromStatusRaw: previous, toStatusRaw: rawValue)
        )
        if rawValue == ApplicationStatus.applied.rawValue, dateApplied == nil {
            dateApplied = Date()
        }
    }

    /// Inserts an entry at its date-ordered position. Equal dates put the new entry first,
    /// keeping the list newest-first without a full re-sort.
    mutating func recordEvent(_ event: ApplicationEvent) {
        let index = timeline.firstIndex { $0.date <= event.date } ?? timeline.endIndex
        timeline.insert(event, at: index)
    }

    /// Replaces an entry. Re-inserts it only when the date moved — editing a note in place
    /// must not reshuffle the list out from under an open editor.
    mutating func updateEvent(_ event: ApplicationEvent) {
        guard let index = timeline.firstIndex(where: { $0.id == event.id }) else { return }
        if timeline[index].date == event.date {
            timeline[index] = event
        } else {
            timeline.remove(at: index)
            recordEvent(event)
        }
    }

    mutating func removeEvent(id: UUID) {
        timeline.removeAll { $0.id == id }
    }

    /// Starts a fresh history for a duplicated role, discarding the original's.
    mutating func resetTimeline() {
        timeline = [ApplicationEvent(date: dateSaved, kind: .created)]
    }
}

extension JobApplication: ResumeContentModel {}
