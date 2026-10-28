import AVFoundation
import AVKit
import AppKit
import Combine
import SakuraPlayerCore
import SwiftUI
import UniformTypeIdentifiers

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
