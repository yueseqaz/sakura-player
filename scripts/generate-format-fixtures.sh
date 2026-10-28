#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo 'Usage: generate-format-fixtures.sh OUTPUT_DIRECTORY' >&2
  exit 2
fi
command -v ffmpeg >/dev/null || { echo 'ffmpeg is required' >&2; exit 2; }
mkdir -p "$1"
out="$(cd "$1" && pwd)"

make_sample() {
  local output="$1" video_codec="$2" audio_codec="$3" format="$4"
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i color=c=black:s=320x180:d=2 \
    -f lavfi -i sine=frequency=440:duration=2 \
    -c:v "$video_codec" -pix_fmt yuv420p -c:a "$audio_codec" \
    -shortest -f "$format" "$out/$output" 2>/dev/null
}

make_audio() {
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i sine=frequency=440:duration=2 \
    -c:a "$2" -f "$3" "$out/$1" 2>/dev/null
}

make_sample h264-aac.mp4 libx264 aac mp4
make_sample h264-aac.mov libx264 aac mov
make_sample h264-aac.m4v libx264 aac mp4
make_sample h264-mp3.avi libx264 libmp3lame avi
make_sample h264-aac.ts libx264 aac mpegts
make_sample h264-aac.mkv libx264 aac matroska
make_sample vp9-opus.webm libvpx-vp9 libopus webm
make_sample hevc-aac.mp4 libx265 aac mp4
make_sample av1-aac.mkv libsvtav1 aac matroska
make_audio aac.m4a aac ipod
make_audio mp3.mp3 libmp3lame mp3
make_audio alac.m4a alac ipod
make_audio flac.flac flac flac
make_audio opus.ogg libopus ogg

subtitle="$(mktemp /tmp/sakura-format-subtitle.XXXXXX)"
trap 'rm -f "$subtitle"' EXIT
cat > "$subtitle" <<'ASS'
[Script Info]
ScriptType: v4.00+
PlayResX: 320
PlayResY: 180
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,24,&H0000FF00,&H0000FF00,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,2,8,8,12,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.10,0:00:01.90,Default,,0,0,0,,{\b1}Sakura ASS probe
ASS
ffmpeg -y -hide_banner -loglevel error \
  -i "$out/h264-aac.mp4" -f lavfi -i sine=frequency=880:duration=2 \
  -f ass -i "$subtitle" -map 0:v -map 0:a -map 1:a -map 2:s \
  -c:v copy -c:a aac -c:s ass -metadata:s:a:0 language=eng \
  -metadata:s:a:1 language=jpn -metadata:s:s:0 language=eng \
  "$out/multi-track-ass.mkv"
