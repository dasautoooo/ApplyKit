//
//  ResumeEditPlanImporter.swift
//  ApplyKit
//
//  Reads a pasted Resume Edit Plan v1.0 without any AI call: extract the one
//  JSON object, check it against the schema, check it against the résumé it
//  was written for, then adapt it into the `TailoringPlan` the review list
//  already knows how to apply. Every step is deterministic; a plan with any
//  error produces no changes at all.
//

import Foundation

/// What the importer needs to know about the résumé a plan was written against.
struct ResumeEditPlanContext {
    var experiences: [ExperienceBullet]
    var employments: [Employment]
    /// The application has a summary to keep.
    var hasSummary: Bool
    /// The profile has an Education block, so the section renders.
    var hasEducation: Bool
    /// This application's role-description overrides; an employer without one
    /// uses its own `roleDescription`.
    var roleDescriptionOverrides: [UUID: String] = [:]
    /// The application's current `experienceOrder`, which records where each
    /// role line sits among its employer's bullets.
    var currentExperienceOrder: [UUID] = []
    /// Bullets and projects on the résumé now. Each must be decided by the
    /// plan, so a model that forgets one can't silently remove it.
    var selectedIDs: Set<UUID> = []

    func roleDescription(for employment: Employment) -> String {
        let override = roleDescriptionOverrides[employment.id]?.trimmed ?? ""
        return override.isEmpty ? employment.roleDescription.trimmed : override
    }
}

enum ResumeEditPlanImporter {
    static let maxPayloadBytes = 256 * 1024
    /// Past this a bullet usually runs to a third line. Advisory only.
    static let bulletLengthBudget = 220

    struct Result {
        /// Nil whenever any error was found.
        var plan: TailoringPlan?
        var fitScore: Double?
        var issues: [ResumeEditPlanIssue]

        var errors: [ResumeEditPlanIssue] { issues.filter(\.isError) }
        var warnings: [ResumeEditPlanIssue] { issues.filter { !$0.isError } }
    }

    static func importPlan(from text: String, context: ResumeEditPlanContext) -> Result {
        let extracted = extractJSON(from: text)
        guard let json = extracted.json else {
            return Result(plan: nil, fitScore: nil, issues: extracted.issues)
        }
        let parsed = parse(json)
        guard let dto = parsed.plan else {
            return Result(plan: nil, fitScore: nil, issues: parsed.issues)
        }
        let issues = semanticIssues(in: dto, context: context)
        guard !issues.contains(where: \.isError) else {
            return Result(plan: nil, fitScore: nil, issues: issues)
        }
        return Result(plan: makeTailoringPlan(from: dto, context: context), fitScore: dto.fitScore, issues: issues)
    }

    /// A bullet's rendered lines, without the `\item` a project's stored
    /// lines may start with — the renderer adds it back.
    static func lines(of text: String) -> [String] {
        text.split(separator: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("\\item") ? String(trimmed.dropFirst(5)).trimmed : trimmed.trimmed
            }
            .filter { !$0.isEmpty }
    }

    // MARK: - Extract

    /// The one JSON object in the reply that carries `schema_version`. Prose and
    /// code fences around it are fine; two plans, or none, are not — guessing
    /// which one was meant is how the wrong edits get applied.
    static func extractJSON(from text: String) -> (json: String?, issues: [ResumeEditPlanIssue]) {
        func failure(_ code: String, _ message: String) -> (String?, [ResumeEditPlanIssue]) {
            (nil, [ResumeEditPlanIssue(.error, code, path: "", message)])
        }
        guard text.utf8.count <= maxPayloadBytes else {
            return failure("payload.too_large",
                           "The pasted text is over 256 KB. Paste only the reply that contains the edit plan.")
        }
        let scan = topLevelObjects(in: text)
        let plans = scan.objects.filter { $0.contains("\"schema_version\"") }
        switch plans.count {
        case 1:
            return (plans[0], [])
        case 0:
            if let unterminated = scan.unterminated, unterminated.contains("\"schema_version\"") {
                return failure("payload.truncated",
                               "The edit plan's JSON is cut off before its closing brace. Ask ChatGPT to send the complete object.")
            }
            if scan.objects.isEmpty {
                return failure("payload.no_json",
                               "No JSON object found. The reply has to end with the edit plan as one JSON object.")
            }
            return failure("payload.no_plan",
                           "The reply has JSON, but no object with \"schema_version\". It may be the old tailoring format — copy the context again and re-generate the plan.")
        default:
            return failure("payload.multiple_plans",
                           "The reply contains \(plans.count) edit plans. Paste a reply with exactly one.")
        }
    }

    /// Balanced top-level `{…}` spans. Quotes only count inside an object, so a
    /// stray `"` in the prose before the JSON can't throw the scan off.
    static func topLevelObjects(in text: String) -> (objects: [String], unterminated: String?) {
        var objects: [String] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for index in text.indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"" where depth > 0:
                inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}" where depth > 0:
                depth -= 1
                if depth == 0, let start {
                    objects.append(String(text[start...index]))
                }
            default:
                break
            }
        }
        let unterminated = depth > 0 ? start.map { String(text[$0...]) } : nil
        return (objects, unterminated)
    }

    // MARK: - Parse and schema-validate

    static func parse(_ json: String) -> (plan: ResumeEditPlanDTO?, issues: [ResumeEditPlanIssue]) {
        let data = Data(json.utf8)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
                ?? error.localizedDescription
            return (nil, [ResumeEditPlanIssue(.error, "json.syntax", path: "",
                                              "The edit plan isn't valid JSON: \(detail)")])
        }

        var validator = SchemaValidator()
        validator.validatePlan(object)
        guard validator.issues.isEmpty else { return (nil, validator.issues) }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return (try decoder.decode(ResumeEditPlanDTO.self, from: data), [])
        } catch {
            return (nil, [ResumeEditPlanIssue(.error, "schema.invalid", path: "",
                                              "Couldn't read the edit plan: \(error.localizedDescription)")])
        }
    }

    // MARK: - Semantic validation

    private struct GroupKey: Hashable {
        let section: String
        let employmentID: UUID?
    }

    static func semanticIssues(in plan: ResumeEditPlanDTO,
                               context: ResumeEditPlanContext) -> [ResumeEditPlanIssue] {
        var issues: [ResumeEditPlanIssue] = []
        let bulletsByID = Dictionary(context.experiences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let employmentsByID = ResumeContentGrouping.employmentsByID(context.employments)

        // Bullet ids: known, used once, and in the array that matches the bullet.
        var firstSeenAt: [UUID: String] = [:]
        var groupOrder: [GroupKey] = []
        var groups: [GroupKey: [(order: Int, path: String)]] = [:]

        for (section, edits) in [("experience", plan.experience), ("projects", plan.projects)] {
            for (index, edit) in edits.enumerated() {
                let path = "/\(section)/\(index)"
                guard let id = UUID(uuidString: edit.id), let bullet = bulletsByID[id] else {
                    issues.append(ResumeEditPlanIssue(.error, "id.unknown", path: path + "/id",
                        "\"\(edit.id)\" isn't a bullet in this résumé's experience bank. Ids must be copied exactly from the context."))
                    continue
                }
                if let first = firstSeenAt[id] {
                    issues.append(ResumeEditPlanIssue(.error, "id.duplicate", path: path + "/id",
                        "This bullet already appears at \(first). Each id may appear once across experience and projects."))
                    continue
                }
                firstSeenAt[id] = path

                let isProject = ResumeContentGrouping.isProjectLike(bullet, employmentsByID: employmentsByID)
                if isProject != (section == "projects") {
                    issues.append(ResumeEditPlanIssue(.error, "id.section_mismatch", path: path + "/id", isProject
                        ? "This is a project bullet; it belongs in projects, not experience."
                        : "This is a work bullet; it belongs in experience, not projects."))
                    continue
                }

                if edit.isRetained, let order = edit.order {
                    let key = GroupKey(section: section, employmentID: bullet.employmentID)
                    if groups[key] == nil { groupOrder.append(key) }
                    groups[key, default: []].append((order, path + "/order"))
                }

                if edit.action == .rewrite {
                    if let title = edit.variantTitle {
                        issues += textIssues(title, path: path + "/variant_title", isProse: false)
                        if isGenericTitle(title) {
                            issues.append(ResumeEditPlanIssue(.warning, "variant.generic_title", path: path + "/variant_title",
                                "\"\(title.trimmed)\" doesn't say what angle this wording takes. It still imports."))
                        }
                    }
                    if let text = edit.text {
                        // A project's points may each open with `\item`, the
                        // way its stored variants do; anywhere else it's the
                        // layout command it looks like.
                        let rendered = lines(of: text)
                        issues += textIssues(isProject ? rendered.joined(separator: "\n") : text,
                                             path: path + "/text", isProse: true)
                        // A project renders one bullet per line; a work bullet
                        // is a single item, where a line break would just vanish.
                        if !isProject, rendered.count > 1 {
                            issues.append(ResumeEditPlanIssue(.error, "text.multiline", path: path + "/text",
                                "A work bullet renders as one line, but this text has \(rendered.count). Put it on one line."))
                        }
                        if let longest = rendered.map(\.count).max(), longest > bulletLengthBudget {
                            issues.append(ResumeEditPlanIssue(.warning, "bullet.length", path: path + "/text",
                                "\(longest) characters in one line — likely to run past two lines."))
                        }
                    }
                }
            }
        }

        // Everything on the résumé now has to be decided, drop included.
        for bullet in context.experiences where context.selectedIDs.contains(bullet.id) && firstSeenAt[bullet.id] == nil {
            let isProject = ResumeContentGrouping.isProjectLike(bullet, employmentsByID: employmentsByID)
            let clipped = ResumeEditPlanImporter.lines(of: bullet.bulletText).first.map {
                $0.count > 60 ? String($0.prefix(60)) + "…" : $0
            } ?? bullet.displayTitle
            issues.append(ResumeEditPlanIssue(.error, "selection.missing", path: isProject ? "/projects" : "/experience",
                "\(isProject ? "Project" : "Bullet") \(bullet.id.uuidString) (\"\(clipped)\") is on the résumé but not in the plan. List it as keep, rewrite, or drop."))
        }

        // A role line given an order takes a slot in its employer's numbering.
        // Invalid or repeated entries are reported by `roleDescriptionIssues`.
        for (employmentID, placement) in placedRoleLines(in: plan, employmentsByID: employmentsByID) {
            let key = GroupKey(section: "experience", employmentID: employmentID)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append((placement.order, "/role_descriptions/\(placement.index)/order"))
        }

        // Order: 1…n within each employment (or project) group.
        for key in groupOrder {
            let entries = groups[key] ?? []
            let name = groupName(key, employmentsByID: employmentsByID)
            var used: Set<Int> = []
            var hasDuplicate = false
            for entry in entries where !used.insert(entry.order).inserted {
                hasDuplicate = true
                issues.append(ResumeEditPlanIssue(.error, "order.duplicate", path: entry.path,
                    "Two lines in \(name) both have order \(entry.order)."))
            }
            if !hasDuplicate, used != Set(1...entries.count) {
                let orders = used.sorted().map(String.init).joined(separator: ", ")
                issues.append(ResumeEditPlanIssue(.error, "order.non_contiguous", path: entries[0].path,
                    "Orders in \(name) are \(orders); they must run 1 to \(entries.count) with no gaps."))
            }
        }

        // Sections: listed exactly when they render.
        let listed = Set(plan.sectionOrder)
        func expect(_ key: ResumeSectionKey, visible: Bool, hiddenBecause reason: String) {
            if visible, !listed.contains(key) {
                issues.append(ResumeEditPlanIssue(.error, "section.mismatch", path: "/section_order",
                    "\(key.rawValue) renders but is missing from section_order."))
            } else if !visible, listed.contains(key) {
                issues.append(ResumeEditPlanIssue(.error, "section.mismatch", path: "/section_order",
                    "\(key.rawValue) is listed in section_order, but \(reason)."))
            }
        }
        expect(.summary, visible: plan.summary.action != .drop, hiddenBecause: "the summary is dropped")
        expect(.education, visible: context.hasEducation, hiddenBecause: "this résumé has no Education section")
        expect(.skills, visible: true, hiddenBecause: "")
        expect(.experience, visible: plan.experience.contains(where: \.isRetained),
               hiddenBecause: "no experience bullet is kept or rewritten")
        expect(.projects, visible: plan.projects.contains(where: \.isRetained),
               hiddenBecause: "no project is kept or rewritten")
        if plan.summary.action == .keep, !context.hasSummary {
            issues.append(ResumeEditPlanIssue(.error, "section.mismatch", path: "/summary/action",
                "The plan keeps the summary, but this résumé has none. Use replace or drop."))
        }

        if plan.summary.action == .replace, let text = plan.summary.text {
            issues += textIssues(text, path: "/summary/text", isProse: true)
        }

        issues += roleDescriptionIssues(in: plan, context: context, employmentsByID: employmentsByID)

        // Skills: no label or skill twice, whatever the casing.
        var seenLabels: [String: String] = [:]
        var seenItems: [String: String] = [:]
        for (rowIndex, row) in plan.skills.rows.enumerated() {
            let rowPath = "/skills/rows/\(rowIndex)"
            issues += textIssues(row.label, path: rowPath + "/label", isProse: false)
            let label = normalizedLabel(row.label).lowercased()
            if let first = seenLabels[label] {
                issues.append(ResumeEditPlanIssue(.error, "skills.duplicate", path: rowPath + "/label",
                    "The label \"\(row.label.trimmed)\" is already used at \(first)."))
            } else {
                seenLabels[label] = rowPath + "/label"
            }
            for (itemIndex, item) in row.items.enumerated() {
                let itemPath = rowPath + "/items/\(itemIndex)"
                issues += textIssues(item, path: itemPath, isProse: false)
                let key = item.trimmed.lowercased()
                if let first = seenItems[key] {
                    issues.append(ResumeEditPlanIssue(.error, "skills.duplicate", path: itemPath,
                        "\"\(item.trimmed)\" is already listed at \(first)."))
                } else {
                    seenItems[key] = itemPath
                }
            }
        }

        return issues
    }

    /// Role lines belong to employers the Experience section shows — ones with
    /// at least one work bullet — and each is decided at most once.
    private static func roleDescriptionIssues(in plan: ResumeEditPlanDTO, context: ResumeEditPlanContext,
                                              employmentsByID: [UUID: Employment]) -> [ResumeEditPlanIssue] {
        var issues: [ResumeEditPlanIssue] = []
        let workEmploymentIDs = Set(context.experiences
            .filter { ResumeContentGrouping.isWorkLike($0, employmentsByID: employmentsByID) }
            .compactMap(\.employmentID))
        var firstSeenAt: [UUID: String] = [:]

        for (index, edit) in plan.roleDescriptions.enumerated() {
            let path = "/role_descriptions/\(index)"
            guard let id = UUID(uuidString: edit.employmentID), let employment = employmentsByID[id],
                  workEmploymentIDs.contains(id) else {
                issues.append(ResumeEditPlanIssue(.error, "role.unknown", path: path + "/employment_id",
                    "\"\(edit.employmentID)\" isn't an employer in this résumé's Experience section. Use an employment_id from the context."))
                continue
            }
            if let first = firstSeenAt[id] {
                issues.append(ResumeEditPlanIssue(.error, "role.duplicate", path: path + "/employment_id",
                    "\(employment.companyName) already has a role description decision at \(first)."))
                continue
            }
            firstSeenAt[id] = path

            switch edit.action {
            case .keep:
                if context.roleDescription(for: employment).isEmpty {
                    issues.append(ResumeEditPlanIssue(.error, "role.empty", path: path + "/action",
                        "\(employment.companyName) has no role description to keep. Use rewrite to add one, or leave it out."))
                }
            case .rewrite:
                if let text = edit.text { issues += textIssues(text, path: path + "/text", isProse: true) }
            case .hide:
                break
            }
        }
        return issues
    }

    /// Role lines the plan places explicitly, keyed by employment: the first
    /// entry per known employer that is shown and has an order.
    private static func placedRoleLines(in plan: ResumeEditPlanDTO, employmentsByID: [UUID: Employment])
        -> [(employmentID: UUID, placement: (index: Int, order: Int))] {
        var seen: Set<UUID> = []
        var placed: [(employmentID: UUID, placement: (index: Int, order: Int))] = []
        for (index, edit) in plan.roleDescriptions.enumerated() {
            guard let id = UUID(uuidString: edit.employmentID), employmentsByID[id] != nil,
                  seen.insert(id).inserted, edit.action != .hide, let order = edit.order else { continue }
            placed.append((id, (index, order)))
        }
        return placed
    }

    private static func groupName(_ key: GroupKey, employmentsByID: [UUID: Employment]) -> String {
        if let id = key.employmentID, let employment = employmentsByID[id] {
            let role = employment.role.trimmed
            return role.isEmpty ? employment.companyName : "\(employment.companyName) — \(role)"
        }
        return key.section == "projects" ? "personal projects" : "unassigned bullets"
    }

    /// Structural LaTeX that would let imported text reshape the document.
    /// Escapes such as `\%` are fine — the renderer already tolerates them.
    private static let forbiddenLatex = try! NSRegularExpression(
        pattern: #"\\(documentclass|begin|end|input|include|includeonly|write|write18|openout|openin|read|usepackage|item|section|subsection|subsubsection|newpage|clearpage|pagebreak|vspace|hspace|def|newcommand|renewcommand|immediate|catcode|csname)(?![A-Za-z])"#
    )

    /// Blank, control characters, layout commands, and — for prose — Markdown
    /// list markers.
    private static func textIssues(_ text: String, path: String, isProse: Bool) -> [ResumeEditPlanIssue] {
        var issues: [ResumeEditPlanIssue] = []
        let trimmed = text.trimmed
        if trimmed.isEmpty {
            issues.append(ResumeEditPlanIssue(.error, "text.blank", path: path, "This text is blank."))
            return issues
        }
        let hasControl = text.unicodeScalars.contains {
            $0.properties.generalCategory == .control && $0 != "\n" && $0 != "\r" && $0 != "\t"
        }
        if hasControl {
            issues.append(ResumeEditPlanIssue(.error, "text.control_character", path: path,
                "This text contains control characters."))
        }
        let range = NSRange(text.startIndex..., in: text)
        if let match = forbiddenLatex.firstMatch(in: text, range: range), let found = Range(match.range, in: text) {
            let command = String(text[found])
            issues.append(ResumeEditPlanIssue(.error, "text.latex_command", path: path, command == "\\item"
                ? "\\item only opens a line of a project's points. A work bullet is a single item; give its text alone."
                : "\"\(command)\" is a layout command. Text must be plain; ApplyKit does the LaTeX."))
        }
        let markers = ["- ", "* ", "+ ", "• "]
        if isProse, text.split(separator: "\n").contains(where: { line in
            markers.contains(where: line.trimmingCharacters(in: .whitespaces).hasPrefix)
        }) {
            issues.append(ResumeEditPlanIssue(.error, "text.markdown", path: path,
                "A line starts with a list marker. Give the text alone."))
        }
        return issues
    }

    private static let genericTitles: Set<String> = [
        "tailored", "tailored version", "tailored bullet", "tailored rewrite", "rewrite", "rewritten",
        "variant", "new variant", "version", "new version", "updated", "updated version",
        "revised", "revised version", "improved", "improved version", "untitled", "untitled variant"
    ]

    static func isGenericTitle(_ title: String) -> Bool {
        let normalized = title.trimmed.lowercased()
        if genericTitles.contains(normalized) { return true }
        return normalized.range(of: #"^(variant|version|option|rewrite)\s*#?\d+$"#, options: .regularExpression) != nil
    }

    /// A row label without the colon the renderer adds itself.
    private static func normalizedLabel(_ label: String) -> String {
        var value = label.trimmed
        while value.hasSuffix(":") { value.removeLast() }
        return value.trimmed
    }

    // MARK: - Adapt

    /// The plan as the edits the review list applies. The plan is the whole
    /// selection, so both ordered lists are always present: a bullet it doesn't
    /// keep or rewrite comes off the résumé.
    static func makeTailoringPlan(from plan: ResumeEditPlanDTO, context: ResumeEditPlanContext) -> TailoringPlan {
        let bulletsByID = Dictionary(context.experiences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let employmentsByID = ResumeContentGrouping.employmentsByID(context.employments)

        // `order` only ranks bullets inside their group; groups keep ApplyKit's
        // own order (the renderer re-sorts them by employment anyway).
        func ordered(_ edits: [BulletEditDTO]) -> [UUID] {
            edits.filter(\.isRetained)
                .compactMap { edit -> (id: UUID, rank: Int, group: String, order: Int)? in
                    guard let id = UUID(uuidString: edit.id), let bullet = bulletsByID[id] else { return nil }
                    let rank = bullet.employmentID.flatMap { employmentsByID[$0]?.displayOrder } ?? Int.max
                    return (id, rank, bullet.employmentID?.uuidString ?? "", edit.order ?? Int.max)
                }
                .sorted { ($0.rank, $0.group, $0.order) < ($1.rank, $1.group, $1.order) }
                .map(\.id)
        }

        // Work bullets carry their employer's role line as the employment id.
        // One the plan places takes its numbered slot; every other goes back in
        // front of the bullet it preceded before (or last, when nothing it
        // preceded survives). Every marker is explicit, so `applySelection`
        // never has to guess — and an employer the plan says nothing about
        // keeps its line where it was.
        let roleSlots = Dictionary(
            placedRoleLines(in: plan, employmentsByID: employmentsByID).map { ($0.employmentID, $0.placement.order) },
            uniquingKeysWith: { first, _ in first })
        func orderedWork() -> [UUID] {
            let items = plan.experience.filter(\.isRetained).compactMap { edit -> (id: UUID, employmentID: UUID?, order: Int)? in
                guard let id = UUID(uuidString: edit.id), let bullet = bulletsByID[id] else { return nil }
                return (id, bullet.employmentID, edit.order ?? Int.max)
            }
            let groups = Dictionary(grouping: items) { $0.employmentID }
            let keys = groups.keys.sorted { lhs, rhs in
                let lo = lhs.flatMap { employmentsByID[$0]?.displayOrder } ?? Int.max
                let ro = rhs.flatMap { employmentsByID[$0]?.displayOrder } ?? Int.max
                return lo != ro ? lo < ro : (lhs?.uuidString ?? "") < (rhs?.uuidString ?? "")
            }
            var result: [UUID] = []
            for key in keys {
                var lines = (groups[key] ?? []).sorted { $0.order < $1.order }.map(\.id)
                if let employmentID = key {
                    if let slot = roleSlots[employmentID] {
                        // Orders run 1…n with the role line counted, so its slot
                        // is its index among the sorted bullets.
                        lines.insert(employmentID, at: min(slot - 1, lines.count))
                    } else if let marker = context.currentExperienceOrder.firstIndex(of: employmentID) {
                        let successor = context.currentExperienceOrder[(marker + 1)...].first(where: lines.contains)
                        lines.insert(employmentID, at: successor.flatMap(lines.firstIndex(of:)) ?? lines.count)
                    }
                }
                result += lines
            }
            return result
        }

        let summary: String? = switch plan.summary.action {
        case .keep: nil
        case .replace: plan.summary.text?.trimmed
        case .drop: ""
        }

        // Sections the plan leaves out don't render; appending them keeps the
        // order comparable with `sectionOrder`, which always lists every kind.
        let listed = plan.sectionOrder.map(\.kind)
        let sectionOrder = listed + ResumeSectionKind.defaultOrder.filter { !listed.contains($0) }

        let edits = plan.experience + plan.projects
        func replacement(_ edit: BulletEditDTO, isProject: Bool) -> TailoringPlan.Replacement? {
            guard edit.action == .rewrite, let id = UUID(uuidString: edit.id), let text = edit.text else { return nil }
            return TailoringPlan.Replacement(experienceID: id, text: isProject ? projectVariantText(text) : text.trimmed,
                                             name: edit.variantTitle?.trimmed)
        }
        let replacements = plan.experience.compactMap { replacement($0, isProject: false) }
            + plan.projects.compactMap { replacement($0, isProject: true) }
        let drops = edits.compactMap { edit -> TailoringPlan.Drop? in
            guard edit.action == .drop, let id = UUID(uuidString: edit.id) else { return nil }
            return TailoringPlan.Drop(experienceID: id)
        }

        // keep → shown as is, rewrite → shown with new wording, hide → hidden.
        // Where the line sits among the bullets is left alone.
        let roleDescriptions = plan.roleDescriptions.compactMap { edit -> TailoringPlan.RoleDescription? in
            guard let id = UUID(uuidString: edit.employmentID) else { return nil }
            return TailoringPlan.RoleDescription(employmentID: id, include: edit.action != .hide,
                                                 text: edit.action == .rewrite ? edit.text?.trimmed : nil)
        }

        return TailoringPlan(
            summary: summary,
            skillsLatex: skillsLatex(rows: plan.skills.rows),
            sectionOrder: sectionOrder.map(\.rawValue),
            orderedExperienceIDs: orderedWork(),
            orderedProjectIDs: ordered(plan.projects),
            replacements: replacements.isEmpty ? nil : replacements,
            roleDescriptions: roleDescriptions.isEmpty ? nil : roleDescriptions,
            drops: drops.isEmpty ? nil : drops
        )
    }

    /// A project rewrite as one variant in the stored convention: several
    /// points each open with `\item`; a single point stays plain.
    static func projectVariantText(_ text: String) -> String {
        let points = lines(of: text)
        guard points.count > 1 else { return points.first ?? text.trimmed }
        return points.map { "\\item \($0)" }.joined(separator: "\n")
    }

    /// The fixed three-row Skills table, in the same shape as the hand-written
    /// blocks in the workspace. Labels and skills are plain text, so everything
    /// is escaped: `C++`, `R&D`, `snake_case`.
    static func skillsLatex(rows: [SkillRowDTO]) -> String {
        let lines = rows.map { row -> String in
            let label = ResumeRenderer.escapeLatex(normalizedLabel(row.label))
            let items = row.items.map { ResumeRenderer.escapeLatex($0.trimmed) }.joined(separator: ", ")
            return "  \\textbf{\(label):} & \(items) \\\\"
        }
        return """
        \\begin{tabular}{@{} >{\\bfseries}l @{\\hspace{2ex}} >{\\raggedright\\arraybackslash}p{\(ResumeEditPlanDTO.skillsContentWidth)}}
        \(lines.joined(separator: "\n"))
        \\end{tabular}
        """
    }
}

// MARK: - Schema validation

/// Hand-written equivalent of the bundled v1.0 JSON Schema
/// (`ResumeEditPlanPrompt.schemaJSON`), run over `JSONSerialization` output so
/// unknown keys, wrong types, and action/field mismatches are reported with a
/// JSON Pointer rather than as a bare decoding failure.
private struct SchemaValidator {
    var issues: [ResumeEditPlanIssue] = []

    private mutating func fail(_ path: String, _ message: String, code: String = "schema.invalid") {
        issues.append(ResumeEditPlanIssue(.error, code, path: path, message))
    }

    private static func pointer(_ base: String, _ token: String) -> String {
        base + "/" + token.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    // MARK: Types

    private static func isNull(_ value: Any) -> Bool { value is NSNull }

    private static func string(_ value: Any) -> String? { value as? String }

    private static func number(_ value: Any) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    private static func integer(_ value: Any) -> Int? {
        guard let number = number(value), number.rounded() == number, abs(number) < 1e9 else { return nil }
        return Int(number)
    }

    /// Reports unknown and missing keys. Returns the object for further checks.
    @discardableResult
    private mutating func object(_ value: Any, at path: String, keys: [String]) -> [String: Any]? {
        guard let object = value as? [String: Any] else {
            fail(path, "Must be an object.")
            return nil
        }
        for key in object.keys.sorted() where !keys.contains(key) {
            fail(Self.pointer(path, key), "Unknown field \"\(key)\".")
        }
        for key in keys where object[key] == nil {
            fail(Self.pointer(path, key), "Missing required field \"\(key)\".")
        }
        return object
    }

    private mutating func string(_ value: Any, at path: String, maxLength: Int) {
        guard let text = Self.string(value) else {
            fail(path, "Must be a string.")
            return
        }
        if text.isEmpty { fail(path, "Must not be empty.") }
        if text.count > maxLength { fail(path, "Must be at most \(maxLength) characters (is \(text.count)).") }
    }

    private mutating func null(_ value: Any?, at path: String, because reason: String) {
        guard let value, !Self.isNull(value) else { return }
        fail(path, "Must be null \(reason).")
    }

    // MARK: Plan

    mutating func validatePlan(_ value: Any) {
        guard let plan = object(value, at: "", keys: [
            "schema_version", "fit_score", "section_order", "summary", "skills", "experience", "projects",
            "role_descriptions"
        ]) else { return }

        if let version = plan["schema_version"] {
            if let text = Self.string(version) {
                if text != ResumeEditPlanDTO.supportedVersion {
                    fail("/schema_version",
                         "Unsupported schema version \"\(text)\". ApplyKit supports version \(ResumeEditPlanDTO.supportedVersion).",
                         code: "schema.version")
                }
            } else {
                fail("/schema_version", "Must be the string \"\(ResumeEditPlanDTO.supportedVersion)\".")
            }
        }

        if let score = plan["fit_score"] {
            if let value = Self.number(score) {
                if !(0...10).contains(value) { fail("/fit_score", "Must be between 0 and 10 (is \(value)).") }
            } else {
                fail("/fit_score", "Must be a number.")
            }
        }

        if let order = plan["section_order"] { validateSectionOrder(order) }
        if let summary = plan["summary"] { validateSummary(summary) }
        if let skills = plan["skills"] { validateSkills(skills) }
        for section in ["experience", "projects"] {
            guard let value = plan[section] else { continue }
            guard let edits = value as? [Any] else {
                fail("/\(section)", "Must be an array.")
                continue
            }
            for (index, edit) in edits.enumerated() {
                validateBulletEdit(edit, at: "/\(section)/\(index)")
            }
        }
        if let value = plan["role_descriptions"] {
            if let edits = value as? [Any] {
                for (index, edit) in edits.enumerated() {
                    validateRoleDescriptionEdit(edit, at: "/role_descriptions/\(index)")
                }
            } else {
                fail("/role_descriptions", "Must be an array.")
            }
        }
    }

    private mutating func validateRoleDescriptionEdit(_ value: Any, at path: String) {
        guard let edit = object(value, at: path, keys: ["employment_id", "action", "order", "text"]) else { return }
        if let id = edit["employment_id"] { string(id, at: path + "/employment_id", maxLength: 255) }
        let order = edit["order"]
        if let order, !Self.isNull(order) {
            if let value = Self.integer(order) {
                if value < 1 { fail(path + "/order", "Must be 1 or more.") }
            } else {
                fail(path + "/order", "Must be a whole number or null.")
            }
        }
        if let text = edit["text"], !Self.isNull(text), Self.string(text) == nil {
            fail(path + "/text", "Must be a string or null.")
        }
        guard let raw = edit["action"] else { return }
        guard let action = Self.string(raw).flatMap(RoleDescriptionAction.init(rawValue:)) else {
            fail(path + "/action", "Must be one of: keep, rewrite, hide.")
            return
        }
        if action == .hide {
            null(order, at: path + "/order", because: "for a hidden role description")
        }
        guard let text = edit["text"] else { return }
        switch action {
        case .rewrite:
            if Self.isNull(text) {
                fail(path + "/text", "A rewritten role description needs a text.")
            } else if Self.string(text) != nil {
                string(text, at: path + "/text", maxLength: 500)
            }
        case .keep, .hide:
            null(text, at: path + "/text", because: action == .keep
                 ? "when the role description is kept — use rewrite to change the wording"
                 : "when the role description is hidden")
        }
    }

    private mutating func validateSectionOrder(_ value: Any) {
        guard let keys = value as? [Any] else {
            fail("/section_order", "Must be an array.")
            return
        }
        if keys.isEmpty || keys.count > ResumeSectionKey.allCases.count {
            fail("/section_order", "Must list between 1 and \(ResumeSectionKey.allCases.count) sections.")
        }
        let allowed = ResumeSectionKey.allCases.map(\.rawValue)
        var seen: Set<String> = []
        for (index, key) in keys.enumerated() {
            let path = "/section_order/\(index)"
            guard let key = Self.string(key), allowed.contains(key) else {
                fail(path, "Must be one of: \(allowed.joined(separator: ", ")).")
                continue
            }
            if !seen.insert(key).inserted { fail(path, "\"\(key)\" is listed twice.") }
        }
    }

    private mutating func validateSummary(_ value: Any) {
        guard let summary = object(value, at: "/summary", keys: ["action", "text"]) else { return }
        guard let raw = summary["action"] else { return }
        guard let action = Self.string(raw).flatMap(SummaryAction.init(rawValue:)) else {
            fail("/summary/action", "Must be one of: keep, replace, drop.")
            return
        }
        guard let text = summary["text"] else { return }
        switch action {
        case .replace:
            string(text, at: "/summary/text", maxLength: 2000)
        case .keep, .drop:
            null(text, at: "/summary/text", because: "when the summary is \(action == .keep ? "kept" : "dropped")")
        }
    }

    private mutating func validateSkills(_ value: Any) {
        guard let skills = object(value, at: "/skills", keys: ["action", "content_width", "rows"]) else { return }
        if let action = skills["action"], Self.string(action) != SkillsAction.replace.rawValue {
            fail("/skills/action", "Must be \"replace\".")
        }
        if let width = skills["content_width"], Self.string(width) != ResumeEditPlanDTO.skillsContentWidth {
            fail("/skills/content_width", "Must be the JSON string \"0.74\\\\textwidth\".")
        }
        guard let value = skills["rows"] else { return }
        guard let rows = value as? [Any] else {
            fail("/skills/rows", "Must be an array.")
            return
        }
        if rows.count != ResumeEditPlanDTO.skillsRowCount {
            fail("/skills/rows", "Must have exactly \(ResumeEditPlanDTO.skillsRowCount) rows (has \(rows.count)).")
        }
        for (index, row) in rows.enumerated() {
            let path = "/skills/rows/\(index)"
            guard let row = object(row, at: path, keys: ["label", "items"]) else { continue }
            if let label = row["label"] { string(label, at: path + "/label", maxLength: 40) }
            guard let value = row["items"] else { continue }
            guard let items = value as? [Any] else {
                fail(path + "/items", "Must be an array.")
                continue
            }
            if items.isEmpty { fail(path + "/items", "Must list at least one skill.") }
            for (itemIndex, item) in items.enumerated() {
                string(item, at: path + "/items/\(itemIndex)", maxLength: 80)
            }
        }
    }

    private mutating func validateBulletEdit(_ value: Any, at path: String) {
        guard let edit = object(value, at: path, keys: ["id", "action", "order", "variant_title", "text"]) else { return }
        if let id = edit["id"] { string(id, at: path + "/id", maxLength: 255) }

        let order = edit["order"]
        if let order, !Self.isNull(order) {
            if let value = Self.integer(order) {
                if value < 1 { fail(path + "/order", "Must be 1 or more.") }
            } else {
                fail(path + "/order", "Must be a whole number or null.")
            }
        }
        for key in ["variant_title", "text"] {
            if let field = edit[key], !Self.isNull(field), Self.string(field) == nil {
                fail(path + "/\(key)", "Must be a string or null.")
            }
        }

        guard let raw = edit["action"] else { return }
        guard let action = Self.string(raw).flatMap(BulletAction.init(rawValue:)) else {
            fail(path + "/action", "Must be one of: keep, rewrite, drop.")
            return
        }
        let orderMissing = order.map(Self.isNull) ?? false
        switch action {
        case .keep:
            if orderMissing { fail(path + "/order", "A kept bullet needs an order.") }
            null(edit["variant_title"], at: path + "/variant_title", because: "for a kept bullet")
            null(edit["text"], at: path + "/text", because: "for a kept bullet — use rewrite to change the wording")
        case .rewrite:
            if orderMissing { fail(path + "/order", "A rewritten bullet needs an order.") }
            for (key, limit) in [("variant_title", 80), ("text", 1000)] {
                guard let field = edit[key] else { continue }
                if Self.isNull(field) {
                    fail(path + "/\(key)", "A rewritten bullet needs a \(key).")
                } else if Self.string(field) != nil {
                    // A non-string was already reported above.
                    string(field, at: path + "/\(key)", maxLength: limit)
                }
            }
        case .drop:
            null(order, at: path + "/order", because: "for a dropped bullet")
            null(edit["variant_title"], at: path + "/variant_title", because: "for a dropped bullet")
            null(edit["text"], at: path + "/text", because: "for a dropped bullet")
        }
    }
}
