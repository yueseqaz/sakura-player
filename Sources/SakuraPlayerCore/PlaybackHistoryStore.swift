import Foundation

public struct PlaybackHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public var lastPosition: TimeInterval
    public var lastPlayedAt: Date

    public init(url: URL, lastPosition: TimeInterval = 0, lastPlayedAt: Date = .now) {
        self.url = url
        self.lastPosition = lastPosition
        self.lastPlayedAt = lastPlayedAt
    }
}

public actor PlaybackHistoryStore {
    private let fileURL: URL
    private var entries: [String: PlaybackHistoryEntry] = [:]
    private var loaded = false

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    public func entry(for url: URL) async -> PlaybackHistoryEntry? {
        await loadIfNeeded()
        pruneMissingFiles()
        return entries[url.path]
    }

    public func allEntries() async -> [PlaybackHistoryEntry] {
        await loadIfNeeded()
        pruneMissingFiles()
        return entries.values.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    public func record(url: URL, position: TimeInterval) async {
        await loadIfNeeded()
        entries[url.path] = PlaybackHistoryEntry(url: url, lastPosition: max(0, position))
        persist()
    }

    public func removeAll() async {
        entries.removeAll()
        persist()
    }

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PlaybackHistoryEntry].self, from: data) else { return }
        entries = Dictionary(uniqueKeysWithValues: decoded.map { ($0.url.path, $0) })
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(entries.values))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // History is best effort and must never interrupt playback.
        }
    }

    private func pruneMissingFiles() {
        let before = entries.count
        entries = entries.filter { FileManager.default.isReadableFile(atPath: $0.value.url.path) }
        if entries.count != before { persist() }
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SakuraPlayer", isDirectory: true).appendingPathComponent("history.json")
    }
}
