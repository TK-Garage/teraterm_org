# Icon Composer ワークフロー

## ファイル構成

```
Resources/
├── AppIcon_source_1024.png   ← Icon Composer用ソース画像 (アプリアイコン)
├── FileIcon_source_1024.png  ← Icon Composer用ソース画像 (TTLファイルアイコン)
├── AppIcon.icns              ← ビルドで使用されるアプリアイコン
├── FileIcon.icns             ← ビルドで使用される.ttlファイルアイコン
└── Info.plist                ← CFBundleIconFile / CFBundleDocumentTypes 定義
```

## 1. Icon Composer でのアイコン作成手順

### A. アプリアイコン (AppIcon.icns)

1. **Icon Composer を起動** (Xcode 16+ 付属、または Apple Developer サイトからダウンロード)
2. **ソース画像を読み込む**: `AppIcon_source_1024.png` をドラッグ＆ドロップ
3. **各解像度の確認**: Icon Composer が自動的に以下のサイズを生成:

   | スロット | ピクセル | 用途 |
   |---------|---------|------|
   | 512x512@2x | 1024x1024 | Retina ディスプレイ |
   | 512x512 | 512x512 | 標準ディスプレイ |
   | 256x256@2x | 512x512 | Retina (小) |
   | 256x256 | 256x256 | 標準 (小) |
   | 128x128@2x | 256x256 | Retina (Finder) |
   | 128x128 | 128x128 | Finder |
   | 32x32@2x | 64x64 | Retina (Dock小) |
   | 32x32 | 32x32 | Dock小 |
   | 16x16@2x | 32x32 | Retina (メニュー) |
   | 16x16 | 16x16 | メニューバー |

4. **書き出し**: File > Export > `AppIcon.icns` として保存

### B. TTLファイルアイコン (FileIcon.icns)

1. 同様に `FileIcon_source_1024.png` を読み込む
2. 各解像度を確認
3. `FileIcon.icns` として書き出し

## 2. Xcode プロジェクトへの配置

### 配置場所

```
TeraTermMac/Sources/TeraTermMac/Resources/AppIcon.icns
TeraTermMac/Sources/TeraTermMac/Resources/FileIcon.icns
```

### Package.swift の設定 (既に設定済み)

```swift
resources: [
    .process("Resources"),
]
```

`Resources` フォルダ内のファイルは自動的にバンドルに含まれます。

### Info.plist の設定 (既に設定済み)

```xml
<!-- アプリアイコン -->
<key>CFBundleIconFile</key>
<string>AppIcon.icns</string>

<!-- .ttl ファイルアイコン -->
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Tera Term Macro</string>
        <key>CFBundleTypeIconFile</key>
        <string>FileIcon.icns</string>
        <key>CFBundleTypeExtensions</key>
        <array>
            <string>ttl</string>
        </array>
        ...
    </dict>
</array>
```

### Xcode で "Add to Targets" する場合

Xcode プロジェクト (.xcodeproj) を使用する場合:
1. `.icns` ファイルを Project Navigator にドラッグ
2. "Add to Targets" で **TeraTermMac** にチェック
3. "Copy items if needed" にチェック

SPM (Package.swift) ベースの場合は、Resources フォルダに配置するだけで自動的に含まれます。

## 3. 本番アイコンへの差し替え手順

**コードの変更は一切不要です。**

### 手順

1. デザイナーが Icon Composer で本番用アイコンを作成
2. 書き出した `.icns` ファイルの名前を確認:
   - アプリアイコン → `AppIcon.icns`
   - TTLファイルアイコン → `FileIcon.icns`
3. プロジェクト内の既存ファイルを**上書き保存**:
   ```
   Resources/AppIcon.icns   ← 上書き
   Resources/FileIcon.icns  ← 上書き
   ```
4. Xcode で Clean Build (Cmd+Shift+K) → Build (Cmd+B)
5. 完了

### 注意事項

- ファイル名を変更しないこと (`AppIcon.icns`, `FileIcon.icns`)
- Info.plist の修正は不要
- ソース画像 (`*_source_1024.png`) は参考用として保持してもよいし、削除してもビルドに影響なし

## 4. コマンドラインでの .icns 作成 (Icon Composer の代替)

macOS 上で `iconutil` を使用する場合:

```bash
# 1. iconset フォルダを作成
mkdir AppIcon.iconset

# 2. 各サイズの PNG を配置
sips -z 16 16     AppIcon_source_1024.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     AppIcon_source_1024.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     AppIcon_source_1024.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     AppIcon_source_1024.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   AppIcon_source_1024.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   AppIcon_source_1024.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   AppIcon_source_1024.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   AppIcon_source_1024.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   AppIcon_source_1024.png --out AppIcon.iconset/icon_512x512.png
cp                 AppIcon_source_1024.png AppIcon.iconset/icon_512x512@2x.png

# 3. .icns に変換
iconutil -c icns AppIcon.iconset -o AppIcon.icns

# 4. クリーンアップ
rm -rf AppIcon.iconset
```
