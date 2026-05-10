//
//  SettingsComponents.swift
//  ApplyKit
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case profile = "Profile"
    case tools = "Tools"
    case templates = "Templates"
    case data = "Data"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .profile: "person.text.rectangle"
        case .tools: "terminal"
        case .templates: "doc.text"
        case .data: "externaldrive.badge.xmark"
        }
    }
}

struct SettingsHeader: View {
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsPaneButton(
                        pane: pane,
                        isSelected: selection == pane
                    ) {
                        selection = pane
                    }
                }
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsPaneButton: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 21, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                Text(pane.rawValue)
                    .font(.caption)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(width: 72, height: 58)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PreferenceSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PreferenceRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .trailing)
                .padding(.top, 5)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }
}

struct PreferenceDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 140)
    }
}

struct PathValueView: View {
    let text: String
    let isPlaceholder: Bool

    var body: some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .foregroundStyle(isPlaceholder ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            }
    }
}

struct TemplatePickerRow: View {
    let title: String
    @Binding var path: String
    @Binding var bookmark: Data?
    let defaultLabel: String

    @State private var statusMessage = ""

    var body: some View {
        PreferenceRow(title) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    PathValueView(
                        text: path.isEmpty ? defaultLabel : path,
                        isPlaceholder: path.isEmpty
                    )

                    Button {
                        chooseTemplate()
                    } label: {
                        Label("Choose", systemImage: "doc.badge.plus")
                    }

                    if !path.isEmpty {
                        Button {
                            path = ""
                            bookmark = nil
                        } label: {
                            Label("Bundled", systemImage: "arrow.uturn.backward")
                        }
                    }
                }

                if !statusMessage.trimmed.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chooseTemplate() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                path = url.path
                bookmark = try WorkspaceService.bookmarkData(for: url)
                statusMessage = "Template saved."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}

struct FileActionRow: View {
    let title: String
    let path: String

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Text(path)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open") {
                FileOpenService.open(path: path)
            }
            Button("Reveal") {
                FileOpenService.reveal(path: path)
            }
        }
    }
}

struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { date != nil },
                set: { enabled in
                    date = enabled ? (date ?? Date()) : nil
                }
            ))

            if date != nil {
                DatePicker(
                    title,
                    selection: Binding(
                        get: { date ?? Date() },
                        set: { date = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
            }
        }
    }
}

struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}
