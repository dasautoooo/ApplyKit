//
//  ApplicationsWorkspaceView.swift
//  ApplyKit
//

import AppKit
import SwiftUI

struct ApplicationsWorkspaceView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var selectedApplicationID: UUID?
    @State private var searchText = ""
    @State private var statusFilter = "All"
    @State private var priorityFilter = "All"
    @State private var scopeFilter = ApplicationListScope.active.rawValue
    @State private var applicationPendingDeletion: JobApplication?
    @State private var shouldDeleteApplicationSourceFiles = false
    @State private var sidebarWidth: CGFloat = 360

    var body: some View {
        StableSidebarSplit(
            sidebarWidth: $sidebarWidth,
            minWidth: 320,
            maxWidth: 440
        ) {
            VStack(spacing: 0) {
                filterBar

                List(selection: $selectedApplicationID) {
                    ForEach(filteredApplications) { application in
                        ApplicationRow(
                            application: application,
                            documents: store.documents.filter { $0.applicationID == application.id }
                        )
                        .tag(application.id)
                        .contextMenu {
                            if application.isArchived {
                                Button {
                                    restore(application)
                                } label: {
                                    Label("Restore Role", systemImage: "tray.and.arrow.up")
                                }
                            } else {
                                Button {
                                    archive(application)
                                } label: {
                                    Label("Archive Role", systemImage: "archivebox")
                                }
                            }

                            Divider()

                            Button(role: .destructive) {
                                requestDelete(application)
                            } label: {
                                Label("Delete Role", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: requestDeleteApplications)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        } detail: {
            if let selectedApplication {
                ApplicationEditorView(
                    application: selectedApplication,
                    settings: settings,
                    onArchive: { archive(selectedApplication) },
                    onRestore: { restore(selectedApplication) },
                    onDeleteRequest: { requestDelete(selectedApplication) }
                )
                .id(selectedApplication.id)
            } else {
                ContentUnavailableView("Select an application", systemImage: "briefcase")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: addApplication) {
                    Label("New Application", systemImage: "plus")
                }
            }
        }
        .sheet(item: $applicationPendingDeletion) { application in
            DeleteApplicationDialog(
                application: application,
                shouldDeleteSourceFiles: $shouldDeleteApplicationSourceFiles,
                onCancel: {
                    applicationPendingDeletion = nil
                },
                onDelete: {
                    delete(
                        application,
                        deletingSourceFiles: shouldDeleteApplicationSourceFiles
                    )
                }
            )
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search roles", text: $searchText)
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

            ApplicationScopeTabs(
                selection: $scopeFilter,
                counts: applicationScopeCounts
            )

            HStack(spacing: 8) {
                ApplicationFilterMenu(
                    title: "Status",
                    value: statusFilter,
                    systemImage: "circle.dashed",
                    selection: $statusFilter,
                    options: ["All"] + ApplicationStatus.allCases.map(\.rawValue)
                )

                ApplicationFilterMenu(
                    title: "Priority",
                    value: priorityFilter,
                    systemImage: "flag",
                    selection: $priorityFilter,
                    options: ["All"] + ApplicationPriority.allCases.map(\.rawValue)
                )
            }

            HStack {
                Text("\(filteredApplications.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if hasActiveApplicationFilters {
                    Button("Reset") {
                        resetApplicationFilters()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var hasActiveApplicationFilters: Bool {
        !searchText.trimmed.isEmpty
            || statusFilter != "All"
            || priorityFilter != "All"
            || scopeFilter != ApplicationListScope.active.rawValue
    }

    private func resetApplicationFilters() {
        searchText = ""
        statusFilter = "All"
        priorityFilter = "All"
        scopeFilter = ApplicationListScope.active.rawValue
    }

    private var filteredApplications: [JobApplication] {
        store.applications.filter { application in
            let query = searchText.trimmed.lowercased()
            let matchesSearch = query.isEmpty
                || application.companyName.lowercased().contains(query)
                || application.jobTitle.lowercased().contains(query)
            let matchesScope: Bool = switch scopeFilter {
            case ApplicationListScope.archived.rawValue:
                application.isArchived
            case ApplicationListScope.all.rawValue:
                true
            default:
                !application.isArchived
            }
            let matchesStatus = statusFilter == "All" || application.statusRaw == statusFilter
            let matchesPriority = priorityFilter == "All" || application.priorityRaw == priorityFilter
            return matchesSearch && matchesScope && matchesStatus && matchesPriority
        }
    }

    private var applicationScopeCounts: [ApplicationListScope: Int] {
        [
            .active: store.applications.filter { !$0.isArchived }.count,
            .archived: store.applications.filter(\.isArchived).count,
            .all: store.applications.count
        ]
    }

    private var selectedApplication: JobApplication? {
        guard let selectedApplicationID else { return nil }
        return store.applications.first { $0.id == selectedApplicationID }
    }

    private func addApplication() {
        var application = JobApplication(companyName: "New Company", jobTitle: "New Role")
        store.applications.insert(application, at: 0)
        persist(application)
        selectedApplicationID = application.id
    }

    private func requestDeleteApplications(offsets: IndexSet) {
        guard let index = offsets.first else { return }
        requestDelete(filteredApplications[index])
    }

    private func archive(_ application: JobApplication) {
        guard let idx = store.applications.firstIndex(where: { $0.id == application.id }) else { return }
        store.applications[idx].archivedAt = Date()
        store.applications[idx].updatedAt = Date()
        persist(store.applications[idx])
        if scopeFilter == ApplicationListScope.active.rawValue {
            selectedApplicationID = nil
        }
    }

    private func restore(_ application: JobApplication) {
        guard let idx = store.applications.firstIndex(where: { $0.id == application.id }) else { return }
        store.applications[idx].archivedAt = nil
        store.applications[idx].updatedAt = Date()
        persist(store.applications[idx])
        if scopeFilter == ApplicationListScope.archived.rawValue {
            selectedApplicationID = nil
        }
    }

    private func requestDelete(_ application: JobApplication) {
        shouldDeleteApplicationSourceFiles = false
        applicationPendingDeletion = application
    }

    private func delete(_ application: JobApplication, deletingSourceFiles: Bool) {
        if deletingSourceFiles {
            WorkspaceSyncService.deleteApplicationFiles(application, settings: settings)
        }
        store.documents.removeAll { $0.applicationID == application.id }
        store.aiRuns.removeAll { $0.applicationID == application.id }
        store.applications.removeAll { $0.id == application.id }

        if selectedApplicationID == application.id {
            selectedApplicationID = nil
        }
        applicationPendingDeletion = nil
    }

    private func persist(_ application: JobApplication) {
        let applicationDocuments = store.documents.filter { $0.applicationID == application.id }
        try? WorkspaceSyncService.persistApplication(application, documents: applicationDocuments, settings: settings)
    }
}
