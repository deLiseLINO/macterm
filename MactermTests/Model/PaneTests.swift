import Foundation
@testable import Macterm
import Testing

@MainActor
struct PaneTests {
    private func shellName() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return (shell as NSString).lastPathComponent
    }

    @Test
    func processTitle_defaults_to_shell_name_when_title_blank() {
        let p = Pane(projectPath: "/", projectID: UUID())
        p.title = ""
        #expect(p.processTitle == shellName())
    }

    @Test
    func processTitle_defaults_to_shell_name_when_title_whitespace() {
        let p = Pane(projectPath: "/", projectID: UUID())
        p.title = "   \t\n"
        #expect(p.processTitle == shellName())
    }

    @Test
    func processTitle_picks_first_non_path_token() {
        let p = Pane(projectPath: "/", projectID: UUID())
        p.title = "/Users/me vim file.swift"
        #expect(p.processTitle == "vim")
    }

    @Test
    func processTitle_picks_first_meaningful_token() {
        let p = Pane(projectPath: "/", projectID: UUID())
        p.title = "git status"
        #expect(p.processTitle == "git")
    }

    @Test
    func processTitle_skips_noise_tokens() {
        let p = Pane(projectPath: "/", projectID: UUID())
        p.title = ">>> /Users/me node server.js"
        // ">>>", "/Users/me" are noise / path — should pick "node".
        #expect(p.processTitle == "node")
    }

    @Test
    func processTitle_falls_back_to_shell_when_all_paths() {
        let p = Pane(projectPath: "/", projectID: UUID())
        p.title = "/usr/bin ~/dev"
        #expect(p.processTitle == shellName())
    }

    @Test
    func processTitle_treats_tilde_prefix_as_path() {
        let p = Pane(projectPath: "/", projectID: UUID())
        p.title = "~/dev cmd"
        #expect(p.processTitle == "cmd")
    }

    @Test
    func sidebarSegmentTitle_matches_processTitle() {
        let p = Pane(projectPath: "/", projectID: UUID())
        p.title = "zsh"
        #expect(p.sidebarSegmentTitle == p.processTitle)
    }

    @Test
    func init_stores_project_path() {
        let p = Pane(projectPath: "/tmp/foo", projectID: UUID())
        #expect(p.projectPath == "/tmp/foo")
    }

    @Test
    func destroySurface_is_safe_when_nsView_is_nil() {
        let p = Pane(projectPath: "/", projectID: UUID())
        #expect(p.nsView == nil)
        p.destroySurface() // must not crash
        p.destroySurface() // idempotent
        #expect(p.nsView == nil)
    }
}
