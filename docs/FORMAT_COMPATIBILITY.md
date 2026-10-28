# Format compatibility

Last checked: 2026-10-28 on the local Apple Silicon host with Swift 6.4 and the macOS 27 SDK.

No broad compatibility claim is made from file extensions alone. The rows below record the generated local smoke fixtures and must be supplemented with legal target-Mac samples, hardware-decoding details and real-world media before release claims.

| Container | Video | Audio | Result |
| --- | --- | --- | --- |
| MP4 | H.264 (320x180, 1 s generated fixture) | AAC | Verified on local Apple Silicon host via `AVPlayerEngine` core check |
| MOV | H.264 (320x180, 1 s generated fixture) | AAC | Verified on local Apple Silicon host via `AVPlayerEngine` core check |
| MP4 | HEVC (320x180, 1 s generated fixture) | AAC | Verified on local Apple Silicon host via `AVPlayerEngine` core check |
| M4V | H.264 (320x180, 1 s generated fixture) | AAC | Verified on local Apple Silicon host via `AVPlayerEngine` core check |
| AVI | H.264 (320x180, 1 s generated fixture) | MP3 | Not opened by current AVFoundation adapter; requires libmpv evaluation |
| MPEG-TS | H.264 (320x180, 1 s generated fixture) | AAC | Verified on local Apple Silicon host via `AVPlayerEngine` core check |
| MKV | H.264/AAC (generated fixture) | AAC | Not opened by current AVFoundation adapter; requires libmpv evaluation |
| WebM | VP9/Opus (generated fixture) | Opus | Not opened by current AVFoundation adapter; requires libmpv evaluation |
| MKV | AV1/AAC (generated fixture) | AAC | Not opened by current AVFoundation adapter; requires libmpv evaluation |
| M4A | Audio-only AAC (1 s generated fixture) | AAC | Verified on local Apple Silicon host via `AVPlayerEngine` core check |
| MP3 | Audio-only MP3 (1 s generated fixture) | MP3 | Verified on local Apple Silicon host via `AVPlayerEngine` core check |
| M4A | Audio-only ALAC (1 s generated fixture) | ALAC | Verified on local Apple Silicon host via `AVPlayerEngine` core check |
| FLAC | Audio-only FLAC (1 s generated fixture) | FLAC | Verified on local Apple Silicon host via `AVPlayerEngine` core check |
| OGG | Audio-only Opus (1 s generated fixture) | Opus | Verified on local Apple Silicon host via `AVPlayerEngine` core check |
| Other codec combinations | HEVC/VP9/AV1 and alternate audio tracks | Various | Pending target-Mac fixture runs |

Required follow-up samples are listed in `docs/TEST_PLAN.md`. Unsupported or damaged files must surface a readable error and never crash the app.
