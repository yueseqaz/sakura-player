# Third-party notices

The current implementation has no vendored third-party libraries. It links Apple system frameworks (`AVFoundation`, `AVKit`, `AppKit`, `SwiftUI`, `Combine`, `OSLog`, and `UniformTypeIdentifiers`) supplied by macOS and Xcode.

If libmpv or another playback dependency is introduced, this file must be updated with its exact version, source, license, linkage mode and redistribution obligations before distribution.

`tools/mpv-probe.c` is our development-only client of an explicitly supplied external libmpv. It is excluded from the SwiftPM app targets. Its headers and runtime are not vendored or redistributed. The local reference-runtime experiment and official API/license references are documented in `docs/ENGINE_EVALUATION.md`; it does not change the app's current dependency set or grant rights to redistribute that runtime.
