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
                String(event.isInferred),
                event.interviewTypeRaw,
                event.interviewResultRaw,
                // In-process change signal only, so a per-launch hash seed doesn't matter.
                String(event.interview.hashValue)
            ].joined(separator: "\u{1E}")
        }
        .joined(separator: "\u{1D}")
    }

    /// Sets the status and records the transition. A no-op when the status is unchanged, so
    /// re-picking the current value doesn't litter the timeline.
    ///
    /// Moves into Recruiter Screen or Interviewing aren't recorded: an interview step always
    /// backs those statuses and is the record of them, so a second entry would only repeat
    /// it — and outlive it when the step is deleted.
    ///
    /// Moving to Applied also stamps `dateApplied`, but only when it is blank — a date the
    /// user set by hand is never overwritten.
    mutating func setStatus(rawValue: String, at date: Date = Date()) {
        guard rawValue != statusRaw else { return }
        let previous = statusRaw
        statusRaw = rawValue
        if ApplicationStatus.stored(rawValue)?.isInterviewPhase != true {
            recordEvent(
                ApplicationEvent(date: date, kind: .statusChanged, fromStatusRaw: previous, toStatusRaw: rawValue)
            )
        }
        if rawValue == ApplicationStatus.applied.rawValue, dateApplied == nil {
            dateApplied = date
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
        let previous = timeline[index]
        if previous.date == event.date {
            timeline[index] = event
        } else {
            timeline.remove(at: index)
            recordEvent(event)
        }
        // Turning a round into the recruiter screen (or back) can change the phase.
        if previous.isRecruiterScreenStep != event.isRecruiterScreenStep {
            syncStatusWithSteps(allowingDowngrade: true)
        }
    }

    /// The timeline as shown. Once interview steps are logged they tell the interview phase
    /// themselves, so the status changes into Recruiter Screen or Interviewing that go with
    /// them are left out rather than read as a second "Recruiter Screen" row. They stay in the
    /// data — Insights reads them — and without steps (older applications) they still show.
    var displayedTimeline: [ApplicationEvent] {
        guard timeline.contains(where: \.isInterview) else { return timeline }
        return timeline.filter { event in
            !(event.isStatusChange && ApplicationStatus.stored(event.toStatusRaw)?.isInterviewPhase == true)
        }
    }

    /// Every interview step, recruiter screens included, in the order they happen: those with
    /// a time by that time, then those still being arranged. The latter are dated when they
    /// were logged, which would otherwise put a round still being booked ahead of one that's
    /// already on the calendar.
    var interviewSteps: [ApplicationEvent] {
        let oldestFirst = timeline.filter(\.isInterview).reversed()
        return oldestFirst.filter(\.hasScheduledTime) + oldestFirst.filter { !$0.hasScheduledTime }
    }

    /// Interview steps past the recruiter screen, oldest first. A round's number is its
    /// position here, so it follows the dates rather than the order the rounds were entered.
    var interviewRounds: [ApplicationEvent] {
        interviewSteps.filter { !$0.isRecruiterScreenStep }
    }

    /// nil for a recruiter screen, which isn't a numbered round.
    func roundNumber(of eventID: UUID) -> Int? {
        interviewRounds.firstIndex { $0.id == eventID }.map { $0 + 1 }
    }

    /// The number of the latest round logged, scheduled ones included, or nil before the first.
    var currentRound: Int? {
        let count = interviewRounds.count
        return count == 0 ? nil : count
    }

    /// "Recruiter Screen" or "Round 2 · System Design", plus the step's label if it has one.
    func stepTitle(for event: ApplicationEvent) -> String {
        guard let number = roundNumber(of: event.id) else { return event.displayTitle }
        return "Round \(number) · \(event.displayTitle)"
    }

    /// The status the logged steps call for: Interviewing once there's a round, Recruiter
    /// Screen with only a screen, nil with no steps at all.
    var interviewPhaseStatus: ApplicationStatus? {
        let steps = timeline.filter(\.isInterview)
        if steps.contains(where: { !$0.isRecruiterScreenStep }) { return .interviewing }
        return steps.isEmpty ? nil : .recruiterScreen
    }

    /// Logs an interview step, moving an earlier status forward to the phase it implies.
    /// Adding never moves the status back: logging a forgotten screen while Interviewing
    /// leaves it Interviewing.
    mutating func recordInterviewStep(_ event: ApplicationEvent) {
        var withStep = self
        withStep.recordEvent(event)
        // The status change is dated with the step (or now, for one scheduled ahead) and
        // recorded first: equal timestamps put the later-recorded entry on top, so the step
        // reads as coming after the status change.
        if let target = withStep.interviewPhaseStatus {
            applyInterviewPhase(target, allowingDowngrade: false, at: min(event.date, Date()))
        }
        recordEvent(event)
    }

    mutating func removeEvent(id: UUID) {
        let wasStep = timeline.contains { $0.id == id && $0.isInterview }
        timeline.removeAll { $0.id == id }
        if wasStep { syncStatusWithSteps(allowingDowngrade: true) }
    }

    /// Brings an interview-phase status in line with the steps. With no steps left the status
    /// stays as it is — it may have been picked by hand — and a closed-out status (Offer,
    /// Rejected, ...) is never touched.
    mutating func syncStatusWithSteps(allowingDowngrade: Bool, at date: Date = Date()) {
        guard let target = interviewPhaseStatus else {
            if allowingDowngrade { retractInterviewPhase() }
            return
        }
        applyInterviewPhase(target, allowingDowngrade: allowingDowngrade, at: date)
    }

    /// With the last step deleted, an interview-phase status has nothing behind it, so it goes
    /// back to where it was before. Not when the timeline records the phase itself — an older
    /// application that moved to Interviewing before steps existed stays Interviewing.
    private mutating func retractInterviewPhase() {
        guard ApplicationStatus.stored(statusRaw)?.isInterviewPhase == true else { return }
        let phaseIsRecorded = timeline.contains {
            $0.isStatusChange && ApplicationStatus.stored($0.toStatusRaw)?.isInterviewPhase == true
        }
        guard !phaseIsRecorded else { return }
        // Newest first, so this is the last status before the interview phase began. Set
        // directly, unrecorded: this undoes the phase rather than being a move of its own.
        statusRaw = timeline.first { $0.isStatusChange }?.toStatusRaw
            ?? (dateApplied != nil ? ApplicationStatus.applied : .saved).rawValue
    }

    private mutating func applyInterviewPhase(_ target: ApplicationStatus, allowingDowngrade: Bool, at date: Date) {
        guard let current = ApplicationStatus(rawValue: statusRaw), !current.isClosed, current != target else { return }
        if current.precedes(target) || (allowingDowngrade && current.isInterviewPhase) {
            setStatus(rawValue: target.rawValue, at: date)
        }
    }

    /// A status chosen in the picker. Choosing an interview-phase status with no step to back
    /// it adds one — the screen, or Round 1 — so the Interview Process never lags the status.
    /// Returns the added step, for the editor to open.
    @discardableResult
    mutating func pickStatus(rawValue: String) -> ApplicationEvent? {
        setStatus(rawValue: rawValue)
        let step: ApplicationEvent
        switch ApplicationStatus(rawValue: rawValue) {
        case .recruiterScreen where interviewSteps.isEmpty:
            step = .newInterviewStep(.recruiterScreen)
        case .interviewing where interviewRounds.isEmpty:
            step = .newInterviewStep(.coding)
        default:
            return nil
        }
        // Recorded directly: the status is already what the user picked.
        recordEvent(step)
        return step
    }

    /// Starts a fresh history for a duplicated role, discarding the original's.
    mutating func resetTimeline() {
        timeline = [ApplicationEvent(date: dateSaved, kind: .created)]
    }
}

extension JobApplication: ResumeContentModel {}
