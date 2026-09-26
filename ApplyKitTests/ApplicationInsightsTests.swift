import XCTest
@testable import ApplyKit

@MainActor
final class ApplicationInsightsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    private func application(appliedDaysAgo applied: Double?) -> JobApplication {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.dateSaved = daysAgo(100)
        application.timeline = [ApplicationEvent(date: application.dateSaved, kind: .created)]
        if let applied {
            application.setStatus(rawValue: ApplicationStatus.applied.rawValue, at: daysAgo(applied))
        }
        return application
    }

    /// A status change as older builds recorded it, before the interview phase was carried by
    /// steps alone.
    private func recordLegacyStatus(_ raw: String, daysAgo days: Double, on app: inout JobApplication) {
        app.recordEvent(ApplicationEvent(date: daysAgo(days), kind: .statusChanged,
                                         fromStatusRaw: app.statusRaw, toStatusRaw: raw))
        app.statusRaw = raw
    }

    private func screen(_ days: Double) -> ApplicationEvent {
        ApplicationEvent(date: daysAgo(days), kind: .interview,
                         interviewTypeRaw: InterviewType.recruiterScreen.rawValue,
                         interviewResultRaw: InterviewResult.passed.rawValue)
    }

    private func round(_ days: Double) -> ApplicationEvent {
        ApplicationEvent(date: daysAgo(days), kind: .interview,
                         interviewTypeRaw: InterviewType.coding.rawValue,
                         interviewResultRaw: InterviewResult.passed.rawValue)
    }

    // MARK: - Journeys

    func testReachIsMonotonicAcrossSkippedStatuses() {
        var app = application(appliedDaysAgo: 30)
        app.recordInterviewStep(round(20))
        app.recordInterviewStep(round(15))
        app.recordInterviewStep(round(10))

        let journey = ApplicationJourney(app, now: now)
        XCTAssertEqual(journey.furthestStage, .round3)
        XCTAssertEqual(journey.outcome, .active)
        XCTAssertTrue(journey.responded)

        // Never set to Recruiter Screen, yet the funnel counts it as passed.
        let insights = ApplicationInsights(applications: [app], now: now)
        XCTAssertEqual(insights.reached.map(\.stage), [.applied, .screen, .round1, .round2, .round3])
    }

    func testARecruiterScreenStepCountsAsTheScreenNotARound() throws {
        var app = application(appliedDaysAgo: 30)
        app.recordInterviewStep(ApplicationEvent(date: daysAgo(20), kind: .interview,
                                                 interviewTypeRaw: InterviewType.recruiterScreen.rawValue))
        let journey = ApplicationJourney(app, now: now)
        XCTAssertEqual(journey.reachedStages, [.applied, .screen])
        XCTAssertTrue(journey.roundDates.isEmpty)
        let response = try XCTUnwrap(journey.firstResponseDate)
        XCTAssertEqual(response.timeIntervalSince1970, daysAgo(20).timeIntervalSince1970, accuracy: 1)
    }

    func testStepsStillBeingArrangedCountTowardReachButNotDates() throws {
        var app = application(appliedDaysAgo: 30)
        app.recordInterviewStep(.newInterviewStep(.recruiterScreen, now: daysAgo(20)))
        app.recordInterviewStep(.newInterviewStep(.coding, now: daysAgo(10)))

        let journey = ApplicationJourney(app, now: now)
        // The screen being arranged means they responded; the round hasn't happened.
        XCTAssertEqual(journey.reachedStages, [.applied, .screen])
        XCTAssertTrue(journey.roundDates.isEmpty)
        XCTAssertTrue(journey.responded)
        // Their dates are only when they were added, not when anyone reached out.
        XCTAssertNil(journey.firstResponseDate)
        XCTAssertNil(journey.stageEntryDates[.screen])
    }

    func testLegacyRoundStatusesCountAsRoundOne() {
        for legacy in ApplicationStatus.legacyRoundRawValues {
            var app = application(appliedDaysAgo: 30)
            recordLegacyStatus(legacy, daysAgo: 20, on: &app)
            XCTAssertEqual(ApplicationJourney(app, now: now).furthestStage, .round1, legacy)
        }
    }

    func testInterviewingWithNothingLoggedCountsAsTheScreen() {
        var app = application(appliedDaysAgo: 30)
        recordLegacyStatus(ApplicationStatus.interviewing.rawValue, daysAgo: 20, on: &app)
        XCTAssertEqual(ApplicationJourney(app, now: now).furthestStage, .screen)

        var screenOnly = application(appliedDaysAgo: 30)
        recordLegacyStatus(ApplicationStatus.recruiterScreen.rawValue, daysAgo: 20, on: &screenOnly)
        let journey = ApplicationJourney(screenOnly, now: now)
        XCTAssertEqual(journey.furthestStage, .screen)
        XCTAssertEqual(journey.stageEntryDates[.screen], daysAgo(20))
    }

    func testScheduledFutureRoundsAreNotReached() {
        var app = application(appliedDaysAgo: 30)
        app.recordInterviewStep(round(10))
        app.recordInterviewStep(ApplicationEvent(date: now.addingTimeInterval(3 * 86_400), kind: .interview))
        XCTAssertEqual(ApplicationJourney(app, now: now).furthestStage, .round1)
    }

    func testAnOfferAfterTwoRoundsSkipsTheLaterRounds() {
        var app = application(appliedDaysAgo: 40)
        app.recordInterviewStep(round(30))
        app.recordInterviewStep(round(20))
        app.setStatus(rawValue: ApplicationStatus.offer.rawValue, at: daysAgo(10))
        XCTAssertEqual(ApplicationJourney(app, now: now).reachedStages, [.applied, .screen, .round1, .round2, .offer])
    }

    func testFiveRoundsFoldIntoRoundFourPlus() {
        var app = application(appliedDaysAgo: 60)
        for days in [50.0, 40, 30, 20, 10] { app.recordInterviewStep(round(days)) }
        let journey = ApplicationJourney(app, now: now)
        XCTAssertEqual(journey.furthestStage, .round4Plus)
        XCTAssertEqual(journey.roundDates.count, 5)
    }

    func testRejectionWithoutAnAppliedEventStillEntersTheFunnel() {
        var app = application(appliedDaysAgo: nil)
        app.setStatus(rawValue: ApplicationStatus.rejected.rawValue, at: daysAgo(5))
        let journey = ApplicationJourney(app, now: now)
        XCTAssertEqual(journey.furthestStage, .applied)
        XCTAssertEqual(journey.outcome, .rejected)
        XCTAssertTrue(journey.responded)
    }

    func testWithdrawingBeforeApplyingStaysOutOfTheFunnel() {
        var app = application(appliedDaysAgo: nil)
        app.setStatus(rawValue: ApplicationStatus.withdrawn.rawValue, at: daysAgo(5))
        XCTAssertNil(ApplicationJourney(app, now: now).furthestStage)
    }

    func testGhostingIsNotAResponse() {
        var app = application(appliedDaysAgo: 30)
        app.setStatus(rawValue: ApplicationStatus.ghosted.rawValue, at: daysAgo(2))
        let journey = ApplicationJourney(app, now: now)
        XCTAssertFalse(journey.responded)
        XCTAssertNil(journey.firstResponseDate)
    }

    func testFirstResponseIsTheEarliestReplyAfterApplying() throws {
        var app = application(appliedDaysAgo: 30)
        app.recordInterviewStep(screen(21))
        app.recordInterviewStep(round(14))
        let response = try XCTUnwrap(ApplicationJourney(app, now: now).firstResponseDate)
        XCTAssertEqual(response.timeIntervalSince1970, daysAgo(21).timeIntervalSince1970, accuracy: 1)
    }

    func testInferredHistoryCountsTowardReachButNotDurations() {
        var app = JobApplication(companyName: "Legacy", jobTitle: "Engineer")
        app.statusRaw = ApplicationStatus.recruiterScreen.rawValue
        app.dateSaved = daysAgo(40)
        app.updatedAt = daysAgo(10)
        app.timeline = ApplicationTimeline.backfilled(for: app)   // no dateApplied: screen entry is inferred

        let journey = ApplicationJourney(app, now: now)
        XCTAssertEqual(journey.furthestStage, .screen)
        XCTAssertTrue(journey.hasInferredHistory)
        XCTAssertNil(journey.stageEntryDates[.screen])
        XCTAssertNil(journey.firstResponseDate)

        let insights = ApplicationInsights(applications: [app], now: now)
        XCTAssertEqual(insights.inferredCount, 1)
        XCTAssertTrue(insights.durations.isEmpty)
    }

    // MARK: - Aggregates

    private func fixture() -> [JobApplication] {
        var offer = application(appliedDaysAgo: 60)
        offer.recordInterviewStep(screen(50))
        offer.recordInterviewStep(round(40))
        offer.recordInterviewStep(round(30))
        offer.setStatus(rawValue: ApplicationStatus.offer.rawValue, at: daysAgo(20))

        var rejectedAfterRound = application(appliedDaysAgo: 50)
        rejectedAfterRound.recordInterviewStep(screen(40))
        rejectedAfterRound.recordInterviewStep(round(30))
        rejectedAfterRound.setStatus(rawValue: ApplicationStatus.rejected.rawValue, at: daysAgo(25))

        var ghosted = application(appliedDaysAgo: 40)
        ghosted.setStatus(rawValue: ApplicationStatus.ghosted.rawValue, at: daysAgo(5))

        let waiting = application(appliedDaysAgo: 10)
        let notApplied = application(appliedDaysAgo: nil)

        return [offer, rejectedAfterRound, ghosted, waiting, notApplied]
    }

    func testFunnelSegmentsAddUpToWhatReachedEachStage() {
        let insights = ApplicationInsights(applications: fixture(), now: now)

        for (stage, reached) in insights.reached {
            let segments = insights.funnel.filter { $0.stage == stage }.reduce(0) { $0 + $1.count }
            XCTAssertEqual(segments, reached, "\(stage.label)")
        }
        XCTAssertEqual(insights.reached.map(\.count), [4, 2, 2, 1, 1])   // applied, screen, r1, r2, offer
    }

    func testFlowsLeavingAStageMatchTheFunnel() {
        let insights = ApplicationInsights(applications: fixture(), now: now)

        // Offer is a Sankey outcome, not a column, so every other stage's reach leaves it.
        for (stage, reached) in insights.reached where stage != .offer {
            let outgoing = insights.flows.filter { $0.from == stage }.reduce(0) { $0 + $1.count }
            XCTAssertEqual(outgoing, reached, "\(stage.label)")
        }
        XCTAssertFalse(insights.flows.contains { $0.from == .offer })
        let offerFlows = insights.flows.filter { $0.to == .outcome(.offer) }
        XCTAssertEqual(offerFlows.map(\.from), [.round2])
    }

    func testKPIs() throws {
        let insights = ApplicationInsights(applications: fixture(), now: now)
        let kpis = insights.kpis
        XCTAssertEqual(kpis.applied, 4)
        XCTAssertEqual(kpis.responded, 2)
        XCTAssertEqual(kpis.interviewed, 2)
        XCTAssertEqual(kpis.offers, 1)
        XCTAssertEqual(try XCTUnwrap(kpis.rate(kpis.responded)), 0.5, accuracy: 0.0001)
        // Replies came 10 days after applying in both cases.
        XCTAssertEqual(try XCTUnwrap(kpis.medianDaysToResponse), 10, accuracy: 0.01)
    }

    func testSnapshotGroupsPreApplyStatuses() {
        let insights = ApplicationInsights(applications: fixture(), now: now)
        let counts = Dictionary(uniqueKeysWithValues: insights.snapshot.map { ($0.category, $0.count) })
        XCTAssertEqual(counts[.preApply], 1)
        XCTAssertEqual(counts[.applied], 1)
        XCTAssertEqual(counts[.offer], 1)
        XCTAssertEqual(counts[.rejected], 1)
        XCTAssertEqual(counts[.ghosted], 1)
    }

    func testArchivedRejectionsCountButArchivedNeverAppliedRolesLeaveTheSnapshot() {
        var rejected = application(appliedDaysAgo: 30)
        rejected.setStatus(rawValue: ApplicationStatus.rejected.rawValue, at: daysAgo(20))
        rejected.archivedAt = daysAgo(19)

        var dropped = application(appliedDaysAgo: nil)
        dropped.archivedAt = daysAgo(10)

        let openSaved = application(appliedDaysAgo: nil)

        let insights = ApplicationInsights(applications: [rejected, dropped, openSaved], now: now)
        XCTAssertEqual(insights.kpis.applied, 1)
        XCTAssertEqual(insights.funnel.first { $0.stage == .applied }?.outcome, .rejected)

        let counts = Dictionary(uniqueKeysWithValues: insights.snapshot.map { ($0.category, $0.count) })
        XCTAssertEqual(counts[.rejected], 1)
        XCTAssertEqual(counts[.preApply], 1)   // the open one; the dropped one is left out
    }

    func testPercentileInterpolates() {
        XCTAssertNil(ApplicationInsights.percentile([], 0.5))
        XCTAssertEqual(ApplicationInsights.percentile([4], 0.25), 4)
        XCTAssertEqual(ApplicationInsights.percentile([1, 2, 3, 4], 0.5), 2.5)
        XCTAssertEqual(ApplicationInsights.percentile([10, 0, 20], 0.25), 5)
    }
}

@MainActor
final class SankeyHoverTests: XCTestCase {
    /// 40 applications, one of them rejected at Applied: a flow a pixel or two thick.
    private func layout() -> (SankeyLayout, ApplicationInsights.Flow) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let apps = (0..<40).map { index -> JobApplication in
            var app = JobApplication(companyName: "C\(index)", jobTitle: "Engineer")
            app.setStatus(rawValue: ApplicationStatus.applied.rawValue, at: now.addingTimeInterval(-86_400 * 20))
            if index == 0 { app.setStatus(rawValue: ApplicationStatus.rejected.rawValue, at: now.addingTimeInterval(-86_400)) }
            return app
        }
        let insights = ApplicationInsights(applications: apps, now: now)
        let thin = insights.flows.first { $0.to == .outcome(.rejected) }!
        return (SankeyLayout(insights: insights, width: 900), thin)
    }

    func testAThinRibbonCanBeHoveredNearItsCentreLine() throws {
        let (layout, thin) = layout()
        let ribbon = try XCTUnwrap(layout.ribbons.first { $0.flow.id == thin.id })
        // The S-curve's midpoint is the centre of its bounds; a few points off it still counts.
        let centre = CGPoint(x: ribbon.path.boundingRect.midX, y: ribbon.path.boundingRect.midY)
        XCTAssertEqual(layout.flowID(at: CGPoint(x: centre.x, y: centre.y + 5)), thin.id)
        XCTAssertNil(layout.flowID(at: CGPoint(x: centre.x + 400, y: centre.y + 200)))
    }

    func testHoveringAnOutcomeLabelShowsItsFlow() throws {
        let (layout, thin) = layout()
        let node = try XCTUnwrap(layout.nodes.first { $0.flowID == thin.id })
        XCTAssertEqual(layout.flowID(at: CGPoint(x: node.labelPoint.x + 30, y: node.labelPoint.y)), thin.id)
    }
}
