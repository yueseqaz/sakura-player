import AVFoundation
import AVKit
import AppKit
import Combine
import SakuraPlayerCore
import SwiftUI
import UniformTypeIdentifiers

struct PlaybackControls: View {
    @ObservedObject var model: PlayerViewModel

    var body: some View {
        VStack(spacing: 8) {
            PlaybackTimelineSlider(timeline: model.timeline, model: model)

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
        PlaybackTimeReadout(timeline: model.timeline)
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
            ForEach(PlaybackRateScale.ticks, id: \.self) { rate in
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
                            if let duration = item.duration { Text(playbackTime(duration)).foregroundStyle(.secondary) }
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

}

private struct PlaybackTimelineSlider: View {
    @ObservedObject var timeline: PlaybackTimelineModel
    let model: PlayerViewModel

    var body: some View {
        Slider(
            value: Binding(
                get: { timeline.position.displayedTime },
                set: { model.updatePendingSeek($0) }
            ),
            in: 0...max(timeline.position.duration, 1),
            onEditingChanged: { editing in
                if editing { model.beginSeek() } else { model.commitSeek() }
            }
        )
        .tint(.pink)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(playbackTime(timeline.position.displayedTime)) of \(playbackTime(timeline.position.duration))")
        .help("Playback position")
    }
}

private struct PlaybackTimeReadout: View {
    @ObservedObject var timeline: PlaybackTimelineModel

    var body: some View {
        Text("\(playbackTime(timeline.position.displayedTime)) / \(playbackTime(timeline.position.duration))")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Playback time")
    }
}

private func playbackTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else { return "--:--" }
    let total = Int(max(0, seconds).rounded(.down))
    if total >= 3600 {
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
    return String(format: "%02d:%02d", total / 60, total % 60)
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
