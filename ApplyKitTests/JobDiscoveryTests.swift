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

    /// Amazon reports a written-out date, and pads single-digit days with a second space.
    func testAmazonParsesWrittenOutPostedDate() throws {
        let json: [String: Any] = ["jobs": [
            ["id": "1", "title": "SDE", "job_path": "/en/jobs/1/sde",
             "posted_date": "August  6, 2026"]
        ]]
        let posted = try XCTUnwrap(AmazonProvider.parse(json).first?.postedAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: posted),
                       DateComponents(year: 2026, month: 8, day: 6))
    }

    /// `transformedPostingTitle` is Apple's URL slug, not a display title — using it as the
    /// title is what made Apple rows read "in-business-expert".
    func testAppleUsesPostingTitleAndSlugsTheURL() throws {
        let json: [String: Any] = ["res": ["searchResults": [
            ["positionId": "200313970",
             "postingTitle": "IN-Business Expert",
             "transformedPostingTitle": "in-business-expert",
             "locations": [["name": "India"]],
             "postingDate": "Aug 06, 2026",
             "postDateInGMT": "2026-08-06T04:01:18.327219746Z"]
        ]]]
        let posting = try XCTUnwrap(AppleProvider.parse(json).first)
        XCTAssertEqual(posting.title, "IN-Business Expert")
        XCTAssertEqual(posting.url, "https://jobs.apple.com/en-us/details/200313970/in-business-expert")
        // postDateInGMT carries nanosecond precision; postingDate is unparseable as ISO.
        XCTAssertEqual(posting.postedAt?.timeIntervalSince1970 ?? 0,
                       Date(timeIntervalSince1970: 1_785_988_878.327).timeIntervalSince1970,
                       accuracy: 1)
    }

    /// Uber's board is Oracle Recruiting Cloud. The legacy www.uber.com search endpoint
    /// still answers but lists requisitions with no public page, so it isn't the source.
    func testUberMapsOracleRequisitionsWithAllOffices() throws {
        let json: [String: Any] = ["items": [[
            "TotalJobsCount": 663,
            "requisitionList": [
                ["Id": "159889", "Title": "Operations Manager, Marketplace",
                 "PostedDate": "2026-08-06",
                 "PrimaryLocation": "Chicago, IL, United States",
                 "secondaryLocations": [["Name": "Miami, FL, United States"],
                                        ["Name": "New York City, NY, United States"]]],
                ["Id": "160418", "Title": "Engineer", "PostedDate": "2026-08-01",
                 "PrimaryLocation": "Toronto, ON, Canada", "secondaryLocations": []]
            ]
        ]]]
        let postings = UberProvider.parse(json)
        XCTAssertEqual(postings.count, 2)

        let first = try XCTUnwrap(postings.first)
        XCTAssertEqual(first.externalID, "159889")
        XCTAssertEqual(first.location,
                       "Chicago, IL, United States | Miami, FL, United States | New York City, NY, United States")
        XCTAssertNotNil(first.postedAt)
        XCTAssertTrue(first.url.hasSuffix("/sites/UberCareers/job/159889"), first.url)

        XCTAssertEqual(postings.last?.location, "Toronto, ON, Canada")
    }

    func testUberBoardDetectionCoversBothItsHosts() throws {
        for candidate in ["https://jobs.uber.com/en/jobs/159889/",
                          "https://www.uber.com/us/en/careers/list/",
                          "https://iaziqy.fa.ocs.oraclecloud.com/hcmUI/CandidateExperience/en/sites/UberCareers/job/159889"] {
            let url = try XCTUnwrap(URL(string: candidate))
            XCTAssertEqual(UberProvider.board(for: url)?.kindRaw, "uber", candidate)
        }
    }

    /// Dedup skips postings already in the inbox, so a provider that starts reporting a
    /// field would never reach rows discovered before the fix without this backfill.
    func testEnrichmentFillsGapsOnExistingRowsWithoutOverwriting() throws {
        var jobs = [
            DiscoveredJob(boardID: UUID(), externalID: "1", dedupeKey: "https://example.com/1",
                          title: "in-business-expert", companyName: "Apple",
                          location: "", url: "https://example.com/1", postedAt: nil),
            DiscoveredJob(boardID: UUID(), externalID: "2", dedupeKey: "https://example.com/2",
                          title: "Engineer", companyName: "Apple",
                          location: "Toronto", url: "https://example.com/2",
                          postedAt: Date(timeIntervalSince1970: 1_000),
                          jobDescription: "Already cached.")
        ]
        let enrichments = [
            "https://example.com/1": DiscoveredPosting(
                externalID: "1", title: "IN-Business Expert", location: "India",
                url: "https://example.com/1", postedAt: Date(timeIntervalSince1970: 5_000),
                descriptionText: "Fresh body."),
            "https://example.com/2": DiscoveredPosting(
                externalID: "2", title: "Engineer", location: "Vancouver",
                url: "https://example.com/2", postedAt: Date(timeIntervalSince1970: 9_000),
                descriptionText: "Different body.")
        ]

        let changed = JobDiscoveryService.applyEnrichments(enrichments, to: &jobs)
        XCTAssertEqual(changed, 1)

        // Gaps filled, and a wrong provider-owned title corrected.
        XCTAssertEqual(jobs[0].title, "IN-Business Expert")
        XCTAssertEqual(jobs[0].location, "India")
        XCTAssertEqual(jobs[0].postedAt, Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(jobs[0].jobDescription, "Fresh body.")
        XCTAssertNotNil(jobs[0].jobDescriptionFetchedAt)

        // Values already present are left alone.
        XCTAssertEqual(jobs[1].location, "Toronto")
        XCTAssertEqual(jobs[1].postedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(jobs[1].jobDescription, "Already cached.")
    }

    func testSharedDateHelpers() {
        XCTAssertNotNil(DiscoveryHTTP.longDate("August  6, 2026"))
        XCTAssertNotNil(DiscoveryHTTP.longDate("Aug 6, 2026"))
        XCTAssertNil(DiscoveryHTTP.longDate("not a date"))
        XCTAssertNil(DiscoveryHTTP.longDate(nil))
        XCTAssertNotNil(DiscoveryHTTP.rfc822Date("Wed, 05 Aug 2026 14:30:00 +0000"))
        XCTAssertNil(DiscoveryHTTP.rfc822Date("2026-08-05"))
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

    /// Google's results page embeds the full dataset as an `AF_initDataCallback` payload.
    /// The old aria-label scrape yielded a title and nothing else, which left `location`
    /// empty — and an empty location makes `passesFilters` skip the location check entirely.
    func testGoogleParsesEmbeddedPayloadForLocationDateAndDescription() {
        let postings = GoogleProvider.parse(html: googleFixtureHTML)
        XCTAssertEqual(postings.count, 2)

        let first = postings.first { $0.externalID == "104461467704533702" }
        XCTAssertEqual(first?.title, "Software Engineer, Infrastructure")
        XCTAssertEqual(first?.location, "Toronto, ON, Canada | Waterloo, ON, Canada")
        XCTAssertEqual(first?.url, "https://www.google.com/about/careers/applications/jobs/results/104461467704533702")
        XCTAssertEqual(first?.postedAt, Date(timeIntervalSince1970: 1_785_150_557))
        XCTAssertTrue(first?.descriptionText.contains("About the job") ?? false)
        XCTAssertTrue(first?.descriptionText.contains("Build infrastructure") ?? false)
    }

    /// The live page ships a second callback block listing Google's sub-brands, with the same
    /// outer shape as the jobs block. Picking a block by position or key would grab it.
    func testGoogleIgnoresTheSubBrandBlockAndFindsTheJobsBlock() {
        let html = """
        <script>AF_initDataCallback({key: 'ds:0', data:[[
        ["projects/x/companies/a","DeepMind","logo"],["projects/x/companies/b","GFiber","logo"]
        ]], sideChannel: {}});</script>
        \(googleFixtureHTML)
        """
        let postings = GoogleProvider.parse(html: html)
        XCTAssertEqual(postings.count, 2)
        XCTAssertFalse(postings.contains { $0.title == "DeepMind" })
    }

    /// The payload is positional, so a record that loses its trailing fields must degrade to
    /// nil rather than trap on an out-of-range index.
    func testGoogleShortRecordDegradesInsteadOfCrashing() {
        let html = googleFixtureHTML.replacingOccurrences(
            of: "]], sideChannel: {}});",
            with: #",["555","Truncated Role"]]], sideChannel: {}});"#)
        let postings = GoogleProvider.parse(html: html)
        XCTAssertEqual(postings.count, 3)
        let truncated = postings.first { $0.externalID == "555" }
        XCTAssertEqual(truncated?.title, "Truncated Role")
        XCTAssertEqual(truncated?.location, "")
        XCTAssertNil(truncated?.postedAt)
    }

    /// Untitled records were previously ingested as jobs — the aria-label regex matched page
    /// furniture such as "Learn more about remote eligibility".
    func testGoogleSkipsRecordsWithoutATitle() {
        let html = googleFixtureHTML.replacingOccurrences(
            of: "]], sideChannel: {}});",
            with: #",["999",""]]], sideChannel: {}});"#)
        XCTAssertEqual(GoogleProvider.parse(html: html).count, 2)
        XCTAssertFalse(GoogleProvider.parse(html: html).contains { $0.externalID == "999" })
    }

    /// Trimmed to the fields the parser reads, at the indices they occupy on the live page.
    private var googleFixtureHTML: String {
        """
        <script>AF_initDataCallback({key: 'ds:1', hash: '3', data:[[
        ["104461467704533702","Software Engineer, Infrastructure","https://apply",
         [null,"<p>Build infrastructure at scale.</p>"],[null,"<p>BS degree.</p>"],
         "projects/x",null,"Google","en-US",
         [["Toronto, ON, Canada",["Toronto, ON, Canada"],"Toronto",null,"ON","CA"],
          ["Waterloo, ON, Canada",["Waterloo, ON, Canada"],"Waterloo",null,"ON","CA"]],
         [null,"<p>About the job</p>"],[2],[1785150557,869000000],[1785150557,869000000],
         [1785150558,362000000],null,null,null,null,null,3],
        ["128658362114941638","Data Scientist","https://apply2",
         [null,"<p>Analyze.</p>"],[null,"<p>MS degree.</p>"],
         "projects/y",null,"Google","en-US",
         [["Mountain View, CA, USA",["Mountain View, CA, USA"],"Mountain View",null,"CA","US"]],
         [null,"<p>About</p>"],[2],[1785000000,0],[1785000000,0],[1785000000,0],
         null,null,null,null,null,3]
        ]], sideChannel: {}});</script>
        """
    }

    func testTeamtailorRSSParsing() {
        let rss = """
        <rss><channel>
          <item><title><![CDATA[Senior Engineer]]></title>
                <link>https://acme.teamtailor.com/jobs/123-senior-engineer</link>
                <pubDate>Wed, 05 Aug 2026 14:30:00 +0000</pubDate>
                <location>Toronto</location></item>
          <item><title>Designer</title>
                <link>https://acme.teamtailor.com/jobs/456-designer</link></item>
        </channel></rss>
        """
        let postings = TeamtailorProvider.parse(rss: rss)
        XCTAssertEqual(postings.count, 2)
        XCTAssertEqual(postings.first?.title, "Senior Engineer")
        XCTAssertEqual(postings.first?.location, "Toronto")
        XCTAssertNotNil(postings.first?.postedAt)   // RFC 822 <pubDate>
        XCTAssertNil(postings.last?.postedAt)       // absent element stays nil
    }

    /// Meta's anchor text is "Title\nOffice\nOffice"; only the first line was being read,
    /// so every Meta posting arrived with an empty location.
    func testMetaParsesLocationsFromAnchorText() throws {
        let json = """
        [{"href":"https://www.metacareers.com/jobs/123456/","text":"Software Engineer\\nMenlo Park, CA\\nSeattle, WA"},
         {"href":"https://www.metacareers.com/jobs/789/","text":"Data Engineer"}]
        """
        let postings = MetaProvider.parse(json: json)
        XCTAssertEqual(postings.count, 2)
        XCTAssertEqual(postings.first?.title, "Software Engineer")
        XCTAssertEqual(postings.first?.location, "Menlo Park, CA | Seattle, WA")
        XCTAssertEqual(postings.last?.location, "")
    }

    func testTikTokQualifiesCityWithParentRegion() throws {
        let json: [String: Any] = ["data": ["job_post_list": [
            ["id": "1", "title": "Engineer",
             "city_info": ["en_name": "London", "parent": ["en_name": "United Kingdom"]]],
            // Singapore is its own parent; don't render "Singapore, Singapore".
            ["id": "2", "title": "Engineer 2",
             "city_info": ["en_name": "Singapore", "parent": ["en_name": "Singapore"]]]
        ]]]
        let postings = ATSxCareers.parse(json, jobURLPrefix: "https://lifeattiktok.com/search/")
        XCTAssertEqual(postings.map(\.location), ["London, United Kingdom", "Singapore"])
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
