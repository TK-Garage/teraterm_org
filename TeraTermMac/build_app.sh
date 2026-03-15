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

# SPM リソースバンドルコピー (Bundle.module が参照する)
# SPM は実行ファイルと同じディレクトリに _<Target>.bundle を生成する
RESOURCE_BUNDLE="${EXECUTABLE}_${EXECUTABLE}.bundle"
if [ -d "$BUILD_DIR/$RESOURCE_BUNDLE" ]; then
    cp -R "$BUILD_DIR/$RESOURCE_BUNDLE" "$APP_DIR/Contents/MacOS/$RESOURCE_BUNDLE"
    echo "  SPM リソースバンドル ($RESOURCE_BUNDLE) をコピーしました"
else
    echo "  警告: SPM リソースバンドル ($RESOURCE_BUNDLE) が見つかりません"
fi

# Info.plist コピー (ソースの完全な Info.plist を使用)
cp "Sources/TeraTermMac/Info.plist" "$APP_DIR/Contents/Info.plist"

# CFBundleDevelopmentRegion と CFBundleLocalizations を追加
# (macOS がローカライズリソースを正しく検出するために必要)
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string ja" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion ja" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations array" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations:0 string ja" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations:1 string en" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true

# PkgInfo 作成
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

# アイコンファイルコピー
RESOURCES_DIR="Sources/TeraTermMac/Resources"

# 既存の .icns ファイルを優先的にコピー
if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "  AppIcon.icns をコピーしました"
else
    # .icns が無い場合、アセットカタログからビルド
    ICON_DIR="$RESOURCES_DIR/Assets.xcassets/AppIcon.appiconset"
    if [ -d "$ICON_DIR" ]; then
        if command -v actool &> /dev/null; then
            actool --compile "$APP_DIR/Contents/Resources" \
                   --platform macosx \
                   --minimum-deployment-target 13.0 \
                   --app-icon AppIcon \
                   --output-partial-info-plist /dev/null \
                   "$RESOURCES_DIR/Assets.xcassets"
            echo "  アセットカタログからアイコンをコンパイルしました"
        elif command -v iconutil &> /dev/null; then
            ICONSET_DIR="/tmp/TeraTermMac.iconset"
            rm -rf "$ICONSET_DIR"
            mkdir -p "$ICONSET_DIR"
            for f in "$ICON_DIR"/icon_*.png; do
                cp "$f" "$ICONSET_DIR/" 2>/dev/null || true
            done
            iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
            rm -rf "$ICONSET_DIR"
            echo "  iconutil で AppIcon.icns を生成しました"
        fi
    fi
fi

# FileIcon.icns をコピー (.ttl ファイル用アイコン)
if [ -f "$RESOURCES_DIR/FileIcon.icns" ]; then
    cp "$RESOURCES_DIR/FileIcon.icns" "$APP_DIR/Contents/Resources/FileIcon.icns"
    echo "  FileIcon.icns をコピーしました"
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
