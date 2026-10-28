import AVFoundation
import AVKit
import AppKit
import Combine
import SakuraPlayerCore
import SwiftUI
import UniformTypeIdentifiers

extension PlaybackOrder {
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
