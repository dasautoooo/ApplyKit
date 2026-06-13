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
        DetailPanel("Tailor Experience") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Each job groups its selected bullets below. Set the role description, choose base wording or a named variant per bullet, and reorder bullets within the job.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let groups = wordingGroups
                if groups.isEmpty {
                    Text("Select an experience or project above to tune its wording for this application.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            wordingGroupCard(group)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wordingGroupCard(_ group: WordingGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group header — names the employment (or project bucket) the bullets belong to.
            if let employment = group.employment {
                ApplicationRoleDescriptionRow(
                    application: $application,
                    employment: employment,
                    embedded: true
                )
            } else {
                HStack(spacing: 8) {
                    Image(systemName: group.isProject ? "folder.fill" : "tray.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(group.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                }
            }

            Divider()

            // Bullets, indented behind a left accent rule to show they belong to this job.
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(group.bullets.enumerated()), id: \.element.id) { index, experience in
                        ApplicationExperienceWordingRow(
                            application: $application,
                            experience: experienceBinding(for: experience.id),
                            applications: applications,
                            settings: settings,
                            onPersistExperience: persistExperienceChanges,
                            onPersistApplication: persistApplicationChanges,
                            canMoveUp: index > 0,
                            canMoveDown: index < group.bullets.count - 1,
                            onMoveUp: { moveExperience(experience.id, in: group, by: -1) },
                            onMoveDown: { moveExperience(experience.id, in: group, by: 1) }
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    struct WordingGroup: Identifiable {
        let id: String
        let title: String
        let employment: Employment?
        let bullets: [ExperienceBullet]
        let isProject: Bool
    }

    /// Selected bullets grouped for the wording section: work-like bullets grouped by employment
    /// (sorted by display order, plus a trailing "Unassigned" group), followed by project-like
    /// bullets bucketed like `projectSelectionGroups`. Each group's bullets are ordered via the
    /// per-application order (`JobApplication.orderedExperiences`).
    var wordingGroups: [WordingGroup] {
        let selectedIDs = application.selectedExperienceIDs.union(application.selectedProjectIDs)
        let employmentsByID: [UUID: Employment] = Dictionary(
            uniqueKeysWithValues: employments.map { ($0.id, $0) }
        )
        let selected = experiences.filter { selectedIDs.contains($0.id) }

        // Work-like bullets grouped by employment.
        var workBuckets: [UUID: [ExperienceBullet]] = [:]
        var unassignedWork: [ExperienceBullet] = []
        for experience in selected where isWorkLikeSelection(experience) {
            if let id = experience.employmentID, employmentsByID[id] != nil {
                workBuckets[id, default: []].append(experience)
            } else {
                unassignedWork.append(experience)
            }
        }
        var groups: [WordingGroup] = workBuckets.compactMap { id, bullets in
            guard let employment = employmentsByID[id] else { return nil }
            return WordingGroup(id: "emp-\(id.uuidString)",
                                title: employment.summaryLine,
                                employment: employment,
                                bullets: application.orderedExperiences(bullets),
                                isProject: false)
        }.sorted { lhs, rhs in
            let lo = lhs.employment?.displayOrder ?? Int.max
            let ro = rhs.employment?.displayOrder ?? Int.max
            return lo != ro ? lo < ro : lhs.title.lowercased() < rhs.title.lowercased()
        }
        if !unassignedWork.isEmpty {
            groups.append(WordingGroup(id: "work-unassigned", title: "Unassigned",
                                       employment: nil,
                                       bullets: application.orderedExperiences(unassignedWork),
                                       isProject: false))
        }

        // Project-like bullets, bucketed by title (mirrors projectSelectionGroups).
        var projectBuckets: [String: (order: Int, bullets: [ExperienceBullet])] = [:]
        for experience in selected where isProjectLikeSelection(experience) {
            let key: String
            let order: Int
            if experience.isPersonalProject {
                key = "Personal Projects"; order = Int.max - 1
            } else if let id = experience.employmentID, let employment = employmentsByID[id] {
                key = employment.displayTitle; order = employment.displayOrder
            } else {
                key = experience.sourceTitle.trimmed.isEmpty ? "Projects" : experience.sourceTitle; order = Int.max
            }
            projectBuckets[key, default: (order, [])].bullets.append(experience)
        }
        let projectGroups = projectBuckets
            .map { key, value in
                WordingGroup(id: "proj-\(key)", title: key, employment: nil,
                             bullets: application.orderedExperiences(value.bullets), isProject: true)
            }
            .sorted { lhs, rhs in
                let lo = projectBuckets[lhs.title]?.order ?? Int.max
                let ro = projectBuckets[rhs.title]?.order ?? Int.max
                return lo != ro ? lo < ro : lhs.title.lowercased() < rhs.title.lowercased()
            }
        groups.append(contentsOf: projectGroups)
        return groups
    }

    /// Reorder a bullet within its wording group by ±1, persisting the per-application order.
    func moveExperience(_ id: UUID, in group: WordingGroup, by delta: Int) {
        let groupIDs = group.bullets.map(\.id)
        guard let pos = groupIDs.firstIndex(of: id) else { return }
        let target = pos + delta
        guard target >= 0, target < groupIDs.count else { return }
        let neighbor = groupIDs[target]

        // Materialize the full display order across all groups (groups are contiguous, so the
        // in-group neighbor is also the adjacent element in this flattened list).
        var fullOrder = wordingGroups.flatMap { $0.bullets.map(\.id) }
        guard let i = fullOrder.firstIndex(of: id), let j = fullOrder.firstIndex(of: neighbor) else { return }
        fullOrder.swapAt(i, j)
        application.setExperienceOrder(fullOrder)
        persistApplicationChanges()
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
