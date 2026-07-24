#!/bin/bash
# Fetch the official Sparkle release into .sparkle/ (gitignored).
# Pinned version + SHA-256 so builds are reproducible. Run once before
# building; make-app.sh calls this automatically when .sparkle/ is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION=2.9.4
SPARKLE_SHA256=ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9

if [[ -d .sparkle/Sparkle.framework ]]; then
    echo "Sparkle already present in .sparkle/"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -sL --fail -o "$tmp/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
echo "$SPARKLE_SHA256  $tmp/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null

rm -rf .sparkle
mkdir -p .sparkle
tar -xJf "$tmp/sparkle.tar.xz" -C .sparkle
[[ -d .sparkle/Sparkle.framework ]] || { echo "unexpected archive layout"; exit 1; }
echo "Sparkle $SPARKLE_VERSION extracted to .sparkle/"
