import Foundation

public enum PlaybackOrder: String, Codable, CaseIterable, Hashable, Sendable {
    case sequential
    case singleLoop
    case queueLoop
    case shuffle
}

public struct QueueItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public var duration: TimeInterval?

    public init(id: UUID = UUID(), url: URL, duration: TimeInterval? = nil) {
        self.id = id
        self.url = url
        self.duration = duration
    }
}

/// A small in-memory queue. It deliberately owns ordering decisions so the UI
/// can remain a projection of queue state rather than reimplementing playback rules.
public struct PlaybackQueue: Equatable, Sendable {
    public private(set) var items: [QueueItem] = []
    public private(set) var currentIndex: Int?
    public var order: PlaybackOrder = .sequential

    public init(items: [QueueItem] = [], order: PlaybackOrder = .sequential) {
        self.items = items
        self.order = order
        currentIndex = items.isEmpty ? nil : 0
    }

    public var current: QueueItem? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    public mutating func replace(with urls: [URL]) {
        items = urls.map { QueueItem(url: $0) }
        currentIndex = items.isEmpty ? nil : 0
    }

    public mutating func append(urls: [URL]) {
        items.append(contentsOf: urls.map { QueueItem(url: $0) })
        if currentIndex == nil, !items.isEmpty { currentIndex = 0 }
    }

    public mutating func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        guard !items.isEmpty else { currentIndex = nil; return }
        if let currentIndex {
            if index < currentIndex { self.currentIndex = currentIndex - 1 }
            else if index == currentIndex { self.currentIndex = min(currentIndex, items.count - 1) }
        }
    }

    public mutating func clear() {
        items.removeAll()
        currentIndex = nil
    }

    public mutating func select(index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
    }

    public mutating func updateDuration(at index: Int, duration: TimeInterval?) {
        guard items.indices.contains(index) else { return }
        guard let duration, duration.isFinite else {
            items[index].duration = nil
            return
        }
        items[index].duration = max(0, duration)
    }

    public mutating func advance() -> QueueItem? {
        guard let currentIndex, !items.isEmpty else { return nil }
        switch order {
        case .singleLoop:
            return items[currentIndex]
        case .shuffle:
            guard items.count > 1 else { return items[currentIndex] }
            var next = Int.random(in: 0..<items.count)
            while next == currentIndex { next = Int.random(in: 0..<items.count) }
            self.currentIndex = next
            return items[next]
        case .sequential:
            guard currentIndex + 1 < items.count else { return nil }
            self.currentIndex = currentIndex + 1
            return items[currentIndex + 1]
        case .queueLoop:
            let next = (currentIndex + 1) % items.count
            self.currentIndex = next
            return items[next]
        }
    }

    public mutating func previous() -> QueueItem? {
        guard let currentIndex, !items.isEmpty else { return nil }
        let previous = currentIndex > 0 ? currentIndex - 1 : (order == .queueLoop ? items.count - 1 : 0)
        self.currentIndex = previous
        return items[previous]
    }
}
