//
//  SettingsView.swift
//  ApplyKit
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppDataStore.self) private var store
    @Bindable var settings: AppSettings
    @Binding var selectedPane: SettingsPane
    @State private var statusMessage = ""
    @State private var isDetectingCodex = false
    @State private var isDetectingClaude = false
    @State private var showResetConfirmation = false
    @State private var settingsSaveDebouncer = Debouncer()

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(selection: $selectedPane)

            selectedPaneContent
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 26)

            if !statusMessage.trimmed.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: settingsPersistenceFingerprint) { _, _ in
            settingsSaveDebouncer.schedule { persistSettingsChanges() }
        }
        .onDisappear { settingsSaveDebouncer.flush { persistSettingsChanges() } }
        .confirmationDialog(
            "Reset all ApplyKit data?",
            isPresented: $showResetConfirmation
        ) {
            Button("Delete All ApplyKit Data", role: .destructive) {
                resetAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes applications, job descriptions, notes, generated documents, experience items, prompt templates, Codex run files, and the local cache. It does not delete the app.")
        }
    }

    @ViewBuilder
    private var selectedPaneContent: some View {
        switch selectedPane {
        case .profile:
            ProfileSettingsPaneView(settings: settings, statusMessage: $statusMessage)

        case .general:
            VStack(spacing: 18) {
                PreferenceSection(title: "Workspace") {
                    PreferenceRow("Folder") {
                        HStack {
                            PathValueView(
                                text: settings.workspacePath.isEmpty ? "Not set" : settings.workspacePath,
                                isPlaceholder: settings.workspacePath.isEmpty
                            )

                            Button {
                                chooseWorkspace()
                            } label: {
                                Label("Choose", systemImage: "folder.badge.plus")
                            }

                            Button {
                                reloadWorkspace()
                            } label: {
                                Label("Reload", systemImage: "arrow.clockwise")
                            }
                            .disabled(settings.workspacePath.trimmed.isEmpty && settings.workspaceBookmark == nil)
                        }
                    }
                }
            }

        case .tools:
            VStack(spacing: 18) {
                PreferenceSection(title: "AI") {
                    PreferenceRow("Claude CLI") {
                        HStack {
                            TextField("Claude CLI path", text: $settings.claudeCLIPath)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                detectClaudePath()
                            } label: {
                                Label("Detect", systemImage: "location.magnifyingglass")
                            }
                            .disabled(isDetectingClaude)

                            if isDetectingClaude {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }

                    PreferenceDivider()

                    PreferenceRow("Codex CLI") {
                        HStack {
                            TextField("Codex CLI path", text: $settings.codexCLIPath)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                detectCodexPath()
                            } label: {
                                Label("Detect", systemImage: "location.magnifyingglass")
                            }
                            .disabled(isDetectingCodex)

                            if isDetectingCodex {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }

                    PreferenceDivider()

                    PreferenceRow("Preferred Backend") {
                        Picker("Preferred Backend", selection: $settings.preferredAIBackendRaw) {
                            Text("Claude Code").tag("Claude")
                            Text("Codex").tag("Codex")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()

                        Text("Used for Suggest Experiences and Refine with AI. Falls back to the other if the preferred path is not set.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                PreferenceSection(title: "Build") {
                    PreferenceRow("LaTeX") {
                        TextField("LaTeX build command", text: $settings.latexBuildCommand)
                            .textFieldStyle(.roundedBorder)
                    }

                    PreferenceDivider()

                    PreferenceRow("Editor") {
                        TextField("External editor path", text: $settings.externalEditorPath)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

        case .templates:
            VStack(spacing: 18) {
                PreferenceSection(title: "Document Templates") {
                    TemplatePickerRow(
                        title: "Resume",
                        path: $settings.resumeTemplatePath,
                        bookmark: $settings.resumeTemplateBookmark,
                        defaultLabel: "Bundled general_resume.tex"
                    )

                    PreferenceDivider()

                    TemplatePickerRow(
                        title: "Cover letter",
                        path: $settings.coverLetterTemplatePath,
                        bookmark: $settings.coverLetterTemplateBookmark,
                        defaultLabel: "Bundled cover_letter.tex"
                    )
                }
            }

        case .data:
            VStack(spacing: 18) {
                PreferenceSection(title: "Workspace Data") {
                    PreferenceRow("Data") {
                        HStack(spacing: 12) {
                            Button(role: .destructive) {
                                showResetConfirmation = true
                            } label: {
                                Label("Reset All Data", systemImage: "trash")
                            }

                            Text("Clears ApplyKit-managed files and local cache.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var settingsPersistenceFingerprint: String {
        [
            settings.codexCLIPath,
            settings.claudeCLIPath,
            settings.preferredAIBackendRaw,
            settings.latexBuildCommand,
            settings.externalEditorPath,
            settings.resumeTemplatePath,
            settings.coverLetterTemplatePath
        ].joined(separator: "\u{1F}")
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let shouldMigrateExistingCache = settings.hasConfiguredWorkspace
                settings.workspacePath = url.path
                settings.workspaceBookmark = try WorkspaceService.bookmarkData(for: url)
                try WorkspaceSyncService.activateWorkspace(store: store, settings: settings, migrateExistingCache: shouldMigrateExistingCache)
                statusMessage = "Workspace saved and loaded."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func reloadWorkspace() {
        do {
            try WorkspaceSyncService.reloadWorkspace(store: store, settings: settings)
            statusMessage = "Workspace reloaded from files."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func persistSettingsChanges() {
        do {
            try WorkspaceSyncService.persistSettings(settings)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func detectCodexPath() {
        isDetectingCodex = true
        statusMessage = "Detecting Codex CLI..."

        Task {
            let detectedPath = await Task.detached {
                CodexPathDetector.detect()
            }.value

            if let detectedPath {
                settings.codexCLIPath = detectedPath
                do {
                    try WorkspaceSyncService.persistSettings(settings)
                    statusMessage = "Detected Codex CLI at \(detectedPath)."
                } catch {
                    statusMessage = error.localizedDescription
                }
            } else {
                statusMessage = "Codex CLI was not found. Install it or enter the path manually."
            }

            isDetectingCodex = false
        }
    }

    private func detectClaudePath() {
        isDetectingClaude = true
        statusMessage = "Detecting Claude CLI..."

        Task {
            let detectedPath = await Task.detached {
                ClaudePathDetector.detect()
            }.value

            if let detectedPath {
                settings.claudeCLIPath = detectedPath
                do {
                    try WorkspaceSyncService.persistSettings(settings)
                    statusMessage = "Detected Claude CLI at \(detectedPath)."
                } catch {
                    statusMessage = error.localizedDescription
                }
            } else {
                statusMessage = "Claude CLI was not found. Install Claude Code or enter the path manually."
            }

            isDetectingClaude = false
        }
    }

    private func resetAllData() {
        do {
            try WorkspaceSyncService.resetAllData(store: store, settings: settings)
            statusMessage = "ApplyKit data reset."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct ProfileSettingsPaneView: View {
    @Environment(AppDataStore.self) private var store
    var settings: AppSettings
    @Binding var statusMessage: String
    @State private var profileSaveDebouncer = Debouncer()

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 18) {
            PreferenceSection(title: "Identity") {
                PreferenceRow("Full Name") {
                    TextField("Your Name", text: $store.profile.fullName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            PreferenceSection(title: "Contact") {
                PreferenceRow("City") {
                    TextField("e.g. Toronto, ON, Canada", text: $store.profile.city)
                        .textFieldStyle(.roundedBorder)
                }
                PreferenceDivider()
                PreferenceRow("Phone") {
                    TextField("e.g. (416) 555-1234", text: $store.profile.phone)
                        .textFieldStyle(.roundedBorder)
                }
                PreferenceDivider()
                PreferenceRow("Email") {
                    TextField("you@example.com", text: $store.profile.email)
                        .textFieldStyle(.roundedBorder)
                }
            }

            PreferenceSection(title: "Online") {
                PreferenceRow("LinkedIn") {
                    TextField("linkedin.com/in/you", text: $store.profile.linkedin)
                        .textFieldStyle(.roundedBorder)
                }
                PreferenceDivider()
                PreferenceRow("GitHub") {
                    TextField("github.com/you", text: $store.profile.github)
                        .textFieldStyle(.roundedBorder)
                }
                PreferenceDivider()
                PreferenceRow("Website") {
                    TextField("www.yoursite.com", text: $store.profile.website)
                        .textFieldStyle(.roundedBorder)
                }
            }

            PreferenceSection(title: "Resume Sections") {
                PreferenceRow("Education") {
                    TextEditor(text: $store.profile.educationBlock)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                        )
                }
                PreferenceDivider()
                PreferenceRow("Skills") {
                    TextEditor(text: $store.profile.skillsBlock)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                        )
                }
            }
        }
        .onChange(of: profileFingerprint) { _, _ in profileSaveDebouncer.schedule { saveProfile() } }
        .onDisappear { profileSaveDebouncer.flush { saveProfile() } }
    }

    private var profileFingerprint: String {
        let p = store.profile
        return [p.fullName, p.city, p.phone, p.email, p.linkedin, p.github, p.website,
                p.educationBlock, p.skillsBlock].joined(separator: "\u{1F}")
    }

    private func saveProfile() {
        do {
            try WorkspaceSyncService.persistProfile(store.profile, settings: settings)
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
