#!/bin/bash
# Build Lonar.app from the SwiftPM executable and sign it.
# Signs with a "Developer ID Application" identity (hardened runtime, needed
# for notarization) when one is in the keychain; falls back to ad-hoc.
# Usage: Scripts/make-app.sh [--install]
#   --install  copy the bundle to /Applications (needed for launch-at-login)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

APP=build/Lonar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/Lonar "$APP/Contents/MacOS/Lonar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
if [[ -n "$IDENTITY" ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    echo "Built $APP (signed: $IDENTITY)"
else
    codesign --force --sign - "$APP"
    echo "Built $APP (ad-hoc signed — no Developer ID Application cert found)"
fi

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Lonar.app
    cp -R "$APP" /Applications/Lonar.app
    echo "Installed /Applications/Lonar.app — launch it once, then enable 'Launch at login' from the menu bar popover."
fi
