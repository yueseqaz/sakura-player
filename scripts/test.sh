#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --target SakuraPlayerCoreChecks
swift run SakuraPlayerCoreChecks
if command -v ffmpeg >/dev/null 2>&1; then
  fixture_dir="$(mktemp -d /tmp/sakura-player-fixtures.XXXXXX)"
  fixture="$fixture_dir/with-audio.mp4"
  no_audio_fixture="$fixture_dir/no-audio.mp4"
  trap 'python3 - "$fixture_dir" <<'"'"'PY'"'"'
import shutil, sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
PY' EXIT
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i color=c=black:s=320x180:d=1 \
    -f lavfi -i sine=frequency=440:duration=1 \
    -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$fixture"
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i color=c=black:s=320x180:d=1 \
    -c:v libx264 -pix_fmt yuv420p -an "$no_audio_fixture"
  for media in "$fixture" "$no_audio_fixture"; do
    SAKURA_MEDIA_FIXTURE="$media" swift run SakuraPlayerCoreChecks
  done
fi
printf 'Core checks passed\n'
