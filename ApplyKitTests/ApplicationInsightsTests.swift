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

    func testFourRoundsStopAtRoundFour() {
        var app = application(appliedDaysAgo: 60)
        for days in [50.0, 40, 30, 20] { app.recordInterviewStep(round(days)) }
        XCTAssertEqual(ApplicationJourney(app, now: now).furthestStage, .round4)
    }

    func testSixRoundsFoldIntoRoundFivePlus() {
        var app = application(appliedDaysAgo: 70)
        for days in [60.0, 50, 40, 30, 20, 10] { app.recordInterviewStep(round(days)) }
        let journey = ApplicationJourney(app, now: now)
        XCTAssertEqual(journey.furthestStage, .round5Plus)
        XCTAssertEqual(journey.reachedStages, [.applied, .screen, .round1, .round2, .round3, .round4, .round5Plus])
        XCTAssertEqual(journey.roundDates.count, 6)
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

        // Offer is the terminal column, so every other stage's reach leaves it.
        for (stage, reached) in insights.reached where stage != .offer {
            let outgoing = insights.flows.filter { $0.from == stage }.reduce(0) { $0 + $1.count }
            XCTAssertEqual(outgoing, reached, "\(stage.label)")
        }
        XCTAssertFalse(insights.flows.contains { $0.from == .offer })
        let offerFlows = insights.flows.filter { $0.to == .stage(.offer) }
        XCTAssertEqual(offerFlows.map(\.from), [.round2])
    }

    func testOfferIsTheLastSankeyColumnNotAnOutcome() throws {
        let insights = ApplicationInsights(applications: fixture(), now: now)
        let layout = SankeyLayout(insights: insights, width: 900)

        let columns = layout.nodes.filter { $0.labelAnchor == .bottomLeading }
        XCTAssertEqual(columns.map(\.label), ["Offer", "Applied", "Screen", "Round 1", "Round 2"])
        let offer = try XCTUnwrap(columns.first)
        XCTAssertEqual(offer.rect.minX, columns.map(\.rect.minX).max())
        XCTAssertFalse(layout.nodes.contains { $0.labelAnchor == .leading && $0.label == "Offer" })

        let ribbon = try XCTUnwrap(layout.ribbons.first { $0.flow.to == .stage(.offer) })
        XCTAssertEqual(ribbon.path.boundingRect.maxX, offer.rect.minX, accuracy: 0.5)
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

    // MARK: - Members

    func testFlowAndStageMembersMatchTheirCounts() {
        let insights = ApplicationInsights(applications: fixture(), now: now)

        for flow in insights.flows {
            XCTAssertEqual(flow.members.count, flow.count)
        }
        for (stage, reached) in insights.reached {
            let members = insights.stageMembers[stage] ?? []
            XCTAssertEqual(members.count, reached, stage.label)
            guard stage != .offer else { continue }
            let outgoing = insights.flows.filter { $0.from == stage }.flatMap(\.members).map(\.applicationID)
            XCTAssertEqual(Set(outgoing), Set(members.map(\.applicationID)), stage.label)
        }
    }

    func testInterviewToOfferCountsOnlyFinishedLoopsPastRoundOne() throws {
        // The fixture: an offer after two rounds, a rejection after one round, a ghosting
        // before any round, one waiting, one never applied.
        var stillInterviewing = application(appliedDaysAgo: 30)
        stillInterviewing.recordInterviewStep(round(20))
        var withdrewAfterRound = application(appliedDaysAgo: 30)
        withdrewAfterRound.recordInterviewStep(round(20))
        withdrewAfterRound.setStatus(rawValue: ApplicationStatus.withdrawn.rawValue, at: daysAgo(10))

        let kpis = ApplicationInsights(applications: fixture() + [stillInterviewing, withdrewAfterRound], now: now).kpis
        XCTAssertEqual(kpis.finishedAfterInterviewing, 3, "offer, rejection, withdrawal; the ghosting never reached a round")
        XCTAssertEqual(kpis.offersAfterInterviewing, 1)
        XCTAssertEqual(kpis.interviewingNow, 1)
        XCTAssertEqual(try XCTUnwrap(kpis.interviewToOfferRate), 1.0 / 3.0, accuracy: 0.0001)
    }

    func testADeclinedOfferStillCountsAsConverting() throws {
        var declined = application(appliedDaysAgo: 40)
        declined.recordInterviewStep(round(30))
        declined.setStatus(rawValue: ApplicationStatus.offer.rawValue, at: daysAgo(20))
        declined.setStatus(rawValue: ApplicationStatus.withdrawn.rawValue, at: daysAgo(10))

        let kpis = ApplicationInsights(applications: [declined], now: now).kpis
        XCTAssertEqual(kpis.finishedAfterInterviewing, 1)
        XCTAssertEqual(kpis.offersAfterInterviewing, 1)
    }

    func testFunnelSegmentsListTheApplicationsThatEndedThere() throws {
        let insights = ApplicationInsights(applications: fixture(), now: now)

        for (stage, _) in insights.reached {
            let segments = insights.funnel.filter { $0.stage == stage }
            let ids = segments.flatMap(\.members).map(\.applicationID)
            XCTAssertEqual(ids.count, Set(ids).count, "each application sits in one segment of \(stage.label)")
            XCTAssertEqual(Set(ids), Set((insights.stageMembers[stage] ?? []).map(\.applicationID)), stage.label)
        }
        // The fixture's rejection came after round 1, so that's the segment that lists it.
        let rejected = try XCTUnwrap(insights.funnel.first { $0.outcome == .rejected })
        XCTAssertEqual(rejected.stage, .round1)
        XCTAssertEqual(rejected.members.count, 1)
    }

    func testARejectionAfterRoundOneIsListedWhereItWent() throws {
        var rejected = application(appliedDaysAgo: 50)
        rejected.companyName = "Contoso"
        rejected.jobTitle = "iOS Engineer"
        rejected.recordInterviewStep(screen(40))
        rejected.recordInterviewStep(round(30))
        rejected.setStatus(rawValue: ApplicationStatus.rejected.rawValue, at: daysAgo(25))
        let insights = ApplicationInsights(applications: [rejected], now: now)

        let flow = try XCTUnwrap(insights.flows.first { $0.from == .round1 && $0.to == .outcome(.rejected) })
        XCTAssertEqual(flow.members.map(\.companyName), ["Contoso"])
        XCTAssertEqual(flow.members.map(\.jobTitle), ["iOS Engineer"])
        for stage in [FunnelStage.applied, .screen, .round1] {
            XCTAssertEqual(insights.stageMembers[stage]?.map(\.applicationID), [rejected.id], stage.label)
        }
        XCTAssertNil(insights.stageMembers[.round2])
    }

    func testMembersAreListedByCompanyThenRole() {
        let names = [("Zeta", "iOS"), ("alpha", "Platform"), ("Alpha", "Mobile"), ("Beta", "iOS")]
        let apps = names.map { company, role -> JobApplication in
            var app = application(appliedDaysAgo: 10)
            app.companyName = company
            app.jobTitle = role
            return app
        }
        let insights = ApplicationInsights(applications: apps, now: now)
        let listed = (insights.stageMembers[.applied] ?? []).map { "\($0.companyName) \($0.jobTitle)" }
        XCTAssertEqual(listed, ["Alpha Mobile", "alpha Platform", "Beta iOS", "Zeta iOS"])
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
        XCTAssertEqual(layout.target(at: CGPoint(x: centre.x, y: centre.y + 5)), .flow(thin.id))
        XCTAssertNil(layout.target(at: CGPoint(x: centre.x + 400, y: centre.y + 200)))
    }

    func testHoveringAnOutcomeLabelShowsItsFlow() throws {
        let (layout, thin) = layout()
        let node = try XCTUnwrap(layout.nodes.first { $0.flowID == thin.id })
        XCTAssertEqual(layout.target(at: CGPoint(x: node.labelPoint.x + 30, y: node.labelPoint.y)), .flow(thin.id))
    }

    func testHoveringAStageColumnOrItsLabelShowsTheStage() throws {
        let (layout, _) = layout()
        let applied = try XCTUnwrap(layout.nodes.first { $0.stage == .applied })
        XCTAssertEqual(layout.target(at: CGPoint(x: applied.rect.midX, y: applied.rect.midY)), .stage(.applied))
        XCTAssertEqual(layout.target(at: CGPoint(x: applied.labelPoint.x + 10, y: applied.labelPoint.y - 6)),
                       .stage(.applied))
    }
}
