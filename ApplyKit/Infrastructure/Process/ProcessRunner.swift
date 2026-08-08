import AppKit
import Foundation

enum ProcessRunner {
    nonisolated static func run(
        executablePath: String,
        arguments: [String],
        currentDirectory: URL?,
        standardInput: String? = nil
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdin = standardInput != nil ? Pipe() : nil
        if let stdin { process.standardInput = stdin }

        try process.run()

        // Drain both output pipes *while* the child runs. A pipe holds 64 KiB;
        // once it fills, the child blocks forever on its next write and never
        // exits, so reading only after `waitUntilExit()` hangs the app outright.
        // Codex echoes the whole prompt back on stderr, which crosses 64 KiB on
        // any long job posting.
        let outputDrain = PipeDrain(stdout)
        let errorDrain = PipeDrain(stderr)

        // Same hazard writing: a prompt larger than the pipe can't be handed
        // over in one go, so it has to overlap with the child consuming it.
        if let stdin, let data = standardInput?.data(using: .utf8) {
            DispatchQueue.global(qos: .userInitiated).async {
                // `write(contentsOf:)` throws on a closed pipe; the older
                // `write(_:)` raises an uncatchable ObjC exception instead.
                try? stdin.fileHandleForWriting.write(contentsOf: data)
                try? stdin.fileHandleForWriting.close()
            }
        }

        process.waitUntilExit()

        return CommandResult(
            standardOutput: String(data: outputDrain.value(), encoding: .utf8) ?? "",
            standardError: String(data: errorDrain.value(), encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}

/// Reads a pipe to EOF on its own queue, so a chatty child process is never
/// left blocked on a full pipe buffer while the caller waits for it to exit.
private final class PipeDrain: @unchecked Sendable {
    private let finished = DispatchSemaphore(value: 0)
    private var data = Data()

    init(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            data = handle.readDataToEndOfFile()
            finished.signal()
        }
    }

    /// Blocks until EOF. Safe to call after `waitUntilExit()`: the child closing
    /// its ends is what produces the EOF this is waiting on.
    func value() -> Data {
        finished.wait()
        return data
    }
}

enum LatexService {
    static func build(texPath: String, command: String) async throws -> CommandResult {
        let texURL = URL(fileURLWithPath: texPath)
        let folder = texURL.deletingLastPathComponent()
        let commandLine = "\(command) \(shellQuoted(texURL.lastPathComponent))"
        return try await Task.detached {
            try ProcessRunner.run(executablePath: "/bin/zsh", arguments: ["-lc", commandLine], currentDirectory: folder)
        }.value
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum FileOpenService {
    static func open(path: String) {
        guard !path.trimmed.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func reveal(path: String) {
        guard !path.trimmed.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
