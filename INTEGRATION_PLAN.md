# Integration Plan / Status Report: Macterm Tracks A–F

## Objective

Finish the parallel-track Macterm integration (Tracks A–F), push a working integration branch to the fork, wire up CI/CD so a ready-to-run macOS binary exists, and verify that the CI-built app opens side-by-side with the installed release app.

## Deliverables and Evidence

| # | Deliverable | Evidence | Status |
|---|---|---|---|
| 1 | Tracks A–F merged into one integration branch | `macterm-features-integration` exists on `deLiseLINO/macterm` | ✅ |
| 2 | CI workflow builds on `macos-26` and produces installable artifacts | GitHub Actions run `29572031513` (success) | ✅ |
| 3 | CI binary installs beside `/Applications/Macterm.app` | `/Applications/Macterm CI.app` present and running | ✅ |
| 4 | CI binary has unique bundle ID / feed URL to avoid update conflicts | `CFBundleIdentifier=com.thdxg.macterm.ci`, `SUFeedURL=https://deLiseLINO.github.io/macterm-ci/appcast.xml` | ✅ |
| 5 | App launches and stays alive | PID 38009 running for >5 s after `open -F -n` | ✅ |
| 6 | Reviewer findings addressed | Notification routing fixed; Sparkle feed isolated; Swift warnings reduced | ✅ |

## Build artifacts

- CI run: `https://github.com/deLiseLINO/macterm/actions/runs/29572031513`
- Artifact `macterm-app-ci` downloaded to `/tmp/macterm-ci-final/Macterm CI.app` and installed to `/Applications/Macterm CI.app`.

## Final verification output

```text
CFBundleDisplayName => "Macterm CI"
CFBundleIdentifier  => "com.thdxg.macterm.ci"
CFBundleName        => "Macterm CI"
SUFeedURL           => "https://deLiseLINO.github.io/macterm-ci/appcast.xml"
SUPublicEDKey       => "nBuEDgHJ7fQALamTpsBWPhLFvTKlIJVAQUtQZQVNe88="
Architecture        => Mach-O universal binary (x86_64 + arm64)
Process alive after 5 s => /Applications/Macterm CI.app/Contents/MacOS/Macterm
```

## Key changes since base integration

1. `4ac45cd fix(build): disable liquid glass + convert exitCode for current SDK`
2. `9e2cd16 fix(notifications): use selector observer for Swift 6 isolation`
3. `8336bff ci: preserve .app wrapper in app artifact`
4. `73c033a fix(ci): build side-by-side test app with unique bundle ID`
5. `44804e3 fix(notifications): restore handleCommandCompletion after botched edit`
6. `120503f fixup! ci: correct PlistBuddy quoting for side-by-side app`
7. `a1f9173 fix(notifications): dispatch authorization completion on main queue`
8. `72c4975 fix(notifications): align TerminalPane userInfo with command-completion routing`
9. `6b56cf8 ci: point side-by-side CI app to a distinct Sparkle feed URL`
10. `fd1a69e fix: restore nonisolated(unsafe) for deinit token cleanup`

## Remaining items (non-blocking)

- `nonisolated(unsafe)` on `observerTokens` still produces a compiler warning; replacing it properly requires a Sendable redesign of the token array and is not needed for the build to succeed.
- The CI reviewer flagged Sparkle XPC re-signing, dummy EdDSA key usability, and missing DMG for the CI app. These do not prevent the current installable binary from launching side-by-side with the release app. If you want a fully notarized/Sparkle-tested CI build, we will need Apple Developer ID credentials and a hosted CI appcast.

## Next step options

1. Merge `macterm-features-integration` into fork `main`.
2. Open an upstream PR against `thdxg/macterm`.
3. Address the remaining reviewer polish items (Sendable annotations, DMG for CI, real Sparkle key).

## Branch refs

- Integration branch: `macterm-features-integration`
- Current HEAD: `fd1a69e`
- Fork: `https://github.com/deLiseLINO/macterm.git`
- Local worktree: `/tmp/macterm-work`
