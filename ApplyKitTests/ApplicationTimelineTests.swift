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
        application.setStatus(rawValue: ApplicationStatus.recruiterScreen.rawValue)

        XCTAssertEqual(application.statusRaw, ApplicationStatus.recruiterScreen.rawValue)
        XCTAssertEqual(application.timeline.count, 2)
        let event = try XCTUnwrap(application.timeline.first)
        XCTAssertEqual(event.kind, .statusChanged)
        XCTAssertEqual(event.fromStatusRaw, ApplicationStatus.saved.rawValue)
        XCTAssertEqual(event.toStatusRaw, ApplicationStatus.recruiterScreen.rawValue)
        XCTAssertEqual(event.transitionDetail, "from Saved")

        // Re-picking the value already selected must not litter the timeline.
        application.setStatus(rawValue: ApplicationStatus.recruiterScreen.rawValue)
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
        application.setStatus(rawValue: ApplicationStatus.technicalInterview.rawValue)
        application.recordEvent(
            ApplicationEvent(kind: .note, title: "Recruiter called", note: "Onsite next week")
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
            // Persisted as ISO-8601 with fractional seconds, so compare at that resolution.
            XCTAssertEqual(loaded.date.timeIntervalSince1970, original.date.timeIntervalSince1970, accuracy: 0.001)
        }
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
}
