import XCTest
@testable import ApplyKit

@MainActor
final class InterviewInsightsTests: XCTestCase {
    /// A Friday morning, UTC.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func days(_ offset: Double) -> Date { now.addingTimeInterval(offset * 86_400) }

    private func application(_ company: String = "Example", role: String = "Engineer") -> JobApplication {
        var application = JobApplication(companyName: company, jobTitle: role)
        application.dateSaved = days(-100)
        application.timeline = [ApplicationEvent(date: application.dateSaved, kind: .created)]
        application.setStatus(rawValue: ApplicationStatus.applied.rawValue, at: days(-60))
        return application
    }

    private func step(_ type: InterviewType?, _ result: InterviewResult, at offset: Double,
                      minutes: Int? = nil) -> ApplicationEvent {
        ApplicationEvent(date: days(offset), kind: .interview,
                         interviewTypeRaw: type?.rawValue ?? "", interviewResultRaw: result.rawValue,
                         interview: InterviewDetails(durationMinutes: minutes))
    }

    private func insights(_ applications: [JobApplication]) -> InterviewInsights {
        InterviewInsights(applications: applications, now: now, calendar: calendar)
    }

    func testStepsSplitIntoHeldAndUpcomingAndLeaveOutOnesBeingArranged() throws {
        var app = application()
        app.recordInterviewStep(step(.recruiterScreen, .passed, at: -20))
        app.recordInterviewStep(step(.coding, .awaiting, at: -5))
        let future = step(.systemDesign, .scheduled, at: 3)
        app.recordInterviewStep(future)
        app.recordInterviewStep(.newInterviewStep(.onsite, now: days(-1)))   // no time yet

        let result = insights([app])
        XCTAssertEqual(result.steps.count, 3)
        XCTAssertEqual(result.steps.filter(\.isUpcoming).map(\.id), [future.id])
        XCTAssertEqual(result.kpis.held, 2)
        XCTAssertEqual(result.kpis.upcomingThisWeek, 1)
        XCTAssertEqual(result.kpis.next?.id, future.id)
        XCTAssertEqual(result.steps.map(\.title), ["Recruiter Screen", "Round 1 · Coding", "Round 2 · System Design"])
        XCTAssertNil(result.steps.last?.outcome, "an upcoming step has no outcome yet")
        XCTAssertEqual(result.steps[1].outcome, .pending)
    }

    func testTypeSummariesCountOutcomesAndRateOnlyDecidedSteps() throws {
        var first = application("Acme")
        first.recordInterviewStep(step(.coding, .passed, at: -30))
        first.recordInterviewStep(step(.coding, .passed, at: -25))
        first.recordInterviewStep(step(.coding, .didNotAdvance, at: -20))
        var second = application("Beta")
        second.recordInterviewStep(step(.coding, .awaiting, at: -10))
        second.recordInterviewStep(step(.systemDesign, .passed, at: -8))
        second.recordInterviewStep(step(nil, .passed, at: -6))

        let summaries = insights([first, second]).typeSummaries
        XCTAssertEqual(summaries.map(\.typeLabel), ["Coding", "Other", "System Design"])
        let coding = try XCTUnwrap(summaries.first)
        XCTAssertEqual(coding.steps.count, 4)
        XCTAssertEqual(coding.passed, 2)
        XCTAssertEqual(coding.count(.didNotAdvance), 1)
        XCTAssertEqual(coding.count(.pending), 1)
        XCTAssertEqual(try XCTUnwrap(coding.passRate), 2.0 / 3.0, accuracy: 0.0001)
    }

    func testWeeksSumHoursWithDefaultsAndRunThroughThisWeek() throws {
        var app = application()
        app.recordInterviewStep(step(.recruiterScreen, .passed, at: -14))            // 30 min by default
        app.recordInterviewStep(step(.coding, .passed, at: -14, minutes: 90))
        app.recordInterviewStep(step(.systemDesign, .scheduled, at: 1))              // 60 min by default

        let weeks = insights([app]).weeks
        XCTAssertEqual(weeks.count, 3, "two weeks ago, a quiet week, this week")
        XCTAssertEqual(weeks[0].heldHours, 2)
        XCTAssertEqual(weeks[0].upcomingHours, 0)
        XCTAssertTrue(weeks[1].steps.isEmpty)
        XCTAssertEqual(weeks[2].upcomingHours, 1)
        XCTAssertEqual(weeks[2].heldHours, 0)
    }

    func testKPIsCountCompaniesHoursAndPassRate() throws {
        var first = application("Acme")
        first.recordInterviewStep(step(.coding, .passed, at: -10, minutes: 60))
        first.recordInterviewStep(step(.behavioral, .didNotAdvance, at: -5, minutes: 45))
        var second = application("Beta")
        second.recordInterviewStep(step(.recruiterScreen, .passed, at: -3, minutes: 15))
        second.recordInterviewStep(step(.coding, .scheduled, at: 10))   // beyond the week ahead

        let kpis = insights([first, second]).kpis
        XCTAssertEqual(kpis.held, 3)
        XCTAssertEqual(kpis.companies, 2)
        XCTAssertEqual(kpis.heldHours, 2)
        XCTAssertEqual(kpis.passed, 2)
        XCTAssertEqual(kpis.decided, 3)
        XCTAssertEqual(kpis.upcomingThisWeek, 0)
        XCTAssertEqual(kpis.next?.companyName, "Beta")
    }

    func testProcessesListNewestActivityFirstAndNameRepeatedCompaniesByRole() {
        var ios = application("Acme", role: "iOS Engineer")
        ios.recordInterviewStep(step(.coding, .passed, at: -30))
        var platform = application("acme", role: "Platform Engineer")
        platform.recordInterviewStep(step(.coding, .passed, at: -20))
        var beta = application("Beta")
        beta.recordInterviewStep(step(.recruiterScreen, .passed, at: -40))
        beta.recordInterviewStep(step(.coding, .scheduled, at: 2))

        let labels = insights([ios, platform, beta]).processes.map(\.label)
        XCTAssertEqual(labels, ["Beta", "acme · Platform Engineer", "Acme · iOS Engineer"])
    }

    func testNoStepsMeansNothingToChart() {
        let result = insights([application()])
        XCTAssertTrue(result.steps.isEmpty)
        XCTAssertTrue(result.weeks.isEmpty)
        XCTAssertTrue(result.processes.isEmpty)
        XCTAssertNil(result.kpis.passRate)
    }

    // MARK: - Timeline layout

    func testStepsTooCloseToTellApartAreStackedIntoLanes() throws {
        var crowded = application("Acme")
        crowded.recordInterviewStep(step(.coding, .passed, at: -30))
        crowded.recordInterviewStep(step(.coding, .passed, at: -10))
        crowded.recordInterviewStep(step(.behavioral, .passed, at: -9.9))
        crowded.recordInterviewStep(step(.hiringManager, .awaiting, at: -9.8))
        var spread = application("Beta")
        spread.recordInterviewStep(step(.coding, .passed, at: -40))
        spread.recordInterviewStep(step(.coding, .passed, at: -20))

        let result = insights([crowded, spread])
        // 50 days across 500 points: 10 points a day, so steps a tenth of a day apart overlap.
        let domain = days(-45)...days(5)
        let layout = InterviewTimelineLayout(processes: result.processes, domain: domain, plotWidth: 500)

        let acme = try XCTUnwrap(layout.rows.first { $0.process.label == "Acme" })
        let beta = try XCTUnwrap(layout.rows.first { $0.process.label == "Beta" })
        let acmeDots = layout.dots.filter { $0.step?.companyName == "Acme" }
        XCTAssertEqual(acmeDots.map(\.lane), [0, 0, 1, 2], "the lone early step stays on the line")
        XCTAssertEqual(Set(acmeDots.map(\.y)).count, 3, "the three close steps each get their own height")
        XCTAssertTrue(layout.dots.filter { $0.step?.companyName == "Beta" }.allSatisfy { $0.y == beta.center })

        // The crowded row grows to fit its lanes; the spread-out one keeps the standard height.
        XCTAssertEqual(layout.height, (acme.center * 2) + InterviewTimelineLayout.rowHeight, accuracy: 0.001)
        XCTAssertGreaterThan(acme.center * 2, InterviewTimelineLayout.rowHeight)
    }

    func testLanesAlternateAboveAndBelowTheLine() {
        let offsets = (0..<5).map(InterviewTimelineLayout.offset(ofLane:))
        let spacing = InterviewTimelineLayout.laneSpacing
        XCTAssertEqual(offsets, [0, -spacing, spacing, -2 * spacing, 2 * spacing])
    }

    func testAnOfferEndsTheProcessOnTheTimeline() throws {
        var offered = application("Acme")
        offered.recordInterviewStep(step(.coding, .passed, at: -40))
        offered.recordInterviewStep(step(.onsite, .passed, at: -30))
        offered.setStatus(rawValue: ApplicationStatus.offer.rawValue, at: days(-20))
        var later = application("Beta")
        later.recordInterviewStep(step(.coding, .passed, at: -25))

        let result = insights([offered, later])
        let acme = try XCTUnwrap(result.processes.first { $0.label == "Acme" })
        XCTAssertEqual(acme.offerDate, days(-20))
        XCTAssertEqual(acme.last, days(-20), "the line runs to the offer, past the last step")
        XCTAssertEqual(result.processes.map(\.label), ["Acme", "Beta"], "the offer is its latest activity")
        XCTAssertNil(result.processes.first { $0.label == "Beta" }?.offerDate)

        let layout = InterviewTimelineLayout(processes: result.processes, domain: days(-45)...days(5), plotWidth: 500)
        let offers = layout.dots.filter { $0.step == nil }
        XCTAssertEqual(offers.count, 1)
        XCTAssertEqual(offers.first?.marker.date, days(-20))
    }

    func testARejectionEndsTheProcessOnlyWhileItStands() throws {
        var rejected = application("Acme")
        rejected.recordInterviewStep(step(.coding, .awaiting, at: -30))
        rejected.setStatus(rawValue: ApplicationStatus.rejected.rawValue, at: days(-25))
        var reopened = application("Beta")
        reopened.recordInterviewStep(step(.coding, .passed, at: -30))
        reopened.setStatus(rawValue: ApplicationStatus.rejected.rawValue, at: days(-25))
        reopened.setStatus(rawValue: ApplicationStatus.interviewing.rawValue, at: days(-20))
        reopened.recordInterviewStep(step(.onsite, .awaiting, at: -15))

        let processes = insights([rejected, reopened]).processes
        let acme = try XCTUnwrap(processes.first { $0.label == "Acme" })
        XCTAssertEqual(acme.endings.map(\.kind), [.rejected])
        XCTAssertEqual(acme.endings.first?.date, days(-25))
        XCTAssertEqual(acme.last, days(-25), "the line runs to the rejection")
        XCTAssertTrue(try XCTUnwrap(processes.first { $0.label == "Beta" }).endings.isEmpty,
                      "reopened since, so it hasn't ended")

        let layout = InterviewTimelineLayout(processes: processes, domain: days(-45)...days(5), plotWidth: 500)
        XCTAssertEqual(layout.dots.filter { $0.step == nil }.count, 1)
    }
}
