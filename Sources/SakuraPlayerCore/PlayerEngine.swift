import Combine
import Foundation

@MainActor
public protocol PlayerEngine: AnyObject {
    var state: PlaybackState { get }
    var statePublisher: AnyPublisher<PlaybackState, Never> { get }
    /// Whether the selected playback adapter can shift presentation audio.
    var supportsAudioDelay: Bool { get }
    func load(url: URL) async throws
    func close()
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func setVolume(_ volume: Float)
    func setMuted(_ muted: Bool)
    func setRate(_ rate: Float)
    /// Throws `unsupportedFeature` when an adapter cannot shift audio presentation.
    func setAudioDelay(_ delay: TimeInterval) throws
    func selectAudioTrack(id: Int?)
    func selectSubtitleTrack(id: Int?)
}

public enum PlayerEngineError: LocalizedError, Equatable {
    case unsupportedURL
    case unsupportedFeature(String)
    case failedToLoad(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "The selected file cannot be opened."
        case let .unsupportedFeature(message):
            return message
        case let .failedToLoad(message):
            return "Unable to play this media: \(message)"
        }
    }
}
