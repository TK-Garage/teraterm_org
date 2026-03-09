# AppKit ダイアログ・スナップショット自動生成エンジン

## 概要

macOS 版 Tera Term の各設定ダイアログが指定ウィンドウサイズ内に収まっているかを、ビルド時に PNG 画像で自動検証する仕組み。

## 追加ファイル

### 1. `NSView+DebugSnapshot.swift`

NSView エクステンション。`saveToDebugPNG(name:)` メソッドを提供。

- `layoutSubtreeIfNeeded()` でレイアウト確定
- `cacheDisplay(in:to:)` でオフスクリーン描画（ウィンドウ表示不要）
- **2pt 赤枠**で境界を視覚化し、はみ出しを確認可能
- 保存先: `~/Desktop/TT_UI_Preview/<name>_<yyyyMMdd>.png`

### 2. `SnapshotGenerator.swift`

3 つのダイアログを生成し PNG 出力するクラス。

| # | ダイアログ | サイズ | 検証ポイント |
|---|-----------|--------|-------------|
| 01 | NewConnection | 520 x 260 | ホスト名入力欄、ラジオボタンの文字切れ |
| 02 | TerminalSetup | 500 x 420 | チェックボックスと入力欄の干渉 |
| 03 | KeyboardSetup | 540 x 450 | ラジオボタン群の垂直方向の重なり |

- オフスクリーン `NSWindow` にホストして Auto Layout を解決
- `fittingSize` が spec サイズを超えた場合に WARNING ログ出力

### 3. `Scripts/generate_ui_snapshots.sh`

Xcode Run Script Phase 用シェルスクリプト。

- スタンドアロンコンパイル → 実行
- 失敗時はビルド済みバイナリ + `--generate-snapshots` フラグでフォールバック
- `--open` オプションで Finder 自動表示

### 4. `AppDelegate.swift` の変更

- `--generate-snapshots` 引数を検出した場合、スナップショット生成後に自動終了

## Xcode への組み込み手順

1. **Xcode** → **Build Phases** → **+** → **New Run Script Phase**
2. Shell に以下を入力:

```bash
${SRCROOT}/Scripts/generate_ui_snapshots.sh
```

3. Finder 自動表示が必要な場合:

```bash
${SRCROOT}/Scripts/generate_ui_snapshots.sh --open
```

## 使い方（コマンドライン）

```bash
cd TeraTermMac

# ビルド後に実行
swift build
.build/debug/TeraTermMac --generate-snapshots

# または直接スクリプトで
./Scripts/generate_ui_snapshots.sh --open
```

## 出力例

```
~/Desktop/TT_UI_Preview/
├── 01_NewConnection_20260309.png
├── 02_TerminalSetup_20260309.png
└── 03_KeyboardSetup_20260309.png
```

各画像はビュー境界に **2pt の赤枠** が描画され、コンテンツがはみ出していないか一目で確認できる。
