import Foundation
import Yams

enum WorkspacePersistenceError: LocalizedError {
    case missingApplicationWorkspace(String)
    case invalidWorkspaceFile(String)

    var errorDescription: String? {
        switch self {
        case .missingApplicationWorkspace(let title): return "Could not find a workspace folder for \(title)."
        case .invalidWorkspaceFile(let path): return "Invalid workspace file: \(path)."
        }
    }
}

enum WorkspaceDateCodec {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func string(from date: Date?) -> String? {
        guard let date else { return nil }
        return formatter.string(from: date)
    }

    static func date(from string: String?) -> Date? {
        guard let string, !string.trimmed.isEmpty else { return nil }
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

enum YAMLFileStore {
    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(type, from: text)
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let yaml = try YAMLEncoder().encode(value)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}
