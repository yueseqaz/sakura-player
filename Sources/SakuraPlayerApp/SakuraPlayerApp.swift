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
                Button("Slower Playback") { model.adjustRate(direction: -1) }
                    .keyboardShortcut(",", modifiers: [])
                Button("Faster Playback") { model.adjustRate(direction: 1) }
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
