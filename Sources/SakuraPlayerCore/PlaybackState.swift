import Foundation

/// Shared playback-rate limits used by the engine, preferences and controls.
public enum PlaybackRateScale {
    public static let minimum: Float = 0.1
    public static let maximum: Float = 32
    public static let defaultValue: Float = 1
    public static let ticks: [Float] = [0.1, 0.25, 0.5, 1, 1.5, 2, 4, 8, 16, 32]

    public static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return defaultValue }
        return min(max(value, minimum), maximum)
    }
}

public enum PlaybackStatus: String, Codable, Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case ended
    case failed
}

public struct AudioTrack: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let language: String?

    public init(id: Int, name: String, language: String? = nil) {
        self.id = id
        self.name = name
        self.language = language
    }
}

public struct SubtitleTrack: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let language: String?
    public let isExternal: Bool

    public init(id: Int, name: String, language: String? = nil, isExternal: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.isExternal = isExternal
    }
}

public struct PlaybackState: Equatable, Sendable {
    public var status: PlaybackStatus = .idle
    public var mediaURL: URL?
    public var currentTime: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var volume: Float = 1
    public var isMuted = false
    public var rate: Float = 1
    public var isBuffering = false
    public var errorMessage: String?
    public var audioTracks: [AudioTrack] = []
    public var subtitleTracks: [SubtitleTrack] = []
    public var selectedAudioTrackID: Int?
    public var selectedSubtitleTrackID: Int?

    public init() {}
}
