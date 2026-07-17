import Foundation

extension Notification.Name {
    static let toggleQuickTerminal = Notification.Name("MactermToggleQuickTerminal")
    static let mactermConfigDidChange = Notification.Name("MactermConfigDidChange")
    static let toggleSidebar = Notification.Name("MactermToggleSidebar")
    static let autoTilingEnabledDidChange = Notification.Name("MactermAutoTilingEnabledDidChange")
    /// Something happened that should wake or speed up the foreground-process
    /// poll: tab switch, OSC title, user interaction, execution-state
    /// transition. Observed by `AppState.notePollEvent()`.
    static let terminalPollEvent = Notification.Name("MactermTerminalPollEvent")
    /// A zmx session was created, killed, or reattached — the
    /// `ZmxForegroundResolver` name→leader-pid cache is stale. Observed by
    /// `AppState`, which invalidates its `ZmxRefreshGate` and wakes the poll.
    static let zmxSessionsChanged = Notification.Name("MactermZmxSessionsChanged")
    static let terminalCommandCompleted = Notification.Name("MactermTerminalCommandCompleted")
}

enum TerminalCommandCompletionUserInfoKey {
    static let projectID = "projectID"
    static let tabID = "tabID"
    static let paneID = "paneID"
    static let label = "label"
    static let outcome = "outcome"
    static let isQuickTerminal = "isQuickTerminal"
    static let completionTimestamp = "completionTimestamp"
}
