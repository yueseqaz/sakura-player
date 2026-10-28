# Changelog

## Unreleased

- Added the user-provided Sakura app icon and reproducible macOS ICNS generation during packaging.
- Selected an explicit Swift 6-capable Xcode toolchain for GitHub Actions and corrected version-tag handling in release builds.
- Required media smoke fixtures now fail the test process on playback errors; unsupported-format measurements use an explicit opt-in instead of silently passing required checks.
- Kept AVFoundation media-selection objects main-actor confined while accommodating older SDK concurrency annotations in CI.

- Added Swift Package Manager project and native SwiftUI macOS player shell.
- Added AVFoundation-backed `PlayerEngine` abstraction with playback state, seek, volume, mute and rate controls.
- Added drag-and-drop/open-panel media loading and local subtitle discovery.
- Added multi-file playback queue, repeat/shuffle ordering and embedded audio/subtitle track selection.
- Added SRT/WebVTT cue parsing, automatic same-name subtitle loading and an external-subtitle delay menu.
- Added picture rotation, fit/fill modes, configurable control auto-hide, resume prompts and stale-load protection.
- Added same-directory media discovery and queue item selection/removal controls.
- Added native Picture in Picture integration when supported by macOS.
- Added generated format-matrix and non-installing libmpv evaluation probes.
- Added throttled-on-demand JSON playback history storage.
- Added deterministic core checks and initial engineering documentation.
- Added a copyable, privacy-preserving Diagnostics panel and an Open Another recovery action for failed loads.
- Added window frame restoration with safe-screen validation between launches.
- Added subtitle toggle/delay, playback-order cycle and rate-adjustment keyboard commands.
- Added an explicit dismissible notice when an external subtitle file cannot be parsed.
- Added validated version/build overrides to the packaging script and release workflow.
- Persisted the selected playback rate and applied it when loading the next file.
- Added a precise subtitle-delay slider with persisted resettable preference.
- Queue entries now show a duration when the media has been loaded, with the current item marked.
- Tightened the playback control rail to a compact dark glass surface with a stable accessibility label for the options menu.
- Reduced the control rail cap again to 640 points so it stays visually light on standard window sizes.
- Hardened Finder/Launch Services URL handling and registered supported audio extensions in the app bundle document types.
- Verified a cold Launch Services launch opens a media URL directly into the playback queue.
- Captured a final playback-history checkpoint when pausing or reaching the end, including short sessions after a seek.
- Added an original-size picture mode that preserves native presentation dimensions when the window can contain them.
- Fixed preference initialization so saved picture mode, subtitle settings and control preferences are not overwritten during startup.
- Removed the redundant menu chevron from the compact playback options button for a cleaner control rail.
- Added an explicit Escape command for leaving full-screen playback.
- Debounced control auto-hide scheduling so continuous pointer movement no longer creates a new timer for every mouse event.
- Added clearer AVFoundation error messages for unsupported codecs, malformed files and decode failures.
- Added checkmarks to playback speed, order, audio-track, subtitle-track and subtitle-off menu items.
- Diagnostics now report the packaged app version and build instead of a hardcoded development label.
- Added basic ASS/SSA timed-text parsing with normalized line breaks and safe stripping of style override tags.
- Kept the playback rail visible while the pointer is pressed or the timeline is being dragged, preventing hide/show flicker during interaction.
- Added a compact transport layout for narrow windows so queue navigation and volume controls do not force a long, wrapped footer.
- Tightened the rail's maximum width to 560 points so it stays visually subordinate to the video on wide windows.
- Tightened the rail once more to 520 points after visual review, keeping the timeline usable without letting the footer dominate the canvas.
- Added native macOS help tooltips to transport controls, the timeline, volume control and options menu.
- Added a persisted control-bar layout preference with Automatic, Compact and Regular modes.
