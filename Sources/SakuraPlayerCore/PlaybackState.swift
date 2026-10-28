import Foundation

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
