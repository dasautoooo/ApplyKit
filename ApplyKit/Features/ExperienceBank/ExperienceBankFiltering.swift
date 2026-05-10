//
//  ExperienceBankFiltering.swift
//  ApplyKit
//

import SwiftUI

extension ExperienceBankView {
    var filterPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search bullets, skills, company, project", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ExperienceSourceFilter.allCases) { filter in
                        ChipButton(
                            title: filter.rawValue,
                            isSelected: sourceFilter == filter.rawValue
                        ) {
                            sourceFilter = filter.rawValue
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            HStack(spacing: 8) {
                ExperienceFilterMenu(
                    title: "Company",
                    value: companyFilter,
                    systemImage: "building.2",
                    selection: $companyFilter,
                    options: ["All Companies"] + companyOptions
                )

                ExperienceFilterMenu(
                    title: "Type",
                    value: typeFilter,
                    systemImage: "square.stack.3d.up",
                    selection: $typeFilter,
                    options: ["All Types"] + typeOptions
                )
            }

            HStack(spacing: 8) {
                ExperienceFilterMenu(
                    title: "Impact",
                    value: impactFilter,
                    systemImage: "chart.bar",
                    selection: $impactFilter,
                    options: ["All Impacts"] + ImpactLevel.allCases.map(\.rawValue)
                )

                ExperienceFilterMenu(
                    title: "Use",
                    value: usageFilter,
                    systemImage: "checklist",
                    selection: $usageFilter,
                    options: ExperienceUsageFilter.allCases.map(\.rawValue)
                )
            }

            HStack {
                Text("\(filteredExperiences.count) of \(store.experiences.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    resetFilters()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .disabled(!hasActiveFilters)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    var filteredExperiences: [ExperienceBullet] {
        let query = searchText.trimmed.lowercased()
        return store.experiences.filter {
            matchesSearch($0, query: query)
                && matchesCompany($0)
                && matchesType($0)
                && matchesImpact($0)
                && matchesUsage($0)
                && matchesSourceFilter($0)
        }
    }

    var groupedExperiences: [ExperienceGroup] {
        let employmentsByID: [UUID: Employment] = Dictionary(
            uniqueKeysWithValues: store.employments.map { ($0.id, $0) }
        )
        let grouped = Dictionary(grouping: filteredExperiences) { experience -> String in
            if experience.isPersonalProject {
                return "Personal Projects"
            }
            if let id = experience.employmentID, let employment = employmentsByID[id] {
                let parts = [employment.companyName, employment.role].filter { !$0.trimmed.isEmpty }
                return parts.isEmpty ? "Untitled Employment" : parts.joined(separator: " - ")
            }
            return experience.sourceTitle.trimmed.isEmpty ? "Unassigned Source" : experience.sourceTitle
        }

        return grouped.keys.sorted().map { title in
            ExperienceGroup(
                title: title,
                items: (grouped[title] ?? []).sorted {
                    if $0.displayTitle == $1.displayTitle {
                        return $0.role < $1.role
                    }
                    return $0.displayTitle < $1.displayTitle
                }
            )
        }
    }

    var companyOptions: [String] {
        Array(Set(store.experiences.map(\.sourceTitle))).sorted()
    }

    var typeOptions: [String] {
        Array(Set(store.experiences.map { $0.experienceType.trimmed }.filter { !$0.isEmpty })).sorted()
    }

    var hasActiveFilters: Bool {
        !searchText.trimmed.isEmpty
            || companyFilter != "All Companies"
            || typeFilter != "All Types"
            || impactFilter != "All Impacts"
            || usageFilter != ExperienceUsageFilter.any.rawValue
            || sourceFilter != ExperienceSourceFilter.all.rawValue
    }

    func resetFilters() {
        searchText = ""
        companyFilter = "All Companies"
        typeFilter = "All Types"
        impactFilter = "All Impacts"
        usageFilter = ExperienceUsageFilter.any.rawValue
        sourceFilter = ExperienceSourceFilter.all.rawValue
    }

    func matchesSearch(_ experience: ExperienceBullet, query: String) -> Bool {
        guard !query.isEmpty else { return true }

        return [
            experience.displayTitle,
            experience.company,
            experience.role,
            experience.projectName,
            experience.bulletText,
            experience.variations.map(\.bulletText).joined(separator: " "),
            experience.skillsText
        ].contains { $0.lowercased().contains(query) }
    }

    func matchesCompany(_ experience: ExperienceBullet) -> Bool {
        companyFilter == "All Companies" || experience.sourceTitle == companyFilter
    }

    func matchesType(_ experience: ExperienceBullet) -> Bool {
        typeFilter == "All Types" || experience.experienceType == typeFilter
    }

    func matchesImpact(_ experience: ExperienceBullet) -> Bool {
        impactFilter == "All Impacts" || experience.impactLevelRaw == impactFilter
    }

    func matchesUsage(_ experience: ExperienceBullet) -> Bool {
        switch ExperienceUsageFilter(rawValue: usageFilter) ?? .any {
        case .any:
            return true
        case .resume:
            return experience.usableInResume
        case .coverLetter:
            return experience.usableInCoverLetter
        case .both:
            return experience.usableInResume && experience.usableInCoverLetter
        }
    }

    func matchesSourceFilter(_ experience: ExperienceBullet) -> Bool {
        switch ExperienceSourceFilter(rawValue: sourceFilter) ?? .all {
        case .all:
            return true
        case .companyExperience:
            return !experience.isPersonalProject
        case .personalProjects:
            return experience.isPersonalProject
        }
    }
}
