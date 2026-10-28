# Test plan

## Automated checks

`SakuraPlayerCoreChecks` verifies history round-tripping and same-basename subtitle discovery without external dependencies:

```bash
swift build --target SakuraPlayerCoreChecks
swift run SakuraPlayerCoreChecks
```

When `ffmpeg` is available, `scripts/test.sh` also generates one-second H.264/AAC and H.264-without-audio fixtures and loads each through `AVPlayerEngine` via `SAKURA_MEDIA_FIXTURE`. The checks also cover missing-file errors, superseded concurrent loads, the explicit audio-delay capability boundary and SRT/WebVTT parsing. Generated files are temporary and are not committed.

Run `./scripts/format-check.sh` to generate short MP4, MOV, M4V, AVI, MPEG-TS, MKV, WebM, HEVC, AV1 and audio-only AAC/MP3/ALAC/FLAC/Opus fixtures and print the current AVFoundation compatibility results.

Once full Xcode is installed, add XCTest/UI-test targets and run `xcodebuild test` on a macOS destination. The current Command Line Tools installation can build the app but does not provide a working Swift Testing macro plugin, so the deterministic executable checks remain the local fallback.

The package intentionally uses `SakuraPlayerCoreChecks` instead of a SwiftPM test target for now: this host's Command Line Tools ships the Testing module but not its macro implementation, causing `swift test` to fail before any test body runs.

GitHub Actions additionally validates the package manifest, builds both the executable product and app target, uploads the core-check log, and archives the unsigned development app. There is no UI-test target yet because this repository is currently built with SwiftPM and the local Command Line Tools environment does not provide a stable AppKit UI-test runner; UI acceptance remains an explicit manual gate on a full Xcode Mac.

## Media matrix

Prepare legal or self-generated samples for MP4/H.264/AAC 1080p, HEVC 1080p/4K, high and variable frame rates, HDR/SDR, MKV with multiple tracks, SRT/VTT/ASS, no-audio/no-subtitle, long duration, corrupted/truncated files and filenames containing spaces, Unicode and special characters.

## Manual acceptance

- Open, drag one or more files, pause, resume, seek, close and quickly switch files.
- Launch the app cold with a media URL from Finder/Launch Services and verify it opens without first showing the idle screen.
- Open multiple files and verify next/previous, sequential, single-repeat, queue-repeat and shuffle behavior.
- Open a single episode/movie and verify supported neighboring files in the same directory are queued in natural order.
- Verify the Queue menu can select, remove and clear queued items.
- Verify the selected playback order is applied immediately after relaunching the app.
- Verify volume, mute, playback-rate changes, end-of-file state, embedded audio/subtitle track selection and error recovery.
- Relaunch a file after changing its embedded track and verify the selection is restored.
- Verify subtitle discovery, window/full-screen behavior, multi-display changes, sleep/wake and audio-device changes.
- Verify fit/fill display modes and 90°/180°/270° rotation on portrait and landscape media.
- Verify Picture in Picture starts/stops when supported and does not affect normal playback when unavailable.
- Verify controls fade during playback and reappear when the pointer moves.
- Verify volume-step and control auto-hide preferences persist after relaunch.
- Verify window size/position restoration after relaunch and after disconnecting the saved display.
- Open `Window > Diagnostics…`, copy the report, and verify it contains no absolute media path.
- Verify the configurable arrow-key seek step changes keyboard seek behavior.
- Verify the selected playback rate survives a relaunch and applies to newly opened media.
- Verify `S`, `[`, `]`, `L`, `,` and `.` shortcuts work in both windowed and full-screen playback.
- Verify `F` enters full screen and `Esc` exits it without changing the saved window frame.
- Run a two-hour playback and inspect CPU, memory and A/V sync with Instruments.
- Verify history survives relaunch and gracefully ignores moved/deleted files.
- Verify the resume prompt offers Continue/Start Over and can be disabled in Settings.
