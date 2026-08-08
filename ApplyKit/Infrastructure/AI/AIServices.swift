//
//  WorkflowServices.swift
//  ApplyKit
//
//  AI command helpers. Other workflow services live in ApplyKit/Services.
//

import Foundation

enum CodexPathDetector {
    nonisolated static func detect() -> String? {
        if let path = commonExecutablePath() {
            return path
        }
        return shellExecutablePath()
    }

    nonisolated static func isExecutablePath(_ path: String) -> Bool {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard !trimmed(expandedPath).isEmpty else { return false }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: expandedPath)
    }

    nonisolated private static func commonExecutablePath() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.volta/bin/codex",
            "\(home)/.asdf/shims/codex",
            "\(home)/.bun/bin/codex"
        ]

        return candidates.first { isExecutablePath($0) }
    }

    nonisolated private static func shellExecutablePath() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"].map(trimmed)
        let shellPath = shell?.isEmpty == false ? shell! : "/bin/zsh"
        guard isExecutablePath(shellPath) else { return nil }

        guard let result = try? ProcessRunner.run(
            executablePath: shellPath,
            arguments: ["-lc", "command -v codex"],
            currentDirectory: nil
        ), result.exitCode == 0 else {
            return nil
        }

        guard let path = result.standardOutput
            .split(whereSeparator: \.isNewline)
            .map({ trimmed(String($0)) })
            .first(where: { $0.hasPrefix("/") && isExecutablePath($0) }) else {
            return nil
        }

        return path
    }

    nonisolated private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ClaudePathDetector {
    nonisolated static func detect() -> String? {
        if let path = commonExecutablePath() { return path }
        return shellExecutablePath()
    }

    nonisolated static func isExecutablePath(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir)
        return exists && !isDir.boolValue && FileManager.default.isExecutableFile(atPath: expanded)
    }

    nonisolated private static func commonExecutablePath() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.volta/bin/claude",
            "\(home)/.asdf/shims/claude",
            "\(home)/.bun/bin/claude"
        ]
        return candidates.first { isExecutablePath($0) }
    }

    nonisolated private static func shellExecutablePath() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shellPath = (shell?.isEmpty == false) ? shell! : "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shellPath) else { return nil }
        guard let result = try? ProcessRunner.run(
            executablePath: shellPath,
            arguments: ["-lc", "command -v claude"],
            currentDirectory: nil
        ), result.exitCode == 0 else { return nil }
        return result.standardOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("/") && isExecutablePath($0) }
    }
}

enum CodexService {
    /// Codex's sandbox has no network, but its native `web_search` tool does —
    /// it is simply off unless asked for. This is what lets a Codex-backed run
    /// read the live posting and the résumé references the tailoring rules cite.
    private static let webSearchArguments = ["-c", "tools.web_search=true"]

    static func run(prompt: String, codexPath: String, workingDirectory: URL?,
                    allowWebTools: Bool = false, model: String = "",
                    reasoningEffort: String = "") async throws -> CommandResult {
        let path = codexPath.trimmed
        guard !path.isEmpty else {
            throw WorkflowError.missingCodexPath
        }

        var arguments = ["exec"]
        if allowWebTools { arguments += webSearchArguments }
        if !model.trimmed.isEmpty { arguments += ["--model", model.trimmed] }
        if !reasoningEffort.trimmed.isEmpty {
            arguments += ["-c", "model_reasoning_effort=\"\(reasoningEffort.trimmed)\""]
        }
        arguments += ["--skip-git-repo-check", "--sandbox", "read-only", "--color", "never", "-"]

        let result = try await Task.detached { [arguments] in
            try ProcessRunner.run(
                executablePath: path,
                arguments: arguments,
                currentDirectory: workingDirectory,
                standardInput: prompt
            )
        }.value
        guard result.succeeded else {
            throw WorkflowError.aiCommandFailed(
                backend: "Codex",
                exitCode: result.exitCode,
                details: AIServiceSupport.errorSummary(from: result)
            )
        }
        return result
    }
}

enum ClaudeService {
    /// Tools the CLI may use without a prompt when a run is allowed to research.
    /// Headless runs auto-deny anything not listed here, so an un-allowlisted
    /// fetch would simply come back unanswered.
    private static let webTools = "WebFetch,WebSearch"

    static func run(prompt: String, claudePath: String, workingDirectory: URL?,
                    allowWebTools: Bool = false, model: String = "",
                    effort: String = "") async throws -> String {
        try await runCommand(prompt: prompt, claudePath: claudePath, workingDirectory: workingDirectory,
                             allowWebTools: allowWebTools, model: model, effort: effort)
            .standardOutput
            .trimmed
    }

    static func runCommand(prompt: String, claudePath: String, workingDirectory: URL?,
                           allowWebTools: Bool = false, model: String = "",
                           effort: String = "") async throws -> CommandResult {
        let path = claudePath.trimmed
        guard !path.isEmpty else { throw WorkflowError.missingClaudeCLIPath }
        var arguments = ["-p", "--output-format", "text"]
        if allowWebTools { arguments += ["--allowedTools", webTools] }
        if !model.trimmed.isEmpty { arguments += ["--model", model.trimmed] }
        if !effort.trimmed.isEmpty { arguments += ["--effort", effort.trimmed] }
        let result = try await Task.detached { [arguments] in
            try ProcessRunner.run(
                executablePath: path,
                arguments: arguments,
                currentDirectory: workingDirectory,
                standardInput: prompt
            )
        }.value
        guard result.succeeded else {
            throw WorkflowError.aiCommandFailed(
                backend: "Claude",
                exitCode: result.exitCode,
                details: AIServiceSupport.errorSummary(from: result)
            )
        }
        return result
    }
}

enum AIServiceSupport {
    /// Condenses a failed CLI run into a short human-readable reason, favouring
    /// the last error-looking stderr lines over progress/banner output.
    static func errorSummary(from result: CommandResult) -> String {
        let lines = result.standardError
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let errorLines = lines.filter { $0.localizedCaseInsensitiveContains("error") }
        let picked = (errorLines.isEmpty ? lines : errorLines).suffix(2).joined(separator: " ")
        return String(picked.prefix(300))
    }
}
