import AVFoundation
import AVKit
import AppKit
import Combine
import SakuraPlayerCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct SakuraPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PlayerViewModel()

    var body: some Scene {
        WindowGroup("Sakura Player") {
            PlayerView(model: model)
                .frame(minWidth: 720, minHeight: 420)
                .background(WindowAccessor(restorer: model.windowRestorer))
                .onAppear {
                    appDelegate.install { model.open(urls: $0) }
                    model.openCommandLineArgumentsIfNeeded()
                }
                .onOpenURL { url in model.open(url: url) }
        }
        .defaultSize(width: 960, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Menu("Open Recent") {
                    if model.recentEntries.isEmpty {
                        Text("No Recent Files")
                    } else {
                        ForEach(model.recentEntries) { entry in
                            Button(entry.url.lastPathComponent) { model.open(url: entry.url) }
                        }
                    }
                    Divider()
                    Button("Clear Recent") { model.clearRecent() }
                }
            }
            CommandGroup(after: .windowArrangement) {
                Button(model.state.status == .playing ? "Pause" : "Play") { model.togglePlayback() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Close Video") { model.close() }
                    .keyboardShortcut("w", modifiers: .command)
                Button("Seek Back \(Int(model.seekStep)) Seconds") { model.seek(to: model.state.currentTime - model.seekStep) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Seek Forward \(Int(model.seekStep)) Seconds") { model.seek(to: model.state.currentTime + model.seekStep) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Volume Up") { model.setVolume(Double(model.state.volume) + model.volumeStep) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("Volume Down") { model.setVolume(Double(model.state.volume) - model.volumeStep) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button("Mute") { model.toggleMute() }
                    .keyboardShortcut("m", modifiers: [])
                Button("Toggle Subtitles") { model.toggleSubtitles() }
                    .keyboardShortcut("s", modifiers: [])
                Button("External Subtitle Delay -0.5 Seconds") { model.setSubtitleDelay(model.subtitleDelay - 0.5) }
                    .keyboardShortcut("[", modifiers: [])
                Button("External Subtitle Delay +0.5 Seconds") { model.setSubtitleDelay(model.subtitleDelay + 0.5) }
                    .keyboardShortcut("]", modifiers: [])
                Button("Cycle Playback Order") { model.cyclePlaybackOrder() }
                    .keyboardShortcut("l", modifiers: [])
                Button("Slower Playback") { model.setRate(model.state.rate - 0.25) }
                    .keyboardShortcut(",", modifiers: [])
                Button("Faster Playback") { model.setRate(model.state.rate + 0.25) }
                    .keyboardShortcut(".", modifiers: [])
                Button("Toggle Full Screen") { model.toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [])
                Button("Exit Full Screen") {
                    guard let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) else { return }
                    window.toggleFullScreen(nil)
                }
                    .keyboardShortcut(.escape, modifiers: [])
                if model.pictureInPicture.isSupported {
                    Button("Picture in Picture") { model.togglePictureInPicture() }
                }
                Divider()
                Button("Diagnostics…") { model.presentDiagnostics() }
            }
        }
        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingURLs: [URL] = []
    private var openHandler: (([URL]) -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func install(openHandler: @escaping ([URL]) -> Void) {
        self.openHandler = openHandler
        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        openHandler(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        receive(urls: filenames.map(URL.init(fileURLWithPath:)))
        sender.reply(toOpenOrPrint: .success)
    }

    // Finder and Launch Services can deliver URL-based open requests instead
    // of the legacy filename callback. Keep both paths on the same queue so
    // files opened before SwiftUI has installed the model are not lost.
    func application(_ application: NSApplication, open urls: [URL]) {
        receive(urls: urls)
    }

    private func receive(urls: [URL]) {
        let readableURLs = urls.filter { $0.isFileURL && FileManager.default.isReadableFile(atPath: $0.path) }
        guard !readableURLs.isEmpty else { return }
        if let openHandler { openHandler(readableURLs) } else { pendingURLs.append(contentsOf: readableURLs) }
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var state = PlaybackState()
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
    @Published private(set) var isSeeking = false
    @Published private(set) var pendingSeekTime: TimeInterval?
    @Published var showDiagnostics = false
    let engine = AVPlayerEngine()
    let pictureInPicture = PictureInPictureCoordinator()
    let windowRestorer = WindowRestorer()
    private let history = PlaybackHistoryStore()
    private var cancellables = Set<AnyCancellable>()
    private var lastHistoryPosition: TimeInterval = 0
    private var lastHistoryWrite = Date.distantPast
    private var lastHistoryStatus: PlaybackStatus = .idle
    private var externalCues: [SubtitleCue] = []
    private var externalSubtitleEnabled = false
    fileprivate(set) var subtitleDelay: TimeInterval = 0
    var isExternalSubtitleEnabled: Bool { externalSubtitleEnabled }
    private let defaults = UserDefaults.standard
    private var didProcessCommandLineArguments = false
    private var hideControlsTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var pointerActivityToken = UUID()
    private var lastPointerLocation: CGPoint?
    private var lastPointerActivityAt = Date.distantPast
    private var pointerIsPressed = false
    private var loadGeneration = UUID()
    private var preferredRate: Float = 1
    private var isLoadingPreferences = true

    init() {
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
            preferredRate = min(max(defaults.float(forKey: "preferredRate"), 0.25), 4)
        }
        queue.order = playbackOrder
        Task { recentEntries = await history.allEntries() }
        engine.statePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let wasPlaying = self.state.status == .playing
                self.state = state
                if state.status == .playing, !wasPlaying {
                    self.scheduleControlsHide()
                }
                if state.status != .playing {
                    self.hideControlsTask?.cancel()
                    self.hideControlsTask = nil
                    self.controlsVisible = true
                }
                self.updateExternalSubtitle(for: state.currentTime)
                self.persistHistoryIfNeeded(for: state)
                if state.status == .ended { self.playNext() }
            }
            .store(in: &cancellables)
        isLoadingPreferences = false
        savePreferences()
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
                if let subtitleID = defaults.object(forKey: trackPreferenceKey("subtitle", url: url)) as? Int, subtitleID >= 0 {
                    engine.selectSubtitleTrack(id: subtitleID)
                }
                if engine.state.subtitleTracks.isEmpty,
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
        isSeeking = true
        // Keep the rail mounted for the whole drag. Hiding it while the
        // pointer is down makes the native slider feel like it is fighting
        // the user, especially on long timelines.
        controlsVisible = true
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
        preferredRate = min(max(rate, 0.25), 4)
        defaults.set(preferredRate, forKey: "preferredRate")
        engine.setRate(preferredRate)
    }
    func toggleFullScreen() { NSApp.keyWindow?.toggleFullScreen(nil) }
    func togglePictureInPicture() { pictureInPicture.toggle() }
    func presentDiagnostics() { showDiagnostics = true }
    func notePointerActivity(at location: CGPoint, eventType: NSEvent.EventType) {
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
            if hideControlsTask == nil, !pointerIsPressed, !isSeeking { scheduleControlsHide() }
        }
    }
    private func scheduleControlsHide() {
        let token = UUID()
        pointerActivityToken = token
        hideControlsTask?.cancel()
        guard autoHideControls else { return }
        if lastPointerActivityAt == .distantPast { lastPointerActivityAt = .now }
        hideControlsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled,
                  self.pointerActivityToken == token,
                  self.state.status == .playing,
                  !self.pointerIsPressed,
                  !self.isSeeking {
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
        guard !externalCues.isEmpty, (state.subtitleTracks.isEmpty || externalSubtitleEnabled) else {
            activeExternalSubtitle = nil
            return
        }
        activeExternalSubtitle = externalCues.first { $0.contains(time + subtitleDelay) }
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

struct PlayerView: View {
    @ObservedObject var model: PlayerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            PlaybackCanvasBackground()
            if model.state.mediaURL != nil {
                PlayerSurface(
                    player: model.engine.player,
                    displayMode: model.displayMode,
                    presentationSize: model.engine.player.currentItem?.presentationSize ?? .zero,
                    layerReady: model.pictureInPicture.attach
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .rotationEffect(model.rotation.angle)
                    .onTapGesture(count: 2) { model.toggleFullScreen() }
            } else {
                EmptyPlayerView { model.presentOpenPanel() }
            }
            if model.state.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
            if model.state.mediaURL != nil {
                PlaybackControls(model: model)
                    .opacity(model.controlsVisible ? 1 : 0)
                    .allowsHitTesting(model.controlsVisible)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.controlsVisible)
            }
            if let cue = model.activeExternalSubtitle {
                SubtitleOverlay(text: cue.text, fontSize: model.subtitleFontSize, color: model.subtitleColor.color)
                    .padding(.bottom, model.subtitleBottomPadding)
            }
            if let message = model.state.errorMessage {
                ErrorBanner(message: message, close: model.close, reopen: model.presentOpenPanel)
            }
            if let message = model.subtitleErrorMessage {
                NoticeBanner(message: message, dismiss: model.dismissSubtitleError)
            }
            if let message = model.noticeMessage {
                NoticeBanner(message: message, dismiss: model.dismissNotice)
            }
            if let pendingResume = model.pendingResume {
                ResumeBanner(position: pendingResume.position,
                             continueAction: model.continueFromSavedPosition,
                             restartAction: model.restartFromBeginning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL], isTargeted: $model.isDropTargeted) { providers in
            guard !providers.isEmpty else { return false }
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    guard let url = await loadDroppedURL(from: provider) else { continue }
                    urls.append(url)
                }
                guard !urls.isEmpty else { return }
                model.open(urls: urls)
            }
            return true
        }
        .overlay { if model.isDropTargeted { RoundedRectangle(cornerRadius: 12).stroke(.pink, lineWidth: 3).padding(8) } }
        .overlay {
            PointerActivityMonitor { event in
                model.notePointerActivity(at: event.locationInWindow, eventType: event.type)
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $model.showDiagnostics) {
            DiagnosticsView(text: model.diagnosticsText)
        }
    }

    private func loadDroppedURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }
}

/// Uses an app-local mouse monitor so control hiding is driven by real pointer
/// movement rather than SwiftUI hover phase updates that can be emitted repeatedly.
struct PointerActivityMonitor: NSViewRepresentable {
    let onActivity: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onActivity: onActivity) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onActivity = onActivity
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onActivity: (NSEvent) -> Void
        private var monitor: Any?

        init(onActivity: @escaping (NSEvent) -> Void) {
            self.onActivity = onActivity
        }

        func install() {
            guard monitor == nil else { return }
            let pointerEvents: NSEvent.EventTypeMask = [
                .mouseMoved,
                .leftMouseDown,
                .leftMouseDragged,
                .leftMouseUp,
                .rightMouseDown,
                .rightMouseDragged,
                .rightMouseUp,
                .otherMouseDown,
                .otherMouseDragged,
                .otherMouseUp
            ]
            monitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents) { [weak self] event in
                self?.onActivity(event)
                return event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { uninstall() }
    }
}

struct PlaybackCanvasBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.016, blue: 0.024)
            RadialGradient(
                colors: [Color.white.opacity(0.045), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
    }
}

struct DiagnosticsView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics").font(.title2.weight(.semibold))
            Text("Copy this report when asking for help. Personal file paths are omitted.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: .constant(text))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 560, minHeight: 300)
                .border(Color.secondary.opacity(0.25))
            HStack {
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 420)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let restorer: WindowRestorer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { restorer.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { restorer.attach(to: nsView.window) }
    }
}

@MainActor
final class WindowRestorer: NSObject {
    private let defaults = UserDefaults.standard
    private let frameKey = "window.frame"
    private weak var window: NSWindow?
    private var didRestore = false
    private var observers: [NSObjectProtocol] = []

    func attach(to window: NSWindow?) {
        guard let window, self.window !== window else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        self.window = window
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.saveFrame() }
            })
        }
        guard !didRestore else { return }
        didRestore = true
        guard let raw = defaults.string(forKey: frameKey) else { return }
        let frame = NSRectFromString(raw)
        guard frame.width >= 720, frame.height >= 420,
              NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return }
        window.setFrame(frame, display: false)
    }

    private func saveFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let frame = window.frame
        defaults.set(NSStringFromRect(frame), forKey: frameKey)
    }
}

struct EmptyPlayerView: View {
    let open: () -> Void
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.075, blue: 0.11),
                    Color(red: 0.065, green: 0.055, blue: 0.10),
                    Color(red: 0.09, green: 0.045, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.pink.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 55)
                .offset(x: 210, y: -150)
            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: -230, y: 180)

            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(0.1))
                            .frame(width: 76, height: 76)
                        Image(systemName: "play.fill")
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(.pink.opacity(0.95))
                            .offset(x: 2)
                    }
                    Text("Ready when you are")
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Drop a video anywhere in this window, or open a file to begin.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                }

                Button(action: open) {
                    Label("Open Video", systemImage: "folder.fill")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .keyboardShortcut("o", modifiers: .command)

                HStack(spacing: 8) {
                    Image(systemName: "command")
                    Text("O")
                    Text("to open")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 34)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 30, y: 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    let displayMode: VideoDisplayMode
    let presentationSize: CGSize
    let layerReady: (AVPlayerLayer) -> Void

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.displayMode = displayMode
        view.presentationSize = presentationSize
        layerReady(view.playerLayer)
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        nsView.playerLayer.player = player
        nsView.displayMode = displayMode
        nsView.presentationSize = presentationSize
        nsView.needsLayout = true
    }
}

@MainActor
final class PictureInPictureCoordinator: NSObject, AVPictureInPictureControllerDelegate {
    private var controller: AVPictureInPictureController?

    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    func attach(_ layer: AVPlayerLayer) {
        guard isSupported else { return }
        if controller?.playerLayer !== layer {
            controller = AVPictureInPictureController(playerLayer: layer)
            controller?.delegate = self
        }
    }

    func toggle() {
        guard let controller, isSupported else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        }
    }
}

final class PlayerLayerView: NSView {
    var presentationSize: CGSize = .zero {
        didSet { needsLayout = true }
    }

    var displayMode: VideoDisplayMode = .fit {
        didSet {
            playerLayer.videoGravity = displayMode.videoGravity
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = AVPlayerLayer()
        layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func layout() {
        super.layout()
        guard displayMode == .original,
              presentationSize.width > 0,
              presentationSize.height > 0 else {
            playerLayer.frame = bounds
            return
        }

        // Keep native-sized media at 1:1 when it fits, but never let it
        // overflow the window. This preserves a useful original-size mode
        // without changing the fill-first default.
        let scale = min(1, min(bounds.width / presentationSize.width, bounds.height / presentationSize.height))
        let size = CGSize(width: presentationSize.width * scale, height: presentationSize.height * scale)
        playerLayer.frame = NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

struct SettingsView: View {
    @ObservedObject var model: PlayerViewModel

    var body: some View {
        Form {
            Section("Playback") {
                Picker("End behavior", selection: $model.playbackOrder) {
                    ForEach(PlaybackOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                Text("Queue settings apply to the current temporary queue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Offer resume prompt", isOn: $model.resumeEnabled)
                HStack {
                    Text("Arrow-key seek step")
                    Slider(value: $model.seekStep, in: 1...30, step: 1)
                    Text("\(Int(model.seekStep))s")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                HStack {
                    Text("Playback rate")
                    Slider(value: Binding(get: { Double(model.state.rate) }, set: { model.setRate(Float($0)) }), in: 0.25...4, step: 0.05)
                    Text("\(model.state.rate, specifier: "%.2g")×")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }
            Section("Subtitles") {
                Picker("Text size", selection: $model.subtitleFontSize) {
                    Text("Small").tag(18.0)
                    Text("Medium").tag(24.0)
                    Text("Large").tag(32.0)
                }
                Picker("Text color", selection: $model.subtitleColor) {
                    ForEach(SubtitleColor.allCases, id: \.self) { color in
                        Text(color.title).tag(color)
                    }
                }
                HStack {
                    Text("External subtitle delay")
                    Slider(value: Binding(get: { model.subtitleDelay }, set: { model.setSubtitleDelay($0) }), in: -10...10, step: 0.1)
                    Text("\(model.subtitleDelay, specifier: "%.1f")s")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                    Button("Reset") { model.setSubtitleDelay(0) }
                }
            }
            Section("Picture") {
                Picker("Display mode", selection: $model.displayMode) {
                    ForEach(VideoDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Rotation", selection: $model.rotation) {
                    ForEach(VideoRotation.allCases, id: \.self) { rotation in
                        Text(rotation.title).tag(rotation)
                    }
                }
            }
            Section("Sound") {
                HStack {
                    Text("Volume key step")
                    Slider(value: $model.volumeStep, in: 0.01...0.2, step: 0.01)
                    Text("\(Int(model.volumeStep * 100))%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                Text("Audio delay is unavailable with the AVFoundation engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Controls") {
                Picker("Control bar layout", selection: $model.controlBarLayout) {
                    ForEach(ControlBarLayout.allCases, id: \.self) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                Text("Automatic chooses the compact layout when the window is tight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Hide controls while playing", isOn: $model.autoHideControls)
                if model.autoHideControls {
                    Slider(value: $model.controlsHideDelay, in: 1...8, step: 0.5) {
                        Text("Hide delay")
                    } minimumValueLabel: {
                        Text("1s")
                    } maximumValueLabel: {
                        Text("8s")
                    }
                }
            }
            Section("Shortcuts") {
                Text("Space play/pause · Left/Right seek · Up/Down volume · M mute · S subtitles · L loop · F full screen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}

struct PlaybackControls: View {
    @ObservedObject var model: PlayerViewModel

    var body: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { model.pendingSeekTime ?? model.state.currentTime },
                    set: { model.updatePendingSeek($0) }
                ),
                in: 0...max(model.state.duration, 1),
                onEditingChanged: { editing in
                    if editing { model.beginSeek() } else { model.commitSeek() }
                }
            )
                .tint(.pink)
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(format(model.pendingSeekTime ?? model.state.currentTime)) of \(format(model.state.duration))")
                .help("Playback position")

            transportRow
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Keep the rail compact and dark in both macOS appearance modes so the
        // controls remain legible over bright video frames.
        .frame(maxWidth: 520)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var transportRow: some View {
        switch model.controlBarLayout {
        case .regular:
            regularTransportRow
        case .compact:
            compactTransportRow
        case .automatic:
            // Prefer the complete rail, but fall back to a genuinely compact
            // row when the window is narrow instead of letting controls push
            // against the edges or wrap unpredictably.
            ViewThatFits(in: .horizontal) {
                regularTransportRow
                compactTransportRow
            }
        }
    }

    @ViewBuilder
    private var regularTransportRow: some View {
        HStack(spacing: 10) {
            transportButtons(includeQueueNavigation: true)
            timeReadout
            Spacer(minLength: 8)
            volumeAndOptions(includeSlider: true)
        }
    }

    @ViewBuilder
    private var compactTransportRow: some View {
        HStack(spacing: 8) {
            transportButtons(includeQueueNavigation: false)
            timeReadout
            Spacer(minLength: 4)
            volumeAndOptions(includeSlider: false)
        }
    }

    private var timeReadout: some View {
        Text("\(format(model.pendingSeekTime ?? model.state.currentTime)) / \(format(model.state.duration))")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Playback time")
    }

    private func transportButtons(includeQueueNavigation: Bool) -> some View {
        HStack(spacing: 5) {
            if includeQueueNavigation {
                controlButton("backward.end.fill", label: "Previous item", action: model.playPrevious)
            }
            controlButton("gobackward.10", label: "Seek backward", action: { model.seek(to: model.state.currentTime - model.seekStep * 2) })
            Button(action: model.togglePlayback) {
                Image(systemName: model.state.status == .playing ? "pause.fill" : "play.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PlaybackIconButtonStyle())
            .accessibilityLabel(model.state.status == .playing ? "Pause" : "Play")
            .help(model.state.status == .playing ? "Pause" : "Play")
            controlButton("goforward.10", label: "Seek forward", action: { model.seek(to: model.state.currentTime + model.seekStep * 2) })
            if includeQueueNavigation {
                controlButton("forward.end.fill", label: "Next item", action: model.playNext)
            }
        }
    }

    @ViewBuilder
    private func volumeAndOptions(includeSlider: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: model.toggleMute) {
                Image(systemName: model.state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(PlaybackIconButtonStyle())
            .accessibilityLabel(model.state.isMuted ? "Unmute" : "Mute")
            .help(model.state.isMuted ? "Unmute" : "Mute")
            if includeSlider {
                Slider(value: Binding(get: { Double(model.state.volume) }, set: { model.setVolume($0) }), in: 0...1)
                    .frame(width: 72)
                    .tint(.pink)
                    .accessibilityLabel("Volume")
                    .help("Volume")
            }
            Menu {
                playbackMenu
                Divider()
                audioMenu
                subtitleMenu
                Divider()
                pictureMenu
            } label: {
                Label("Playback options", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(.white)
            .accessibilityLabel("Playback options")
            .help("Playback options")
        }
    }

    @ViewBuilder
    private var playbackMenu: some View {
        Menu("Playback speed") {
            ForEach([0.5, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button {
                    model.setRate(Float(rate))
                } label: {
                    Label("\(rate, specifier: "%.2g")×", systemImage: abs(model.state.rate - Float(rate)) < 0.01 ? "checkmark" : "")
                }
            }
        }
        Menu("Playback order") {
            ForEach(PlaybackOrder.allCases, id: \.self) { order in
                Button {
                    model.setPlaybackOrder(order)
                } label: {
                    Label(order.title, systemImage: model.playbackOrder == order ? "checkmark" : "")
                }
            }
        }
        Menu("Queue") {
            if model.queue.items.isEmpty {
                Text("Queue is empty")
            } else {
                ForEach(Array(model.queue.items.enumerated()), id: \.element.id) { index, item in
                    Menu {
                        Button("Play") { model.selectQueueItem(index) }
                        Button("Remove") { model.removeQueueItem(index) }
                    } label: {
                        HStack {
                            Text(item.url.lastPathComponent)
                            if let duration = item.duration { Text(format(duration)).foregroundStyle(.secondary) }
                            if index == model.queue.currentIndex { Image(systemName: "checkmark") }
                        }
                    }
                }
                Divider()
                Button("Clear Queue") { model.clearQueue() }
            }
        }
    }

    @ViewBuilder
    private var audioMenu: some View {
        if !model.state.audioTracks.isEmpty {
            Menu("Audio track") {
                ForEach(model.state.audioTracks) { track in
                    Button {
                        model.selectAudioTrack(track.id)
                    } label: {
                        Label(track.name, systemImage: model.state.selectedAudioTrackID == track.id ? "checkmark" : "")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subtitleMenu: some View {
        Menu("Subtitles") {
            Button {
                model.turnSubtitlesOff()
            } label: {
                Label("Off", systemImage: model.state.selectedSubtitleTrackID == nil && !model.isExternalSubtitleEnabled ? "checkmark" : "")
            }
            Button("Open Subtitle…") { model.openSubtitle() }
            if !model.state.subtitleTracks.isEmpty {
                Divider()
                ForEach(model.state.subtitleTracks) { track in
                    Button {
                        model.selectSubtitleTrack(track.id)
                    } label: {
                        Label(track.name, systemImage: model.state.selectedSubtitleTrackID == track.id ? "checkmark" : "")
                    }
                }
            }
            Divider()
            Button("External Delay -0.5s") { model.setSubtitleDelay(model.subtitleDelay - 0.5) }
                .disabled(model.externalSubtitleURL == nil)
            Button("External Delay 0s") { model.setSubtitleDelay(0) }
                .disabled(model.externalSubtitleURL == nil)
            Button("External Delay +0.5s") { model.setSubtitleDelay(model.subtitleDelay + 0.5) }
                .disabled(model.externalSubtitleURL == nil)
            Divider()
            Menu("Text Size") {
                Button("Small") { model.setSubtitleFontSize(18) }
                Button("Medium") { model.setSubtitleFontSize(24) }
                Button("Large") { model.setSubtitleFontSize(32) }
            }
            Menu("Text Color") {
                ForEach(SubtitleColor.allCases, id: \.self) { color in
                    Button(color.title) { model.subtitleColor = color }
                }
            }
            Menu("Position") {
                Button("Low") { model.setSubtitleBottomPadding(64) }
                Button("Center") { model.setSubtitleBottomPadding(108) }
                Button("High") { model.setSubtitleBottomPadding(160) }
            }
        }
    }

    @ViewBuilder
    private var pictureMenu: some View {
        Menu("Picture") {
            ForEach(VideoDisplayMode.allCases, id: \.self) { mode in
                Button {
                    model.displayMode = mode
                } label: {
                    Label(mode.title, systemImage: model.displayMode == mode ? "checkmark" : "")
                }
            }
            Divider()
            ForEach(VideoRotation.allCases, id: \.self) { rotation in
                Button {
                    model.rotation = rotation
                } label: {
                    Label(rotation.title, systemImage: model.rotation == rotation ? "checkmark" : "")
                }
            }
            if model.pictureInPicture.isSupported {
                Divider()
                Button("Picture in Picture") { model.togglePictureInPicture() }
            }
        }
    }

    private func controlButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(PlaybackIconButtonStyle())
        .accessibilityLabel(label)
        .help(label)
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        if total >= 3600 {
            return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct PlaybackIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? .white : .white.opacity(0.86))
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.white.opacity(0.2)
                            : Color.white.opacity(0.001)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.2 : 0), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension PlaybackOrder {
    var title: String {
        switch self {
        case .sequential: return "Play Once"
        case .singleLoop: return "Repeat Current"
        case .queueLoop: return "Repeat Queue"
        case .shuffle: return "Shuffle"
        }
    }
}

struct SubtitleOverlay: View {
    let text: String
    let fontSize: Double
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(color)
            .shadow(color: .black, radius: 0, x: 1, y: 1)
            .shadow(color: .black, radius: 3)
            .padding(.horizontal, 24)
            .frame(maxWidth: 900)
    }
}

enum SubtitleColor: String, CaseIterable, Hashable {
    case white
    case yellow
    case cyan

    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .white: return .white
        case .yellow: return .yellow
        case .cyan: return .cyan
        }
    }
}

enum VideoDisplayMode: String, CaseIterable, Hashable {
    case fit
    case fill
    case original

    var title: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .original: return "Original"
        }
    }
    var contentMode: ContentMode {
        switch self {
        case .fit, .original: return .fit
        case .fill: return .fill
        }
    }
    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fit, .original: return .resizeAspect
        case .fill: return .resizeAspectFill
        }
    }
}

enum ControlBarLayout: String, CaseIterable, Hashable {
    case automatic
    case compact
    case regular

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .compact: return "Compact"
        case .regular: return "Regular"
        }
    }
}

enum VideoRotation: String, CaseIterable, Hashable {
    case zero
    case clockwise90
    case halfTurn
    case counterClockwise90

    var title: String {
        switch self {
        case .zero: return "0°"
        case .clockwise90: return "90°"
        case .halfTurn: return "180°"
        case .counterClockwise90: return "270°"
        }
    }

    var angle: Angle {
        switch self {
        case .zero: return .degrees(0)
        case .clockwise90: return .degrees(90)
        case .halfTurn: return .degrees(180)
        case .counterClockwise90: return .degrees(270)
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let close: () -> Void
    let reopen: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).foregroundStyle(.white)
            Spacer()
            Button("Open Another", action: reopen).buttonStyle(.bordered)
            Button("Close", action: close).buttonStyle(.bordered)
        }
        .padding(12)
        .background(.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
        .padding(16)
    }
}

struct NoticeBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "info.circle.fill").foregroundStyle(.yellow)
            Text(message).foregroundStyle(.white)
            Spacer()
            Button("Dismiss", action: dismiss).buttonStyle(.bordered)
        }
        .padding(12)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 82)
    }
}

struct ResumeBanner: View {
    let position: TimeInterval
    let continueAction: () -> Void
    let restartAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Continue from \(format(position))?").foregroundStyle(.white)
            Button("Continue", action: continueAction).buttonStyle(.borderedProminent)
            Button("Start Over", action: restartAction).buttonStyle(.bordered)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 92)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
