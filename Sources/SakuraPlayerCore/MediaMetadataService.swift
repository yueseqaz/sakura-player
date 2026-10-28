import AVFoundation
import Foundation

public struct MediaMetadata: Equatable, Sendable {
    public let duration: TimeInterval
    public let naturalSize: CGSize

    public init(duration: TimeInterval, naturalSize: CGSize) {
        self.duration = duration
        self.naturalSize = naturalSize
    }
}

public enum MediaMetadataService {
    public static func metadata(for url: URL) async throws -> MediaMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let size: CGSize
        if let track = tracks.first {
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = natural.applying(transform)
            size = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        } else {
            size = .zero
        }
        return MediaMetadata(duration: duration.seconds.isFinite ? duration.seconds : 0, naturalSize: size)
    }
}
