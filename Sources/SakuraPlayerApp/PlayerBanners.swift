import AVFoundation
import AVKit
import AppKit
import Combine
import SakuraPlayerCore
import SwiftUI
import UniformTypeIdentifiers

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
