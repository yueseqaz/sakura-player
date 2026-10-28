import AVFoundation
import AVKit
import AppKit
import Combine
import SakuraPlayerCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PlayerViewModel: ObservableObject {
    private(set) var state = PlaybackState() {
        willSet {
            // Clock-only updates belong to the timeline, not the window,
            // native video surface, menus and settings observing this model.
            var previous = state
            previous.currentTime = newValue.currentTime
            previous.duration = newValue.duration
            if previous != newValue { objectWillChange.send() }
        }
    }
    let timeline = PlaybackTimelineModel()
    @Published private(set) var queue = PlaybackQueue()
    @Published private(set) var recentEntries: [PlaybackHistoryEntry] = []
    @Published private(set) var pendingResume: ResumePrompt?
    @Published private(set) var subtitleErrorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published var playbackOrder: PlaybackOrder = .sequential {
        didSet { queue.order = playbackOrder; savePreferences() }
    }
    @Published private(set) var activeExternalSubtitle: SubtitleCue?
    @Published private(set) var externalSubtitleURL: URL?
    @Published var subtitleFontSize: Double = 24 { didSet { savePreferences() } }
    @Published var subtitleColor: SubtitleColor = .white { didSet { savePreferences() } }
    @Published var subtitleBottomPadding: Double = 108 { didSet { savePreferences() } }
    // Fill is the least surprising default while preserving aspect ratio: window resizes do not expose a hard black strip.
    @Published var displayMode: VideoDisplayMode = .fill { didSet { savePreferences() } }
    @Published var rotation: VideoRotation = .zero { didSet { savePreferences() } }
    @Published var controlBarLayout: ControlBarLayout = .automatic { didSet { savePreferences() } }
    @Published var resumeEnabled = true { didSet { savePreferences() } }
    @Published var volumeStep = 0.05 { didSet { savePreferences() } }
    @Published var controlsHideDelay = 2.5 {
        didSet {
            savePreferences()
            if autoHideControls, state.status == .playing {
                lastPointerActivityAt = .now
                scheduleControlsHide()
            }
        }
    }
    @Published var autoHideControls = true {
        didSet {
            savePreferences()
            if !autoHideControls {
                hideControlsTask?.cancel()
                hideControlsTask = nil
                controlsVisible = true
            } else if state.status == .playing {
                lastPointerActivityAt = .now
                scheduleControlsHide()
            }
        }
    }
    @Published var seekStep = 5.0 { didSet { savePreferences() } }
    @Published var isDropTargeted = false
    @Published var controlsVisible = true
    @Published private(set) var controlsHovering = false
    @Published private(set) var isSeeking = false
    private var pendingSeekTime: TimeInterval? {
        get { timeline.position.pendingTime }
        set { timeline.preview(newValue) }
    }
    @Published var showDiagnostics = false
    let engine = AVPlayerEngine()
    let pictureInPicture = PictureInPictureCoordinator()
    let windowRestorer = WindowRestorer()
    private let history: PlaybackHistoryStore
    private var cancellables = Set<AnyCancellable>()
    private var lastHistoryPosition: TimeInterval = 0
    private var lastHistoryWrite = Date.distantPast
    private var lastHistoryStatus: PlaybackStatus = .idle
    private var externalCues: [SubtitleCue] = []
    private var externalSubtitleEnabled = false
    fileprivate(set) var subtitleDelay: TimeInterval = 0
    var isExternalSubtitleEnabled: Bool { externalSubtitleEnabled }
    private let defaults: UserDefaults
    private var didProcessCommandLineArguments = false
    private var hideControlsTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var pointerActivityToken = UUID()
    private var lastPointerLocation: CGPoint?
    private var lastPointerActivityAt = Date.distantPast
    private var pointerIsPressed = false
    // NSEvent window coordinates use a bottom-left origin. Keep a generous
    // bottom band armed while the pointer is approaching the floating rail;
    // this is more reliable than waiting for SwiftUI hover delivery during a
    // fade-in animation or a menu transition.
    private var pointerNearControls = false
    private var loadGeneration = UUID()
    private var preferredRate: Float = PlaybackRateScale.defaultValue
    // Kept outside the published playback snapshot so slider drags do not
    // cause the entire player surface to refresh on every pointer tick.
    var rateSliderDraftPosition: Double?
    private var isLoadingPreferences = true

    init(defaults: UserDefaults = .standard, history: PlaybackHistoryStore = PlaybackHistoryStore()) {
        self.defaults = defaults
        self.history = history
        if let rawOrder = defaults.string(forKey: "playbackOrder"), let order = PlaybackOrder(rawValue: rawOrder) {
            playbackOrder = order
        }
        if defaults.object(forKey: "subtitleFontSize") != nil {
            subtitleFontSize = defaults.double(forKey: "subtitleFontSize")
        }
        if let rawColor = defaults.string(forKey: "subtitleColor"), let color = SubtitleColor(rawValue: rawColor) {
            subtitleColor = color
        }
        if defaults.object(forKey: "subtitleBottomPadding") != nil {
            subtitleBottomPadding = defaults.double(forKey: "subtitleBottomPadding")
        }
        if let rawMode = defaults.string(forKey: "displayMode"), let mode = VideoDisplayMode(rawValue: rawMode) {
            displayMode = mode
        }
        if let rawRotation = defaults.string(forKey: "rotation"), let rotation = VideoRotation(rawValue: rawRotation) {
            self.rotation = rotation
        }
        if let rawControlBarLayout = defaults.string(forKey: "controlBarLayout"),
           let controlBarLayout = ControlBarLayout(rawValue: rawControlBarLayout) {
            self.controlBarLayout = controlBarLayout
        }
        if defaults.object(forKey: "resumeEnabled") != nil {
            resumeEnabled = defaults.bool(forKey: "resumeEnabled")
        }
        if defaults.object(forKey: "volumeStep") != nil { volumeStep = defaults.double(forKey: "volumeStep") }
        if defaults.object(forKey: "controlsHideDelay") != nil { controlsHideDelay = defaults.double(forKey: "controlsHideDelay") }
        if defaults.object(forKey: "autoHideControls") != nil { autoHideControls = defaults.bool(forKey: "autoHideControls") }
        if defaults.object(forKey: "seekStep") != nil { seekStep = defaults.double(forKey: "seekStep") }
        if defaults.object(forKey: "subtitleDelay") != nil {
            subtitleDelay = min(max(defaults.double(forKey: "subtitleDelay"), -10), 10)
        }
        if defaults.object(forKey: "preferredRate") != nil {
            preferredRate = PlaybackRateScale.clamp(defaults.float(forKey: "preferredRate"))
        }
        queue.order = playbackOrder
        Task { recentEntries = await history.allEntries() }
        // Engines publish on the main actor; an extra RunLoop hop can replay a
        // stale end-of-file event after the user has already opened another item.
        engine.statePublisher
            .sink { [weak self] state in self?.receiveEngineState(state) }
            .store(in: &cancellables)
        isLoadingPreferences = false
        savePreferences()
    }

    func receiveEngineState(_ state: PlaybackState) {
        let wasPlaying = self.state.status == .playing
        let wasEnded = self.state.status == .ended
        self.state = state
        timeline.update(from: state)
        if state.status == .playing, !wasPlaying { scheduleControlsHide() }
        if state.status != .playing {
            hideControlsTask?.cancel()
            hideControlsTask = nil
            if !controlsVisible { controlsVisible = true }
        }
        updateExternalSubtitle(for: state.currentTime)
        persistHistoryIfNeeded(for: state)
        if state.status == .ended, !wasEnded { playNext() }
    }

    func open(url: URL) {
        let siblings = MediaFileDiscovery.playableFiles(in: url.deletingLastPathComponent())
        let directoryQueue = siblings.contains(url) ? siblings : [url]
        queue.replace(with: directoryQueue)
        if let index = directoryQueue.firstIndex(of: url) { queue.select(index: index) }
        openCurrent()
    }

    func open(urls: [URL]) {
        queue.replace(with: urls)
        openCurrent()
    }

    func openCommandLineArgumentsIfNeeded() {
        guard !didProcessCommandLineArguments else { return }
        didProcessCommandLineArguments = true
        let urls = CommandLine.arguments.dropFirst()
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.isReadableFile(atPath: $0.path) }
        if !urls.isEmpty { open(urls: urls) }
    }

    func append(urls: [URL]) {
        queue.append(urls: urls)
    }

    private func openCurrent() {
        guard let url = queue.current?.url else { return }
        isSeeking = false
        pendingSeekTime = nil
        let generation = UUID()
        loadGeneration = generation
        lastHistoryPosition = 0
        lastHistoryWrite = .distantPast
        lastHistoryStatus = .loading
        externalCues = []
        externalSubtitleURL = nil
        activeExternalSubtitle = nil
        externalSubtitleEnabled = false
        subtitleErrorMessage = nil
        noticeTask?.cancel()
        noticeMessage = nil
        pendingResume = nil
        Task {
            do {
                try await engine.load(url: url)
                guard loadGeneration == generation else { return }
                engine.setRate(preferredRate)
                if let currentIndex = queue.currentIndex {
                    queue.updateDuration(at: currentIndex, duration: engine.state.duration)
                }
                if let audioID = defaults.object(forKey: trackPreferenceKey("audio", url: url)) as? Int {
                    engine.selectAudioTrack(id: audioID)
                }
                let savedSubtitleID = defaults.object(forKey: trackPreferenceKey("subtitle", url: url)) as? Int
                if let subtitleID = savedSubtitleID {
                    engine.selectSubtitleTrack(id: subtitleID >= 0 ? subtitleID : nil)
                }
                if savedSubtitleID != -1, engine.state.subtitleTracks.isEmpty,
                   let subtitleURL = SubtitleDiscovery.subtitles(for: url).first,
                   let cues = try? SubtitleParser.parse(url: subtitleURL) {
                    guard loadGeneration == generation else { return }
                    externalSubtitleURL = subtitleURL
                    externalCues = cues
                    externalSubtitleEnabled = true
                }
                if resumeEnabled, let resume = await history.entry(for: url)?.lastPosition,
                   resume > 5, resume < max(engine.state.duration - 5, 5) {
                    guard loadGeneration == generation else { return }
                    pendingResume = ResumePrompt(url: url, position: resume)
                    return
                }
                engine.play()
                scheduleControlsHide()
            }
            catch {
                guard loadGeneration == generation else { return }
                state.errorMessage = sanitizedError(error.localizedDescription, for: url)
                state.status = .failed
            }
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audio, .data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, !panel.urls.isEmpty { open(urls: panel.urls) }
    }

    func openSubtitle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.text, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let cues: [SubtitleCue]
        do {
            cues = try SubtitleParser.parse(url: url)
        } catch {
            subtitleErrorMessage = error.localizedDescription
            return
        }
        engine.selectSubtitleTrack(id: nil)
        externalSubtitleURL = url
        externalCues = cues
        externalSubtitleEnabled = true
        updateExternalSubtitle(for: state.currentTime)
        showNotice("External subtitles: \(url.lastPathComponent)")
    }

    func dismissSubtitleError() { subtitleErrorMessage = nil }
    func dismissNotice() {
        noticeTask?.cancel()
        noticeMessage = nil
    }

    func close() {
        loadGeneration = UUID()
        isSeeking = false
        pendingSeekTime = nil
        pendingResume = nil
        externalCues = []
        externalSubtitleURL = nil
        externalSubtitleEnabled = false
        activeExternalSubtitle = nil
        subtitleErrorMessage = nil
        noticeTask?.cancel()
        noticeMessage = nil
        engine.close()
    }
    func continueFromSavedPosition() {
        guard let pendingResume else { return }
        engine.seek(to: pendingResume.position)
        self.pendingResume = nil
        engine.play()
    }
    func restartFromBeginning() {
        pendingResume = nil
        engine.seek(to: 0)
        engine.play()
    }
    func clearRecent() {
        Task {
            await history.removeAll()
            recentEntries = []
        }
    }
    func playNext() {
        guard queue.advance() != nil else { return }
        openCurrent()
    }
    func playPrevious() {
        guard queue.previous() != nil else { return }
        openCurrent()
    }
    func selectQueueItem(_ index: Int) {
        queue.select(index: index)
        openCurrent()
    }
    func removeQueueItem(_ index: Int) {
        let currentURL = queue.current?.url
        queue.remove(at: index)
        if queue.current?.url != currentURL {
            if queue.current == nil { close() } else { openCurrent() }
        }
    }
    func clearQueue() {
        queue.clear()
        close()
    }
    func togglePlayback() {
        if state.status == .playing { engine.pause() } else { engine.play() }
    }
    func seek(to value: Double) { engine.seek(to: value) }
    func beginSeek() {
        guard !isSeeking else { return }
        isSeeking = true
        // Keep the rail mounted for the whole drag. Hiding it while the
        // pointer is down makes the native slider feel like it is fighting
        // the user, especially on long timelines.
        if !controlsVisible { controlsVisible = true }
        lastPointerActivityAt = .now
        hideControlsTask?.cancel()
        hideControlsTask = nil
        pendingSeekTime = clampedSeekTime(state.currentTime)
    }
    func updatePendingSeek(_ value: Double) {
        if !isSeeking { beginSeek() }
        pendingSeekTime = clampedSeekTime(value)
    }
    func commitSeek() {
        guard isSeeking else { return }
        let target = pendingSeekTime ?? state.currentTime
        isSeeking = false
        pendingSeekTime = nil
        engine.seek(to: target)
        lastPointerActivityAt = .now
        scheduleControlsHide()
    }
    private func clampedSeekTime(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        return min(max(0, value), max(state.duration, 1))
    }
    func setVolume(_ value: Double) { engine.setVolume(Float(value)) }
    func toggleMute() { engine.setMuted(!state.isMuted) }
    func setRate(_ rate: Float) {
        preferredRate = PlaybackRateScale.clamp(rate)
        defaults.set(preferredRate, forKey: "preferredRate")
        engine.setRate(preferredRate)
    }
    func adjustRate(direction: Int) {
        guard direction != 0 else { return }
        let ticks = PlaybackRateScale.ticks
        let current = PlaybackRateScale.clamp(state.rate)
        let index: Int
        if direction < 0 {
            index = ticks.lastIndex(where: { $0 < current - 0.0001 }) ?? 0
        } else {
            index = ticks.firstIndex(where: { $0 > current + 0.0001 }) ?? (ticks.count - 1)
        }
        setRate(ticks[index])
    }
    func toggleFullScreen() { NSApp.keyWindow?.toggleFullScreen(nil) }
    func togglePictureInPicture() { pictureInPicture.toggle() }
    func presentDiagnostics() { showDiagnostics = true }
    func notePointerActivity(at location: CGPoint, eventType: NSEvent.EventType) {
        pointerNearControls = location.y <= 180
        if let lastPointerLocation,
           abs(lastPointerLocation.x - location.x) < 1,
           abs(lastPointerLocation.y - location.y) < 1 {
            // A mouse-down/up at the same location is still meaningful even
            // though it did not move the pointer.
            if eventType == .mouseMoved { return }
        }
        lastPointerLocation = location
        lastPointerActivityAt = .now
        if !controlsVisible { controlsVisible = true }
        switch eventType {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            pointerIsPressed = true
            hideControlsTask?.cancel()
            hideControlsTask = nil
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            pointerIsPressed = false
            scheduleControlsHide()
        default:
            if pointerNearControls || controlsHovering {
                hideControlsTask?.cancel()
                hideControlsTask = nil
            } else if hideControlsTask == nil, !pointerIsPressed, !isSeeking {
                scheduleControlsHide()
            }
        }
    }
    func setControlsHovering(_ hovering: Bool) {
        guard controlsHovering != hovering else { return }
        controlsHovering = hovering
        if hovering {
            controlsVisible = true
            pointerNearControls = true
            hideControlsTask?.cancel()
            hideControlsTask = nil
        } else if state.status == .playing {
            pointerNearControls = false
            lastPointerActivityAt = .now
            scheduleControlsHide()
        }
    }
    private func scheduleControlsHide() {
        let token = UUID()
        pointerActivityToken = token
        hideControlsTask?.cancel()
        guard autoHideControls, !controlsHovering, !pointerNearControls else { return }
        if lastPointerActivityAt == .distantPast { lastPointerActivityAt = .now }
        hideControlsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled,
                  self.pointerActivityToken == token,
                  self.state.status == .playing,
                  !self.pointerIsPressed,
                  !self.isSeeking,
                  !self.controlsHovering,
                  !self.pointerNearControls {
                let elapsed = Date().timeIntervalSince(self.lastPointerActivityAt)
                let remaining = max(0, self.controlsHideDelay - elapsed)
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                guard !Task.isCancelled, self.pointerActivityToken == token,
                      self.state.status == .playing else { return }
                if Date().timeIntervalSince(self.lastPointerActivityAt) >= self.controlsHideDelay {
                    self.controlsVisible = false
                    break
                }
            }
            if self.pointerActivityToken == token {
                self.hideControlsTask = nil
            }
        }
    }
    private func showNotice(_ message: String) {
        noticeTask?.cancel()
        noticeMessage = message
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.noticeMessage = nil
        }
    }
    func selectAudioTrack(_ id: Int?) {
        let trackName = id.flatMap { index in state.audioTracks.first(where: { $0.id == index })?.name }
        engine.selectAudioTrack(id: id)
        if let id, let url = state.mediaURL { defaults.set(id, forKey: trackPreferenceKey("audio", url: url)) }
        showNotice(trackName.map { "Audio: \($0)" } ?? "Audio track off")
    }
    func selectSubtitleTrack(_ id: Int?) {
        let trackName = id.flatMap { index in state.subtitleTracks.first(where: { $0.id == index })?.name }
        externalSubtitleEnabled = false
        externalCues = []
        externalSubtitleURL = nil
        activeExternalSubtitle = nil
        engine.selectSubtitleTrack(id: id)
        if let url = state.mediaURL { defaults.set(id ?? -1, forKey: trackPreferenceKey("subtitle", url: url)) }
        showNotice(trackName.map { "Subtitles: \($0)" } ?? "Subtitles off")
    }
    func turnSubtitlesOff() {
        if !externalCues.isEmpty {
            externalSubtitleEnabled = false
            activeExternalSubtitle = nil
            showNotice("Subtitles off")
            return
        }
        selectSubtitleTrack(nil)
    }
    func toggleSubtitles() {
        if !externalCues.isEmpty {
            externalSubtitleEnabled.toggle()
            updateExternalSubtitle(for: state.currentTime)
        } else if state.selectedSubtitleTrackID != nil {
            selectSubtitleTrack(nil)
        } else if let first = state.subtitleTracks.first {
            selectSubtitleTrack(first.id)
        }
    }
    func setSubtitleDelay(_ delay: TimeInterval) {
        subtitleDelay = min(max(-10, delay), 10)
        defaults.set(subtitleDelay, forKey: "subtitleDelay")
        updateExternalSubtitle(for: state.currentTime)
    }
    func setSubtitleFontSize(_ size: Double) { subtitleFontSize = min(max(14, size), 48) }
    func setSubtitleBottomPadding(_ padding: Double) { subtitleBottomPadding = min(max(48, padding), 220) }
    func setPlaybackOrder(_ order: PlaybackOrder) { playbackOrder = order }
    func cyclePlaybackOrder() {
        guard let index = PlaybackOrder.allCases.firstIndex(of: playbackOrder) else { return }
        setPlaybackOrder(PlaybackOrder.allCases[(index + 1) % PlaybackOrder.allCases.count])
    }

    private func persistHistoryIfNeeded(for state: PlaybackState) {
        defer { lastHistoryStatus = state.status }
        guard let url = state.mediaURL else { return }
        let statusChanged = state.status != lastHistoryStatus
        let isPlaybackCheckpoint = state.status == .playing && state.currentTime - lastHistoryPosition >= 5
        let shouldCaptureTransition = statusChanged && state.currentTime > 0.5 && (state.status == .paused || state.status == .ended)
        guard isPlaybackCheckpoint || shouldCaptureTransition,
              Date.timeIntervalSinceReferenceDate - lastHistoryWrite.timeIntervalSinceReferenceDate >= 1 else { return }
        lastHistoryPosition = state.currentTime
        lastHistoryWrite = .now
        Task {
            await history.record(url: url, position: state.currentTime)
            recentEntries = await history.allEntries()
        }
    }

    private func updateExternalSubtitle(for time: TimeInterval) {
        let cue = SubtitleCue.active(in: externalCues, at: time, delay: subtitleDelay,
                                     enabled: externalSubtitleEnabled)
        if activeExternalSubtitle != cue { activeExternalSubtitle = cue }
    }

    private func savePreferences() {
        guard !isLoadingPreferences else { return }
        defaults.set(playbackOrder.rawValue, forKey: "playbackOrder")
        defaults.set(subtitleFontSize, forKey: "subtitleFontSize")
        defaults.set(subtitleColor.rawValue, forKey: "subtitleColor")
        defaults.set(subtitleBottomPadding, forKey: "subtitleBottomPadding")
        defaults.set(displayMode.rawValue, forKey: "displayMode")
        defaults.set(rotation.rawValue, forKey: "rotation")
        defaults.set(controlBarLayout.rawValue, forKey: "controlBarLayout")
        defaults.set(resumeEnabled, forKey: "resumeEnabled")
        defaults.set(volumeStep, forKey: "volumeStep")
        defaults.set(controlsHideDelay, forKey: "controlsHideDelay")
        defaults.set(autoHideControls, forKey: "autoHideControls")
        defaults.set(seekStep, forKey: "seekStep")
    }

    private func trackPreferenceKey(_ kind: String, url: URL) -> String {
        "track.\(kind).\(url.path)"
    }

    private func sanitizedError(_ message: String, for url: URL) -> String {
        let path = url.path
        guard !path.isEmpty else { return message }
        return message
            .replacingOccurrences(of: url.absoluteString, with: "<media>")
            .replacingOccurrences(of: path, with: "<media>")
    }

    var diagnosticsText: String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
        let mediaType = state.mediaURL?.pathExtension.uppercased().isEmpty == false
            ? state.mediaURL!.pathExtension.uppercased()
            : "unknown"
        let audio = state.audioTracks.isEmpty ? "none" : state.audioTracks.map(\.name).joined(separator: ", ")
        let subtitles = state.subtitleTracks.isEmpty ? "none" : state.subtitleTracks.map(\.name).joined(separator: ", ")
        let error = state.errorMessage.map { message in
            guard let url = state.mediaURL else { return message }
            return sanitizedError(message, for: url)
        } ?? "none"
        return """
        Sakura Player diagnostics
        App: \(appVersion) (build \(appBuild))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Engine: AVFoundation / AVPlayer
        Audio delay: \(engine.supportsAudioDelay ? "available" : "unavailable")
        Status: \(state.status.rawValue)
        Media type: \(mediaType)
        Duration: \(formatDiagnosticsTime(state.duration))
        Position: \(formatDiagnosticsTime(state.currentTime))
        Rate: \(state.rate)
        Buffering: \(state.isBuffering)
        Audio tracks: \(audio)
        Subtitle tracks: \(subtitles)
        Error: \(error)
        """
    }

    private func formatDiagnosticsTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "unknown" }
        return String(format: "%.2fs", max(0, seconds))
    }
}

struct ResumePrompt: Identifiable {
    let id = UUID()
    let url: URL
    let position: TimeInterval
}
