// Older SDKs lack Sendable annotations for AVMediaSelectionGroup; its use
// stays confined to this main-actor adapter.
@preconcurrency import AVFoundation
import Combine
import Foundation

@MainActor
public final class AVPlayerEngine: NSObject, PlayerEngine {
    public private(set) var state = PlaybackState() {
        didSet { if state != oldValue { stateSubject.send(state) } }
    }

    public var statePublisher: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    public let player: AVPlayer
    public let supportsAudioDelay = false

    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())
    private var itemObservation: NSKeyValueObservation?
    private let observers: AVPlayerObserverLifetime
    private var timeControlObservation: NSKeyValueObservation?
    private var audioSelectionGroup: AVMediaSelectionGroup?
    private var subtitleSelectionGroup: AVMediaSelectionGroup?
    private var loadGeneration = UUID()
    private var seekGeneration = UUID()
    private var isSeeking = false

    public override init() {
        let player = AVPlayer()
        self.player = player
        observers = AVPlayerObserverLifetime(player: player)
        super.init()
        timeControlObservation = player.observe(\AVPlayer.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem?.status == .readyToPlay,
                      self.state.status != .failed else { return }
                // KVO may arrive off-main; read the current value after hopping
                // rather than applying a status captured for the previous item.
                switch self.player.timeControlStatus {
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
        observers.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let itemID = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            Task { @MainActor [weak self] in
                guard let self, let itemID, let currentItem = self.player.currentItem,
                      ObjectIdentifier(currentItem) == itemID, !self.isSeeking else { return }
                let time = currentItem.currentTime().seconds
                let duration = currentItem.duration.seconds
                if time.isFinite, duration.isFinite, time < duration - 0.1 { return }
                self.state.status = .ended
            }
        }
    }

    public func load(url: URL) async throws {
        let generation = UUID()
        loadGeneration = generation
        resetItem()
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
                    if self.state.status == .loading { self.state.status = .paused }
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
            try await updateTracks(for: item, generation: generation)
        } catch {
            if loadGeneration == generation {
                resetItem()
                state.mediaURL = url
                markFailure(error)
            }
            throw error
        }
        guard loadGeneration == generation else {
            throw PlayerEngineError.failedToLoad("The media load was superseded.")
        }
        installTimeObserver(generation: generation)
    }

    public func close() {
        loadGeneration = UUID()
        resetItem()
    }

    public func play() {
        guard player.currentItem?.status == .readyToPlay, state.status != .failed else { return }
        if state.status == .ended { seek(to: 0) }
        player.playImmediately(atRate: state.rate)
        state.status = .playing
    }

    public func pause() {
        player.pause()
        guard player.currentItem?.status == .readyToPlay, state.status != .failed else { return }
        state.status = .paused
    }

    public func seek(to seconds: TimeInterval) {
        guard seconds.isFinite, let item = player.currentItem, item.status == .readyToPlay else { return }
        let clamped = min(max(0, seconds), state.duration > 0 ? state.duration : seconds)
        let generation = UUID()
        seekGeneration = generation
        isSeeking = true
        item.cancelPendingSeeks()
        state.currentTime = clamped
        if state.status == .ended { state.status = .paused }
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.seekGeneration == generation, self.player.currentItem === item else { return }
                self.isSeeking = false
                let actual = self.player.currentTime().seconds
                if actual.isFinite { self.state.currentTime = max(0, actual) }
                // Audio seeks can resolve to the last packet before duration.
                // An explicit end target still represents a completed item.
                if finished, self.state.duration > 0,
                   clamped >= self.state.duration || (actual.isFinite && actual >= self.state.duration - 0.01) {
                    self.state.currentTime = self.state.duration
                    self.state.status = .ended
                }
            }
        }
    }

    public func setVolume(_ volume: Float) {
        guard volume.isFinite else { return }
        let clamped = min(max(0, volume), 1)
        player.volume = clamped
        state.volume = clamped
        if clamped > 0 { setMuted(false) }
    }

    public func setMuted(_ muted: Bool) {
        player.isMuted = muted
        state.isMuted = muted
    }

    public func setRate(_ rate: Float) {
        guard rate.isFinite else { return }
        let clamped = min(max(0.25, rate), 4)
        state.rate = clamped
        if state.status == .playing { player.rate = clamped }
    }

    public func setAudioDelay(_ delay: TimeInterval) throws {
        throw PlayerEngineError.unsupportedFeature("Audio delay is not available with the AVFoundation engine.")
    }

    public func selectAudioTrack(id: Int?) {
        guard let item = player.currentItem, let group = audioSelectionGroup,
              id.map({ group.options.indices.contains($0) }) ?? group.allowsEmptySelection else { return }
        let option = id.map { group.options[$0] }
        item.select(option, in: group)
        state.selectedAudioTrackID = id
    }

    public func selectSubtitleTrack(id: Int?) {
        guard let item = player.currentItem, let group = subtitleSelectionGroup,
              id.map({ group.options.indices.contains($0) }) ?? group.allowsEmptySelection else { return }
        let option = id.map { group.options[$0] }
        item.select(option, in: group)
        state.selectedSubtitleTrackID = id
    }

    private func updateTracks(for item: AVPlayerItem, generation: UUID) async throws {
        let audioGroup = try? await item.asset.loadMediaSelectionGroup(for: .audible)
        try validateLoad(item: item, generation: generation)
        let subtitleGroup = try? await item.asset.loadMediaSelectionGroup(for: .legible)
        try validateLoad(item: item, generation: generation)
        audioSelectionGroup = audioGroup
        subtitleSelectionGroup = subtitleGroup

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
            try validateLoad(item: item, generation: generation)
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

    private func validateLoad(item: AVPlayerItem, generation: UUID) throws {
        try Task.checkCancellation()
        guard loadGeneration == generation, player.currentItem === item else {
            throw PlayerEngineError.failedToLoad("The media load was superseded.")
        }
    }

    private func resetItem() {
        seekGeneration = UUID()
        isSeeking = false
        itemObservation?.invalidate()
        itemObservation = nil
        observers.removeTimeObserver()
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        audioSelectionGroup = nil
        subtitleSelectionGroup = nil
        var next = PlaybackState()
        next.volume = state.volume
        next.isMuted = state.isMuted
        next.rate = state.rate
        state = next
    }

    private func installTimeObserver(generation: UUID) {
        observers.timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.loadGeneration == generation, !self.isSeeking else { return }
                let seconds = max(0, time.seconds.isFinite ? time.seconds : 0)
                var next = self.state
                next.currentTime = next.status == .ended ? next.duration : seconds
                if let duration = self.player.currentItem?.duration.seconds, duration.isFinite {
                    next.duration = max(0, duration)
                }
                if next != self.state { self.state = next }
            }
        }
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

// Tokens are only mutated by the main-actor engine. The separate owner makes
// nonisolated deinit cleanup safe without scheduling work that retains it.
private final class AVPlayerObserverLifetime: @unchecked Sendable {
    let player: AVPlayer
    var timeObserver: Any?
    var endObserver: NSObjectProtocol?

    init(player: AVPlayer) { self.player = player }

    func removeTimeObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    deinit {
        removeTimeObserver()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
