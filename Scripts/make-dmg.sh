#!/bin/bash
# Package Lonar.app into a styled drag-to-Applications DMG.
# Uses create-dmg (brew install create-dmg) for the designed window
# (background, volume icon, positioned icons); falls back to plain hdiutil.
# If a Developer ID cert was used and a notarytool keychain profile named
# "lonar-notary" exists, the DMG is notarized and stapled.
# Usage: Scripts/make-dmg.sh   (runs make-app.sh first)
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/make-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
STAGING=build/dmg-staging
DMG="build/Lonar-$VERSION.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/Lonar.app "$STAGING/Lonar.app"

if command -v create-dmg >/dev/null; then
    create-dmg \
        --volname "Lonar $VERSION" \
        --volicon Resources/AppIcon.icns \
        --background Resources/dmg-background.tiff \
        --window-size 660 400 \
        --icon-size 128 \
        --icon "Lonar.app" 165 200 \
        --app-drop-link 528 200 \
        --hide-extension "Lonar.app" \
        --no-internet-enable \
        "$DMG" "$STAGING"
else
    echo "create-dmg not found — building plain DMG (brew install create-dmg for the styled one)"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "Lonar $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
fi
rm -rf "$STAGING"

IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
if [[ -n "$IDENTITY" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    if xcrun notarytool history --keychain-profile lonar-notary >/dev/null 2>&1; then
        echo "Submitting to Apple notary service (usually 1-5 minutes)..."
        xcrun notarytool submit "$DMG" --keychain-profile lonar-notary --wait
        xcrun stapler staple "$DMG"
        echo "Built $DMG (notarized + stapled)"
    else
        echo "Built $DMG (signed, NOT notarized — set up 'lonar-notary' keychain profile: xcrun notarytool store-credentials lonar-notary --apple-id <id> --team-id <team>)"
    fi
else
    codesign --force --sign - "$DMG"
    echo "Built $DMG (ad-hoc signed)"
fi
