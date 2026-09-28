#!/usr/bin/env bash
# Build myWhisperer, wrap it in a signed .app, and install it to ~/Applications.
#
# Usage: scripts/bundle.sh [debug|release]   (default: debug)
# Env:   SIGN_IDENTITY  codesign identity (default: first valid "Apple
#                       Development" identity, else "-" for ad-hoc).
#        INSTALL_DIR    where to put myWhisperer.app (default: ~/Applications).
#
# With ad-hoc signing macOS forgets Accessibility grants on every rebuild; a
# development certificate keeps them. The app is installed outside the
# iCloud-synced repo so iCloud can't add attributes that break the signature.
set -euo pipefail

CONFIG="${1:-debug}"
NAME="myWhisperer"
BUNDLE_ID="com.mywhisperer.app"
VERSION="0.3.0"
BUILD_NUMBER="$(git -C "$(dirname "$0")/.." rev-list --count HEAD 2>/dev/null || echo 1)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/"Apple Development/ { print $2; exit }')"
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

mkdir -p "$INSTALL_DIR"
APP="$INSTALL_DIR/$NAME.app"
STAGING="$(mktemp -d)/$NAME.app"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BIN_DIR/MyWhisperer" "$STAGING/Contents/MacOS/$NAME"
cp resources/icon.icns "$STAGING/Contents/Resources/AppIcon.icns"

cat > "$STAGING/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>$NAME listens only while you hold the dictation key, and turns your speech into text.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key><array><string>mywhisperer</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

xattr -cr "$STAGING"
codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$STAGING"
codesign --verify --strict "$STAGING"

# Replace the installed copy (quit it first so the new build launches).
if pgrep -f "$APP/Contents/MacOS/$NAME" >/dev/null; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    sleep 1
    pkill -f "$APP/Contents/MacOS/$NAME" 2>/dev/null || true
fi
rm -rf "$APP"
ditto "$STAGING" "$APP"
rm -rf "$(dirname "$STAGING")"

echo "Installed $APP (signed: $([[ "$SIGN_IDENTITY" == "-" ]] && echo ad-hoc || echo "$SIGN_IDENTITY"))"
