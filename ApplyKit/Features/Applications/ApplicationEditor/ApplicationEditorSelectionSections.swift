//
//  ApplicationEditorSelectionSections.swift
//  ApplyKit
//

import AppKit
import SwiftUI

extension ApplicationEditorView {
    var selectedExperienceSection: some View {
        DetailPanel("Experience Source") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Work and education bullets used in the resume Experience section and Codex prompts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

                if experiences.isEmpty {
                    Text("No experience items yet.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(selectionGroups, id: \.title) { group in
                            SelectionGroupView(title: group.title) {
                                ForEach(group.bullets) { experience in
                                    SelectionToggleRow(
                                        title: experience.displayTitle,
                                        detail: [experience.skillsText].filter { !$0.trimmed.isEmpty }.joined(separator: " - "),
                                        isOn: Binding(
                                            get: { application.selectedExperienceIDs.contains(experience.id) },
                                            set: { application.setExperience(experience.id, selected: $0) }
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var selectedProjectSection: some View {
        DetailPanel("Selected Projects") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Projects render separately from work experience in the Selected Projects section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if projectSelectionGroups.isEmpty {
                    Text("No personal, project, or open-source items yet. Add personal projects in Experience Bank.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(projectSelectionGroups, id: \.title) { group in
                            SelectionGroupView(title: group.title) {
                                ForEach(group.bullets) { project in
                                    SelectionToggleRow(
                                        title: project.displayTitle,
                                        detail: [project.company, project.skillsText].filter { !$0.trimmed.isEmpty }.joined(separator: " - "),
                                        isOn: Binding(
                                            get: { application.selectedProjectIDs.contains(project.id) },
                                            set: { application.setProject(project.id, selected: $0) }
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var selectedBulletWordingSection: some View {
        DetailPanel("Selected Bullet Wording") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose base wording or a named variant for each selected experience.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let selectedItems = selectedExperiencesForWording
                if selectedItems.isEmpty {
                    Text("Select an experience or project above to tune its wording for this application.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(selectedItems) { experience in
                            ApplicationExperienceWordingRow(
                                application: $application,
                                experience: experienceBinding(for: experience.id),
                                applications: applications,
                                settings: settings,
                                onPersistExperience: persistExperienceChanges,
                                onPersistApplication: persistApplicationChanges
                            )
                        }
                    }
                }
            }
        }
    }

    var roleDescriptionsSection: some View {
        DetailPanel("Role Descriptions") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Override the one-line role description per job for this application. Leave blank to use the default from the Experience Bank.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let jobs = selectedEmploymentsForRoleDescription
                if jobs.isEmpty {
                    Text("Select work experiences above to tune their role descriptions for this application.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(jobs) { employment in
                            ApplicationRoleDescriptionRow(
                                application: $application,
                                employment: employment
                            )
                        }
                    }
                }
            }
        }
    }

    /// Distinct employments referenced by the application's selected work-like bullets,
    /// sorted by display order — exactly the jobs that render a resume subsection.
    var selectedEmploymentsForRoleDescription: [Employment] {
        let selectedIDs = application.selectedExperienceIDs
        let employmentsByID: [UUID: Employment] = Dictionary(
            uniqueKeysWithValues: employments.map { ($0.id, $0) }
        )
        var seen = Set<UUID>()
        var result: [Employment] = []
        for experience in experiences where selectedIDs.contains(experience.id) && isWorkLikeSelection(experience) {
            guard let id = experience.employmentID, let employment = employmentsByID[id],
                  !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(employment)
        }
        return result.sorted { lhs, rhs in
            lhs.displayOrder != rhs.displayOrder
                ? lhs.displayOrder < rhs.displayOrder
                : lhs.companyName.lowercased() < rhs.companyName.lowercased()
        }
    }

    struct ExperienceSelectionGroup {
        let title: String
        let bullets: [ExperienceBullet]
        let order: Int
    }

    var selectionGroups: [ExperienceSelectionGroup] {
        let employmentsByID: [UUID: Employment] = Dictionary(
            uniqueKeysWithValues: employments.map { ($0.id, $0) }
        )
        var buckets: [String: (order: Int, bullets: [ExperienceBullet])] = [:]
        let unassignedKey = "Unassigned"
        for experience in experiences {
            guard isWorkLikeSelection(experience) else { continue }
            if let id = experience.employmentID, let employment = employmentsByID[id] {
                let title = employment.summaryLine.isEmpty ? "Untitled Employment" : employment.summaryLine
                buckets[title, default: (employment.displayOrder, [])].bullets.append(experience)
            } else {
                buckets[unassignedKey, default: (Int.max, [])].bullets.append(experience)
            }
        }
        return buckets
            .map { key, value in
                ExperienceSelectionGroup(
                    title: key,
                    bullets: value.bullets.sorted { $0.createdAt < $1.createdAt },
                    order: value.order
                )
            }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.title.lowercased() < rhs.title.lowercased()
            }
    }

    var projectSelectionGroups: [ExperienceSelectionGroup] {
        let employmentsByID: [UUID: Employment] = Dictionary(
            uniqueKeysWithValues: employments.map { ($0.id, $0) }
        )
        var buckets: [String: (order: Int, bullets: [ExperienceBullet])] = [:]
        for experience in experiences {
            guard isProjectLikeSelection(experience) else { continue }
            if experience.isPersonalProject {
                buckets["Personal Projects", default: (Int.max - 1, [])].bullets.append(experience)
            } else if let id = experience.employmentID, let employment = employmentsByID[id] {
                let title = employment.displayTitle
                buckets[title, default: (employment.displayOrder, [])].bullets.append(experience)
            } else {
                let title = experience.sourceTitle.trimmed.isEmpty ? "Projects" : experience.sourceTitle
                buckets[title, default: (Int.max, [])].bullets.append(experience)
            }
        }
        return buckets
            .map { key, value in
                ExperienceSelectionGroup(
                    title: key,
                    bullets: value.bullets.sorted { $0.createdAt < $1.createdAt },
                    order: value.order
                )
            }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.title.lowercased() < rhs.title.lowercased()
            }
    }

    var selectedExperiencesForWording: [ExperienceBullet] {
        let selectedIDs = application.selectedExperienceIDs.union(application.selectedProjectIDs)
        let employmentOrderByID: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: employments.map { ($0.id, $0.displayOrder) }
        )

        return experiences
            .filter { selectedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsProject = isProjectLikeSelection(lhs)
                let rhsProject = isProjectLikeSelection(rhs)
                if lhsProject != rhsProject { return !lhsProject }

                let lhsOrder = lhs.employmentID.flatMap { employmentOrderByID[$0] } ?? Int.max
                let rhsOrder = rhs.employmentID.flatMap { employmentOrderByID[$0] } ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func isProjectLikeSelection(_ experience: ExperienceBullet) -> Bool {
        if experience.isProjectLike { return true }
        guard let employmentID = experience.employmentID,
              let employment = employments.first(where: { $0.id == employmentID }) else {
            return false
        }
        return employment.experienceCategory == .project || employment.experienceCategory == .openSource
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
