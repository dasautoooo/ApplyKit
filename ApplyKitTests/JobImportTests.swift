import XCTest
@testable import ApplyKit

@MainActor
final class JobImportTests: XCTestCase {
    func testURLValidationAndDuplicateNormalization() throws {
        XCTAssertEqual(
            JobURLNormalizer.duplicateKey(for: "HTTPS://Example.com/jobs/123/?utm_source=mail#apply"),
            "https://example.com/jobs/123"
        )
        XCTAssertEqual(
            JobURLNormalizer.duplicateKey(for: "https://example.com/jobs/123"),
            "https://example.com/jobs/123"
        )
        XCTAssertThrowsError(try JobURLNormalizer.validatedURL(from: "file:///tmp/job.html"))
        XCTAssertThrowsError(try JobURLNormalizer.validatedURL(from: "example.com/job"))
    }

    func testHTMLExtractorFindsJobPostingAndCleansVisibleText() throws {
        let html = """
        <html>
          <head>
            <title>Senior Engineer &amp; Builder</title>
            <meta name="description" content="Join Example Co">
            <script type="application/ld+json">
              {"@context":"https://schema.org","@type":"JobPosting","title":"Senior Engineer"}
            </script>
            <style>.hidden { display: none }</style>
          </head>
          <body><nav>Jobs</nav><main><h1>Senior Engineer</h1><p>Build useful software.</p></main></body>
        </html>
        """

        let result = HTMLJobExtractor.extract(
            html: html,
            url: try XCTUnwrap(URL(string: "https://example.com/job")),
            wasRendered: false
        )

        XCTAssertEqual(result.pageTitle, "Senior Engineer & Builder")
        XCTAssertEqual(result.metadataDescription, "Join Example Co")
        XCTAssertTrue(result.jobPostingJSON.contains(#""@type":"JobPosting""#))
        XCTAssertTrue(result.visibleText.contains("Build useful software."))
        XCTAssertFalse(result.visibleText.contains("display: none"))
        XCTAssertTrue(result.isLikelyUsable)
    }

    func testATSURLResolutionUsesPublicJobDetailEndpoints() throws {
        let greenhouse = try XCTUnwrap(ATSJobAPIResolver.request(
            for: XCTUnwrap(URL(string: "https://boards.greenhouse.io/example/jobs/12345"))
        ))
        XCTAssertEqual(greenhouse.kind, .greenhouse)
        XCTAssertEqual(
            greenhouse.apiURL.absoluteString,
            "https://boards-api.greenhouse.io/v1/boards/example/jobs/12345"
        )

        let lever = try XCTUnwrap(ATSJobAPIResolver.request(
            for: XCTUnwrap(URL(string: "https://jobs.lever.co/example/abc-123"))
        ))
        XCTAssertEqual(lever.kind, .lever)
        XCTAssertEqual(
            lever.apiURL.absoluteString,
            "https://api.lever.co/v0/postings/example/abc-123"
        )

        let workday = try XCTUnwrap(ATSJobAPIResolver.request(
            for: XCTUnwrap(URL(string: "https://example.wd5.myworkdayjobs.com/en-US/Careers/job/Toronto/Engineer_R123"))
        ))
        XCTAssertEqual(workday.kind, .workday)
        XCTAssertEqual(
            workday.apiURL.absoluteString,
            "https://example.wd5.myworkdayjobs.com/wday/cxs/example/Careers/job/Toronto/Engineer_R123"
        )
    }

    func testLeverAPIContentPreservesStructuredSections() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://jobs.lever.co/example/abc-123"))
        let request = try XCTUnwrap(ATSJobAPIResolver.request(for: sourceURL))
        let payload: [String: Any] = [
            "id": "abc-123",
            "text": "Senior Engineer",
            "description": "<p>Build reliable products.</p>",
            "categories": [
                "location": "Toronto",
                "commitment": "Full-time"
            ],
            "workplaceType": "hybrid",
            "lists": [
                [
                    "text": "Requirements",
                    "content": "<ul><li>Strong Swift experience</li><li>Clear communication</li></ul>"
                ]
            ]
        ]

        let content = try XCTUnwrap(ATSJobAPIResolver.content(from: payload, request: request))
        XCTAssertEqual(content.pageTitle, "Senior Engineer")
        XCTAssertTrue(content.visibleText.contains("Build reliable products."))
        XCTAssertTrue(content.visibleText.contains("Requirements"))
        XCTAssertTrue(content.visibleText.contains("Strong Swift experience"))
        XCTAssertTrue(content.jobPostingJSON.contains(#""workplaceType":"hybrid""#))
    }

    func testResponseParserPreselectsOnlyHighConfidenceMatch() throws {
        let first = UUID()
        let second = UUID()
        let highResponse = responseJSON(
            firstID: first,
            firstConfidence: 0.91,
            secondID: second,
            secondConfidence: 0.62
        )
        let high = try JobImportResponseParser.parse(
            highResponse,
            submittedURL: "https://example.com/job",
            wasRendered: false,
            validMasterResumeIDs: [first, second]
        )
        XCTAssertTrue(high.hasHighConfidenceRecommendation)
        XCTAssertEqual(high.selectedMasterResumeID, first)

        let lowResponse = responseJSON(
            firstID: first,
            firstConfidence: 0.78,
            secondID: second,
            secondConfidence: 0.70
        )
        let low = try JobImportResponseParser.parse(
            lowResponse,
            submittedURL: "https://example.com/job",
            wasRendered: false,
            validMasterResumeIDs: [first, second]
        )
        XCTAssertFalse(low.hasHighConfidenceRecommendation)
        XCTAssertNil(low.selectedMasterResumeID)
    }

    func testResponseParserRejectsUnknownResumeIDsAndInvalidEnums() throws {
        let known = UUID()
        let response = responseJSON(
            firstID: UUID(),
            firstConfidence: 0.99,
            secondID: UUID(),
            secondConfidence: 0.80,
            workMode: "Sometimes",
            employmentType: "Permanent",
            source: "Job Board"
        )
        let result = try JobImportResponseParser.parse(
            response,
            submittedURL: "https://www.linkedin.com/jobs/view/123",
            wasRendered: true,
            validMasterResumeIDs: [known]
        )
        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertNil(result.selectedMasterResumeID)
        XCTAssertEqual(result.workModeRaw, WorkMode.unknown.rawValue)
        XCTAssertEqual(result.employmentTypeRaw, EmploymentType.unknown.rawValue)
        XCTAssertEqual(result.sourceRaw, ApplicationSource.linkedin.rawValue)
    }

    /// When the ATS already gave us a clean body the prompt omits `job_description`,
    /// so the parser must supply it — and must keep the verbatim text even if the
    /// model returns a (paraphrased) one anyway.
    func testCanonicalDescriptionIsUsedInsteadOfTheModelsEcho() throws {
        let resumeID = UUID()
        let canonical = String(repeating: "Canonical Workday posting body. ", count: 8)

        let omitted = """
        {
          "company_name": "Autodesk",
          "job_title": "Software Engineer, Education",
          "location": "Toronto, ON",
          "work_mode": "Hybrid",
          "employment_type": "Full-time",
          "deadline": null,
          "source": "Company Website",
          "master_resume_matches": []
        }
        """
        let fromOmitted = try JobImportResponseParser.parse(
            omitted,
            submittedURL: "https://autodesk.wd1.myworkdayjobs.com/Ext/job/x",
            wasRendered: false,
            validMasterResumeIDs: [resumeID],
            canonicalDescription: canonical
        )
        XCTAssertEqual(fromOmitted.jobDescription, canonical.trimmed)
        XCTAssertEqual(fromOmitted.jobTitle, "Software Engineer, Education")

        let echoed = try JobImportResponseParser.parse(
            responseJSON(firstID: resumeID, firstConfidence: 0.9,
                         secondID: UUID(), secondConfidence: 0.1),
            submittedURL: "https://autodesk.wd1.myworkdayjobs.com/Ext/job/x",
            wasRendered: false,
            validMasterResumeIDs: [resumeID],
            canonicalDescription: canonical
        )
        XCTAssertEqual(echoed.jobDescription, canonical.trimmed)

        // Generic HTML scrapes have no canonical body, so the model's text stands.
        let scraped = try JobImportResponseParser.parse(
            responseJSON(firstID: resumeID, firstConfidence: 0.9,
                         secondID: UUID(), secondConfidence: 0.1),
            submittedURL: "https://example.com/job",
            wasRendered: false,
            validMasterResumeIDs: [resumeID]
        )
        XCTAssertTrue(scraped.jobDescription.hasPrefix("This is a sufficiently complete"))
    }

    func testMasterResumeProvenanceRoundTripsThroughWorkspaceDTO() throws {
        let masterID = UUID()
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.sourceMasterResumeID = masterID
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dto = WorkspaceFiles.applicationDTO(from: application, documents: [], appFolder: folder)
        let restored = WorkspaceFiles.makeApplication(from: dto, appFolder: folder)
        XCTAssertEqual(restored.sourceMasterResumeID, masterID)

        var legacyDTO = dto
        legacyDTO.sourceMasterResumeID = nil
        let legacy = WorkspaceFiles.makeApplication(from: legacyDTO, appFolder: folder)
        XCTAssertNil(legacy.sourceMasterResumeID)
    }

    private func responseJSON(
        firstID: UUID,
        firstConfidence: Double,
        secondID: UUID,
        secondConfidence: Double,
        workMode: String = "Remote",
        employmentType: String = "Full-time",
        source: String = "Company Website"
    ) -> String {
        """
        {
          "company_name": "Example Co",
          "job_title": "Senior Engineer",
          "location": "Toronto, ON",
          "work_mode": "\(workMode)",
          "employment_type": "\(employmentType)",
          "deadline": "2026-08-31",
          "source": "\(source)",
          "job_description": "This is a sufficiently complete job description containing responsibilities, qualifications, expectations, and company context for the parser.",
          "master_resume_matches": [
            {
              "master_resume_id": "\(firstID.uuidString)",
              "confidence": \(firstConfidence),
              "rationale": "The strongest match."
            },
            {
              "master_resume_id": "\(secondID.uuidString)",
              "confidence": \(secondConfidence),
              "rationale": "A secondary match."
            }
          ]
        }
        """
    }
}
