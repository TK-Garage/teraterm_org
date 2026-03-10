# Tera Term Mac — メニューリファレンス

## メニューバー構成

| メニュー | 説明 |
|---------|------|
| Application | アプリ情報・環境設定・終了 |
| File | 接続・ログ・ファイル送受信・転送 |
| Edit | コピー・ペースト・画面操作・履歴編集 |
| Setup | 各種設定ダイアログ・追加設定 |
| Code | 文字エンコーディング選択 |
| Control | 端末制御・マクロ実行・ブロードキャスト |
| Window | ウィンドウ操作・一覧 |
| Help | ヘルプ |

---

## Application メニュー

| メニュー項目 | ショートカット | アクション | 機能 | SF Symbol |
|-------------|-------------|----------|------|----------|
| About Tera Term Mac | — | `showAbout` | バージョン情報を表示 | info.circle |
| Preferences… | ⌘, | `showPreferences` | 環境設定（端末設定ダイアログ）を開く | gearshape |
| Hide Tera Term Mac | ⌘H | `NSApplication.hide` | アプリを隠す | eye.slash |
| Hide Others | ⌥⌘H | `NSApplication.hideOtherApplications` | 他のアプリを隠す | eye.slash.circle |
| Show All | — | `NSApplication.unhideAllApplications` | 全アプリを表示 | eye |
| Quit Tera Term Mac | ⌘Q | `NSApplication.terminate` | アプリを終了 | power |

---

## File メニュー

| メニュー項目 | ショートカット | アクション | 機能 | SF Symbol |
|-------------|-------------|----------|------|----------|
| New Connection… | ⌘N | `newConnection` | 新規接続ダイアログを表示 | network |
| New Window | ⌘T | `newWindow` | 新しいターミナルウィンドウを開く | macwindow.badge.plus |
| Duplicate Session | ⌘D | `duplicateSession` | 現在のセッションを複製 | doc.on.doc |
| Send File… | — | `showSendFileDialog` | ファイル送信ダイアログを表示 | arrow.up.doc |
| Receive File… | — | `showRecvFileDialog` | ファイル受信ダイアログを表示 | arrow.down.doc |
| Log… | — | `showLogDialog` | ログ記録ダイアログを表示 | doc.text |
| Stop Log | — | `stopLog` | ログ記録を停止 | doc.text.fill |
| Change Directory… | — | `showChangeDir` | ディレクトリ変更ダイアログを表示 | folder |
| **File Transfer** | | | **サブメニュー** | arrow.left.arrow.right |
| ├ XMODEM Send… | — | `xmodemSend` | XMODEM プロトコルでファイル送信 | arrow.up.doc |
| ├ XMODEM Receive… | — | `xmodemRecv` | XMODEM プロトコルでファイル受信 | arrow.down.doc |
| ├ ZMODEM Send… | — | `zmodemSend` | ZMODEM プロトコルでファイル送信 | arrow.up.doc |
| ├ ZMODEM Receive… | — | `zmodemRecv` | ZMODEM プロトコルでファイル受信 | arrow.down.doc |
| ├ Kermit Send… | — | `kermitSend` | Kermit プロトコルでファイル送信 | arrow.up.doc |
| └ Kermit Receive… | — | `kermitRecv` | Kermit プロトコルでファイル受信 | arrow.down.doc |
| Disconnect | — | `doDisconnect` | 現在の接続を切断 | xmark.circle |
| Close | ⌘W | `NSWindow.performClose` | ウィンドウを閉じる | xmark.square |

---

## Edit メニュー

| メニュー項目 | ショートカット | アクション | 機能 | SF Symbol |
|-------------|-------------|----------|------|----------|
| Copy | ⌘C | `NSText.copy` | 選択テキストをクリップボードにコピー | doc.on.doc |
| Copy as Table | — | `copyAsTable` | 選択テキストをタブ区切りでコピー | tablecells |
| Paste | ⌘V | `NSText.paste` | クリップボードから貼り付け | doc.on.clipboard |
| Paste Special… | — | `pasteSpecial` | 特殊ペースト（テキスト編集後送信） | doc.on.clipboard.fill |
| Clear Screen | — | `clearScreen` | 画面をクリア | rectangle.slash |
| Clear Buffer | — | `clearBuffer` | スクロールバッファをクリア | trash |
| Select All | ⌘A | `NSText.selectAll` | 全テキストを選択 | selection.pin.in.out |
| Edit History… | — | `showEditHistory` | ホスト接続履歴を編集 | clock.arrow.circlepath |

---

## Setup メニュー

| メニュー項目 | ショートカット | アクション | 機能 | SF Symbol |
|-------------|-------------|----------|------|----------|
| Terminal… | — | `setupTerminal` | 端末設定ダイアログを開く | terminal |
| Window… | — | `setupWindow` | ウィンドウ設定ダイアログを開く | macwindow |
| Font… | — | `setupFont` | フォント選択パネルを開く (NSFontPanel) | textformat.size |
| Keyboard… | — | `setupKeyboard` | キーボード設定ダイアログを開く | keyboard |
| Serial Port… | — | `setupSerialPort` | シリアルポート設定ダイアログを開く | cable.connector |
| TCP/IP… | — | `setupTCPIP` | TCP/IP 設定ダイアログを開く | network |
| Additional Settings… | — | `setupAdditional` | 追加設定タブダイアログを開く (13タブ) | slider.horizontal.3 |
| Save Setup… | — | `saveSetup` | 設定を JSON ファイルに保存 (NSSavePanel) | square.and.arrow.down |
| Restore Setup… | — | `restoreSetup` | JSON ファイルから設定を復元 (NSOpenPanel) | square.and.arrow.up |

### Additional Settings タブ一覧

| タブ名 | クラス | 対応オリジナル |
|-------|-------|-------------|
| General | `GeneralTab` | IDD_TABSHEET_GENERAL |
| Coding | `CodingTab` | IDD_TABSHEET_CODING |
| Copy and Paste | `CopyPasteTab` | IDD_TABSHEET_COPYPASTE |
| Sequence | `SequenceTab` | IDD_TABSHEET_SEQUENCE |
| Mouse | `MouseTab` | IDD_TABSHEET_MOUSE |
| Log | `LogTab` | IDD_TABSHEET_LOG |
| Visual | `VisualTab` | IDD_TABSHEET_VISUAL |
| Font | `FontTab` | IDD_TABSHEET_FONT |
| TEK Font | `TEKFontTab` | IDD_TABSHEET_TEKFONT |
| Theme | `ThemeTab` | IDD_TABSHEET_THEME |
| UI | `UITab` | IDD_TABSHEET_UI |
| Plugin | `PluginTab` | IDD_TABSHEET_PLUGIN |
| Debug | `DebugTab` | IDD_TABSHEET_DEBUG |

---

## Code メニュー（エンコーディング選択）

各エンコーディングは **Send & Receive** / **Receive** / **Send** の3モードで適用可能。

### サブメニュー構成

| サブメニュー | 方向 | SF Symbol |
|------------|------|----------|
| Send & Receive | 送受信両方 | arrow.left.arrow.right |
| Receive | 受信のみ | arrow.down.circle |
| Send | 送信のみ | arrow.up.circle |

### Unicode

| エンコーディング | 内部値 | displayName |
|----------------|-------|-------------|
| UTF-8 | `utf8` (1) | Unicode (UTF-8) |
| UTF-16 | `utf16` (30) | Unicode (UTF-16) |
| UTF-16BE | `utf16be` (31) | Unicode (UTF-16BE) |
| UTF-16LE | `utf16le` (32) | Unicode (UTF-16LE) |
| UTF-32 | `utf32` (33) | Unicode (UTF-32) |
| UTF-32BE | `utf32be` (34) | Unicode (UTF-32BE) |
| UTF-32LE | `utf32le` (35) | Unicode (UTF-32LE) |

### 日本語

| エンコーディング | 内部値 | displayName |
|----------------|-------|-------------|
| Shift JIS | `sjis` (2) | Japanese (Shift JIS) |
| EUC-JP | `eucjp` (3) | Japanese (EUC-JP) |
| ISO-2022-JP (JIS) | `jis` (4) | Japanese (ISO-2022-JP) |

### 中国語

| エンコーディング | 内部値 | displayName |
|----------------|-------|-------------|
| GB2312 (簡体字) | `gb2312` (21) | Chinese Simplified (GB2312) |
| GBK (簡体字) | `gbk` (36) | Chinese Simplified (GBK) |
| Big5 (繁体字) | `big5` (22) | Chinese Traditional (Big5) |
| Big5-HKSCS (繁体字) | `big5hkscs` (37) | Chinese Traditional (Big5-HKSCS) |

### 韓国語

| エンコーディング | 内部値 | displayName |
|----------------|-------|-------------|
| EUC-KR | `eucKR` (20) | Korean (EUC-KR) |

### 西欧 / ISO 8859

| エンコーディング | 内部値 | displayName |
|----------------|-------|-------------|
| ISO 8859-1 (Latin-1) | `iso8859_1` (5) | Western (ISO Latin 1) |
| ISO 8859-2 (Latin-2) | `iso8859_2` (6) | Central European (ISO Latin 2) |
| ISO 8859-3 (Latin-3) | `iso8859_3` (7) | ISO 8859-3 (Latin-3) |
| ISO 8859-4 (Latin-4) | `iso8859_4` (8) | ISO 8859-4 (Latin-4) |
| ISO 8859-5 (Cyrillic) | `iso8859_5` (9) | Cyrillic (ISO 8859-5) |
| ISO 8859-6 (Arabic) | `iso8859_6` (10) | Arabic (ISO 8859-6) |
| ISO 8859-7 (Greek) | `iso8859_7` (11) | Greek (ISO 8859-7) |
| ISO 8859-8 (Hebrew) | `iso8859_8` (12) | Hebrew (ISO 8859-8) |
| ISO 8859-9 (Latin-5) | `iso8859_9` (13) | ISO 8859-9 (Latin-5) |
| ISO 8859-10 (Latin-6) | `iso8859_10` (14) | ISO 8859-10 (Latin-6) |
| ISO 8859-11 (Thai) | `iso8859_11` (15) | Thai (TIS-620) |
| ISO 8859-13 (Latin-7) | `iso8859_13` (16) | ISO 8859-13 (Latin-7) |
| ISO 8859-14 (Latin-8) | `iso8859_14` (17) | ISO 8859-14 (Latin-8) |
| ISO 8859-15 (Latin-9) | `iso8859_15` (18) | ISO 8859-15 (Latin-9) |
| ISO 8859-16 (Latin-10) | `iso8859_16` (19) | ISO 8859-16 (Latin-10) |

### DOS / Windows

| エンコーディング | 内部値 | displayName |
|----------------|-------|-------------|
| DOS Latin US (CP437) | `cp437` (38) | DOS Latin US |
| DOS Japanese (CP932) | `cp932` (39) | DOS Japanese |
| Windows Latin 1 (CP1252) | `cp1252` (40) | Windows Latin 1 |
| Windows Cyrillic (CP1251) | `cp1251` (24) | Windows Cyrillic |
| Windows Greek (CP1253) | `cp1253` (41) | Windows Greek |
| Windows Hebrew (CP1255) | `cp1255` (42) | Windows Hebrew |
| Windows Arabic (CP1256) | `cp1256` (43) | Windows Arabic |
| DOS Russian (CP866) | `cp866` (23) | DOS Russian |
| KOI8-R | `koi8r` (25) | KOI8-R |

---

## Control メニュー

| メニュー項目 | ショートカット | アクション | 機能 | SF Symbol |
|-------------|-------------|----------|------|----------|
| Reset Terminal | — | `resetTerminal` | 端末エミュレータをリセット | arrow.counterclockwise |
| Are You There | — | `areYouThere` | Telnet AYT コマンドを送信 (0xFF 0xF6) | questionmark.circle |
| Send Break | — | `sendBreak` | ブレーク信号を送信 | exclamationmark.triangle |
| Reset Port | — | `resetPort` | ポート接続をリセット | arrow.triangle.2.circlepath |
| Macro… | ⇧⌘M | `runMacro` | TTL マクロスクリプトを実行 (.ttl) | applescript |
| Replay Log… | — | `replayLog` | ログファイルを再生 | play.rectangle |
| Command Broadcast | — | `toggleBroadcast` | ブロードキャストパネルの表示/非表示 | antenna.radiowaves.left.and.right |

---

## Window メニュー

| メニュー項目 | ショートカット | アクション | 機能 | SF Symbol |
|-------------|-------------|----------|------|----------|
| Minimize | ⌘M | `NSWindow.performMiniaturize` | ウィンドウを最小化 | minus.square |
| Zoom | — | `NSWindow.performZoom` | ウィンドウを拡大/縮小 | arrow.up.left.and.arrow.down.right |
| Window List… | — | `showWindowList` | ウィンドウ一覧を表示 | list.bullet.rectangle |

---

## Help メニュー

| メニュー項目 | ショートカット | アクション | 機能 | SF Symbol |
|-------------|-------------|----------|------|----------|
| Tera Term Mac Help | ⌘? | `showHelp` | teratermproject.github.io を開く | questionmark.circle |

---

## ダイアログ一覧

### 基本設定ダイアログ

| ダイアログ | 起動元 | コントローラ | オリジナル |
|----------|--------|------------|----------|
| New Connection | File → New Connection… | `AppDelegate` (インライン) | IDD_HOSTDLG |
| Terminal Setup | Setup → Terminal… | `TerminalSetupViewController` | IDD_TERMDLG |
| Window Setup | Setup → Window… | `WindowSetupViewController` | IDD_WINDLG |
| Keyboard Setup | Setup → Keyboard… | `KeyboardSetupViewController` | IDD_KEYBDLG |
| Serial Port Setup | Setup → Serial Port… | `SerialPortSetupViewController` | IDD_SERIALDLG |
| TCP/IP Setup | Setup → TCP/IP… | `TCPIPSetupViewController` | IDD_TCPIPDLG |
| SSH Authentication | 接続時自動表示 | `SSHAuthViewController` | — |

### ファイル転送ダイアログ

| ダイアログ | 起動元 | ヘルパー |
|----------|--------|---------|
| Send File | File → Send File… | `FileTransferDialogHelper` |
| Receive File | File → Receive File… | `FileTransferDialogHelper` |
| XMODEM Option (Accessory) | File Transfer → XMODEM | `FileTransferDialogHelper` |
| Protocol Transfer Progress | 転送中自動表示 | `ProtocolTransferPanel` |
| File Transfer Progress | 転送中自動表示 | `FileTransferProgressPanel` |
| Kermit Get | File Transfer → Kermit | `KermitGetDialog` |

### その他のダイアログ

| ダイアログ | 起動元 | コントローラ |
|----------|--------|------------|
| Log | File → Log… | `LogDialogController` |
| Change Directory | File → Change Directory… | `ChangeDirectoryDialog` |
| Edit History | Edit → Edit History… | `EditHistoryDialogController` |
| Window List | Window → Window List… | `WindowListDialog` |
| Clipboard Confirmation | ペースト時 | `ClipboardConfirmDialog` |
| Broadcast Panel | Control → Command Broadcast | `AppDelegate` (NSPanel) |

### マクロダイアログ

| ダイアログ | コントローラ |
|----------|------------|
| Macro Status Panel | `MacroStatusPanelController` |
| TTL Message Box | `DialogCommandProvider` |
| TTL Input Box | `DialogCommandProvider` |
| TTL List Box | `DialogCommandProvider` |
