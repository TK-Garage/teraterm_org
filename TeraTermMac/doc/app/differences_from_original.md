# TeraTerm Mac.app - オリジナル Windows 版との差分

## 概要

TeraTerm Mac は Windows 版 Tera Term (v5.x) を macOS にフォーク移植したものである。
本文書では、アーキテクチャ、機能、実装の各レベルでの差分をまとめる。

---

## アーキテクチャの差分

### 言語・フレームワーク

| 項目 | Windows 版 | Mac 版 |
|------|-----------|--------|
| 言語 | C/C++ | Swift 5.9 |
| UI フレームワーク | Win32 API (GDI/GDI+/DirectWrite) | AppKit (Core Text) |
| ビルドシステム | Visual Studio / CMake | Swift Package Manager / Xcode |
| 最小 OS | Windows XP 以降 | macOS 13.0 |
| 実行形態 | .exe + DLL プラグイン | 単一 .app バンドル |

### コンポーネント構成

| Windows 版 | Mac 版 | 備考 |
|-----------|--------|------|
| ttermpro.exe | TeraTermMac (executable) | メイン端末アプリ |
| ttpcmn.dll | ConnectionManager.swift | 通信共通ライブラリ |
| ttpdlg.dll | Settings/*.swift | ダイアログ群 |
| ttpfile.dll | FileTransferProtocol.swift | ファイル転送 |
| ttpset.dll | TerminalSettings.swift | 設定管理 |
| ttptek.dll | TEKWindowController.swift | TEK エミュレーション |
| ttpmacro.exe | TTLMacro (executable) | マクロ実行 |
| TTSSH.dll (プラグイン) | SSHConnection.swift | SSH 接続 |

### SSH 実装の根本的な違い

| 項目 | Windows 版 (TTSSH) | Mac 版 |
|------|-------------------|--------|
| ライブラリ | libssh2 / OpenSSL (内蔵) | /usr/bin/ssh (OS 付属) |
| 方式 | ライブラリ API 呼び出し | forkpty + execvp |
| プロトコル制御 | 直接制御 (暗号/鍵交換/チャネル) | OpenSSH に委譲 |
| 認証 | 独自 UI + API | SSH_ASKPASS メカニズム |
| ポートフォワーディング | 詳細設定 UI | ssh -L/-R オプション |
| X11 転送 | サポート | ssh -X オプション |
| SCP | 内蔵実装 | /usr/bin/scp 呼び出し |

### 設定ストレージ

| 項目 | Windows 版 | Mac 版 |
|------|-----------|--------|
| 主要形式 | TERATERM.INI (Shift_JIS/UTF-8) | settings.json (Swift Codable) |
| 互換形式 | - | TERATERM.INI (UTF-8 LF) |
| 保存場所 | exe と同一フォルダ | ~/Library/Application Support/ |
| INI バージョン | 5.x | 5.6 |

---

## 機能面の差分

### Mac 版で未実装の機能

#### Windows 固有機能 (移植不要)

| 機能 | 理由 |
|------|------|
| DDE (Dynamic Data Exchange) | Windows IPC。macOS は XPC / AppleScript |
| IME 制御 (EnableIME/SetIMEOpenStatus) | macOS は OS レベルで入力メソッド管理 |
| Jump List (タスクバーピン止め) | Windows 7+ 固有 |
| タスクトレイ通知 | Windows 固有 |
| BalloonTip / ToolTip ウィンドウ | macOS は NSPopover / UserNotifications |
| レジストリベース設定 | macOS は UserDefaults / plist |
| COM ポート列挙 (DeviceIoControl) | macOS は IOKit |
| メニューバー非表示 | macOS メニューバーは常時表示 |
| ウィンドウ最小化→トレイ | macOS は Dock |

#### 未実装の端末機能

| 機能 | Windows 版 | Mac 版 | 状態 |
|------|-----------|--------|------|
| Sixel グラフィックス | DCS パススルー | DCS パススルーのみ | 描画未実装 |
| 倍幅/倍高行 (DECDWL/DECDHL) | 対応 | フラグのみ | 描画未実装 |
| プリンタ出力 | GDI 印刷 | スタブのみ | 未実装 |
| ハイパーリンク (OSC 8) | 検出+表示 | url フラグのみ | 視覚的区別なし |
| セッションリカバリ | 設定保存/復元 | なし | 未実装 |
| IME 合成表示 | インライン | 未対応 | 未実装 |
| 背景画像 | BG プラグイン | 設定のみ | 描画未実装 |

#### 未実装/部分実装のファイル転送

| プロトコル | Windows 版 | Mac 版 |
|-----------|-----------|--------|
| XMODEM | 完全実装 | 実装済み |
| YMODEM | 完全実装 | 実装済み |
| ZMODEM | 完全実装 (自動受信) | 実装済み |
| Kermit | 完全実装 | スタブ |
| B-Plus | 完全実装 | 未実装 |
| Quick-VAN | 完全実装 | 未実装 |

#### プラグインシステム

| 項目 | Windows 版 | Mac 版 |
|------|-----------|--------|
| プラグイン機構 | DLL ベース (TTXInit/TTXGetSetupHooks...) | なし |
| TTSSH | DLL プラグイン | 内蔵 SSHConnection |
| TTProxy | DLL プラグイン | 設定のみ (proxy 関連設定) |
| TTXKanjiMenu | DLL プラグイン | メニューに統合 |
| カスタムプラグイン | API 公開 | 未サポート |

---

### Mac 版固有の機能・改良点

#### ローカルシェル接続

Windows 版の Cygwin 接続に相当する macOS ネイティブ実装。

| 項目 | 詳細 |
|------|------|
| 方式 | forkpty + execvp |
| デフォルトシェル | $SHELL 環境変数 or /bin/zsh |
| ログインシェルモード | `-l` オプション |
| TERM 設定 | カスタマイズ可能 (デフォルト: xterm-256color) |
| HOME chdir | オプション |
| カスタム環境変数 | ENV1, ENV2 で KEY=VALUE 指定 |

#### セキュリティ強化

| 項目 | 詳細 |
|------|------|
| SecurePasswordBuffer | パスワードの確実なメモリゼロクリア |
| ASKPASS ファイル | 削除前にゼロデータ上書き |
| ホストキー検証 | `StrictHostKeyChecking=accept-new`（新規受入、変更拒否） |

#### 設定管理

| 項目 | 詳細 |
|------|------|
| JSON 設定 | Swift Codable による型安全な設定管理 |
| INI 互換読み込み | Windows INI ファイルを自動変換 |
| エンコーディング自動検出 | UTF-8/Shift_JIS/EUC-JP/ISO-8859-1 |
| バージョン自動アップグレード | INI バージョン < 5.6 → 再生成 |

#### マクロシステム

| 項目 | Windows 版 | Mac 版 |
|------|-----------|--------|
| 通信方式 | DDE | XPC (macOS IPC) |
| プロセス構成 | ttpmacro.exe (別プロセス) | TTLMacro (XPC サービス) |
| 共有コード | - | TTLMacroShared (Swift Package) |
| デバッグ機能 | 基本 | BreakpointStore + VariableWatchPanel |
| キーチェーン | なし | TTLKeychainManager (スタブ) |

#### UI/UX

| 項目 | 詳細 |
|------|------|
| レイアウト | Auto Layout (NSStackView ベース) |
| ローカライズ | Localizable.strings (英語/日本語) |
| ウィンドウサイズ保存 | NSWindow.setFrameAutosaveName |
| ダークモード | NSAppearance 対応 |
| Retina 対応 | HiDPI 自動スケーリング |

---

## 設定カバレッジ

### 統計

| 項目 | 数 |
|------|-----|
| Windows 版 INI キー総数 | 約 312 |
| Mac 版にマッピング済み | 約 278 (89%) |
| 未マッピング (Windows 固有) | 約 31 |
| 未マッピング (macOS 代替あり) | 約 3 |

### 未マッピング設定 (主要)

詳細は `doc/INISettingsUnsupportedReasons.md` を参照。

| 設定キー | カテゴリ | 理由 |
|---------|---------|------|
| EnablePopupMenu | Windows 固有 | macOS メニューバー |
| EnablePopupClose | Windows 固有 | macOS メニューバー |
| TEKGINMouseCode | 未実装 | TEK GIN モード未実装 |
| PrinterName | Windows 固有 | macOS プリンタ API 異なる |
| VTCompatTab | 互換性 | macOS では不要 |
| IME* 系 | Windows 固有 | macOS IM 管理 |

---

## VT エミュレーション互換性

### 完全互換の機能

- CSI シーケンス (カーソル移動、消去、スクロール、属性設定)
- ESC シーケンス (カーソル保存/復元、文字セット指定)
- SGR 属性 (太字/斜体/下線/反転/色/256色/TrueColor)
- DEC プライベートモード (DECCKM, DECAWM, DECTCEM, etc.)
- 代替画面バッファ (47/1047/1048/1049)
- マウストラッキング (X10/1000/1002/1003/SGR)
- ブラケットペースト (mode 2004)
- OSC タイトル/色変更/クリップボード
- NAWS (Telnet ウィンドウサイズ通知)

### 動作差異

| 項目 | Windows 版 | Mac 版 | 影響 |
|------|-----------|--------|------|
| バッファ構造 | 固定リングバッファ (modulo 演算) | 動的配列 + visibleStartLine | メモリ効率が異なる |
| フォント描画 | GDI/DirectWrite | Core Text | グリフ形状が微妙に異なる |
| カラーパレット | 256 エントリ COLORREF 配列 | ColorIndex 構造体 (RGB 直持ち) | 色の精度は同等 |
| 文字幅判定 | C 実装 (CP932 依存) | Swift Unicode range | Unicode 対応が改善 |
| キーマップ | KEYBOARD.CNF (Win32 仮想キー) | 同形式 (macOS キーコード変換) | 互換 |
