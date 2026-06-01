#!/bin/bash
set -e

# Builds a universal Session Cove .app and zips it for distribution.
# Output: dist/SessionCove-<version>-universal.zip
#
# Usage:
#   bash scripts/make-release.sh           # version from bundle.sh default (0.1.0)
#   VERSION=0.2.0 bash scripts/make-release.sh

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
ZIP_NAME="SessionCove-${VERSION}-universal.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"

# `ditto` preserves resource forks / extended attributes so the .app stays
# launch-able after extraction. `zip -r` would silently strip those.
echo "Zipping → $ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo ""
echo "✅ Release ready: $ZIP_PATH ($SIZE)"
echo ""
echo "  Note: this binary is unsigned. First-run users must either:"
echo "    • Right-click → Open (one time), OR"
echo "    • xattr -dr com.apple.quarantine \"/Applications/$APP_NAME.app\""
echo ""
