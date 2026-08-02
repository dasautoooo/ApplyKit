//
//  ApplicationEditorTailoring.swift
//  ApplyKit
//
//  "Apply a suggestion" flow: paste a ChatGPT tailoring reply, reconcile it into
//  a TailoringPlan via a local AI call, then apply the resulting changes one-by-one
//  or all at once. See TailoringPlan.swift and the reconciliation prompt in
//  PromptBuilder.
//

import AppKit
import SwiftUI

/// One reviewable, individually-applyable edit derived from a `TailoringPlan`.
struct TailoringChange: Identifiable {
    enum Action {
        case summary(String)
        case skills(String)
        case sectionOrder([ResumeSectionKind])
        /// `nil` dimension = leave that dimension's selection/order unchanged.
        case selection(work: [UUID]?, projects: [UUID]?)
        case replacement(ResolvedReplacement)
        /// Per-employment role-description line: `include` toggles visibility
        /// (nil = leave as-is), `text` overrides the wording (nil = keep current).
        case roleDescription(employmentID: UUID, include: Bool?, text: String?)
    }

    let id: String
    let title: String
    let detail: String
    let before: String?
    let after: String?
    let blockedReason: String?
    let action: Action
    var applied: Bool

    var isBlocked: Bool { blockedReason != nil }
}

/// A tailored bullet rewrite resolved against the experience bank.
struct ResolvedReplacement {
    let experienceID: UUID
    let text: String
    let name: String
    let reason: String
    let originalText: String
    let isProject: Bool
}

extension ApplicationEditorView {

    // MARK: - Copy context for ChatGPT

    /// The `Copy Context` prompt with ids embedded inline in the résumé section
    /// (so bullet text is never duplicated), plus only the bullets that aren't
    /// currently selected, and a short note on referencing ids. This is what the
    /// user pastes into ChatGPT so its reply can be reconciled unambiguously.
    func tailoringContextText() -> String {
        let base = applicationContextText(includeAnalysis: true, includeIDs: true)
        let selected = application.selectedExperienceIDs.union(application.selectedProjectIDs)
        let employmentsByID = Dictionary(uniqueKeysWithValues: employments.map { ($0.id, $0) })
        let unselected = experiences
            .filter { !selected.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }

        var parts = [base]

        if !unselected.isEmpty {
            let lines = unselected.map { exp -> String in
                let source = exp.employmentID.flatMap { employmentsByID[$0]?.companyName }
                    ?? (exp.company.trimmed.isEmpty ? "Personal" : exp.company)
                return "- [id: \(exp.id.uuidString)] (\(source)) \(exp.bulletText.trimmed)"
            }.joined(separator: "\n")
            parts.append("## Other Available Bullets (not currently selected)\n\(lines)")
        }

        parts.append("""
        ## Referencing bullets
        Each bullet above is tagged `[id: …]`, each project `[id: …]`, and each employment \
        `(employment_id: …)`. When you propose which bullets to select, drop, reorder, or \
        rewrite, refer to them by these ids so the edits can be applied automatically.
        """)

        return parts.joined(separator: "\n\n---\n\n")
    }

    func copyTailoringContext() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(tailoringContextText(), forType: .string)
        activityMonitor.succeed("Tailoring context copied. Paste it into ChatGPT.")
    }

    // MARK: - Reconcile

    func reconcileTailoring(pastedReply: String) async {
        guard aiBackendPath != nil else { return }
        let reply = pastedReply.trimmed
        guard !reply.isEmpty else { return }
        await MainActor.run {
            isReconcilingTailoring = true
            activityMonitor.start("Reconciling tailoring suggestion…")
        }
        do {
            let prompt = PromptBuilder.tailoringReconciliationPrompt(
                pastedReply: reply,
                application: application,
                allExperiences: experiences,
                employments: employments
            )
            let response = try await runAI(prompt: prompt)
            let plan = TailoringPlan.parse(from: response)
            await MainActor.run {
                isReconcilingTailoring = false
                guard let plan, !plan.isEmpty else {
                    activityMonitor.fail("Couldn't extract any changes from that suggestion. Try re-pasting the full reply.")
                    return
                }
                tailoringPlan = plan
                tailoringChanges = buildTailoringChanges(from: plan)
                persistTailoringSession()
                let count = tailoringChanges.filter { !$0.isBlocked }.count
                activityMonitor.succeed("Found \(count) change\(count == 1 ? "" : "s") to review.")
            }
        } catch {
            await MainActor.run {
                isReconcilingTailoring = false
                activityMonitor.fail(error.localizedDescription)
            }
        }
    }

    // MARK: - Build changes

    func buildTailoringChanges(from plan: TailoringPlan) -> [TailoringChange] {
        let alreadyApplied = Set(TailoringSession.decode(application.tailoringPlanData)?.appliedChangeIDs ?? [])
        func applied(_ id: String) -> Bool { alreadyApplied.contains(id) }

        var changes: [TailoringChange] = []

        if let summary = plan.summary?.trimmed, !summary.isEmpty, summary != application.summaryText.trimmed {
            changes.append(TailoringChange(
                id: "summary",
                title: "Update professional summary",
                detail: "Replace the summary with the tailored version.",
                before: application.summaryText.trimmed.isEmpty ? nil : application.summaryText,
                after: summary,
                blockedReason: nil,
                action: .summary(summary),
                applied: applied("summary")
            ))
        }

        if let skills = plan.skillsLatex?.trimmed, !skills.isEmpty, skills != application.skillsBlockText.trimmed {
            changes.append(TailoringChange(
                id: "skills",
                title: "Update skills block",
                detail: "Replace the LaTeX skills block with the tailored version.",
                before: application.skillsBlockText.trimmed.isEmpty ? nil : application.skillsBlockText,
                after: skills,
                blockedReason: nil,
                action: .skills(skills),
                applied: applied("skills")
            ))
        }

        if let rawOrder = plan.sectionOrder {
            let order = rawOrder.compactMap { ResumeSectionKind(rawValue: $0) }
            if !order.isEmpty, order != application.sectionOrder {
                changes.append(TailoringChange(
                    id: "sectionOrder",
                    title: "Reorder résumé sections",
                    detail: order.map(\.rawValue).joined(separator: " → "),
                    before: application.sectionOrder.map(\.rawValue).joined(separator: " → "),
                    after: order.map(\.rawValue).joined(separator: " → "),
                    blockedReason: nil,
                    action: .sectionOrder(order),
                    applied: applied("sectionOrder")
                ))
            }
        }

        if plan.orderedExperienceIDs != nil || plan.orderedProjectIDs != nil {
            let workIDs = Set(experiences.filter { isWorkLikeSelection($0) }.map(\.id))
            let projectIDs = Set(experiences.filter { isProjectLikeSelection($0) }.map(\.id))
            let work = plan.orderedExperienceIDs.map { $0.filter(workIDs.contains) }
            let projects = plan.orderedProjectIDs.map { $0.filter(projectIDs.contains) }

            var parts: [String] = []
            if let work { parts.append("\(work.count) experience bullet\(work.count == 1 ? "" : "s")") }
            if let projects { parts.append("\(projects.count) project\(projects.count == 1 ? "" : "s")") }
            let selectedSummary = parts.joined(separator: " and ")

            changes.append(TailoringChange(
                id: "selection",
                title: "Apply bullet selection & order",
                detail: "Select \(selectedSummary) in the suggested order; drop the rest.",
                before: nil,
                after: nil,
                blockedReason: nil,
                action: .selection(work: work, projects: projects),
                applied: applied("selection")
            ))
        }

        for replacement in plan.replacements ?? [] {
            let id = "replacement:\(replacement.experienceID.uuidString)"
            guard let bullet = experiences.first(where: { $0.id == replacement.experienceID }) else {
                changes.append(TailoringChange(
                    id: id,
                    title: "Tailored bullet rewrite",
                    detail: "The referenced bullet no longer exists in your experience bank.",
                    before: nil,
                    after: replacement.text,
                    blockedReason: "Bullet id not found — it may have been deleted since you copied the context.",
                    action: .replacement(ResolvedReplacement(
                        experienceID: replacement.experienceID, text: replacement.text,
                        name: replacement.name ?? "", reason: replacement.reason ?? "",
                        originalText: "", isProject: false)),
                    applied: false
                ))
                continue
            }
            // "Current" reflects the wording this application actually renders —
            // the selected variant, not the shared base text.
            let currentText = bullet.bulletText(variantID: application.selectedVariantID(for: bullet.id))
            let resolved = ResolvedReplacement(
                experienceID: bullet.id,
                text: replacement.text,
                name: replacement.name?.trimmed.isEmpty == false ? replacement.name!.trimmed
                    : ExperienceVariation.defaultName(existing: bullet.variations),
                reason: replacement.reason ?? "",
                originalText: currentText,
                isProject: isProjectLikeSelection(bullet)
            )
            changes.append(TailoringChange(
                id: id,
                title: "Rewrite: \(bullet.displayTitle)",
                detail: replacement.reason ?? "Tailored wording for this bullet.",
                before: currentText,
                after: replacement.text,
                blockedReason: nil,
                action: .replacement(resolved),
                applied: applied(id)
            ))
        }

        for role in plan.roleDescriptions ?? [] {
            let id = "role:\(role.employmentID.uuidString)"
            guard let employment = employments.first(where: { $0.id == role.employmentID }) else {
                changes.append(TailoringChange(
                    id: id,
                    title: "Role description",
                    detail: "The referenced employment no longer exists.",
                    before: nil,
                    after: nil,
                    blockedReason: "Employment id not found — it may have changed since you copied the context.",
                    action: .roleDescription(employmentID: role.employmentID, include: role.include, text: role.text),
                    applied: false
                ))
                continue
            }
            let currentlyHidden = application.isRoleDescriptionHidden(for: employment.id)
            let currentText = (application.roleDescription(for: employment.id) ?? employment.roleDescription).trimmed
            let newText = role.text?.trimmed
            let textChanges = (newText?.isEmpty == false) && newText! != currentText
            // `include == currentlyHidden` is true exactly when the requested
            // visibility differs from the current state (want-shown while hidden,
            // or want-hidden while shown).
            let inclusionChanges = role.include.map { $0 == currentlyHidden } ?? false
            guard textChanges || inclusionChanges else { continue }

            var detailParts: [String] = []
            if inclusionChanges { detailParts.append(role.include == true ? "Show the role-description line" : "Hide the role-description line") }
            if textChanges { detailParts.append("Update the role-description wording") }

            let afterText: String
            if textChanges { afterText = newText! }
            else { afterText = role.include == true ? "(show role description)" : "(hide role description)" }

            changes.append(TailoringChange(
                id: id,
                title: "Role description: \(employment.companyName)",
                detail: detailParts.joined(separator: "; ") + ".",
                before: currentText.isEmpty ? (currentlyHidden ? "(hidden)" : nil) : "\(currentlyHidden ? "(hidden) " : "")\(currentText)",
                after: afterText,
                blockedReason: nil,
                action: .roleDescription(employmentID: employment.id, include: role.include, text: newText),
                applied: applied(id)
            ))
        }

        return changes
    }

    // MARK: - Apply

    func applyTailoringChange(_ change: TailoringChange) {
        guard !change.isBlocked, !change.applied else { return }
        switch change.action {
        case .summary(let text):
            application.summaryText = text
        case .skills(let text):
            application.skillsBlockText = text
        case .sectionOrder(let order):
            application.setSectionOrder(order)
        case .selection(let work, let projects):
            applySelection(work: work, projects: projects)
        case .replacement(let replacement):
            applyReplacement(replacement)
        case .roleDescription(let employmentID, let include, let text):
            if let text, !text.trimmed.isEmpty {
                application.setRoleDescription(text, for: employmentID)
            }
            if let include {
                application.setRoleDescriptionHidden(!include, for: employmentID)
            }
        }
        markApplied(change.id)
        persistApplicationChanges()
    }

    func applyAllTailoring() {
        for change in tailoringChanges where !change.isBlocked && !change.applied {
            applyTailoringChange(change)
        }
    }

    private func applySelection(work: [UUID]?, projects: [UUID]?) {
        if let work {
            let target = Set(work)
            for exp in experiences where isWorkLikeSelection(exp) {
                application.setExperience(exp.id, selected: target.contains(exp.id))
            }
        }
        if let projects {
            let target = Set(projects)
            for exp in experiences where isProjectLikeSelection(exp) {
                application.setProject(exp.id, selected: target.contains(exp.id))
            }
        }
        // Rebuild the flat order: use the provided lists where given, otherwise keep
        // the current relative order of that dimension's still-selected bullets.
        let currentOrder = application.experienceOrder
        let selectedWork = application.selectedExperienceIDs
        let selectedProjects = application.selectedProjectIDs
        let workOrder = work ?? currentOrder.filter { selectedWork.contains($0) }
        let projectOrder = projects ?? currentOrder.filter { selectedProjects.contains($0) }
        application.setExperienceOrder(workOrder + projectOrder)
    }

    private func applyReplacement(_ replacement: ResolvedReplacement) {
        guard let idx = store.experiences.firstIndex(where: { $0.id == replacement.experienceID }) else { return }
        var bullet = store.experiences[idx]
        let variant = ExperienceVariation(
            name: replacement.name.isEmpty ? ExperienceVariation.defaultName(existing: bullet.variations) : replacement.name,
            bulletText: replacement.text,
            notes: replacement.reason
        )
        bullet.variations.append(variant)
        store.experiences[idx] = bullet
        persistExperienceChanges(bullet)

        if replacement.isProject {
            application.setProject(replacement.experienceID, selected: true)
        } else {
            application.setExperience(replacement.experienceID, selected: true)
        }
        application.setVariant(variant.id, for: replacement.experienceID)
    }

    // MARK: - Session persistence

    private func markApplied(_ id: String) {
        if let idx = tailoringChanges.firstIndex(where: { $0.id == id }) {
            tailoringChanges[idx].applied = true
        }
        persistTailoringSession()
    }

    func persistTailoringSession() {
        let appliedIDs = tailoringChanges.filter(\.applied).map(\.id)
        let session = TailoringSession(pastedText: tailoringPastedText, plan: tailoringPlan, appliedChangeIDs: appliedIDs)
        application.tailoringPlanData = session.encoded()
    }

    /// Restore a persisted session (raw paste + plan + applied markers) when the
    /// sheet opens, so multi-round progress survives close / relaunch.
    func restoreTailoringSession() {
        guard tailoringChanges.isEmpty,
              let session = TailoringSession.decode(application.tailoringPlanData) else { return }
        tailoringPastedText = session.pastedText
        tailoringPlan = session.plan
        if let plan = session.plan {
            tailoringChanges = buildTailoringChanges(from: plan)
        }
    }

    func clearTailoringSession() {
        tailoringPastedText = ""
        tailoringPlan = nil
        tailoringChanges = []
        application.tailoringPlanData = ""
        persistApplicationChanges()
    }
}
