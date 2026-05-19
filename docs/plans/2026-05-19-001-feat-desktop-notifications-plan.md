---
title: "feat: Desktop Notifications via OSC 9"
type: feat
status: completed
date: 2026-05-19
origin: docs/brainstorms/desktop-notifications-requirements.md
deepened: 2026-05-19
---

# feat: Desktop Notifications via OSC 9

## Overview

Wire libghostty's existing `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` callback to macOS `UNUserNotificationCenter` so terminal programs that emit OSC 9 notifications produce visible system notifications. Clicking a notification brings Macterm forward and focuses the source pane.

## Problem Frame

Terminal programs (tmux, long-running tasks, chat clients) emit desktop notifications via OSC 9. libghostty already receives these callbacks with title/body data, but Macterm silently discards them at `GhosttyCallbacks.swift:43-44`. Users get no feedback from background terminal activity. (See origin: `docs/brainstorms/desktop-notifications-requirements.md`)

## Requirements Trace

- R1. Post macOS system notifications when a terminal emits OSC 9 (origin req 1)
- R2. Only show notifications when app is not frontmost or source pane is not focused (origin req 2)
- R3. Clicking a notification navigates to the source pane: activate app, switch project, select tab, focus pane (origin req 3)
- R4. Suppress notifications from closed panes; nil out callback in destroySurface (origin req 4)
- R5. Request notification authorization at app launch (origin req 5)
- R6. Set UNUserNotificationCenterDelegate at app launch (origin req 6)
- R7. Quick terminal pane notifications show the Quick Terminal panel on click (origin Quick Terminal section)

## Scope Boundaries

- No terminal bell (`GHOSTTY_ACTION_RING_BELL`) handling
- No settings UI for notification behavior
- No custom notification sounds
- No rich notification content (images, actions, inline replies)
- No badge count or notification grouping beyond what macOS provides natively

## Context & Research

### Relevant Code and Patterns

- `GhosttyCallbacks.swift:10-47` -- action dispatch pattern with `surfaceView(from:)` and C string extraction
- `GhosttyCallbacks.swift:12-16` -- `GHOSTTY_ACTION_SET_TITLE` pattern: extract C string, dispatch to main, call view callback
- `TerminalPane.swift:111-136` -- `TerminalSurface.configure(_:)` wires NSView callbacks with `[weak pane]` closures
- `SplitNode.swift:36-55` -- `Pane.destroySurface()` nulls all callbacks before destroying surface
- `AppState.swift:300-302` -- `focusPane` only updates `focusedPaneID` within the active tab (insufficient for R3)
- `AppState.swift:97-101` -- `selectProject` sets `activeProjectID` and records recency
- `Workspace.swift:201-205` -- `Workspace.selectTab` updates `activeTabID`
- `MactermApp.swift:83-128` -- `applicationDidFinishLaunching` initialization sequence
- `MactermApp.swift:198-219` -- `reopenIfNeeded()` walks `NSApp.windows` for hidden non-panel windows (used when window is ordered-out)
- `QuickTerminal.swift:386` -- `QuickTerminalView.projectID` is a static UUID not in `AppState.workspaces`

### Institutional Learnings

None -- no prior notification work in the codebase.

## Key Technical Decisions

- **Add `projectID` to `Pane`**: Pane currently has `projectPath` but no `projectID`. Adding `projectID: UUID` allows the notification callback to carry both pane ID and project ID for click routing without threading the value through the view hierarchy. The projectID is available at every Pane creation site (from `Workspace.projectID` or `QuickTerminalView.projectID`). (See origin: Click-to-Focus Routing section)
- **New `AppState.navigateToPane` method**: The existing `focusPane` is insufficient for R3. A new method composes project switching + tab selection + pane focus + app activation + window unhide. Uses `selectProject` (preserves recency and workspace-ensure side effects) rather than setting `activeProjectID` directly. Uses `AppDelegate.reopenIfNeeded()` to unhide the ordered-out main window (see `MactermApp.swift:198-219` for the hidden-window recovery pattern).
- **`NotificationHandler` singleton as `UNUserNotificationCenterDelegate`**: Small class that lives for the app's lifetime, set as delegate in `applicationDidFinishLaunching`. Click handler stubs workspace routing until Unit 3 provides `navigateToPane`, and Quick Terminal routing until Unit 5 provides `showPanel()`.
- **`onDesktopNotification` callback on `GhosttyTerminalNSView`**: Follows the established `[weak pane]` closure pattern. Closure captures pane ID and project ID at configure time, posts `UNNotificationContent` with `userInfo` carrying these IDs plus a `isQuickTerminal` flag.
- **Add `QuickTerminalService.showPanel()`**: A new internal method that shows the Quick Terminal panel when hidden, or brings it forward and focuses when already visible. Unlike `toggle()`, this never hides the panel. Required because the existing `show()` is private and `toggle()` would hide the panel when already visible.

## Open Questions

### Resolved During Planning

- **projectID on Pane vs. threading through view hierarchy**: Add to Pane. Cleaner, available everywhere the pane is referenced, avoids threading through multiple view layers. (User confirmed)

### Deferred to Implementation

- **Exact `ghostty_action_desktop_notification_s` field access path**: `action.action.desktop_notification.title` / `.body` follows naming convention of other actions, but GhosttyKit headers are not in the repo. Compile-time verification will confirm.
- **Whether `UNUserNotificationCenter.requestAuthorization` should request `.sound` alongside `.alert`**: Requesting `.alert` only keeps the permission prompt minimal. Adding `.sound` is low-cost for future extensibility. Implementation can decide.

## Implementation Units

- [ ] **Unit 1: Add projectID to Pane and thread through creation sites**

**Goal:** Give every Pane a `projectID: UUID` so notification callbacks can route clicks to the correct project.

**Requirements:** R3, R7

**Dependencies:** None

**Files:**
- Modify: `Macterm/Model/SplitNode.swift`
- Modify: `Macterm/Model/Workspace.swift`
- Modify: `Macterm/Persistence/WorkspacePersistence.swift`
- Modify: `Macterm/Views/QuickTerminal.swift`
- Modify: `MactermTests/Support/TreeBuilder.swift`
- Test: `MactermTests/Model/PaneTests.swift`
- Test: `MactermTests/Model/SplitNodeTests.swift`

**Approach:** Add `let projectID: UUID` to `Pane`. Update `Pane.init(projectPath:)` to `Pane.init(projectPath:projectID:)`. Thread projectID from every creation site:
- `TerminalTab.init(projectPath:projectID:)` (from `Workspace.init`)
- `SplitNode.splitting(paneID:direction:position:projectPath:projectID:)` (new pane inherits source pane's projectID via `splitRoot.findPane`)
- `WorkspacePersistence.restoreNode(_:projectID:)` -- add a `projectID` parameter to the restore method, threaded from `WorkspaceSerializer.restore()` which has `snap.projectID` available
- `QuickTerminalSplitState.init` (uses `QuickTerminalView.projectID`)
- Test files (use `UUID()` or a test constant)

Note: `PaneSnapshot` does not need a `projectID` field because pane IDs are not stable across restarts (CLAUDE.md). On restore, `projectID` comes from the enclosing workspace context, not from the persisted snapshot.

**Patterns to follow:**
- `Pane.init(projectPath:)` at `SplitNode.swift:85-87`
- `TerminalTab.init(projectPath:)` at `Workspace.swift:57-62`
- `Workspace.init(projectID:projectPath:)` at `Workspace.swift:158-163`
- `WorkspaceSerializer.restore()` at `WorkspacePersistence.swift:148-159`

**Test scenarios:**
- Happy path: Pane created with a specific projectID retains it
- Edge case: Split pane inherits the source pane's projectID, not the workspace's
- Integration: WorkspacePersistence round-trip preserves projectID across save/restore

**Verification:**
- All existing tests pass after API change
- Pane.projectID is set and accessible for workspace panes and quick terminal panes

---

- [ ] **Unit 2: Add UNUserNotificationCenter infrastructure and NotificationHandler**

**Goal:** Set up notification authorization, delegate, and click-response stub at app launch.

**Requirements:** R5, R6

**Dependencies:** None (can be built in parallel with Unit 1)

**Files:**
- Create: `Macterm/App/NotificationHandler.swift`
- Modify: `Macterm/App/MactermApp.swift`
- Modify: `project.yml`

**Approach:**
- Add `UserNotifications.framework` to `project.yml` dependencies
- Create `NotificationHandler` class: `@MainActor`, conforms to `UNUserNotificationCenterDelegate`
  - `requestAuthorization()` calls `UNUserNotificationCenter.current().requestAuthorization(options: [.alert])`
  - `userNotificationCenter(_:didReceive:withCompletionHandler:)` handles notification click:
    - Read `userInfo` for `paneID`, `projectID`, `isQuickTerminal`
    - If `isQuickTerminal`: stub -- will be wired in Unit 5
    - Else: stub -- will be wired to `AppState.navigateToPane` in Unit 3
  - Holds weak reference to `AppState` (set after `onAppear` provides it)
- In `applicationDidFinishLaunching`:
  - Place notification setup **after** the `XCTestConfigurationFilePath` test guard, **before** `_ = GhosttyApp.shared`
  - Create `NotificationHandler.shared`, assign as `UNUserNotificationCenter.current().delegate`
  - Call `requestAuthorization()`

Note: The click handler is stubbed in this unit. The workspace-routing branch is wired in Unit 3 (after `navigateToPane` exists). The Quick Terminal branch is wired in Unit 5 (after `showPanel()` exists). This avoids a hard dependency on later units.

**Patterns to follow:**
- `GhosttyApp.shared` singleton pattern at `MactermApp.swift:94`
- `AppDelegate.appState` lazy acquisition pattern at `MactermApp.swift:36`
- Test guard at `MactermApp.swift:89-91`

**Test scenarios:**
- Happy path: requestAuthorization called at launch, delegate assigned
- Edge case: App launches in test mode (XCTestConfigurationFilePath check) -- skip authorization and delegate setup
- Happy path: click handler doesn't crash with stubbed routing

**Verification:**
- App launch completes without crashes; UNUserNotificationCenter delegate is set
- Notification authorization prompt appears on first launch

---

- [ ] **Unit 3: Add AppState.navigateToPane method and wire workspace click routing**

**Goal:** Provide a method that activates the app, unhides the window, switches to the correct project, selects the tab containing a pane, focuses it, and wire it into the NotificationHandler.

**Requirements:** R3

**Dependencies:** Unit 1 (Pane.projectID required by callers to populate userInfo dict), Unit 2 (NotificationHandler click handler exists to wire into)

**Files:**
- Modify: `Macterm/App/AppState.swift`
- Modify: `Macterm/App/NotificationHandler.swift`
- Test: `MactermTests/App/AppStateTests.swift`

**Approach:**
Add `navigateToPane(_ paneID: UUID, projectID: UUID)` that:
1. Call `selectProject` with a matching project (or call `recordProjectVisit` + `ensureWorkspace` explicitly if a full `Project` isn't available, then set `activeProjectID`)
2. Find the tab containing the pane: `workspaces[projectID]?.tabs.first(where: { $0.splitRoot.findPane(id: paneID) != nil })`
3. If tab found: call `workspace.selectTab(tab.id)` then `tab.focusPane(paneID)`
4. Unhide the main window and activate the app: call `AppDelegate.reopenIfNeeded()` which handles the ordered-out window case (`MactermApp.swift:198-219`), then `NSApp.activate()`
5. `DispatchQueue.main.async` for `FocusRestoration.restoreFocus(to:in:window:)` (same pattern as `restoreFocusToActivePane`)

If the pane no longer exists in any tab (it was closed), skip step 3 and 5 -- just activate the app.

Wire the workspace-routing branch in `NotificationHandler.userNotificationCenter(_:didReceive:withCompletionHandler:)` to call `appState.navigateToPane(paneID:projectID:)`.

**Patterns to follow:**
- `AppState.restoreFocusToActivePane()` at `AppState.swift:339-349`
- `AppState.closePane` tab-finding pattern at `AppState.swift:264-266`
- `AppDelegate.reopenIfNeeded()` at `MactermApp.swift:198-219` (hidden window recovery)
- `FocusRestoration.restoreFocus(to:in:window:)` usage

**Test scenarios:**
- Happy path: navigateToPane switches project, selects correct tab, focuses pane
- Edge case: pane in a different project than currently active -- full switch occurs
- Edge case: pane is in the currently active tab -- only focus changes
- Error path: pane ID doesn't exist in any tab -- activates app but doesn't crash
- Edge case: main window is hidden (ordered-out) -- reopenIfNeeded brings it forward
- Integration: NotificationHandler click handler routes to navigateToPane correctly

**Verification:**
- Calling navigateToPane with a pane in a different project/tab activates that project in sidebar and makes the pane focused
- Clicking a notification from a workspace pane navigates to it

---

- [ ] **Unit 4: Wire GHOSTTY_ACTION_DESKTOP_NOTIFICATION to notification posting**

**Goal:** Extract title/body from the libghostty callback, evaluate focus state, and post a UNNotification when appropriate.

**Requirements:** R1, R2, R4

**Dependencies:** Unit 1 (Pane.projectID), Unit 2 (NotificationHandler)

**Files:**
- Modify: `Macterm/Ghostty/GhosttyCallbacks.swift`
- Modify: `Macterm/Views/Terminal/GhosttyTerminalNSView.swift`
- Modify: `Macterm/Views/TerminalPane.swift`
- Modify: `Macterm/Model/SplitNode.swift` (destroySurface nil-out)

**Approach:**
1. Add `onDesktopNotification: ((String, String) -> Void)?` to `GhosttyTerminalNSView`
2. In `GhosttyCallbacks.action`, replace the `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` stub with extraction code following the `SET_TITLE` pattern: extract title/body C strings, dispatch to main, call `view.onDesktopNotification?(title, body)`
3. In `TerminalSurface.configure(_:)`, wire `onDesktopNotification` with a `[weak pane]` closure that:
   - Checks `NSApp.isActive` and `view.isFocused` on the main thread (inside the dispatched block)
   - If app is active AND pane is focused, skip (R2)
   - Otherwise, create `UNMutableNotificationContent` with title, body, and `userInfo` containing `paneID`, `projectID`, `isQuickTerminal`
   - Create `UNNotificationRequest` with a unique identifier (e.g., `"macterm-\(paneID.uuidString)-\(timestamp)")` and deliver via `UNUserNotificationCenter.current().add(_)`
4. In `Pane.destroySurface()`, add `view.onDesktopNotification = nil` alongside the existing callback nil-outs

**Patterns to follow:**
- `GHOSTTY_ACTION_SET_TITLE` extraction at `GhosttyCallbacks.swift:12-16`
- `[weak pane]` closure wiring at `TerminalPane.swift:117`
- Callback nil-out at `SplitNode.swift:39-46`

**Test scenarios:**
- Happy path: DESKTOP_NOTIFICATION callback posts a UNNotification when app is in background
- Happy path: notification userInfo contains correct paneID, projectID, isQuickTerminal
- Edge case: app is foreground and pane is focused -- no notification posted
- Edge case: app is foreground but pane is not focused -- notification IS posted
- Edge case: title or body is nil/empty -- graceful handling (post with empty string)
- Integration: callback extraction + main-queue dispatch + notification center delivery

**Verification:**
- Terminal command `printf '\033]9;Title\007'` produces a macOS notification when app is backgrounded
- No notification appears when the source terminal is the focused pane in the foreground app

---

- [ ] **Unit 5: Quick Terminal notification click routing**

**Goal:** Notifications from Quick Terminal panes show and focus the Quick Terminal on click.

**Requirements:** R7

**Dependencies:** Unit 2 (NotificationHandler), Unit 4 (notification posting with `isQuickTerminal` flag)

**Files:**
- Modify: `Macterm/App/NotificationHandler.swift`
- Modify: `Macterm/Views/QuickTerminal.swift`

**Approach:**
1. Add `showPanel()` method to `QuickTerminalService`: calls `show()` when the panel is not visible, or calls `makeKeyAndOrderFront` + `focusPane` when already visible. Unlike `toggle()`, this never hides the panel.
2. In `NotificationHandler.userNotificationCenter(_:didReceive:withCompletionHandler:)`, wire the `isQuickTerminal` branch:
   - Call `QuickTerminalService.shared.showPanel()`
   - Focus the pane within `QuickTerminalService.shared.splitState`
3. Guard against closed pane: check if the pane ID still exists in the split state before focusing

**Patterns to follow:**
- `QuickTerminalService.shared` singleton at `QuickTerminal.swift:7`
- `QuickTerminalSplitState.focusPane` at `QuickTerminal.swift:290-292`
- `QuickTerminalService.show()` at `QuickTerminal.swift:190` (private, `showPanel()` wraps it)

**Test scenarios:**
- Happy path: clicking quick terminal notification shows the panel and focuses the source pane
- Edge case: quick terminal is already visible -- shows panel, focuses pane, does NOT hide
- Edge case: pane in quick terminal was closed between notification post and click -- no crash

**Verification:**
- Clicking a notification from a Quick Terminal pane brings the Quick Terminal to front with the correct pane focused
- If the Quick Terminal is already visible, clicking its notification focuses the pane without hiding

## System-Wide Impact

- **Interaction graph:** `GhosttyCallbacks.action` -> `GhosttyTerminalNSView.onDesktopNotification` -> `UNUserNotificationCenter` -> macOS Notification Center -> user click -> `NotificationHandler` -> `AppState.navigateToPane` or `QuickTerminalService.showPanel()`
- **Error propagation:** Authorization denied is non-fatal (notifications silently not delivered). Notification posting failure is non-fatal (log and continue).
- **State lifecycle risks:** Pane may be closed between notification post and click. Mitigated by checking pane existence in navigateToPane and the quick terminal click handler.
- **API surface parity:** This is a new feature with no existing parallel in the app, so no parity concerns.
- **Unchanged invariants:** `Pane` identity and ownership model unchanged. `GhosttyTerminalNSView` ownership by `Pane` unchanged. `destroySurface` pattern extended but not altered.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| GhosttyKit C struct field names may differ from expected `desktop_notification.title/.body` | Compile-time verification catches this. The naming follows the convention of all other actions. |
| Notification authorization denied by user | Non-fatal. Notifications silently not delivered. No special handling needed. |
| Focus modes suppress notifications | macOS behavior, not something Macterm should override. Document as known limitation. |
| Main window is ordered-out (hidden) on notification click | `navigateToPane` calls `reopenIfNeeded()` which handles this exact case. |
| Pane created without projectID in test code | Provide a default UUID or update test helpers. All production paths have projectID available. |

## Sources & References

- **Origin document:** [docs/brainstorms/desktop-notifications-requirements.md](docs/brainstorms/desktop-notifications-requirements.md)
- Related code: `Macterm/Ghostty/GhosttyCallbacks.swift`, `Macterm/App/AppState.swift`, `Macterm/Model/SplitNode.swift`, `Macterm/App/MactermApp.swift`
- AppKit UNUserNotificationCenter API (macOS 10.14+, Macterm targets macOS 26)