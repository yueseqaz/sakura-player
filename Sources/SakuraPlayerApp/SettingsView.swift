import AVFoundation
import AVKit
import AppKit
import Combine
import SakuraPlayerCore
import SwiftUI
import UniformTypeIdentifiers

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
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Playback rate")
                        Spacer(minLength: 12)
                        Text("\(model.state.rate, specifier: "%.3g")×")
                            .font(.headline.monospacedDigit())
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    PlaybackRateSlider(
                        value: Binding(
                            get: { model.rateSliderDraftPosition ?? rateSliderPosition(for: model.state.rate) },
                            set: {
                                // Keep the thumb local while AVPlayer publishes its
                                // state so a drag never jumps back under the pointer.
                                model.rateSliderDraftPosition = $0
                                model.setRate(rate(for: $0))
                            }
                        ),
                        onEditingChanged: { editing in
                            if !editing { model.rateSliderDraftPosition = nil }
                        }
                    )
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
        .frame(width: 520)
        .padding()
        .onDisappear { model.rateSliderDraftPosition = nil }
    }

    private func rateSliderPosition(for rate: Float) -> Double {
        let minimum = log10(Double(PlaybackRateScale.minimum))
        let maximum = log10(Double(PlaybackRateScale.maximum))
        let value = log10(Double(PlaybackRateScale.clamp(rate)))
        return min(max((value - minimum) / (maximum - minimum), 0), 1)
    }

    private func rate(for position: Double) -> Float {
        let minimum = log10(Double(PlaybackRateScale.minimum))
        let maximum = log10(Double(PlaybackRateScale.maximum))
        let clamped = min(max(position, 0), 1)
        return PlaybackRateScale.clamp(Float(pow(10, minimum + clamped * (maximum - minimum))))
    }
}

/// A full-width rate control whose track and labels share one coordinate system.
/// The native Slider's intrinsic width is platform-dependent, which can make a
/// separately drawn tick row drift away from the visible track.
private struct PlaybackRateSlider: View {
    @Binding var value: Double
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 10
            let trackWidth = max(proxy.size.width - inset * 2, 1)
            let thumbX = inset + CGFloat(min(max(value, 0), 1)) * trackWidth

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: trackWidth, height: 5)
                    .position(x: inset + trackWidth / 2, y: 12)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(thumbX - inset, 2), height: 5)
                    .position(x: inset + max(thumbX - inset, 2) / 2, y: 12)

                ForEach(Array(PlaybackRateScale.ticks.enumerated()), id: \.offset) { index, tick in
                    let x = inset + CGFloat(rateSliderPosition(for: tick)) * trackWidth
                    Rectangle()
                        .fill(Color.secondary.opacity(0.72))
                        .frame(width: 1, height: 7)
                        .position(x: x, y: 12)
                    Text("\(tick, specifier: "%.3g")×")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: x, y: index.isMultiple(of: 2) ? 29 : 46)
                }

                Circle()
                    .fill(Color(nsColor: .controlAccentColor))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1))
                    .position(x: thumbX, y: 12)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onEditingChanged(true)
                        let x = min(max(gesture.location.x, inset), inset + trackWidth)
                        value = Double((x - inset) / trackWidth)
                    }
                    .onEnded { _ in onEditingChanged(false) }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .accessibilityElement()
        .accessibilityLabel("Playback rate")
        .accessibilityValue(Text("\(rate(for: value), specifier: "%.3g") times"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + 0.02, 1)
            case .decrement:
                value = max(value - 0.02, 0)
            @unknown default:
                break
            }
        }
    }

    private func rateSliderPosition(for rate: Float) -> Double {
        let minimum = log10(Double(PlaybackRateScale.minimum))
        let maximum = log10(Double(PlaybackRateScale.maximum))
        let value = log10(Double(PlaybackRateScale.clamp(rate)))
        return min(max((value - minimum) / (maximum - minimum), 0), 1)
    }

    private func rate(for position: Double) -> Float {
        let minimum = log10(Double(PlaybackRateScale.minimum))
        let maximum = log10(Double(PlaybackRateScale.maximum))
        let clamped = min(max(position, 0), 1)
        return PlaybackRateScale.clamp(Float(pow(10, minimum + clamped * (maximum - minimum))))
    }
}
