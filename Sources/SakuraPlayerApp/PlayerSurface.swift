import AVFoundation
import AVKit
import AppKit
import Combine
import SakuraPlayerCore
import SwiftUI
import UniformTypeIdentifiers

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
