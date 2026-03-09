# Tera Term Mac — 設定値リファレンス

設定は `TerminalSettings` クラスで管理され、JSON 形式で永続化される。
保存先: `~/Library/Application Support/TeraTermMac/settings.json`

---

## 1. 端末エミュレーション設定

設定ダイアログ: **Setup → Terminal…**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 端末幅 | `terminalWidth` | Int | 80 | ターミナルの桁数 |
| 端末高さ | `terminalHeight` | Int | 24 | ターミナルの行数 |
| 端末サイズ=ウィンドウサイズ | `termIsWin` | Bool | true | 端末サイズをウィンドウサイズに連動 |
| 自動ウィンドウリサイズ | `autoWinResize` | Bool | false | 端末サイズ変更時にウィンドウを自動リサイズ |
| 端末ID | `terminalID` | TerminalID | .vt220 | エミュレートする端末の種類 |
| ローカルエコー | `localEcho` | Bool | false | 入力文字をローカルにエコー |
| アンサーバック | `answerback` | String | "" | ENQ 応答文字列 |

### TerminalID 一覧

| 値 | 端末 |
|---|------|
| .vt100 | VT100 |
| .vt100j | VT100J |
| .vt101 | VT101 |
| .vt102 | VT102 |
| .vt102j | VT102J |
| .vt220 | VT220（デフォルト） |
| .vt220j | VT220J |
| .vt282 | VT282 |
| .vt320 | VT320 |
| .vt382 | VT382 |
| .vt420 | VT420 |
| .vt520 | VT520 |
| .vt525 | VT525 |
| .dumb | Dumb Terminal |

---

## 2. 改行設定

設定ダイアログ: **Setup → Terminal…** (New-line グループ)

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 受信改行コード | `crReceive` | NewLineMode | .auto_ | 受信時の改行変換モード |
| 送信改行コード | `crSend` | NewLineMode | .cr | 送信時の改行変換モード |

### NewLineMode 一覧

| 値 | 意味 |
|---|------|
| .cr | CR のみ |
| .crlf | CR+LF |
| .lf | LF のみ |
| .auto_ | 自動判別（受信のみ） |

---

## 3. カーソル設定

設定ダイアログ: **Setup → Window…** (Cursor shape グループ)

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| カーソル形状 | `cursorShape` | CursorShape | .block | カーソルの表示形状 |
| カーソル点滅 | `cursorBlink` | Bool | true | カーソルを点滅させる |

### CursorShape 一覧

| 値 | 形状 |
|---|------|
| .block | ブロック（■） |
| .vertical | 縦線（│） |
| .horizontal | 横線（＿） |

---

## 4. ウィンドウ設定

設定ダイアログ: **Setup → Window…**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| タイトル | `title` | String | "Tera Term" | ウィンドウタイトル |
| タイトル書式 | `titleFormat` | Int | 0 | 0=タイトル, 1=ホスト名 等 |
| ウィンドウ透過度 | `windowAlpha` | Double | 1.0 | 不透明度 (0.2〜1.0) |
| スクロールバッファ有効 | `enableScrollBuffer` | Bool | true | スクロールバッファを使用 |
| スクロールバッファサイズ | `scrollBufferSize` | Int | 10000 | バッファの最大行数 |
| スクロールバッファ上限 | `scrollBufferMax` | Int | 500000 | 設定可能な最大値 |

---

## 5. 色設定

設定ダイアログ: **Setup → Window…** (Color グループ)

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| テキスト色 | `colorTheme.foreground` | TerminalColor | (255,255,255) 白 | 前景色 RGB |
| 背景色 | `colorTheme.background` | TerminalColor | (0,0,0) 黒 | 背景色 RGB |
| カーソル色 | `colorTheme.cursorColor` | TerminalColor | (0,255,0) 緑 | カーソル色 RGB |
| 選択テキスト色 | `colorTheme.selectionForeground` | TerminalColor | (0,0,0) 黒 | 選択時前景色 |
| 選択背景色 | `colorTheme.selectionBackground` | TerminalColor | (128,128,255) | 選択時背景色 |
| URL色 | `colorTheme.urlColor` | TerminalColor | (0,128,255) 青 | URL 表示色 |
| ANSI 16色 | `colorTheme.ansiColors` | [TerminalColor] | 標準16色 | ANSI カラーパレット |

### TerminalColor 構造体

| フィールド | 型 | 範囲 |
|----------|---|------|
| `r` | UInt8 | 0〜255 |
| `g` | UInt8 | 0〜255 |
| `b` | UInt8 | 0〜255 |

---

## 6. フォント設定

設定ダイアログ: **Setup → Font…** (NSFontPanel)

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| フォント名 | `fontName` | String | "Menlo" | 使用フォント |
| フォントサイズ | `fontSize` | Double | 14.0 | フォントサイズ (pt) |

---

## 7. キーボード設定

設定ダイアログ: **Setup → Keyboard…**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| Backspace キー | `bsKey` | Int | 8 | 8=BS (0x08), 127=DEL (0x7F) |
| Delete キー | `deleteKey` | Int | 127 | 127=DEL, 8=BS, ESC sequence |
| Meta キー | `metaKey` | Int | 0 | 0=オフ, 1=オン（Option を Meta として使用） |

---

## 8. 接続設定

設定ダイアログ: **File → New Connection…**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| ポートタイプ | `portType` | PortType | .tcpip | 接続方式 |
| サービスタイプ | `serviceType` | ServiceType | .telnet | TCP/IP サービス |
| デフォルトポート | `defaultPort` | Int | 23 | TCP ポート番号 |
| ホスト名 | `hostname` | String | "" | 接続先ホスト名 |
| Telnet | `telnet` | Bool | true | Telnet プロトコル使用 |
| プロトコルファミリ | `protocolFamily` | ProtocolFamily | .auto_ | IPv4/IPv6 選択 |
| ホスト履歴 | `hostHistory` | [String] | [] | 接続履歴 |
| SSH バージョン | `sshVersion` | SSHVersion | .ssh2 | SSH プロトコルバージョン |
| 端末タイプ文字列 | `termType` | String | "xterm" | TERM 環境変数 |

### PortType 一覧

| 値 | 接続方式 |
|---|---------|
| .tcpip | TCP/IP |
| .serial | シリアルポート |
| .file | ファイル |
| .namedPipe | 名前付きパイプ |

### ServiceType 一覧

| 値 | サービス | デフォルトポート |
|---|---------|--------------|
| .telnet | Telnet | 23 |
| .ssh | SSH | 22 |
| .other | その他 | 0 |

### ProtocolFamily 一覧

| 値 | IP バージョン |
|---|-------------|
| .auto_ | 自動選択 |
| .ipv4 | IPv4 のみ |
| .ipv6 | IPv6 のみ |

### SSHVersion 一覧

| 値 | バージョン |
|---|----------|
| .ssh1 | SSH1 |
| .ssh2 | SSH2（デフォルト） |

---

## 9. SSH 認証設定

設定ダイアログ: **SSH Authentication** (接続時に自動表示)

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 認証方式 | `sshAuthMethod` | SSHAuthMethod | .password | SSH 認証方式 |
| ユーザー名 | `sshUsername` | String | "" | SSH ログインユーザー名 |
| 秘密鍵ファイル | `sshKeyFile` | String | "" | 秘密鍵のファイルパス |
| パスワード記憶 | `sshRememberPassword` | Bool | false | パスワードをメモリに保持 |
| エージェント転送 | `sshForwardAgent` | Bool | false | SSH エージェント転送を有効化 |

### SSHAuthMethod 一覧

| 値 | 認証方式 | 説明 |
|---|---------|------|
| .password | パスワード認証 | プレーンパスワードでログイン |
| .publicKey | 公開鍵認証 | RSA/DSA/ECDSA/ED25519 鍵を使用 |
| .rhosts | rhosts 認証 | SSH1 のみ対応 |
| .challengeResponse | チャレンジレスポンス | keyboard-interactive 方式 |
| .pageant | Pageant | Pageant エージェントを使用 |

---

## 10. シリアルポート設定

設定ダイアログ: **Setup → Serial Port…**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| ポート | `serialPort` | String | "" | シリアルポートデバイス (/dev/cu.*) |
| ボーレート | `baudRate` | Int | 9600 | 通信速度 (bps) |
| データビット | `dataBits` | Int | 8 | データビット数 |
| パリティ | `parity` | Parity | .none | パリティチェック方式 |
| ストップビット | `stopBits` | Int | 1 | ストップビット数 |
| フロー制御 | `flowControl` | FlowControl | .none | フロー制御方式 |

### ボーレート選択肢

110, 300, 600, 1200, 2400, 4800, **9600**, 14400, 19200, 38400, 57600, 115200, 230400, 460800, 921600

### Parity 一覧

| 値 | パリティ |
|---|---------|
| .none | なし |
| .odd | 奇数 |
| .even | 偶数 |
| .mark | マーク |
| .space | スペース |

### FlowControl 一覧

| 値 | フロー制御 |
|---|----------|
| .none | なし |
| .xonXoff | XON/XOFF (ソフトウェア) |
| .hardware | ハードウェア (RTS/CTS) |

---

## 11. エンコーディング設定

設定ダイアログ: **Code メニュー**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 文字エンコーディング | `encoding` | CharacterEncoding | .utf8 | 受信時エンコーディング |
| 送信エンコーディング | `sendEncoding` | CharacterEncoding | .utf8 | 送信時エンコーディング |

### Unicode 設定

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 曖昧幅文字 | `unicodeAmbiguousWidth` | Int | 1 | 1=半角, 2=全角 |
| 絵文字幅 | `unicodeEmojiWidth` | Int | 2 | 絵文字の表示幅 |

---

## 12. ビープ設定

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| ビープ種別 | `beepType` | BeepType | .system | ビープ音の種類 |
| 接続時ビープ | `beepOnConnect` | Bool | false | 接続完了時にビープを鳴らす |

### BeepType 一覧

| 値 | ビープ種別 |
|---|----------|
| .none | なし（無音） |
| .system | システムビープ |
| .visual | ビジュアルベル（画面フラッシュ） |

---

## 13. ログ設定

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 自動開始 | `logAutoStart` | Bool | false | 接続時にログを自動開始 |
| デフォルトディレクトリ | `logDefaultDirectory` | String | "" | ログ保存先ディレクトリ |
| デフォルトファイル名 | `logDefaultName` | String | "teraterm.log" | ログファイル名 |
| タイムスタンプ | `logTimestamp` | Bool | false | タイムスタンプを付加 |
| プレーンテキスト | `logPlainText` | Bool | true | 制御コードを除去して記録 |

---

## 14. ファイル転送設定

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| XMODEM オプション | `xmodemOption` | Int | 1 | 1=チェックサム, 2=CRC, 3=1K |
| ZMODEM データ長 | `zmodemDataLen` | Int | 1024 | ZMODEM データブロック長 |
| ZMODEM ウィンドウサイズ | `zmodemWindowSize` | Int | 32767 | ZMODEM ウィンドウサイズ |

---

## 15. マウス設定

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| マウストラッキング | `mouseTracking` | Bool | true | マウスイベントをアプリに送信 |
| スクロール行数 | `mouseWheelScrollLines` | Int | 3 | ホイール1回あたりのスクロール行数 |

---

## 16. その他の設定

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 切断確認 | `confirmOnDisconnect` | Bool | true | 切断時に確認ダイアログを表示 |
| 設定ディレクトリ | `setupDirectory` | String | "" | 設定ファイルの保存先 |
| マクロディレクトリ | `macroDirectory` | String | "" | マクロファイルの検索パス |
