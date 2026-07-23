#!/bin/bash
# Package Lonar.app into a drag-to-Applications DMG using only hdiutil.
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
codesign --force --sign - "$DMG"
rm -rf "$STAGING"
echo "Built $DMG"
