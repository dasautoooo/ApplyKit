//
//  SettingsWindowView.swift
//  ApplyKit
//

import SwiftUI

struct SettingsWindowView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selectedPane: SettingsPane = .general

    var body: some View {
        SettingsView(settings: settings, selectedPane: $selectedPane)
            .navigationTitle(selectedPane.rawValue)
            .frame(width: 720)
            .fixedSize(horizontal: true, vertical: true)
    }
}
