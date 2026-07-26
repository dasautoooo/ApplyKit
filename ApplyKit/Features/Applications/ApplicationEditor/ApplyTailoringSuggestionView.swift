//
//  ApplyTailoringSuggestionView.swift
//  ApplyKit
//
//  The "Apply Suggestion" sheet: copy an id-rich context for ChatGPT, paste the
//  reply, reconcile it into a TailoringPlan via a local AI call, then apply the
//  resulting changes one-by-one or all at once. Logic lives in
//  ApplicationEditorTailoring.swift.
//

import SwiftUI

extension ApplicationEditorView {
    var tailoringSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            tailoringSheetHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tailoringInputSection
                    if !tailoringChanges.isEmpty {
                        Divider()
                        tailoringChangesSection
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 520, idealHeight: 680)
        .onAppear { restoreTailoringSession() }
    }

    private var tailoringSheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apply Tailoring Suggestion")
                    .font(.headline)
                Text(application.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { showTailoringSheet = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var tailoringInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    copyTailoringContext()
                } label: {
                    Label("Copy context for ChatGPT", systemImage: "doc.on.clipboard")
                }
                Spacer()
                if !tailoringChanges.isEmpty || !tailoringPastedText.isEmpty {
                    Button(role: .destructive) {
                        clearTailoringSession()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }

            Text("Paste ChatGPT's tailoring reply below, then reconcile it into applyable changes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $tailoringPastedText)
                .font(.body.monospaced())
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor))
                )

            HStack {
                Button {
                    Task { await reconcileTailoring(pastedReply: tailoringPastedText) }
                } label: {
                    if isReconcilingTailoring {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Reconciling…")
                        }
                    } else {
                        Label(tailoringChanges.isEmpty ? "Reconcile" : "Re-reconcile", systemImage: "sparkles")
                    }
                }
                .disabled(isReconcilingTailoring || tailoringPastedText.trimmed.isEmpty || aiBackendPath == nil)

                if aiBackendPath == nil {
                    Text("Configure an AI CLI in Settings → Tools")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var tailoringChangesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let pending = tailoringChanges.filter { !$0.isBlocked && !$0.applied }.count
            HStack {
                Text("Proposed changes")
                    .font(.headline)
                Spacer()
                Button {
                    applyAllTailoring()
                } label: {
                    Label("Apply All", systemImage: "checkmark.circle")
                }
                .disabled(pending == 0)
            }

            ForEach(tailoringChanges) { change in
                TailoringChangeRow(change: change) {
                    applyTailoringChange(change)
                }
            }
        }
    }
}

private struct TailoringChangeRow: View {
    let change: TailoringChange
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: change.isBlocked ? "exclamationmark.triangle.fill" : "circle")
                    .foregroundStyle(change.isBlocked ? Color.orange : Color.secondary)
                    .imageScale(.small)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.title).font(.subheadline.weight(.semibold))
                    if !change.detail.isEmpty {
                        Text(change.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                actionControl
            }

            if let blocked = change.blockedReason {
                Text(blocked)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                diffView
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        .opacity(change.applied ? 0.6 : 1)
    }

    @ViewBuilder private var actionControl: some View {
        if change.isBlocked {
            EmptyView()
        } else if change.applied {
            Label("Applied", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        } else {
            Button("Apply", action: onApply)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    @ViewBuilder private var diffView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let before = change.before, !before.trimmed.isEmpty {
                labeledText("Current", before, color: .secondary)
            }
            if let after = change.after, !after.trimmed.isEmpty {
                labeledText(change.before == nil ? "New" : "Tailored", after, color: .primary)
            }
        }
    }

    private func labeledText(_ label: String, _ text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
