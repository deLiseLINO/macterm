import Foundation
@testable import Macterm
import Testing

@MainActor
struct CompletionNotificationTests {
    @Test
    func runningToDone_postsOneEventWithRoutingIdentifiers() throws {
        let center = NotificationCenter()
        let projectID = UUID()
        let pane = Pane(projectPath: "/tmp/project", projectID: projectID)
        let tab = TerminalTab(id: UUID(), splitRoot: .pane(pane), focusedPaneID: pane.id)
        let state = AppState(
            workspaceStore: WorkspaceStore(fileURL: temporaryURL()),
            projectFiles: ProjectFileStore(directoryURL: temporaryURL()),
            notificationCenter: center
        )
        state.workspaces[projectID] = Workspace(
            projectID: projectID,
            tabs: [tab],
            activeTabID: tab.id
        )
        state.isAppActive = { true }
        state.activeProjectID = projectID
        state.foregroundProcessRefresher = { pane, _ in
            pane.markCommandFinished()
        }
        pane.markCommandRunning()
        #expect(pane.executionState == .running)

        let events = LockedBox<[[String: Any]]>([])
        let observer = center.addObserver(forName: .terminalCommandCompleted, object: nil, queue: .main) { event in
            let values = (event.userInfo ?? [:]).reduce(into: [String: Any]()) { result, entry in
                guard let key = entry.key as? String else { return }
                result[key] = entry.value
            }
            events.mutate { $0.append(values) }
        }
        defer { center.removeObserver(observer) }

        state.refreshAllForegroundProcesses()
        state.refreshAllForegroundProcesses()

        let captured = events.value
        #expect(captured.count == 1)
        let event = try #require(captured.first)
        #expect(UUID(uuidString: event[TerminalCommandCompletionUserInfoKey.projectID] as? String ?? "") == projectID)
        #expect(UUID(uuidString: event[TerminalCommandCompletionUserInfoKey.tabID] as? String ?? "") == tab.id)
        #expect(UUID(uuidString: event[TerminalCommandCompletionUserInfoKey.paneID] as? String ?? "") == pane.id)
        #expect(!((event[TerminalCommandCompletionUserInfoKey.label] as? String) ?? "").isEmpty)
        #expect(event[TerminalCommandCompletionUserInfoKey.outcome] as? String == "success")
        #expect(event[TerminalCommandCompletionUserInfoKey.isQuickTerminal] as? Bool == false)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("macterm-completion-tests-\(UUID().uuidString)")
    }
}
