// Older SDKs lack Sendable annotations for AVMediaSelectionGroup; its use
// stays confined to this main-actor adapter.
@preconcurrency import AVFoundation
import Combine
import Foundation

@MainActor
public final class AVPlayerEngine: NSObject, PlayerEngine {
    public private(set) var state = PlaybackState() {
        didSet { stateSubject.send(state) }
    }

    public var statePublisher: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    public let player = AVPlayer()
    public let supportsAudioDelay = false

    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())
    private var itemObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var timeControlObservation: NSKeyValueObservation?
    private var audioSelectionGroup: AVMediaSelectionGroup?
    private var subtitleSelectionGroup: AVMediaSelectionGroup?
    private var loadGeneration = UUID()

    public override init() {
        super.init()
        timeControlObservation = player.observe(\AVPlayer.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .playing:
                    self.state.isBuffering = false
                    if self.player.currentItem != nil { self.state.status = .playing }
                case .waitingToPlayAtSpecifiedRate:
                    self.state.isBuffering = true
                case .paused:
                    self.state.isBuffering = false
                    if self.player.currentItem != nil, self.state.status != .ended, self.state.status != .loading {
                        self.state.status = .paused
                    }
                @unknown default:
                    break
                }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = max(0, time.seconds.isFinite ? time.seconds : 0)
            Task { @MainActor [weak self] in
                guard let self, abs(self.state.currentTime - seconds) >= 0.05 else { return }
                self.state.currentTime = seconds
                if let duration = self.player.currentItem?.duration.seconds, duration.isFinite {
                    self.state.duration = max(0, duration)
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let itemID = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            Task { @MainActor [weak self] in
                guard let self, let itemID, let currentItem = self.player.currentItem,
                      ObjectIdentifier(currentItem) == itemID else { return }
                self.state.status = .ended
            }
        }
    }

    deinit {}

    public func load(url: URL) async throws {
        let generation = UUID()
        loadGeneration = generation
        itemObservation?.invalidate()
        itemObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        audioSelectionGroup = nil
        subtitleSelectionGroup = nil
        state = PlaybackState()
        state.mediaURL = url

        guard url.isFileURL else {
            let error = PlayerEngineError.unsupportedURL
            markFailure(error)
            throw error
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            let error = PlayerEngineError.failedToLoad("The file is not readable or no longer exists.")
            markFailure(error)
            throw error
        }
        PlayerLogger.loading(url: url)

        state.status = .loading

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        itemObservation = item.observe(\AVPlayerItem.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    self.state.duration = item.duration.seconds.isFinite ? max(0, item.duration.seconds) : 0
                    self.state.status = .paused
                    self.state.errorMessage = nil
                case .failed:
                    self.state.status = .failed
                    let detail = item.error.map(Self.userFacingError)
                    self.state.errorMessage = detail.map { "Unable to play this media: \($0)" }
                        ?? "Unable to play this media. The file could not be decoded."
                default:
                    break
                }
            }
        }
        do {
            try await waitUntilReady(item, generation: generation)
        } catch {
            if loadGeneration == generation { markFailure(error) }
            throw error
        }
        guard loadGeneration == generation else {
            throw PlayerEngineError.failedToLoad("The media load was superseded.")
        }
        await updateTracks(for: item)
    }

    public func close() {
        loadGeneration = UUID()
        itemObservation?.invalidate()
        itemObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = PlaybackState()
    }

    public func play() {
        guard player.currentItem != nil else { return }
        player.playImmediately(atRate: state.rate)
        state.status = .playing
    }

    public func pause() {
        player.pause()
        guard player.currentItem != nil else { return }
        state.status = .paused
    }

    public func seek(to seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        let clamped = min(max(0, seconds), state.duration > 0 ? state.duration : seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor [weak self] in self?.state.currentTime = clamped }
        }
    }

    public func setVolume(_ volume: Float) {
        let clamped = min(max(0, volume), 1)
        player.volume = clamped
        state.volume = clamped
        if clamped > 0 { state.isMuted = false }
    }

    public func setMuted(_ muted: Bool) {
        player.isMuted = muted
        state.isMuted = muted
    }

    public func setRate(_ rate: Float) {
        let clamped = min(max(0.25, rate), 4)
        state.rate = clamped
        if state.status == .playing { player.rate = clamped }
    }

    public func setAudioDelay(_ delay: TimeInterval) throws {
        throw PlayerEngineError.unsupportedFeature("Audio delay is not available with the AVFoundation engine.")
    }

    public func selectAudioTrack(id: Int?) {
        if let item = player.currentItem, let group = audioSelectionGroup {
            let option = id.flatMap { index in group.options.indices.contains(index) ? group.options[index] : nil }
            item.select(option, in: group)
        }
        state.selectedAudioTrackID = id
    }

    public func selectSubtitleTrack(id: Int?) {
        if let item = player.currentItem, let group = subtitleSelectionGroup {
            let option = id.flatMap { index in group.options.indices.contains(index) ? group.options[index] : nil }
            item.select(option, in: group)
        }
        state.selectedSubtitleTrackID = id
    }

    private func updateTracks(for item: AVPlayerItem) async {
        audioSelectionGroup = try? await item.asset.loadMediaSelectionGroup(for: .audible)
        subtitleSelectionGroup = try? await item.asset.loadMediaSelectionGroup(for: .legible)

        if let group = audioSelectionGroup {
            state.audioTracks = group.options.enumerated().map { index, option in
                let name = option.displayName.isEmpty
                    ? (option.extendedLanguageTag ?? "Audio \(index + 1)")
                    : option.displayName
                return AudioTrack(id: index, name: name, language: option.extendedLanguageTag)
            }
            if let selected = item.currentMediaSelection.selectedMediaOption(in: group),
               let index = group.options.firstIndex(of: selected) {
                state.selectedAudioTrackID = index
            }
        } else {
            state.audioTracks = []
            state.selectedAudioTrackID = nil
        }

        if let group = subtitleSelectionGroup {
            state.subtitleTracks = group.options.enumerated().map { index, option in
                let name = option.displayName.isEmpty
                    ? (option.extendedLanguageTag ?? "Subtitle \(index + 1)")
                    : option.displayName
                return SubtitleTrack(id: index, name: name, language: option.extendedLanguageTag)
            }
            if let selected = item.currentMediaSelection.selectedMediaOption(in: group),
               let index = group.options.firstIndex(of: selected) {
                state.selectedSubtitleTrackID = index
            }
        } else {
            state.subtitleTracks = []
            state.selectedSubtitleTrackID = nil
        }
    }

    private func waitUntilReady(_ item: AVPlayerItem, generation: UUID) async throws {
        for _ in 0..<200 {
            guard loadGeneration == generation else {
                throw PlayerEngineError.failedToLoad("The media load was superseded.")
            }
            switch item.status {
            case .readyToPlay:
                return
            case .failed:
                let error = PlayerEngineError.failedToLoad(item.error.map(Self.userFacingError) ?? "The media could not be decoded.")
                throw error
            case .unknown:
                break
            @unknown default:
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let error = PlayerEngineError.failedToLoad("Timed out while loading the media.")
        throw error
    }

    private func markFailure(_ error: Error) {
        state.status = .failed
        state.errorMessage = error.localizedDescription
        PlayerLogger.failure(error)
    }

    private static func userFacingError(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == AVFoundationErrorDomain else { return error.localizedDescription }
        switch nsError.code {
        case AVError.fileFormatNotRecognized.rawValue,
             AVError.formatUnsupported.rawValue,
             AVError.decoderNotFound.rawValue,
             AVError.undecodableMediaData.rawValue:
            return "This media format or codec is not supported by AVFoundation."
        case AVError.fileFailedToParse.rawValue,
             AVError.failedToParse.rawValue,
             AVError.decodeFailed.rawValue:
            return "The media could not be decoded. The file may be damaged or use an unsupported codec."
        default:
            return error.localizedDescription
        }
    }
}
