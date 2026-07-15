//
//  ResumeContentGrouping.swift
//  ApplyKit
//

import Foundation

/// An orderable entry in a wording group: either the employment's role-description
/// line or a selected bullet. Both participate in the flat `experienceOrder` list
/// (role descriptions keyed by their employment's ID).
enum WordingItem: Identifiable {
    case roleDescription(Employment)
    case bullet(ExperienceBullet)

    var id: UUID {
        switch self {
        case .roleDescription(let employment): employment.id
        case .bullet(let bullet): bullet.id
        }
    }

    var bullet: ExperienceBullet? {
        if case .bullet(let bullet) = self { return bullet }
        return nil
    }
}

/// A group of selected items shown in the "Tailor Experience" section: one per
/// employment (plus "Unassigned"), followed by project buckets.
struct WordingGroup: Identifiable {
    let id: String
    let title: String
    let employment: Employment?
    let items: [WordingItem]
    let isProject: Bool

    var bullets: [ExperienceBullet] { items.compactMap(\.bullet) }
}

/// A bucket of selectable bullets in the experience/project selection sections.
struct ExperienceSelectionGroup {
    let title: String
    let bullets: [ExperienceBullet]
    let order: Int
}

/// Pure grouping/ordering helpers shared by the application editor and the
/// master resume editor. All functions are stateless over the passed content.
enum ResumeContentGrouping {
    /// Dictionary-keyed variant for hot loops — avoids an O(employments) `first(where:)` per call.
    static func isProjectLike(_ experience: ExperienceBullet, employmentsByID: [UUID: Employment]) -> Bool {
        if experience.isProjectLike { return true }
        guard let employmentID = experience.employmentID,
              let employment = employmentsByID[employmentID] else {
            return false
        }
        return employment.experienceCategory == .project || employment.experienceCategory == .openSource
    }

    static func isWorkLike(_ experience: ExperienceBullet, employmentsByID: [UUID: Employment]) -> Bool {
        !isProjectLike(experience, employmentsByID: employmentsByID)
    }

    static func employmentsByID(_ employments: [Employment]) -> [UUID: Employment] {
        Dictionary(uniqueKeysWithValues: employments.map { ($0.id, $0) })
    }

    static func selectionGroups(experiences: [ExperienceBullet], employments: [Employment]) -> [ExperienceSelectionGroup] {
        let employmentsByID = employmentsByID(employments)
        var buckets: [String: (order: Int, bullets: [ExperienceBullet])] = [:]
        let unassignedKey = "Unassigned"
        for experience in experiences {
            guard isWorkLike(experience, employmentsByID: employmentsByID) else { continue }
            if let id = experience.employmentID, let employment = employmentsByID[id] {
                let title = employment.summaryLine.isEmpty ? "Untitled Employment" : employment.summaryLine
                buckets[title, default: (employment.displayOrder, [])].bullets.append(experience)
            } else {
                buckets[unassignedKey, default: (Int.max, [])].bullets.append(experience)
            }
        }
        return sortedSelectionGroups(buckets)
    }

    static func projectSelectionGroups(experiences: [ExperienceBullet], employments: [Employment]) -> [ExperienceSelectionGroup] {
        let employmentsByID = employmentsByID(employments)
        var buckets: [String: (order: Int, bullets: [ExperienceBullet])] = [:]
        for experience in experiences {
            guard isProjectLike(experience, employmentsByID: employmentsByID) else { continue }
            if experience.isPersonalProject {
                buckets["Personal Projects", default: (Int.max - 1, [])].bullets.append(experience)
            } else if let id = experience.employmentID, let employment = employmentsByID[id] {
                buckets[employment.displayTitle, default: (employment.displayOrder, [])].bullets.append(experience)
            } else {
                let title = experience.sourceTitle.trimmed.isEmpty ? "Projects" : experience.sourceTitle
                buckets[title, default: (Int.max, [])].bullets.append(experience)
            }
        }
        return sortedSelectionGroups(buckets)
    }

    private static func sortedSelectionGroups(_ buckets: [String: (order: Int, bullets: [ExperienceBullet])]) -> [ExperienceSelectionGroup] {
        buckets
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

    /// Selected bullets grouped for the wording section: work-like bullets grouped by employment
    /// (sorted by display order, plus a trailing "Unassigned" group), followed by project-like
    /// bullets bucketed like `projectSelectionGroups`. Each group's bullets are ordered via the
    /// content's stored order (`ResumeContentModel.experienceOrder`).
    static func wordingGroups(content: some ResumeContentModel,
                              experiences: [ExperienceBullet],
                              employments: [Employment]) -> [WordingGroup] {
        let selectedIDs = content.selectedExperienceIDs.union(content.selectedProjectIDs)
        let employmentsByID = employmentsByID(employments)
        let selected = experiences.filter { selectedIDs.contains($0.id) }

        // Decode the stored bullet order once and reuse for every group, instead of
        // re-splitting `experienceOrderText` inside `orderedExperiences` for each group.
        let orderIndex = Dictionary(
            uniqueKeysWithValues: content.experienceOrder.enumerated().map { ($0.element, $0.offset) }
        )
        func ordered(_ bullets: [ExperienceBullet]) -> [ExperienceBullet] {
            bullets.sorted { lhs, rhs in
                let li = orderIndex[lhs.id] ?? Int.max
                let ri = orderIndex[rhs.id] ?? Int.max
                return li != ri ? li < ri : lhs.createdAt < rhs.createdAt
            }
        }
        // Employment groups carry a role-description item at its stored position among
        // the bullets (absent from the order = first, matching the renderer).
        func items(employment: Employment?, bullets: [ExperienceBullet]) -> [WordingItem] {
            let sorted = ordered(bullets)
            guard let employment else { return sorted.map { .bullet($0) } }
            let roleKey = orderIndex[employment.id] ?? -1
            var result: [WordingItem] = []
            var inserted = false
            for bullet in sorted {
                let bulletKey = orderIndex[bullet.id] ?? Int.max
                if !inserted && roleKey < bulletKey {
                    result.append(.roleDescription(employment))
                    inserted = true
                }
                result.append(.bullet(bullet))
            }
            if !inserted { result.append(.roleDescription(employment)) }
            return result
        }

        // Work-like bullets grouped by employment.
        var workBuckets: [UUID: [ExperienceBullet]] = [:]
        var unassignedWork: [ExperienceBullet] = []
        for experience in selected where isWorkLike(experience, employmentsByID: employmentsByID) {
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
                                items: items(employment: employment, bullets: bullets),
                                isProject: false)
        }.sorted { lhs, rhs in
            let lo = lhs.employment?.displayOrder ?? Int.max
            let ro = rhs.employment?.displayOrder ?? Int.max
            return lo != ro ? lo < ro : lhs.title.lowercased() < rhs.title.lowercased()
        }
        if !unassignedWork.isEmpty {
            groups.append(WordingGroup(id: "work-unassigned", title: "Unassigned",
                                       employment: nil,
                                       items: items(employment: nil, bullets: unassignedWork),
                                       isProject: false))
        }

        // Project-like bullets, bucketed by title (mirrors projectSelectionGroups).
        var projectBuckets: [String: (order: Int, bullets: [ExperienceBullet])] = [:]
        for experience in selected where isProjectLike(experience, employmentsByID: employmentsByID) {
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
                             items: items(employment: nil, bullets: value.bullets), isProject: true)
            }
            .sorted { lhs, rhs in
                let lo = projectBuckets[lhs.title]?.order ?? Int.max
                let ro = projectBuckets[rhs.title]?.order ?? Int.max
                return lo != ro ? lo < ro : lhs.title.lowercased() < rhs.title.lowercased()
            }
        groups.append(contentsOf: projectGroups)
        return groups
    }

    /// The full display order with `id` swapped ±1 within its wording group, or nil when the
    /// move falls outside the group. Items include role-description entries (keyed by
    /// employment ID). Groups are contiguous in the flattened list, so the in-group
    /// neighbor is also the adjacent element there.
    static func experienceOrderMoving(_ id: UUID, in group: WordingGroup, by delta: Int,
                                      groups: [WordingGroup]) -> [UUID]? {
        let groupIDs = group.items.map(\.id)
        guard let pos = groupIDs.firstIndex(of: id) else { return nil }
        let target = pos + delta
        guard target >= 0, target < groupIDs.count else { return nil }
        let neighbor = groupIDs[target]

        var fullOrder = groups.flatMap { $0.items.map(\.id) }
        guard let i = fullOrder.firstIndex(of: id), let j = fullOrder.firstIndex(of: neighbor) else { return nil }
        fullOrder.swapAt(i, j)
        return fullOrder
    }
}
