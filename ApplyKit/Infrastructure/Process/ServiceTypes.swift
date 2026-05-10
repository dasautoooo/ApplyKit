import Foundation

struct CommandResult: Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    var combinedOutput: String {
        [standardOutput, standardError].filter { !$0.trimmed.isEmpty }.joined(separator: "\n")
    }
}

struct GeneratedFileResult {
    let texURL: URL
    let pdfURL: URL
    let warnings: [String]

    init(texURL: URL, pdfURL: URL, warnings: [String] = []) {
        self.texURL = texURL; self.pdfURL = pdfURL; self.warnings = warnings
    }
}

enum WorkflowError: LocalizedError {
    case missingWorkspace
    case missingBundledTemplate(String)
    case fileAlreadyExists(String)
    case invalidPath(String)
    case missingCodexPath
    case missingClaudeCLIPath
    case emptyAIResponse
    case invalidAIResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "Choose a workspace folder in Settings before generating files."
        case .missingBundledTemplate(let name):
            return "Bundled template not found: \(name)."
        case .fileAlreadyExists(let path):
            return "A generated file already exists at \(path). Rename, move, or remove it before generating again."
        case .invalidPath(let path):
            return "Invalid path: \(path)."
        case .missingCodexPath:
            return "Set the Codex CLI path in Settings before running Codex."
        case .missingClaudeCLIPath:
            return "Set the Claude CLI path in Settings → Tools before using AI features."
        case .emptyAIResponse:
            return "The AI command returned an empty response."
        case .invalidAIResponse(let reason):
            return "The AI response could not be used. \(reason)"
        }
    }
}
