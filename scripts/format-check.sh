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

./scripts/generate-format-fixtures.sh "$tmpdir"

printf '| Sample | Result |\n| --- | --- |\n'
result=0
for sample in "$tmpdir"/*; do
  set +e
  output="$(SAKURA_ALLOW_UNSUPPORTED_FIXTURE=1 SAKURA_MEDIA_FIXTURE="$sample" swift run --quiet SakuraPlayerCoreChecks 2>/dev/null)"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    printf '| `%s` | CHECK PROCESS FAILED (%s) |\n' "$(basename "$sample")" "$status"
    result=1
  elif printf '%s\n' "$output" | grep -q "Media fixture passed"; then
    printf '| `%s` | PASS |\n' "$(basename "$sample")"
  else
    printf '| `%s` | FAIL or unsupported |\n' "$(basename "$sample")"
  fi
done

# Format support is measured data, not a build gate: unsupported codecs must be
# recorded and investigated without making every CI runner fail.
exit "$result"
