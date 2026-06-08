#!/bin/bash
set -e

# One-command release: build DMG → create GitHub Release → upload asset.
#
# Usage:
#   bash scripts/create-release.sh 0.3.0
#   bash scripts/create-release.sh 0.3.0 --notes "Bug fixes and improvements"
#
# Prerequisites:
#   - gh CLI installed and authenticated (brew install gh && gh auth login)

VERSION="${1:?Usage: $0 <version> [--notes <text>]}"
shift

NOTES=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes) NOTES="$2"; shift 2 ;;
        *) shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

DMG_PATH="dist/SessionCove-${VERSION}-universal.dmg"

echo "=== Building DMG for v${VERSION} ==="
VERSION="$VERSION" bash "$SCRIPT_DIR/make-dmg.sh"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found at $DMG_PATH" >&2
    exit 1
fi

echo ""
echo "=== Creating GitHub Release v${VERSION} ==="

NOTES_ARG=""
if [ -n "$NOTES" ]; then
    NOTES_ARG="--notes $NOTES"
elif [ -f "releases/notes/${VERSION}.md" ]; then
    NOTES_ARG="--notes-file releases/notes/${VERSION}.md"
else
    NOTES_ARG="--generate-notes"
fi

gh release create "v${VERSION}" "$DMG_PATH" \
    --title "Session Cove v${VERSION}" \
    $NOTES_ARG

echo ""
echo "✅ Release v${VERSION} published!"
echo "   DMG: $DMG_PATH"
echo "   URL: https://github.com/koersliven/Session-cove/releases/tag/v${VERSION}"
