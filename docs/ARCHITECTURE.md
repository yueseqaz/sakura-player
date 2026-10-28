# Architecture

## Modules

- `SakuraPlayerCore`: playback state models, `PlayerEngine`, AVFoundation adapter, subtitle discovery, metadata loading and local history storage.
- `SakuraPlayerApp`: SwiftUI/AppKit shell. `PlayerViewModel` owns one engine and publishes its state to the view; controls do not call AVFoundation directly. `PlayerSurface` hosts an `AVPlayerLayer` without duplicating AVKit's native control strip, and `PictureInPictureCoordinator` attaches to that layer only when macOS reports native support.
- `SakuraPlayerCoreChecks`: a dependency-free executable test harness usable on machines that only have the Command Line Tools.
- `PlaybackQueue`: deterministic queue ordering (sequential, single-file loop, queue loop and shuffle) shared by the player view model and future queue UI.
- `MediaFileDiscovery`: conservative same-directory discovery based on supported media extensions; it never treats an extension as proof that a codec is playable.

## State flow

`AVPlayerEngine` is the single owner of playback state. It publishes changed snapshots through Combine on the main actor. A per-item periodic observer updates time at 250 ms intervals, not on every display tick. Unchanged snapshots are not republished.

The app is now split into `SakuraPlayerApp`, `PlayerViewModel`, `PlayerView`, `PlayerSurface`, `PlaybackControls`, `SettingsView`, `PresentationPreferences` and `PlayerBanners` source files. The engine's main-actor publisher is consumed synchronously rather than queued through another RunLoop hop, preventing an obsolete end event from advancing a newly selected queue item. Clock-only snapshots update `PlaybackTimelineModel` without invalidating the window-level model. Only the timeline slider and time readout observe this clock; seek previews use the same narrow model, while control interaction/status changes still notify the window. The view model retains the latest full state for commands, history and diagnostics. Actual GPU/CPU/SwiftUI rendering performance still requires Instruments measurements.

Periodic observers are installed per loaded item with generation checks and removed on replacement/close. A dedicated token lifetime owner removes periodic and notification observers and releases the current AVPlayer item when the engine deinitializes. Async media-selection loads validate item identity/generation after each suspension; seek completions validate their own generation and item identity. Canceled loads release the current item, while superseded loads cannot tear down the replacement.

Volume, mute and rate survive media-state resets so the published snapshot agrees with the actual AVPlayer. Raising volume explicitly unmutes both. Invalid/non-finite controls and nonexistent track IDs cannot install phantom state. External cue lookup uses an explicit enabled flag and `mediaTime - delay`, so positive offsets mean later subtitles.

Loading a new URL first invalidates the previous item observation and replaces the AVPlayer item. Failed loads become `.failed` with a user-facing message rather than terminating the process. History is an actor-backed, best-effort JSON store so disk writes cannot block playback.

AVFoundation error codes are mapped to stable user-facing categories (unsupported format/codec, malformed media or decode failure); logs retain only the error type and never emit the media path.

The view model assigns every load a generation token. A stale asynchronous load cannot start playback, install subtitles or overwrite the error state after the user has opened another file.

AVFoundation media-selection groups are converted into stable index-based audio and subtitle track models. Selecting a track stays inside the engine boundary; external subtitle injection remains a playback-engine evaluation item because AVPlayer does not expose a portable API for attaching arbitrary SRT/ASS files.

The view model stores selected embedded track indexes under path-scoped UserDefaults keys, so preferences remain local and can be restored without adding media contents to the history store.

For SRT, WebVTT, ASS and SSA, `SubtitleParser` provides a lightweight timed cue model. ASS/SSA override tags are stripped and line breaks are normalized; the view model uses the result as an overlay only when the media has no embedded legible track, preventing accidental duplicate subtitles. Full ASS styling remains an engine-evaluation item.

External subtitle timing is applied in the cue lookup path and is clearly labeled as external-only in the UI; AVPlayer's embedded subtitle renderer is not shifted by this setting.

The Settings scene binds to the same view-model preferences used by the player, so changing queue order or subtitle appearance does not create a second source of truth.

Preference loading suppresses persistence callbacks until initialization is complete; saved values therefore survive launch instead of being overwritten by default property values.

Playback diagnostics use `OSLog` with hashed media basenames and public error text; full user paths are not emitted by default.

The app's Diagnostics panel is generated from the current playback snapshot. It includes engine/status, timing, track and error fields but deliberately omits the media path. The window bridge stores only the last frame in `UserDefaults` and restores it only when it still intersects a visible screen, so unplugging a display cannot strand the window off-screen.

Pointer activity updates a timestamp while one hide task waits for the quiet period; the task rechecks the timestamp before hiding instead of being cancelled and recreated for every mouse-moved event.

Pointer press and drag events temporarily suspend auto-hide. This keeps the control rail stable while a user is dragging the timeline or opening a menu, then resumes the quiet-period timer on release. The transport row uses `ViewThatFits` to fall back to a compact variant for narrow windows without changing the video canvas layout.

`PlayerEngine` exposes an explicit `supportsAudioDelay` capability and a throwing `setAudioDelay` boundary. The AVFoundation adapter reports this capability as unavailable instead of silently pretending to shift samples; a future adapter must implement it together with synchronization tests.

History reads prune entries whose files are no longer readable, keeping the Recent menu useful after files are moved or deleted.

History checkpoints are written during playback and also on the first meaningful pause/end transition, so closing or pausing shortly after a seek does not lose the user's latest position while repeated state updates remain throttled.

## Future boundaries

Queue management, subtitle styling/offsets, track selection and settings should extend `PlayerEngine` and `PlaybackState` rather than introducing engine calls in views. The engine protocol is intentionally independent of AVFoundation so a validated libmpv adapter can be evaluated without rewriting UI code.
