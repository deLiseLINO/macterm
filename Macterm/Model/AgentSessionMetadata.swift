import Foundation

enum AgentProvider: String, Codable, Equatable, Sendable {
    case pi
    case omp

    var executable: String { rawValue }
}

typealias AgentSessionProvider = AgentProvider

struct AgentSessionMetadata: Codable, Equatable, Sendable {
    typealias Provider = AgentProvider

    let provider: AgentProvider
    let sessionID: String
    let workingDirectory: String?

    init(provider: AgentProvider, sessionID: String, workingDirectory: String? = nil) {
        self.provider = provider
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
    }
}

enum AgentResumeCommand {
    static func argv(for metadata: AgentSessionMetadata) -> [String]? {
        guard !metadata.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return [metadata.provider.executable, "--session", metadata.sessionID]
    }

    static func shellLine(for metadata: AgentSessionMetadata) -> String? {
        guard let argv = argv(for: metadata) else { return nil }
        return argv.map(shellEscape).joined(separator: " ")
    }

    private static func shellEscape(_ argument: String) -> String {
        let safeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_./:@%+=,-"))
        guard !argument.isEmpty,
              argument.unicodeScalars.allSatisfy(safeCharacters.contains)
        else {
            return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return argument
    }
}
