import Foundation

/// What the logged interview steps say about the search: how each kind of round tends to go,
/// how each company's process has unfolded, and how much time interviewing takes week to
/// week. Pure, built from the same filtered applications as `ApplicationInsights`.
struct InterviewInsights {
    /// One step with a time set. Steps still being arranged are left out: their date is only
    /// when they were logged, so every chart here would misplace them.
    struct Step: Identifiable {
        let id: UUID
        let applicationID: UUID
        let companyName: String
        let jobTitle: String
        let date: Date
        /// The type as stored, or "Other" when it's empty.
        let typeLabel: String
        let isRecruiterScreen: Bool
        let result: InterviewResult
        /// "Recruiter Screen" or "Round 2 · System Design", plus the step's own label.
        let title: String
        let durationMinutes: Int?
        let format: InterviewFormat?
        let interviewers: String
        let isUpcoming: Bool

        /// Logged duration, else the length a new step of this kind starts with.
        var effectiveMinutes: Int { durationMinutes ?? (isRecruiterScreen ? 30 : 60) }

        /// nil until the step has happened.
        var outcome: StepOutcome? {
            guard !isUpcoming else { return nil }
            switch result {
            case .passed: return .passed
            case .didNotAdvance: return .didNotAdvance
            case .awaiting, .scheduled, .scheduling: return .pending
            }
        }
    }

    /// How a step that has happened went, by its recorded result alone.
    enum StepOutcome: Int, CaseIterable, Identifiable {
        case passed, didNotAdvance, pending

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .passed: "Passed"
            case .didNotAdvance: "Didn't advance"
            case .pending: "Pending"
            }
        }
    }

    struct TypeSummary: Identifiable {
        let typeLabel: String
        /// Held steps of this type, oldest first.
        let steps: [Step]
        var id: String { typeLabel }

        func count(_ outcome: StepOutcome) -> Int { steps.filter { $0.outcome == outcome }.count }
        var passed: Int { count(.passed) }
        var decided: Int { passed + count(.didNotAdvance) }
        /// Share passed among steps with a verdict; nil while every one is pending.
        var passRate: Double? { decided == 0 ? nil : Double(passed) / Double(decided) }
    }

    struct Week: Identifiable {
        let start: Date
        var steps: [Step] = []
        var id: Date { start }

        var held: [Step] { steps.filter { !$0.isUpcoming } }
        var upcoming: [Step] { steps.filter(\.isUpcoming) }
        var heldHours: Double { Self.hours(held) }
        var upcomingHours: Double { Self.hours(upcoming) }
        var totalHours: Double { Self.hours(steps) }

        private static func hours(_ steps: [Step]) -> Double {
            Double(steps.reduce(0) { $0 + $1.effectiveMinutes }) / 60
        }
    }

    /// One application's interviews, start to latest.
    struct Process: Identifiable {
        let applicationID: UUID
        /// The company, or "Company · Role" when the same company appears more than once.
        let label: String
        /// Oldest first.
        let steps: [Step]
        var id: UUID { applicationID }
        var first: Date { steps.first?.date ?? .distantPast }
        var last: Date { steps.last?.date ?? .distantPast }
    }

    struct KPIs {
        var held = 0
        var companies = 0
        var heldHours: Double = 0
        var passed = 0
        var decided = 0
        var upcomingThisWeek = 0
        var next: Step?

        var passRate: Double? { decided == 0 ? nil : Double(passed) / Double(decided) }
    }

    /// Every step with a time, oldest first.
    let steps: [Step]
    /// Kinds of step that have happened, most common first.
    let typeSummaries: [TypeSummary]
    /// From the first step's week through the later of the last step's and this week, quiet
    /// weeks included.
    let weeks: [Week]
    /// Most recently active first.
    let processes: [Process]
    let kpis: KPIs
    /// The moment "held" and "upcoming" are split at.
    let now: Date

    init(applications: [JobApplication], now: Date, calendar: Calendar = .current) {
        self.now = now
        var steps: [Step] = []
        for application in applications {
            for event in application.interviewSteps where event.hasScheduledTime {
                steps.append(Step(
                    id: event.id,
                    applicationID: application.id,
                    companyName: application.companyName.trimmed.isEmpty ? "Untitled" : application.companyName,
                    jobTitle: application.jobTitle,
                    date: event.date,
                    typeLabel: event.interviewTypeRaw.trimmed.isEmpty ? InterviewType.other.rawValue : event.interviewTypeRaw,
                    isRecruiterScreen: event.isRecruiterScreenStep,
                    result: event.interviewResult,
                    title: application.stepTitle(for: event),
                    durationMinutes: event.interview.durationMinutes,
                    format: event.interview.format,
                    interviewers: event.interview.interviewers,
                    isUpcoming: event.date > now
                ))
            }
        }
        steps.sort { $0.date < $1.date }
        self.steps = steps
        let held = steps.filter { !$0.isUpcoming }

        typeSummaries = Dictionary(grouping: held, by: \.typeLabel)
            .map { TypeSummary(typeLabel: $0.key, steps: $0.value) }
            .sorted { lhs, rhs in
                lhs.steps.count != rhs.steps.count
                    ? lhs.steps.count > rhs.steps.count
                    : lhs.typeLabel.localizedStandardCompare(rhs.typeLabel) == .orderedAscending
            }

        weeks = Self.weeks(steps, now: now, calendar: calendar)

        let byApplication = Dictionary(grouping: steps, by: \.applicationID)
        let companyCounts = Dictionary(grouping: byApplication.values.compactMap(\.first),
                                       by: { $0.companyName.lowercased() }).mapValues(\.count)
        processes = byApplication.values.compactMap { steps -> Process? in
            guard let first = steps.first else { return nil }
            let shared = (companyCounts[first.companyName.lowercased()] ?? 0) > 1
            let role = first.jobTitle.trimmed
            let label = shared && !role.isEmpty ? "\(first.companyName) · \(role)" : first.companyName
            return Process(applicationID: first.applicationID, label: label, steps: steps)
        }
        .sorted { $0.last > $1.last }

        var kpis = KPIs()
        kpis.held = held.count
        kpis.companies = Set(held.map(\.applicationID)).count
        kpis.heldHours = Double(held.reduce(0) { $0 + $1.effectiveMinutes }) / 60
        kpis.passed = held.filter { $0.outcome == .passed }.count
        kpis.decided = kpis.passed + held.filter { $0.outcome == .didNotAdvance }.count
        let weekAhead = now.addingTimeInterval(7 * 86_400)
        let upcoming = steps.filter(\.isUpcoming)
        kpis.upcomingThisWeek = upcoming.filter { $0.date <= weekAhead }.count
        kpis.next = upcoming.first
        self.kpis = kpis
    }

    /// "4" or "4.5": hours to at most one decimal.
    static func formatHours(_ hours: Double) -> String {
        hours.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func weeks(_ steps: [Step], now: Date, calendar: Calendar) -> [Week] {
        func weekStart(_ date: Date) -> Date? { calendar.dateInterval(of: .weekOfYear, for: date)?.start }
        var byStart: [Date: Week] = [:]
        for step in steps {
            guard let start = weekStart(step.date) else { continue }
            byStart[start, default: Week(start: start)].steps.append(step)
        }
        guard let first = byStart.keys.min(), let lastStep = byStart.keys.max() else { return [] }
        let last = max(lastStep, weekStart(now) ?? lastStep)
        var weeks: [Week] = []
        var start = first
        while start <= last {
            weeks.append(byStart[start] ?? Week(start: start))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { break }
            start = next
        }
        return weeks
    }
}
