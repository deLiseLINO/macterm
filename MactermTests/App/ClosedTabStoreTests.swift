import Foundation
import Testing
@testable import Macterm

struct ClosedTabStoreTests {
    private func fileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("macterm-closed-tabs-\(UUID().uuidString).json")
    }

    private func entry(
        _ id: UUID = UUID(),
        projectID: UUID = UUID(),
        closedAt: Date,
        root: SplitNodeSnapshot? = nil
    ) -> ClosedTabEntry {
        let pane = PaneSnapshot(
            id: UUID(),
            projectPath: "/tmp/project",
            sessionID: UUID(),
            sessionName: "macterm-project-abc",
            workingDirectory: "/tmp/project/src"
        )
        return ClosedTabEntry(
            projectID: projectID,
            closedAt: closedAt,
            tab: TabSnapshot(
                id: id,
                customTitle: "Tab",
                focusedPaneID: pane.id,
                splitRoot: root ?? .pane(pane)
            )
        )
    }

    @Test
    func newestEntriesComeFirstAndHistoryIsBounded() {
        let now = Date(timeIntervalSince1970: 1000)
        let store = ClosedTabStore(fileURL: fileURL(), expiration: 600, now: { now })
        let entries = (0 ..< 12).map { index in
            entry(closedAt: now.addingTimeInterval(TimeInterval(index)))
        }

        for value in entries { #expect(store.record(value)) }

        #expect(store.count == ClosedTabStore.capacity)
        #expect(store.all().map(\.tab.id) == entries.reversed().prefix(ClosedTabStore.capacity).map(\.tab.id))
    }

    @Test
    func entriesExpireAtConfiguredTTLAndPruneOnRead() {
        let now = Date(timeIntervalSince1970: 1000)
        let store = ClosedTabStore(fileURL: fileURL(), expiration: 600, now: { now })
        let expired = entry(closedAt: now.addingTimeInterval(-601))
        let valid = entry(closedAt: now.addingTimeInterval(-599))
        #expect(store.record(expired))
        #expect(store.record(valid))

        #expect(store.all().map(\.tab.id) == [valid.tab.id])
        #expect(store.count == 1)
    }

    @Test
        let store = ClosedTabStore(fileURL: fileURL(), expiration: 600, now: { now })
        let first = entry(closedAt: now)
        let second = entry(closedAt: now)
        #expect(store.record(first))
        #expect(store.record(second))

        #expect(store.consumeLatest()?.tab.id == second.tab.id)
        #expect(store.consumeLatest()?.tab.id == first.tab.id)
        #expect(store.consumeLatest() == nil)
    }

    @Test
    func snapshotRoundTripPreservesLayoutFocusAndPaneIdentity() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let url = fileURL()
        let store = ClosedTabStore(fileURL: url, expiration: 600, now: { now })
        let firstID = UUID()
        let secondID = UUID()
        let first = PaneSnapshot(
            id: firstID,
            projectPath: "/tmp/project",
            sessionID: UUID(),
            sessionName: "macterm-project-first",
            workingDirectory: "/tmp/project/one"
        )
        let second = PaneSnapshot(
            id: secondID,
            projectPath: "remote.example:/srv/project",
            sessionID: UUID(),
            sessionName: "macterm-project-second",
            workingDirectory: nil
        )
        let root = SplitNodeSnapshot.split(SplitBranchSnapshot(
            direction: .horizontal,
            ratio: 0.37,
            first: .pane(first),
            second: .pane(second)
        ))
        let original = entry(closedAt: now, root: root)
        #expect(store.record(original))

        let restored = try #require(ClosedTabStore(fileURL: url, expiration: 600, now: { now }).all().first)
        #expect(restored.tab.focusedPaneID == firstID)
        guard case let .split(branch) = restored.tab.splitRoot else {
            Issue.record("Expected split snapshot")
            return
        }
        #expect(branch.ratio == 0.37)
        guard case let .pane(restoredFirst) = branch.first,
              case let .pane(restoredSecond) = branch.second
        else {
            Issue.record("Expected pane snapshots")
            return
        }
        #expect(restoredFirst.sessionName == "macterm-project-first")
        #expect(restoredFirst.workingDirectory == "/tmp/project/one")
        #expect(restoredSecond.projectPath == "remote.example:/srv/project")
        #expect(restoredSecond.workingDirectory == nil)
    }

    @Test
    func corruptHistoryIsPreservedAndCannotBeOverwritten() throws {
        let url = fileURL()
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: url)
        let store = ClosedTabStore(fileURL: url, expiration: 600, now: Date.init)

        #expect(store.loadFailed)
        #expect(store.all().isEmpty)
        #expect(!store.record(entry(closedAt: Date())))
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test
    func zeroTTLMeansEveryEntryExpiresImmediately() {
        let now = Date(timeIntervalSince1970: 1000)
        let store = ClosedTabStore(fileURL: fileURL(), expiration: 0, now: { now })
        #expect(store.record(entry(closedAt: now)))
        // Even at `closedAt = now`, anything strictly older than `now` is expired.
        #expect(store.isEmpty)
    }

    @Test
    func pruneExpiredReturnsSessionNamesOfDroppedEntries() {
        let now = Date(timeIntervalSince1970: 1000)
        let store = ClosedTabStore(fileURL: fileURL(), expiration: 10, now: { now })
        let paneName = "macterm-foo-1"
        let pane = PaneSnapshot(
            id: UUID(),
            projectPath: "/tmp/foo",
            sessionID: UUID(),
            sessionName: paneName
        )
        let expiredEntry = ClosedTabEntry(
            projectID: UUID(),
            closedAt: now.addingTimeInterval(-20),
            tab: TabSnapshot(id: UUID(), customTitle: nil, focusedPaneID: pane.id, splitRoot: .pane(pane))
        )
        #expect(store.record(expiredEntry))

        let dropped = store.pruneExpired()
        #expect(dropped == [paneName])
        #expect(store.isEmpty)
    }

    @Test
    func pruneExpiredReturnsEmptySetWhenNothingDropped() {
        let now = Date(timeIntervalSince1970: 1000)
        let store = ClosedTabStore(fileURL: fileURL(), expiration: 600, now: { now })
        #expect(store.record(entry(closedAt: now)))
        #expect(store.pruneExpired().isEmpty)
    }
