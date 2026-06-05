#!/bin/bash
set -e

# Builds Session Cove and packages it as a macOS DMG installer.
# Output: dist/SessionCove-<version>-universal.dmg
#
# Usage:
#   bash scripts/make-dmg.sh                # default version (matches bundle.sh)
#   VERSION=0.3.0 bash scripts/make-dmg.sh  # explicit version
#
# Layout inside the mounted volume:
#   /Volumes/Session Cove/
#     ├── Session Cove.app
#     └── Applications -> /Applications     (drag-target shortcut)
#
# Zero dependencies — uses macOS-bundled `hdiutil`. If you want a fancier
# DMG with a custom background image and pre-positioned icons, install
# `brew install create-dmg` and we can switch to that. For now the plain
# UDZO compressed image is small (~10 MB) and the user just drag-drops the
# .app onto Applications.

APP_NAME="Session Cove"
EXECUTABLE="SessionCove"
VERSION="${VERSION:-0.1.0}"
DIST_DIR="dist"
APP_DIR=".build/release/$APP_NAME.app"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

VERSION="$VERSION" UNIVERSAL=1 bash "$SCRIPT_DIR/bundle.sh"

if [ ! -d "$APP_DIR" ]; then
    echo "❌ Bundle not found at $APP_DIR" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"
DMG_NAME="SessionCove-${VERSION}-universal.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

# Stage the .app + an Applications symlink so users can drag the app
# straight to /Applications without leaving the mounted volume. `mktemp -d`
# yields a unique path so re-running while a previous mount is still up
# doesn't collide.
STAGE=$(mktemp -d -t session-cove-dmg)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP_DIR" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "Building DMG → $DMG_PATH"
# UDZO = compressed read-only image. `-volname` is what shows up under
# /Volumes when mounted; keep it short so Finder doesn't truncate.
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" >/dev/null

SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo ""
echo "✅ DMG ready: $DMG_PATH ($SIZE)"
echo ""
echo "  First-run gatekeeper note (binary is unsigned):"
echo "    • Mount the DMG, drag Session Cove to Applications"
echo "    • Right-click the .app → Open the FIRST time, OR"
echo "    • xattr -dr com.apple.quarantine \"/Applications/$APP_NAME.app\""
echo ""
