# 多言語化（ローカライズ）対応状況

> **調査日**: 2026-03-17
> **対象言語**: 日本語 (ja) / 英語 (en)
> **対象アプリ**: TeraTermMac.app / TTLMacro.app / Keycode.app

---

## 1. アーキテクチャ概要

### ローカライズ関数

プロジェクト全体で2種類のローカライズヘルパー関数を使用している。Apple 標準の `NSLocalizedString()` は使用していない。

| 関数 | 定義ファイル | 使用モジュール | バンドル解決 |
|------|------------|--------------|------------|
| `TTL()` | `Settings/DialogConstants.swift` | TeraTermMac.app | `.lproj` バンドル or パース済み辞書 |
| `L()` | `TTLMacroShared/MacroLocalizable.swift` | TTLMacro.app, TTLMacroShared | `Bundle.module` (SPM) |
| `L()` | `Keycode/KeycodeLocalizable.swift` | Keycode.app | `Bundle.module` (SPM) |

- `TTL()` は `UserDefaults("TeraTermUILanguage")` の設定 (Auto/English/Japanese) に基づき言語を選択
- `L()` (TTLMacroShared) も同様に `UserDefaults("TeraTermUILanguage")` を参照
- `L()` (Keycode) は `Bundle.module` のみ参照（ユーザー言語設定なし）
- いずれも可変長引数版 `TTL(key, args...)` / `L(key, args...)` をサポート

### Localizable.strings ファイル

| モジュール | en キー数 | ja キー数 | 同期状態 |
|-----------|----------|----------|---------|
| TeraTermMac | 887 | 887 | 完全同期 |
| TTLMacroShared | 25 | 25 | 完全同期 |
| TTLMacro | 2 | 2 | 完全同期 |
| Keycode | 14 | 14 | 完全同期 |
| **合計** | **928** | **928** | **完全同期** |

既存の `.strings` ファイルでは en/ja 間のキー欠落はなく、完全に同期されている。

---

## 2. モジュール別対応状況

### 2.1 TeraTermMac.app — 対応率: 高

**対応済み (887キー):**
- メインメニュー全項目
- 全設定ダイアログ（Additional Settings 含む）
- SSH 接続ダイアログ
- ファイル転送ダイアログ
- コンテキストメニュー
- エラー/確認ダイアログ大部分
- ステータスバー表示

**TTL() 使用状況:** 960箇所 / 26ファイル

**未対応箇所:**

| # | ファイル | 行 | ハードコード文字列 | 分類 |
|---|---------|----|--------------------|------|
| 1 | `App/MacroXPCManager.swift` | 684 | `"Macro Error (line \(line))"` | エラーダイアログ タイトル |
| 2 | `App/MacroXPCManager.swift` | 685 | `"File: \(fileName)"` | エラーダイアログ 本文 |
| 3 | `App/MacroXPCManager.swift` | 687 | `"Stop"` | ボタンタイトル |
| 4 | `App/MacroXPCManager.swift` | 688 | `"Continue"` | ボタンタイトル |
| 5 | `App/MacroXPCManager.swift` | 698 | `"Status"` | ステータスダイアログ タイトル |
| 6 | `Settings/DialogConstants.swift` | 419 | `"OK"` (デフォルト値) | ボタンデフォルト値 |
| 7 | `Settings/DialogConstants.swift` | 420 | `"Cancel"` (デフォルト値) | ボタンデフォルト値 |
| 8 | `Settings/BroadcastDialog.swift` | 146 | `"Close"` | ボタンタイトル |
| 9 | `Settings/MiscDialogs.swift` | 493 | `"..."` (Browse) | ボタンタイトル（要検討） |

---

### 2.2 TTLMacro.app — 対応率: 低

**対応済み (2キー):**
- `macro.open.title` — ファイル選択ダイアログタイトル
- `macro.open.prompt` — 実行ボタン

**L() 使用状況:** 22箇所 / 5ファイル（大部分は TTLMacroShared の25キーを参照）

**未対応箇所:**

| # | ファイル | 行 | ハードコード文字列 | 分類 |
|---|---------|----|--------------------|------|
| 1 | `StatusBarManager.swift` | 262 | `"Step Line (F10)"` | デバッガメニュー項目 |
| 2 | `StatusBarManager.swift` | 268 | `"Step Over (F11)"` | デバッガメニュー項目 |
| 3 | `StatusBarManager.swift` | 274 | `"Step Out (Shift+F11)"` | デバッガメニュー項目 |
| 4 | `StatusBarManager.swift` | 315 | `"M"` | ステータスバーアイコン文字 |
| 5 | `VariableWatchPanel.swift` | 85 | `"Filter variables..."` | プレースホルダー |
| 6 | `VariableWatchPanel.swift` | 93 | `"Variable"` | テーブルカラムヘッダ |
| 7 | `VariableWatchPanel.swift` | 98 | `"Value"` | テーブルカラムヘッダ |
| 8 | `VariableWatchPanel.swift` | 152 | `"Variable Watch"` | パネルタイトル |

---

### 2.3 TTLMacroShared — 対応率: 中

**対応済み (25キー):**
- マクロメニュー（Running, Paused, Line, Pause, Resume, Stop, Open, Quit, Watch Variables）
- 停止確認ダイアログ
- 共通ダイアログボタン（OK, Cancel, Yes, No）
- マクロエラー（noFile, cancelled, syntaxError）
- ステータス表示（running, paused）

**未対応箇所:**

| # | ファイル | 行 | ハードコード文字列 | 分類 |
|---|---------|----|--------------------|------|
| 1 | `TransferErrorDetail.swift` | 103 | `"\(proto) \(dir) Failed"` | 転送エラーダイアログタイトル |
| 2 | `TransferErrorDetail.swift` | 107 | `"File: \(path)"` | 転送エラー詳細ラベル |
| 3 | `TransferErrorDetail.swift` | 109 | `"Progress: \(text)"` | 転送エラー詳細ラベル |
| 4 | `TransferErrorDetail.swift` | 110 | `"Line: \(num)"` | 転送エラー詳細ラベル |
| 5 | `TransferErrorDetail.swift` | 114 | `"OK"` | ボタンタイトル |
| 6 | `TTLParserShared.swift` | 179-199 | TTLError 21メッセージ | パーサーエラーメッセージ全体 |

**TTLError メッセージ一覧（全21件・全て未対応）:**

| エラーコード | ハードコード英語メッセージ |
|-------------|------------------------|
| `closeParenExpected` | "Close parenthesis expected" |
| `cannotCall` | "Cannot call" |
| `cannotConnect` | "Cannot connect" |
| `cannotOpenFile` | "Cannot open file" |
| `divisionByZero` | "Division by zero" |
| `invalidControl` | "Invalid control" |
| `labelAlreadyDef` | "Label already defined" |
| `labelReq` | "Label required" |
| `linkFirst` | "Link first" |
| `stackOverflow` | "Stack overflow" |
| `syntax` | "Syntax error" |
| `tooManyLabels` | "Too many labels" |
| `tooManyVar` | "Too many variables" |
| `typeMismatch` | "Type mismatch" |
| `varNotInit` | "Variable not initialized" |
| `closeCommentExpected` | "Close comment expected" |
| `outOfRange` | "Out of range" |
| `closeBracketExpected` | "Close bracket expected" |
| `notEnoughMemory` | "Not enough memory" |
| `notSupported` | "Not supported" |
| `cannotExecute` | "Cannot execute" |

---

### 2.4 MacroRunner.swift エラーメッセージ — 対応率: 未対応

MacroRunner.swift の `reportError()` に渡されるエラーメッセージは全てハードコード英語。

**未対応件数: 33件**

| カテゴリ | 件数 | 代表例 |
|---------|------|--------|
| 制御フロー | 8 | `"goto: label not found: \(label)"` |
| 送受信 | 3 | `"sendfile: cannot read file: \(filePath)"` |
| Wait系 | 4 | `"wait: at least one pattern required"` |
| ファイルI/O | 1 | `"fileopen: requires handlevar, filepath, mode"` |
| パスワード | 2 | `"getpassword: requires filename, keyname, varname"` |
| ファイル転送 | 12 | `"\(proto)send: transfer already in progress"` |
| SCP | 2 | `"scpsend: localpath and remotepath required"` |
| その他 | 1 | `"Not implemented: \(cmd)"` |

---

### 2.5 Keycode.app — 対応率: 高（一部例外）

**対応済み (14キー):**
- ウィンドウタイトル
- プロンプトメッセージ
- キーコード結果表示
- Option キーヒント
- メニュー項目全体（About, Hide, Quit, Window, Minimize, Close）

**未対応箇所:**

| # | ファイル | 行 | ハードコード文字列 | 分類 |
|---|---------|----|--------------------|------|
| 1 | `PCKeyCode.swift` | 60 | `"Return"`, `"Tab"`, `"Space"` 等 | キー名 (40+件) |
| 2 | `PCKeyCode.swift` | 64-68 | `"F1"`〜`"F20"` | ファンクションキー名 |
| 3 | `PCKeyCode.swift` | 74-75 | `"Delete"`, `"Home"`, `"End"` 等 | 特殊キー名 |
| 4 | `PCKeyCode.swift` | 78-83 | `"Keypad 0"`〜`"Keypad Enter"` | テンキー名 |
| 5 | `PCKeyCode.swift` | 151-154 | `"Shift"`, `"Ctrl"`, `"Option"`, `"Cmd"` | 修飾キー名 |
| 6 | `PCKeyCode.swift` | 159 | `" + "` (結合子) | キー組み合わせ区切り |

> **注記:** キー名は国際的に英語表記が標準であるため、ローカライズ不要と判断する方針もある。ただし macOS のシステム環境設定では日本語表記（"リターン"、"スペース"等）を使用しているケースもあり、方針決定が必要。

---

## 3. 未対応箇所サマリー

| モジュール | 未対応件数 | 内訳 |
|-----------|----------|------|
| TeraTermMac.app | 9 | ダイアログ・ボタン |
| TTLMacro.app | 8 | デバッガUI・変数ウォッチ |
| TTLMacroShared | 26 | 転送エラー(5) + TTLError(21) |
| MacroRunner.swift | 33 | reportError メッセージ全体 |
| Keycode.app | 47 | キー名・修飾キー名 |
| **合計** | **123** | |

### 優先度別分類

#### P1: ユーザーに直接表示されるUI文字列 (17件)

| 件数 | 対象 |
|------|------|
| 9 | TeraTermMac.app ダイアログ・ボタン |
| 8 | TTLMacro.app デバッガメニュー・変数ウォッチパネル |

#### P2: エラーダイアログに表示されるメッセージ (59件)

| 件数 | 対象 |
|------|------|
| 5 | TransferErrorDetail 転送エラー表示 |
| 21 | TTLError パーサーエラーメッセージ |
| 33 | MacroRunner reportError メッセージ |

#### P3: 方針検討が必要な項目 (47件)

| 件数 | 対象 |
|------|------|
| 47 | Keycode.app キー名・修飾キー名 |

---

## 4. 推奨対応手順

### Step 1: TTLMacro.app の UI 文字列 (P1)

`TTLMacro/Resources/{en,ja}.lproj/Localizable.strings` にキーを追加:

```properties
# 追加が必要なキー例
"debugger.stepLine" = "Step Line (F10)";
"debugger.stepOver" = "Step Over (F11)";
"debugger.stepOut" = "Step Out (Shift+F11)";
"watch.title" = "Variable Watch";
"watch.filter" = "Filter variables...";
"watch.column.variable" = "Variable";
"watch.column.value" = "Value";
```

### Step 2: TeraTermMac.app の残りダイアログ (P1)

`TeraTermMac/Resources/{en,ja}.lproj/Localizable.strings` にキーを追加:

```properties
"macro.error.dialog.title" = "Macro Error (line %d)";
"macro.error.dialog.file" = "File: %@";
"macro.error.dialog.stop" = "Stop";
"macro.error.dialog.continue" = "Continue";
"dialog.status" = "Status";
"dialog.close" = "Close";
```

### Step 3: TTLError メッセージの多言語化 (P2)

`TTLParserShared.swift` の `TTLError.message` プロパティで `L()` を使用:

```swift
case .syntax: return L("error.syntax")
case .typeMismatch: return L("error.typeMismatch")
```

`TTLMacroShared/Resources/{en,ja}.lproj/Localizable.strings` に21キーを追加。

### Step 4: MacroRunner エラーメッセージ (P2)

`reportError()` の引数を `L()` ラップ:

```swift
reportError(L("error.goto.labelNotFound", label))
```

33件のキーを `TTLMacroShared/Resources/` に追加。

### Step 5: Keycode キー名 (P3)

方針決定後に対応。キー名を英語のまま維持するか、macOS 準拠の日本語表記にするか。

---

## 5. 既存実装の注意点

### L() 関数の重複定義

`L()` は2ファイルで別々に定義されている:
- `TTLMacroShared/MacroLocalizable.swift` — `public func L()` (UserDefaults 参照あり)
- `Keycode/KeycodeLocalizable.swift` — `func L()` (UserDefaults 参照なし)

Keycode.app の `L()` は言語設定 (`TeraTermUILanguage`) を参照しないため、OS のシステム言語に依存する。TeraTermMac のアプリ内言語切替が Keycode には反映されない。統一するなら TTLMacroShared の `L()` を共通利用することを検討。

### TTL() のフォールバック戦略

`DialogConstants.swift` の `TTL()` は2段階のフォールバックを持つ:
1. `.lproj` バンドルが見つかった場合 → `bundle.localizedString()`
2. バンドルが見つからない場合 → パース済み辞書から直接引く

SPM ビルドではバンドル解決が不安定になる場合があるため、辞書フォールバックが設けられている。
