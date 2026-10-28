import Foundation
import SakuraPlayerCore

@main
enum SakuraPlayerCoreChecks {
    static func main() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sakura-player-check-\(UUID().uuidString).json")
        let mediaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sakura-player-example-\(UUID().uuidString).mp4")
        try Data().write(to: mediaURL)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: mediaURL)
        }
        let history = PlaybackHistoryStore(fileURL: fileURL)
        await history.record(url: mediaURL, position: 42.5)
        guard await history.entry(for: mediaURL)?.lastPosition == 42.5 else {
            throw CheckFailure.history
        }
        try FileManager.default.removeItem(at: mediaURL)
        guard await history.allEntries().isEmpty else { throw CheckFailure.history }

        let subtitleDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sakura-player-subtitles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: subtitleDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: subtitleDirectory) }
        let videoURL = subtitleDirectory.appendingPathComponent("Movie.mkv")
        try Data().write(to: videoURL)
        try FileManager.default.createDirectory(at: subtitleDirectory.appendingPathComponent("Folder.mp4"), withIntermediateDirectories: true)
        try Data().write(to: subtitleDirectory.appendingPathComponent("Movie.srt"))
        let assText = "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:05.00,0:00:07.50,Default,,0,0,0,,{\\i1}ASS cue\\Nsecond line"
        let assURL = subtitleDirectory.appendingPathComponent("Movie.ass")
        try Data(assText.utf8).write(to: assURL)
        try Data().write(to: subtitleDirectory.appendingPathComponent("Other.srt"))
        try Data().write(to: subtitleDirectory.appendingPathComponent("Audio.mp3"))
        guard SubtitleDiscovery.subtitles(for: videoURL).count == 2 else {
            throw CheckFailure.subtitles
        }
        guard MediaFileDiscovery.playableFiles(in: subtitleDirectory).count == 2 else {
            throw CheckFailure.queue
        }

        let first = URL(fileURLWithPath: "/tmp/first.mp4")
        let second = URL(fileURLWithPath: "/tmp/second.mp4")
        var queue = PlaybackQueue(items: [QueueItem(url: first), QueueItem(url: second)])
        guard queue.current?.url == first, queue.advance()?.url == second else {
            throw CheckFailure.queue
        }
        queue.order = .queueLoop
        guard queue.advance()?.url == first else { throw CheckFailure.queue }
        queue.updateDuration(at: 0, duration: 12.5)
        guard queue.items[0].duration == 12.5 else { throw CheckFailure.queue }

        let cues = SubtitleParser.parse(text: "1\n00:00:01,000 --> 00:00:02,500\nHello <i>world</i>\n")
        guard cues.count == 1, cues[0].start == 1, cues[0].end == 2.5, cues[0].text == "Hello world" else {
            throw CheckFailure.subtitles
        }
        guard SubtitleCue.active(in: cues, at: 1.25) == cues[0],
              SubtitleCue.active(in: cues, at: 1.25, delay: 0.5) == nil,
              SubtitleCue.active(in: cues, at: 2.75, delay: 0.5) == cues[0],
              SubtitleCue.active(in: cues, at: 0.75, delay: -0.5) == cues[0],
              SubtitleCue.active(in: cues, at: 1.25, enabled: false) == nil,
              SubtitleCue.active(in: cues, at: .nan) == nil else { throw CheckFailure.subtitles }
        let webVTT = SubtitleParser.parse(text: "WEBVTT\n\n00:00:03.000 --> 00:00:04.000\nVTT cue\n")
        guard webVTT.count == 1, webVTT[0].text == "VTT cue" else { throw CheckFailure.subtitles }
        let ass = SubtitleParser.parse(text: assText)
        guard ass.count == 1, ass[0].start == 5, ass[0].end == 7.5, ass[0].text == "ASS cue\nsecond line" else {
            throw CheckFailure.subtitles
        }
        let assFromFile = try SubtitleParser.parse(url: assURL)
        guard assFromFile.count == ass.count,
              assFromFile[0].start == ass[0].start,
              assFromFile[0].end == ass[0].end,
              assFromFile[0].text == ass[0].text else { throw CheckFailure.subtitles }

        if let fixturePath = ProcessInfo.processInfo.environment["SAKURA_MEDIA_FIXTURE"] {
            do {
                try await verifyEngine(with: URL(fileURLWithPath: fixturePath))
                print("Media fixture passed: \(URL(fileURLWithPath: fixturePath).pathExtension)")
            } catch let error as PlayerEngineError {
                guard ProcessInfo.processInfo.environment["SAKURA_ALLOW_UNSUPPORTED_FIXTURE"] == "1" else { throw error }
                print("Media fixture unsupported or failed: \(error.localizedDescription)")
            }
        }
        try await verifyMissingMediaFails()
        print("SakuraPlayerCoreChecks passed")
    }

    @MainActor
    private static func verifyEngine(with url: URL) async throws {
        let engine = AVPlayerEngine()
        engine.setMuted(true)
        engine.setVolume(0.4)
        guard !engine.player.isMuted, !engine.state.isMuted else { throw CheckFailure.engine }
        engine.setMuted(true)
        engine.setRate(1.5)
        engine.setRate(0.05)
        guard engine.state.rate == PlaybackRateScale.minimum else { throw CheckFailure.engine }
        engine.setRate(40)
        guard engine.state.rate == PlaybackRateScale.maximum else { throw CheckFailure.engine }
        engine.setRate(1.5)
        let supersededLoad = Task { try? await engine.load(url: url) }
        await Task.yield()
        try await engine.load(url: url)
        _ = await supersededLoad.value
        guard engine.state.mediaURL == url, engine.state.duration > 0,
              engine.state.volume == 0.4, engine.state.isMuted, engine.state.rate == 1.5,
              engine.player.isMuted, engine.player.volume == 0.4 else {
            throw CheckFailure.engine
        }
        let audioID = engine.state.selectedAudioTrackID
        let subtitleID = engine.state.selectedSubtitleTrackID
        engine.selectAudioTrack(id: Int.max)
        engine.selectSubtitleTrack(id: Int.max)
        guard engine.state.selectedAudioTrackID == audioID,
              engine.state.selectedSubtitleTrackID == subtitleID else { throw CheckFailure.engine }
        engine.setVolume(.nan)
        engine.setRate(.infinity)
        guard engine.state.volume == 0.4, engine.state.rate == 1.5 else { throw CheckFailure.engine }
        let target = engine.state.duration * 0.3
        engine.seek(to: engine.state.duration * 0.8)
        engine.seek(to: target)
        engine.seek(to: .nan)
        try await Task.sleep(for: .milliseconds(350))
        guard abs(engine.state.currentTime - target) < 0.3 else {
            throw CheckFailure.engineDetail("Latest seek did not win: expected \(target), actual \(engine.state.currentTime)")
        }
        engine.seek(to: engine.state.duration)
        try await Task.sleep(for: .milliseconds(350))
        guard engine.state.status == .ended else {
            throw CheckFailure.engineDetail("Seek to end: \(engine.state.status), time \(engine.state.currentTime), duration \(engine.state.duration)")
        }
        engine.play()
        try await Task.sleep(for: .milliseconds(100))
        guard engine.state.status == .playing, engine.state.currentTime < engine.state.duration * 0.8 else {
            throw CheckFailure.engineDetail("Replay: \(engine.state.status), time \(engine.state.currentTime), duration \(engine.state.duration)")
        }
        engine.seek(to: engine.state.duration * 0.8)
        engine.close()
        try await Task.sleep(for: .milliseconds(300))
        guard engine.state.status == .idle, engine.state.mediaURL == nil,
              engine.state.currentTime == 0, engine.state.audioTracks.isEmpty,
              engine.state.subtitleTracks.isEmpty else { throw CheckFailure.engine }
        engine.seek(to: 50)
        guard engine.state.currentTime == 0 else { throw CheckFailure.engine }

        let cancelled = Task { try await engine.load(url: url) }
        cancelled.cancel()
        do {
            try await cancelled.value
            throw CheckFailure.engine
        } catch is CancellationError {
            guard engine.player.currentItem == nil else { throw CheckFailure.engine }
        }
        do {
            try await engine.load(url: URL(fileURLWithPath: "/tmp/sakura-player-file-that-does-not-exist.mp4"))
            throw CheckFailure.engine
        } catch PlayerEngineError.failedToLoad {
            guard engine.state.status == .failed, engine.player.currentItem == nil else {
                throw CheckFailure.engine
            }
        }
        engine.close()
        try await verifyEngineRelease(with: url)
    }

    @MainActor
    private static func verifyEngineRelease(with url: URL) async throws {
        var engine: AVPlayerEngine? = AVPlayerEngine()
        weak var releasedEngine = engine
        let player = engine!.player
        try await engine!.load(url: url)
        engine = nil
        try await Task.sleep(for: .milliseconds(100))
        guard releasedEngine == nil, player.currentItem == nil else { throw CheckFailure.engine }
    }

    @MainActor
    private static func verifyMissingMediaFails() async throws {
        let engine = AVPlayerEngine()
        guard !engine.supportsAudioDelay else { throw CheckFailure.engine }
        do {
            try engine.setAudioDelay(0.5)
            throw CheckFailure.engine
        } catch PlayerEngineError.unsupportedFeature {
            // Expected until an engine with a real audio pipeline is selected.
        }
        do {
            try await engine.load(url: URL(fileURLWithPath: "/tmp/sakura-player-file-that-does-not-exist.mp4"))
            throw CheckFailure.engine
        } catch PlayerEngineError.failedToLoad {
            // Expected: errors are surfaced instead of crashing the app.
        }
        do {
            try await engine.load(url: URL(string: "https://example.com/video.mp4")!)
            throw CheckFailure.engine
        } catch PlayerEngineError.unsupportedURL {
            // Expected: the player is intentionally local-file only.
        }
    }

    private enum CheckFailure: Error {
        case history
        case subtitles
        case queue
        case engine
        case engineDetail(String)
    }
}
