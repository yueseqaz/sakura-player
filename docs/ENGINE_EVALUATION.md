# Playback engine evaluation

Date: 2026-10-28

## Environment

- Host: Apple Silicon macOS host
- Swift: 6.4.0.34.1
- Xcode: not installed; active developer directory is CommandLineTools
- macOS SDK exposed by the toolchain: MacOSX27.0.sdk

## Current result

The initial adapter is `AVFoundation` (`AVPlayerEngine.swift`). It gives native window integration, hardware-decoding decisions to the OS, and no additional redistribution dependency. The code is intentionally behind `PlayerEngine` so a libmpv adapter can be tested later.

No representative media fixture set is checked into this repository yet, so the container/codec, HDR, hardware-decoding, first-frame, seek-latency, CPU, memory and bundle-size fields are **not claimed**. They must be measured on real target Macs before release. The SwiftPM app target now builds on this host; install full Xcode before collecting UI-test and Instruments measurements.

The deterministic check generates a one-second 320x180 H.264/AAC MP4 with ffmpeg and verifies that `AVPlayerEngine.load` reaches `readyToPlay` and reports a positive duration. This is an engine smoke test, not a broad compatibility claim.

The generated local matrix currently opens MP4/M4V/MOV/MPEG-TS H.264 samples, MP4 HEVC/AAC, and audio-only AAC, MP3, ALAC, FLAC and Opus fixtures. The same AVFoundation adapter rejects generated MKV H.264/AAC, AVI H.264/MP3, WebM VP9/Opus and MKV AV1/AAC fixtures; those failures are recorded rather than hidden and are the primary reason libmpv remains a release-gate evaluation.

AVPlayer supports selecting audio media options and changing volume, but it does not expose a supported per-item audio presentation delay. The current UI intentionally omits that control rather than applying an inaccurate approximation; a future engine choice must add delay and A/V-sync coverage together.

The current local arm64 release build measured approximately 1.3 MB for the unsigned `.app` bundle (1,386,128-byte executable; no bundled third-party runtime) and took 7.66 seconds wall-clock on this host. These are development-machine measurements, not release size or startup/first-frame guarantees.

## libmpv decision gate

Before adding libmpv, measure the format matrix and compare package size, startup time, HDR behavior, subtitle fidelity, hardware decode and GPL/LGPL obligations. Do not claim broad format support based on file extensions.

The local probe (`scripts/check-mpv-evaluation.sh`) found no installed `libmpv` pkg-config module. Homebrew metadata reports `mpv` 0.41.0, licensed `GPL-2.0-or-later AND LGPL-2.1-or-later`, with a large FFmpeg/libass/libplacebo dependency set; the formula is not installed. The probe does not install packages or change the machine.
