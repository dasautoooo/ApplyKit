//
//  ContentView.swift
//  ApplyKit
//

import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case applications = "Applications"
    case employments = "Employments"
    case experienceBank = "Experience Bank"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .applications: "briefcase"
        case .employments: "building.2"
        case .experienceBank: "archivebox"
        }
    }
}

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppDataStore.self) private var store
    @Environment(AppActivityMonitor.self) private var activityMonitor
    @State private var selection: SidebarDestination? = .applications

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarDestination.allCases) { destination in
                    Label(destination.rawValue, systemImage: destination.systemImage)
                        .tag(destination)
                }
            }
            .navigationTitle("ApplyKit")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarStatusBar(monitor: activityMonitor)
            }
        } detail: {
            switch selection ?? .applications {
            case .applications:
                ApplicationsWorkspaceView()
            case .employments:
                EmploymentBankView()
            case .experienceBank:
                ExperienceBankView()
            }
        }
        .task {
            do {
                try WorkspaceSyncService.bootstrap(store: store, settings: settings)
            } catch {
                print("ApplyKit workspace bootstrap failed: \(error.localizedDescription)")
            }
            activityMonitor.history = WorkspaceSyncService.loadActivityHistory(settings: settings)
            activityMonitor.onPersistRecord = { record in
                WorkspaceSyncService.appendActivityRecord(record, settings: settings)
            }
            activityMonitor.onClearHistory = {
                WorkspaceSyncService.clearActivityHistory(settings: settings)
            }
        }
        .onChange(of: settings.workspacePath) { _, _ in
            activityMonitor.history = WorkspaceSyncService.loadActivityHistory(settings: settings)
            activityMonitor.onPersistRecord = { record in
                WorkspaceSyncService.appendActivityRecord(record, settings: settings)
            }
            activityMonitor.onClearHistory = {
                WorkspaceSyncService.clearActivityHistory(settings: settings)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
        .environment(AppDataStore())
        .environment(AppActivityMonitor())
}
