import Foundation

enum AgentProvider: String, Codable, Equatable, Sendable {
    case pi
    case omp

    var executable: String { rawValue }
}

typealias AgentSessionProvider = AgentProvider

struct AgentSessionMetadata: Codable, Equatable, Sendable {
    typealias Provider = AgentProvider

    static let schemaVersion: Int = 1

    let provider: AgentProvider
    let sessionID: String

    init(provider: AgentProvider, sessionID: String) {
        self.provider = provider
        self.sessionID = sessionID
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case sessionID
    }
}

enum AgentResumeCommand {
    nonisolated(unsafe) static let validSessionIDPattern = /^[A-Za-z0-9._:@\-]{1,128}$/

    static func argv(for metadata: AgentSessionMetadata) -> [String]? {
        let trimmed = metadata.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              (try? validSessionIDPattern.wholeMatch(in: trimmed)) != nil
        else {
            return nil
        }
        return [metadata.provider.executable, "--session", trimmed]
    }

    static func shellLine(for metadata: AgentSessionMetadata) -> String? {
        guard let argv = argv(for: metadata) else { return nil }
        return argv.compactMap(singleQuoteEscape).joined(separator: " ")
    }

    private static func singleQuoteEscape(_ argument: String) -> String? {
        guard !argument.unicodeScalars.contains(where: { $0 == "\u{0000}" || $0 == "\n" || $0 == "\r" })
        else { return nil }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
