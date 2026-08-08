//
//  AIBackend.swift
//  ApplyKit
//
//  The configured AI CLI, resolved once and callable from anywhere — the
//  application editor for interactive work, and `TailoringRunner` for runs that
//  outlive the view that started them.
//
//  Each call is its own subprocess, so several can be in flight at once; nothing
//  here serializes them.
//

import Foundation

struct AIBackend {
    let path: String
    let usesClaude: Bool
    /// Blank means "whatever the CLI is configured to use" — see `AIBackendDefaults`.
    var model: String = ""
    var effort: String = ""

    var name: String { usesClaude ? "Claude Code" : "Codex" }

    /// The preferred CLI, falling back to the other one when only it is set.
    static func resolve(settings: AppSettings?) -> AIBackend? {
        guard let settings else { return nil }
        let claude = settings.claudeCLIPath.trimmed.isEmpty ? nil : AIBackend(
            path: settings.claudeCLIPath, usesClaude: true,
            model: settings.claudeModel.trimmed, effort: settings.claudeEffort.trimmed)
        let codex = settings.codexCLIPath.trimmed.isEmpty ? nil : AIBackend(
            path: settings.codexCLIPath, usesClaude: false,
            model: settings.codexModel.trimmed, effort: settings.codexReasoningEffort.trimmed)
        return settings.preferredAIBackendRaw == "Codex" ? (codex ?? claude) : (claude ?? codex)
    }

    /// What this run will actually use, for display: the override when set,
    /// otherwise what the CLI's own config says.
    var effectiveModel: String {
        model.isEmpty ? (AIBackendDefaults.model(usesClaude: usesClaude) ?? "CLI default") : model
    }

    var effectiveEffort: String {
        effort.isEmpty ? (AIBackendDefaults.effort(usesClaude: usesClaude) ?? "CLI default") : effort
    }

    /// Both backends can reach the web when asked: Claude through WebFetch and
    /// WebSearch, Codex through its native `web_search` tool. They fail
    /// differently, though — Claude's WebFetch is refused outright (HTTP 403) by
    /// some sites, so prompts that research tell it to fall back to searching
    /// rather than reporting nothing.
    var canResearch: Bool { true }

    func run(prompt: String, allowWebTools: Bool = false) async throws -> String {
        if usesClaude {
            return try await ClaudeService.run(prompt: prompt, claudePath: path, workingDirectory: nil,
                                               allowWebTools: allowWebTools, model: model, effort: effort)
        }
        return try await CodexService.run(prompt: prompt, codexPath: path, workingDirectory: nil,
                                          allowWebTools: allowWebTools, model: model, reasoningEffort: effort)
            .standardOutput
            .trimmed
    }

    /// Runs `prompt`, parses the reply, and — when that fails — makes one short
    /// repair call that asks only for the JSON back. Models routinely wrap or
    /// malform a long structured reply; re-asking for the shape is far cheaper
    /// than redoing the reasoning. Returns the parsed value and the raw text of
    /// the last attempt, so a total failure stays traceable.
    func runStructured<T>(prompt: String, schema: String, allowWebTools: Bool = false,
                          parse: (String) -> T?) async throws -> (value: T?, raw: String) {
        let response = try await run(prompt: prompt, allowWebTools: allowWebTools)
        if let parsed = parse(response) { return (parsed, response) }
        guard !response.trimmed.isEmpty else { return (nil, response) }

        let repaired = try await run(prompt: PromptBuilder.jsonRepairPrompt(rawReply: response, schema: schema))
        return (parse(repaired), repaired.trimmed.isEmpty ? response : repaired)
    }
}

enum AIResponseArchive {
    /// Writes an unparseable reply into the application's `ai-responses` folder
    /// so a failure can be inspected instead of guessed at. Returns the file name
    /// to show in the error.
    @discardableResult
    static func saveUnparseable(_ text: String, label: String,
                                application: JobApplication, settings: AppSettings?) -> String? {
        guard let settings, !text.trimmed.isEmpty,
              let folder = try? WorkspaceService.ensureApplicationFolder(for: application, settings: settings) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(formatter.string(from: Date()))-\(label)-unparsed.txt"
        let url = folder.appendingPathComponent(WorkspaceFiles.aiResponsesDirectory).appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return name
        } catch {
            return nil
        }
    }
}

/// Reads each CLI's own configuration so the app can show what a run will use
/// when nothing is overridden, instead of claiming a default it doesn't know.
enum AIBackendDefaults {
    static func model(usesClaude: Bool) -> String? {
        usesClaude ? claudeSetting("model") : codexSetting("model")
    }

    static func effort(usesClaude: Bool) -> String? {
        usesClaude ? claudeSetting("effort") : codexSetting("model_reasoning_effort")
    }

    /// `~/.claude/settings.json`, read shallowly — only top-level string values.
    private static func claudeSetting(_ key: String) -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object[key] as? String)?.trimmed.isEmpty == false ? (object[key] as? String) : nil
    }

    /// `$CODEX_HOME/config.toml` (or `~/.codex/config.toml`). A line scrape
    /// rather than a TOML parser: these are flat `key = "value"` entries, and
    /// guessing wrong only costs the label its value.
    private static func codexSetting(_ key: String) -> String? {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let text = try? String(contentsOf: home.appendingPathComponent("config.toml"), encoding: .utf8) else {
            return nil
        }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            // Stop at the first table header: nested tables use the same keys.
            if trimmed.hasPrefix("[") { break }
            guard trimmed.hasPrefix(key) else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0).trimmed }
            guard parts.count == 2, parts[0] == key else { continue }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
