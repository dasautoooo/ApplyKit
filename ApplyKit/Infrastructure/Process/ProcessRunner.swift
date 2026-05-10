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

        if let standardInput {
            let stdin = Pipe()
            process.standardInput = stdin
            try process.run()
            if let data = standardInput.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
            }
            try? stdin.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        process.waitUntilExit()

        return CommandResult(
            standardOutput: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            standardError: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
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
