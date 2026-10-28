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
        let supersededLoad = Task { try? await engine.load(url: url) }
        await Task.yield()
        try await engine.load(url: url)
        _ = await supersededLoad.value
        guard engine.state.mediaURL == url, engine.state.duration > 0 else {
            throw CheckFailure.engine
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
    }
}
