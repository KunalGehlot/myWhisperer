#!/usr/bin/env bash
# Build a universal release of OpenFlow and zip it for GitHub Releases.
#
# Usage: scripts/package.sh
# Output: dist/OpenFlow-<version>.zip and dist/OpenFlow-<version>.zip.sha256
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/dist"

rm -rf "$OUT"
mkdir -p "$OUT"
INSTALL_DIR="$OUT" scripts/bundle.sh release

APP="$OUT/OpenFlow.app"
VERSION="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
ZIP="$OUT/OpenFlow-$VERSION.zip"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")

lipo -archs "$APP/Contents/MacOS/OpenFlow"
echo "Packaged $ZIP"
cat "$ZIP.sha256"
