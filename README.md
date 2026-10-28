# Sakura Player

<img src="Assets/AppIcon.png" width="160" alt="Sakura Player app icon">

Sakura Player is a native macOS local video player focused on a quiet, responsive viewing experience. The first implementation uses SwiftUI/AppKit for the UI and an `AVFoundation` playback engine behind a small `PlayerEngine` abstraction.

[Source code](https://github.com/yueseqaz/sakura-player) · [Builds and checks](https://github.com/yueseqaz/sakura-player/actions) · [Report an issue](https://github.com/yueseqaz/sakura-player/issues)

> Development status: active early development. The current tree contains a playable foundation (open/drop media, multi-file queue, seeking, volume, mute, speed, embedded track selection, history persistence and subtitle discovery). Format coverage and long-running media tests are still being measured; see `docs/`.

## Requirements

- macOS 13 or later (Apple Silicon is the primary target)
- Xcode 15 or later for the native app target and UI previews
- Swift 6 toolchain

The checked-in package builds the native app and deterministic checks with the Command Line Tools. Full Xcode is still recommended for previews, Instruments, UI testing and signing.

## Build and run

```bash
./scripts/build.sh       # release build of SakuraPlayer
./scripts/test.sh        # core checks and package validation
./scripts/format-check.sh # generated container/codec smoke matrix
./scripts/check-mpv-evaluation.sh # inspect local libmpv availability without installing it
./scripts/package.sh     # creates a local unsigned SakuraPlayer.app
```

Launch the generated development app with `open dist/SakuraPlayer.app` (or double-click it in Finder). It is unsigned, so macOS may require Control-click > Open on first launch. No account, network service, or telemetry is required.

Packaging converts the user-provided `Assets/AppIcon.png` into the native multi-resolution `AppIcon.icns` with Apple's `sips` and `iconutil`. The original artwork is preserved without background removal or redrawing. GitHub Actions artifacts are development builds, not signed or notarized releases.

## Current controls

- `Space`: play/pause
- `Cmd-O`: open a local media file
- `Cmd-W`: close the current file
- Left/right arrow: seek 5 seconds; on-screen seek buttons: 10 seconds
- Up/down arrow: volume; `M`: mute
- `S`: toggle subtitles; `[`/`]`: external subtitle delay; `L`: cycle playback order; `,`/`.`: adjust playback rate
- `Cmd-O` accepts multiple files and creates a temporary queue
- Dragging multiple local media files into the window loads them as one temporary queue
- Same-directory discovery includes common audio containers (`m4a`, `mp3`, `flac`, `ogg`, `opus`, `wav`, `aiff`, `caf`)
- Opening one media file automatically queues other supported videos in the same directory
- The `Queue` menu lets you select or clear queued items
- The `Queue` menu marks the current item and shows durations after each item has loaded
- `File > Open Recent` shows locally stored playback history; `Clear Recent` removes it
- Launching the app with one or more readable file paths opens them as a queue
- When a saved position exists, the player offers `Continue` or `Start Over` (configurable in Settings)
- Playback speed menu: 0.1x to 32x on a shared set of readable rate marks
- Settings exposes a logarithmic playback-rate scale from 0.1x to 32x, so slow motion and fast-forward remain equally usable
- The selected playback rate is restored for the next media file and launch
- The Subtitles menu can load SRT/WebVTT/ASS/SSA files, turn subtitles off, and apply a quick external-subtitle timing offset
- Settings also provide a precise -10s to +10s subtitle-delay slider and reset action
- Embedded audio/subtitle track choices are remembered per local media path
- Audio-delay adjustment is not exposed yet: AVPlayer has no supported per-item delay API, and this remains an engine-evaluation gate
- Subtitle appearance includes size, color and vertical-position presets
- `Sakura Player > Settings…` exposes playback-order and subtitle preferences
- `Esc` exits full screen when the player window is in full-screen mode
- Settings also include volume-key step, control auto-hide delay and keyboard shortcut reference
- Arrow-key seek step is configurable from 1 to 30 seconds
- Picture settings include fit/fill/original-size modes and 90°/180°/270° rotation; Fill is the default so window resizing does not expose a hard black strip
- Picture in Picture is available when the current macOS environment reports native support
- Window size and position are restored when the saved frame still intersects a connected display
- `Window > Diagnostics…` opens a copyable report with local file paths omitted
- While playing, controls fade out after a short period without pointer activity and reappear on movement
- Drag a local file onto the player window

## Privacy

Media stays on the local machine. Playback history is stored in the user's Application Support directory and is never uploaded. Logs and diagnostics must not include full personal paths by default.

## Known limitations

- The AVFoundation adapter currently rejects some MKV, AVI, WebM and AV1 combinations; see the measured matrix in `docs/FORMAT_COMPATIBILITY.md`.
- ASS/SSA styling, embedded-subtitle timing shifts and per-item audio delay require a future playback engine with a dedicated subtitle/audio pipeline; basic ASS/SSA timing and text are supported.
- Shortcut remapping and system media-key integration are not yet exposed; the built-in shortcuts are listed above and in Settings.
- Signing, notarization, Instruments measurements and full UI acceptance require a full Xcode installation and a physical target Mac.

## Documentation

- `docs/ARCHITECTURE.md` - module boundaries and state flow
- `docs/ENGINE_EVALUATION.md` - playback-engine investigation and measurements
- `docs/FORMAT_COMPATIBILITY.md` - measured media matrix and remaining compatibility gaps
- `docs/TEST_PLAN.md` - automated and manual acceptance checks
- `docs/LONG_PLAYBACK_TEST.zh-CN.md` - user-run two-hour playback checks and report template
- `docs/RELEASE.md` - signing, packaging and release checklist
- `CHANGELOG.md` - user-visible changes

GitHub Actions runs the package manifest check, app/core build, deterministic core checks, and unsigned app packaging on macOS. A command-line test log and development app are uploaded as workflow artifacts. Full UI and Instruments validation still requires a checked-out Xcode environment and a real Mac session.

## License

Sakura Player source code is released under the MIT License. See `LICENSE`. AVFoundation/AVKit are Apple system frameworks and remain subject to Apple's terms.

The optional `scripts/test-mpv.sh` probe uses an explicitly supplied external runtime and official headers for development measurements only. libmpv is not currently bundled or used by the app; a successful probe does not expand the app's advertised format support. See `docs/ENGINE_EVALUATION.md` for results and remaining integration/license gates.
