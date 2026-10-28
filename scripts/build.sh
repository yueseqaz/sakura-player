#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --configuration release --product SakuraPlayer
printf 'Built SakuraPlayer (release)\n'
