# Tera Term Mac — メニューリファレンス

## メニューバー構成

| メニュー | 説明 |
|---------|------|
| Application | アプリ情報・環境設定・終了 |
| File | 接続・ログ・ファイル転送 |
| Edit | コピー・ペースト・画面操作 |
| Setup | 各種設定ダイアログ |
| Code | 文字エンコーディング選択 |
| Control | 端末制御・マクロ実行 |
| Window | ウィンドウ操作 |
| Help | ヘルプ |

---

## Application メニュー

| メニュー項目 | ショートカット | アクション | 機能 |
|-------------|-------------|----------|------|
| About Tera Term Mac | — | `showAbout` | バージョン情報を表示 |
| Preferences… | ⌘, | `showPreferences` | 環境設定を開く |
| Hide Tera Term Mac | ⌘H | `NSApplication.hide` | アプリを隠す |
| Hide Others | ⌥⌘H | `NSApplication.hideOtherApplications` | 他のアプリを隠す |
| Show All | — | `NSApplication.unhideAllApplications` | 全アプリを表示 |
| Quit Tera Term Mac | ⌘Q | `NSApplication.terminate` | アプリを終了 |

---

## File メニュー

| メニュー項目 | ショートカット | アクション | 機能 |
|-------------|-------------|----------|------|
| New Connection… | ⌘N | `newConnection` | 新規接続ダイアログを表示 |
| New Window | ⌘T | `newWindow` | 新しいターミナルウィンドウを開く |
| Duplicate Session | ⌘D | `duplicateSession` | 現在のセッションを複製 |
| Log… | — | `startLog` | ログ記録を開始（NSSavePanel） |
| Stop Log | — | `stopLog` | ログ記録を停止 |
| **File Transfer** | | | **サブメニュー** |
| ├ XMODEM Send… | — | `xmodemSend` | XMODEM プロトコルでファイル送信 |
| ├ XMODEM Receive… | — | `xmodemRecv` | XMODEM プロトコルでファイル受信 |
| ├ ZMODEM Send… | — | `zmodemSend` | ZMODEM プロトコルでファイル送信 |
| ├ ZMODEM Receive… | — | `zmodemRecv` | ZMODEM プロトコルでファイル受信 |
| ├ Kermit Send… | — | `kermitSend` | Kermit プロトコルでファイル送信 |
| └ Kermit Receive… | — | `kermitRecv` | Kermit プロトコルでファイル受信 |
| Disconnect | — | `doDisconnect` | 現在の接続を切断 |
| Close | ⌘W | `NSWindow.performClose` | ウィンドウを閉じる |

---

## Edit メニュー

| メニュー項目 | ショートカット | アクション | 機能 |
|-------------|-------------|----------|------|
| Copy | ⌘C | `NSText.copy` | 選択テキストをクリップボードにコピー |
| Copy as Table | — | `copyAsTable` | 選択テキストをタブ区切りでコピー |
| Paste | ⌘V | `NSText.paste` | クリップボードから貼り付け |
| Paste Special… | — | `pasteSpecial` | 特殊ペースト（改行変換等） |
| Clear Screen | — | `clearScreen` | 画面をクリア |
| Clear Buffer | — | `clearBuffer` | スクロールバッファをクリア |
| Select All | ⌘A | `NSText.selectAll` | 全テキストを選択 |

---

## Setup メニュー

| メニュー項目 | ショートカット | アクション | 機能 |
|-------------|-------------|----------|------|
| Terminal… | — | `setupTerminal` | 端末設定ダイアログを開く |
| Window… | — | `setupWindow` | ウィンドウ設定ダイアログを開く |
| Font… | — | `setupFont` | フォント選択パネルを開く |
| Keyboard… | — | `setupKeyboard` | キーボード設定ダイアログを開く |
| Serial Port… | — | `setupSerialPort` | シリアルポート設定ダイアログを開く |
| Save Setup… | — | `saveSetup` | 設定を JSON ファイルに保存 |
| Restore Setup… | — | `restoreSetup` | JSON ファイルから設定を復元 |

---

## Code メニュー（エンコーディング選択）

各エンコーディングは **Send & Receive** / **Receive** / **Send** の3モードで適用可能。

### Unicode

| エンコーディング | 内部値 |
|----------------|-------|
| UTF-8 | `utf8` |
| UTF-16 | `utf16` |
| UTF-16BE | `utf16be` |
| UTF-16LE | `utf16le` |
| UTF-32 | `utf32` |
| UTF-32BE | `utf32be` |
| UTF-32LE | `utf32le` |

### 日本語

| エンコーディング | 内部値 |
|----------------|-------|
| Shift JIS | `sjis` |
| EUC-JP | `eucjp` |
| ISO-2022-JP (JIS) | `jis` |

### 中国語

| エンコーディング | 内部値 |
|----------------|-------|
| GB2312 (簡体字) | `gb2312` |
| GBK (簡体字) | `gbk` |
| Big5 (繁体字) | `big5` |
| Big5-HKSCS (繁体字) | `big5hkscs` |

### 韓国語

| エンコーディング | 内部値 |
|----------------|-------|
| EUC-KR | `eucKR` |

### 西欧 / ISO 8859

| エンコーディング | 内部値 |
|----------------|-------|
| ISO 8859-1 (Latin-1) | `iso8859_1` |
| ISO 8859-2 (Latin-2) | `iso8859_2` |
| ISO 8859-3 〜 16 | `iso8859_3` 〜 `iso8859_16` |

### DOS / Windows

| エンコーディング | 内部値 |
|----------------|-------|
| DOS Latin US (CP437) | `cp437` |
| DOS Japanese (CP932) | `cp932` |
| Windows Latin 1 (CP1252) | `cp1252` |
| Windows Cyrillic (CP1251) | `cp1251` |
| Windows Greek (CP1253) | `cp1253` |
| Windows Hebrew (CP1255) | `cp1255` |
| Windows Arabic (CP1256) | `cp1256` |
| DOS Russian (CP866) | `cp866` |
| KOI8-R | `koi8r` |

---

## Control メニュー

| メニュー項目 | ショートカット | アクション | 機能 |
|-------------|-------------|----------|------|
| Reset Terminal | — | `resetTerminal` | 端末エミュレータをリセット |
| Are You There | — | `areYouThere` | Telnet AYT コマンドを送信 |
| Send Break | — | `sendBreak` | ブレーク信号を送信 |
| Reset Port | — | `resetPort` | ポート接続をリセット |
| Macro… | ⇧⌘M | `runMacro` | TTL マクロスクリプトを実行 |
| Replay Log… | — | `replayLog` | ログファイルを再生 |
| Command Broadcast | — | `toggleBroadcast` | ブロードキャストパネルの表示/非表示 |

---

## Window メニュー

| メニュー項目 | ショートカット | アクション | 機能 |
|-------------|-------------|----------|------|
| Minimize | ⌘M | `NSWindow.performMiniaturize` | ウィンドウを最小化 |
| Zoom | — | `NSWindow.performZoom` | ウィンドウを拡大/縮小 |

---

## Help メニュー

| メニュー項目 | ショートカット | アクション | 機能 |
|-------------|-------------|----------|------|
| Tera Term Mac Help | ⌘? | `showHelp` | ヘルプを表示 |
