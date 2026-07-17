import os
import UserNotifications

private let logger = Logger(subsystem: appBundleID, category: "NotificationHandler")

/// The delegate methods are `nonisolated` (they can be called off-main) and
/// hand off to the main actor explicitly via a `Task { @MainActor }`, instead
/// of a `@preconcurrency` conformance that would silently disable isolation
/// checking.
@MainActor
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    weak var appState: AppState?

    private let notificationCenter: NotificationCenter
    private let userNotificationCenter: UNUserNotificationCenter

    init(
        notificationCenter: NotificationCenter = .default,
        userNotificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.notificationCenter = notificationCenter
        self.userNotificationCenter = userNotificationCenter
        super.init()

        notificationCenter.addObserver(
            self,
            selector: #selector(commandCompleted(_:)),
            name: .terminalCommandCompleted,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    @objc private func commandCompleted(_ notification: Notification) {
        handleCommandCompletion(notification)
    }
    func requestAuthorization() {
        userNotificationCenter.requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                logger.error("Macterm notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                logger.notice("Macterm notification authorization denied")
            }
        }
    }

    private func handleCommandCompletion(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let projectID = userInfo[TerminalCommandCompletionUserInfoKey.projectID] as? String,
              let tabID = userInfo[TerminalCommandCompletionUserInfoKey.tabID] as? String,
              let paneID = userInfo[TerminalCommandCompletionUserInfoKey.paneID] as? String,
              UUID(uuidString: projectID) != nil,
              UUID(uuidString: tabID) != nil,
              UUID(uuidString: paneID) != nil
        else { return }

        let label = (userInfo[TerminalCommandCompletionUserInfoKey.label] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = (userInfo[TerminalCommandCompletionUserInfoKey.outcome] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuickTerminal = userInfo[TerminalCommandCompletionUserInfoKey.isQuickTerminal] as? Bool ?? false
        let timestamp = (userInfo[TerminalCommandCompletionUserInfoKey.completionTimestamp] as? String)
            ?? String(format: "%.6f", Date().timeIntervalSince1970)

        let content = UNMutableNotificationContent()
        content.title = "Command completed"
        content.body = [label, outcome].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        content.userInfo = [
            TerminalCommandCompletionUserInfoKey.projectID: projectID,
            TerminalCommandCompletionUserInfoKey.tabID: tabID,
            TerminalCommandCompletionUserInfoKey.paneID: paneID,
            TerminalCommandCompletionUserInfoKey.outcome: outcome ?? "success",
            TerminalCommandCompletionUserInfoKey.isQuickTerminal: isQuickTerminal
        ]

        let request = UNNotificationRequest(
            identifier: "macterm-command-\(paneID)-\(timestamp)",
            content: content,
            trigger: nil
        )
        userNotificationCenter.add(request) { error in
            if let error {
                logger.error("Macterm completion notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Extract only Sendable values (Strings/Bool) from the non-Sendable
        // response before handing off to the main actor.
        let userInfo = response.notification.request.content.userInfo
        let paneIDString = userInfo[TerminalCommandCompletionUserInfoKey.paneID] as? String
        let projectIDString = userInfo[TerminalCommandCompletionUserInfoKey.projectID] as? String
        let tabIDString = userInfo[TerminalCommandCompletionUserInfoKey.tabID] as? String
        let isQuickTerminal = userInfo[TerminalCommandCompletionUserInfoKey.isQuickTerminal] as? Bool ?? false
        completionHandler()

        guard let paneIDString, let paneID = UUID(uuidString: paneIDString),
              let projectIDString, let projectID = UUID(uuidString: projectIDString),
              let tabIDString, let tabID = UUID(uuidString: tabIDString)
        else { return }
        Task { @MainActor in
            Self.shared.handleTap(
                paneID: paneID,
                tabID: tabID,
                projectID: projectID,
                isQuickTerminal: isQuickTerminal
            )
        }
    }

    private func handleTap(paneID: UUID, tabID: UUID, projectID: UUID, isQuickTerminal: Bool) {
        if isQuickTerminal {
            let tab = QuickTerminalService.shared.splitState.tab
            guard tab.id == tabID, tab.splitRoot.findPane(id: paneID) != nil else { return }
            QuickTerminalService.shared.showPanel()
            tab.focusPane(paneID)
            FocusRestoration.restoreFocus(
                to: paneID,
                in: tab.splitRoot,
                window: QuickTerminalService.shared.panel
            )
        } else {
            guard let appState,
                  let workspace = appState.workspaces[projectID],
                  let tab = workspace.tabs.first(where: { $0.id == tabID }),
                  tab.splitRoot.findPane(id: paneID) != nil
            else { return }
            appState.navigateToPane(paneID, projectID: projectID)
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
