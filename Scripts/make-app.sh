#!/bin/bash
# Build Lonar.app from the SwiftPM executable and ad-hoc sign it.
# Usage: Scripts/make-app.sh [--install]
#   --install  copy the bundle to /Applications (needed for launch-at-login)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

APP=build/Lonar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/arm64-apple-macosx/release/Lonar "$APP/Contents/MacOS/Lonar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Lonar.app
    cp -R "$APP" /Applications/Lonar.app
    echo "Installed /Applications/Lonar.app — launch it once, then enable 'Launch at login' from the menu bar popover."
fi
