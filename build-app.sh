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
printf 'APPL????' > "$APP/Contents/PkgInfo"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
