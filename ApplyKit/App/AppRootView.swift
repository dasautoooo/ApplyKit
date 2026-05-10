//
//  AppRootView.swift
//  ApplyKit
//

import AppKit
import SwiftUI

struct AppRootView: View {
    @Environment(AppSettings.self) private var settings

    @State private var bootstrapMessage = ""

    var body: some View {
        Group {
            if settings.hasConfiguredWorkspace {
                ContentView()
            } else {
                WorkspaceOnboardingView(statusMessage: bootstrapMessage)
            }
        }
    }
}

struct WorkspaceOnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppDataStore.self) private var store

    let statusMessage: String

    @State private var localStatusMessage = ""
    @State private var isWorking = false
    @State private var codexPath = ""
    @State private var codexDetectionMessage = ""
    @State private var isDetectingCodex = false
    @State private var claudePath = ""
    @State private var claudeDetectionMessage = ""
    @State private var isDetectingClaude = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Set Up ApplyKit")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("Choose a workspace folder before using the app. ApplyKit stores applications, job descriptions, notes, resumes, experience items, prompt templates, and run metadata as files in that folder.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("YAML and Markdown files are the source of truth.", systemImage: "doc.text")
                Label("Data is loaded into memory on launch.", systemImage: "arrow.triangle.2.circlepath")
                Label("An empty workspace is initialized automatically.", systemImage: "folder.badge.plus")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Codex CLI", systemImage: "terminal")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField("Codex CLI path", text: $codexPath)
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

                if !codexDetectionMessage.trimmed.isEmpty {
                    Text(codexDetectionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Claude Code CLI", systemImage: "sparkles")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField("Claude CLI path", text: $claudePath)
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

                if !claudeDetectionMessage.trimmed.isEmpty {
                    Text(claudeDetectionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button {
                    chooseWorkspace()
                } label: {
                    Label("Choose Workspace", systemImage: "folder")
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)

                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            let message = localStatusMessage.trimmed.isEmpty ? statusMessage : localStatusMessage
            if !message.trimmed.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(48)
        .frame(minWidth: 620, idealWidth: 720, maxWidth: 820, minHeight: 420, alignment: .leading)
        .task {
            prepareCodexPath()
            prepareClaudePath()
        }
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Workspace"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            if codexPath.trimmed.isEmpty, let detectedPath = CodexPathDetector.detect() {
                codexPath = detectedPath
            }
            if claudePath.trimmed.isEmpty, let detectedPath = ClaudePathDetector.detect() {
                claudePath = detectedPath
            }
            settings.workspacePath = url.path
            settings.workspaceBookmark = try WorkspaceService.bookmarkData(for: url)
            settings.codexCLIPath = codexPath.trimmed
            settings.claudeCLIPath = claudePath.trimmed
            try WorkspaceSyncService.activateWorkspace(store: store, settings: settings, migrateExistingCache: false)
            localStatusMessage = "Workspace saved and loaded."
        } catch {
            localStatusMessage = error.localizedDescription
        }
    }

    private func prepareCodexPath() {
        if codexPath.trimmed.isEmpty {
            codexPath = settings.codexCLIPath
        }

        if codexPath.trimmed.isEmpty || !CodexPathDetector.isExecutablePath(codexPath) {
            detectCodexPath()
        } else {
            codexDetectionMessage = "Using \(codexPath)."
        }
    }

    private func prepareClaudePath() {
        if claudePath.trimmed.isEmpty {
            claudePath = settings.claudeCLIPath
        }

        if claudePath.trimmed.isEmpty || !ClaudePathDetector.isExecutablePath(claudePath) {
            detectClaudePath()
        } else {
            claudeDetectionMessage = "Using \(claudePath)."
        }
    }

    private func detectClaudePath() {
        isDetectingClaude = true
        claudeDetectionMessage = "Detecting Claude CLI..."

        Task {
            let detectedPath = await Task.detached {
                ClaudePathDetector.detect()
            }.value

            if let detectedPath {
                claudePath = detectedPath
                claudeDetectionMessage = "Detected \(detectedPath)."
            } else {
                claudeDetectionMessage = "Claude CLI was not found. Install Claude Code or enter the path manually."
            }

            isDetectingClaude = false
        }
    }

    private func detectCodexPath() {
        isDetectingCodex = true
        codexDetectionMessage = "Detecting Codex CLI..."

        Task {
            let detectedPath = await Task.detached {
                CodexPathDetector.detect()
            }.value

            if let detectedPath {
                codexPath = detectedPath
                codexDetectionMessage = "Detected \(detectedPath)."
            } else {
                codexDetectionMessage = "Codex CLI was not found. Install it or enter the path manually."
            }

            isDetectingCodex = false
        }
    }
}
