import Foundation

/// A step of the application funnel. Pre-apply statuses aren't stages: the funnel starts
/// at the point the company could first respond.
enum FunnelStage: Int, CaseIterable, Comparable, Identifiable {
    case applied, screen, round1, round2, round3, round4, round5Plus, offer

    var id: Int { rawValue }

    static func < (lhs: FunnelStage, rhs: FunnelStage) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .applied: "Applied"
        case .screen: "Screen"
        case .round1: "Round 1"
        case .round2: "Round 2"
        case .round3: "Round 3"
        case .round4: "Round 4"
        case .round5Plus: "Round 5+"
        case .offer: "Offer"
        }
    }

    static func round(_ number: Int) -> FunnelStage {
        switch number {
        case ...1: .round1
        case 2: .round2
        case 3: .round3
        case 4: .round4
        default: .round5Plus
        }
    }
}

/// What happened to an application at a stage. Shared by every chart so a color means the
/// same thing everywhere.
enum FunnelOutcome: Int, CaseIterable, Identifiable {
    case advanced, active, offer, rejected, ghosted, withdrawn

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .advanced: "Advanced"
        case .active: "Still active"
        case .offer: "Offer"
        case .rejected: "Rejected"
        case .ghosted: "Ghosted"
        case .withdrawn: "Withdrawn"
        }
    }

    /// Outcomes that end an application before (or instead of) an offer.
    static let exits: [FunnelOutcome] = [.rejected, .ghosted, .withdrawn]
}

/// How far one application got and when, reconstructed from its timeline.
///
/// Reach up to the last round is filled in: an application in round 3 counts as having
/// passed Applied, Screen, and rounds 1–2 even when the user skipped those statuses, since
/// skipping or jumping back in the picker is common and the funnel asks "ever reached", not
/// "passed through in order". Offer is the exception: it can follow any round, so an offer
/// after two rounds never counts as reaching rounds 3 and up.
struct ApplicationJourney {
    let applicationID: UUID
    /// Stages reached, in order. Empty when the application never reached Applied — it
    /// stays out of the funnel.
    let reachedStages: [FunnelStage]
    /// What became of it at its last reached stage.
    let outcome: FunnelOutcome
    let currentStatus: ApplicationStatus?
    /// Whether the company answered at all. Ghosted is the absence of one.
    let responded: Bool
    let appliedDate: Date?
    let firstResponseDate: Date?
    /// First observed entry into each stage. Inferred timeline entries are left out: their
    /// dates are reconstructed, and durations built on them would be fiction.
    let stageEntryDates: [FunnelStage: Date]
    /// Dates of rounds that have happened, oldest first. Unlike the stages, not capped at 5.
    let roundDates: [Date]
    let hasInferredHistory: Bool
    let fitScore: Double?
    let isArchived: Bool
    let companyName: String
    let jobTitle: String

    var furthestStage: FunnelStage? { reachedStages.last }
    var reachedOffer: Bool { reachedStages.last == .offer }

    /// The last stage before any offer: where the application sits in the pipeline.
    var lastPipelineStage: FunnelStage? { reachedStages.last { $0 != .offer } }

    init(_ application: JobApplication, now: Date) {
        applicationID = application.id
        fitScore = application.fitScore
        isArchived = application.isArchived
        companyName = application.companyName
        jobTitle = application.jobTitle
        hasInferredHistory = application.timeline.contains(where: \.isInferred)

        let current = ApplicationStatus.stored(application.statusRaw)
        currentStatus = current

        let oldestFirst = Array(application.timeline.reversed())
        let statusEvents = oldestFirst.filter(\.isStatusChange)
        var everStatuses = Set(statusEvents.compactMap { ApplicationStatus.stored($0.toStatusRaw) })
        if let current { everStatuses.insert(current) }
        // History keeps legacy round statuses verbatim; they say how far an application got
        // before rounds were tracked as steps.
        let everRaw = Set(statusEvents.map(\.toStatusRaw)).union([application.statusRaw])
        let everLegacyRound = !everRaw.isDisjoint(with: ApplicationStatus.legacyRoundRawValues)

        // Only steps that have happened; one scheduled next week hasn't been reached yet, nor
        // has a round still being arranged. A screen being arranged already is a response —
        // the recruiter reached out — but its date is only when it was added, so it counts
        // toward reach and never toward dates.
        let steps = oldestFirst.filter { $0.isInterview && $0.date <= now }
        let screenSteps = steps.filter(\.isRecruiterScreenStep)
        let screenDates = screenSteps.filter(\.hasScheduledTime).map(\.date)
        let rounds = steps.filter { !$0.isRecruiterScreenStep && $0.hasScheduledTime }
        roundDates = rounds.map(\.date)
        // Interviewing with nothing logged still means the company engaged: at least a screen.
        let everScreen = !screenSteps.isEmpty || everStatuses.contains(.recruiterScreen)
            || everStatuses.contains(.interviewing)
        // A legacy Technical/Final Interview status means at least one round, logged or not.
        let roundCount = max(rounds.count, everLegacyRound ? 1 : 0)

        let everExitedByCompany = everStatuses.contains(.rejected) || everStatuses.contains(.ghosted)
        let appliedEvidence = everStatuses.contains(.applied)
            || application.dateApplied != nil
            || everExitedByCompany

        let everOffer = everStatuses.contains(.offer)
        var stages: [FunnelStage] = []
        if appliedEvidence || everOffer || roundCount > 0 || everScreen {
            stages.append(.applied)
            if everScreen || roundCount > 0 || everOffer {
                stages.append(.screen)
            }
            // Round 5+ is one stage however many rounds followed the fourth.
            stages += (0..<min(roundCount, 5)).map { .round($0 + 1) }
            if everOffer { stages.append(.offer) }
        }
        reachedStages = stages

        switch current {
        case .rejected: outcome = .rejected
        case .ghosted: outcome = .ghosted
        case .withdrawn: outcome = .withdrawn
        default: outcome = everOffer ? .offer : .active
        }

        responded = stages.count > 1 || everStatuses.contains(.rejected)

        // MARK: Dates

        let observed = statusEvents.filter { !$0.isInferred }
        func firstObserved(_ status: ApplicationStatus) -> Date? {
            observed.first { ApplicationStatus.stored($0.toStatusRaw) == status }?.date
        }
        func firstObserved(raw values: Set<String>) -> Date? {
            observed.first { values.contains($0.toStatusRaw) }?.date
        }

        let applied = application.dateApplied ?? firstObserved(.applied)
        appliedDate = applied

        var entries: [FunnelStage: Date] = [:]
        entries[.applied] = applied
        entries[.screen] = [firstObserved(.recruiterScreen), screenDates.first].compactMap { $0 }.min()
        if rounds.isEmpty {
            entries[.round1] = firstObserved(raw: ApplicationStatus.legacyRoundRawValues)
        } else {
            for (index, date) in roundDates.prefix(5).enumerated() {
                entries[.round(index + 1)] = date
            }
        }
        entries[.offer] = firstObserved(.offer)
        stageEntryDates = entries

        // Legacy round statuses parse as Interviewing, so they count here too.
        let responseStatuses: Set<ApplicationStatus> = [.recruiterScreen, .interviewing, .offer, .rejected]
        let candidates = observed
            .filter { ApplicationStatus.stored($0.toStatusRaw).map(responseStatuses.contains) ?? false }
            .map(\.date) + screenDates + roundDates
        firstResponseDate = candidates
            .filter { date in applied.map { date >= $0 } ?? true }
            .min()
    }
}

/// Everything the Insights dashboard draws, computed in one pass over the filtered
/// applications. Pure so it can be tested without a view.
struct ApplicationInsights {
    struct KPIs {
        var applied = 0
        var responded = 0
        var interviewed = 0
        var offers = 0
        var medianDaysToResponse: Double?

        func rate(_ count: Int) -> Double? { applied == 0 ? nil : Double(count) / Double(applied) }
    }

    struct FunnelSegment: Identifiable {
        let stage: FunnelStage
        let outcome: FunnelOutcome
        /// The applications in this piece of the bar, by company then role.
        let members: [ApplicationJourney]
        var count: Int { members.count }
        var id: String { "\(stage.rawValue)-\(outcome.rawValue)" }
    }

    enum FlowTarget: Hashable {
        case stage(FunnelStage)
        case outcome(FunnelOutcome)
    }

    private struct FlowKey: Hashable {
        let from: FunnelStage
        let to: FlowTarget
    }

    struct Flow: Identifiable {
        let from: FunnelStage
        let to: FlowTarget
        /// The applications that took this path, by company then role.
        let members: [ApplicationJourney]
        var count: Int { members.count }
        var id: String { "\(from.rawValue)->\(to)" }
    }

    enum SnapshotCategory: Int, CaseIterable, Identifiable {
        case preApply, applied, screen, interviewing, offer, rejected, ghosted, withdrawn
        var id: Int { rawValue }

        var label: String {
            switch self {
            case .preApply: "Pre-apply"
            case .applied: "Applied"
            case .screen: "Recruiter Screen"
            case .interviewing: "Interviewing"
            case .offer: "Offer"
            case .rejected: "Rejected"
            case .ghosted: "Ghosted"
            case .withdrawn: "Withdrawn"
            }
        }

        init(_ status: ApplicationStatus?) {
            switch status {
            case .applied: self = .applied
            case .recruiterScreen: self = .screen
            case .interviewing: self = .interviewing
            case .offer: self = .offer
            case .rejected: self = .rejected
            case .ghosted: self = .ghosted
            case .withdrawn: self = .withdrawn
            case .saved, .interested, .preparing, .referralRequested, nil: self = .preApply
            }
        }
    }

    struct SnapshotSlice: Identifiable {
        let category: SnapshotCategory
        let count: Int
        var id: Int { category.rawValue }
    }

    enum ActivityKind: String, CaseIterable {
        case applied = "Applied"
        case response = "Responses"
    }

    struct ActivityPoint {
        let date: Date
        let kind: ActivityKind
    }

    struct DurationSummary: Identifiable {
        let label: String
        let sampleCount: Int
        let p25: Double
        let median: Double
        let p75: Double
        var id: String { label }
    }

    struct FitPoint: Identifiable {
        let id: UUID
        let fitScore: Double
        let stage: FunnelStage
        let outcome: FunnelOutcome
    }

    let journeys: [ApplicationJourney]
    let kpis: KPIs
    let funnel: [FunnelSegment]
    /// How many applications reached each stage, in stage order, stages nobody reached left out.
    /// Every stage but Offer is a prefix of the one before it; Offer can follow any of them.
    let reached: [(stage: FunnelStage, count: Int)]
    let flows: [Flow]
    /// The applications that reached each stage, by company then role.
    let stageMembers: [FunnelStage: [ApplicationJourney]]
    let snapshot: [SnapshotSlice]
    let activity: [ActivityPoint]
    let durations: [DurationSummary]
    let fitPoints: [FitPoint]
    /// Applications in the funnel whose history is partly reconstructed.
    let inferredCount: Int
    /// The interview steps themselves: round types, per-company timelines, weekly load.
    let interviews: InterviewInsights

    init(applications: [JobApplication], now: Date = Date()) {
        let all = applications.map { ApplicationJourney($0, now: now) }
        journeys = all
        let inFunnel = all.filter { !$0.reachedStages.isEmpty }

        // Funnel: every reached stage but the last is "advanced"; the last carries the outcome.
        let byName = inFunnel.sorted(by: Self.byCompanyThenRole)
        var segmentMembers: [FunnelStage: [FunnelOutcome: [ApplicationJourney]]] = [:]
        var stageMembers: [FunnelStage: [ApplicationJourney]] = [:]
        for journey in byName {
            for stage in journey.reachedStages {
                let outcome = stage == journey.furthestStage ? journey.outcome : .advanced
                segmentMembers[stage, default: [:]][outcome, default: []].append(journey)
                stageMembers[stage, default: []].append(journey)
            }
        }
        self.stageMembers = stageMembers
        funnel = FunnelStage.allCases.flatMap { stage in
            FunnelOutcome.allCases.compactMap { outcome in
                segmentMembers[stage]?[outcome].map { FunnelSegment(stage: stage, outcome: outcome, members: $0) }
            }
        }
        reached = FunnelStage.allCases.compactMap { stage in
            let total = stageMembers[stage]?.count ?? 0
            return total > 0 ? (stage, total) : nil
        }

        // Sankey flows run along the pipeline stages, which are always contiguous. Offer is the
        // final column, fed from whichever stage the offer followed, so its ribbons can skip
        // columns. It's terminal: however an offer ended, nothing flows out of it.
        var flowMembers: [FlowKey: [ApplicationJourney]] = [:]
        for journey in byName {
            let pipeline = journey.reachedStages.filter { $0 != .offer }
            for (stage, next) in zip(pipeline, pipeline.dropFirst()) {
                flowMembers[FlowKey(from: stage, to: .stage(next)), default: []].append(journey)
            }
            if let last = pipeline.last {
                let target: FlowTarget = journey.reachedOffer ? .stage(.offer) : .outcome(journey.outcome)
                flowMembers[FlowKey(from: last, to: target), default: []].append(journey)
            }
        }
        let targetOrder: [FlowTarget] = FunnelStage.allCases.map { .stage($0) }
            + ([.active] + FunnelOutcome.exits).map { .outcome($0) }
        flows = FunnelStage.allCases.flatMap { stage in
            targetOrder.compactMap { target in
                flowMembers[FlowKey(from: stage, to: target)].map { Flow(from: stage, to: target, members: $0) }
            }
        }

        var kpis = KPIs()
        kpis.applied = inFunnel.count
        kpis.responded = inFunnel.filter(\.responded).count
        kpis.interviewed = inFunnel.filter { $0.reachedStages.contains(.round1) }.count
        kpis.offers = inFunnel.filter(\.reachedOffer).count

        let responseDays = inFunnel.compactMap { journey -> Double? in
            guard let applied = journey.appliedDate, let response = journey.firstResponseDate else { return nil }
            return Self.days(from: applied, to: response)
        }
        kpis.medianDaysToResponse = Self.percentile(responseDays, 0.5)
        self.kpis = kpis

        // Archiving is how applications get closed out, so archived ones count everywhere —
        // except one archived without ever being applied to, which was simply dropped and
        // would only pad the Pre-apply slice.
        let inSnapshot = all.filter { !$0.reachedStages.isEmpty || !$0.isArchived }
        let snapshotCounts = Dictionary(grouping: inSnapshot, by: { SnapshotCategory($0.currentStatus) })
            .mapValues(\.count)
        snapshot = SnapshotCategory.allCases.compactMap { category in
            snapshotCounts[category].map { SnapshotSlice(category: category, count: $0) }
        }

        activity = inFunnel.flatMap { journey in
            [journey.appliedDate.map { ActivityPoint(date: $0, kind: .applied) },
             journey.firstResponseDate.map { ActivityPoint(date: $0, kind: .response) }]
                .compactMap { $0 }
        }

        var screenToRound: [Double] = []
        var betweenRounds: [Double] = []
        var lastRoundToOffer: [Double] = []
        for journey in inFunnel {
            if let screen = journey.stageEntryDates[.screen], let round = journey.stageEntryDates[.round1],
               let days = Self.days(from: screen, to: round) {
                screenToRound.append(days)
            }
            for (earlier, later) in zip(journey.roundDates, journey.roundDates.dropFirst()) {
                if let days = Self.days(from: earlier, to: later) { betweenRounds.append(days) }
            }
            if let offer = journey.stageEntryDates[.offer],
               let lastRound = journey.roundDates.last(where: { $0 <= offer }),
               let days = Self.days(from: lastRound, to: offer) {
                lastRoundToOffer.append(days)
            }
        }
        durations = [
            ("Applied → first response", responseDays),
            ("Screen → round 1", screenToRound),
            ("Between rounds", betweenRounds),
            ("Last round → offer", lastRoundToOffer)
        ].compactMap { label, samples in
            guard let p25 = Self.percentile(samples, 0.25),
                  let median = Self.percentile(samples, 0.5),
                  let p75 = Self.percentile(samples, 0.75) else { return nil }
            return DurationSummary(label: label, sampleCount: samples.count, p25: p25, median: median, p75: p75)
        }

        fitPoints = inFunnel.compactMap { journey in
            guard let fit = journey.fitScore, let stage = journey.furthestStage else { return nil }
            return FitPoint(id: journey.applicationID, fitScore: fit, stage: stage, outcome: journey.outcome)
        }

        inferredCount = inFunnel.filter(\.hasInferredHistory).count
        interviews = InterviewInsights(applications: applications, now: now)
    }

    private static func byCompanyThenRole(_ lhs: ApplicationJourney, _ rhs: ApplicationJourney) -> Bool {
        // Case-insensitive so one company's roles stay together however its name was typed.
        let company = lhs.companyName.localizedCaseInsensitiveCompare(rhs.companyName)
        if company != .orderedSame { return company == .orderedAscending }
        return lhs.jobTitle.localizedStandardCompare(rhs.jobTitle) == .orderedAscending
    }

    /// Whole-or-fractional days between two dates; nil when the order is backwards, which
    /// only happens when an entry's date was edited to something inconsistent.
    static func days(from start: Date, to end: Date) -> Double? {
        let interval = end.timeIntervalSince(start)
        return interval >= 0 ? interval / 86_400 : nil
    }

    /// Linear-interpolated percentile; nil for an empty sample.
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
