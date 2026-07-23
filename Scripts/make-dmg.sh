#!/bin/bash
# Package Lonar.app into a drag-to-Applications DMG using only hdiutil.
# If a Developer ID cert was used and a notarytool keychain profile named
# "lonar-notary" exists, the DMG is notarized and stapled — downloads then
# open with no Gatekeeper warning.
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
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Lonar $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
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
