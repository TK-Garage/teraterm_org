# Tera Term Mac — 設定値リファレンス

設定は `TerminalSettings` クラスで管理され、JSON 形式で永続化される。
保存先: `~/Library/Application Support/TeraTermMac/settings.json`

ソースファイル: `Sources/TeraTermMac/Settings/TerminalSettings.swift`

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

| 値 | rawValue | 端末 |
|---|---------|------|
| .vt100 | 1 | VT100 |
| .vt100j | 2 | VT100J |
| .vt101 | 3 | VT101 |
| .vt102 | 4 | VT102 |
| .vt102j | 5 | VT102J |
| .vt220 | 6 | VT220（デフォルト） |
| .vt220j | 7 | VT220J |
| .vt282 | 8 | VT282 |
| .vt320 | 9 | VT320 |
| .vt382 | 10 | VT382 |
| .vt420 | 11 | VT420 |
| .vt520 | 12 | VT520 |
| .vt525 | 13 | VT525 |
| .dumb | 14 | Dumb Terminal |

---

## 2. 改行設定

設定ダイアログ: **Setup → Terminal…** (New-line グループ)

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 受信改行コード | `crReceive` | NewLineMode | .auto_ | 受信時の改行変換モード |
| 送信改行コード | `crSend` | NewLineMode | .cr | 送信時の改行変換モード |

### NewLineMode 一覧

| 値 | rawValue | 意味 |
|---|---------|------|
| .cr | 0 | CR のみ |
| .crlf | 1 | CR+LF |
| .lf | 2 | LF のみ |
| .auto_ | 3 | 自動判別（受信のみ） |

---

## 3. カーソル設定

設定ダイアログ: **Setup → Window…** (Cursor shape グループ)

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| カーソル形状 | `cursorShape` | CursorShape | .block | カーソルの表示形状 |
| カーソル点滅 | `cursorBlink` | Bool | true | カーソルを点滅させる |

### CursorShape 一覧

| 値 | rawValue | 形状 |
|---|---------|------|
| .block | 0 | ブロック（■） |
| .vertical | 1 | 縦線（│） |
| .horizontal | 2 | 横線（＿） |

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

### ANSI 16色デフォルト値

| インデックス | 色名 | R | G | B |
|------------|------|---|---|---|
| 0 | Black | 0 | 0 | 0 |
| 1 | Red | 187 | 0 | 0 |
| 2 | Green | 0 | 187 | 0 |
| 3 | Yellow | 187 | 187 | 0 |
| 4 | Blue | 0 | 0 | 187 |
| 5 | Magenta | 187 | 0 | 187 |
| 6 | Cyan | 0 | 187 | 187 |
| 7 | White | 187 | 187 | 187 |
| 8 | Bright Black | 85 | 85 | 85 |
| 9 | Bright Red | 255 | 85 | 85 |
| 10 | Bright Green | 85 | 255 | 85 |
| 11 | Bright Yellow | 255 | 255 | 85 |
| 12 | Bright Blue | 85 | 85 | 255 |
| 13 | Bright Magenta | 255 | 85 | 255 |
| 14 | Bright Cyan | 85 | 255 | 255 |
| 15 | Bright White | 255 | 255 | 255 |

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

| 値 | rawValue | 接続方式 |
|---|---------|---------|
| .tcpip | 0 | TCP/IP |
| .serial | 1 | シリアルポート |
| .file | 2 | ファイル |
| .namedPipe | 3 | 名前付きパイプ |

### ServiceType 一覧

| 値 | rawValue | サービス | デフォルトポート |
|---|---------|---------|--------------|
| .telnet | 0 | Telnet | 23 |
| .ssh | 1 | SSH | 22 |
| .other | 2 | その他 | 0 |

### ProtocolFamily 一覧

| 値 | rawValue | IP バージョン | displayName |
|---|---------|-------------|------------|
| .auto_ | 0 | 自動選択 (AF_UNSPEC) | AUTO |
| .ipv6 | 1 | IPv6 (AF_INET6) | IPv6 |
| .ipv4 | 2 | IPv4 (AF_INET) | IPv4 |

### SSHVersion 一覧

| 値 | rawValue | バージョン |
|---|---------|----------|
| .ssh1 | 1 | SSH1 |
| .ssh2 | 2 | SSH2（デフォルト） |

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

| 値 | rawValue | 認証方式 | 説明 |
|---|---------|---------|------|
| .password | 0 | パスワード認証 | プレーンパスワードでログイン |
| .publicKey | 1 | 公開鍵認証 | RSA/DSA/ECDSA/ED25519 鍵を使用 |
| .rhosts | 2 | rhosts 認証 | SSH1 のみ対応 |
| .challengeResponse | 3 | チャレンジレスポンス | keyboard-interactive 方式 |
| .pageant | 4 | Pageant | Pageant エージェントを使用 |

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

| 値 | rawValue | パリティ |
|---|---------|---------|
| .none | 0 | なし |
| .odd | 1 | 奇数 |
| .even | 2 | 偶数 |
| .mark | 3 | マーク |
| .space | 4 | スペース |

### FlowControl 一覧

| 値 | rawValue | フロー制御 |
|---|---------|----------|
| .none | 0 | なし |
| .xonXoff | 1 | XON/XOFF (ソフトウェア) |
| .hardware | 2 | ハードウェア (RTS/CTS) |

---

## 11. エンコーディング設定

設定ダイアログ: **Code メニュー** / **Additional Settings → Coding タブ**

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

| 値 | rawValue | ビープ種別 |
|---|---------|----------|
| .none | 0 | なし（無音） |
| .system | 1 | システムビープ |
| .visual | 2 | ビジュアルベル（画面フラッシュ） |

---

## 13. ログ設定

設定ダイアログ: **File → Log…** / **Additional Settings → Log タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 自動開始 | `logAutoStart` | Bool | false | 接続時にログを自動開始 |
| デフォルトディレクトリ | `logDefaultDirectory` | String | "" | ログ保存先ディレクトリ |
| デフォルトファイル名 | `logDefaultName` | String | "teraterm.log" | ログファイル名 |
| タイムスタンプ | `logTimestamp` | Bool | false | タイムスタンプを付加 |
| プレーンテキスト | `logPlainText` | Bool | true | 制御コードを除去して記録 |
| ログビューアパス | `logViewEditor` | String | "" | ログ閲覧用エディタ |
| エディタ引数 | `logEditorArguments` | String | "" | エディタ起動引数 |
| 追記モード | `logAppend` | Bool | false | ログファイルに追記 |
| バイナリモード | `logBinary` | Bool | false | バイナリログ記録 |
| ダイアログ非表示 | `logHideDialog` | Bool | false | ログダイアログを非表示 |
| バッファ含む | `logIncludeScreenBuffer` | Bool | false | 画面バッファを含む |
| ログローテーション | `logRotateEnabled` | Bool | false | ログローテーション有効 |
| ローテーションサイズ | `logRotateSize` | Int | 0 | ローテーションサイズ |
| ローテーションステップ | `logRotateStep` | Int | 0 | ローテーションステップ |

---

## 14. ファイル転送設定

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| XMODEM オプション | `xmodemOption` | Int | 1 | 1=チェックサム, 2=CRC, 3=1K |
| ZMODEM データ長 | `zmodemDataLen` | Int | 1024 | ZMODEM データブロック長 |
| ZMODEM ウィンドウサイズ | `zmodemWindowSize` | Int | 32767 | ZMODEM ウィンドウサイズ |
| 転送フォルダ | `fileTransferFolder` | String | "" | ファイル転送デフォルトフォルダ |

---

## 15. マウス設定

設定ダイアログ: **Additional Settings → Mouse タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| マウストラッキング | `mouseTracking` | Bool | true | マウスイベントをアプリに送信 |
| スクロール行数 | `mouseWheelScrollLines` | Int | 3 | ホイール1回あたりのスクロール行数 |

---

## 16. コピー＆ペースト設定

設定ダイアログ: **Additional Settings → Copy and Paste タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 連続行コピー | `continuedLineCopy` | Bool | true | 連続行をまとめてコピー |
| 改行付きペースト確認 | `confirmPasteNewLine` | Bool | true | 改行を含むペースト時確認 |
| ペースト遅延 | `pasteDelay` | Int | 5 | 行毎ペースト遅延 (msec) |
| 自動テキストコピー | `autoTextCopy` | Bool | true | 選択時自動コピー |
| 区切り文字 | `delimiterList` | String | " ;,()\"'" | ダブルクリック選択の区切り文字 |
| クリップボード貼付確認 | `clipboardConfirmPaste` | Bool | true | ペースト時確認ダイアログ |

---

## 17. 制御シーケンス設定

設定ダイアログ: **Additional Settings → Sequence タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| タイトル変更要求 | `titleChangeRequest` | Bool | false | リモートからのタイトル変更許可 |
| タイトルレポート要求 | `titleReportRequest` | Bool | false | タイトルレポート許可 |
| ウィンドウ制御シーケンス | `windowControlSequence` | Bool | true | ウィンドウ制御シーケンス有効 |
| カーソル制御シーケンス | `cursorControlSequence` | Bool | true | カーソル制御シーケンス有効 |
| リモートクリップボード | `clipboardAccessFromRemote` | Bool | false | リモートからのクリップボードアクセス |

---

## 18. ビジュアル設定

設定ダイアログ: **Additional Settings → Visual タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| アクティブ時不透明度 | `windowOpacityActive` | Int | 100 | アクティブウィンドウ不透明度 (%) |
| 非アクティブ時不透明度 | `windowOpacityInactive` | Int | 100 | 非アクティブウィンドウ不透明度 (%) |
| マウスカーソル形状 | `mouseCursorType` | Int | 0 | マウスカーソルの形状 |
| ちらつき抑制移動 | `flickerlessMoveEnabled` | Bool | false | ちらつき抑制移動有効 |
| 角丸め | `cornerRounding` | Int | 0 | ウィンドウ角丸め |
| 太字色 | `attrBold` | Bool | true | 太字属性色有効 |
| 点滅色 | `attrBlink` | Bool | true | 点滅属性色有効 |
| 反転色 | `attrReverse` | Bool | true | 反転属性色有効 |
| 下線色 | `attrUnderline` | Bool | true | 下線属性色有効 |
| 取消線色 | `attrStrikethrough` | Bool | false | 取消線属性色有効 |

---

## 19. フォント追加設定

設定ダイアログ: **Additional Settings → Font タブ** / **TEK Font タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| VTプロポーショナル | `vtFontProportional` | Bool | false | プロポーショナルフォント表示 |
| VT非表示フォント | `vtFontHidden` | Bool | false | 非表示フォント表示 |
| TEKフォント名 | `tekFontName` | String | "Menlo" | TEKフォント |
| TEKフォントサイズ | `tekFontSize` | Double | 14.0 | TEKフォントサイズ (pt) |
| TEKプロポーショナル | `tekFontProportional` | Bool | false | TEKプロポーショナルフォント |
| TEK非表示フォント | `tekFontHidden` | Bool | false | TEK非表示フォント |
| 描画API | `drawingAPI` | Int | 0 | 描画API選択 |
| コードページ | `codePage` | Int | 65001 | コードページ (65001=UTF-8) |
| 文字間隔 水平 | `charSpaceH` | Int | 0 | 水平方向の文字間隔 |
| 文字間隔 垂直 | `charSpaceV` | Int | 0 | 垂直方向の文字間隔 |
| フォント品質 | `fontQuality` | Int | 0 | フォント描画品質 |

---

## 20. 一般設定

設定ダイアログ: **Additional Settings → General タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 切断確認 | `confirmOnDisconnect` | Bool | true | 切断時に確認ダイアログを表示 |
| 出力時自動スクロール | `autoScrollOnOutput` | Bool | true | 出力時に自動スクロール |
| リサイズ時クリア | `clearOnResize` | Bool | false | リサイズ時に画面クリア |
| IMEカーソル変更 | `cursorChangeIME` | Bool | true | IMEでカーソル変更 |
| 通知音 | `notifySound` | Bool | true | 通知音有効 |
| タイトル (TCP) | `titleFormatTCP` | Bool | true | TCP接続時タイトルにホスト表示 |
| タイトル (Serial) | `titleFormatSerial` | Bool | true | シリアル接続時タイトルにポート表示 |
| タイトル (Session) | `titleFormatSession` | Bool | false | セッション情報をタイトルに表示 |

---

## 21. TCP/IP 追加設定

設定ダイアログ: **Setup → TCP/IP…**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| TCP Keep Alive | `tcpKeepAlive` | Bool | true | TCP キープアライブ有効 |
| Keep Alive 間隔 | `tcpKeepAliveInterval` | Int | 300 | キープアライブ間隔 (秒) |
| ウィンドウ自動クローズ | `autoWindowClose` | Bool | true | 切断時にウィンドウを自動閉じ |

---

## 22. テーマ設定

設定ダイアログ: **Additional Settings → Theme タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| テーマ有効 | `themeEnabled` | Bool | false | テーマ機能有効化 |
| テーマファイル | `themeFile` | String | "" | テーマファイルパス |
| 起動時テーマ | `startupTheme` | String | "" | 起動時に適用するテーマ |
| 高速サイズ変更 | `fastSizeMove` | Bool | false | 高速サイズ変更有効 |
| Susieパス | `susiePath` | String | "" | Susie プラグインパス |

---

## 23. プラグイン設定

設定ダイアログ: **Additional Settings → Plugin タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| プラグインディレクトリ | `pluginDirectories` | [String] | [] | プラグイン検索ディレクトリ一覧 |

---

## 24. UI 設定

設定ダイアログ: **Additional Settings → UI タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| UI言語 | `language` | String | "English" | UI表示言語 |
| ダイアログフォント名 | `dialogFontName` | String | "" | ダイアログフォント |
| ダイアログフォントサイズ | `dialogFontSize` | Double | 0 | ダイアログフォントサイズ |
| プロポーショナル | `dialogFontProportional` | Bool | false | プロポーショナルフォント表示 |
| 非表示フォント | `dialogFontHidden` | Bool | false | 非表示フォント表示 |

---

## 25. デバッグ設定

設定ダイアログ: **Additional Settings → Debug タブ**

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 文字情報ポップアップ | `debugCharInfoPopup` | Bool | false | 文字情報ポップアップ有効 |

---

## 26. パス設定

| 設定項目 | プロパティ | 型 | デフォルト値 | 説明 |
|---------|----------|---|------------|------|
| 設定ディレクトリ | `setupDirectory` | String | (AppSupport) | 設定ファイルの保存先 |
| マクロディレクトリ | `macroDirectory` | String | (AppSupport) | マクロファイルの検索パス |

デフォルト値は `~/Library/Application Support/TeraTermMac/` に設定される。

---

## 統計情報

| カテゴリ | プロパティ数 |
|---------|-----------|
| 端末エミュレーション | 7 |
| 改行 | 2 |
| カーソル | 2 |
| ウィンドウ | 6 |
| 色 | 7 (+ ANSI 16色) |
| フォント | 2 |
| キーボード | 3 |
| 接続 | 9 |
| SSH 認証 | 5 |
| シリアルポート | 6 |
| エンコーディング | 4 |
| ビープ | 2 |
| ログ | 13 |
| ファイル転送 | 4 |
| マウス | 2 |
| コピー＆ペースト | 6 |
| 制御シーケンス | 5 |
| ビジュアル | 10 |
| フォント追加 | 11 |
| 一般 | 8 |
| TCP/IP 追加 | 3 |
| テーマ | 5 |
| プラグイン | 1 |
| UI | 5 |
| デバッグ | 1 |
| パス | 2 |
| **合計** | **約130** |
