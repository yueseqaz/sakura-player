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
