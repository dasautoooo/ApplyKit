//
//  ApplicationEditorTailoring.swift
//  ApplyKit
//
//  Stage 2 of the Resume Tailor: turn an approved brief (via a local AI call)
//  or a pasted ChatGPT edit plan (read deterministically, see
//  ResumeEditPlanImporter.swift) into a TailoringPlan, then apply the
//  resulting changes one-by-one or all at once.
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
        /// Create a bullet the plan proposes from a confirmed fact. `toBank`
        /// decides whether it joins the shared experience bank or stays with
        /// this application.
        case newBullet(TailoringPlan.NewBullet, toBank: Bool)
        /// Take one bullet off this résumé. Only used when the plan names drops
        /// without also giving a full ordered selection — otherwise the
        /// selection change already removes it.
        case drop(experienceID: UUID)
        /// Not an edit: the plan's readiness verdict and open questions, shown at
        /// the end of the review list.
        case verdict
    }

    /// Which run proposed this — the two are reviewed together but come from
    /// different places and mean different things.
    enum Source: Hashable {
        case build
        case pdfCheck(round: Int)

        var heading: String {
            switch self {
            case .build: "From the build"
            case .pdfCheck(let round): "From the PDF check #\(round)"
            }
        }

        var caption: String {
            switch self {
            case .build: "Tailoring the résumé to this role."
            case .pdfCheck: "Fixing what the rendered file showed."
            }
        }
    }

    let id: String
    let title: String
    let detail: String
    let before: String?
    let after: String?
    let blockedReason: String?
    var action: Action
    var applied: Bool
    /// Clause-by-clause justification, shown under the summary change.
    var rationale: [TailoringPlan.SummaryClaim] = []
    /// Which hiring signal a rewrite improves.
    var signal: String?
    /// A fact to verify before submitting — advisory, never blocking.
    var confirmationNeeded: String?
    /// A problem ApplyKit spotted in the proposal itself, rather than one the
    /// model reported. Advisory: the rewrite is still offered.
    var caution: String?
    var source: Source = .build

    var isBlocked: Bool { blockedReason != nil }

    /// True for rows that only report something; they have no Apply button.
    var isInformational: Bool {
        if case .verdict = action { return true }
        return false
    }

    /// A new bullet is applied one of two ways, so its row offers both.
    var newBullet: TailoringPlan.NewBullet? {
        if case .newBullet(let bullet, _) = action { return bullet }
        return nil
    }
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

    /// The `Copy Context` prompt with ids embedded inline in the résumé section,
    /// plus the bullets that aren't currently selected, and the Resume Edit Plan
    /// v1.0 output contract. This is what the user pastes into ChatGPT; its
    /// reply is read by `importTailoringPlan` without any AI in between.
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

        parts.append(ResumeEditPlanPrompt.outputContract(
            experiences: experiences, employments: employments,
            selectedIDs: selected, variantSelections: application.selectedVariantIDs,
            roleDescriptions: application.employmentRoleDescriptions,
            hiddenRoleDescriptions: Set(employments.map(\.id).filter(application.isRoleDescriptionHidden(for:))),
            hasSummary: application.hasSummary,
            hasEducation: !store.profile.educationBlock.trimmed.isEmpty
        ))

        return parts.joined(separator: "\n\n---\n\n")
    }

    /// The brief and any answers, rendered for the pasted-reply route so an
    /// outside model starts from the same judgment the app already made.
    func tailoringBriefContextText() -> String {
        guard let brief = tailoringBrief else { return "" }
        var lines: [String] = []
        if let fit = brief.fitScoreText { lines.append("Fit: \(fit)\(brief.fitConfidence.map { " (\($0) confidence)" } ?? "")") }
        if let priority = brief.recommendedPriority { lines.append("Recommended priority: \(priority)") }
        if let tier = brief.investmentTier {
            lines.append("Investment: \(tier)\(brief.investmentTime.map { " (\($0))" } ?? "")")
        }
        if let story = brief.candidateStory { lines.append("Candidate story: \(story)") }
        if !brief.gaps.isEmpty {
            lines.append("Gaps:\n" + brief.gaps.map { "- [\($0.kind)] \($0.text)" }.joined(separator: "\n"))
        }
        if !brief.answeredQuestions.isEmpty {
            lines.append("Answered questions:\n" + brief.answeredQuestions
                .map { "- Q: \($0.question)\n  A: \($0.answer.trimmed)" }
                .joined(separator: "\n"))
        }
        return lines.isEmpty ? "" : "## Tailoring Brief\n\(lines.joined(separator: "\n"))"
    }

    func copyTailoringContext() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(tailoringContextText(), forType: .string)
        tailoringContextCopiedAt = Date()
        activityMonitor.succeed("Tailoring context copied. Paste it into ChatGPT.")
    }

    /// The clipboard's text, unless it's empty or still holds something this
    /// app copied out — the usual slip is pasting back before copying the reply.
    private func pastedReply(rejectingPrefix copiedPrefix: String, what: String) -> String? {
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmed.isEmpty else {
            activityMonitor.fail("The clipboard is empty. Copy the chat's reply first.")
            return nil
        }
        guard !text.trimmed.hasPrefix(copiedPrefix) else {
            activityMonitor.fail("The clipboard still holds the \(what) you copied. Copy the chat's reply instead.")
            return nil
        }
        return text
    }

    /// Step 2 in one click: take the reply off the clipboard and import it.
    /// The text stays in the editor below, opened when there's something to fix.
    func pasteAndImportTailoringPlan() {
        guard let text = pastedReply(rejectingPrefix: "# Application Context:", what: "context") else { return }
        tailoringPastedText = text
        importTailoringPlan(pasted: text)
        if tailoringImportIssues.contains(where: \.isError) { showPastedPlanText = true }
    }

    /// The same for a PDF review done in the chat.
    func pasteAndReadReview() {
        guard let text = pastedReply(rejectingPrefix: "Résumé for ", what: "PDF text") else { return }
        pastedReviewText = text
        Task { await reconcilePastedReview(text) }
    }

    // MARK: - Runs
    //
    // Both routes hand off to `TailoringRunner`; the resulting plan lands on the
    // stored record, and `adoptExternalTailoringState` turns it into reviewable
    // changes here whenever this editor is on screen.

    /// Stage 2: turn the approved brief — including any answers given during the
    /// clarify loop — into the same reviewable change list the paste route
    /// produces.
    func buildTailoringPlan() async {
        await tailoringRunner.build(applicationID: application.id)
    }

    /// Reads a pasted Resume Edit Plan. Any error leaves the current plan and
    /// résumé untouched; warnings are shown but don't block the import.
    func importTailoringPlan(pasted: String) {
        let context = ResumeEditPlanContext(
            experiences: experiences,
            employments: employments,
            hasSummary: application.hasSummary,
            hasEducation: !store.profile.educationBlock.trimmed.isEmpty,
            roleDescriptionOverrides: application.employmentRoleDescriptions,
            currentExperienceOrder: application.experienceOrder,
            selectedIDs: application.selectedExperienceIDs.union(application.selectedProjectIDs)
        )
        let result = ResumeEditPlanImporter.importPlan(from: pasted, context: context)
        tailoringImportIssues = result.issues
        guard let plan = result.plan else {
            activityMonitor.fail("The edit plan has \(result.errors.count) problem\(result.errors.count == 1 ? "" : "s") to fix.")
            return
        }

        // A fresh plan starts with no applied markers — they belong to the plan
        // they were recorded against. The raw paste is kept for traceability.
        appliedBeforeText = [:]
        revertPoints = [:]
        application.tailoringPlanData = TailoringSession(pastedText: pasted, plan: plan).encoded()
        if let index = store.applications.firstIndex(where: { $0.id == application.id }) {
            store.applications[index].tailoringPlanData = application.tailoringPlanData
        }
        // The plan's score lands on the brief, which also mirrors it to the
        // applications list. Everything else on the brief is left as it was.
        if let fitScore = result.fitScore {
            var brief = tailoringBrief ?? TailoringBrief()
            brief.fitScore = fitScore
            editingBrief = brief
            commitTailoringBrief()
        } else {
            persistApplicationChanges()
        }
        tailoringChanges = allTailoringChanges()

        let rewrites = plan.replacements?.count ?? 0
        activityMonitor.succeed("Imported the edit plan: \(rewrites) rewrite\(rewrites == 1 ? "" : "s") to review.")
    }

    // MARK: - Build changes

    /// Changes from the plan, followed by any the PDF check produced. Review
    /// edits carry a `pdf:` id prefix so their applied markers never collide
    /// with the build's, and a later check can supersede an earlier one.
    func allTailoringChanges() -> [TailoringChange] {
        var changes = tailoringPlan.map { buildTailoringChanges(from: $0) } ?? []
        if let review = storedApplication?.tailoringReview, let edits = review.edits {
            changes += buildTailoringChanges(from: edits, idPrefix: "pdf\(review.round):",
                                             source: .pdfCheck(round: review.round))
        }
        return changes
    }

    func buildTailoringChanges(from plan: TailoringPlan, idPrefix: String = "",
                               source: TailoringChange.Source = .build) -> [TailoringChange] {
        let session = TailoringSession.decode(application.tailoringPlanData)
        let alreadyApplied = Set(session?.appliedChangeIDs ?? [])
        let appliedBefore = session?.appliedBefore ?? [:]
        func applied(_ id: String) -> Bool { alreadyApplied.contains(id) }

        var changes: [TailoringChange] = []

        // Applied changes are kept in the list rather than dropped for matching
        // the state they themselves produced — a row that disappears the moment
        // you click it reads as work lost, and takes its "Applied" mark with it.
        // `appliedBefore` is what makes the diff still show what it replaced.
        let summaryID = idPrefix + "summary"
        // A present-but-empty summary is "remove it", not "nothing to say" — a
        // tailoring reply that decides the résumé is stronger without a summary
        // has no other way to express that, and an absent field means "leave
        // unchanged".
        if let proposed = plan.summary, proposed.trimmed.isEmpty,
           applied(summaryID) || !application.summaryText.trimmed.isEmpty {
            let previous = appliedBefore[summaryID] ?? application.summaryText
            changes.append(TailoringChange(
                id: summaryID,
                title: "Remove the professional summary",
                detail: "The plan gives the space to experience instead. The Summary section is left out of the résumé entirely.",
                before: previous.trimmed.isEmpty ? nil : previous,
                after: nil,
                blockedReason: nil,
                action: .summary(""),
                applied: applied(summaryID),
                source: source
            ))
        } else if let summary = plan.summary?.trimmed, !summary.isEmpty,
           applied(summaryID) || summary != application.summaryText.trimmed {
            var detail = "Replace the summary with the tailored version."
            if let omitted = plan.deliberatelyOmitted?.trimmed, !omitted.isEmpty {
                detail += " Deliberately omitted: \(omitted)"
            }
            let previous = appliedBefore[summaryID] ?? application.summaryText
            changes.append(TailoringChange(
                id: summaryID,
                title: "Update professional summary",
                detail: detail,
                before: previous.trimmed.isEmpty ? nil : previous,
                after: summary,
                blockedReason: nil,
                action: .summary(summary),
                applied: applied(summaryID),
                rationale: plan.summaryRationale ?? [],
                    source: source
                ))
        }

        let skillsID = idPrefix + "skills"
        if let skills = plan.skillsLatex?.trimmed, !skills.isEmpty,
           applied(skillsID) || skills != application.skillsBlockText.trimmed {
            let previous = appliedBefore[skillsID] ?? application.skillsBlockText
            changes.append(TailoringChange(
                id: skillsID,
                title: "Update skills block",
                detail: "Replace the LaTeX skills block with the tailored version.",
                before: previous.trimmed.isEmpty ? nil : previous,
                after: skills,
                blockedReason: nil,
                action: .skills(skills),
                applied: applied(skillsID),
                    source: source
                ))
        }

        if let rawOrder = plan.sectionOrder {
            let orderID = idPrefix + "sectionOrder"
            let order = rawOrder.compactMap { ResumeSectionKind(rawValue: $0) }
            if !order.isEmpty, applied(orderID) || order != application.sectionOrder {
                changes.append(TailoringChange(
                    id: orderID,
                    title: "Reorder résumé sections",
                    detail: order.map(\.rawValue).joined(separator: " → "),
                    before: appliedBefore[orderID]
                        ?? application.sectionOrder.map(\.rawValue).joined(separator: " → "),
                    after: order.map(\.rawValue).joined(separator: " → "),
                    blockedReason: nil,
                    action: .sectionOrder(order),
                    applied: applied(orderID),
                    source: source
                ))
            }
        }

        if plan.orderedExperienceIDs != nil || plan.orderedProjectIDs != nil {
            let workIDs = Set(experiences.filter { isWorkLikeSelection($0) }.map(\.id))
            let projectIDs = Set(experiences.filter { isProjectLikeSelection($0) }.map(\.id))
            // Employment ids are legal here: they position a job's role line.
            let employmentIDs = Set(employments.map(\.id))
            let work = plan.orderedExperienceIDs.map {
                $0.filter { workIDs.contains($0) || employmentIDs.contains($0) }
            }
            let projects = plan.orderedProjectIDs.map { $0.filter(projectIDs.contains) }

            var parts: [String] = []
            if let work {
                let bullets = work.filter { !employmentIDs.contains($0) }.count
                parts.append("\(bullets) experience bullet\(bullets == 1 ? "" : "s")")
            }
            if let projects { parts.append("\(projects.count) project\(projects.count == 1 ? "" : "s")") }
            let selectedSummary = parts.joined(separator: " and ")

            var detail = "Select \(selectedSummary) in the suggested order; drop the rest."
            if let dropped = dropSummary(plan.drops) { detail += "\n\(dropped)" }

            changes.append(TailoringChange(
                id: idPrefix + "selection",
                title: "Apply bullet selection & order",
                detail: detail,
                before: nil,
                after: nil,
                blockedReason: nil,
                action: .selection(work: work, projects: projects),
                applied: applied(idPrefix + "selection"),
                    source: source
                ))
        } else {
            // A plan can name drops without restating the whole selection — the
            // PDF check does exactly that. Without this the drop was shown as
            // prose and could never be applied.
            let onResume = application.selectedExperienceIDs.union(application.selectedProjectIDs)
            for drop in plan.drops ?? [] {
                let id = idPrefix + "drop:\(drop.experienceID.uuidString)"
                guard let bullet = experiences.first(where: { $0.id == drop.experienceID }),
                      applied(id) || onResume.contains(drop.experienceID) else { continue }
                changes.append(TailoringChange(
                    id: id,
                    title: "Drop: \(bullet.displayTitle)",
                    detail: drop.reason ?? "Take this bullet off the résumé.",
                    before: bullet.bulletText(variantID: application.selectedVariantID(for: bullet.id)),
                    after: nil,
                    blockedReason: nil,
                    action: .drop(experienceID: drop.experienceID),
                    applied: applied(id),
                    source: source
                ))
            }
        }

        for replacement in plan.replacements ?? [] {
            let id = idPrefix + "replacement:\(replacement.experienceID.uuidString)"
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
                    applied: false,
                    source: source
                ))
                continue
            }
            // "Current" reflects the wording this application actually renders —
            // the selected variant, not the shared base text. Once applied, that
            // *is* the rewrite, so show what it replaced instead.
            let liveText = bullet.bulletText(variantID: application.selectedVariantID(for: bullet.id))
            let currentText = applied(id) ? (appliedBefore[id] ?? liveText) : liveText

            // A rewrite that changes nothing is not a rewrite. Models return the
            // original wording more often than you would think.
            guard applied(id) || replacement.text.trimmed != liveText.trimmed else { continue }

            // A check on the rendered file can only speak about what was in it.
            // The prompt says so; this is what makes it true.
            if case .pdfCheck = source {
                let onResume = application.selectedExperienceIDs.union(application.selectedProjectIDs)
                guard applied(id) || onResume.contains(bullet.id) else { continue }
            }

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
                applied: applied(id),
                signal: replacement.signal?.trimmed.isEmpty == false ? replacement.signal : nil,
                confirmationNeeded: replacement.confirmationNeeded?.trimmed.isEmpty == false
                    ? replacement.confirmationNeeded : nil,
                // The prompts forbid trading an opening result for an opening
                // activity, twice, and it happens anyway. Say so on the row.
                caution: BulletOpening.downgradeWarning(current: currentText, proposed: replacement.text),
                    source: source
                ))
        }

        for role in plan.roleDescriptions ?? [] {
            let id = idPrefix + "role:\(role.employmentID.uuidString)"
            guard let employment = employments.first(where: { $0.id == role.employmentID }) else {
                changes.append(TailoringChange(
                    id: id,
                    title: "Role description",
                    detail: "The referenced employment no longer exists.",
                    before: nil,
                    after: nil,
                    blockedReason: "Employment id not found — it may have changed since you copied the context.",
                    action: .roleDescription(employmentID: role.employmentID, include: role.include, text: role.text),
                    applied: false,
                    source: source
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
            // Once applied, the requested state *is* the current state, so both
            // flags go false — keep the row anyway rather than have it vanish
            // under the click that applied it.
            guard applied(id) || textChanges || inclusionChanges else { continue }

            let wantsText = newText?.isEmpty == false
            var detailParts: [String] = []
            if let include = role.include, applied(id) || inclusionChanges {
                detailParts.append(include ? "Show the role-description line" : "Hide the role-description line")
            }
            if wantsText, applied(id) || textChanges { detailParts.append("Update the role-description wording") }
            if detailParts.isEmpty { detailParts.append("Keep the role-description line as it is") }

            let afterText = wantsText ? newText!
                : (role.include == true ? "(show role description)" : "(hide role description)")
            let previous = appliedBefore[id]
                ?? (currentText.isEmpty ? (currentlyHidden ? "(hidden)" : "")
                    : "\(currentlyHidden ? "(hidden) " : "")\(currentText)")

            changes.append(TailoringChange(
                id: id,
                title: "Role description: \(employment.companyName)",
                detail: detailParts.joined(separator: "; ") + ".",
                before: previous.isEmpty ? nil : previous,
                after: afterText,
                blockedReason: nil,
                action: .roleDescription(employmentID: employment.id, include: role.include, text: newText),
                applied: applied(id),
                    source: source
                ))
        }

        for (index, bullet) in (plan.newBullets ?? []).enumerated() {
            let text = bullet.text.trimmed
            guard !text.isEmpty else { continue }
            let id = idPrefix + "newBullet:\(index)"
            let employment = bullet.employmentID.flatMap { id in employments.first { $0.id == id } }
            changes.append(TailoringChange(
                id: id,
                title: employment.map { "Add bullet: \($0.displayTitle)" } ?? "Add bullet",
                detail: bullet.reason ?? "A fact you confirmed that stands on its own.",
                before: nil,
                after: text,
                blockedReason: nil,
                action: .newBullet(bullet, toBank: true),
                applied: applied(id),
                confirmationNeeded: bullet.confirmationNeeded?.trimmed.isEmpty == false
                    ? bullet.confirmationNeeded : nil,
                    source: source
                ))
        }

        if let verdict = verdictChange(from: plan, idPrefix: idPrefix, source: source) { changes.append(verdict) }

        return changes
    }

    /// The plan's drop list, resolved to bullet titles. Nil when it has none.
    private func dropSummary(_ drops: [TailoringPlan.Drop]?) -> String? {
        guard let drops, !drops.isEmpty else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: experiences.map { ($0.id, $0) })
        let lines = drops.map { drop -> String in
            let title = byID[drop.experienceID]?.displayTitle ?? "Unknown bullet"
            return "• \(title)\(drop.reason.map { " — \($0)" } ?? "")"
        }
        return "Dropped:\n" + lines.joined(separator: "\n")
    }

    /// The readiness verdict and open questions as a final, non-applyable row.
    private func verdictChange(from plan: TailoringPlan, idPrefix: String,
                               source: TailoringChange.Source) -> TailoringChange? {
        let readiness = plan.readiness?.trimmed ?? ""
        let uncertainties = (plan.uncertainties ?? []).map(\.trimmed).filter { !$0.isEmpty }
        guard !readiness.isEmpty || !uncertainties.isEmpty else { return nil }
        let detail = uncertainties.isEmpty
            ? "Nothing left to confirm."
            : "Still to confirm:\n" + uncertainties.map { "• \($0)" }.joined(separator: "\n")
        return TailoringChange(
            id: idPrefix + "verdict",
            title: readiness.isEmpty ? "Before you submit" : readiness,
            detail: detail,
            before: nil,
            after: nil,
            blockedReason: nil,
            action: .verdict,
            applied: false,
        source: source
    )
    }

    // MARK: - Apply

    func applyTailoringChange(_ change: TailoringChange) {
        guard !change.isBlocked, !change.applied, !change.isInformational else { return }
        // Snapshot first: everything below rewrites application state in place,
        // and this is what `revertTailoringChange` puts back.
        var revert = TailoringRevertPoint(application)
        switch change.action {
        case .verdict:
            return
        case .summary(let text):
            application.summaryText = text
        case .skills(let text):
            application.skillsBlockText = text
        case .sectionOrder(let order):
            application.setSectionOrder(order)
        case .selection(let work, let projects):
            applySelection(work: work, projects: projects)
        case .replacement(let replacement):
            // Only a variant this change minted is deleted on revert; one it
            // reused was there before and stays.
            if let variant = applyReplacement(replacement), variant.created {
                revert.createdVariantID = variant.id
                revert.createdVariantOwnerID = replacement.experienceID
            }
        case .roleDescription(let employmentID, let include, let text):
            if let text, !text.trimmed.isEmpty {
                application.setRoleDescription(text, for: employmentID)
            }
            if let include {
                application.setRoleDescriptionHidden(!include, for: employmentID)
            }
        case .newBullet(let bullet, let toBank):
            revert.createdExperienceID = applyNewBullet(bullet, toBank: toBank)
        case .drop(let experienceID):
            application.setExperience(experienceID, selected: false)
            application.setProject(experienceID, selected: false)
            application.setExperienceOrder(application.experienceOrder.filter { $0 != experienceID })
        }
        markApplied(change.id, revert: revert)
        persistApplicationChanges()
    }

    /// False for changes applied before revert existed — their session has no
    /// snapshot, so there is nothing to put back.
    func canRevertTailoringChange(_ change: TailoringChange) -> Bool {
        change.applied && revertPoints[change.id] != nil
    }

    /// Puts back exactly what the change replaced, including deleting a bullet
    /// or variant it created, and clears its applied marker so it can be
    /// applied again.
    func revertTailoringChange(_ change: TailoringChange) {
        guard change.applied,
              let session = TailoringSession.decode(storedApplication?.tailoringPlanData ?? ""),
              let revert = session.revertPoints[change.id] else { return }

        revert.restore(into: &application)

        // A variant the rewrite minted is removed, not just deselected — leaving
        // it behind would litter the bullet's wording list with dead entries.
        if let variantID = revert.createdVariantID, let ownerID = revert.createdVariantOwnerID,
           let index = store.experiences.firstIndex(where: { $0.id == ownerID }) {
            var bullet = store.experiences[index]
            bullet.variations.removeAll { $0.id == variantID }
            store.experiences[index] = bullet
            persistExperienceChanges(bullet)
        }
        if let createdID = revert.createdExperienceID,
           let bullet = store.experiences.first(where: { $0.id == createdID }) {
            store.experiences.removeAll { $0.id == createdID }
            WorkspaceSyncService.deleteExperienceFile(bullet, remainingExperiences: store.experiences,
                                                      settings: settings)
        }

        appliedBeforeText[change.id] = nil
        if let index = tailoringChanges.firstIndex(where: { $0.id == change.id }) {
            tailoringChanges[index].applied = false
        }
        persistTailoringSession(dropping: change.id)
        persistApplicationChanges()
        tailoringChanges = allTailoringChanges()
    }

    func applyAllTailoring() {
        for change in tailoringChanges where !change.isBlocked && !change.applied && !change.isInformational {
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
        //
        // The order also carries employment ids, marking where each job's
        // role-description line sits among its bullets. A plan may place them
        // itself; when it doesn't, they are put back where they were rather than
        // dropped — losing them silently resets every role line to the top of
        // its job.
        let currentOrder = application.experienceOrder
        let employmentIDs = Set(employments.map(\.id))
        let selectedWork = application.selectedExperienceIDs
        let selectedProjects = application.selectedProjectIDs
        var workOrder = work ?? currentOrder.filter {
            selectedWork.contains($0) || employmentIDs.contains($0)
        }
        if work != nil, !workOrder.contains(where: employmentIDs.contains) {
            workOrder = restoringRoleLines(in: workOrder, from: currentOrder, employmentIDs: employmentIDs)
        }
        let projectOrder = projects ?? currentOrder.filter { selectedProjects.contains($0) }
        application.setExperienceOrder(workOrder + projectOrder)
    }

    /// Puts each role-line marker back beside the bullet it used to precede.
    /// Absent from the order means "first in its job", so an id with nowhere to
    /// go is simply left out.
    private func restoringRoleLines(in order: [UUID], from previous: [UUID],
                                    employmentIDs: Set<UUID>) -> [UUID] {
        var result = order
        for (index, id) in previous.enumerated() where employmentIDs.contains(id) {
            let successor = previous[(index + 1)...].first { result.contains($0) }
            guard let successor, let position = result.firstIndex(of: successor) else { continue }
            result.insert(id, at: position)
        }
        return result
    }

    /// Creates a bullet the plan proposed, selects it for this résumé, and puts
    /// it last in its employment's order. `toBank == false` scopes it to this
    /// application (see `ExperienceScope`).
    @discardableResult
    private func applyNewBullet(_ bullet: TailoringPlan.NewBullet, toBank: Bool) -> UUID? {
        guard let settings else { return nil }
        let employment = bullet.employmentID.flatMap { id in employments.first { $0.id == id } }
        var created = ExperienceBullet(
            company: employment?.companyName ?? "",
            role: employment?.role ?? "",
            bulletText: bullet.text.trimmed,
            notes: bullet.reason ?? "",
            employmentID: employment?.id,
            owningApplicationID: toBank ? nil : application.id
        )
        created.updatedAt = Date()
        store.experiences.insert(created, at: 0)
        try? WorkspaceSyncService.persistExperience(created, allExperiences: store.experiences, settings: settings)

        application.setExperience(created.id, selected: true)
        application.setExperienceOrder(application.experienceOrder + [created.id])
        return created.id
    }

    /// Selects the rewrite as this bullet's wording. Re-applying the same plan
    /// reuses the variant it made the first time rather than minting a copy.
    @discardableResult
    private func applyReplacement(_ replacement: ResolvedReplacement) -> (id: UUID, created: Bool)? {
        guard let idx = store.experiences.firstIndex(where: { $0.id == replacement.experienceID }) else { return nil }
        var bullet = store.experiences[idx]
        let name = replacement.name.isEmpty ? ExperienceVariation.defaultName(existing: bullet.variations) : replacement.name
        let variant: ExperienceVariation
        let created: Bool
        if let existing = ExperienceVariation.matching(name: name, text: replacement.text,
                                                        in: bullet.variations(visibleTo: application.id)) {
            variant = existing
            created = false
        } else {
            variant = ExperienceVariation(name: name, bulletText: replacement.text, notes: replacement.reason)
            bullet.variations.append(variant)
            store.experiences[idx] = bullet
            persistExperienceChanges(bullet)
            created = true
        }

        if replacement.isProject {
            application.setProject(replacement.experienceID, selected: true)
        } else {
            application.setExperience(replacement.experienceID, selected: true)
        }
        application.setVariant(variant.id, for: replacement.experienceID)
        return (variant.id, created)
    }

    // MARK: - Session persistence

    private func markApplied(_ id: String, revert: TailoringRevertPoint) {
        if let idx = tailoringChanges.firstIndex(where: { $0.id == id }) {
            tailoringChanges[idx].applied = true
            // Captured before the bullet changes underneath us, so the diff
            // keeps showing what this rewrite actually replaced.
            if let before = tailoringChanges[idx].before, appliedBeforeText[id] == nil {
                appliedBeforeText[id] = before
            }
        }
        revertPoints[id] = revert
        persistTailoringSession()
    }

    /// The plan itself belongs to the stored record (a run may have written it
    /// while another application was on screen); only the paste box and the
    /// applied markers come from this editor.
    ///
    /// `dropping` forgets one change's revert point — used when that change has
    /// just been reverted, so the snapshot doesn't outlive what it describes.
    func persistTailoringSession(dropping revertedID: String? = nil) {
        if let revertedID { revertPoints[revertedID] = nil }
        let appliedIDs = tailoringChanges.filter(\.applied).map(\.id)
        let session = TailoringSession(pastedText: tailoringPastedText, plan: tailoringPlan,
                                       appliedChangeIDs: appliedIDs,
                                       appliedBefore: appliedBeforeText,
                                       revertPoints: revertPoints.filter { appliedIDs.contains($0.key) })
        application.tailoringPlanData = session.encoded()
        if let index = store.applications.firstIndex(where: { $0.id == application.id }) {
            store.applications[index].tailoringPlanData = application.tailoringPlanData
        }
    }

    /// Restore a persisted session (raw paste + plan + applied markers) when the
    /// sheet opens, so multi-round progress survives close / relaunch.
    func restoreTailoringSession() {
        guard let session = TailoringSession.decode(storedApplication?.tailoringPlanData ?? "") else { return }
        if tailoringPastedText.isEmpty { tailoringPastedText = session.pastedText }
        appliedBeforeText.merge(session.appliedBefore) { current, _ in current }
        revertPoints.merge(session.revertPoints) { current, _ in current }
        if tailoringChanges.isEmpty {
            tailoringChanges = allTailoringChanges()
        }
    }

    func clearTailoringSession() {
        tailoringPastedText = ""
        tailoringImportIssues = []
        tailoringChanges = []
        application.tailoringPlanData = ""
        if let index = store.applications.firstIndex(where: { $0.id == application.id }) {
            store.applications[index].tailoringPlanData = ""
        }
        persistApplicationChanges()
    }
}
