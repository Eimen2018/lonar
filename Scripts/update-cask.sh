#!/bin/bash
# Point the Homebrew tap at the current release.
# Run after make-dmg.sh + gh release create: clones the tap, rewrites
# version + sha256 in the cask, and pushes.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG="build/Lonar-$VERSION.dmg"
[[ -f "$DMG" ]] || { echo "$DMG not found — run Scripts/make-dmg.sh first"; exit 1; }
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

TAP=build/tap
rm -rf "$TAP"
git clone --depth 1 git@github.com:Eimen2018/homebrew-tap.git "$TAP"
sed -i '' \
    -e "s/^  version \".*\"/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
    "$TAP/Casks/lonar.rb"
git -C "$TAP" commit -am "lonar $VERSION"
git -C "$TAP" push
rm -rf "$TAP"
echo "Tap updated to $VERSION ($SHA)"
