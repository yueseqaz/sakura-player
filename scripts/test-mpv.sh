#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Runtime and official headers must be supplied explicitly. Nothing is installed,
# downloaded, copied into the app, or taken automatically from another product.
: "${SAKURA_MPV_LIBRARY:?Set to the absolute libmpv dylib path for local evaluation}"
: "${SAKURA_MPV_INCLUDE:?Set to the directory containing official client.h and render.h}"
[[ "$SAKURA_MPV_LIBRARY" = /* && -f "$SAKURA_MPV_LIBRARY" ]] || exit 2
command -v ffmpeg >/dev/null || { echo 'ffmpeg is required' >&2; exit 2; }
tmpdir="$(mktemp -d /tmp/sakura-mpv-probe.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT
clang -Wall -Wextra -Werror -I "$SAKURA_MPV_INCLUDE" tools/mpv-probe.c \
  "$SAKURA_MPV_LIBRARY" -Wl,-rpath,"$(dirname "$SAKURA_MPV_LIBRARY")" -o "$tmpdir/mpv-probe"
./scripts/generate-format-fixtures.sh "$tmpdir/media"

result=0
for sample in "$tmpdir/media"/*; do
  printf '\nSample: %s\n' "$(basename "$sample")"
  "$tmpdir/mpv-probe" "$sample" || result=1
done
echo 'Evaluation only: software rendering, null audio; no hardware/HDR/real-device A/V-sync claim.'
exit "$result"
