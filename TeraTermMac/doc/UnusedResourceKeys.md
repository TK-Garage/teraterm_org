# Tera Term Mac: 未使用リソースキー・未移植機能の一覧

## 1. 日本語リソース (`ja.lproj/Localizable.strings`) で定義済みだがSwiftコードで未使用のキー (36個)

### 端末設定ダイアログ (旧 — `dialog.termSetup.*` に置換済み)

| キー | 日本語テキスト |
|------|---------------|
| `dialog.terminalSetup.title` | 端末の設定 |
| `dialog.terminalSetup.message` | ターミナルエミュレーションの設定 |
| `dialog.terminalSetup.terminalId` | 端末ID: |
| `dialog.terminalSetup.size` | サイズ: |
| `dialog.terminalSetup.encoding` | 文字コード: |
| `dialog.terminalSetup.newLine` | 改行コード: |
| `dialog.terminalSetup.autoWrap` | 自動折り返し |
| `dialog.terminalSetup.ok` | OK |
| `dialog.terminalSetup.cancel` | キャンセル |

### ウインドウ設定ダイアログ (旧 — `dialog.winSetup.*` に置換済み)

| キー | 日本語テキスト |
|------|---------------|
| `dialog.windowSetup.title` | ウインドウの設定 |
| `dialog.windowSetup.cursorShape` | カーソル: |
| `dialog.windowSetup.cursorBlink` | 点滅 |
| `dialog.windowSetup.cursorColor` | カーソル: |
| `dialog.windowSetup.foreground` | 前景色: |
| `dialog.windowSetup.background` | 背景色: |
| `dialog.windowSetup.selection` | 選択: |
| `dialog.windowSetup.enableScroll` | 有効 |
| `dialog.windowSetup.beep` | ビープ: |
| `dialog.windowSetup.beepNone` | なし |
| `dialog.windowSetup.beepSystem` | システム音 |
| `dialog.windowSetup.beepVisual` | ビジュアルベル |
| `dialog.windowSetup.ok` | OK |
| `dialog.windowSetup.cancel` | キャンセル |

### シリアルポートダイアログ (旧 — `dialog.serialSetup.*` に置換済み)

| キー | 日本語テキスト |
|------|---------------|
| `dialog.serialPort.title` | シリアルポートの設定 |
| `dialog.serialPort.baudRate` | ボーレート: |
| `dialog.serialPort.flow` | フロー: |
| `dialog.serialPort.connect` | 接続 |
| `dialog.serialPort.cancel` | キャンセル |

### 接続エラーメッセージ (コードで直接英語文字列を使用している可能性あり)

| キー | 日本語テキスト | 状態 |
|------|---------------|------|
| `error.connection.failed` | %@:%d に接続できませんでした。 | 実装済 (ConnectionError.connectionFailed) |
| `error.connection.refused` | %@:%d への接続が拒否されました。ホストがこのポートで待ち受けていない可能性があります。 | 実装済 (ConnectionError.connectionRefused) |
| `error.connection.timeout` | %@:%d への接続がタイムアウトしました。ホストに到達できないか、ファイアウォールでブロックされている可能性があります。 | 実装済 (ConnectionError.connectionTimeout) |
| `error.connection.hostNotFound` | ホスト "%@" が見つかりません。ホスト名とネットワーク接続を確認してください。 | 実装済 (ConnectionError.hostNotFound) |
| `error.connection.sshNotSupported` | %@:%d へのSSH接続はまだサポートされていません。外部のSSHクライアントを使用するか、Telnetで接続してください。 | 実装済 (ConnectionError.sshNotSupported) |
| `error.connection.streamFailed` | %@:%d へのネットワークストリームの作成に失敗しました。 | 実装済 (ConnectionError.streamCreationFailed) |
| `error.connection.serialFailed` | シリアルポート %@ を開けませんでした。 | 実装済 (ConnectionError.serialPortOpenFailed) |
| `error.connection.title.ssh` | SSH未対応 | 実装済 (ConnectionError.sshNotSupported.alertTitle) |

---

## 2. オリジナルTera Term (Windows) にあってmacOS版に未移植の主な機能

### ファイルメニュー

| Windows版の機能 | 備考 |
|----------------|------|
| Cygwin接続 (`Alt+G`) | macOSでは不要 |
| ログを中断 | ログの一時停止 |
| ログにコメントを付加 | ログ中にコメント追記 |
| ログを表示 | 外部エディタでログ表示 |
| ログ記録中ダイアログを表示 | ログ進捗ダイアログ |
| Tera Termの全終了 | 全ウインドウの強制終了 |

### 転送メニュー

| Windows版の機能 | 備考 |
|----------------|------|
| YMODEM 送受信 | プロトコル未実装 |
| B-Plus 送受信 | プロトコル未実装 |
| Quick-VAN 送受信 | プロトコル未実装 |
| Kermit 取得 / Kermit 終了 | サブコマンド未実装 |

### 編集メニュー

| Windows版の機能 | 備考 |
|----------------|------|
| 貼り付け\<CR\> (`Alt+R`) | CR付き貼り付け |
| 選択を解除 | 選択範囲のキャンセル |
| 表示画面を選択 | 表示中の画面のみ選択 |

### コントロールメニュー

| Windows版の機能 | 備考 |
|----------------|------|
| リモートタイトルリセット | リモート設定タイトルのリセット |
| TEKウィンドウを開く / 閉じる | TEK 4014エミュレーション |
| マクロウィンドウの表示 | マクロ実行ウインドウの表示切替 |

### 設定メニュー

| Windows版の機能 | 備考 |
|----------------|------|
| 設定フォルダを開く | INI/CNF/known_hostsの場所表示 |
| キーマップ読み込み | `.cnf` ファイルの読み込み |

### ウインドウメニュー

| Windows版の機能 | 備考 |
|----------------|------|
| すべて最小化 | 全ウインドウの最小化 |
| 重ねて表示 | カスケード配置 |
| 上下に並べて表示 | タイル配置 (縦) |
| 左右に並べて表示 | タイル配置 (横) |
| すべて復元 | 全ウインドウの復元 |

### キーボード設定

| Windows版の機能 | 備考 |
|----------------|------|
| キーボード種類選択 | VT100/VT200等の選択 |
| アプリケーションキーパッドの無効化 | モード無効化オプション |
| アプリケーションカーソルの無効化 | モード無効化オプション |

### SSH設定 (詳細)

| Windows版の機能 | 備考 |
|----------------|------|
| ~~SSH圧縮レベル設定~~ | ~~圧縮レベル 0–9~~ → **実装済み** (`SSHSetupDialogController`) |
| ~~圧縮アルゴリズム順設定~~ | ~~アルゴリズム優先順位~~ → **実装済み** |
| ~~鍵交換アルゴリズム順設定 (KEX)~~ | ~~アルゴリズム優先順位~~ → **実装済み** |
| ~~ホストキーアルゴリズム順設定~~ | ~~アルゴリズム優先順位~~ → **実装済み** |
| ~~MACアルゴリズム順設定~~ | ~~アルゴリズム優先順位~~ → **実装済み** |
| ~~Known Hosts 読み書き/読み取り専用分離~~ | ~~ファイル分離設定~~ → **実装済み** |
| ~~ホスト公開鍵の自動更新 (有効/無効/確認)~~ | ~~ローテーション設定~~ → **実装済み** |

### セキュリティ警告ダイアログ

| Windows版の機能 | 備考 |
|----------------|------|
| ~~Unknown host 警告~~ | ~~初回接続時の確認~~ → **実装済み** (`UnknownHostDialog`) |
| ~~Different key 警告~~ | ~~ホスト鍵変更時の警告~~ → **実装済み** (`DifferentKeyDialog`) |
| ~~Different type key 警告~~ | ~~鍵種類不一致の警告~~ → **実装済み** (`DifferentTypeKeyDialog`) |
| ~~ホスト鍵ローテーション確認~~ | ~~鍵の自動更新確認~~ → **実装済み** (`HostKeyRotationDialog`) |
| ~~SSHFP (DNS鍵指紋) 表示~~ | ~~DNSSECによる検証結果表示~~ → **実装済み** (`SSHFPDialog`) |

### ブロードキャスト (拡張機能)

| Windows版の機能 | 備考 |
|----------------|------|
| ~~ヒストリ~~ | ~~コマンド履歴~~ → **実装済み** (`BroadcastDialogController` + NSComboBox) |
| ~~このプロセスのみに送信~~ | ~~送信範囲制限~~ → **実装済み** (`broadcastSendToThisOnly`) |
| ~~Enterキー~~ | ~~Enter送信オプション~~ → **実装済み** (`broadcastSendEnter`) |
| ~~リアルタイム~~ | ~~リアルタイム送信モード~~ → **実装済み** (`broadcastRealtime`) |
| ~~ウインドウ一覧の右クリックメニュー~~ | ~~前面表示/最小化/選択反転等~~ → **実装済み** (NSMenu context menu) |

### コピーと貼り付け (拡張機能)

| Windows版の機能 | 備考 |
|----------------|------|
| ~~右クリックでの貼り付け無効化~~ | ~~マウス操作設定~~ → **実装済み** (`disableRightClickPaste`) |
| ~~右クリックでの貼り付け確認~~ | ~~確認ダイアログ~~ → **実装済み** (`confirmRightClickPaste`) |
| ~~中クリックでの貼り付け無効化~~ | ~~マウス操作設定~~ → **実装済み** (`disableMiddleClickPaste`) |
| ~~左クリックでのみ選択開始~~ | ~~選択動作制限~~ → **実装済み** (`leftClickOnlySelection`) |
| ~~貼り付け時に末尾の改行を削除~~ | ~~クリップボード処理~~ → **実装済み** (`trimTrailingNewline`) |
| ~~危険なクリップボードの貼り付け確認~~ | ~~セキュリティ機能~~ → **実装済み** (`confirmDangerousClipboard`) |
| ~~キーワードファイル指定~~ | ~~警告キーワード定義~~ → **実装済み** (`dangerousKeywordFile`) |
| ~~マウスでウィンドウ選択時の文字選択有効化~~ | ~~ウインドウアクティブ化時の動作~~ → **実装済み** (`enableSelectionOnActivate`) |

### 制御シーケンス (拡張機能)

| Windows版の機能 | 備考 |
|----------------|------|
| ~~Controlキー押下中のマウスイベント無効化~~ | ~~修飾キー連携~~ → **実装済み** (`disableControlKeyMouseEvent`) |
| ~~タイトル変更の詳細設定 (上書き/前追加/後追加)~~ | ~~変更モード選択~~ → **実装済み** (`titleChangeMode`) |
| ~~ウインドウ情報報告シーケンス~~ | ~~ウインドウレポート~~ → **実装済み** (`windowInfoReportSequence`) |
| ~~クリップボードアクセスの詳細設定 (読込/書込/読込のみ/書込のみ)~~ | ~~アクセス制御~~ → **実装済み** (`clipboardAccessMode`) |
| ~~リモートからのクリップボードアクセス通知~~ | ~~通知機能~~ → **実装済み** (`notifyClipboardAccess`) |
| ~~リモートからのスクロールバッファ消去受け入れ~~ | ~~バッファ制御~~ → **実装済み** (`acceptScrollBufferClear`) |
| ~~印字開始シーケンス無効化~~ | ~~パススルー印刷制御~~ → **実装済み** (`disablePrintSequence`) |

### 表示設定 (拡張機能)

| Windows版の機能 | 備考 |
|----------------|------|
| ~~マウスカーソル設定~~ | ~~カーソル外観変更~~ → **実装済み** (`mouseCursorType` + VisualTab popup) |
| ~~フォントの品質 (Default/AntiAlias/ClearType)~~ | ~~レンダリング品質~~ → **実装済み** (`fontRenderingQuality`) |
| ウインドウの角を丸くしない | Windows 11対応 (macOS不要) |
| ~~太字属性色の有効化~~ | ~~属性別カラー~~ → **実装済み** (`enableBoldColor`) |
| ~~太字属性フォントの有効化~~ | ~~属性別フォント~~ → **実装済み** (`enableBoldFont`) |
| ~~点滅属性色の有効化~~ | ~~属性別カラー~~ → **実装済み** (`enableBlinkColor`) |
| ~~反転属性色の有効化~~ | ~~属性別カラー~~ → **実装済み** (`enableReverseColor`) |
| ~~下線属性色の有効化~~ | ~~属性別カラー~~ → **実装済み** (`enableUnderlineColor`) |
| ~~下線属性に下線を付加~~ | ~~属性別フォント装飾~~ → **実装済み** (`enableUnderlineDecoration`) |
| ~~URL属性色の有効化~~ | ~~属性別カラー~~ → **実装済み** (`enableURLColor`) |
| ~~URL文字列に下線を付加~~ | ~~属性別フォント装飾~~ → **実装済み** (`enableURLUnderline`) |
| ~~ANSIカラーの有効化~~ | ~~カラー有効/無効~~ → **実装済み** (`enableANSIColor`) |
| テーマ起動設定 (固定テーマ/ランダムテーマ) | テーマ自動選択 |

### ウインドウ設定 (拡張機能)

| Windows版の機能 | 備考 |
|----------------|------|
| ~~太字を有効~~ | ~~太字フォント描画~~ → **実装済み** (`enableBoldDisplay` + VisualTab) |
| ~~ウインドウ枠を隠す~~ | ~~フレームレス表示~~ → **実装済み** (`hideWindowFrame` + VisualTab) |
| ~~aixterm 16色モード~~ | ~~カラーモード~~ → **実装済み** (`enableAixtermColors` + VisualTab) |
| ~~xterm 256色モード~~ | ~~カラーモード~~ → **実装済み** (`enableXterm256Colors` + VisualTab) |
| ~~常に標準の背景色を使う~~ | ~~背景色固定~~ → **実装済み** (`useStandardBGColor` + VisualTab) |
| ~~属性別カラー設定 (標準/太字/点滅/反転/URL/下線)~~ | ~~6種の属性色~~ → **実装済み** (`attrColor*` + VisualTab NSColorWell) |

### フォント設定 (拡張機能)

| Windows版の機能 | 備考 |
|----------------|------|
| ~~描画幅に合わせてリサイズしたフォントを描画~~ | ~~フォントリサイズ~~ → **実装済み** (`resizeFontToFitWidth` + FontTab) |
| フォント設定/フォントフォルダを開く | フォルダ表示 |
| ダイアログフォント設定 | UI用フォント変更 |

### テーマエディタ

| Windows版の機能 | 備考 |
|----------------|------|
| テーマプレビュー/読み込み/保存 | テーマファイル管理 |
| ~~背景画像設定~~ | ~~背景画像指定~~ → **実装済み** (`bgImagePath` + ThemeTab NSOpenPanel) |
| ~~背景画像透過設定 (通常文字/反転文字/その他)~~ | ~~透過度設定~~ → **実装済み** (`bgImageAlpha*` + ThemeTab NSSlider) |
| ~~文字色テーマ編集~~ | ~~テーマカラー編集~~ → **実装済み** (ThemeTab NSColorWell 6色エディタ) |

### ログ設定 (拡張機能)

| Windows版の機能 | 備考 |
|----------------|------|
| ~~BOM出力~~ | ~~UTF-8 BOM付きログ~~ → **実装済み** (`logBOM` + LogTab + TerminalLogger BOM書き込み) |
| ~~タイムスタンプ種別 (ローカル/UTC/経過時間)~~ | ~~時刻形式選択~~ → **実装済み** (`logTimestampType` + `LogTimestampType` enum + LogTab) |

### 印刷

| Windows版の機能 | 備考 |
|----------------|------|
| 印刷中ダイアログ | VTウインドウ印刷進捗 |
| ~~TEKウインドウ印刷~~ | ~~TEKグラフィックス印刷~~ → **実装済み** (`TEKWindowController.printTEKWindow()` + macOS NSPrintOperation) |

---

## 3. 未移植のプラグイン (TTX拡張)

| プラグイン名 | 機能概要 |
|-------------|---------|
| **TTProxy** | プロキシ接続拡張 (SOCKS名前解決、Telnetプロキシ、SSL証明書検証等の詳細設定) |
| **TTMenu** | Tera Term支援ツール (リスト管理、自動ログイン、LockBox暗号化パスワード保存) |
| **TTXKanjiMenu** | 漢字コードメニュー拡張 (送受信エンコーディング切替、Ambiguous文字幅メニュー) |
| **TTXRecurringCommand** | 繰り返しコマンド (定期的なコマンド自動送信) |
| **TTXCheckUpdate** | アップデート確認 |
| **TTXttyrec** | TTY録画/再生 (ttyrec形式) |
| **TTXViewMode** | View mode (パスワード保護による表示専用モード) |
| **TTXAlwaysOnTop** | 常に最前面に表示 |

---

## 4. 備考

- **旧ダイアログキー**: `dialog.terminalSetup.*`、`dialog.windowSetup.*`、`dialog.serialPort.*` の多くは新しいViewController用キー (`dialog.termSetup.*`、`dialog.winSetup.*`、`dialog.serialSetup.*`) に置き換えられており、旧キーが残存している状態です。削除しても問題ありません。
- **接続エラーメッセージ**: `error.connection.failed` 等は定義済みですが、コード側で直接英語文字列を使用している可能性があります。ローカライゼーション対応の際に参照キーへの置き換えが必要です。
- **SCP進捗ダイアログ**: `dialog.scp.progress.*` のキーは `SCPProgressWindowController` で使用されています。
- **macOS不要の機能**: Cygwin接続、TTMenu等はWindows固有のため移植不要です。
