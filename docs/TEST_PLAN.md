# Test plan

## Automated checks

`SakuraPlayerCoreChecks` verifies history round-tripping and same-basename subtitle discovery without external dependencies:

```bash
swift build --target SakuraPlayerCoreChecks
swift run SakuraPlayerCoreChecks
```

When `ffmpeg` is available, `scripts/test.sh` also generates one-second H.264/AAC and H.264-without-audio fixtures plus a two-second audio-only AAC fixture, then loads each through `AVPlayerEngine` via `SAKURA_MEDIA_FIXTURE`. The checks also cover missing-file errors, superseded concurrent loads, the explicit audio-delay capability boundary and SRT/WebVTT parsing. Generated files are temporary and are not committed.

Engine regressions additionally cover mute/volume consistency, playback settings across item changes, non-finite inputs, invalid track IDs, rapid latest-wins seeks, explicit end targets, replay, closing with a pending seek, load cancellation and engine deallocation while retaining the AVPlayer to verify item teardown. AAC end seeks can land on the final packet slightly before duration, so an explicit completed end target is represented as ended rather than stranded paused. Subtitle checks cover disabled cues and the positive-delay-means-later convention.

Run `./scripts/format-check.sh` to generate short MP4, MOV, M4V, AVI, MPEG-TS, MKV, WebM, HEVC, AV1 and audio-only AAC/MP3/ALAC/FLAC/Opus fixtures and print the current AVFoundation compatibility results.

Both engine probes use `scripts/generate-format-fixtures.sh` for the approximately two-second matrix and a two-audio-track ASS MKV. `scripts/test-mpv.sh` is an explicit opt-in development probe requiring a supplied runtime and official headers; see `ENGINE_EVALUATION.md`. Unsupported AVFoundation formats remain measured results, but a crashed check process makes the matrix script fail.

`SakuraPlayerPresentationTests` is an XCTest target covering clock-only updates not invalidating the window model, drag previews surviving clock ticks and repeated begin events, clamping, and preview cleanup on close. Run `swift test` with full Xcode. The local Command Line Tools host compiled the updated app but cannot resolve the XCTest module, so XCTest execution is delegated to GitHub's full-Xcode runner. The dependency-free `SakuraPlayerCoreChecks` remains runnable locally; it does not replace the presentation tests or manual UI acceptance.

GitHub Actions additionally validates the package manifest, builds both the executable product and app target, runs `swift test`, uploads the core/presentation logs, and archives the unsigned development app. Presentation tests use isolated temporary history and UserDefaults suites rather than personal preferences. There is no automated UI-test target yet; native-slider behavior, actual redraw performance and UI acceptance remain explicit manual/Instruments gates on a full Xcode Mac.

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
- Run a two-hour playback and inspect CPU, memory and A/V sync. **Delegated to the user, not yet verified:** follow [the Chinese step-by-step guide](LONG_PLAYBACK_TEST.zh-CN.md). Activity Monitor is sufficient for initial reporting; Instruments remains the developer follow-up for suspicious trends.
- Verify history survives relaunch and gracefully ignores moved/deleted files.
- Verify the resume prompt offers Continue/Start Over and can be disabled in Settings.
