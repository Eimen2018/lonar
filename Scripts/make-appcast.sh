#!/bin/bash
# Regenerate appcast.xml for Sparkle auto-updates.
# Expects build/Lonar.app to exist (run make-app.sh / make-dmg.sh first).
# Signs the archive with the EdDSA key in the login keychain (created once
# via Sparkle's generate_keys) and points downloads at the GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ARCHIVES=build/appcast
mkdir -p "$ARCHIVES"
rm -f "$ARCHIVES"/*.zip "$ARCHIVES"/*.html
ditto -c -k --keepParent build/Lonar.app "$ARCHIVES/Lonar-$VERSION.zip"

.sparkle/bin/generate_appcast \
    --download-url-prefix "https://github.com/Eimen2018/lonar/releases/download/v$VERSION/" \
    -o appcast.xml \
    "$ARCHIVES"
echo "Wrote appcast.xml for v$VERSION (upload $ARCHIVES/Lonar-$VERSION.zip as a release asset, then commit appcast.xml)"
