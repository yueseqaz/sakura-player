# Technical decisions

## 2026-10-28: Compact dark control rail

Playback controls are rendered as a centered rail capped at 640 points rather than a full-width footer. A dark translucent surface keeps icons readable over both bright and dark video while secondary actions stay inside a single options menu. This keeps the video canvas visually dominant and avoids layout changes when controls appear.

The Picture menu also exposes an `Original` mode. It keeps media at native presentation dimensions when the window can contain them, then scales down proportionally only when necessary; the default remains `Fill` for an edge-to-edge viewing canvas.

The rail's current presentation cap is 520 points. The layout uses `ViewThatFits` so it can remove low-frequency queue navigation and the volume slider when space is constrained, rather than allowing the footer to stretch across the entire video.

The Controls settings section exposes Automatic, Compact and Regular modes. Automatic remains the default and uses the available width; the explicit modes let users keep a preferred control density when they watch in a consistent window size.

## 2026-10-28: Fill-first video presentation

The player defaults to aspect-ratio-preserving `resizeAspectFill` so ordinary window resizes do not reveal a distracting black strip. Users can switch to `Fit` from the Picture menu whenever the complete uncropped frame is more important than edge-to-edge presentation; neither mode applies non-uniform stretching.

## 2026-10-28: Swift Package Manager first

The repository uses Swift Package Manager instead of committing generated Xcode project files. This keeps dependencies and build steps reproducible in CI. Xcode can open the package directly for the native macOS app target.

## 2026-10-28: AVFoundation adapter first

The first playable foundation uses AVFoundation/AVKit because they are system frameworks, integrate naturally with macOS, and avoid an unverified libmpv redistribution decision. `PlayerEngine` isolates this choice. A libmpv evaluation remains a release gate for broader codec/subtitle coverage.

## 2026-10-28: Best-effort JSON history

The initial history model is small, so JSON in Application Support is preferable to introducing a database before queue and migration requirements are known. Writes are actor-isolated and replace the file atomically; history failures never interrupt playback.

## 2026-10-28: External subtitle scope

SRT, WebVTT, ASS and SSA are parsed into timed SwiftUI cues and overlaid only when no embedded legible track exists. ASS/SSA override tags are stripped because the current overlay has one consistent style; full libass-compatible styling and subtitle delay semantics remain part of the libmpv/engine evaluation gate.

## 2026-10-28: Audio-delay limitation is explicit

`AVPlayer` exposes volume and track selection but no supported per-item audio presentation delay. The app therefore does not expose a misleading audio-delay control or emulate one by dropping samples. Audio delay remains a P0 release-gate item for a future engine adapter (likely libmpv or a dedicated audio pipeline) and must be implemented with A/V sync tests before being advertised.
