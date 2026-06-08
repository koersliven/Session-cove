#!/bin/bash
set -e

# Builds Session Cove as a universal (arm64 + x86_64) macOS app bundle.
# Set UNIVERSAL=0 to fall back to a single-arch host build (faster iteration).

APP_NAME="Session Cove"
BUNDLE_ID="com.sessioncove.app"
EXECUTABLE="SessionCove"
VERSION="${VERSION:-0.1.0}"
UNIVERSAL="${UNIVERSAL:-1}"

OUT_DIR=".build/release"
APP_DIR="$OUT_DIR/$APP_NAME.app"

if [ "$UNIVERSAL" = "1" ]; then
    echo "Building universal release (arm64 + x86_64)..."
    swift build -c release --arch arm64 --arch x86_64
    BUILD_PRODUCTS=".build/apple/Products/Release"
else
    echo "Building host-arch release..."
    swift build -c release
    HOST_ARCH=$(uname -m)
    BUILD_PRODUCTS=".build/${HOST_ARCH}-apple-macosx/release"
    if [ ! -f "$BUILD_PRODUCTS/$EXECUTABLE" ]; then
        BUILD_PRODUCTS=".build/release"
    fi
fi

if [ ! -f "$BUILD_PRODUCTS/$EXECUTABLE" ]; then
    echo "❌ Binary not found at $BUILD_PRODUCTS/$EXECUTABLE" >&2
    exit 1
fi

echo "Creating app bundle..."
mkdir -p "$OUT_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_PRODUCTS/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

# SwiftPM emits resource bundles next to the binary in the same Products dir.
RESOURCE_BUNDLE="$BUILD_PRODUCTS/SessionCove_SessionCove.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
else
    echo "⚠️  Resource bundle missing at $RESOURCE_BUNDLE — sounds/sprites may be missing." >&2
fi

cat > "$APP_DIR/Contents/Info.plist" << EOF
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
    <string>$VERSION</string>
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
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF

# Ad-hoc codesign with entitlements (enables network access without Apple Developer ID)
ENTITLEMENTS="$ROOT_DIR/SessionCove/Resources/SessionCove.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_DIR/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true
    codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
fi

echo "✅ App bundle: $APP_DIR"
if [ "$UNIVERSAL" = "1" ]; then
    echo "   Architectures: $(lipo -archs "$APP_DIR/Contents/MacOS/$EXECUTABLE" 2>/dev/null || echo unknown)"
fi
echo "   Run with: open \"$APP_DIR\""
