# Desktop Notifications

**Date:** 2026-05-19
**Status:** Draft
**Scope:** Standard

## Problem

Terminal programs (tmux notifications, long-running task completions, chat clients) emit desktop notifications via the OSC 9 escape sequence. libghostty already receives these as `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` callbacks (with `title` and `body` fields), but Macterm silently discards them. Users get no feedback from background terminal activity.

## Requirements

1. **Post macOS system notifications** when a terminal emits a desktop notification via OSC 9.
2. **Only show notifications when Macterm is not frontmost** (or the source pane is not the focused pane). If the user is actively looking at the terminal that triggered the notification, the TUI already displays the content -- a system notification would be redundant noise.
3. **Clicking a notification brings Macterm forward and focuses the source pane** so the user lands at the terminal that produced the notification. The click handler must: (a) activate the app and bring the window forward, (b) switch to the correct project, (c) select the tab containing the pane, (d) focus the pane within that tab. The existing `AppState.focusPane(_:projectID:)` only updates focused-pane state within the active tab -- it does not switch projects, select tabs, or activate the window. A new routing method is needed.
4. **Suppress notifications from panes that no longer exist.** If a pane is closed between the time the notification is posted and the user clicks it, bring Macterm forward but do not attempt to focus a dead pane. The `onDesktopNotification` callback must be nulled in `Pane.destroySurface()` alongside the existing callbacks (`SplitNode.swift:39-45`).
5. **Request notification authorization** at app launch. `UNUserNotificationCenter.requestAuthorization(options:)` must be called before any notification can be delivered. The app currently has no notification infrastructure.
6. **Set the notification delegate early.** A `UNUserNotificationCenterDelegate` must be instantiated and assigned to `UNUserNotificationCenter.current().delegate` at app launch so click responses are captured.

## Non-Goals

- Terminal bell (`GHOSTTY_ACTION_RING_BELL`) handling -- separate feature.
- Settings UI for notification behavior (enable/disable, focus filtering). Can be added later if users ask for it.
- Notification sound customization. Use the system default.
- Notification grouping or throttling. macOS handles this natively for same-source notifications.

## Trigger

- `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` callback from libghostty, currently stubbed at `GhosttyCallbacks.swift:43-44`.

## Data Available

The C struct `ghostty_action_desktop_notification_s` provides:
- `title: [*:0]const u8` -- notification title
- `body: [*:0]const u8` -- notification body

Extracted the same way as existing actions (e.g., `SET_TITLE` at `GhosttyCallbacks.swift:12-16`).

## Focus Detection

Macterm is "in the background" when `NSApp.isActive` is `false`. The source pane is "not focused" when the `GhosttyTerminalNSView.isFocused` flag is `false` (already maintained by `TerminalSurface` in `TerminalPane.swift:93-98`).

Post the notification when either condition is true (app not active OR pane not focused). Both checks must be evaluated on the main thread at dispatch time (inside the `DispatchQueue.main.async` block), not at callback time, to avoid stale state.

## Quick Terminal

The Quick Terminal has its own `TerminalTab`/`SplitNode`/`Pane` tree using a static `projectID` not registered in `AppState.workspaces`. Notifications from quick terminal panes are in scope -- they are real terminals that can emit OSC 9. On notification click for a quick terminal pane, show the Quick Terminal panel and focus the pane within it rather than routing through the main window's `AppState`.

The notification's `userInfo` dictionary needs a flag to distinguish quick terminal panes from workspace panes so the click handler can route correctly.

## Click-to-Focus Routing

The `onDesktopNotification` callback follows the `[weak pane]` closure pattern from `TerminalSurface.configure(_:)` (`TerminalPane.swift:117`). However, `Pane` has no `projectID` property, and `TerminalSurface`/`TerminalPane` do not currently receive `projectID` in their scope.

To store the pane ID and project ID in the notification's `userInfo` dictionary, `projectID` must be threaded into the closure. Options:
- Add `projectID` as a property on `Pane` (it's already available at pane creation time via the workspace)
- Thread it through `TerminalPane` and `TerminalSurface` as a parameter

The `UNUserNotificationCenterDelegate` handles the click response using the `userInfo` dictionary to identify the target pane and route to it.

## Out of Scope

- Rich notification content (images, actions, inline replies)
- Custom notification sounds
- Notification history or persistence beyond what macOS provides
- Badge count on the dock icon

## Success Criteria

- A terminal program that prints `echo -e "\033]9;Title\007"` (OSC 9) produces a visible macOS notification when Macterm is in the background.
- Clicking the notification brings Macterm forward and focuses the source pane.
- Clicking a notification for a pane in a different project/tab switches the sidebar and tab to that pane.
- Clicking a notification for a pane in the Quick Terminal shows the Quick Terminal panel.
- No notification is posted when Macterm is frontmost and the source pane is focused.
- Notifications from closed panes do not crash or misroute.