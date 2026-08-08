//
//  AIModelControls.swift
//  ApplyKit
//
//  Model and effort controls for one AI CLI.
//
//  Both default to "whatever the CLI is configured to use" — the app reads that
//  config and shows it rather than claiming a default it hasn't checked (see
//  `AIBackendDefaults`). The model is free text: neither CLI can list the models
//  an account may actually use, so any menu of names would be a guess presented
//  as a choice.
//

import SwiftUI

struct AIModelControls: View {
    @Binding var model: String
    @Binding var effort: String
    let effortOptions: [String]
    let defaultModel: String?
    let defaultEffort: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField(defaultModel ?? "CLI setting", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Picker("Effort", selection: $effort) {
                    Text(defaultEffort.map { "CLI setting (\($0))" } ?? "CLI setting").tag("")
                    Divider()
                    ForEach(effortOptions, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()

                Spacer(minLength: 0)
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: String {
        let resolvedModel = model.trimmed.isEmpty ? defaultModel : model.trimmed
        let resolvedEffort = effort.trimmed.isEmpty ? defaultEffort : effort.trimmed
        switch (resolvedModel, resolvedEffort) {
        case let (model?, effort?):
            return "Runs use \(model) at \(effort) effort."
        case let (model?, nil):
            return "Runs use \(model), at whatever effort the CLI defaults to."
        case let (nil, effort?):
            return "Runs use the CLI's model at \(effort) effort."
        default:
            return "Runs use whatever the CLI is configured for. Its config couldn't be read, so this can't be shown here."
        }
    }
}
