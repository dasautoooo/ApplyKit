//
//  ApplyKitApp.swift
//  ApplyKit
//
//  Created by Leonard Chen on 5/7/26.
//

import SwiftUI

@main
struct ApplyKitApp: App {
    let activityMonitor = AppActivityMonitor()
    let settings = AppSettings()
    let store = AppDataStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .environment(activityMonitor)
        .environment(settings)
        .environment(store)

        Settings {
            SettingsWindowView()
        }
        .environment(activityMonitor)
        .environment(settings)
        .environment(store)
        .windowResizability(.contentSize)
    }
}
