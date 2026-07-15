//
//  ReferenceTextPopover.swift
//  ApplyKit
//

import AppKit
import SwiftUI

/// Small button that reveals reference text (e.g. a base bullet or default role
/// description) in a popover with a Copy action, instead of taking up inline space.
struct ReferenceTextPopoverButton: View {
    let label: String
    let popoverTitle: String
    let text: String
    var emptyPlaceholder: String = "Nothing here yet."
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(label, systemImage: "doc.plaintext")
        }
        .controlSize(.small)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(popoverTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(text.trimmed.isEmpty ? emptyPlaceholder : text)
                        .font(.body.monospaced())
                        .foregroundStyle(text.trimmed.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)

                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .disabled(text.trimmed.isEmpty)
                }
            }
            .padding(14)
            .frame(width: 420)
        }
    }
}
