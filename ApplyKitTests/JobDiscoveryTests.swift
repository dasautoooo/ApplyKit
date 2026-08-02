import XCTest
@testable import ApplyKit

@MainActor
final class JobDiscoveryTests: XCTestCase {

    // MARK: - Board detection

    func testBoardDetectionForAllProvidersFromRootAndDetailURLs() throws {
        func board(_ string: String) throws -> TrackedBoard {
            try XCTUnwrap(JobBoardProviders.detect(url: XCTUnwrap(URL(string: string))))
        }

        let ghRoot = try board("https://boards.greenhouse.io/acme")
        XCTAssertEqual(ghRoot.kindRaw, "greenhouse")
        XCTAssertEqual(ghRoot.slug, "acme")

        let ghDetail = try board("https://boards.greenhouse.io/acme/jobs/12345")
        XCTAssertEqual(ghDetail.kindRaw, "greenhouse")
        XCTAssertEqual(ghDetail.slug, "acme")

        let lever = try board("https://jobs.lever.co/acme")
        XCTAssertEqual(lever.kindRaw, "lever")
        XCTAssertEqual(lever.slug, "acme")
        XCTAssertEqual(lever.host, "jobs.lever.co")

        let ashby = try board("https://jobs.ashbyhq.com/acme/some-id")
        XCTAssertEqual(ashby.kindRaw, "ashby")
        XCTAssertEqual(ashby.slug, "acme")

        let workday = try board("https://acme.wd5.myworkdayjobs.com/en-US/Careers")
        XCTAssertEqual(workday.kindRaw, "workday")
        XCTAssertEqual(workday.slug, "acme")
        XCTAssertEqual(workday.site, "Careers")
        XCTAssertEqual(workday.host, "acme.wd5.myworkdayjobs.com")

        XCTAssertNil(JobBoardProviders.detect(url: try XCTUnwrap(URL(string: "https://example.com/careers"))))
    }

    // MARK: - List JSON mapping

    func testGreenhouseListMapping() {
        let json: [String: Any] = ["jobs": [
            ["id": 123, "title": "Senior iOS Engineer",
             "absolute_url": "https://boards.greenhouse.io/acme/jobs/123",
             "location": ["name": "Remote"], "updated_at": "2026-01-02T10:00:00Z"]
        ]]
        let postings = GreenhouseProvider.parse(json)
        XCTAssertEqual(postings.count, 1)
        XCTAssertEqual(postings.first?.externalID, "123")
        XCTAssertEqual(postings.first?.title, "Senior iOS Engineer")
        XCTAssertEqual(postings.first?.location, "Remote")
        XCTAssertNotNil(postings.first?.postedAt)
    }

    func testLeverListMapping() {
        let json: [[String: Any]] = [
            ["id": "abc", "text": "Backend Engineer", "hostedUrl": "https://jobs.lever.co/acme/abc",
             "categories": ["location": "New York"], "createdAt": 1_700_000_000_000]
        ]
        let postings = LeverProvider.parse(json)
        XCTAssertEqual(postings.count, 1)
        XCTAssertEqual(postings.first?.externalID, "abc")
        XCTAssertEqual(postings.first?.title, "Backend Engineer")
        XCTAssertEqual(postings.first?.location, "New York")
        XCTAssertNotNil(postings.first?.postedAt)
    }

    func testAshbyListMapping() {
        let json: [String: Any] = ["jobs": [
            ["id": "xyz", "title": "ML Engineer", "jobUrl": "https://jobs.ashbyhq.com/acme/xyz",
             "location": "San Francisco", "publishedAt": "2026-01-01T00:00:00Z"]
        ]]
        let postings = AshbyProvider.parse(json)
        XCTAssertEqual(postings.count, 1)
        XCTAssertEqual(postings.first?.externalID, "xyz")
        XCTAssertEqual(postings.first?.title, "ML Engineer")
        XCTAssertEqual(postings.first?.location, "San Francisco")
    }

    func testWorkdayListMappingAndURLRoundTrip() throws {
        let host = "acme.wd5.myworkdayjobs.com"
        let site = "Careers"
        let json: [String: Any] = ["total": 1, "jobPostings": [
            ["title": "Platform Engineer", "externalPath": "/job/Toronto/Engineer_R123",
             "locationsText": "Toronto", "bulletFields": ["R123"], "postedOn": "Posted 5 Days Ago"]
        ]]
        let postings = WorkdayProvider.parse(json, host: host, site: site)
        XCTAssertEqual(postings.count, 1)
        let posting = try XCTUnwrap(postings.first)
        XCTAssertEqual(posting.externalID, "R123")
        XCTAssertEqual(posting.url, "https://acme.wd5.myworkdayjobs.com/Careers/job/Toronto/Engineer_R123")
        XCTAssertNotNil(posting.postedAt, "Workday relative post text should resolve to a date")
        XCTAssertLessThan(try XCTUnwrap(posting.postedAt), Date())

        // The reconstructed public URL must resolve back to the Workday detail API.
        let request = try XCTUnwrap(ATSJobAPIResolver.request(for: XCTUnwrap(URL(string: posting.url))))
        XCTAssertEqual(request.kind, .workday)
        XCTAssertEqual(
            request.apiURL.absoluteString,
            "https://acme.wd5.myworkdayjobs.com/wday/cxs/acme/Careers/job/Toronto/Engineer_R123"
        )
    }

    func testWorkdayPostedDateParsing() {
        let now = Date()
        let cal = Calendar.current
        XCTAssertEqual(WorkdayProvider.postedDate("Posted Today", now: now), now)
        XCTAssertEqual(WorkdayProvider.postedDate("Posted Yesterday", now: now),
                       cal.date(byAdding: .day, value: -1, to: now))
        XCTAssertEqual(WorkdayProvider.postedDate("Posted 5 Days Ago", now: now),
                       cal.date(byAdding: .day, value: -5, to: now))
        XCTAssertEqual(WorkdayProvider.postedDate("Posted 30+ Days Ago", now: now),
                       cal.date(byAdding: .day, value: -30, to: now))
        XCTAssertNil(WorkdayProvider.postedDate("Posted Recently", now: now))
        XCTAssertNil(WorkdayProvider.postedDate(nil, now: now))
    }

    // MARK: - Workday cap / facet subdivision

    func testWorkdayFacetSelectionPrefersPriorityOrderAndSkipsApplied() {
        let facets: [[String: Any]] = [
            ["facetParameter": "workerSubType",
             "values": [["id": "a", "count": 10], ["id": "b", "count": 5]]],
            ["facetParameter": "jobFamilyGroup",
             "values": [["id": "eng", "count": 900], ["id": "sales", "count": 400]]],
            ["facetParameter": "timeType",
             "values": [["id": "ft", "count": 800], ["id": "pt", "count": 100]]]
        ]
        // jobFamilyGroup outranks timeType and workerSubType.
        let first = WorkdayProvider.pickFacet(facets, alreadyApplied: [])
        XCTAssertEqual(first?.parameter, "jobFamilyGroup")
        XCTAssertEqual(first?.values, ["eng", "sales"])

        // Once applied it must not be reused — that would just re-hit the cap.
        let second = WorkdayProvider.pickFacet(facets, alreadyApplied: ["jobFamilyGroup"])
        XCTAssertEqual(second?.parameter, "timeType")

        // Single-value and zero-count facets are not useful partitions.
        let degenerate: [[String: Any]] = [
            ["facetParameter": "onlyOne", "values": [["id": "x", "count": 3]]],
            ["facetParameter": "allZero", "values": [["id": "y", "count": 0], ["id": "z", "count": 0]]]
        ]
        XCTAssertNil(WorkdayProvider.pickFacet(degenerate, alreadyApplied: []))
    }

    func testWorkdayRollupLocationDetectionAndFormatting() {
        XCTAssertTrue(WorkdayProvider.isRollupLocation("3 Locations"))
        XCTAssertTrue(WorkdayProvider.isRollupLocation("11 locations"))
        XCTAssertFalse(WorkdayProvider.isRollupLocation("Toronto, ON"))
        XCTAssertFalse(WorkdayProvider.isRollupLocation(""))

        XCTAssertEqual(
            WorkdayProvider.formatLocations(primary: "Toronto", additional: ["Vancouver", "Montreal"]),
            "Toronto | Vancouver | Montreal")
        XCTAssertEqual(WorkdayProvider.formatLocations(primary: "Toronto", additional: nil), "Toronto")
        XCTAssertEqual(WorkdayProvider.formatLocations(primary: nil, additional: nil), "")
    }

    func testWorkdayExternalPathExtraction() {
        XCTAssertEqual(
            WorkdayProvider.externalPath(from: "https://acme.wd5.myworkdayjobs.com/Careers/job/Toronto/Engineer_R1"),
            "/job/Toronto/Engineer_R1")
        XCTAssertNil(WorkdayProvider.externalPath(from: "https://acme.wd5.myworkdayjobs.com/Careers"))
    }

    func testWorkdayCollectsNestedLocationFacets() {
        // Real NVIDIA shape: location facets sit one level deep inside
        // `locationMainGroup`, whose own values are facet groups, not values.
        let facets: [[String: Any]] = [
            ["facetParameter": "jobFamilyGroup",
             "values": [["id": "eng", "descriptor": "Engineering", "count": 900]]],
            ["facetParameter": "locationMainGroup", "values": [
                ["facetParameter": "locationHierarchy2", "descriptor": "Location Type", "values": [
                    ["id": "office-id", "descriptor": "Office", "count": 2496],
                    ["id": "remote-id", "descriptor": "Remote", "count": 545]
                ]],
                ["facetParameter": "locationHierarchy1", "descriptor": "Locations", "values": [
                    ["id": "canada-id", "descriptor": "Canada", "count": 15],
                    ["id": "us-id", "descriptor": "United States", "count": 1426]
                ]],
                ["facetParameter": "locations", "descriptor": "Sites", "values": [
                    ["id": "tor-id", "descriptor": "Canada, Toronto", "count": 8]
                ]]
            ]]
        ]
        let collected = WorkdayProvider.collectLocationFacets(facets)
        let descriptors = Set(collected.map(\.descriptor))
        XCTAssertTrue(descriptors.contains("Canada"))
        XCTAssertTrue(descriptors.contains("Canada, Toronto"))
        // Non-location facets must not leak in.
        XCTAssertFalse(descriptors.contains("Engineering"))
        XCTAssertEqual(collected.first { $0.descriptor == "Canada, Toronto" }?.parameter, "locations")
    }

    func testWorkdayVerifiedLocationBypassesClientFilter() {
        // Once Workday has filtered by location server-side, a multi-office role
        // reported as "4 Locations" must survive the client-side filter.
        let board = TrackedBoard(kindRaw: "workday", slug: "nvidia", host: "nvidia.wd5.myworkdayjobs.com",
                                 site: "Careers", locationKeywords: ["toronto"])
        let verified = DiscoveredPosting(externalID: "1", title: "Engineer", location: "4 Locations",
                                         url: "https://x/job/1", postedAt: nil,
                                         descriptionText: "", locationVerified: true)
        let unverifiedMiss = DiscoveredPosting(externalID: "2", title: "Engineer", location: "Austin, Texas",
                                               url: "https://x/job/2", postedAt: nil)
        XCTAssertTrue(JobDiscoveryService.passesFilters(verified, board: board))
        XCTAssertFalse(JobDiscoveryService.passesFilters(unverifiedMiss, board: board))
    }

    // MARK: - Closed (delisted) detection

    func testClosedDetectionOnlyAppliesToSuccessfullyPolledBoards() {
        let boardA = UUID()
        let boardB = UUID()
        func job(_ key: String, board: UUID, state: DiscoveryState = .new) -> DiscoveredJob {
            DiscoveredJob(boardID: board, externalID: key, dedupeKey: key, title: "Engineer",
                          companyName: "Acme", location: "Remote", url: key, state: state)
        }
        let jobs = [
            job("a1", board: boardA),               // still listed  → stays
            job("a2", board: boardA),               // gone          → closed
            job("b1", board: boardB),               // board errored → untouched
            job("a3", board: boardA, state: .imported),  // not `new` → untouched
            job("a4", board: boardA, state: .dismissed)  // not `new` → untouched
        ]
        // Only board A reported a live listing; board B errored or came back empty.
        let live: [UUID: Set<String>] = [boardA: ["a1"]]

        let closed = JobDiscoveryService.closedJobIDs(in: jobs, liveKeysByBoard: live)
        XCTAssertEqual(closed, [jobs[1].id],
                       "Only the missing `new` posting on the polled board should close")
    }

    func testClosedDetectionIsANoOpWhenEveryBoardFailed() {
        let board = UUID()
        let jobs = [
            DiscoveredJob(boardID: board, externalID: "1", dedupeKey: "k1", title: "Engineer",
                          companyName: "Acme", location: "", url: "k1")
        ]
        // An outage yields no live keys at all — nothing may be closed, or one
        // bad refresh would wipe the inbox.
        XCTAssertTrue(JobDiscoveryService.closedJobIDs(in: jobs, liveKeysByBoard: [:]).isEmpty)
    }

    // MARK: - New provider URL detection & mapping

    func testNewProviderURLDetection() throws {
        func detect(_ string: String) throws -> TrackedBoard {
            try XCTUnwrap(JobBoardProviders.detect(url: XCTUnwrap(URL(string: string))))
        }
        XCTAssertEqual(try detect("https://jobs.smartrecruiters.com/Visa/744000133907678").kindRaw, "smartrecruiters")
        XCTAssertEqual(try detect("https://apply.workable.com/acme/").kindRaw, "workable")
        XCTAssertEqual(try detect("https://acme.recruitee.com/").kindRaw, "recruitee")
        XCTAssertEqual(try detect("https://acme.jobs.personio.com/").kindRaw, "personio")
        XCTAssertEqual(try detect("https://acme.bamboohr.com/careers").kindRaw, "bamboohr")
        XCTAssertEqual(try detect("https://acme.breezy.hr/").kindRaw, "breezy")
        XCTAssertEqual(try detect("https://acme.applytojob.com/apply/jobs").kindRaw, "jazzhr")
        XCTAssertEqual(try detect("https://acme.teamtailor.com/jobs").kindRaw, "teamtailor")

        // Big-tech career sites resolve to their bespoke providers.
        XCTAssertEqual(try detect("https://www.amazon.jobs/en/search").kindRaw, "amazon")
        XCTAssertEqual(try detect("https://jobs.apple.com/en-us/search").kindRaw, "apple")
        XCTAssertEqual(try detect("https://www.uber.com/us/en/careers/list/").kindRaw, "uber")
        XCTAssertEqual(try detect("https://lifeattiktok.com/search").kindRaw, "tiktok")
        XCTAssertEqual(try detect("https://jobs.bytedance.com/en/position").kindRaw, "bytedance")
        XCTAssertEqual(try detect("https://www.google.com/about/careers/applications/jobs/results").kindRaw, "google")
        XCTAssertEqual(try detect("https://www.tesla.com/careers/search/").kindRaw, "tesla")
        XCTAssertEqual(try detect("https://www.metacareers.com/jobs").kindRaw, "meta")
    }

    func testSmartRecruitersMapping() {
        let json: [String: Any] = ["totalFound": 1, "content": [
            ["id": "744000133907678", "name": "Sr. Manager",
             "releasedDate": "2026-06-24T10:00:11.853Z",
             "location": ["city": "Austin", "region": "TX", "fullLocation": "Austin, TX, United States"]]
        ]]
        let postings = SmartRecruitersProvider.parse(json, slug: "Visa")
        XCTAssertEqual(postings.count, 1)
        XCTAssertEqual(postings.first?.title, "Sr. Manager")
        XCTAssertEqual(postings.first?.location, "Austin, TX, United States")
        XCTAssertEqual(postings.first?.url, "https://jobs.smartrecruiters.com/Visa/744000133907678")
        XCTAssertNotNil(postings.first?.postedAt)
    }

    func testAmazonAndAppleMapping() {
        let amazon: [String: Any] = ["jobs": [
            ["id_icims": "2900", "title": "SDE II", "job_path": "/en/jobs/2900/sde-ii",
             "normalized_location": "Toronto, ON, CAN"]
        ]]
        let amazonPostings = AmazonProvider.parse(amazon)
        XCTAssertEqual(amazonPostings.first?.externalID, "2900")
        XCTAssertEqual(amazonPostings.first?.url, "https://www.amazon.jobs/en/jobs/2900/sde-ii")

        let apple: [String: Any] = ["res": ["searchResults": [
            ["positionId": "200313970", "postingTitle": "Software Engineer",
             "locations": [["name": "Toronto"], ["name": "Vancouver"]]]
        ]]]
        let applePostings = AppleProvider.parse(apple)
        XCTAssertEqual(applePostings.first?.externalID, "200313970")
        XCTAssertEqual(applePostings.first?.location, "Toronto | Vancouver")
        XCTAssertEqual(applePostings.first?.url, "https://jobs.apple.com/en-us/details/200313970")
    }

    func testTikTokFamilyMappingCarriesDescription() {
        let json: [String: Any] = ["data": ["job_post_list": [
            ["id": "766790", "title": "Backend Engineer",
             "city_info": ["en_name": "Singapore"],
             "description": "Build systems.", "requirement": "5 years experience."]
        ]]]
        let postings = ATSxCareers.parse(json, jobURLPrefix: "https://lifeattiktok.com/search/")
        XCTAssertEqual(postings.first?.externalID, "766790")
        XCTAssertEqual(postings.first?.location, "Singapore")
        XCTAssertTrue(postings.first?.descriptionText.contains("Build systems.") ?? false)
        XCTAssertTrue(postings.first?.descriptionText.contains("5 years experience.") ?? false)
    }

    func testGoogleHTMLParsingUsesAriaLabelContract() {
        let html = """
        <div>
          <a href="/about/careers/applications/jobs/results/12345-software-engineer"
             aria-label="Learn more about Software Engineer, Infrastructure">x</a>
          <a href="/about/careers/applications/jobs/results/67890-data-scientist"
             aria-label="Learn more about Data Scientist">y</a>
          <a href="/about/careers/other" aria-label="Unrelated link">z</a>
        </div>
        """
        let postings = GoogleProvider.parse(html: html)
        XCTAssertEqual(postings.count, 2)
        XCTAssertEqual(postings.first?.title, "Software Engineer, Infrastructure")
        XCTAssertTrue(postings.first?.url.hasPrefix("https://www.google.com/") ?? false)
    }

    func testTeamtailorRSSParsing() {
        let rss = """
        <rss><channel>
          <item><title><![CDATA[Senior Engineer]]></title>
                <link>https://acme.teamtailor.com/jobs/123-senior-engineer</link>
                <location>Toronto</location></item>
          <item><title>Designer</title>
                <link>https://acme.teamtailor.com/jobs/456-designer</link></item>
        </channel></rss>
        """
        let postings = TeamtailorProvider.parse(rss: rss)
        XCTAssertEqual(postings.count, 2)
        XCTAssertEqual(postings.first?.title, "Senior Engineer")
        XCTAssertEqual(postings.first?.location, "Toronto")
    }

    func testDescriptionFromProviderSeedsDiscoveredJob() {
        let board = TrackedBoard(kindRaw: "tiktok", slug: "tiktok", companyName: "TikTok")
        let postings = [
            DiscoveredPosting(externalID: "1", title: "Engineer", location: "Remote",
                              url: "https://lifeattiktok.com/search/1", postedAt: nil,
                              descriptionText: "Full description here.")
        ]
        var seen = Set<String>()
        let jobs = JobDiscoveryService.filterAndDedupe(postings: postings, board: board, seenKeys: &seen)
        XCTAssertEqual(jobs.first?.jobDescription, "Full description here.")
        XCTAssertNotNil(jobs.first?.jobDescriptionFetchedAt)
    }

    // MARK: - Filtering & dedup

    func testFilterAndDedupeAppliesKeywordsAndDeduplicates() {
        let board = TrackedBoard(kindRaw: "greenhouse", slug: "acme", companyName: "Acme",
                                 titleKeywords: ["engineer"], excludeKeywords: ["senior"],
                                 locationKeywords: ["remote"])
        let postings = [
            DiscoveredPosting(externalID: "1", title: "Senior Engineer", location: "Remote",
                              url: "https://boards.greenhouse.io/acme/jobs/1", postedAt: nil),  // excluded (senior)
            DiscoveredPosting(externalID: "2", title: "Backend Engineer", location: "Remote - US",
                              url: "https://boards.greenhouse.io/acme/jobs/2", postedAt: nil),  // kept
            DiscoveredPosting(externalID: "3", title: "Product Designer", location: "Remote",
                              url: "https://boards.greenhouse.io/acme/jobs/3", postedAt: nil),  // not "engineer"
            DiscoveredPosting(externalID: "4", title: "Backend Engineer", location: "New York",
                              url: "https://boards.greenhouse.io/acme/jobs/4", postedAt: nil)   // location miss
        ]
        var seen = Set<String>()
        let kept = JobDiscoveryService.filterAndDedupe(postings: postings, board: board, seenKeys: &seen)
        XCTAssertEqual(kept.map(\.externalID), ["2"])

        // Running again with the key already seen yields nothing.
        let again = JobDiscoveryService.filterAndDedupe(postings: postings, board: board, seenKeys: &seen)
        XCTAssertTrue(again.isEmpty)
    }

    func testFilterDropsCatchAllTalentPoolPostings() {
        XCTAssertTrue(JobDiscoveryService.isCatchAllPosting(title: "Don't see what you're looking for?"))
        XCTAssertTrue(JobDiscoveryService.isCatchAllPosting(title: "Interested in an internship?"))
        XCTAssertTrue(JobDiscoveryService.isCatchAllPosting(title: "General Application"))
        XCTAssertTrue(JobDiscoveryService.isCatchAllPosting(title: "Join Our Talent Community"))
        XCTAssertFalse(JobDiscoveryService.isCatchAllPosting(title: "Software Engineer"))
        XCTAssertFalse(JobDiscoveryService.isCatchAllPosting(title: "Manager, Computational Biology"))

        let board = TrackedBoard(kindRaw: "greenhouse", slug: "acme")
        let postings = [
            DiscoveredPosting(externalID: "1", title: "Don't see what you're looking for?", location: "Salt Lake City, Utah",
                              url: "https://boards.greenhouse.io/acme/jobs/1", postedAt: nil),
            DiscoveredPosting(externalID: "2", title: "Engineering Manager - Machine Learning", location: "Toronto",
                              url: "https://boards.greenhouse.io/acme/jobs/2", postedAt: nil)
        ]
        var seen = Set<String>()
        let kept = JobDiscoveryService.filterAndDedupe(postings: postings, board: board, seenKeys: &seen)
        XCTAssertEqual(kept.map(\.externalID), ["2"])
    }

    func testLocationFilterKeepsAmbiguousMultiLocationPostings() {
        XCTAssertTrue(JobDiscoveryService.isAmbiguousLocation("11 Locations"))
        XCTAssertTrue(JobDiscoveryService.isAmbiguousLocation("2 locations"))
        XCTAssertTrue(JobDiscoveryService.isAmbiguousLocation(""))
        XCTAssertFalse(JobDiscoveryService.isAmbiguousLocation("Toronto, Ontario"))

        let board = TrackedBoard(kindRaw: "workday", slug: "acme", host: "acme.wd5.myworkdayjobs.com",
                                 site: "Careers", locationKeywords: ["toronto"])
        let postings = [
            DiscoveredPosting(externalID: "1", title: "Engineer", location: "11 Locations",
                              url: "https://acme.wd5.myworkdayjobs.com/Careers/job/x/Engineer_R1", postedAt: nil),  // ambiguous → kept
            DiscoveredPosting(externalID: "2", title: "Engineer", location: "Toronto, Ontario",
                              url: "https://acme.wd5.myworkdayjobs.com/Careers/job/y/Engineer_R2", postedAt: nil),  // matches → kept
            DiscoveredPosting(externalID: "3", title: "Engineer", location: "Austin, Texas",
                              url: "https://acme.wd5.myworkdayjobs.com/Careers/job/z/Engineer_R3", postedAt: nil)   // miss → dropped
        ]
        var seen = Set<String>()
        let kept = JobDiscoveryService.filterAndDedupe(postings: postings, board: board, seenKeys: &seen)
        XCTAssertEqual(kept.map(\.externalID), ["1", "2"])
    }

    func testFilterAndDedupeWithNoKeywordsKeepsAllUniqueURLs() {
        let board = TrackedBoard(kindRaw: "lever", slug: "acme")
        let postings = [
            DiscoveredPosting(externalID: "1", title: "Anything", location: "Anywhere",
                              url: "https://jobs.lever.co/acme/1", postedAt: nil),
            DiscoveredPosting(externalID: "1-dupe", title: "Anything", location: "Anywhere",
                              url: "https://jobs.lever.co/acme/1?utm_source=x", postedAt: nil)  // same dedupe key
        ]
        var seen = Set<String>()
        let kept = JobDiscoveryService.filterAndDedupe(postings: postings, board: board, seenKeys: &seen)
        XCTAssertEqual(kept.count, 1)
    }

    // MARK: - Persistence round-trip

    func testDiscoveredJobRoundTripsThroughWorkspaceDTO() throws {
        let boardID = UUID()
        let appID = UUID()
        var job = DiscoveredJob(boardID: boardID, externalID: "42", dedupeKey: "https://x/y",
                                title: "Engineer", companyName: "Acme", location: "Remote",
                                url: "https://x/y", state: .imported, importedApplicationID: appID)
        job.postedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let restored = try XCTUnwrap(WorkspaceFiles.makeDiscoveredJob(from: WorkspaceFiles.discoveredJobDTO(from: job)))
        XCTAssertEqual(restored.boardID, boardID)
        XCTAssertEqual(restored.externalID, "42")
        XCTAssertEqual(restored.state, .imported)
        XCTAssertEqual(restored.importedApplicationID, appID)
    }

    func testTrackedBoardRoundTripsThroughWorkspaceDTO() {
        let board = TrackedBoard(kindRaw: "workday", slug: "acme", host: "acme.wd5.myworkdayjobs.com",
                                 site: "Careers", companyName: "Acme",
                                 titleKeywords: ["engineer"], excludeKeywords: ["intern"],
                                 locationKeywords: ["remote"])
        let restored = WorkspaceFiles.makeTrackedBoard(from: WorkspaceFiles.trackedBoardDTO(from: board))
        XCTAssertEqual(restored.id, board.id)
        XCTAssertEqual(restored.kindRaw, "workday")
        XCTAssertEqual(restored.site, "Careers")
        XCTAssertEqual(restored.titleKeywords, ["engineer"])
        XCTAssertEqual(restored.excludeKeywords, ["intern"])
    }
}
