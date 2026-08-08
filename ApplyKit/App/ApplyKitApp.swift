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
    /// Owns AI runs so they survive the editor being torn down when you switch
    /// applications — that's what lets several applications tailor at once.
    let tailoringRunner = TailoringRunner()

    init() {
        tailoringRunner.store = store
        tailoringRunner.settings = settings
        tailoringRunner.monitor = activityMonitor
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .environment(activityMonitor)
        .environment(settings)
        .environment(store)
        .environment(tailoringRunner)

        Settings {
            SettingsWindowView()
        }
        .environment(activityMonitor)
        .environment(settings)
        .environment(store)
        .environment(tailoringRunner)
        .windowResizability(.contentSize)
    }
}
