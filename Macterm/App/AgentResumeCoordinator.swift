import Foundation
import os

private let agentResumeLogger = Logger(subsystem: appBundleID, category: "AgentResumeCoordinator")

@MainActor
final class AgentResumeCoordinator {
    typealias SendText = (Pane, String) -> Bool

    private let zmx: ZmxClient
    private let sendText: SendText
    private var didDecide = false
    private var didCapturePreRestoreListing = false
    private var capturedPreRestoreLiveSessionNames: Set<String>?


    init(zmx: ZmxClient = .live, sendText: SendText? = nil) {
        self.zmx = zmx
        self.sendText = sendText ?? { pane, text in
            guard let view = pane.nsView else { return false }
            return view.sendText(text)
        }
    }
    func capturePreRestoreLiveSessionNames() async -> Set<String>? {
        guard !didCapturePreRestoreListing else {
            return capturedPreRestoreLiveSessionNames
        }
        didCapturePreRestoreListing = true
        let names = await zmx.liveSessionNames()
        capturedPreRestoreLiveSessionNames = names
        if names == nil {
            agentResumeLogger.info("Skipping agent resume: pre-restore zmx session listing unavailable")
        }
        return names
    }

    /// Make the one-shot post-attach resume decision. A pane is resumed only
    /// when its saved zmx session was absent from the successful pre-restore
    /// listing. The decision is consumed even when no pane can be resumed, so
    /// a later lifecycle notification can never duplicate a command.
    func resumeRestoredAgents(
        _ panes: [Pane],
        preRestoreLiveSessionNames: Set<String>?
    ) {
        guard !didDecide else {
            agentResumeLogger.debug("Skipping agent resume: decision already made")
            return
        }
        didDecide = true

        guard let preRestoreLiveSessionNames else {
            agentResumeLogger.info("Skipping agent resume: pre-restore zmx state is unknown")
            return
        }

        for pane in panes {
            guard !preRestoreLiveSessionNames.contains(pane.sessionName) else {
                continue
            }
            guard let metadata = pane.agentSession else { continue }
            guard let line = AgentResumeCommand.shellLine(for: metadata) else {
                agentResumeLogger.info("Skipping agent resume: pane metadata has no usable session ID")
                continue
            }
            guard sendText(pane, line + "\n") else {
                agentResumeLogger.info("Skipping agent resume: pane surface rejected provider command")
                continue
            }
        }
    }
}
