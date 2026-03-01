#!/bin/bash
#
# Build Tera Term Mac as a proper .app bundle
#
# Usage:
#   ./build_app.sh          # Debug build
#   ./build_app.sh release  # Release build
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_TYPE="${1:-debug}"
APP_NAME="Tera Term Mac"
BUNDLE_ID="com.teraterm.mac"
EXECUTABLE="TeraTermMac"

echo "=== Building Tera Term Mac ($BUILD_TYPE) ==="

if [ "$BUILD_TYPE" = "release" ]; then
    swift build -c release
    BUILD_DIR=".build/release"
else
    swift build
    BUILD_DIR=".build/debug"
fi

echo "=== Creating .app bundle ==="

APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
rm -rf "$APP_DIR"

# Create bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Tera Term Mac</string>
    <key>CFBundleDisplayName</key>
    <string>Tera Term Mac</string>
    <key>CFBundleIdentifier</key>
    <string>com.teraterm.mac</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>TeraTermMac</string>
    <key>CFBundleIconFile</key>
    <string></string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "=== Build complete ==="
echo "App bundle: $APP_DIR"
echo ""
echo "To run:"
echo "  open \"$APP_DIR\""
echo ""
echo "Or from terminal:"
echo "  \"$APP_DIR/Contents/MacOS/$EXECUTABLE\""
