//
//  ApplicationEditorSelectionSections.swift
//  ApplyKit
//
//  Thin wrappers around the shared resume-content sections (see
//  Features/ResumeContent/), wiring in the application-specific AI hooks.
//

import AppKit
import SwiftUI

extension ApplicationEditorView {
    /// Per-application Summary (optional; omitted from the resume when blank).
    var summarySection: some View {
        ResumeSummarySection(content: $application, collapseKey: "applicationEditor.collapsed.summary")
    }

    /// Per-application Skills override (falls back to the global block when blank).
    var skillsSection: some View {
        ResumeSkillsSection(
            content: $application,
            globalSkillsBlock: store.profile.skillsBlock,
            collapseKey: "applicationEditor.collapsed.skills"
        )
    }

    /// Per-application resume section ordering.
    var sectionOrderSection: some View {
        ResumeSectionOrderSection(content: $application, collapseKey: "applicationEditor.collapsed.sectionOrder")
    }

    var selectedExperienceSection: some View {
        ResumeExperienceSelectionSection(
            content: $application,
            experiences: experiences,
            employments: employments,
            collapseKey: "applicationEditor.collapsed.experienceSource"
        ) {
            if aiBackend != nil {
                HStack {
                    Button {
                        Task { await suggestExperiences() }
                    } label: {
                        Label(isSuggestingExperiences ? "Thinking…" : "Suggest Experiences", systemImage: "sparkles")
                    }
                    .disabled(isSuggestingExperiences || application.jobDescription.trimmed.isEmpty)
                    .help("Ask AI to recommend which experiences best match the job description")
                    Spacer()
                }
            }
        }
    }

    var selectedProjectSection: some View {
        ResumeProjectSelectionSection(
            content: $application,
            experiences: experiences,
            employments: employments,
            collapseKey: "applicationEditor.collapsed.selectedProjects"
        )
    }

    var selectedBulletWordingSection: some View {
        ResumeWordingSection(
            content: $application,
            experiences: experiences,
            employments: employments,
            applications: applications,
            settings: settings,
            refinePrompt: { [application] experience in
                PromptBuilder.bulletRefinementPrompt(application: application, experience: experience)
            },
            experienceBinding: experienceBinding(for:),
            onPersistExperience: persistExperienceChanges,
            onPersistApplication: persistApplicationChanges,
            onPersistContent: persistApplicationChanges,
            scopeApplicationID: application.id,
            onPromoteToBank: promoteToBank,
            collapseKey: "applicationEditor.collapsed.tailorExperience"
        )
    }

    /// Clears the application scope from a bullet (and any wording it owns) so
    /// the rest of the app can reuse it.
    func promoteToBank(_ experience: ExperienceBullet) {
        guard let index = store.experiences.firstIndex(where: { $0.id == experience.id }) else { return }
        var promoted = store.experiences[index]
        promoted.owningApplicationID = nil
        promoted.variations = promoted.variations.map { variation in
            var shared = variation
            if shared.owningApplicationID == application.id { shared.owningApplicationID = nil }
            return shared
        }
        store.experiences[index] = promoted
        persistExperienceChanges(promoted)
        activityMonitor.succeed("\"\(promoted.displayTitle)\" moved to the experience bank.")
    }

    /// Selected bullets grouped for prompts and cover-letter context (see
    /// `ResumeContentGrouping.wordingGroups`).
    var wordingGroups: [WordingGroup] {
        ResumeContentGrouping.wordingGroups(content: application, experiences: experiences, employments: employments)
    }

    func isProjectLikeSelection(_ experience: ExperienceBullet) -> Bool {
        ResumeContentGrouping.isProjectLike(experience, employmentsByID: ResumeContentGrouping.employmentsByID(employments))
    }

    func isWorkLikeSelection(_ experience: ExperienceBullet) -> Bool {
        !isProjectLikeSelection(experience)
    }

    func experienceBinding(for id: UUID) -> Binding<ExperienceBullet> {
        Binding(
            get: { store.experiences.first { $0.id == id } ?? ExperienceBullet() },
            set: { updated in
                if let idx = store.experiences.firstIndex(where: { $0.id == updated.id }) {
                    store.experiences[idx] = updated
                }
            }
        )
    }
}
