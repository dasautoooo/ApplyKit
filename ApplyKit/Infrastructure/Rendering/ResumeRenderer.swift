import Foundation

enum ResumeRenderer {
    static let sectionsPlaceholder = "{{APPLYKIT_SECTIONS}}"

    struct RenderResult { let rendered: String; let warnings: [String] }

    static func render(template: String, variantSelections: [UUID: UUID],
                       selectedExperiences: [ExperienceBullet], selectedProjects: [ExperienceBullet],
                       employments: [Employment], roleDescriptionOverrides: [UUID: String] = [:],
                       experienceOrder: [UUID] = [],
                       educationBlock: String = "", skillsBlock: String = "", summary: String = "",
                       sectionOrder: [ResumeSectionKind] = ResumeSectionKind.defaultOrder) -> RenderResult {
        let orderIndex = Dictionary(uniqueKeysWithValues: experienceOrder.enumerated().map { ($0.element, $0.offset) })
        let experience = experienceBlock(selectedExperiences: selectedExperiences,
                                         variantSelections: variantSelections, employments: employments,
                                         roleDescriptionOverrides: roleDescriptionOverrides, orderIndex: orderIndex)
        let projects = projectBlock(selectedProjects: selectedProjects,
                                     variantSelections: variantSelections, employments: employments, orderIndex: orderIndex)
        let sectionBlocks: [ResumeSectionKind: String] = [
            .summary: summarySection(summary),
            .education: wrappedSection(title: "Education", content: educationBlock),
            .experience: wrappedSection(title: "Experience", content: experience.block),
            .projects: wrappedSection(title: "Selected Projects", content: projects.block),
            .skills: wrappedSection(title: "Skills", content: skillsBlock)
        ]
        let sectionsText = sectionOrder
            .compactMap { sectionBlocks[$0] }
            .filter { !$0.trimmed.isEmpty }
            .joined(separator: "\n\n")
        let rendered = template.replacingOccurrences(of: sectionsPlaceholder, with: sectionsText)
        return RenderResult(rendered: rendered, warnings: experience.warnings + projects.warnings)
    }

    /// Wrap the summary in its own `rSection`, or return empty so the section is omitted
    /// entirely when the application has no summary.
    static func summarySection(_ summary: String) -> String {
        guard !summary.trimmed.isEmpty else { return "" }
        return wrappedSection(title: "Summary", content: summary)
    }

    private static func wrappedSection(title: String, content: String) -> String {
        """
        \\begin{rSection}{\(title)}

        \(content)

        \\end{rSection}
        """
    }

    static func experienceBlock(selectedExperiences: [ExperienceBullet], variantSelections: [UUID: UUID],
                                 employments: [Employment],
                                 roleDescriptionOverrides: [UUID: String] = [:],
                                 orderIndex: [UUID: Int] = [:]) -> (block: String, warnings: [String]) {
        guard !selectedExperiences.isEmpty else { return ("% No experience bullets selected.", []) }
        let employmentsByID = Dictionary(uniqueKeysWithValues: employments.map { ($0.id, $0) })
        var grouped: [UUID: [ExperienceBullet]] = [:]
        var orphanCount = 0
        for bullet in selectedExperiences {
            guard let empID = bullet.employmentID, employmentsByID[empID] != nil else { orphanCount += 1; continue }
            grouped[empID, default: []].append(bullet)
        }
        let groups: [(Employment, [ExperienceBullet])] = grouped.compactMap { id, bullets in
            guard let emp = employmentsByID[id] else { return nil }
            return (emp, bullets.sorted { lhs, rhs in
                let li = orderIndex[lhs.id] ?? Int.max
                let ri = orderIndex[rhs.id] ?? Int.max
                return li != ri ? li < ri : lhs.createdAt < rhs.createdAt
            })
        }.sorted { lhs, rhs in
            lhs.0.displayOrder != rhs.0.displayOrder
                ? lhs.0.displayOrder < rhs.0.displayOrder
                : lhs.0.companyName.lowercased() < rhs.0.companyName.lowercased()
        }
        let separator = "%------------------------------------------------"
        var rendered: [String] = []
        for (index, group) in groups.enumerated() {
            if index > 0 { rendered.append("\n\(separator)\n") }
            rendered.append(renderSubsection(employment: group.0, bullets: group.1, variantSelections: variantSelections,
                                             roleDescriptionOverride: roleDescriptionOverrides[group.0.id]))
        }
        var warnings: [String] = []
        if orphanCount > 0 { warnings.append("\(orphanCount) selected experience(s) skipped because they have no employment record.") }
        let block = rendered.joined(separator: "\n")
        return (block.isEmpty ? "% No experience bullets selected." : block, warnings)
    }

    static func projectBlock(selectedProjects: [ExperienceBullet], variantSelections: [UUID: UUID],
                              employments: [Employment], orderIndex: [UUID: Int] = [:]) -> (block: String, warnings: [String]) {
        guard !selectedProjects.isEmpty else { return ("% No projects selected.", []) }
        let employmentsByID = Dictionary(uniqueKeysWithValues: employments.map { ($0.id, $0) })
        let sorted = selectedProjects.sorted { lhs, rhs in
            let lo = lhs.employmentID.flatMap { employmentsByID[$0] }?.displayOrder ?? Int.max
            let ro = rhs.employmentID.flatMap { employmentsByID[$0] }?.displayOrder ?? Int.max
            if lo != ro { return lo < ro }
            let li = orderIndex[lhs.id] ?? Int.max
            let ri = orderIndex[rhs.id] ?? Int.max
            return li != ri ? li < ri : lhs.createdAt < rhs.createdAt
        }
        let rendered = sorted.map {
            renderProjectSubsection(project: $0, variantID: variantSelections[$0.id],
                                    employment: $0.employmentID.flatMap { employmentsByID[$0] })
        }
        return (rendered.joined(separator: "\n\n"), [])
    }

    private static func renderSubsection(employment: Employment, bullets: [ExperienceBullet], variantSelections: [UUID: UUID],
                                         roleDescriptionOverride: String? = nil) -> String {
        var allItems: [String] = []
        let override = roleDescriptionOverride?.trimmed
        let roleDescription = (override?.isEmpty == false) ? override! : employment.roleDescription
        if !roleDescription.trimmed.isEmpty { allItems.append("    \\item \(roleDescription)") }
        allItems += bullets.map { "    \\item \($0.bulletText(variantID: variantSelections[$0.id]))" }
        return """
        \\begin{rSubsection}{\(escapeLatex(employment.companyName))}{\(escapeLatex(employment.dateRangeText()))}{\(escapeLatex(employment.role))}{\(escapeLatex(employment.location))}
        \(allItems.joined(separator: "\n"))
        \\end{rSubsection}
        """
    }

    private static func renderProjectSubsection(project: ExperienceBullet, variantID: UUID?, employment: Employment?) -> String {
        let title = projectTitle(project, employment: employment)
        let items = project.bulletText(variantID: variantID)
            .split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
            .map { line in line.hasPrefix("\\item") ? "    \(line)" : "    \\item \(line)" }
            .joined(separator: "\n")
        return """
        \\begin{rSubsection}{\(title)}{}{}{}
        \(items.isEmpty ? "    \\item % Empty project bullet." : items)
        \\end{rSubsection}
        """
    }

    private static func projectTitle(_ project: ExperienceBullet, employment: Employment?) -> String {
        // resumeDisplayName takes priority — passed through as raw LaTeX, no escaping.
        if !project.resumeDisplayName.trimmed.isEmpty { return project.resumeDisplayName }
        let name = project.displayTitle == "Untitled Experience" ? (employment?.displayTitle ?? project.displayTitle) : project.displayTitle
        // If the name already contains LaTeX commands, pass it through as-is (raw LaTeX mode).
        if name.contains("\\") { return name }
        let link = project.referenceURL.trimmed.isEmpty ? employment?.referenceURL.trimmed : project.referenceURL.trimmed
        if let link, !link.isEmpty { return "\\ulhref{\(link)}{\(escapeLatex(name))}" }
        return escapeLatex(name)
    }

    nonisolated static func escapeLatex(_ value: String) -> String {
        let sentinel = "\u{0001}BACKSLASH\u{0001}"
        var output = value.replacingOccurrences(of: "\\", with: sentinel)
        for ch in ["&", "%", "$", "#", "_", "{", "}"] { output = output.replacingOccurrences(of: ch, with: "\\\(ch)") }
        output = output.replacingOccurrences(of: "~", with: "\\textasciitilde{}")
        output = output.replacingOccurrences(of: "^", with: "\\textasciicircum{}")
        return output.replacingOccurrences(of: sentinel, with: "\\textbackslash{}")
    }
}
