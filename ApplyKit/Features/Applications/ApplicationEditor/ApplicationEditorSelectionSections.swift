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
            if aiBackendPath != nil {
                HStack {
                    Button {
                        Task { await suggestExperiences() }
                    } label: {
                        Label(isSuggestingExperiences ? "Thinking…" : "Suggest Experiences", systemImage: "sparkles")
                    }
                    .disabled(activityMonitor.state == .running || application.jobDescription.trimmed.isEmpty)
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
            collapseKey: "applicationEditor.collapsed.tailorExperience"
        )
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
