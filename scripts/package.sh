#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration=release
version="${SAKURA_VERSION:-0.1.0}"
build_number="${SAKURA_BUILD:-1}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  printf 'Invalid SAKURA_VERSION: %s\n' "$version" >&2
  exit 2
fi
if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
  printf 'Invalid SAKURA_BUILD: %s\n' "$build_number" >&2
  exit 2
fi
swift build --configuration "$configuration" --product SakuraPlayer
binary="$(swift build --configuration "$configuration" --show-bin-path)/SakuraPlayer"
dist="$PWD/dist"
app="$dist/SakuraPlayer.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/SakuraPlayer"
./scripts/build-icon.sh "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleDisplayName</key><string>Sakura Player</string>
    <key>CFBundleExecutable</key><string>SakuraPlayer</string>
    <key>CFBundleIdentifier</key><string>com.yueseqaz.SakuraPlayer</string>
    <key>CFBundleName</key><string>SakuraPlayer</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${version}</string>
    <key>CFBundleVersion</key><string>${build_number}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array><dict>
        <key>CFBundleTypeName</key><string>Video or audio media</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>CFBundleTypeExtensions</key><array>
            <string>mp4</string><string>mov</string><string>m4v</string><string>mkv</string>
            <string>avi</string><string>webm</string><string>ts</string><string>m2ts</string>
            <string>m4a</string><string>mp3</string><string>flac</string><string>ogg</string>
            <string>opus</string><string>wav</string><string>aiff</string><string>aif</string><string>caf</string>
        </array>
        <key>LSItemContentTypes</key><array>
            <string>public.movie</string><string>public.audio</string>
        </array>
    </dict></array>
</dict></plist>
PLIST
printf 'Unsigned app bundle: %s\n' "$app"
