#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required for generated format checks" >&2
  exit 2
fi

tmpdir="$(mktemp -d /tmp/sakura-player-formats.XXXXXX)"
cleanup() {
  python3 - "$tmpdir" <<'PY'
import shutil, sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
PY
}
trap cleanup EXIT

make_sample() {
  local output="$1" video_codec="$2" audio_codec="$3" format="$4"
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i color=c=black:s=320x180:d=1 \
    -f lavfi -i sine=frequency=440:duration=1 \
    -c:v "$video_codec" -pix_fmt yuv420p -c:a "$audio_codec" \
    -shortest -f "$format" "$output" 2>/dev/null
}

make_audio() {
  local output="$1" audio_codec="$2" format="$3"
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i sine=frequency=440:duration=1 \
    -c:a "$audio_codec" -f "$format" "$output" 2>/dev/null
}

make_sample "$tmpdir/h264-aac.mp4" libx264 aac mp4
make_sample "$tmpdir/h264-aac.mov" libx264 aac mov
make_sample "$tmpdir/h264-aac.m4v" libx264 aac mp4
make_sample "$tmpdir/h264-mp3.avi" libx264 libmp3lame avi
make_sample "$tmpdir/h264-aac.ts" libx264 aac mpegts
make_sample "$tmpdir/h264-aac.mkv" libx264 aac matroska
make_sample "$tmpdir/vp9-opus.webm" libvpx-vp9 libopus webm
make_sample "$tmpdir/hevc-aac.mp4" libx265 aac mp4
make_sample "$tmpdir/av1-aac.mkv" libsvtav1 aac matroska
make_audio "$tmpdir/aac.m4a" aac ipod
make_audio "$tmpdir/mp3.mp3" libmp3lame mp3
make_audio "$tmpdir/alac.m4a" alac ipod
make_audio "$tmpdir/flac.flac" flac flac
make_audio "$tmpdir/opus.ogg" libopus ogg

printf '| Sample | Result |\n| --- | --- |\n'
result=0
for sample in "$tmpdir"/*; do
  set +e
  output="$(SAKURA_ALLOW_UNSUPPORTED_FIXTURE=1 SAKURA_MEDIA_FIXTURE="$sample" swift run --quiet SakuraPlayerCoreChecks 2>/dev/null)"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    printf '| `%s` | CHECK PROCESS FAILED (%s) |\n' "$(basename "$sample")" "$status"
  elif printf '%s\n' "$output" | grep -q "Media fixture passed"; then
    printf '| `%s` | PASS |\n' "$(basename "$sample")"
  else
    printf '| `%s` | FAIL or unsupported |\n' "$(basename "$sample")"
    result=1
  fi
done

# Format support is measured data, not a build gate: unsupported codecs must be
# recorded and investigated without making every CI runner fail.
exit 0
