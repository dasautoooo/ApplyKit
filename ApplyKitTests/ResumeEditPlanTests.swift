import XCTest
@testable import ApplyKit

/// The pasted Resume Edit Plan v1.0: read as-is, never guessed at. Every test
/// builds the plan as a dictionary so each case changes one thing.
@MainActor
final class ResumeEditPlanTests: XCTestCase {

    // MARK: - Fixture

    private let acme = Employment(companyName: "Acme", role: "iOS Engineer", displayOrder: 0,
                                  roleDescription: "Led the iOS team.")
    private let globex = Employment(companyName: "Globex", role: "Engineer", displayOrder: 1)
    private var a1 = ExperienceBullet(bulletText: "Acme one.")
    private var a2 = ExperienceBullet(bulletText: "Acme two.")
    private var a3 = ExperienceBullet(bulletText: "Acme three.")
    private var g1 = ExperienceBullet(bulletText: "Globex one.")
    private var g2 = ExperienceBullet(bulletText: "Globex two.")
    private var project = ExperienceBullet(experienceType: "Project", projectName: "Side App",
                                           bulletText: "Shipped a side app.")

    override func setUp() {
        super.setUp()
        a1.employmentID = acme.id
        a2.employmentID = acme.id
        a3.employmentID = acme.id
        g1.employmentID = globex.id
        g2.employmentID = globex.id
    }

    private var context: ResumeEditPlanContext {
        ResumeEditPlanContext(experiences: [a1, a2, a3, g1, g2, project], employments: [acme, globex],
                              hasSummary: true, hasEducation: true)
    }

    private func bullet(_ item: ExperienceBullet, _ action: String, order: Int? = nil,
                        title: String? = nil, text: String? = nil) -> [String: Any] {
        ["id": item.id.uuidString, "action": action,
         "order": order.map { $0 as Any } ?? NSNull(),
         "variant_title": title.map { $0 as Any } ?? NSNull(),
         "text": text.map { $0 as Any } ?? NSNull()]
    }

    /// The canonical example, against the fixture's real ids.
    private func canonicalPlan() -> [String: Any] {
        [
            "schema_version": "1.0",
            "fit_score": 8.5,
            "section_order": ["education", "skills", "experience", "projects"],
            "summary": ["action": "drop", "text": NSNull()],
            "skills": [
                "action": "replace",
                "content_width": "0.74\\textwidth",
                "rows": [
                    ["label": "Languages", "items": ["Swift", "Objective-C", "C++"]],
                    ["label": "iOS", "items": ["UIKit", "SwiftUI", "Combine"]],
                    ["label": "Engineering", "items": ["R&D", "snake_case tooling", "CI/CD"]]
                ]
            ],
            "experience": [
                bullet(a2, "keep", order: 1),
                bullet(a1, "rewrite", order: 2, title: "Build Reliability and Swift Tooling",
                       text: "Reduced CI failures 70% across 20+ apps."),
                bullet(a3, "drop"),
                bullet(g1, "keep", order: 1),
                bullet(g2, "drop")
            ],
            "projects": [bullet(project, "keep", order: 1)],
            "role_descriptions": [[String: Any]]()
        ]
    }

    private func role(_ employment: Employment, _ action: String, order: Int? = nil,
                      text: String? = nil) -> [String: Any] {
        ["employment_id": employment.id.uuidString, "action": action,
         "order": order.map { $0 as Any } ?? NSNull(),
         "text": text.map { $0 as Any } ?? NSNull()]
    }

    private func json(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
    }

    private func importing(_ object: [String: Any], context: ResumeEditPlanContext? = nil)
        -> ResumeEditPlanImporter.Result {
        ResumeEditPlanImporter.importPlan(from: json(object), context: context ?? self.context)
    }

    private func codes(_ result: ResumeEditPlanImporter.Result) -> [String] { result.errors.map(\.code) }

    private func paths(_ result: ResumeEditPlanImporter.Result) -> [String] { result.errors.map(\.path) }

    /// Sets `value` at a dictionary path like `["summary", "text"]`.
    private func with(_ plan: [String: Any], _ keys: [String], _ value: Any?) -> [String: Any] {
        var plan = plan
        guard let first = keys.first else { return plan }
        if keys.count == 1 {
            plan[first] = value
        } else {
            plan[first] = with(plan[first] as? [String: Any] ?? [:], Array(keys.dropFirst()), value)
        }
        return plan
    }

    private func withBullet(_ plan: [String: Any], section: String = "experience", at index: Int,
                            _ key: String, _ value: Any) -> [String: Any] {
        var plan = plan
        var edits = plan[section] as! [[String: Any]]
        edits[index][key] = value
        plan[section] = edits
        return plan
    }

    // MARK: - Accepted shapes

    func testTheCanonicalPlanImportsCleanly() throws {
        let result = importing(canonicalPlan())
        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.fitScore, 8.5)
        XCTAssertNotNil(result.plan)
    }

    func testKeptAndReplacedSummariesAreAccepted() {
        var kept = with(canonicalPlan(), ["summary"], ["action": "keep", "text": NSNull()])
        kept["section_order"] = ["summary", "education", "skills", "experience", "projects"]
        XCTAssertEqual(codes(importing(kept)), [])
        XCTAssertNil(importing(kept).plan?.summary, "keep leaves the summary alone")

        var replaced = with(canonicalPlan(), ["summary"], ["action": "replace", "text": "iOS engineer."])
        replaced["section_order"] = ["summary", "education", "skills", "experience", "projects"]
        XCTAssertEqual(importing(replaced).plan?.summary, "iOS engineer.")
    }

    func testEmptyProjectsLeftOutOfSectionOrderIsAccepted() {
        var plan = canonicalPlan()
        plan["projects"] = [[String: Any]]()
        plan["section_order"] = ["education", "skills", "experience"]
        XCTAssertEqual(codes(importing(plan)), [])
    }

    // MARK: - Extraction

    func testAFencedPlanInsideProseIsFound() {
        let reply = """
        Here's my read: this is a strong match. The "Swift" work carries it.

        ```json
        \(json(canonicalPlan()))
        ```

        Good luck!
        """
        XCTAssertNotNil(ResumeEditPlanImporter.importPlan(from: reply, context: context).plan)
    }

    func testTwoPlansNoJSONAndOversizedInputAreRejected() {
        let two = json(canonicalPlan()) + "\n\n" + json(canonicalPlan())
        XCTAssertEqual(codes(ResumeEditPlanImporter.importPlan(from: two, context: context)), ["payload.multiple_plans"])

        XCTAssertEqual(codes(ResumeEditPlanImporter.importPlan(from: "Looks good, keep everything.", context: context)),
                       ["payload.no_json"])

        XCTAssertEqual(codes(ResumeEditPlanImporter.importPlan(from: #"{"summary": "old format"}"#, context: context)),
                       ["payload.no_plan"])

        let truncated = String(json(canonicalPlan()).dropLast(20))
        XCTAssertEqual(codes(ResumeEditPlanImporter.importPlan(from: truncated, context: context)), ["payload.truncated"])

        let huge = json(canonicalPlan()) + String(repeating: " ", count: ResumeEditPlanImporter.maxPayloadBytes)
        XCTAssertEqual(codes(ResumeEditPlanImporter.importPlan(from: huge, context: context)), ["payload.too_large"])
    }

    // MARK: - Schema

    func testVersionAndScoreAreChecked() {
        XCTAssertEqual(codes(importing(with(canonicalPlan(), ["schema_version"], nil))), ["payload.no_plan"],
                       "Without a version there's no telling it's a plan at all")
        XCTAssertEqual(codes(importing(with(canonicalPlan(), ["schema_version"], "2.0"))), ["schema.version"])
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["fit_score"], -1))), ["/fit_score"])
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["fit_score"], 11))), ["/fit_score"])
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["fit_score"], "8"))), ["/fit_score"])
    }

    func testUnknownFieldsAreRejectedAtEveryLevel() {
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["rationale"], "Because."))), ["/rationale"])
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["summary", "why"], "x"))), ["/summary/why"])
        XCTAssertEqual(paths(importing(withBullet(canonicalPlan(), at: 0, "reason", "x"))), ["/experience/0/reason"])
    }

    func testDuplicateSectionKeysAreRejected() {
        let result = importing(with(canonicalPlan(), ["section_order"],
                                    ["education", "skills", "experience", "skills", "projects"]))
        XCTAssertEqual(paths(result), ["/section_order/3"])
    }

    func testSkillsMustBeThreeRowsAtTheFixedWidth() {
        let rows = (canonicalPlan()["skills"] as! [String: Any])["rows"] as! [Any]
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["skills", "rows"], Array(rows.prefix(2))))),
                       ["/skills/rows"])
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["skills", "rows"],
                                            rows + [["label": "More", "items": ["Go"]]]))),
                       ["/skills/rows"])
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["skills", "content_width"], "0.72\\textwidth"))),
                       ["/skills/content_width"])
    }

    func testFieldsMustMatchTheirAction() {
        // keep with rewrite text
        XCTAssertEqual(paths(importing(withBullet(canonicalPlan(), at: 0, "text", "New words."))),
                       ["/experience/0/text"])
        // rewrite without title, text, or order
        XCTAssertEqual(paths(importing(withBullet(canonicalPlan(), at: 1, "variant_title", NSNull()))),
                       ["/experience/1/variant_title"])
        XCTAssertEqual(paths(importing(withBullet(canonicalPlan(), at: 1, "text", NSNull()))),
                       ["/experience/1/text"])
        XCTAssertEqual(paths(importing(withBullet(canonicalPlan(), at: 1, "order", NSNull()))),
                       ["/experience/1/order"])
        // drop with anything set
        XCTAssertEqual(paths(importing(withBullet(canonicalPlan(), at: 2, "order", 3))), ["/experience/2/order"])
        XCTAssertEqual(paths(importing(withBullet(canonicalPlan(), at: 2, "text", "x"))), ["/experience/2/text"])
        // a replaced summary needs its text, a dropped one must not have any
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["summary", "text"], "Leftover."))), ["/summary/text"])
    }

    // MARK: - Semantics

    func testIDsMustBeRealUniqueAndInTheRightArray() {
        // Index 2 is a drop, so swapping its id doesn't also disturb an order.
        XCTAssertEqual(codes(importing(withBullet(canonicalPlan(), at: 2, "id", UUID().uuidString))), ["id.unknown"])
        XCTAssertEqual(paths(importing(withBullet(canonicalPlan(), at: 2, "id", "exp_item_01"))), ["/experience/2/id"])

        // Twice in one array.
        var plan = canonicalPlan()
        plan["experience"] = (plan["experience"] as! [[String: Any]]) + [bullet(g2, "keep", order: 2)]
        XCTAssertEqual(codes(importing(plan)), ["id.duplicate"])

        // Once in each array.
        plan = canonicalPlan()
        plan["projects"] = [bullet(project, "keep", order: 1), bullet(a3, "drop")]
        XCTAssert(codes(importing(plan)).contains("id.duplicate"))

        // A project listed as experience.
        plan = canonicalPlan()
        plan["experience"] = (plan["experience"] as! [[String: Any]]) + [bullet(project, "drop")]
        plan["projects"] = [[String: Any]]()
        plan["section_order"] = ["education", "skills", "experience"]
        XCTAssertEqual(codes(importing(plan)), ["id.section_mismatch"])
    }

    func testOrderIsCountedWithinEachGroup() {
        // Acme's a2 and a1 both 1.
        XCTAssertEqual(codes(importing(withBullet(canonicalPlan(), at: 1, "order", 1))), ["order.duplicate"])
        // Acme 1, 3.
        XCTAssertEqual(codes(importing(withBullet(canonicalPlan(), at: 1, "order", 3))), ["order.non_contiguous"])
        // Acme and Globex both starting at 1 is the whole point of groups — the
        // canonical plan already does it.
        XCTAssertEqual(codes(importing(canonicalPlan())), [])
    }

    func testSectionOrderMustMatchWhatRenders() {
        // A dropped summary still listed.
        XCTAssertEqual(codes(importing(with(canonicalPlan(), ["section_order"],
                                            ["summary", "education", "skills", "experience", "projects"]))),
                       ["section.mismatch"])
        // Kept projects left out.
        XCTAssertEqual(codes(importing(with(canonicalPlan(), ["section_order"], ["education", "skills", "experience"]))),
                       ["section.mismatch"])
        // No projects kept, but the section still listed.
        var plan = canonicalPlan()
        plan["projects"] = [bullet(project, "drop")]
        XCTAssertEqual(codes(importing(plan)), ["section.mismatch"])
        // Education listed on a résumé without one.
        var noEducation = context
        noEducation.hasEducation = false
        XCTAssertEqual(codes(importing(canonicalPlan(), context: noEducation)), ["section.mismatch"])
        // Keeping a summary that doesn't exist.
        var noSummary = context
        noSummary.hasSummary = false
        var keeping = with(canonicalPlan(), ["summary"], ["action": "keep", "text": NSNull()])
        keeping["section_order"] = ["summary", "education", "skills", "experience", "projects"]
        XCTAssertEqual(paths(importing(keeping, context: noSummary)), ["/summary/action"])
    }

    func testSkillsMayNotRepeatInAnyCasing() {
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["skills", "rows"], [
            ["label": "Languages", "items": ["Swift"]],
            ["label": "languages:", "items": ["Python"]],
            ["label": "Tools", "items": ["Xcode"]]
        ]))), ["/skills/rows/1/label"])
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["skills", "rows"], [
            ["label": "Languages", "items": ["Swift", "SWIFT"]],
            ["label": "iOS", "items": ["UIKit"]],
            ["label": "Tools", "items": ["Xcode"]]
        ]))), ["/skills/rows/0/items/1"])
    }

    func testLayoutCommandsAreRejectedWhereverTextGoes() {
        XCTAssertEqual(codes(importing(withBullet(canonicalPlan(), at: 1, "text", "Shipped \\begin{itemize} it."))),
                       ["text.latex_command"])
        var summary = with(canonicalPlan(), ["summary"], ["action": "replace", "text": "Engineer.\\newpage"])
        summary["section_order"] = ["summary", "education", "skills", "experience", "projects"]
        XCTAssertEqual(codes(importing(summary)), ["text.latex_command"])
        XCTAssertEqual(codes(importing(with(canonicalPlan(), ["skills", "rows"], [
            ["label": "Languages", "items": ["Swift", "\\input{secrets}"]],
            ["label": "iOS", "items": ["UIKit"]],
            ["label": "Tools", "items": ["Xcode"]]
        ]))), ["text.latex_command"])
        // An escape the existing bullets already use is fine.
        XCTAssertEqual(codes(importing(withBullet(canonicalPlan(), at: 1, "text", "Cut 40\\% of crashes."))), [])
        // So is a Markdown bullet… not.
        XCTAssertEqual(codes(importing(withBullet(canonicalPlan(), at: 1, "text", "- Cut crashes."))), ["text.markdown"])
    }

    func testAGenericTitleWarnsButStillImports() {
        let result = importing(withBullet(canonicalPlan(), at: 1, "variant_title", "Tailored Version"))
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.warnings.map(\.code), ["variant.generic_title"])
        XCTAssertNotNil(result.plan)
        XCTAssertTrue(ResumeEditPlanImporter.isGenericTitle("Variant 3"))
        XCTAssertFalse(ResumeEditPlanImporter.isGenericTitle("Build Reliability and Swift Tooling"))
    }

    // MARK: - Adapting into a TailoringPlan

    func testThePlanBecomesTheWholeSelectionInGroupOrder() throws {
        let plan = try XCTUnwrap(importing(canonicalPlan()).plan)
        XCTAssertEqual(plan.orderedExperienceIDs, [a2.id, a1.id, g1.id], "Acme first, then Globex, each by order")
        XCTAssertEqual(plan.orderedProjectIDs, [project.id])
        XCTAssertEqual(plan.drops?.map(\.experienceID), [a3.id, g2.id])
        XCTAssertEqual(plan.summary, "", "drop is the existing 'remove the summary'")
        XCTAssertEqual(plan.replacements?.map(\.experienceID), [a1.id])
        XCTAssertEqual(plan.replacements?.first?.name, "Build Reliability and Swift Tooling")
        XCTAssertEqual(plan.sectionOrder, ["Education", "Skills", "Experience", "Selected Projects", "Summary"],
                       "Unlisted sections trail and render empty")

        // Nothing kept anywhere still means "select nothing", not "leave alone".
        var empty = canonicalPlan()
        empty["projects"] = [bullet(project, "drop")]
        empty["section_order"] = ["education", "skills", "experience"]
        XCTAssertEqual(try XCTUnwrap(importing(empty).plan).orderedProjectIDs, [])
    }

    func testSkillsRowsBecomeTheFixedWidthTable() throws {
        let latex = try XCTUnwrap(importing(canonicalPlan()).plan?.skillsLatex)
        XCTAssertTrue(latex.contains("p{0.74\\textwidth}"))
        XCTAssertEqual(latex.components(separatedBy: "\\textbf{").count - 1, 3, "Three rows")
        XCTAssertTrue(latex.contains("\\textbf{Languages:} & Swift, Objective-C, C++ \\\\"))
        XCTAssertTrue(latex.contains("R\\&D, snake\\_case tooling"), "Plain text is escaped once, here")
    }

    /// Imported, applied the way the review list applies it, and rendered.
    func testAnImportedPlanRendersAsPlanned() throws {
        let plan = try XCTUnwrap(importing(canonicalPlan()).plan)
        var experiences = [a1, a2, a3, g1, g2, project]
        var application = JobApplication(companyName: "Example", jobTitle: "Engineer")
        application.summaryText = "Old summary."
        for id in [a3.id, g2.id] { application.setExperience(id, selected: true) }

        // Selection and order.
        for exp in experiences where !exp.isProjectLike {
            application.setExperience(exp.id, selected: plan.orderedExperienceIDs!.contains(exp.id))
        }
        for exp in experiences where exp.isProjectLike {
            application.setProject(exp.id, selected: plan.orderedProjectIDs!.contains(exp.id))
        }
        application.setExperienceOrder(plan.orderedExperienceIDs! + plan.orderedProjectIDs!)
        // The rewrite, as a variant.
        let replacement = try XCTUnwrap(plan.replacements?.first)
        let index = try XCTUnwrap(experiences.firstIndex { $0.id == replacement.experienceID })
        let variant = ExperienceVariation(name: replacement.name ?? "", bulletText: replacement.text)
        experiences[index].variations.append(variant)
        application.setVariant(variant.id, for: replacement.experienceID)
        application.summaryText = plan.summary ?? application.summaryText
        application.skillsBlockText = plan.skillsLatex ?? ""
        application.setSectionOrder(plan.sectionOrder!.compactMap(ResumeSectionKind.init(rawValue:)))

        let selected = experiences.filter { application.selectedExperienceIDs.contains($0.id) }
        let projects = experiences.filter { application.selectedProjectIDs.contains($0.id) }
        let rendered = ResumeRenderer.render(
            template: ResumeRenderer.sectionsPlaceholder, variantSelections: application.selectedVariantIDs,
            selectedExperiences: selected, selectedProjects: projects, employments: [acme, globex],
            experienceOrder: application.experienceOrder, educationBlock: "Some University",
            skillsBlock: application.skillsBlockText, summary: application.summaryText,
            sectionOrder: application.sectionOrder
        ).rendered

        let order = ["{Education}", "{Skills}", "{Experience}", "{Selected Projects}"]
            .map { rendered.range(of: $0)?.lowerBound }
        XCTAssertFalse(order.contains(nil))
        XCTAssertEqual(order.compactMap { $0 }, order.compactMap { $0 }.sorted(), "Sections follow section_order")
        XCTAssertFalse(rendered.contains("{Summary}"))
        XCTAssertFalse(rendered.contains("Old summary."))

        let kept = try XCTUnwrap(rendered.range(of: "Acme two."))
        let rewritten = try XCTUnwrap(rendered.range(of: "Reduced CI failures 70\\% across 20+ apps."))
        XCTAssertLessThan(kept.lowerBound, rewritten.lowerBound, "order within Acme")
        XCTAssertFalse(rendered.contains("Acme one."), "The rewrite replaces the wording")
        XCTAssertFalse(rendered.contains("Acme three."), "Dropped")
        XCTAssertFalse(rendered.contains("Globex two."), "Dropped")
        XCTAssertEqual(experiences[index].bulletText, "Acme one.", "The source bullet itself is untouched")
    }

    // MARK: - Idempotency

    func testReapplyingTheSameRewriteReusesItsVariant() {
        let existing = ExperienceVariation(name: "Build Reliability", bulletText: "Reduced CI failures 70%.")
        let variations = [ExperienceVariation(name: "Other", bulletText: "Other."), existing]

        let same = ExperienceVariation.matching(name: " Build  Reliability ",
                                                text: "Reduced CI failures\t70%.\r\n", in: variations)
        XCTAssertEqual(same?.id, existing.id, "Whitespace differences are the same variant")

        XCTAssertNil(ExperienceVariation.matching(name: "Build Reliability", text: "Reduced CI failures 75%.",
                                                  in: variations), "Changed text is a new variant")
        XCTAssertNil(ExperienceVariation.matching(name: "Build reliability", text: "Reduced CI failures 70%.",
                                                  in: variations), "Case still counts")
    }

    // MARK: - The prompt

    func testTheCopiedContractListsEveryIDUnderItsGroup() throws {
        let contract = ResumeEditPlanPrompt.outputContract(
            experiences: [a1, g1, project], employments: [acme, globex],
            selectedIDs: [a1.id], variantSelections: [:], hasSummary: false, hasEducation: true
        )
        let acmeHeader = try XCTUnwrap(contract.range(of: "Acme — iOS Engineer"))
        let a1Line = try XCTUnwrap(contract.range(of: "\(a1.id.uuidString) (on résumé) Acme one."))
        let globexHeader = try XCTUnwrap(contract.range(of: "Globex — Engineer"))
        let projectsHeader = try XCTUnwrap(contract.range(of: "Projects (goes in `projects`)"))
        let projectLine = try XCTUnwrap(contract.range(of: "\(project.id.uuidString) (not selected)"))
        XCTAssertLessThan(acmeHeader.lowerBound, a1Line.lowerBound)
        XCTAssertLessThan(a1Line.lowerBound, globexHeader.lowerBound)
        XCTAssertLessThan(projectsHeader.lowerBound, projectLine.lowerBound)
        XCTAssertTrue(contract.contains("this résumé has none"))
        XCTAssertTrue(contract.contains(#""content_width": { "const": "0.74\\textwidth" }"#))

        // The example in the prompt passes the schema checks itself.
        let example = ResumeEditPlanImporter.parse(ResumeEditPlanPrompt.exampleJSON)
        XCTAssertEqual(example.issues, [])
        XCTAssertEqual(example.plan?.skills.contentWidth, "0.74\\textwidth")
    }

    // MARK: - Role descriptions

    func testRoleDescriptionsCanBeKeptRewrittenOrHidden() throws {
        var plan = canonicalPlan()
        plan["role_descriptions"] = [role(acme, "hide"), role(globex, "rewrite", text: "Built payments at Globex.")]
        let imported = try XCTUnwrap(importing(plan).plan)
        XCTAssertEqual(imported.roleDescriptions, [
            TailoringPlan.RoleDescription(employmentID: acme.id, include: false, text: nil),
            TailoringPlan.RoleDescription(employmentID: globex.id, include: true, text: "Built payments at Globex.")
        ])

        plan["role_descriptions"] = [role(acme, "keep")]
        XCTAssertEqual(try XCTUnwrap(importing(plan).plan).roleDescriptions,
                       [TailoringPlan.RoleDescription(employmentID: acme.id, include: true, text: nil)],
                       "keep shows the line — how a hidden one comes back")

        XCTAssertNil(try XCTUnwrap(importing(canonicalPlan()).plan).roleDescriptions,
                     "No entries, no role-description changes")
    }

    func testRoleDescriptionFieldsMustMatchTheirAction() {
        var plan = canonicalPlan()
        plan["role_descriptions"] = [role(globex, "rewrite")]
        XCTAssertEqual(paths(importing(plan)), ["/role_descriptions/0/text"])
        plan["role_descriptions"] = [role(acme, "hide", text: "x")]
        XCTAssertEqual(paths(importing(plan)), ["/role_descriptions/0/text"])
        plan["role_descriptions"] = [role(acme, "show")]
        XCTAssertEqual(paths(importing(plan)), ["/role_descriptions/0/action"])
        XCTAssertEqual(paths(importing(with(canonicalPlan(), ["role_descriptions"], nil))), ["/role_descriptions"],
                       "The array is required, even when empty")
    }

    func testRoleDescriptionsMustNameAnEmployerOnceAndHaveALineToKeep() {
        var plan = canonicalPlan()
        plan["role_descriptions"] = [["employment_id": a1.id.uuidString, "action": "hide", "order": NSNull(), "text": NSNull()]]
        XCTAssertEqual(codes(importing(plan)), ["role.unknown"], "A bullet id is not an employer")

        plan["role_descriptions"] = [role(acme, "hide"), role(acme, "keep")]
        XCTAssertEqual(codes(importing(plan)), ["role.duplicate"])

        plan["role_descriptions"] = [role(globex, "keep")]
        XCTAssertEqual(codes(importing(plan)), ["role.empty"], "Globex has no line to keep")
        var withOverride = context
        withOverride.roleDescriptionOverrides = [globex.id: "Payments engineer."]
        XCTAssertEqual(codes(importing(plan, context: withOverride)), [], "This application's own wording counts")

        plan["role_descriptions"] = [role(acme, "rewrite", text: "Led \\section{x} things.")]
        XCTAssertEqual(codes(importing(plan)), ["text.latex_command"])
    }

    func testTheListingNamesEachEmployersRoleLineState() {
        let listing = ResumeEditPlanPrompt.idListing(
            experiences: [a1, g1], employments: [acme, globex], selectedIDs: [], variantSelections: [:],
            hiddenRoleDescriptions: [acme.id]
        )
        XCTAssertTrue(listing.contains("Acme — iOS Engineer (employment_id: \(acme.id.uuidString); role description: hidden)"))
        XCTAssertTrue(listing.contains("Globex — Engineer (employment_id: \(globex.id.uuidString); role description: none)"))
    }

    // MARK: - Role line position

    func testARoleLineCanBePlacedAmongItsEmployersBullets() throws {
        // Acme: a2 is 1, the role line 2, a1 3.
        var plan = withBullet(canonicalPlan(), at: 1, "order", 3)
        plan["role_descriptions"] = [role(acme, "keep", order: 2)]
        let imported = try XCTUnwrap(importing(plan).plan)
        XCTAssertEqual(imported.orderedExperienceIDs, [a2.id, acme.id, a1.id, g1.id])

        // At the top.
        plan = withBullet(withBullet(canonicalPlan(), at: 0, "order", 2), at: 1, "order", 3)
        plan["role_descriptions"] = [role(acme, "rewrite", order: 1, text: "Led the iOS team of six.")]
        XCTAssertEqual(try XCTUnwrap(importing(plan).plan).orderedExperienceIDs, [acme.id, a2.id, a1.id, g1.id])
    }

    func testARoleLineSlotCountsInItsEmployersNumbering() {
        // The bullets already use 1 and 2, so a role line at 2 collides…
        var plan = canonicalPlan()
        plan["role_descriptions"] = [role(acme, "keep", order: 2)]
        XCTAssertEqual(paths(importing(plan)), ["/role_descriptions/0/order"])
        // …and one at 4 leaves a gap.
        plan["role_descriptions"] = [role(acme, "keep", order: 4)]
        XCTAssertEqual(codes(importing(plan)), ["order.non_contiguous"])
        // A hidden line has no position.
        plan["role_descriptions"] = [role(acme, "hide", order: 1)]
        XCTAssertEqual(paths(importing(plan)), ["/role_descriptions/0/order"])
    }

    func testAnUnplacedRoleLineStaysBesideTheBulletItPreceded() throws {
        var context = self.context
        // Acme today: a1, [role line], a2, a3.
        context.currentExperienceOrder = [a1.id, acme.id, a2.id, a3.id, g1.id]
        // The plan reorders to a2, a1 and doesn't mention the line: it stays in front of a2.
        XCTAssertEqual(try XCTUnwrap(importing(canonicalPlan(), context: context).plan).orderedExperienceIDs,
                       [acme.id, a2.id, a1.id, g1.id])

        // Nothing it preceded survives: it goes last in its group.
        context.currentExperienceOrder = [a1.id, a2.id, acme.id, a3.id]
        XCTAssertEqual(try XCTUnwrap(importing(canonicalPlan(), context: context).plan).orderedExperienceIDs,
                       [a2.id, a1.id, acme.id, g1.id])

        // Never placed: no marker, so it renders first by default.
        context.currentExperienceOrder = [a1.id, a2.id]
        XCTAssertEqual(try XCTUnwrap(importing(canonicalPlan(), context: context).plan).orderedExperienceIDs,
                       [a2.id, a1.id, g1.id])
    }

    // MARK: - Selection completeness and projects

    func testEveryBulletOnTheResumeMustBeDecided() {
        var context = self.context
        context.selectedIDs = [a3.id, project.id]
        // The canonical plan decides both (a3 as a drop): fine.
        XCTAssertEqual(codes(importing(canonicalPlan(), context: context)), [])

        // Leaving a3 out is no longer a silent drop.
        var plan = canonicalPlan()
        plan["experience"] = (plan["experience"] as! [[String: Any]]).filter { ($0["id"] as? String) != a3.id.uuidString }
        let result = importing(plan, context: context)
        XCTAssertEqual(codes(result), ["selection.missing"])
        XCTAssertEqual(paths(result), ["/experience"])
        XCTAssertTrue(result.errors.first?.message.contains(a3.id.uuidString) == true)

        // A bullet that isn't on the résumé can simply be left out.
        XCTAssertEqual(codes(importing(plan)), [])
    }

    func testAProjectRewriteIsOneVariantInTheItemConvention() throws {
        func rewritten(_ text: String) -> [String: Any] {
            var plan = canonicalPlan()
            plan["projects"] = [bullet(project, "rewrite", order: 1, title: "Open Source Traction", text: text)]
            return plan
        }
        func stored(_ plan: [String: Any]) throws -> String? {
            try XCTUnwrap(importing(plan).plan).replacements?.first { $0.experienceID == project.id }?.text
        }

        // Points opened with \item, the way the stored variants are written.
        let itemized = "\\item Grew the app to 800 stars.\n\\item Designed a renderer pipeline."
        XCTAssertEqual(codes(importing(rewritten(itemized))), [])
        XCTAssertEqual(try stored(rewritten(itemized)), itemized)

        // Bare lines become the same thing.
        XCTAssertEqual(try stored(rewritten("Grew the app to 800 stars.\nDesigned a renderer pipeline.")), itemized)
        // A single point stays plain.
        XCTAssertEqual(try stored(rewritten("\\item Grew the app to 800 stars.")), "Grew the app to 800 stars.")

        // \item anywhere but the start of a point is still a layout command.
        XCTAssertEqual(codes(importing(rewritten("Grew the app \\item to 800 stars."))), ["text.latex_command"])
        XCTAssertEqual(codes(importing(rewritten("\\item Grew the app.\n- Designed a renderer."))), ["text.markdown"],
                       "Checked on every line, not just the first")

        // A work bullet is a single item: no \item, no second line.
        XCTAssertEqual(codes(importing(withBullet(canonicalPlan(), at: 1, "text", "\\item Cut crashes."))),
                       ["text.latex_command"])
        XCTAssertEqual(codes(importing(withBullet(canonicalPlan(), at: 1, "text", "One.\nTwo."))), ["text.multiline"])
        // Inline markup carried over from the source is fine.
        XCTAssertEqual(codes(importing(withBullet(canonicalPlan(), at: 1, "text",
                                                  "Built \\texttt{XMLParser} composers for B\\'{e}zier paths."))), [])
    }

    func testStoredProjectLinesLoseTheirItemPrefix() {
        XCTAssertEqual(ResumeEditPlanImporter.lines(of: "\\item Grew Parma.\n\n  \\item Built a renderer.\nPlain line."),
                       ["Grew Parma.", "Built a renderer.", "Plain line."])
    }
}
