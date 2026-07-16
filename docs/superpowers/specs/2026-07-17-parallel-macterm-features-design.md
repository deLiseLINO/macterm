# Parallel Macterm Features Design

## Goal

Implement six independent improvements in parallel while preserving Macterm's existing workspace persistence, zmx session lifecycle, SwiftUI/AppKit window model, and macOS CI checks:

1. Cyrillic-layout shortcut handling.
2. Configurable main-window size.
3. Command-completion notifications with pane focus.
4. Native agent-session resume metadata.
5. Reopen recently closed tabs.
6. macOS release artifacts in CI.

Each feature is developed in its own worktree and reviewed independently. Shared persistence and event contracts are defined before implementation.

## Current architecture constraints

- `WorkspaceStore` serializes `WorkspaceSnapshot` values to `workspaces_v3.json`.
- `PaneSnapshot` already persists `sessionID`, `sessionName`, `workingDirectory`, and `needsAttention`.
- `ZmxClient` is authoritative for attach-vs-create; `zmx attach` upserts a session and therefore naturally handles a dead session by creating a new shell.
- `AppState.restoreSelection` restores snapshots and then reaps unclaimed local Macterm zmx sessions.
- `HotkeyRegistry.eventToken` already has a key-code fallback for non-ASCII or shifted symbols. The Cyrillic track must verify and cover this path rather than introduce duplicate per-layout bindings.
- `NotificationHandler` already requests macOS notification permission and focuses a pane from notification metadata. The notification track extends the existing path with command-completion events; it must not replace the handler.
- Main-window size currently comes from `MactermApp.defaultSize(width: 1200, height: 800)`. Quick Terminal has separate fractional-size Preferences and is out of scope for main-window sizing.
- Closing a tab is destructive: its panes and zmx sessions are killed after confirmation. Reopening must therefore restore layout and use zmx reattach only when the session still exists.

## Shared contracts

### Persistence

Keep `WorkspaceSnapshot` as the durable launch state. Add only optional Codable fields where possible so old snapshots remain readable. Do not persist credentials, tokens, arbitrary shell text, or transient process state.

Agent metadata is a separate optional value on `PaneSnapshot`, with a versioned, typed shape:

- provider/agent kind;
- native session identifier;
- working directory;
- sanitized resume invocation descriptor.

The descriptor is not an opaque command assembled from untrusted text. It contains an allow-listed executable/argument representation produced by a provider integration. Unknown or invalid metadata is ignored and restores a normal shell.

Recently closed tabs are not part of the normal workspace array. Store them in a separate bounded, expiring collection so closing/reopening a tab cannot corrupt the active workspace snapshot. The entry contains the original project ID, tab identity/title/focus, split tree, pane working directories, and zmx identities. It is an undo history, not a second active workspace.

### Events

Extend `Notifications.swift` with a typed command-completion notification carrying only Sendable identifiers and display data:

- project ID;
- tab ID;
- pane ID;
- command/session label;
- completion outcome.

`AppState` or the execution tracker publishes the event exactly on a running-to-done transition. `NotificationHandler` converts it to a macOS notification and preserves existing click-to-focus behavior. Existing polling wake events remain separate from user-facing notifications.

## Feature tracks

### A. Cyrillic shortcuts

Use the hardware `keyCode` only as a fallback when `charactersIgnoringModifiers` is non-ASCII or cannot produce a canonical token. Preserve logical-character matching for layouts such as Colemak/AZERTY where it is meaningful. Add focused tests for Cmd+V, Ctrl+C, Cmd+T, Cmd+W, and split shortcuts under a Cyrillic event representation, plus regression coverage for shifted symbols, arrows, and normal Latin input.

No per-layout aliases, duplicate bindings, or Ghostty config workarounds.

### B. Main-window size

Add persisted `mainWindowWidth` and `mainWindowHeight` to `Preferences` with explicit minimum/maximum bounds and defaults matching the current `1200x800` behavior. Replace the hard-coded SwiftUI default with the preferences-backed values at app launch. Expose both fields in the existing Settings UI. Changes apply on next launch; resizing and macOS's saved window frame remain authoritative after a window has been created.

Quick Terminal's width/height fractions remain unchanged.

### C. Completion notifications

Reuse the existing `NotificationHandler` and `FocusRestoration`. Add a completion event at the execution-state transition boundary, not in a periodic poll and not in zmx attach code. Avoid duplicate notifications by tracking the transition or using the existing execution-state edge semantics. Respect notification authorization and the user's notification setting. A notification click activates Macterm, selects the project/tab, and focuses the pane; stale IDs are ignored safely.

### D. Agent resume

Introduce a provider-neutral protocol for capturing and validating native agent session metadata. Providers supply a native session ID and an allow-listed resume invocation; the generic shell path remains unchanged when no provider is present. Persist metadata with `PaneSnapshot`, restore it after the pane/zmx session is rebuilt, and launch the resume invocation only when the provider confirms the ID is usable. Never persist credentials or full environment values. A failed resume falls back to the normal shell and leaves the pane usable.

The first implementation must support the existing `pi`/`omp` workflow through an explicit provider adapter; adding unsupported agents must not require unsafe generic command execution.

### E. Recently closed tabs

Add a `RecencyStack`-style bounded tab snapshot store in `AppState`/persistence. Capture the tab snapshot before confirmed destructive close, including split ratios, focus, working directories, session IDs/names, and project ID. Add `Reopen Closed Tab` to `AppCommand` and the command/menu surfaces, with the standard `Cmd+Shift+T` default.

On reopen, restore the saved tree and call the existing zmx attach path. If a session was killed or the machine rebooted, zmx creates a fresh shell in the saved local working directory. Remote working directories remain remote metadata and must not be treated as local paths. Expire entries after a bounded timeout and cap history size.

### F. macOS CI artifacts

Add a separate manually invokable or release/dispatch workflow on a macOS runner. Reuse the repository's existing `mise` setup, Xcode project generation, and build script. Produce the release `.app` and compressed `.dmg`, then upload both as workflow artifacts. Keep normal PR checks focused on format, lint, and tests. Fail the artifact job if export/signature/package verification fails; do not publish a release automatically from a feature PR.

## Worktree ownership

- Track A: `Macterm/App/Hotkeys.swift`, responder/key-router tests.
- Track B: `Macterm/App/Preferences.swift`, `Macterm/App/MactermApp.swift`, relevant Settings view/tests.
- Track C: `Macterm/App/Notifications.swift`, `NotificationHandler.swift`, execution transition integration/tests.
- Track D: new provider/resume types plus `PaneSnapshot` and restore integration; no unrelated AppState refactor.
- Track E: `AppCommand.swift`, command actions/menu, `AppState.swift`, tab snapshot persistence and focused tests.
- Track F: `.github/workflows/`, build/export scripts, and only the minimum project configuration needed for artifacts.

Shared-file edits must be limited to the contract additions agreed during integration. No track changes the zmx authority model or the existing corruption-safe persistence behavior.

## Error handling and compatibility

- Missing optional fields decode as absent and preserve existing behavior.
- Corrupt or newer workspace files remain protected by the existing no-overwrite guard.
- Invalid agent metadata, stale closed-tab IDs, dead zmx sessions, missing remote hosts, and denied notification permission degrade without crashing or blocking launch.
- New settings use current values as defaults and do not affect Quick Terminal.
- Existing hotkeys and notification clicks remain backward-compatible.

## Verification

Each track must provide focused behavioral tests or a deterministic smoke scenario for its observable contract. Integration must then verify:

1. launch restores current workspaces and zmx sessions;
2. old snapshots decode and save safely;
3. Cyrillic shortcuts route to the same commands as Latin shortcuts;
4. window-size Preferences survive relaunch;
5. completion notifications are emitted once and focus the correct pane;
6. invalid agent resume metadata falls back to a shell;
7. closed tabs reopen with layout and best-effort zmx reattachment;
8. macOS CI produces valid `.app` and `.dmg` artifacts.

No push or upstream PR is part of this design approval. Those are delivery decisions after implementation and verification.
