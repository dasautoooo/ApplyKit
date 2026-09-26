import XCTest
@testable import ApplyKit

@MainActor
final class ApplicationTimelineTests: XCTestCase {
    func testNewApplicationStartsWithACreatedEntry() throws {
        let application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        XCTAssertEqual(application.timeline.count, 1)
        XCTAssertEqual(application.timeline.first?.kind, .created)
        XCTAssertFalse(try XCTUnwrap(application.timeline.first).isInferred)
    }

    func testSetStatusRecordsTheTransitionAndIgnoresNoOpPicks() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.setStatus(rawValue: ApplicationStatus.offer.rawValue)

        XCTAssertEqual(application.statusRaw, ApplicationStatus.offer.rawValue)
        XCTAssertEqual(application.timeline.count, 2)
        let event = try XCTUnwrap(application.timeline.first)
        XCTAssertEqual(event.kind, .statusChanged)
        XCTAssertEqual(event.fromStatusRaw, ApplicationStatus.saved.rawValue)
        XCTAssertEqual(event.toStatusRaw, ApplicationStatus.offer.rawValue)
        XCTAssertEqual(event.transitionDetail, "from Saved")

        // Re-picking the value already selected must not litter the timeline.
        application.setStatus(rawValue: ApplicationStatus.offer.rawValue)
        XCTAssertEqual(application.timeline.count, 2)
    }

    func testMovingToAppliedStampsTheAppliedDateOnlyWhenBlank() throws {
        var fresh = JobApplication(companyName: "Example", jobTitle: "Engineer")
        XCTAssertNil(fresh.dateApplied)
        fresh.setStatus(rawValue: ApplicationStatus.applied.rawValue)
        XCTAssertNotNil(fresh.dateApplied)

        let handEntered = Date(timeIntervalSince1970: 1_700_000_000)
        var existing = JobApplication(companyName: "Example", jobTitle: "Engineer")
        existing.dateApplied = handEntered
        existing.setStatus(rawValue: ApplicationStatus.applied.rawValue)
        XCTAssertEqual(existing.dateApplied, handEntered)
    }

    func testEventsStayNewestFirstAndUpdatesReorderOnlyOnDateChange() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.timeline = []
        let old = ApplicationEvent(date: Date(timeIntervalSince1970: 1_000), kind: .note, title: "Old")
        let recent = ApplicationEvent(date: Date(timeIntervalSince1970: 9_000), kind: .note, title: "Recent")
        application.recordEvent(old)
        application.recordEvent(recent)
        XCTAssertEqual(application.timeline.map(\.title), ["Recent", "Old"])

        // Editing text leaves the order alone so an open editor keeps focus.
        var edited = recent
        edited.note = "Called back"
        application.updateEvent(edited)
        XCTAssertEqual(application.timeline.map(\.title), ["Recent", "Old"])
        XCTAssertEqual(application.timeline.first?.note, "Called back")

        // Correcting the date does re-sort.
        edited.date = Date(timeIntervalSince1970: 500)
        application.updateEvent(edited)
        XCTAssertEqual(application.timeline.map(\.title), ["Old", "Recent"])

        application.removeEvent(id: old.id)
        XCTAssertEqual(application.timeline.map(\.title), ["Recent"])
    }

    func testBackfillReconstructsHistoryFromStoredDates() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.dateSaved = Date(timeIntervalSince1970: 1_000)
        application.dateApplied = Date(timeIntervalSince1970: 2_000)
        application.updatedAt = Date(timeIntervalSince1970: 3_000)
        application.statusRaw = ApplicationStatus.offer.rawValue

        let events = ApplicationTimeline.backfilled(for: application)

        XCTAssertEqual(events.map(\.kind), [.statusChanged, .statusChanged, .created])
        XCTAssertEqual(events.map(\.toStatusRaw), [ApplicationStatus.offer.rawValue, ApplicationStatus.applied.rawValue, ""])
        XCTAssertEqual(events.map(\.date), [
            Date(timeIntervalSince1970: 3_000),
            Date(timeIntervalSince1970: 2_000),
            Date(timeIntervalSince1970: 1_000)
        ])
        XCTAssertTrue(events.allSatisfy(\.isInferred))
    }

    func testBackfillDoesNotDuplicateAppliedOrInventAStatusForFreshRoles() throws {
        var applied = JobApplication(companyName: "Example", jobTitle: "Engineer")
        applied.dateApplied = Date(timeIntervalSince1970: 2_000)
        applied.statusRaw = ApplicationStatus.applied.rawValue
        let appliedEvents = ApplicationTimeline.backfilled(for: applied)
        XCTAssertEqual(appliedEvents.filter { $0.toStatusRaw == ApplicationStatus.applied.rawValue }.count, 1)

        // A never-touched application has nothing to say beyond being saved.
        let untouched = JobApplication(companyName: "Example", jobTitle: "Engineer")
        XCTAssertEqual(ApplicationTimeline.backfilled(for: untouched).map(\.kind), [.created])

        var archived = JobApplication(companyName: "Example", jobTitle: "Engineer")
        archived.dateSaved = Date(timeIntervalSince1970: 1_000)
        archived.archivedAt = Date(timeIntervalSince1970: 5_000)
        XCTAssertEqual(ApplicationTimeline.backfilled(for: archived).map(\.kind), [.archived, .created])
    }

    func testTimelineRoundTripsThroughTheWorkspaceSidecar() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.setStatus(rawValue: ApplicationStatus.interviewing.rawValue)
        application.recordEvent(
            ApplicationEvent(kind: .note, title: "Recruiter called", note: "Onsite next week")
        )
        application.recordInterviewStep(
            ApplicationEvent(kind: .interview, title: "With the iOS team",
                             interviewTypeRaw: InterviewType.systemDesign.rawValue,
                             interviewResultRaw: InterviewResult.passed.rawValue,
                             interview: InterviewDetails(
                                durationMinutes: 45, formatRaw: InterviewFormat.video.rawValue,
                                location: "https://meet.example.com/abc", interviewers: "Ana (EM)",
                                prepChecklist: [InterviewChecklistItem(text: "Review caching", isDone: true),
                                                InterviewChecklistItem(text: "Questions for Ana")],
                                prepNotes: "Scale story", questionsAsked: "Design a feed", selfRating: 4))
        )

        let dto = WorkspaceFiles.applicationDTO(from: application, documents: [], appFolder: folder)
        XCTAssertEqual(dto.paths.timeline, WorkspaceFiles.timelineFile)
        try YAMLFileStore.write(
            WorkspaceFiles.timelineDTO(from: application.timeline),
            to: folder.appendingPathComponent(WorkspaceFiles.timelineFile)
        )

        let restored = WorkspaceFiles.makeApplication(from: dto, appFolder: folder)
        XCTAssertEqual(restored.timeline.count, application.timeline.count)
        for (original, loaded) in zip(application.timeline, restored.timeline) {
            XCTAssertEqual(loaded.id, original.id)
            XCTAssertEqual(loaded.kindRaw, original.kindRaw)
            XCTAssertEqual(loaded.fromStatusRaw, original.fromStatusRaw)
            XCTAssertEqual(loaded.toStatusRaw, original.toStatusRaw)
            XCTAssertEqual(loaded.title, original.title)
            XCTAssertEqual(loaded.note, original.note)
            XCTAssertEqual(loaded.isInferred, original.isInferred)
            XCTAssertEqual(loaded.interviewTypeRaw, original.interviewTypeRaw)
            XCTAssertEqual(loaded.interviewResultRaw, original.interviewResultRaw)
            XCTAssertEqual(loaded.interview, original.interview)
            // Persisted as ISO-8601 with fractional seconds, so compare at that resolution.
            XCTAssertEqual(loaded.date.timeIntervalSince1970, original.date.timeIntervalSince1970, accuracy: 0.001)
        }
    }

    /// A build that appended an adopted entry the target already held wrote the
    /// same id twice. Loading repairs those files rather than showing the entry
    /// twice forever.
    func testDuplicateEntriesInASidecarAreCollapsedOnLoad() throws {
        let sharedID = UUID()
        let dto = ApplicationTimelineDTO(events: [
            ApplicationEventDTO(id: sharedID.uuidString, date: "2026-08-08T04:13:54.330Z", kind: "Created",
                                fromStatus: nil, toStatus: nil, title: nil, note: nil, inferred: nil),
            ApplicationEventDTO(id: sharedID.uuidString, date: "2026-08-08T04:13:54.330Z", kind: "Created",
                                fromStatus: nil, toStatus: nil, title: nil, note: nil, inferred: nil)
        ])
        let restored = WorkspaceFiles.makeTimeline(from: dto)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, sharedID)
    }

    func testLegacyApplicationWithoutASidecarLoadsAnInferredTimeline() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.dateSaved = Date(timeIntervalSince1970: 1_000)
        application.dateApplied = Date(timeIntervalSince1970: 2_000)
        application.updatedAt = Date(timeIntervalSince1970: 3_000)
        application.statusRaw = ApplicationStatus.rejected.rawValue

        var dto = WorkspaceFiles.applicationDTO(from: application, documents: [], appFolder: folder)
        dto.paths.timeline = nil    // as written by every build that predates timelines

        // No timeline.yml on disk, so the loader must reconstruct rather than come back empty.
        let restored = WorkspaceFiles.makeApplication(from: dto, appFolder: folder)
        XCTAssertEqual(restored.timeline.map(\.kind), [.statusChanged, .statusChanged, .created])
        XCTAssertTrue(restored.timeline.allSatisfy(\.isInferred))
        XCTAssertEqual(restored.timeline.first?.toStatusRaw, ApplicationStatus.rejected.rawValue)
        XCTAssertEqual(restored.lastTimelineChange, Date(timeIntervalSince1970: 3_000))
    }

    /// Dates persist at millisecond resolution, so entries recorded in quick succession can
    /// tie. Reloading must not reshuffle them.
    func testEntriesSharingATimestampKeepTheirOrderOnLoad() throws {
        let sameInstant = Date(timeIntervalSince1970: 4_000)
        let events = [
            ApplicationEvent(date: sameInstant, kind: .note, title: "Third"),
            ApplicationEvent(date: sameInstant, kind: .note, title: "Second"),
            ApplicationEvent(date: sameInstant, kind: .note, title: "First")
        ]
        let restored = WorkspaceFiles.makeTimeline(from: WorkspaceFiles.timelineDTO(from: events))
        XCTAssertEqual(restored.map(\.title), ["Third", "Second", "First"])
    }

    func testEmptyTimelineOmitsTheSidecarPath() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.timeline = []
        let dto = WorkspaceFiles.applicationDTO(from: application, documents: [], appFolder: folder)
        XCTAssertNil(dto.paths.timeline)
        XCTAssertNil(application.lastTimelineChange)
    }

    // MARK: - Interview rounds

    func testLegacyInterviewStatusesLoadAsInterviewing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        var dto = WorkspaceFiles.applicationDTO(from: application, documents: [], appFolder: folder)
        dto.status = ApplicationStatus.recruiterScreen.rawValue
        XCTAssertEqual(WorkspaceFiles.makeApplication(from: dto, appFolder: folder).statusRaw,
                       ApplicationStatus.recruiterScreen.rawValue)

        for legacy in ApplicationStatus.legacyRoundRawValues {
            dto.status = legacy
            dto.paths.timeline = nil
            let restored = WorkspaceFiles.makeApplication(from: dto, appFolder: folder)
            XCTAssertEqual(restored.statusRaw, ApplicationStatus.interviewing.rawValue)
            // The inferred history says what the status actually was.
            XCTAssertEqual(restored.timeline.first { $0.isStatusChange }?.toStatusRaw, legacy)
        }

        let timeline = WorkspaceFiles.makeTimeline(from: ApplicationTimelineDTO(events: [
            ApplicationEventDTO(id: UUID().uuidString, date: "2026-08-08T04:13:54.330Z", kind: "Status Changed",
                                fromStatus: "Technical Interview", toStatus: "Final Interview",
                                title: nil, note: nil, inferred: nil)
        ]))
        // History is kept verbatim.
        XCTAssertEqual(timeline.first?.fromStatusRaw, "Technical Interview")
        XCTAssertEqual(timeline.first?.toStatusRaw, "Final Interview")
    }

    func testSidecarEntriesWithoutInterviewKeysStillDecode() throws {
        let yaml = """
        events:
        - id: \(UUID().uuidString)
          date: "2026-08-08T04:13:54.330Z"
          kind: Note
          title: Called
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let events = WorkspaceFiles.makeTimeline(from: try YAMLFileStore.read(ApplicationTimelineDTO.self, from: url))
        XCTAssertEqual(events.first?.interviewTypeRaw, "")
        XCTAssertEqual(events.first?.interviewResultRaw, "")
        // Written back without the keys, so an untouched file doesn't change shape.
        XCTAssertNil(WorkspaceFiles.timelineDTO(from: events).events.first?.interviewType)
    }

    func testRecordingARoundAdvancesAnEarlierStatusToInterviewing() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.setStatus(rawValue: ApplicationStatus.applied.rawValue)
        application.recordInterviewStep(ApplicationEvent(kind: .interview))

        XCTAssertEqual(application.statusRaw, ApplicationStatus.interviewing.rawValue)
        // The step is the record of the move to Interviewing; only the move to Applied is logged.
        XCTAssertEqual(application.timeline.map(\.kind), [.interview, .statusChanged, .created])
        XCTAssertEqual(application.timeline[1].toStatusRaw, ApplicationStatus.applied.rawValue)
    }

    func testARecruiterScreenStepAdvancesToRecruiterScreenAndIsNotARound() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer", status: .applied)
        let screen = ApplicationEvent(date: Date(timeIntervalSince1970: 1_000), kind: .interview,
                                      interviewTypeRaw: InterviewType.recruiterScreen.rawValue)
        application.recordInterviewStep(screen)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.recruiterScreen.rawValue)
        XCTAssertNil(application.roundNumber(of: screen.id))
        XCTAssertNil(application.currentRound)
        XCTAssertEqual(application.stepTitle(for: screen), "Recruiter Screen")

        let round = ApplicationEvent(date: Date(timeIntervalSince1970: 2_000), kind: .interview,
                                     interviewTypeRaw: InterviewType.coding.rawValue)
        application.recordInterviewStep(round)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.interviewing.rawValue)
        XCTAssertTrue(application.timeline.filter(\.isStatusChange).isEmpty)   // the steps are the record
        XCTAssertEqual(application.stepTitle(for: round), "Round 1 · Coding")
        XCTAssertEqual(application.interviewSteps.map(\.id), [screen.id, round.id])
    }

    func testAScreenLoggedMidProcessDoesNotMoveTheStatusBack() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer", status: .interviewing)
        application.recordInterviewStep(ApplicationEvent(kind: .interview, interviewTypeRaw: InterviewType.recruiterScreen.rawValue))
        XCTAssertEqual(application.statusRaw, ApplicationStatus.interviewing.rawValue)
    }

    // MARK: - Status and steps in step

    private func screenStep(_ seconds: TimeInterval) -> ApplicationEvent {
        ApplicationEvent(date: Date(timeIntervalSince1970: seconds), kind: .interview,
                         interviewTypeRaw: InterviewType.recruiterScreen.rawValue)
    }

    private func roundStep(_ seconds: TimeInterval) -> ApplicationEvent {
        ApplicationEvent(date: Date(timeIntervalSince1970: seconds), kind: .interview,
                         interviewTypeRaw: InterviewType.coding.rawValue)
    }

    func testPickingAnInterviewStatusAddsTheMissingStep() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer", status: .applied)
        let screen = try XCTUnwrap(application.pickStatus(rawValue: ApplicationStatus.recruiterScreen.rawValue))
        XCTAssertTrue(screen.isRecruiterScreenStep)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.recruiterScreen.rawValue)

        let round = try XCTUnwrap(application.pickStatus(rawValue: ApplicationStatus.interviewing.rawValue))
        XCTAssertEqual(application.roundNumber(of: round.id), 1)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.interviewing.rawValue)

        // Steps already back each status now, so re-picking adds nothing.
        XCTAssertNil(application.pickStatus(rawValue: ApplicationStatus.recruiterScreen.rawValue))
        XCTAssertNil(application.pickStatus(rawValue: ApplicationStatus.interviewing.rawValue))
        XCTAssertEqual(application.interviewSteps.count, 2)
        // A pick is a pick: the status stays where it was put.
        XCTAssertEqual(application.statusRaw, ApplicationStatus.interviewing.rawValue)
    }

    func testNewStepsStartAsSchedulingUntilATimeIsSet() {
        let now = Date(timeIntervalSince1970: 5_000)
        var step = ApplicationEvent.newInterviewStep(.recruiterScreen, now: now)
        XCTAssertEqual(step.interviewResult, .scheduling)
        XCTAssertFalse(step.hasScheduledTime)
        XCTAssertEqual(step.date, now)   // when they reached out

        let agreed = Date(timeIntervalSince1970: 90_000)
        step.schedule(at: agreed)
        XCTAssertEqual(step.interviewResult, .scheduled)
        XCTAssertEqual(step.date, agreed)

        // Rescheduling a step that already has a result leaves the result alone.
        step.interviewResult = .awaiting
        step.schedule(at: Date(timeIntervalSince1970: 95_000))
        XCTAssertEqual(step.interviewResult, .awaiting)
    }

    func testAStepStillBeingArrangedComesAfterBookedOnes() {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer", status: .applied)
        var booked = ApplicationEvent.newInterviewStep(.coding, now: Date(timeIntervalSince1970: 1_000))
        booked.schedule(at: Date(timeIntervalSince1970: 9_000))   // on the calendar, later than...
        application.recordInterviewStep(booked)
        let arranging = ApplicationEvent.newInterviewStep(.systemDesign, now: Date(timeIntervalSince1970: 5_000))
        application.recordInterviewStep(arranging)                  // ...when this one was logged

        XCTAssertEqual(application.roundNumber(of: booked.id), 1)
        XCTAssertEqual(application.roundNumber(of: arranging.id), 2)
    }

    func testTheTimelineShowsStepsInsteadOfTheStatusChangesTheyMade() {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.pickStatus(rawValue: ApplicationStatus.recruiterScreen.rawValue)
        application.recordInterviewStep(.newInterviewStep(.coding))
        application.setStatus(rawValue: ApplicationStatus.rejected.rawValue)

        // Stored: created, screen step, round, → Rejected. Phase moves aren't recorded.
        XCTAssertEqual(application.timeline.filter(\.isStatusChange).count, 1)
        // Shown: the steps carry the interview phase; only the rejection stays as a status row.
        let shown = application.displayedTimeline
        XCTAssertEqual(shown.filter(\.isStatusChange).map(\.toStatusRaw), [ApplicationStatus.rejected.rawValue])
        XCTAssertEqual(shown.filter(\.isInterview).count, 2)

        // An older build recorded phase moves. With steps those rows are hidden; without, the
        // status change is the only record, so it shows.
        var legacy = JobApplication(companyName: "Example", jobTitle: "Engineer")
        legacy.recordEvent(ApplicationEvent(kind: .statusChanged, fromStatusRaw: "Saved",
                                            toStatusRaw: ApplicationStatus.recruiterScreen.rawValue))
        XCTAssertEqual(legacy.displayedTimeline.filter(\.isStatusChange).count, 1)
        legacy.recordInterviewStep(.newInterviewStep(.recruiterScreen))
        XCTAssertEqual(legacy.displayedTimeline.filter(\.isStatusChange).count, 0)
    }

    func testPickingANonInterviewStatusAddsNoStep() {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer", status: .applied)
        XCTAssertNil(application.pickStatus(rawValue: ApplicationStatus.rejected.rawValue))
        XCTAssertTrue(application.interviewSteps.isEmpty)
    }

    func testDeletingTheOnlyRoundMovesTheStatusBackToRecruiterScreen() {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer", status: .applied)
        application.recordInterviewStep(screenStep(1_000))
        let round = roundStep(2_000)
        application.recordInterviewStep(round)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.interviewing.rawValue)

        application.removeEvent(id: round.id)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.recruiterScreen.rawValue)
    }

    func testDeletingEveryStepUndoesTheInterviewPhase() {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.setStatus(rawValue: ApplicationStatus.applied.rawValue)
        let screen = try! XCTUnwrap(application.pickStatus(rawValue: ApplicationStatus.recruiterScreen.rawValue))
        let round = roundStep(2_000)
        application.recordInterviewStep(round)

        application.removeEvent(id: round.id)
        application.removeEvent(id: screen.id)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.applied.rawValue)
        // Nothing is left behind to say otherwise.
        XCTAssertEqual(application.displayedTimeline.filter(\.isStatusChange).map(\.toStatusRaw),
                       [ApplicationStatus.applied.rawValue])
    }

    func testDeletingEveryStepKeepsARecordedLegacyPhase() {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.recordEvent(ApplicationEvent(kind: .statusChanged, fromStatusRaw: "Applied",
                                                 toStatusRaw: ApplicationStatus.interviewing.rawValue))
        application.statusRaw = ApplicationStatus.interviewing.rawValue
        let round = roundStep(2_000)
        application.recordInterviewStep(round)
        application.removeEvent(id: round.id)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.interviewing.rawValue)
    }

    func testChangingAStepsTypeKeepsTheStatusInStep() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer", status: .applied)
        var step = roundStep(1_000)
        application.recordInterviewStep(step)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.interviewing.rawValue)

        step.interviewTypeRaw = InterviewType.recruiterScreen.rawValue
        application.updateEvent(step)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.recruiterScreen.rawValue)

        step.interviewTypeRaw = InterviewType.systemDesign.rawValue
        application.updateEvent(step)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.interviewing.rawValue)
    }

    func testStepChangesNeverTouchAClosedOutStatus() {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer", status: .applied)
        application.recordInterviewStep(screenStep(1_000))
        let round = roundStep(2_000)
        application.recordInterviewStep(round)
        application.setStatus(rawValue: ApplicationStatus.rejected.rawValue)

        application.removeEvent(id: round.id)
        XCTAssertEqual(application.statusRaw, ApplicationStatus.rejected.rawValue)
    }

    func testEmptyInterviewDetailsAreNotWritten() throws {
        let dto = WorkspaceFiles.timelineDTO(from: [ApplicationEvent(kind: .interview)])
        XCTAssertNil(dto.events.first?.interview)
    }

    func testRecordingARoundLeavesAClosedOutStatusAlone() throws {
        for closed in [ApplicationStatus.offer, .rejected, .ghosted, .withdrawn] {
            var application = JobApplication(companyName: "Example", jobTitle: "Engineer", status: closed)
            application.recordInterviewStep(ApplicationEvent(kind: .interview))
            XCTAssertEqual(application.statusRaw, closed.rawValue)
            XCTAssertEqual(application.timeline.filter(\.isStatusChange).count, 0)
        }
    }

    func testRoundsAreNumberedByDate() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer", status: .interviewing)
        let later = ApplicationEvent(date: Date(timeIntervalSince1970: 3_000), kind: .interview)
        let earlier = ApplicationEvent(date: Date(timeIntervalSince1970: 2_000), kind: .interview)
        application.recordInterviewStep(later)
        application.recordInterviewStep(earlier)

        XCTAssertEqual(application.roundNumber(of: earlier.id), 1)
        XCTAssertEqual(application.roundNumber(of: later.id), 2)
        XCTAssertEqual(application.currentRound, 2)

        // Moving the later round before the other swaps their numbers.
        var moved = later
        moved.date = Date(timeIntervalSince1970: 1_000)
        application.updateEvent(moved)
        XCTAssertEqual(application.roundNumber(of: later.id), 1)
        XCTAssertEqual(application.roundNumber(of: earlier.id), 2)
    }
}
