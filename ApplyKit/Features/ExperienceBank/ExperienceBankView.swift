//
//  ExperienceBankView.swift
//  ApplyKit
//

import AppKit
import SwiftUI

struct ExperienceBankView: View {
    @Environment(AppDataStore.self) var store
    @Environment(AppSettings.self) var settings

    @State private var selectedID: UUID?
    @State var searchText = ""
    @State var companyFilter = "All Companies"
    @State var typeFilter = "All Types"
    @State var impactFilter = "All Impacts"
    @State var usageFilter = ExperienceUsageFilter.any.rawValue
    @State var sourceFilter = ExperienceSourceFilter.all.rawValue
    @State private var experiencePendingDeletion: ExperienceBullet?
    @State private var shouldDeleteExperienceSourceFile = false
    @State private var sidebarWidth: CGFloat = 460

    var body: some View {
        StableSidebarSplit(
            sidebarWidth: $sidebarWidth,
            minWidth: 390,
            maxWidth: 540
        ) {
            VStack(spacing: 0) {
                filterPanel

                List(selection: $selectedID) {
                    ForEach(groupedExperiences) { group in
                        Section(group.title) {
                            ForEach(group.items) { experience in
                                ExperienceSummaryRow(experience: experience)
                                    .tag(experience.id)
                                    .contextMenu {
                                        Button {
                                            duplicate(experience)
                                        } label: {
                                            Label("Duplicate", systemImage: "doc.on.doc")
                                        }

                                        Button(role: .destructive) {
                                            requestDelete(experience)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        } detail: {
            if let selectedExperience {
                ExperienceEditorView(
                    experience: selectedExperience,
                    settings: settings
                )
                .id(selectedID)
            } else {
                ContentUnavailableView("Select an experience item", systemImage: "archivebox")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        addExperience()
                    } label: {
                        Label("Company Experience", systemImage: "building.2")
                    }

                    Button {
                        addPersonalProject()
                    } label: {
                        Label("Personal Project", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("New Experience", systemImage: "plus")
                }
            }

            ToolbarItem {
                Button(action: duplicateSelected) {
                    Label("Duplicate Experience", systemImage: "doc.on.doc")
                }
                .disabled(selectedExperience == nil)
            }

            ToolbarItem {
                Button(role: .destructive, action: requestDeleteSelected) {
                    Label("Delete Experience", systemImage: "trash")
                }
                .disabled(selectedExperience == nil)
            }
        }
        .sheet(item: $experiencePendingDeletion) { experience in
            DeleteExperienceDialog(
                experience: experience,
                shouldDeleteSourceFile: $shouldDeleteExperienceSourceFile,
                onCancel: { experiencePendingDeletion = nil },
                onDelete: { delete(experience, deletingSourceFile: shouldDeleteExperienceSourceFile) }
            )
        }
    }

    private var selectedExperience: ExperienceBullet? {
        guard let selectedID else { return nil }
        return store.experiences.first { $0.id == selectedID }
    }

    private func addExperience() {
        let experience = ExperienceBullet(projectName: "New Experience")
        insert(experience)
    }

    private func addPersonalProject() {
        let project = ExperienceBullet(
            experienceType: ExperienceCategory.project.rawValue,
            projectName: "New Personal Project",
            roleCategory: .generalSoftware,
            referenceURL: ""
        )
        insert(project)
    }

    private func insert(_ experience: ExperienceBullet) {
        store.experiences.insert(experience, at: 0)
        try? WorkspaceSyncService.persistExperience(experience, allExperiences: store.experiences, settings: settings)
        selectedID = experience.id
    }

    private func duplicateSelected() {
        guard let selectedExperience else { return }
        duplicate(selectedExperience)
    }

    private func duplicate(_ experience: ExperienceBullet) {
        let copy = ExperienceBullet(
            experienceType: experience.experienceType,
            company: experience.company,
            role: experience.role,
            projectName: "\(experience.displayTitle) Copy",
            bulletText: experience.bulletText,
            variations: experience.variations,
            skillsText: experience.skillsText,
            roleCategory: RoleCategory(rawValue: experience.roleCategoryRaw) ?? .generalSoftware,
            impactLevel: ImpactLevel(rawValue: experience.impactLevelRaw) ?? .medium,
            usableInResume: experience.usableInResume,
            usableInCoverLetter: experience.usableInCoverLetter,
            referenceURL: experience.referenceURL,
            employmentID: experience.employmentID
        )
        store.experiences.insert(copy, at: 0)
        try? WorkspaceSyncService.persistExperience(copy, allExperiences: store.experiences, settings: settings)
        selectedID = copy.id
    }

    private func requestDeleteSelected() {
        guard let selectedExperience else { return }
        requestDelete(selectedExperience)
    }

    private func requestDelete(_ experience: ExperienceBullet) {
        shouldDeleteExperienceSourceFile = false
        experiencePendingDeletion = experience
    }

    private func delete(_ experience: ExperienceBullet, deletingSourceFile: Bool) {
        if deletingSourceFile {
            WorkspaceSyncService.deleteExperienceFile(
                experience,
                remainingExperiences: store.experiences.filter { $0.id != experience.id },
                settings: settings
            )
        }
        store.experiences.removeAll { $0.id == experience.id }

        if selectedID == experience.id {
            selectedID = nil
        }
        experiencePendingDeletion = nil
    }
}
