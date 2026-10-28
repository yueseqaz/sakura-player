# Contributing

1. Install Xcode and the Swift toolchain listed in `README.md`.
2. Run `./scripts/test.sh` before opening a pull request.
3. Keep playback-engine calls behind `PlayerEngine`; SwiftUI views should consume `PlaybackState` rather than reaching into AVFoundation directly.
4. Do not add telemetry, cloud media services, or unlicensed test media.
5. Record format, performance and compatibility measurements in `docs/` with the device and macOS version used.

Pull requests should include tests or a manual-test note for behavior changes and should not commit signing credentials, personal paths, or generated build products.
