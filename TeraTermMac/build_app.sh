#!/bin/bash
#
# Tera Term Mac を .app バンドルとしてビルド
#
# 使い方:
#   ./build_app.sh          # デバッグビルド
#   ./build_app.sh release  # リリースビルド
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_TYPE="${1:-debug}"
APP_NAME="Tera Term Mac"
BUNDLE_ID="com.teraterm.mac"
EXECUTABLE="TeraTermMac"

echo "=== Tera Term Mac ビルド開始 ($BUILD_TYPE) ==="

if [ "$BUILD_TYPE" = "release" ]; then
    swift build -c release
    BUILD_DIR=".build/release"
else
    swift build
    BUILD_DIR=".build/debug"
fi

echo "=== .app バンドル作成 ==="

APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
rm -rf "$APP_DIR"

# バンドル構造作成
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 実行ファイルコピー
cp "$BUILD_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

# Info.plist 作成
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
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
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

# PkgInfo 作成
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

# アイコンファイルコピー (.icns があれば使用)
ICON_DIR="Sources/TeraTermMac/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICON_DIR" ]; then
    # actool が使える場合はアセットカタログをコンパイル
    if command -v actool &> /dev/null; then
        actool --compile "$APP_DIR/Contents/Resources" \
               --platform macosx \
               --minimum-deployment-target 13.0 \
               --app-icon AppIcon \
               --output-partial-info-plist /dev/null \
               "Sources/TeraTermMac/Resources/Assets.xcassets"
        echo "  アセットカタログからアイコンをコンパイルしました"
    elif command -v iconutil &> /dev/null; then
        # iconutil で .icns を生成
        ICONSET_DIR="/tmp/TeraTermMac.iconset"
        rm -rf "$ICONSET_DIR"
        mkdir -p "$ICONSET_DIR"
        # アイコンファイルをiconutilの命名規則にコピー
        cp "$ICON_DIR/icon_16x16.png"     "$ICONSET_DIR/icon_16x16.png"     2>/dev/null || true
        cp "$ICON_DIR/icon_16x16@2x.png"  "$ICONSET_DIR/icon_16x16@2x.png"  2>/dev/null || true
        cp "$ICON_DIR/icon_32x32.png"      "$ICONSET_DIR/icon_32x32.png"     2>/dev/null || true
        cp "$ICON_DIR/icon_32x32@2x.png"  "$ICONSET_DIR/icon_32x32@2x.png"  2>/dev/null || true
        cp "$ICON_DIR/icon_128x128.png"    "$ICONSET_DIR/icon_128x128.png"   2>/dev/null || true
        cp "$ICON_DIR/icon_128x128@2x.png" "$ICONSET_DIR/icon_128x128@2x.png" 2>/dev/null || true
        cp "$ICON_DIR/icon_256x256.png"    "$ICONSET_DIR/icon_256x256.png"   2>/dev/null || true
        cp "$ICON_DIR/icon_256x256@2x.png" "$ICONSET_DIR/icon_256x256@2x.png" 2>/dev/null || true
        cp "$ICON_DIR/icon_512x512.png"    "$ICONSET_DIR/icon_512x512.png"   2>/dev/null || true
        cp "$ICON_DIR/icon_512x512@2x.png" "$ICONSET_DIR/icon_512x512@2x.png" 2>/dev/null || true
        iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
        rm -rf "$ICONSET_DIR"
        echo "  iconutil で AppIcon.icns を生成しました"
    else
        # フォールバック: 最大サイズの PNG を直接コピー
        if [ -f "$ICON_DIR/icon_512x512@2x.png" ]; then
            cp "$ICON_DIR/icon_512x512@2x.png" "$APP_DIR/Contents/Resources/AppIcon.png"
            echo "  PNG アイコンをコピーしました (actool/iconutil が見つかりません)"
        fi
    fi
fi

# ローカライズファイルコピー
for lang in en ja; do
    LPROJ="Sources/TeraTermMac/Resources/${lang}.lproj"
    if [ -d "$LPROJ" ]; then
        mkdir -p "$APP_DIR/Contents/Resources/${lang}.lproj"
        cp "$LPROJ"/*.strings "$APP_DIR/Contents/Resources/${lang}.lproj/" 2>/dev/null || true
    fi
done

echo "=== ビルド完了 ==="
echo "アプリバンドル: $APP_DIR"
echo ""
echo "実行方法:"
echo "  open \"$APP_DIR\""
echo ""
echo "ターミナルから直接実行:"
echo "  \"$APP_DIR/Contents/MacOS/$EXECUTABLE\""
