#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

printf '%s\n' 'Sakura Player libmpv evaluation probe'
printf 'date: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'host: %s\n' "$(uname -m)"

if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists mpv; then
  printf 'installed libmpv: %s\n' "$(pkg-config --modversion mpv)"
  printf 'include flags: %s\n' "$(pkg-config --cflags mpv)"
  printf 'link flags: %s\n' "$(pkg-config --libs mpv)"
else
  echo 'installed libmpv: no pkg-config module found'
fi

if command -v brew >/dev/null 2>&1; then
  brew info --json=v2 mpv 2>/dev/null | python3 -c '
import json, sys
payload = json.load(sys.stdin)
formula = payload.get("formulae", [{}])[0]
print("Homebrew mpv formula: %s" % formula.get("versions", {}).get("stable", "unknown"))
print("Homebrew mpv license: %s" % formula.get("license", "unknown"))
print("Homebrew mpv installed: %s" % bool(formula.get("installed")))
print("Homebrew mpv dependencies: %s" % ", ".join(formula.get("dependencies", [])))
' || echo 'Homebrew mpv metadata unavailable'
fi

echo 'No package was installed by this probe.'
