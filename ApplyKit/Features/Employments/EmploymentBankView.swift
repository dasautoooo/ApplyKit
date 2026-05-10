//
//  EmploymentBankView.swift
//  ApplyKit
//

import AppKit
import SwiftUI

struct EmploymentBankView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var selectedID: UUID?
    @State private var employmentPendingDeletion: Employment?
    @State private var shouldDeleteEmploymentSourceFile = false
    @State private var sidebarWidth: CGFloat = 360

    var body: some View {
        StableSidebarSplit(
            sidebarWidth: $sidebarWidth,
            minWidth: 320,
            maxWidth: 440
        ) {
            List(selection: $selectedID) {
                ForEach(store.employments) { employment in
                    EmploymentSummaryRow(
                        employment: employment,
                        attachedBulletCount: bulletCount(for: employment)
                    )
                    .tag(employment.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            requestDelete(employment)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
        } detail: {
            if let selectedEmployment {
                EmploymentEditorView(
                    employment: selectedEmployment,
                    settings: settings
                )
                .id(selectedID)
            } else {
                ContentUnavailableView("Select an employment", systemImage: "building.2")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: add) {
                    Label("New Employment", systemImage: "plus")
                }
            }

            ToolbarItem {
                Button(role: .destructive, action: requestDeleteSelected) {
                    Label("Delete Employment", systemImage: "trash")
                }
                .disabled(selectedEmployment == nil)
            }
        }
        .sheet(item: $employmentPendingDeletion) { employment in
            DeleteEmploymentDialog(
                employment: employment,
                attachedBulletCount: bulletCount(for: employment),
                shouldDeleteSourceFile: $shouldDeleteEmploymentSourceFile,
                onCancel: { employmentPendingDeletion = nil },
                onDelete: { delete(employment, deletingSourceFile: shouldDeleteEmploymentSourceFile) }
            )
        }
    }

    private var selectedEmployment: Employment? {
        guard let selectedID else { return nil }
        return store.employments.first { $0.id == selectedID }
    }

    private func bulletCount(for employment: Employment) -> Int {
        store.experiences.filter { $0.employmentID == employment.id }.count
    }

    private func add() {
        let employment = Employment(
            companyName: "New Company",
            displayOrder: (store.employments.map(\.displayOrder).max() ?? -1) + 1
        )
        store.employments.append(employment)
        try? WorkspaceSyncService.persistEmployment(employment, allEmployments: store.employments, settings: settings)
        selectedID = employment.id
    }

    private func requestDeleteSelected() {
        guard let selectedEmployment else { return }
        requestDelete(selectedEmployment)
    }

    private func requestDelete(_ employment: Employment) {
        shouldDeleteEmploymentSourceFile = false
        employmentPendingDeletion = employment
    }

    private func delete(_ employment: Employment, deletingSourceFile: Bool) {
        for i in 0..<store.experiences.count where store.experiences[i].employmentID == employment.id {
            store.experiences[i].employmentID = nil
            store.experiences[i].updatedAt = Date()
            try? WorkspaceSyncService.persistExperience(store.experiences[i], allExperiences: store.experiences, settings: settings)
        }

        if deletingSourceFile {
            WorkspaceSyncService.deleteEmploymentFile(
                employment,
                remainingEmployments: store.employments.filter { $0.id != employment.id },
                settings: settings
            )
        }
        store.employments.removeAll { $0.id == employment.id }

        if selectedID == employment.id {
            selectedID = nil
        }
        employmentPendingDeletion = nil
    }
}
