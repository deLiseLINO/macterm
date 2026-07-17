import Foundation
import os

private let closedTabLogger = Logger(subsystem: appBundleID, category: "ClosedTabStore")

struct ClosedTabEntry: Codable {
    let projectID: UUID
    let closedAt: Date
    let tab: TabSnapshot
}

struct ClosedTabsFile: Codable {
    let version: Int
    let entries: [ClosedTabEntry]
}

final class ClosedTabStore {
    static let capacity = 10
    static let expiration: TimeInterval = 10 * 60

    private let fileURL: URL
    private let now: () -> Date
    private(set) var entries: [ClosedTabEntry] = []
    private(set) var loadFailed = false

    init(fileURL: URL = FileStorage.fileURL(filename: "closed_tabs_v1.json"), now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
        load()
    }

    var isEmpty: Bool {
        validEntries().isEmpty
    }

    var count: Int {
        all().count
    }

    func all() -> [ClosedTabEntry] {
        pruneExpired()
        return entries
    }

    @discardableResult
    func record(_ entry: ClosedTabEntry) -> Bool {
        guard !loadFailed else { return false }
        let candidate = ([entry] + validEntries()).prefix(Self.capacity)
        let values = Array(candidate)
        guard persist(values) else { return false }
        entries = values
        return true
    }

    func consumeLatest() -> ClosedTabEntry? {
        guard !loadFailed else { return nil }
        pruneExpired()
        guard let entry = entries.first else { return nil }
        let remaining = Array(entries.dropFirst())
        guard persist(remaining) else { return nil }
        entries = remaining
        return entry
    }

    private func validEntries() -> [ClosedTabEntry] {
        let cutoff = now().addingTimeInterval(-Self.expiration)
        return entries.filter { $0.closedAt > cutoff }
    }

    private func pruneExpired() {
        guard !loadFailed else { return }
        let valid = validEntries()
        guard valid.count != entries.count else { return }
        if persist(valid) {
            entries = valid
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return }
            let decoded = try JSONDecoder().decode(ClosedTabsFile.self, from: data)
            guard decoded.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            entries = Array(decoded.entries.prefix(Self.capacity))
            pruneExpired()
        } catch {
            loadFailed = true
            closedTabLogger.error("Failed to decode closed tabs: \(error, privacy: .public)")
        }
    }

    private func persist(_ values: [ClosedTabEntry]) -> Bool {
        do {
            let file = ClosedTabsFile(version: 1, entries: values)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: fileURL, options: .atomic)
            return true
        } catch {
            closedTabLogger.error("Failed to save closed tabs: \(error, privacy: .public)")
            return false
        }
    }
}
