#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$ROOT"
swift build -c release

APP="$ROOT/dist/WiVoice.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WiVoice "$APP/Contents/MacOS/WiVoice"
cp Info.plist "$APP/Contents/Info.plist"
ditto .build/x86_64-apple-macosx/release/WiVoice_WiVoice.bundle "$APP/Contents/WiVoice_WiVoice.bundle"
cp ResourceInfo.plist "$APP/Contents/WiVoice_WiVoice.bundle/Info.plist"
ICONSET="$ROOT/.build/WiVoice.iconset"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ROOT/.build/WiVoice-1024.png"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -s format png -z "$size" "$size" "$ROOT/.build/WiVoice-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -s format png -z "$double" "$double" "$ROOT/.build/WiVoice-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/WiVoice.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
