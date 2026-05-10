//
//  ExperienceVariantEditorCard.swift
//  ApplyKit
//

import SwiftUI

struct ExperienceVariantEditorCard: View {
    @Binding var variation: ExperienceVariation
    let usageText: String
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("Variant name", text: $variation.name)
                    .font(.callout.weight(.semibold))
                    .textFieldStyle(.roundedBorder)

                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }

            if !usageText.trimmed.isEmpty {
                Text(usageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            LabeledControl("Bullet") {
                TextEditor(text: $variation.bulletText)
                    .font(.body.monospaced())
                    .frame(minHeight: 96)
            }

            LabeledControl("Notes") {
                TextField("When this wording should be used", text: $variation.notes)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
