#!/bin/bash
set -e

APP_NAME="Session Cove"
BUNDLE_ID="com.sessioncove.app"
EXECUTABLE="SessionCove"
INSTALL_DIR="/Applications"

echo ""
echo "  🏝  Session Cove Installer"
echo "  ─────────────────────────────"
echo ""

# --- Prerequisites ---

if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ Session Cove only runs on macOS."
    exit 1
fi

MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$MACOS_VERSION" -lt 14 ]]; then
    echo "❌ Requires macOS 14 (Sonoma) or later. You have $(sw_vers -productVersion)."
    exit 1
fi

if ! command -v swift &>/dev/null; then
    echo "❌ Swift not found. Install Xcode or Xcode Command Line Tools:"
    echo "   xcode-select --install"
    exit 1
fi

if ! command -v git &>/dev/null; then
    echo "❌ git not found. Install Xcode Command Line Tools:"
    echo "   xcode-select --install"
    exit 1
fi

# --- Clone or use local ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/Package.swift" ]]; then
    echo "📂 Using local source: $SCRIPT_DIR"
    BUILD_ROOT="$SCRIPT_DIR"
else
    CLONE_DIR="${TMPDIR:-/tmp}/session-cove-install"
    echo "📥 Cloning Session Cove..."
    rm -rf "$CLONE_DIR"
    git clone --depth 1 https://github.com/koersliven/Session-cove.git "$CLONE_DIR"
    BUILD_ROOT="$CLONE_DIR"
fi

cd "$BUILD_ROOT"

# --- Build ---

echo "🔨 Building release (this may take a minute)..."
swift build -c release 2>&1 | grep -E "^(Build|Compil|Link|error)" || true

BUILD_DIR=".build/release"
if [[ ! -f "$BUILD_DIR/$EXECUTABLE" ]]; then
    BUILD_DIR=".build/arm64-apple-macosx/release"
fi

if [[ ! -f "$BUILD_DIR/$EXECUTABLE" ]]; then
    echo "❌ Build failed. Binary not found."
    exit 1
fi

echo "✅ Build succeeded."

# --- Bundle .app ---

APP_DIR="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

RESOURCE_BUNDLE=$(find "$BUILD_DIR" -name "SessionCove_SessionCove.bundle" -maxdepth 1 2>/dev/null | head -1)
if [[ -z "$RESOURCE_BUNDLE" ]]; then
    RESOURCE_BUNDLE=$(find ".build/arm64-apple-macosx/release" -name "SessionCove_SessionCove.bundle" -maxdepth 1 2>/dev/null | head -1)
fi
if [[ -n "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Session Cove needs to send commands to your terminal to resume Claude Code sessions.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# --- Install ---

echo "📦 Installing to $INSTALL_DIR..."
if [[ -d "$INSTALL_DIR/$APP_NAME.app" ]]; then
    echo "   Removing existing installation..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi
cp -R "$APP_DIR" "$INSTALL_DIR/"

# --- Post-install: grant Automation permission hint ---

echo ""
echo "✅ Installed: $INSTALL_DIR/$APP_NAME.app"
echo ""
echo "  ─────────────────────────────"
echo "  Post-install steps:"
echo ""
echo "  1. Launch the app:"
echo "     open \"/Applications/$APP_NAME.app\""
echo ""
echo "  2. On first launch, the app will automatically:"
echo "     • Register the Claude Code PermissionRequest hook"
echo "     • Create ~/.session-cove/ for hook IPC"
echo ""
echo "  3. Grant Automation permission when prompted:"
echo "     System Settings → Privacy & Security → Automation"
echo "     → Session Cove → iTerm2 ✓"
echo ""
echo "  4. (Optional) Add to Login Items for auto-start:"
echo "     System Settings → General → Login Items → + → Session Cove"
echo "  ─────────────────────────────"
echo ""
echo "  🏝  Done! Run: open \"/Applications/$APP_NAME.app\""
echo ""
