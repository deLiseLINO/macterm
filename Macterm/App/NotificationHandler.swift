import UserNotifications

@MainActor
final class NotificationHandler: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()
    weak var appState: AppState?

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        guard let paneIDString = userInfo["paneID"] as? String,
              let paneID = UUID(uuidString: paneIDString),
              let projectIDString = userInfo["projectID"] as? String,
              let projectID = UUID(uuidString: projectIDString)
        else { return }
        let isQuickTerminal = userInfo["isQuickTerminal"] as? Bool ?? false
        if isQuickTerminal {
            QuickTerminalService.shared.showPanel()
            if let focusedIDString = userInfo["paneID"] as? String,
               let focusedID = UUID(uuidString: focusedIDString),
               QuickTerminalService.shared.splitState.tab.splitRoot.findPane(id: focusedID) != nil
            {
                QuickTerminalService.shared.splitState.tab.focusPane(focusedID)
                FocusRestoration.restoreFocus(
                    to: focusedID,
                    in: QuickTerminalService.shared.splitState.tab.splitRoot,
                    window: QuickTerminalService.shared.panel
                )
            }
        } else {
            appState?.navigateToPane(paneID, projectID: projectID)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
