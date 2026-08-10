import XCTest
@testable import ApplyKit

@MainActor
final class ResumeTailorTests: XCTestCase {

    // MARK: - Stage 1 brief

    func testBriefParsesFromAFencedReplyWrappedInProse() throws {
        let response = """
        Here is my assessment.

        ```json
        {
          "fit_score": 7.5,
          "fit_confidence": "medium",
          "recommended_priority": "Normal",
          "investment_tier": "Standard",
          "investment_time": "20–35 minutes",
          "candidate_story": "Systems-leaning iOS engineer",
          "strong_matches": [{ "claim": "Ships performance work", "evidence": "Cut cold start 40%" }],
          "gaps": [
            { "id": "kafka", "kind": "genuine", "text": "No streaming infrastructure" },
            { "id": "metrics", "kind": "presentation", "text": "Impact is buried" }
          ],
          "plan": { "summary_direction": "Lead with platform depth" },
          "questions": [
            { "kind": "fact", "question": "Did you own the migration end to end?" },
            { "kind": "recall", "gap_id": "kafka", "question": "Have you run a streaming pipeline in production?" }
          ]
        }
        ```

        Let me know if you want the résumé built.
        """

        let brief = try XCTUnwrap(TailoringBrief.parse(from: response))
        XCTAssertEqual(brief.fitScore, 7.5)
        XCTAssertEqual(brief.fitScoreText, "7.5/10")
        XCTAssertEqual(brief.priority, .normal)
        XCTAssertEqual(brief.gaps.count, 2)
        XCTAssertEqual(brief.genuineGaps.map(\.id), ["kafka"])
        XCTAssertEqual(brief.questions.count, 2)
        XCTAssertEqual(brief.questions.last?.questionKind, .recall)
        XCTAssertEqual(brief.questions.last?.gapID, "kafka")
        // Ids and rounds are minted locally — the model doesn't supply them.
        XCTAssertEqual(Set(brief.questions.map(\.id)).count, 2)
        XCTAssertTrue(brief.questions.allSatisfy { $0.round == 1 })
        XCTAssertEqual(brief.unansweredQuestions.count, 2)
    }

    func testWholeNumberFitScoresDropTheDecimal() throws {
        let brief = try XCTUnwrap(TailoringBrief.parse(from: #"{"fit_score": 8}"#))
        XCTAssertEqual(brief.fitScoreText, "8/10")
    }

    func testAnswersAndBriefSurviveTheApplicationRoundTrip() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: """
        { "fit_score": 6, "recommended_priority": "Low",
          "questions": [{ "kind": "fact", "question": "Who owned the rollout?" }] }
        """))
        let questionID = try XCTUnwrap(brief.questions.first?.id)
        brief.setAnswer("I did, with two reviewers.", for: questionID)

        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.setTailoringBrief(brief)

        // The list-facing score is written through, not left to be decoded per row.
        XCTAssertEqual(application.fitScore, 6)

        let restored = try XCTUnwrap(application.tailoringBrief)
        XCTAssertEqual(restored.questions.first?.id, questionID)
        XCTAssertEqual(restored.questions.first?.answer, "I did, with two reviewers.")
        XCTAssertNotNil(restored.questions.first?.answeredAt)
        XCTAssertTrue(restored.pendingAnswers.count == 1, "An answer the clarify pass hasn't seen is still pending")

        application.setTailoringBrief(nil)
        XCTAssertNil(application.fitScore)
    }

    func testBriefAndFitScoreRoundTripThroughTheWorkspaceDTO() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        let brief = try XCTUnwrap(TailoringBrief.parse(from: #"{"fit_score": 9, "recommended_priority": "High"}"#))
        application.setTailoringBrief(brief)

        let dto = WorkspaceFiles.applicationDTO(from: application, documents: [], appFolder: folder)
        XCTAssertEqual(dto.fitScore, 9)
        try application.jobDescription.write(to: folder.appendingPathComponent(WorkspaceFiles.jobDescriptionFile),
                                             atomically: true, encoding: .utf8)
        try application.notes.write(to: folder.appendingPathComponent(WorkspaceFiles.notesFile),
                                    atomically: true, encoding: .utf8)
        try application.tailoringBriefData.write(to: folder.appendingPathComponent(WorkspaceFiles.tailoringBriefFile),
                                                 atomically: true, encoding: .utf8)

        let restored = WorkspaceFiles.makeApplication(from: dto, appFolder: folder)
        XCTAssertEqual(restored.fitScore, 9)
        XCTAssertEqual(restored.tailoringBrief?.fitScore, 9)
        // Still judged and stored — it just has no UI and no mirrored field.
        XCTAssertEqual(restored.tailoringBrief?.recommendedPriority, "High")
    }

    // MARK: - Clarify loop

    func testClarifyPassAppendsFollowUpsAndRetiresResolvedGaps() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: """
        { "gaps": [{ "id": "kafka", "kind": "genuine", "text": "No streaming work" }],
          "questions": [{ "kind": "recall", "gap_id": "kafka", "question": "Any streaming pipelines?" }] }
        """))
        let clarification = try XCTUnwrap(TailoringClarification.parse(from: """
        {
          "updated_gaps": [{ "id": "kafka", "kind": "presentation", "text": "Streaming work isn't on the résumé", "mitigation": "Add the ingest bullet" }],
          "new_questions": [{ "kind": "fact", "question": "What throughput did it handle?" }],
          "recalled_facts": [{ "fact": "Built and operated the ingest pipeline", "relevance": "Covers the streaming must-have" }]
        }
        """))

        brief.apply(clarification)

        XCTAssertEqual(brief.clarifyRound, 1)
        XCTAssertEqual(brief.gaps.count, 1, "An updated gap replaces the original rather than piling up")
        XCTAssertEqual(brief.gaps.first?.gapKind, .presentation)
        XCTAssertTrue(brief.genuineGaps.isEmpty)
        XCTAssertEqual(brief.questions.count, 2)
        XCTAssertEqual(brief.questions.last?.round, 2)
        // Facts, not bullets — wording is Stage 2's job.
        XCTAssertEqual(brief.recalledFacts.map(\.fact), ["Built and operated the ingest pipeline"])
    }

    func testClarifyRecordsFactsRatherThanBullets() throws {
        let bulletID = UUID()
        let clarification = try XCTUnwrap(TailoringClarification.parse(from: """
        { "recalled_facts": [
            { "fact": "Used Protocol Buffers via the IoTCore SDK in the Tuya app",
              "related_bullet_id": "\(bulletID.uuidString)",
              "confirmation_needed": "Whether you defined the schemas or only consumed them" }
        ] }
        """))
        let fact = try XCTUnwrap(clarification.recalledFacts?.first)
        XCTAssertEqual(fact.fact, "Used Protocol Buffers via the IoTCore SDK in the Tuya app")
        XCTAssertEqual(fact.relatedBulletID, bulletID, "A fact that belongs with an existing bullet says so")
        XCTAssertNotNil(fact.confirmationNeeded)
    }

    func testPlanCanAddBulletsAndDropsUnusableOnes() throws {
        let employmentID = UUID()
        let plan = try XCTUnwrap(TailoringPlan.parse(from: """
        { "new_bullets": [
            { "text": "Cut SDK release time 70% by automating the pipeline",
              "employment_id": "\(employmentID.uuidString)",
              "reason": "Distinct accomplishment with its own result" },
            { "reason": "No text, so unusable" }
        ] }
        """))
        XCTAssertEqual(plan.newBullets?.count, 1, "A bullet with no text is dropped, not created empty")
        XCTAssertEqual(plan.newBullets?.first?.employmentID, employmentID)
        XCTAssertFalse(plan.isEmpty, "A plan that only adds a bullet is still actionable")
    }

    func testAppliedRewritesRememberWhatTheyReplaced() throws {
        let changeID = "replacement:\(UUID().uuidString)"
        let session = TailoringSession(
            pastedText: "",
            plan: try XCTUnwrap(TailoringPlan.parse(from: #"{"summary": "Tailored"}"#)),
            appliedChangeIDs: [changeID],
            appliedBefore: [changeID: "Enabled approximately 100 engineers to evaluate unfamiliar codebases…"]
        )
        let restored = try XCTUnwrap(TailoringSession.decode(session.encoded()))
        XCTAssertEqual(restored.appliedChangeIDs, [changeID])
        XCTAssertEqual(restored.appliedBefore[changeID],
                       "Enabled approximately 100 engineers to evaluate unfamiliar codebases…")

        // Sessions written before this existed still load.
        let legacy = try XCTUnwrap(TailoringSession.decode("""
        {"pastedText": "", "appliedChangeIDs": ["\(changeID)"]}
        """))
        XCTAssertEqual(legacy.appliedChangeIDs, [changeID])
        XCTAssertTrue(legacy.appliedBefore.isEmpty)
    }

    /// The prompts carry the skill's own text, so fidelity is what can be
    /// tested without a CLI: these are sentences from SKILL.md and its
    /// references, not from any rewording of them.
    func testPromptsCarryTheSkillVerbatim() {
        let application = JobApplication(companyName: "Example", jobTitle: "iOS Engineer")
        let stageOne = PromptBuilder.tailoringBriefPrompt(
            application: application, allExperiences: [], employments: [],
            masterResume: nil, globalSkillsBlock: "", canResearch: false
        )
        let stageTwo = PromptBuilder.tailoringBuildPrompt(
            brief: TailoringBrief.parse(from: #"{"candidate_story": "x"}"#)!,
            application: application, allExperiences: [], employments: [], globalSkillsBlock: ""
        )

        for rule in [
            "Act as a software engineering hiring manager",
            "Produce a complete resume even when fit is weak",
            "Build an expertise profile from the specialization-specific master resume",
            "Give an approximate fit score out of 10 only as a compact judgment aid",
            "Minimal — 5–15 minutes",
            "directly evidenced",
            "Do not report an ATS match percentage"
        ] {
            XCTAssertTrue(stageOne.contains(rule), "Stage 1 lost skill text: \(rule)")
        }

        for rule in [
            "Write a concise job-relevant summary, normally 35–55 words",
            "Reject a summary that could describe any qualified applicant after swapping the company name",
            "Keep a scope bullet only when it supplies necessary product, system, team, or scale context",
            "Include projects only when they add evidence not already demonstrated more credibly",
            "including a full term plus abbreviation when useful",
            "Connect the most important skills to experience bullets",
            "Prefer recent evidence, but retain older evidence",
            "Escape LaTeX-sensitive characters in content",
            "Would the summary and bullets still sound specific to this candidate if the company name and product nouns were removed?"
        ] {
            XCTAssertTrue(stageTwo.contains(rule), "Stage 2 lost skill text: \(rule)")
        }
    }

    /// The PDF check proposes summary, skills, and bullet edits, so it is bound
    /// by the same rules as the build that produced them. It was not, until the
    /// `edits` field was added and these rules didn't follow.
    func testThePDFCheckIsHeldToTheSameSkillRulesAsTheBuild() {
        let application = JobApplication(companyName: "Example", jobTitle: "iOS Engineer")
        let rendered = ResumePDFInspector.Rendered(pageCount: 2, pages: ["Page one", "Page two"])
        let review = PromptBuilder.tailoringReviewPrompt(
            application: application,
            brief: TailoringBrief.parse(from: #"{"candidate_story": "x"}"#),
            rendered: rendered,
            renderedExperiences: [], employments: [], globalSkillsBlock: ""
        )

        for rule in [
            "Act as a software engineering hiring manager",     // identity
            "Never invent or silently strengthen metrics",      // non-negotiables
            "duplicated ideas;",                                // page budget
            "orphaned headings or roles",                       // render inspection
            "normally 35–55 words",                             // it can replace the summary
            "Use one row per selected category",                // it can replace the Skills block
            "Signal improved: Relevance | Technical depth",     // it must justify a rewrite
            "directly evidenced",                               // truthful keyword classification
            "50% strength and depth of evidence",               // selection weighting
            "keep a result in the opening"                      // no weakening a bullet
        ] {
            XCTAssertTrue(review.contains(rule), "The PDF check is missing a skill rule: \(rule)")
        }

        // And the deviation that makes it a check rather than a second pass.
        XCTAssertTrue(review.contains("What is on this résumé (the ONLY valid ids)"))
        XCTAssertTrue(review.contains("you may not add material that is not"))
    }

    func testTheScoreIsAFitReCheckTheSameAsStageOne() throws {
        // The score is asked for directly, same as the brief — not derived from
        // the checklist below, which still drives findings/checksSummary but no
        // longer the headline number.
        let response = """
        {
          "page_count": 9,
          "verdict": "Ready after minor corrections",
          "fit_score": 7,
          "fit_confidence": "medium",
          "checks": [
            { "section": "Two-page and rewrite checks", "question": "Is actual or estimated length at most two pages?", "status": "pass" },
            { "section": "Engineering signal", "question": "Do the first bullets in each role carry the strongest relevant evidence?", "status": "pass" },
            { "section": "Engineering signal", "question": "Is redundant content removed?", "status": "fail", "note": "The 10.8% result appears twice" },
            { "section": "Structure and ATS readability", "question": "Are roles reverse chronological?", "status": "pass" },
            { "section": "Structure and ATS readability", "question": "Does plain-text extraction preserve content and order when a file is available?", "status": "fail", "note": "Skills labels extract before their values" },
            { "section": "Job alignment", "question": "Does the summary communicate one clear candidate story?", "status": "pass" },
            { "section": "Job alignment", "question": "Are genuine gaps stated rather than disguised?", "status": "pass" },
            { "section": "Source traceability and truth", "question": "Can the user defend every selected bullet in an interview?", "status": "unclear", "note": "Not answerable from the rendered file" }
          ]
        }
        """
        let review = try XCTUnwrap(TailoringReview.parse(from: response, pageCount: 2,
                                                        documentPath: "/tmp/resume.pdf", round: 3))
        XCTAssertEqual(review.passedChecks.count, 5)
        XCTAssertEqual(review.failedChecks.count, 2)
        XCTAssertEqual(review.unclearChecks.count, 1, "Unclear is kept, not counted as a pass or a fail")
        XCTAssertEqual(review.fitScore, 7)
        XCTAssertEqual(review.fitConfidence, "medium")
        XCTAssertEqual(review.score, 7, "The headline score is the fit re-check, not the checklist ratio (which would be 5/7 here)")
        XCTAssertEqual(review.scoreText, "7/10")
        XCTAssertEqual(review.checksSummary, "5 of 7 skill checks pass, 1 unclear")
        XCTAssertEqual(review.pageCount, 2, "Length comes from the file, not the model's claim of 9")
        XCTAssertTrue(review.summary.contains("Check #3"))

        // No fit_score in the reply means no score, rather than a made-up one —
        // even when every check passed.
        let empty = try XCTUnwrap(TailoringReview.parse(
            from: #"{"verdict": "Needs layout verification", "checks": [{"question": "Q", "status": "pass"}]}"#,
            pageCount: 2, documentPath: "", round: 1))
        XCTAssertNil(empty.score)
        XCTAssertNotNil(empty.checksSummary, "Checks still summarize independently of the score")
    }

    /// A revert point is a snapshot, not an inverse operation: the tailoring
    /// actions rewrite whole fields (a selection change rewrites the order, a
    /// rewrite repoints the variant), so putting the fields back is the only
    /// way to land exactly where you were.
    func testARevertPointRestoresEverythingTailoringTouches() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "iOS Engineer")
        application.summaryText = "Original summary"
        application.skillsBlockText = "Original skills"
        let kept = UUID(), dropped = UUID(), variant = UUID()
        application.setExperience(kept, selected: true)
        application.setExperience(dropped, selected: true)
        application.setExperienceOrder([kept, dropped])
        application.setVariant(variant, for: kept)
        application.setRoleDescription("Original role line", for: kept)
        application.setSectionOrder([.projects, .experience])

        let revert = TailoringRevertPoint(application)

        // Everything a change could plausibly touch, changed.
        application.summaryText = "Tailored summary"
        application.skillsBlockText = "Tailored skills"
        application.setExperience(dropped, selected: false)
        application.setExperienceOrder([dropped, kept])
        application.setVariant(UUID(), for: kept)
        application.setRoleDescription("Rewritten role line", for: kept)
        application.setRoleDescriptionHidden(true, for: kept)
        application.setSectionOrder([.experience, .projects])

        revert.restore(into: &application)

        XCTAssertEqual(application.summaryText, "Original summary")
        XCTAssertEqual(application.skillsBlockText, "Original skills")
        XCTAssertTrue(application.selectedExperienceIDs.contains(dropped), "A dropped bullet comes back")
        XCTAssertEqual(application.experienceOrder, [kept, dropped])
        XCTAssertEqual(application.selectedVariantID(for: kept), variant, "The previous wording is reselected")
        XCTAssertEqual(application.roleDescription(for: kept), "Original role line")
        XCTAssertFalse(application.isRoleDescriptionHidden(for: kept))
        // `setSectionOrder` appends whatever wasn't named, so compare the lead.
        XCTAssertEqual(Array(application.sectionOrder.prefix(2)), [.projects, .experience])
    }

    func testRevertPointsSurviveTheSessionRoundTripAndOldSessionsStillLoad() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.summaryText = "Before"
        var point = TailoringRevertPoint(application)
        point.createdVariantID = UUID()
        point.createdVariantOwnerID = UUID()

        let session = TailoringSession(appliedChangeIDs: ["summary"], revertPoints: ["summary": point])
        let restored = try XCTUnwrap(TailoringSession.decode(session.encoded()))
        XCTAssertEqual(restored.revertPoints["summary"], point)

        // A session written before revert existed still decodes; those changes
        // stay applied and simply can't be undone.
        let legacy = try XCTUnwrap(TailoringSession.decode(#"{"pastedText":"","appliedChangeIDs":["summary"]}"#))
        XCTAssertTrue(legacy.revertPoints.isEmpty)
        XCTAssertEqual(legacy.appliedChangeIDs, ["summary"])
    }

    /// Applying a suggestion saves the editor's snapshot of the application. That
    /// snapshot predates the PDF check — the runner writes the review straight to
    /// the store — so an unguarded save wiped it, taking the suggestion you just
    /// clicked and every unapplied sibling with it.
    func testSavingTheEditorSnapshotCannotEraseTheReviewThatSuggestedTheChange() throws {
        var stored = JobApplication(companyName: "Example", jobTitle: "iOS Engineer")
        let review = try XCTUnwrap(TailoringReview.parse(
            from: #"{"verdict": "Ready after minor corrections", "checks": [{"question": "Is it two pages?", "status": "pass"}]}"#,
            pageCount: 2, documentPath: "/tmp/resume.pdf", round: 1))
        stored.tailoringReviewData = review.encoded()

        // The editor's copy, taken before the check ran, with an applied edit on it.
        var snapshot = stored
        snapshot.tailoringReviewData = ""
        snapshot.summaryText = "Tailored summary"

        snapshot.preserveRunOwnedState(from: stored)

        XCTAssertEqual(snapshot.tailoringReview?.round, 1, "The review survives the save")
        XCTAssertEqual(snapshot.tailoringReview?.checks.count, 1)
        XCTAssertEqual(snapshot.summaryText, "Tailored summary", "…and the edit being saved still lands")
    }

    func testTheReviewPromptRunsTheChecklistAndReJudgesFitTheSameAsStageOne() {
        let review = PromptBuilder.tailoringReviewPrompt(
            application: JobApplication(companyName: "Example", jobTitle: "iOS Engineer"),
            brief: nil,
            rendered: ResumePDFInspector.Rendered(pageCount: 2, pages: ["a", "b"]),
            renderedExperiences: [], employments: [], globalSkillsBlock: ""
        )
        // It still runs the skill's checklist, quoting the skill's questions...
        XCTAssertTrue(review.contains("Are roles reverse chronological?"))
        XCTAssertTrue(review.contains("quoting the question as the checklist"))
        // ...and the score is the same fit rubric Stage 1 uses, asked for directly.
        XCTAssertTrue(review.contains("\"fit_score\": 7.5"))
        XCTAssertTrue(review.contains("\"fit_confidence\""))
        XCTAssertTrue(review.contains(PromptBuilder.fitReassessmentRules),
                      "Same fit rubric text as Stage 1, not a paraphrase")
        XCTAssertTrue(review.contains("Score fit again from what this rendered document actually claims"))
    }

    func testTheReviewFitRubricIsTheSameSkillTextAsStageOnes() {
        // Both `fitAndEffortRules` (Stage 1) and `fitReassessmentRules` (the PDF
        // check) quote `ResumeTailorSkill.fitAssessment` verbatim — one rubric,
        // not two hand-written copies that can drift apart.
        XCTAssertTrue(PromptBuilder.fitAndEffortRules.contains(ResumeTailorSkill.fitAssessment))
        XCTAssertTrue(PromptBuilder.fitReassessmentRules.contains(ResumeTailorSkill.fitAssessment))
    }

    /// The PDF check used to receive only each fact's `confirmation_needed`
    /// caveat, under the heading "Facts the candidate has not yet confirmed" —
    /// the fact itself was dropped. So an answer like "Kubernetes ingress for
    /// Recursion's upload platform" reached the review as nothing but "the
    /// specific implementation was not provided", and it correctly-but-wrongly
    /// proposed deleting the ingress claim the candidate had just confirmed.
    func testTheReviewSeesConfirmedFactsNotJustTheirCaveats() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: #"{"fit_score": 7}"#))
        brief.recalledFacts = [
            RecalledFact(fact: "The candidate operated Kubernetes ingress for Recursion's upload platform.",
                         relevance: "Adds direct production ingress experience.",
                         confirmationNeeded: "The specific ingress implementation and production scale were not provided.")
        ]
        let review = PromptBuilder.tailoringReviewPrompt(
            application: JobApplication(companyName: "Example", jobTitle: "Infrastructure Engineer"),
            brief: brief,
            rendered: ResumePDFInspector.Rendered(pageCount: 2, pages: ["a", "b"]),
            renderedExperiences: [], employments: [], globalSkillsBlock: ""
        )
        // The fact reaches the review, with its context…
        XCTAssertTrue(review.contains("operated Kubernetes ingress for Recursion's upload platform"))
        XCTAssertTrue(review.contains("Adds direct production ingress experience"))
        // …the caveat is still passed, but labelled as a missing detail…
        XCTAssertTrue(review.contains("detail the candidate has not supplied"))
        XCTAssertTrue(review.contains("The specific ingress implementation"))
        // …and the old, load-bearing mislabel is gone.
        XCTAssertFalse(review.contains("Facts the candidate has not yet confirmed"),
                       "A supplied answer is confirmation, not a pending question")
        // The rule that stops the deletion is stated outright.
        XCTAssertTrue(review.contains("Never recommend deleting something the candidate has told you they did"))
    }

    /// Each clarify pass re-reads the same answers and restates what it learned,
    /// so appending blindly gave the candidate one copy of every fact per round
    /// — visible in the panel, and each copy arguing for itself in the build.
    func testReRunningClarifyDoesNotDuplicateTheSameFact() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: #"{"fit_score": 7}"#))
        let questionID = UUID()

        let first = TailoringClarification(updatedGaps: nil, newQuestions: nil, recalledFacts: [
            RecalledFact(questionID: questionID, fact: "The candidate operated Kubernetes ingress for Recursion's upload platform.")
        ])
        brief.apply(first)
        XCTAssertEqual(brief.recalledFacts.count, 1)

        // Same answer, restated with a caveat: it updates in place.
        let second = TailoringClarification(updatedGaps: nil, newQuestions: nil, recalledFacts: [
            RecalledFact(questionID: questionID,
                         fact: "The candidate operated Kubernetes ingress for Recursion's upload platform.",
                         confirmationNeeded: "Scale was not provided.")
        ])
        brief.apply(second)
        XCTAssertEqual(brief.recalledFacts.count, 1, "One fact, not one per round")
        XCTAssertEqual(brief.recalledFacts.first?.confirmationNeeded, "Scale was not provided.",
                       "The newer wording wins")

        // Reworded without a question id — matched on the wording instead.
        brief.apply(TailoringClarification(updatedGaps: nil, newQuestions: nil, recalledFacts: [
            RecalledFact(fact: "Candidate operated the Kubernetes ingress for the Recursion upload platform.")
        ]))
        XCTAssertEqual(brief.recalledFacts.count, 1)

        // A genuinely different fact still lands.
        brief.apply(TailoringClarification(updatedGaps: nil, newQuestions: nil, recalledFacts: [
            RecalledFact(fact: "The candidate participated in an on-call rotation at Alibaba.")
        ]))
        XCTAssertEqual(brief.recalledFacts.count, 2)
    }

    /// The review is asked to re-score fit "same rubric as Stage 1" — but the
    /// posting was never in its prompt, only "eBay — iOS Engineer". It answered
    /// honestly, with low confidence and a finding blaming the missing JD.
    func testTheReviewSeesTheJobDescriptionItIsScoringAgainst() throws {
        var application = JobApplication(companyName: "eBay", jobTitle: "iOS Engineer")
        application.jobDescription = "You will own release engineering for the iOS app, including accessibility."
        let review = PromptBuilder.tailoringReviewPrompt(
            application: application, brief: nil,
            rendered: ResumePDFInspector.Rendered(pageCount: 2, pages: ["a", "b"]),
            renderedExperiences: [], employments: [], globalSkillsBlock: ""
        )
        XCTAssertTrue(review.contains("own release engineering for the iOS app"),
                      "Fit can't be judged against a posting the review never sees")
        XCTAssertTrue(review.contains("## Job description"))
        XCTAssertTrue(review.contains("Judge fit against it"))
        // Stage 1 and the build already had it; the review now uses the same block.
        XCTAssertTrue(review.contains(PromptBuilder.tailoringJobBlock(application: application)))
    }

    /// The check is judging the artifact a whole pipeline produced, so it needs
    /// what that pipeline knew: the posting, the master résumé, Stage 1's
    /// judgment and plan, the candidate's answers and direction, their notes,
    /// and what the previous check already found.
    func testTheReviewSeesEverythingStageOneDid() throws {
        var application = JobApplication(companyName: "eBay", jobTitle: "iOS Engineer")
        application.jobDescription = "Own release engineering for the iOS app."
        application.notes = "Referred by a staff engineer on the payments team."

        var brief = try XCTUnwrap(TailoringBrief.parse(from: """
        {
          "fit_score": 7.5, "fit_confidence": "medium",
          "investment_tier": "Standard", "investment_time": "20–35 minutes",
          "effort_rationale": "More tailoring can plausibly change the outcome here.",
          "candidate_story": "Systems-leaning iOS engineer",
          "strong_matches": [{ "claim": "Ships release tooling", "evidence": "Cut release time 40%" }],
          "gaps": [{ "id": "a11y", "kind": "genuine", "text": "No accessibility ownership", "mitigation": "State it plainly" }],
          "plan": { "summary_direction": "Lead with release ownership", "skills_direction": "Put Swift first" },
          "questions": [{ "kind": "recall", "question": "Have you owned an App Store release?" }]
        }
        """))
        let questionID = try XCTUnwrap(brief.questions.first?.id)
        brief.setAnswer("Yes — I ran the release train for two years.", for: questionID)
        brief.buildNotes = "Keep the Tuya bullet; it's my strongest."

        let previous = try XCTUnwrap(TailoringReview.parse(
            from: #"{"verdict": "Needs layout verification", "fit_score": 7, "findings": [{"severity": "fix", "text": "Skills table extracts column-first", "fix": "Re-render sequentially"}], "checks": [{"question": "Are roles reverse chronological?", "status": "fail", "note": "Tuya precedes Recursion"}]}"#,
            pageCount: 2, documentPath: "/tmp/r.pdf", round: 1))

        let master = MasterResume(name: "iOS Platform")
        let review = PromptBuilder.tailoringReviewPrompt(
            application: application, brief: brief,
            rendered: ResumePDFInspector.Rendered(pageCount: 2, pages: ["a", "b"]),
            renderedExperiences: [], employments: [], globalSkillsBlock: "",
            masterResume: master, allExperiences: [], previous: previous
        )

        // The posting, the master résumé, and the candidate's notes.
        XCTAssertTrue(review.contains("Own release engineering for the iOS app."))
        XCTAssertTrue(review.contains("iOS Platform"), "The master résumé it was built from")
        XCTAssertTrue(review.contains("Referred by a staff engineer"))
        // Stage 1's judgment, evidence, gaps, and plan.
        XCTAssertTrue(review.contains("Fit: 7.5/10 (medium confidence)"))
        XCTAssertTrue(review.contains("Investment: Standard, 20–35 minutes"))
        XCTAssertTrue(review.contains("Ships release tooling"))
        XCTAssertTrue(review.contains("No accessibility ownership"))
        XCTAssertTrue(review.contains("Lead with release ownership"))
        // The Q&A and the candidate's own direction.
        XCTAssertTrue(review.contains("Have you owned an App Store release?"))
        XCTAssertTrue(review.contains("I ran the release train for two years"))
        XCTAssertTrue(review.contains("Keep the Tuya bullet"))
        // The previous check, and the instruction not to parrot it.
        XCTAssertTrue(review.contains("What check #1 found"))
        XCTAssertTrue(review.contains("Skills table extracts column-first"))
        XCTAssertTrue(review.contains("Tuya precedes Recursion"), "Including which checks failed")
        XCTAssertTrue(review.contains("judge the file in front of you, not this list"))
        // The master résumé must not widen what may be edited.
        XCTAssertTrue(review.contains("is not on this document and is not yours to edit"))
    }

    func testTheFirstCheckHasNoPreviousBlock() {
        let review = PromptBuilder.tailoringReviewPrompt(
            application: JobApplication(companyName: "Example", jobTitle: "Engineer"), brief: nil,
            rendered: ResumePDFInspector.Rendered(pageCount: 2, pages: ["a"]),
            renderedExperiences: [], employments: [], globalSkillsBlock: ""
        )
        XCTAssertFalse(review.contains("What check #"))
        XCTAssertTrue(review.contains("No brief was produced"), "A missing brief is stated, not silently skipped")
    }

    /// A 7.7 judgment rendered as "7.5/10" sat directly above a finding quoting
    /// "the 7.7 fit judgment". Show what was actually judged, and ask for the
    /// half-point scale rather than silently rounding to it.
    func testFitScoresAreShownExactlyAsJudged() {
        XCTAssertEqual(FitScore.text(7.7), "7.7/10", "Not silently rounded to 7.5")
        XCTAssertEqual(FitScore.text(7.5), "7.5/10")
        XCTAssertEqual(FitScore.text(8), "8/10", "A whole number drops the decimal")
        XCTAssertNil(FitScore.text(nil))

        let review = PromptBuilder.tailoringReviewPrompt(
            application: JobApplication(companyName: "Example", jobTitle: "Engineer"), brief: nil,
            rendered: ResumePDFInspector.Rendered(pageCount: 2, pages: ["a"]),
            renderedExperiences: [], employments: [], globalSkillsBlock: ""
        )
        XCTAssertTrue(review.contains("0.5 increments"))
    }

    func testTheReviewPromptShowsStageOnesScoreOnlyAsReference() throws {
        let brief = try XCTUnwrap(TailoringBrief.parse(from: #"{"fit_score": 6, "fit_confidence": "low"}"#))
        let review = PromptBuilder.tailoringReviewPrompt(
            application: JobApplication(companyName: "Example", jobTitle: "iOS Engineer"),
            brief: brief,
            rendered: ResumePDFInspector.Rendered(pageCount: 2, pages: ["a"]),
            renderedExperiences: [], employments: [], globalSkillsBlock: ""
        )
        XCTAssertTrue(review.contains("Fit: 6/10 (low confidence)"))
        XCTAssertTrue(review.contains("Stage 1's numbers are context, not an answer to copy"))
        XCTAssertTrue(review.contains("re-score fit from what actually got built"))
    }

    /// Role-description lines are per-application state ApplyKit owns, so the
    /// tailor has to be able to see them, reword them, and hide them.
    func testRoleDescriptionsCanBeSeenRewordedAndHidden() throws {
        var employment = Employment(companyName: "Tuya", role: "Software Engineer",
                                    roleDescription: "Consumer IoT platform serving millions of devices.")
        employment.id = UUID()
        var application = JobApplication(companyName: "Example", jobTitle: "Backend Engineer")

        // The prompts show the line, its employment id, and whether it renders.
        let build = PromptBuilder.tailoringBuildPrompt(
            brief: TailoringBrief.parse(from: #"{"candidate_story": "x"}"#)!,
            application: application, allExperiences: [], employments: [employment], globalSkillsBlock: ""
        )
        XCTAssertTrue(build.contains(employment.id.uuidString))
        XCTAssertTrue(build.contains("currently SHOWN"))
        XCTAssertTrue(build.contains("\"role_descriptions\""))

        // The PDF check can act on one too — an orphaned heading is usually a
        // scope line, and it could previously only describe the problem.
        let review = PromptBuilder.tailoringReviewPrompt(
            application: application, brief: nil,
            rendered: ResumePDFInspector.Rendered(pageCount: 2, pages: ["a", "b"]),
            renderedExperiences: [], employments: [employment], globalSkillsBlock: ""
        )
        XCTAssertTrue(review.contains("\"role_descriptions\""))
        XCTAssertTrue(review.contains("Hiding one (`include: false`)"))

        // And a plan carrying both a reword and a hide applies to the record.
        let plan = try XCTUnwrap(TailoringPlan.parse(from: """
        { "role_descriptions": [
            { "employment_id": "\(employment.id.uuidString)", "include": false, "text": "IoT platform, millions of devices." }
        ] }
        """))
        let decision = try XCTUnwrap(plan.roleDescriptions?.first)
        XCTAssertEqual(decision.include, false)
        application.setRoleDescription(try XCTUnwrap(decision.text), for: employment.id)
        application.setRoleDescriptionHidden(!(decision.include ?? true), for: employment.id)
        XCTAssertEqual(application.roleDescription(for: employment.id), "IoT platform, millions of devices.")
        XCTAssertTrue(application.isRoleDescriptionHidden(for: employment.id))
    }

    /// The flat order interleaves bullets with employment ids, which mark where
    /// each job's role-description line renders. Reordering must not lose them.
    func testRoleLinesAreOrderedAlongsideBullets() throws {
        let employmentID = UUID()
        let first = UUID(), second = UUID(), third = UUID()
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        for id in [first, second, third] { application.setExperience(id, selected: true) }
        application.setExperienceOrder([first, employmentID, second, third])
        XCTAssertEqual(application.experienceOrder, [first, employmentID, second, third])

        // A plan may place the line deliberately by naming the employment id,
        // which has to survive parsing as a legal entry rather than be filtered
        // out as "not a bullet".
        let placing = try XCTUnwrap(TailoringPlan.parse(from: """
        { "ordered_experience_ids": ["\(first.uuidString)", "\(second.uuidString)", "\(employmentID.uuidString)", "\(third.uuidString)"] }
        """))
        XCTAssertEqual(placing.orderedExperienceIDs?[2], employmentID)

        // A plan that reorders bullets without mentioning the line still parses;
        // applying it puts the marker back rather than dropping it, which would
        // silently move the line to the top of its job.
        let silent = try XCTUnwrap(TailoringPlan.parse(from: """
        { "ordered_experience_ids": ["\(third.uuidString)", "\(first.uuidString)", "\(second.uuidString)"] }
        """))
        XCTAssertEqual(silent.orderedExperienceIDs, [third, first, second])
        XCTAssertFalse(silent.orderedExperienceIDs?.contains(employmentID) ?? true)
    }

    func testBothStagesExplainHowToPositionARoleLine() {
        let employment = Employment(companyName: "Tuya", role: "Engineer", roleDescription: "IoT platform.")
        let application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        let build = PromptBuilder.tailoringBuildPrompt(
            brief: TailoringBrief.parse(from: #"{"candidate_story": "x"}"#)!,
            application: application, allExperiences: [], employments: [employment], globalSkillsBlock: ""
        )
        let review = PromptBuilder.tailoringReviewPrompt(
            application: application, brief: nil,
            rendered: ResumePDFInspector.Rendered(pageCount: 2, pages: ["a", "b"]),
            renderedExperiences: [], employments: [employment], globalSkillsBlock: ""
        )
        for prompt in [build, review] {
            XCTAssertTrue(prompt.contains("put its `employment_id`"))
            XCTAssertTrue(prompt.contains("keep the line at the top of its job"))
        }
    }

    /// The deliberate deviations, so they stay deliberate.
    func testAppSpecificAdaptationsAreApplied() {
        let application = JobApplication(companyName: "Example", jobTitle: "iOS Engineer")
        let stageOne = PromptBuilder.tailoringBriefPrompt(
            application: application, allExperiences: [], employments: [],
            masterResume: nil, globalSkillsBlock: "", canResearch: false
        )
        // The skill weighs logistics as a fit input; the app never asks about them.
        XCTAssertTrue(stageOne.contains("never ask about it"))
        XCTAssertTrue(stageOne.contains("Never ask about work authorization"))
        // ApplyKit holds the résumé, so Stage 2 returns edits, not a document.
        let stageTwo = PromptBuilder.tailoringBuildPrompt(
            brief: TailoringBrief.parse(from: #"{"candidate_story": "x"}"#)!,
            application: application, allExperiences: [], employments: [], globalSkillsBlock: ""
        )
        XCTAssertTrue(stageTwo.contains("ApplyKit holds the résumé itself"))
    }

    /// The real case: the PDF check replaced a bullet opening with a result
    /// ("Made … reproducible") by one opening with the work ("Built automated
    /// test infrastructure…"), justified as "Technical depth". The prompts
    /// forbid that in two places and it happened anyway, so it's checked.
    func testARewriteThatTradesAResultOpeningForAnActivityOpeningIsFlagged() {
        let current = """
        Made scientific model evaluation reproducible by implementing Hydra-configured dataset adapters and task \
        definitions, distributing execution through Slurm, and tracking configurations in W&B.
        """
        let proposed = """
        Built automated test infrastructure for recall@k, precision@k, and z-score evaluations using \
        Hydra-configured dataset adapters, distributed Slurm execution, and W&B tracking.
        """
        let warning = BulletOpening.downgradeWarning(current: current, proposed: proposed)
        XCTAssertNotNil(warning, "Result opening traded for an activity opening")
        XCTAssertEqual(warning?.contains("built"), true)
        XCTAssertEqual(warning?.contains("made"), true)

        // The other direction is an upgrade, not a downgrade.
        XCTAssertNil(BulletOpening.downgradeWarning(current: proposed, proposed: current))
        // Two activity openings, or two result openings, are left alone.
        XCTAssertNil(BulletOpening.downgradeWarning(current: "Built X by doing Y.",
                                                    proposed: "Designed X by doing Z."))
        XCTAssertNil(BulletOpening.downgradeWarning(current: "Cut latency 40% by caching.",
                                                    proposed: "Reduced latency 40% by caching."))
        // An unrecognized opening is not guessed at.
        XCTAssertNil(BulletOpening.downgradeWarning(current: "Partnered with design on X.",
                                                    proposed: "Built X with design."))
        XCTAssertTrue(BulletOpening.opensWithOutcome("  Reduced p99 by 30%."), "Leading space and case ignored")
    }

    /// "Signal improved: Technical depth" names a category, not a reason. The
    /// meaning is fixed text — what a signal does for a reader doesn't vary by
    /// application, so there's nothing gained by asking the model each time.
    func testEverySignalExplainsItself() {
        for signal in TailoringSignal.allCases {
            let described = TailoringSignal.described(signal.rawValue)
            XCTAssertTrue(described.hasPrefix(signal.rawValue), signal.rawValue)
            XCTAssertTrue(described.count > signal.rawValue.count + 20,
                          "\(signal.rawValue) needs to say what it means, not just name itself")
        }
        XCTAssertEqual(TailoringSignal.described("Technical depth"),
                       "Technical depth — makes the mechanism visible, so the skill is evidenced rather than merely listed")
        // The model's wording varies; the gloss shouldn't be lost to case.
        XCTAssertEqual(TailoringSignal(loose: "technical depth"), .technicalDepth)
        XCTAssertEqual(TailoringSignal(loose: "ATS Terminology"), .atsTerminology)
        // A signal outside the skill's vocabulary is passed through, not dropped.
        XCTAssertEqual(TailoringSignal.described("Momentum"), "Momentum")
        XCTAssertNil(TailoringSignal(loose: "Momentum"))
    }

    /// The field is specified as exactly one signal, and replies routinely name
    /// several — "Relevance | Technical depth | Ownership | Concision". Matching
    /// the whole string found nothing, so every gloss was lost and the row
    /// showed the bare labels it was meant to replace.
    func testSeveralSignalsInOneReplyAreEachExplained() {
        let descriptions = TailoringSignal.descriptions("Relevance | Technical depth | Ownership | Concision")
        XCTAssertEqual(descriptions.count, 4)
        XCTAssertTrue(descriptions[0].hasPrefix("Relevance — "))
        XCTAssertTrue(descriptions[3].hasPrefix("Concision — "))
        XCTAssertTrue(descriptions.allSatisfy { $0.contains(" — ") }, "Every one explains itself")

        // The separators replies actually use.
        XCTAssertEqual(TailoringSignal.all(in: "Clarity, ATS terminology").count, 2)
        XCTAssertEqual(TailoringSignal.all(in: "Impact and Ownership").count, 2)
        XCTAssertEqual(TailoringSignal.all(in: "Relevance / Concision").count, 2)
        // Repeats collapse, and order of appearance is kept.
        XCTAssertEqual(TailoringSignal.all(in: "Impact | Impact | Clarity"), [.impact, .clarity])
        // Still fine with the single value the schema actually asks for.
        XCTAssertEqual(TailoringSignal.all(in: "Technical depth"), [.technicalDepth])
    }

    /// The schema wrote this field's allowed values as a pipe-separated list,
    /// which is itself a plausible JSON string — so replies copied the list.
    /// Every other field uses an angle-bracket placeholder; this one now does.
    func testTheSignalFieldAsksForExactlyOneValue() {
        let build = PromptBuilder.tailoringBuildPrompt(
            brief: try! XCTUnwrap(TailoringBrief.parse(from: #"{"fit_score": 7}"#)),
            application: JobApplication(companyName: "Example", jobTitle: "Engineer"),
            allExperiences: [], employments: [], globalSkillsBlock: ""
        )
        XCTAssertTrue(build.contains("<exactly one of: Relevance, Technical depth"))
        XCTAssertFalse(build.contains("\"Relevance | Technical depth"),
                       "A pipe-separated value list reads as a literal value")
    }

    func testRewritesMustArgueTheirCaseNotLabelIt() {
        let build = PromptBuilder.tailoringBuildPrompt(
            brief: try! XCTUnwrap(TailoringBrief.parse(from: #"{"fit_score": 7}"#)),
            application: JobApplication(companyName: "Example", jobTitle: "Engineer"),
            allExperiences: [], employments: [], globalSkillsBlock: ""
        )
        XCTAssertTrue(build.contains("Name the hiring value for THIS posting"))
        XCTAssertTrue(build.contains("`signal` already carries the category — the reason exists to justify it"))
        // The rejected forms are named, since they're what it defaults to.
        XCTAssertTrue(build.contains("improves technical depth"))
        XCTAssertTrue(build.contains("better matches the JD"))
    }

    func testTheReviewIsToldItsRewritesAreStillBullets() {
        let review = PromptBuilder.tailoringReviewPrompt(
            application: JobApplication(companyName: "Example", jobTitle: "Engineer"), brief: nil,
            rendered: ResumePDFInspector.Rendered(pageCount: 2, pages: ["a"]),
            renderedExperiences: [], employments: [], globalSkillsBlock: ""
        )
        XCTAssertTrue(review.contains("held to the bullet rules above, not loosened because it is fixing a finding"))
        XCTAssertTrue(review.contains("De-duplicating two bullets does not license"))
    }

    func testRewriteRulesForbidWeakeningAndNoOps() {
        let brief = TailoringBrief.parse(from: #"{"candidate_story": "Systems-leaning iOS engineer"}"#)!
        let prompt = PromptBuilder.tailoringBuildPrompt(
            brief: brief, application: JobApplication(companyName: "Example", jobTitle: "iOS Engineer"),
            allExperiences: [], employments: [], globalSkillsBlock: ""
        )
        XCTAssertTrue(prompt.contains("keep a result in the opening"))
        XCTAssertTrue(prompt.contains("Never drop a verified number"))
        XCTAssertTrue(prompt.contains("Re-stating the bullet unchanged is not a rewrite"))
    }

    func testBuildPromptCarriesTheFactsAndTheCandidatesDirection() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: """
        { "recalled_facts": [{ "fact": "Owned the iOS release pipeline", "relevance": "Platform ownership" }] }
        """))
        brief.buildNotes = "Fold the Protocol Buffers detail into the Tuya bullet; don't give it its own line."

        let prompt = PromptBuilder.tailoringBuildPrompt(
            brief: brief, application: JobApplication(companyName: "Example", jobTitle: "iOS Engineer"),
            allExperiences: [], employments: [], globalSkillsBlock: ""
        )
        XCTAssertTrue(prompt.contains("Owned the iOS release pipeline"))
        XCTAssertTrue(prompt.contains("Fold the Protocol Buffers detail"))
        XCTAssertTrue(prompt.contains("Prefer folding a fact into an existing bullet"))
        XCTAssertTrue(prompt.contains("A small detail is not a bullet"))
    }

    func testClarifyPromptForbidsDraftingBullets() throws {
        let brief = try XCTUnwrap(TailoringBrief.parse(from: #"{"candidate_story": "Systems-leaning iOS engineer"}"#))
        let prompt = PromptBuilder.tailoringClarifyPrompt(
            brief: brief, answered: [], application: JobApplication(),
            allExperiences: [], employments: [], probeGaps: false
        )
        XCTAssertTrue(prompt.contains("Record the fact, not a résumé line"))
        XCTAssertTrue(prompt.contains("recalled_facts"))
        XCTAssertFalse(prompt.contains("résumé-ready bullet"), "Clarify must not ask for wording at all")
    }

    func testRepeatedQuestionsAreRefused() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: """
        { "gaps": [{ "id": "ide", "kind": "genuine", "text": "No IDE extension work" }],
          "questions": [
            { "kind": "recall", "gap_id": "ide", "question": "Have you built or shipped any VS Code, Cursor, JetBrains, Xcode, language-server, editor-automation, or agent-hook integration, even internally or as a prototype?" },
            { "kind": "verify", "question": "Are you currently based in and authorized to work from Canada or the United States without a location change?" }
          ] }
        """))
        brief.setAnswer("no", for: try XCTUnwrap(brief.questions.first?.id))

        // The rephrased versions the model actually produced in the field.
        let result = brief.apply(try XCTUnwrap(TailoringClarification.parse(from: """
        { "new_questions": [
            { "kind": "recall", "gap_id": "ide", "question": "Have you built or shipped an extension, plugin, or agent hook for Cursor, VS Code, JetBrains, Xcode, or another IDE? If yes, which IDE, what did it do, and was it used by anyone beyond you?" },
            { "kind": "verify", "question": "Do you currently reside in Canada or the United States, and are you authorized to work there without employer sponsorship?" },
            { "kind": "recall", "question": "What was the largest dataset you have processed, and with what tooling?" }
        ] }
        """)))

        // The IDE rephrase is caught as a duplicate; the work-authorization
        // rephrase never gets that far — it's refused as logistics first.
        XCTAssertEqual(result.skippedDuplicates, 1)
        XCTAssertEqual(result.skippedLogistical, 1)
        XCTAssertEqual(result.appendedQuestions, 1)
        XCTAssertEqual(brief.questions.count, 3)
        XCTAssertEqual(brief.questions.last?.question.prefix(20), "What was the largest")
    }

    func testAGapAlreadyAskedAboutIsNotOfferedForProbingAgain() throws {
        let brief = try XCTUnwrap(TailoringBrief.parse(from: """
        { "gaps": [
            { "id": "ide", "kind": "genuine", "text": "No IDE extension work" },
            { "id": "streaming", "kind": "genuine", "text": "No streaming infrastructure" },
            { "id": "polish", "kind": "presentation", "text": "Impact is buried" }
          ],
          "questions": [{ "kind": "recall", "gap_id": "ide", "question": "Any IDE extensions?" }] }
        """))
        XCTAssertEqual(brief.probedGapIDs, ["ide"])
        XCTAssertEqual(brief.unprobedGenuineGaps.map(\.id), ["streaming"],
                       "Presentation gaps aren't probed, and 'ide' already has a question")
    }

    func testLogisticalQuestionsAreRefused() throws {
        // The one from the field, plus its neighbours.
        let logistical = [
            "Are you legally eligible to work in Canada and willing to meet an onsite or hybrid requirement in Toronto if DoorDash confirms one?",
            "Would you need visa sponsorship for this role?",
            "Are you willing to relocate to Seattle?",
            "What are your salary expectations?",
            "What is your notice period, and when could you start?",
            "How interested are you in this company specifically?"
        ]
        for question in logistical {
            XCTAssertTrue(QuestionRelevance.isLogistical(question), "Should be refused: \(question)")
        }

        // Technical questions that happen to contain nearby words must survive.
        let technical = [
            "Did you build the remote debugging bridge yourself, or extend an existing one?",
            "What start-up latency did the service hold at peak?",
            "Which parts of the migration did you personally own?",
            "Have you operated a streaming pipeline in production?"
        ]
        for question in technical {
            XCTAssertFalse(QuestionRelevance.isLogistical(question), "Should be kept: \(question)")
        }
    }

    func testLogisticalFollowUpsAreDroppedWithoutCostingTheGoodOnes() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: #"{"candidate_story": "Systems-leaning iOS engineer"}"#))
        let result = brief.apply(try XCTUnwrap(TailoringClarification.parse(from: """
        { "new_questions": [
            { "kind": "verify", "question": "Are you authorized to work in the United States without sponsorship?" },
            { "kind": "recall", "question": "What throughput did the ingest pipeline sustain?" }
        ] }
        """)))

        XCTAssertEqual(result.skippedLogistical, 1)
        XCTAssertEqual(result.appendedQuestions, 1)
        XCTAssertEqual(brief.questions.map(\.question), ["What throughput did the ingest pipeline sustain?"])
    }

    func testAFreshBriefDropsLogisticalQuestionsBeforeItIsShown() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: """
        { "fit_score": 7,
          "questions": [
            { "kind": "verify", "question": "Are you legally eligible to work in Canada?" },
            { "kind": "fact", "question": "Who owned the rollout end to end?" }
          ] }
        """))
        brief.dropLogisticalQuestions()
        XCTAssertEqual(brief.questions.map(\.question), ["Who owned the rollout end to end?"])
    }

    func testPromptsForbidLogisticalQuestions() {
        var application = JobApplication(companyName: "Example", jobTitle: "iOS Engineer")
        application.jobDescription = "Build the iOS app."
        let brief = PromptBuilder.tailoringBriefPrompt(
            application: application, allExperiences: [], employments: [],
            masterResume: nil, globalSkillsBlock: "", canResearch: false
        )
        XCTAssertTrue(brief.contains("Never ask about work authorization"))
        XCTAssertTrue(brief.contains("record it as a gap instead"))
    }

    func testDistinctQuestionsAboutTheSameAreaAreKept() {
        XCTAssertFalse(QuestionSimilarity.areEquivalent(
            "Have you shipped a VS Code extension?",
            "Did you own the release process for that extension, or did someone else?"
        ))
        XCTAssertTrue(QuestionSimilarity.areEquivalent(
            "For Parma, did you review external pull requests, triage issues, publish releases or migration notes, maintain user documentation, or support adopters publicly?",
            "For Parma or another public repository, have you personally triaged user issues, reviewed external pull requests, maintained releases or changelogs, supported users, or participated in public design discussions?"
        ))
    }

    func testAnswersQueueByWhetherTheyWereSentNotByRound() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: """
        { "questions": [
            { "kind": "fact", "question": "Who owned the rollout?" },
            { "kind": "recall", "question": "Any streaming pipelines?" }
          ] }
        """))
        let first = try XCTUnwrap(brief.questions.first?.id)
        let second = try XCTUnwrap(brief.questions.last?.id)

        // Answer one, send it, and take a follow-up round.
        brief.setAnswer("I did.", for: first)
        XCTAssertEqual(brief.pendingAnswers.count, 1)
        brief.markAnswersSent([first])
        brief.apply(try XCTUnwrap(TailoringClarification.parse(from: """
        { "new_questions": [{ "kind": "fact", "question": "How large was the fleet you migrated?" }] }
        """)))
        XCTAssertTrue(brief.pendingAnswers.isEmpty)

        // Now answer the *earlier* question. Round 1 < clarifyRound 1, but it has
        // never been sent, so it must still queue — this is what made the loop
        // feel like a single shot.
        brief.setAnswer("Yes, at Example Corp.", for: second)
        XCTAssertEqual(brief.pendingAnswers.map(\.id), [second])

        // Editing an already-sent answer re-queues it too.
        brief.setAnswer("I did, with two reviewers.", for: first)
        XCTAssertEqual(Set(brief.pendingAnswers.map(\.id)), [first, second])

        // Re-setting the identical text is not a change and must not re-queue.
        brief.markAnswersSent([first, second])
        brief.setAnswer("I did, with two reviewers.", for: first)
        XCTAssertTrue(brief.pendingAnswers.isEmpty)
    }

    func testReAnalysingKeepsTheAnswersYouAlreadyTyped() throws {
        var previous = try XCTUnwrap(TailoringBrief.parse(from: """
        { "questions": [
            { "kind": "recall", "question": "Have you built or shipped an IDE extension for VS Code, Cursor, or Xcode?" },
            { "kind": "fact", "question": "Who owned the migration end to end?" },
            { "kind": "fact", "question": "Never answered this one" }
          ] }
        """))
        previous.setAnswer("no", for: try XCTUnwrap(previous.questions.first?.id))
        previous.setAnswer("I did.", for: try XCTUnwrap(previous.questions.dropFirst().first?.id))

        // A fresh judgement asks one of them again in different words.
        var fresh = try XCTUnwrap(TailoringBrief.parse(from: """
        { "fit_score": 7,
          "questions": [
            { "kind": "recall", "question": "Have you shipped an extension or plugin for VS Code, Cursor, JetBrains, or Xcode?" },
            { "kind": "recall", "question": "Any production streaming work?" }
          ] }
        """))
        fresh.carryOverAnswers(from: previous)

        XCTAssertEqual(fresh.questions.count, 3, "Two fresh questions plus the unmatched answered one")
        // Answered history first, then the questions still to answer — the same
        // direction the clarify loop appends in.
        XCTAssertEqual(fresh.questions.first?.answer, "I did.", "Carried-over history leads")
        XCTAssertEqual(fresh.questions.dropFirst().first?.answer, "no", "The re-asked question keeps its answer")
        XCTAssertEqual(fresh.questions.last?.answer, "", "A genuinely new question is last, and blank")
        XCTAssertFalse(fresh.questions.contains { $0.question == "Never answered this one" },
                       "Stale unanswered questions are not carried over")
    }

    func testTheLoopAllowsSeveralRounds() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: #"{"candidate_story": "Systems-leaning iOS engineer"}"#))
        XCTAssertGreaterThanOrEqual(TailoringBrief.maxClarifyRounds, 3)
        for round in 1..<TailoringBrief.maxClarifyRounds {
            brief.apply(TailoringClarification())
            XCTAssertTrue(brief.canClarifyFurther, "Round \(round) must not end the conversation")
        }
    }

    func testClarifyRoundsAreCapped() throws {
        var brief = try XCTUnwrap(TailoringBrief.parse(from: #"{"candidate_story": "Systems-leaning iOS engineer"}"#))
        XCTAssertTrue(brief.canClarifyFurther)
        for _ in 0..<TailoringBrief.maxClarifyRounds {
            brief.apply(TailoringClarification())
        }
        XCTAssertEqual(brief.clarifyRound, TailoringBrief.maxClarifyRounds)
        XCTAssertFalse(brief.canClarifyFurther)
    }

    // MARK: - Stage 2 plan

    func testExtendedPlanDecodesAndOldPlansStillDo() throws {
        let bulletID = UUID()
        let extended = try XCTUnwrap(TailoringPlan.parse(from: """
        {
          "summary": "Systems-leaning iOS engineer",
          "summary_rationale": [
            { "phrase": "iOS engineer", "evidence": "6 years shipping", "signal": "Core requirement", "why_it_earns_space": "Establishes identity first" }
          ],
          "deliberately_omitted": "Left out the graphics work",
          "replacements": [
            { "experience_id": "\(bulletID.uuidString)", "text": "Cut cold start 40%", "reason": "Leads with the result",
              "signal": "Impact", "confirmation_needed": "Was it 40% or 45%?" }
          ],
          "drops": [{ "experience_id": "\(bulletID.uuidString)", "reason": "Redundant with the launch bullet" }],
          "readiness": "Needs factual confirmation",
          "uncertainties": ["Cold start figure"]
        }
        """))
        XCTAssertEqual(extended.summaryRationale?.count, 1)
        XCTAssertEqual(extended.deliberatelyOmitted, "Left out the graphics work")
        XCTAssertEqual(extended.replacements?.first?.signal, "Impact")
        XCTAssertEqual(extended.replacements?.first?.confirmationNeeded, "Was it 40% or 45%?")
        XCTAssertEqual(extended.drops?.first?.experienceID, bulletID)
        XCTAssertEqual(TailoringReadiness(rawValue: try XCTUnwrap(extended.readiness)), .needsConfirmation)

        // A plan persisted before these fields existed must still load.
        let legacy = try XCTUnwrap(TailoringPlan.parse(from: """
        { "summary": "Older plan", "ordered_experience_ids": ["\(bulletID.uuidString)"] }
        """))
        XCTAssertNil(legacy.summaryRationale)
        XCTAssertNil(legacy.readiness)
        XCTAssertEqual(legacy.orderedExperienceIDs, [bulletID])
        XCTAssertFalse(legacy.isEmpty)

        // Commentary alone is not an edit to review.
        let commentaryOnly = try XCTUnwrap(TailoringPlan.parse(from: #"{"readiness": "Ready to submit"}"#))
        XCTAssertTrue(commentaryOnly.isEmpty)
    }

    func testPlanWithNoDecodableObjectIsRejected() {
        XCTAssertNil(TailoringPlan.parse(from: "I couldn't produce a plan for this role."))
        XCTAssertNil(TailoringBrief.parse(from: "No JSON here."))
    }

    // MARK: - Tolerating real replies

    func testOneMalformedEntryDoesNotCostTheWholeBrief() throws {
        // The second gap has no `text`, the second question no `question`, and
        // the score is quoted — none of which should sink the rest.
        let brief = try XCTUnwrap(TailoringBrief.parse(from: """
        {
          "fit_score": "7.5/10",
          "candidate_story": "Systems-leaning iOS engineer",
          "gaps": [
            { "id": "kafka", "kind": "genuine", "text": "No streaming work" },
            { "id": "broken", "kind": "genuine" }
          ],
          "questions": [
            { "kind": "fact", "question": "Who owned the rollout?" },
            { "kind": "recall" }
          ],
          "strong_matches": [{ "claim": "Ships performance work", "experience_id": "not-a-uuid" }]
        }
        """))
        XCTAssertEqual(brief.fitScore, 7.5)
        XCTAssertEqual(brief.gaps.map(\.id), ["kafka"])
        XCTAssertEqual(brief.questions.count, 1)
        XCTAssertEqual(brief.strongMatches.count, 1)
        XCTAssertNil(brief.strongMatches.first?.experienceID, "A garbled id is dropped, not fatal")
    }

    func testGapWithoutAnIDGetsAStableOneDerivedFromItsText() throws {
        let brief = try XCTUnwrap(TailoringBrief.parse(from: """
        { "gaps": [{ "kind": "genuine", "text": "No Kubernetes operations experience" }] }
        """))
        let gap = try XCTUnwrap(brief.gaps.first)
        XCTAssertEqual(gap.id, "no-kubernetes-operations-experience")
        XCTAssertEqual(gap.gapKind, .genuine)

        // The same text decodes to the same id, so a clarify round can still
        // retire the gap it resolves.
        let again = try XCTUnwrap(TailoringBrief.parse(from: """
        { "gaps": [{ "kind": "presentation", "text": "No Kubernetes operations experience" }] }
        """))
        XCTAssertEqual(again.gaps.first?.id, gap.id)
    }

    func testUnknownGapKindDegradesInsteadOfFailing() throws {
        let brief = try XCTUnwrap(TailoringBrief.parse(from: """
        { "gaps": [{ "id": "x", "kind": "maybe-a-problem", "text": "Unclear" }] }
        """))
        XCTAssertEqual(brief.gaps.first?.gapKind, .unknown)
    }

    func testRepliesThatBuryTheJSONInProseOrFencesStillParse() throws {
        let leadingProse = try XCTUnwrap(TailoringBrief.parse(from: """
        I looked at this role. My reasoning uses {curly braces} in passing, then:

        {"fit_score": 6, "candidate_story": "Backend-leaning"}

        Happy to build the résumé next.
        """))
        XCTAssertEqual(leadingProse.fitScore, 6)
        XCTAssertEqual(leadingProse.candidateStory, "Backend-leaning")

        let fencedAfterProse = try XCTUnwrap(TailoringBrief.parse(from: """
        Here you go:
        ```json
        {"fit_score": 8, "candidate_story": "iOS platform engineer"}
        ```
        """))
        XCTAssertEqual(fencedAfterProse.fitScore, 8)

        // Two objects: the real payload wins over a stray fragment, where the
        // old first-brace-to-last-brace span would have parsed as neither.
        let twoObjects = try XCTUnwrap(TailoringBrief.parse(from: """
        {"note": "ignore me"}
        {"fit_score": 9, "candidate_story": "Distributed systems engineer", "gaps": [{"id": "a", "kind": "genuine", "text": "No Go"}]}
        """))
        XCTAssertEqual(twoObjects.fitScore, 9)
        XCTAssertEqual(twoObjects.gaps.count, 1)
    }

    func testAnEmptyOrContentlessObjectIsNotAccepted() {
        XCTAssertNil(TailoringBrief.parse(from: "Sorry, I can't help with that. {}"))
        XCTAssertNil(TailoringBrief.parse(from: #"{"unrelated": "value"}"#))
    }

    func testPlanTolerateMalformedReplacementsAndQuotedIDs() throws {
        let good = UUID()
        let plan = try XCTUnwrap(TailoringPlan.parse(from: """
        {
          "summary": "Systems-leaning iOS engineer",
          "replacements": [
            { "experience_id": "\(good.uuidString)", "text": "Cut cold start 40%" },
            { "text": "No id, so unusable" },
            { "experience_id": "nope", "text": "Bad id" }
          ],
          "drops": [{ "reason": "no id here" }]
        }
        """))
        XCTAssertEqual(plan.replacements?.count, 1)
        XCTAssertEqual(plan.replacements?.first?.experienceID, good)
        XCTAssertNil(plan.drops, "A drop with no id is unusable, and none survived")
    }

    func testGarbledIDListsLeaveTheSelectionAloneRatherThanEmptyingIt() throws {
        let good = UUID()
        let mixed = try XCTUnwrap(TailoringPlan.parse(from: """
        { "ordered_experience_ids": ["\(good.uuidString)", "bullet-3", ""] }
        """))
        XCTAssertEqual(mixed.orderedExperienceIDs, [good], "Usable ids survive; junk is dropped")

        let allJunk = try XCTUnwrap(TailoringPlan.parse(from: """
        { "summary": "Still usable", "ordered_experience_ids": ["bullet-1", "bullet-2"] }
        """))
        XCTAssertNil(allJunk.orderedExperienceIDs,
                     "No parseable id means 'unspecified' — never 'deselect everything'")
        XCTAssertEqual(allJunk.summary, "Still usable")

        let explicitlyEmpty = try XCTUnwrap(TailoringPlan.parse(from: """
        { "summary": "Drop the projects", "ordered_project_ids": [] }
        """))
        XCTAssertEqual(explicitlyEmpty.orderedProjectIDs, [], "An explicit empty list is a real instruction")
    }

    // MARK: - Application-scoped bullets

    func testScopedBulletsAreVisibleOnlyInsideTheirOwnApplication() {
        let applicationID = UUID()
        let otherApplicationID = UUID()
        let shared = ExperienceBullet(bulletText: "Shared bullet")
        let mine = ExperienceBullet(bulletText: "Recalled here", owningApplicationID: applicationID)
        let theirs = ExperienceBullet(bulletText: "Recalled elsewhere", owningApplicationID: otherApplicationID)
        let all = [shared, mine, theirs]

        XCTAssertEqual(ExperienceScope.visible(all, to: applicationID).map(\.id), [shared.id, mine.id])
        XCTAssertEqual(ExperienceScope.shared(all).map(\.id), [shared.id])
        XCTAssertEqual(ExperienceScope.owned(by: otherApplicationID, in: all).map(\.id), [theirs.id])
        XCTAssertFalse(shared.isApplicationScoped)
        XCTAssertTrue(mine.isApplicationScoped)
    }

    func testScopedVariantsAreHiddenFromOtherApplications() {
        let applicationID = UUID()
        var bullet = ExperienceBullet(bulletText: "Base")
        let sharedVariant = ExperienceVariation(name: "Shared", bulletText: "Shared wording")
        let privateVariant = ExperienceVariation(name: "Private", bulletText: "Private wording",
                                                 owningApplicationID: applicationID)
        bullet.variations = [sharedVariant, privateVariant]

        XCTAssertEqual(bullet.variations(visibleTo: applicationID).map(\.id), [sharedVariant.id, privateVariant.id])
        XCTAssertEqual(bullet.variations(visibleTo: UUID()).map(\.id), [sharedVariant.id])
        XCTAssertEqual(bullet.variations(visibleTo: nil).map(\.id), [sharedVariant.id])
    }

    func testScopeRoundTripsThroughTheWorkspaceDTO() throws {
        let applicationID = UUID()
        var bullet = ExperienceBullet(bulletText: "Recalled here", owningApplicationID: applicationID)
        bullet.variations = [
            ExperienceVariation(name: "Private", bulletText: "Private wording", owningApplicationID: applicationID),
            ExperienceVariation(name: "Shared", bulletText: "Shared wording")
        ]

        let restored = WorkspaceFiles.makeExperience(from: WorkspaceFiles.experienceDTO(from: bullet))
        XCTAssertEqual(restored.owningApplicationID, applicationID)
        XCTAssertEqual(restored.variations.first?.owningApplicationID, applicationID)
        XCTAssertNil(restored.variations.last?.owningApplicationID)
    }

    // MARK: - Concurrent runs

    func testActivityMonitorTracksSeveralRunsAtOnce() {
        let monitor = AppActivityMonitor()
        monitor.start("Judging fit — Acme…", key: "brief:acme")
        monitor.start("Judging fit — Globex…", key: "brief:globex")

        XCTAssertEqual(monitor.runningCount, 2)
        XCTAssertTrue(monitor.isRunning(key: "brief:acme"))

        monitor.succeed("Acme: brief ready.", key: "brief:acme")
        XCTAssertEqual(monitor.state, .running, "The other run is still going")
        XCTAssertEqual(monitor.runningCount, 1)
        XCTAssertFalse(monitor.isRunning(key: "brief:acme"))
        XCTAssertEqual(monitor.history.first?.message, "Acme: brief ready.")

        monitor.fail("Globex: couldn't read the brief.", key: "brief:globex")
        XCTAssertEqual(monitor.state, .failure)
        XCTAssertEqual(monitor.runningCount, 0)
        XCTAssertEqual(monitor.history.count, 2, "Both outcomes are recorded, not just the last")
    }

    func testFinishingAnUnknownKeyDoesNotStrandARun() {
        let monitor = AppActivityMonitor()
        monitor.start("Working…", key: "a")
        monitor.succeed("Done", key: "not-a-real-key")
        XCTAssertEqual(monitor.runningCount, 1, "An unmatched key must not close someone else's run")
        monitor.succeed("Done", key: "a")
        XCTAssertEqual(monitor.runningCount, 0)
    }

    /// A key-less finish used to close the *oldest* run, whichever it was. With
    /// a keyed discovery sweep running behind a key-less import, the import's
    /// success closed the sweep, and the sweep's own keyed finish then matched
    /// nothing — leaving "Importing job posting…" spinning forever.
    func testAKeylessFinishCannotCloseAKeyedRun() {
        let monitor = AppActivityMonitor()
        monitor.start("Checking boards for new jobs…", key: "discovery-refresh")
        monitor.start("Importing job posting…")           // key-less, started second
        XCTAssertEqual(monitor.runningCount, 2)

        monitor.succeed("Job posting ready to review.")   // key-less finish
        XCTAssertEqual(monitor.runningCount, 1)
        XCTAssertTrue(monitor.isRunning(key: "discovery-refresh"),
                      "The key-less finish closes the import, not the keyed sweep")

        monitor.succeed("Found 3 new postings.", key: "discovery-refresh")
        XCTAssertEqual(monitor.runningCount, 0, "Nothing is left spinning")
        XCTAssertEqual(monitor.state, .success)
    }

    /// The key `start` hands back finishes that exact operation, even when it
    /// was started without one.
    func testStartReturnsAKeyThatClosesThatRun() {
        let monitor = AppActivityMonitor()
        let first = monitor.start("Importing job posting…")
        let second = monitor.start("Parsing pasted job description…")
        XCTAssertEqual(monitor.runningCount, 2)

        monitor.succeed("Parsed.", key: second)
        XCTAssertEqual(monitor.runningCount, 1)
        monitor.succeed("Imported.", key: first)
        XCTAssertEqual(monitor.runningCount, 0)
    }

    func testRunnerTracksJobsPerApplication() {
        let runner = TailoringRunner()
        let acme = UUID()
        let globex = UUID()
        XCTAssertFalse(runner.isBusy(acme))

        runner.beginForTesting(.brief, for: acme)
        runner.beginForTesting(.build, for: globex)
        XCTAssertTrue(runner.isRunning(.brief, for: acme))
        XCTAssertFalse(runner.isRunning(.build, for: acme))
        XCTAssertEqual(runner.busyApplicationIDs, [acme, globex])

        runner.endForTesting(.brief, for: acme)
        XCTAssertFalse(runner.isBusy(acme))
        XCTAssertEqual(runner.busyApplicationIDs, [globex])
    }

    // MARK: - Prompts

    func testBriefPromptCarriesRealIDsAndTheResearchDecision() {
        var application = JobApplication(companyName: "Example", jobTitle: "iOS Engineer")
        application.jobDescription = "Build the iOS app."
        application.jobURL = "https://example.com/jobs/1"
        let bullet = ExperienceBullet(bulletText: "Cut cold start 40%")

        let researching = PromptBuilder.tailoringBriefPrompt(
            application: application, allExperiences: [bullet], employments: [],
            masterResume: nil, globalSkillsBlock: "", canResearch: true
        )
        XCTAssertTrue(researching.contains(bullet.id.uuidString), "The pool must carry ids the reply can reference")
        XCTAssertTrue(researching.contains("https://example.com/jobs/1"))
        XCTAssertTrue(researching.contains("research_notes"))

        let offline = PromptBuilder.tailoringBriefPrompt(
            application: application, allExperiences: [bullet], employments: [],
            masterResume: nil, globalSkillsBlock: "", canResearch: false
        )
        XCTAssertTrue(offline.contains("Not available for this run"))
    }

    func testResearchCoversTheSkillsReferenceSourcesAsWellAsThePosting() {
        var application = JobApplication(companyName: "Example", jobTitle: "iOS Engineer")
        application.jobDescription = "Build the iOS app."

        // No posting URL: the reference guidance is still worth reading, so the
        // run must not fall back to "no research".
        let noURL = PromptBuilder.tailoringBriefPrompt(
            application: application, allExperiences: [], employments: [],
            masterResume: nil, globalSkillsBlock: "", canResearch: true
        )
        XCTAssertFalse(noURL.contains("Not available for this run"))
        XCTAssertTrue(noURL.contains("No posting URL was saved"))
        for source in PromptBuilder.referenceSources {
            XCTAssertTrue(noURL.contains(source), "Missing reference source: \(source)")
        }

        // The handbook argues for one page; the candidate's cap is two, and a
        // fetched page must not be allowed to override it.
        XCTAssertTrue(noURL.contains("the two-page budget"))
        XCTAssertTrue(noURL.contains("search for it instead of giving up"),
                      "A blocked fetch has to have a stated fallback")
    }

    func testBuildPromptPreservesTheApplicationsSkillsTemplate() throws {
        var application = JobApplication(companyName: "Example", jobTitle: "iOS Engineer")
        application.skillsBlockText = "\\textbf{Languages:} & Swift, C++ \\\\"
        let brief = try XCTUnwrap(TailoringBrief.parse(from: #"{"candidate_story": "Systems-leaning iOS engineer"}"#))

        let prompt = PromptBuilder.tailoringBuildPrompt(
            brief: brief, application: application, allExperiences: [], employments: [], globalSkillsBlock: "ignored"
        )
        XCTAssertTrue(prompt.contains("\\textbf{Languages:} & Swift, C++"))
        XCTAssertTrue(prompt.contains("Systems-leaning iOS engineer"))
        XCTAssertFalse(prompt.contains("ignored"), "The application's own block wins over the global one")
    }

    func testCurationPromptTargetsTheBriefsGaps() throws {
        let application = JobApplication(companyName: "Example", jobTitle: "iOS Engineer")
        let brief = try XCTUnwrap(TailoringBrief.parse(from: """
        { "gaps": [
            { "id": "kafka", "kind": "genuine", "text": "No streaming infrastructure" },
            { "id": "metrics", "kind": "presentation", "text": "Impact is buried" }
        ] }
        """))

        let prompt = PromptBuilder.bulletCurationPrompt(
            application: application, allExperiences: [], employments: [], brief: brief
        )
        XCTAssertTrue(prompt.contains("No streaming infrastructure"))
        XCTAssertFalse(prompt.contains("Impact is buried"),
                       "Presentation gaps are a tailoring problem, not something to develop new experience for")
    }
}
