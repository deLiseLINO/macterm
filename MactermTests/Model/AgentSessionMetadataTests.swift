import Foundation
@testable import Macterm
import Testing

@MainActor
struct AgentSessionMetadataTests {
    @Test
    func codable_round_trip_contains_only_allow_listed_metadata() throws {
        let metadata = AgentSessionMetadata(
            provider: .pi,
            sessionID: "native-session-42",
            workingDirectory: "/tmp/project"
        )
        let data = try JSONEncoder().encode(metadata)
        let json = String(decoding: data, as: UTF8.self).lowercased()
        let restored = try JSONDecoder().decode(AgentSessionMetadata.self, from: data)

        #expect(restored == metadata)
        #expect(!json.contains("command"))
        #expect(!json.contains("token"))
        #expect(!json.contains("credential"))
        #expect(!json.contains("environment"))
    }

    @Test
    func blank_or_whitespace_session_ids_are_rejected() {
        #expect(AgentResumeCommand.argv(for: AgentSessionMetadata(provider: .pi, sessionID: "")) == nil)
        #expect(AgentResumeCommand.argv(for: AgentSessionMetadata(provider: .omp, sessionID: " \n\t")) == nil)
    }

    @Test
    func provider_argv_is_exact_for_pi_and_omp() {
        #expect(
            AgentResumeCommand.argv(for: AgentSessionMetadata(provider: .pi, sessionID: "sample"))
                == ["pi", "--session", "sample"]
        )
        #expect(
            AgentResumeCommand.argv(for: AgentSessionMetadata(provider: .omp, sessionID: "sample"))
                == ["omp", "--session", "sample"]
        )
        #expect(AgentResumeCommand.shellLine(for: AgentSessionMetadata(provider: .pi, sessionID: "sample")) == "pi --session sample")
    }

    @Test
    func unknown_provider_fails_decoding() {
        let data = Data(#"{"provider":"other","sessionID":"sample"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AgentSessionMetadata.self, from: data)
        }
    }

    @Test
    func coordinator_resumes_only_absent_sessions_and_only_once() {
        let survivingPane = Pane(projectPath: "/tmp", projectID: UUID())
        survivingPane.agentSession = AgentSessionMetadata(provider: .pi, sessionID: "sample")
        var sent: [String] = []
        let survivingCoordinator = AgentResumeCoordinator(sendText: { _, text in
            sent.append(text)
            return true
        })

        survivingCoordinator.resumeRestoredAgents(
            [survivingPane],
            preRestoreLiveSessionNames: [survivingPane.sessionName]
        )
        #expect(sent.isEmpty)

        let absentPane = Pane(projectPath: "/tmp", projectID: UUID())
        absentPane.agentSession = AgentSessionMetadata(provider: .omp, sessionID: "other")
        let absentCoordinator = AgentResumeCoordinator(sendText: { _, text in
            sent.append(text)
            return true
        })
        absentCoordinator.resumeRestoredAgents([absentPane], preRestoreLiveSessionNames: [])
        absentCoordinator.resumeRestoredAgents([absentPane], preRestoreLiveSessionNames: [])
        #expect(sent == ["omp --session other\n"])
    }

    @Test
    func coordinator_fails_closed_for_unknown_zmx_state() {
        let pane = Pane(projectPath: "/tmp", projectID: UUID())
        pane.agentSession = AgentSessionMetadata(provider: .pi, sessionID: "sample")
        var sent = false
        let coordinator = AgentResumeCoordinator(sendText: { _, _ in
            sent = true
            return true
        })

        coordinator.resumeRestoredAgents([pane], preRestoreLiveSessionNames: nil)
        #expect(!sent)
    }
}
