# Playback engine evaluation

Date: 2026-10-28

## Environment

- Host: Apple Silicon macOS host
- Swift: 6.4.0.34.1
- Xcode: not installed; active developer directory is CommandLineTools
- macOS SDK exposed by the toolchain: MacOSX27.0.sdk

## Current result

The initial adapter is `AVFoundation` (`AVPlayerEngine.swift`). It gives native window integration, hardware-decoding decisions to the OS, and no additional redistribution dependency. The code is intentionally behind `PlayerEngine` so a libmpv adapter can be integrated after the development probe passes the remaining gates.

No representative real-world media fixture set is checked into this repository yet, so the container/codec, HDR, hardware-decoding, first-frame, seek-latency, CPU, memory and bundle-size fields are **not claimed**. They must be measured on real target Macs before release. The SwiftPM app target now builds on this host; install full Xcode before collecting UI-test and Instruments measurements.

The deterministic check generates a one-second 320x180 H.264/AAC MP4 with ffmpeg and verifies that `AVPlayerEngine.load` reaches `readyToPlay` and reports a positive duration. This is an engine smoke test, not a broad compatibility claim.

The generated local matrix currently opens MP4/M4V/MOV/MPEG-TS H.264 samples, MP4 HEVC/AAC, and audio-only AAC, MP3, ALAC, FLAC and Opus fixtures. The same AVFoundation adapter rejects generated MKV H.264/AAC, AVI H.264/MP3, WebM VP9/Opus and MKV AV1/AAC fixtures; those failures are recorded rather than hidden and are the primary reason libmpv remains a release-gate evaluation.

AVPlayer supports selecting audio media options and changing volume, but it does not expose a supported per-item audio presentation delay. The current UI intentionally omits that control rather than applying an inaccurate approximation; a future engine choice must add delay and A/V-sync coverage together.

An early local arm64 release build, before the app icon was added, measured approximately 1.3 MB for the unsigned `.app` bundle (1,386,128-byte executable; no bundled third-party runtime) and took 7.66 seconds wall-clock on this host. These are development-machine measurements, not release size or startup/first-frame guarantees.

## libmpv decision gate

Before adding libmpv, measure the format matrix and compare package size, startup time, HDR behavior, subtitle fidelity, hardware decode and GPL/LGPL obligations. Do not claim broad format support based on file extensions.

The local probe (`scripts/check-mpv-evaluation.sh`) found no installed `libmpv` pkg-config module. Homebrew metadata reports `mpv` 0.41.0, licensed `GPL-2.0-or-later AND LGPL-2.1-or-later`, with a large FFmpeg/libass/libplacebo dependency set; the formula is not installed. The probe does not install packages or change the machine.

## Executed libmpv client/render probe (2026-10-28)

A separate C executable (`tools/mpv-probe.c`, launched by `scripts/test-mpv.sh`) now exercises the real client and software render APIs. It is not part of the Swift package or the distributed app. A Homebrew installation attempt was stopped during downloads when it proposed upgrading the existing FFmpeg and other dependencies; no packages were installed by that attempt.

For this local-only experiment, the explicitly supplied runtime was the already-installed IINA 1.5.0 `libmpv.2.dylib`, reporting **mpv v0.41.0 / client API 2.5**. No IINA code, artwork, headers or binaries were copied into this repository or app. This is a reference runtime measurement, **not** a reproducible redistribution recipe or permission to bundle IINA's libraries.

- Host: arm64, macOS 27.0.1 (26A434), Command Line Tools / Swift 6.4.
- Runtime SHA-256: `64247b1b41eabfa3b24e579cb747f098bf6852f2dd727a856db3f2ebd89af6e8`.
- Official v0.41.0 headers were fetched outside the repo. `client.h` SHA-256: `3c073236a09cb456c6e80587d5523c8771c32fb22ca014e0f99cc3d43905b75c`; `render.h`: `192691941602052f00df0587f126246c48785a1cf21de68d22a92ea1908d1c55`.
- Configuration: user config/scripts/network helper disabled, software rendering to a 320x180 RGB buffer, `hwdec=no`, `ao=null`, generated approximately two-second local fixtures. No audible output, display, HDR or hardware-decode result is implied.
- **15/15 fixtures passed** loading, positive duration, decoder initialization and an exact seek. Includes the 14 container/codec fixtures in the shared generator plus one H.264 MKV with two AAC tracks and ASS subtitles.
- Audio/subtitle delay property round-trips passed for positive, negative and zero offsets. This verifies API capability, **not audible synchronization**.
- The multi-track fixture selected audio ID 2 and read it back. ASS text was present at 0.5 seconds, and disabling its visibility changed 1,656 rendered buffer bytes. This proves basic libass rendering, not full styling fidelity.
- Observed file-loaded times were 0.005–0.008 s; exact-seek event times were 0.000–0.051 s in this run. These are warm tiny-fixture API-event measurements, **not app startup, visible first-frame latency, P95, or real-world seek guarantees**.

To reproduce against an independently built runtime and matching official headers:

```bash
SAKURA_MPV_LIBRARY=/absolute/path/to/libmpv.2.dylib \
SAKURA_MPV_INCLUDE=/absolute/path/to/directory/containing/mpv/headers \
./scripts/test-mpv.sh
```

The include directory must contain `client.h` and `render.h` directly. The script compiles a temporary executable with an rpath to the supplied runtime, generates legal fixtures, returns nonzero on any failed probe, and removes only its own temporary files. It never installs or downloads dependencies. Normal app builds/CI do not require libmpv.

### Decision after this probe

libmpv is technically promising for the measured compatibility gaps and real subtitle/audio-delay APIs. **Do not switch the production adapter yet.** Remaining gates:

1. Build a pinned standalone runtime/dependency set with recorded build flags, licenses, corresponding sources and redistribution obligations. A Homebrew formula license string is not a full dependency audit. Do not silently treat a GPL-enabled linked binary as MIT-only.
2. Embed a GPU-backed renderer in an AppKit window and measure resizing, Retina, rotation, full screen, teardown, event-thread dispatch and PiP tradeoffs. The software renderer is a test tool, not the planned production rendering path.
3. Verify VideoToolbox/hardware decoding, SDR/HDR/color handling and real-device A/V sync, including positive/negative delays, track changes and seek recovery.
4. Measure 1080p/4K first visible frame, seek recovery, CPU, memory and final bundle size on target Macs. Run the two-hour acceptance separately (delegated to the user).

Primary references (v0.41.0): [client API](https://github.com/mpv-player/mpv/blob/v0.41.0/include/mpv/client.h), [render API and software-renderer limitations](https://github.com/mpv-player/mpv/blob/v0.41.0/include/mpv/render.h), [audio/subtitle delay options](https://github.com/mpv-player/mpv/blob/v0.41.0/DOCS/man/options.rst), [copyright and GPL/LGPL build caveats](https://github.com/mpv-player/mpv/blob/v0.41.0/Copyright).
