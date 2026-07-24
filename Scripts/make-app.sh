#!/bin/bash
# Build Lonar.app from the SwiftPM executable, embed Sparkle, and sign.
# Signs with a "Developer ID Application" identity (hardened runtime, needed
# for notarization) when one is in the keychain; falls back to ad-hoc.
# Usage: Scripts/make-app.sh [--install]
#   --install  copy the bundle to /Applications (needed for launch-at-login)
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/fetch-sparkle.sh
swift build -c release --arch arm64

APP=build/Lonar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/arm64-apple-macosx/release/Lonar "$APP/Contents/MacOS/Lonar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cp -R .sparkle/Sparkle.framework "$APP/Contents/Frameworks/"

IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
FW="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -n "$IDENTITY" ]]; then
    # Nested-first signing order per Sparkle's sandboxing/distribution docs.
    codesign -f -s "$IDENTITY" -o runtime "$FW/Versions/B/XPCServices/Installer.xpc"
    codesign -f -s "$IDENTITY" -o runtime --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
    codesign -f -s "$IDENTITY" -o runtime "$FW/Versions/B/Autoupdate"
    codesign -f -s "$IDENTITY" -o runtime "$FW/Versions/B/Updater.app"
    codesign -f -s "$IDENTITY" -o runtime "$FW"
    codesign -f -s "$IDENTITY" -o runtime --timestamp "$APP"
    echo "Built $APP (signed: $IDENTITY)"
else
    codesign -f --deep -s - "$FW"
    codesign -f -s - "$APP"
    echo "Built $APP (ad-hoc signed — no Developer ID Application cert found)"
fi

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Lonar.app
    cp -R "$APP" /Applications/Lonar.app
    echo "Installed /Applications/Lonar.app — launch it once, then enable 'Launch at login' from the menu bar popover."
fi
