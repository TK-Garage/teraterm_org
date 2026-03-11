# TERATERM.INI 未対応設定 — 詳細理由

INISettingsMapping.md で `x`（未対応）となっている設定項目について、
未対応の理由を分類・詳述する。

---

## 理由分類

| 分類 | 略称 | 説明 |
|------|------|------|
| A | Windows 専用 | Windows API・UI 機構に依存しており、macOS に該当概念がない |
| B | TEK 非対応 | Tektronix (TEK) グラフィック端末エミュレーションは Mac 版の対象外 |
| C | レガシープロトコル | Kermit / B-Plus / Quick-VAN 等、現在ほぼ使われないプロトコル |
| D | JIS/カタカナ固有 | JIS エスケープシーケンスや 7bit カタカナ等、UTF-8 主体の Mac 版では不要 |
| E | macOS 標準で代替 | macOS の標準機能（IME、ブラウザ連携等）が同等機能を提供 |
| F | 優先度低・将来検討 | 技術的には実装可能だが、需要が低く未実装 |
| G | Telnet 固有 | Telnet プロトコル固有の詳細設定で、SSH 中心の Mac 版では優先度低 |

---

## セクション: [Tera Term]

### 端末エミュレーション

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| TerminalUID | F | 端末ユニークID。Tera Term 独自仕様で、SSH/Telnet プロトコル上で使用されない。実用上の需要が少ないため未実装。 |

### 文字コード

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| KatakanaReceive | D | 7bit/8bit カタカナ切替。JIS X 0201 片仮名の 7bit (ESC シーケンス) / 8bit (0xA1-0xDF) 選択。macOS は UTF-8 が標準であり、レガシー JIS カタカナの 7bit/8bit 区別は不要。 |
| KatakanaSend | D | 上記 KatakanaReceive の送信側。同じ理由で不要。 |
| KanjiIn | D | JIS エスケープシーケンスの漢字開始指示子 (`ESC $ @` / `ESC $ B`)。JIS (ISO-2022-JP) エンコーディング固有の設定で、UTF-8 主体の Mac 版では不要。 |
| KanjiOut | D | JIS エスケープシーケンスの漢字終了指示子 (`ESC ( J` / `ESC ( B` / `ESC ( H`)。同上。 |

### ウィンドウ表示

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| HideTitle | A | タイトルバー非表示。macOS ではウィンドウのタイトルバーは OS 標準の操作体系（閉じる/最小化/最大化ボタン）と密接に関連しており、非表示にするとユーザビリティが著しく低下する。`NSWindow.styleMask` で技術的には可能だが、macOS の HIG に反するため非対応。 |
| PopupMenu | A | ポップアップメニューモード。Windows 版ではタイトルバーを非表示にした際にメニューを右クリックで表示する機能。macOS ではメニューバーが画面上部に常駐するため不要。 |
| VTPos | A | VT ウィンドウの絶対座標位置指定。macOS ではウィンドウ位置は `NSWindow.setFrameAutosaveName` による自動保存が標準。ピクセル座標の直接指定は Retina 対応等の問題もあり非対応。 |
| TEKPos | B | TEK ウィンドウの位置指定。TEK エミュレーション自体が非対応。 |

### 色設定

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| TEKColor | B | TEK ウィンドウの文字色/背景色。TEK エミュレーション自体が非対応。 |
| UseTextColor | F | テキスト色を ANSI カラーパレットの前景色として使用する設定。ANSI カラー対応が充実しているため、この互換設定の需要は低い。 |
| TEKColorEmulation | B | TEK カラーエミュレーション。TEK 自体が非対応。 |

### フォント

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| PrnFont | A | プリンタ用フォント指定。macOS の印刷機構は `NSPrintOperation` を使用し、画面フォントがそのまま使われる。プリンタ専用フォントの概念がない。 |

### キーボード

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| Meta8Bit | F | Meta キーで 8bit 目をセットするモード ("raw"/"text")。macOS では Option キーが Meta に対応するが、8bit エンコーディングとの組み合わせは UTF-8 環境で実用性が低い。ESC プレフィックス方式 (`MetaKey`) で十分。 |
| StrictKeyMapping | F | KEYBOARD.CNF の厳密なキーマッピング適用。Mac 版は独自のキーマッピング方式を採用しており、Windows 版の KEYBOARD.CNF との互換性は不要。 |
| RussKeyb | F | ロシア語キーボードレイアウト切替。macOS ではシステムの入力ソースでロシア語キーボードを選択可能であり、アプリ独自の対応は不要。 |
| IME | E | IME の有効/無効。macOS では入力メソッド（日本語入力等）はシステムレベルで管理され、アプリが個別に制御する必要がない。 |
| IMEInline | E | IME インライン入力。macOS の `NSTextInputClient` プロトコルにより、インライン入力は標準動作として提供される。 |

### ビープ

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| BeepVBellWait | F | ビジュアルベルの表示待機時間 (ms)。Mac 版ではビジュアルベルの表示時間を固定値としており、細かいミリ秒単位の調整は不要と判断。 |

### 接続 (TCP/IP)

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| TelPort | G | Telnet 専用ポート番号。`TCPPort` で TCP ポートが設定可能であり、Telnet 用に別途ポートを持つ必要がない。 |
| TelAutoDetect | G | Telnet プロトコルの自動検出。SSH 接続が主流の Mac 版では優先度が低い。 |
| TelBin | G | Telnet バイナリモードフラグ。Telnet 固有のネゴシエーションオプションで、SSH 中心の利用では不要。 |
| TelEcho | G | Telnet エコーオプション。同上。 |
| TCPLocalEcho | G | 非 Telnet 接続時のローカルエコー。`LocalEcho` 設定で統一的にカバー。 |
| TCPCRSend | G | 非 Telnet 接続時の改行送信設定。`CRSend` で統一的にカバー。 |
| DisableTCPEchoCR | G | TCPLocalEcho / TCPCRSend の無効化フラグ。上記2項目が非対応のため不要。 |
| HostDialogOnStartup | E | 起動時に接続ダイアログを自動表示。Mac 版は起動時に新規ウィンドウを開く macOS 標準の動作に従い、メニューから接続を開始する設計。 |

### シリアルポート

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| MaxComPort | A | 最大 COM ポート番号 (Windows の COM1〜COM256)。macOS ではシリアルポートは `/dev/tty.*` / `/dev/cu.*` のデバイスファイルとして列挙されるため、番号上限の概念がない。 |
| WaitCom | F | COM ポートの接続待機。macOS ではデバイスファイルの出現を `IOKit` や `FSEvents` で監視する方式が適切だが、未実装。 |
| AutoComPortReconnectDelayNormal | F | 自動再接続の通常時遅延。`AutoComPortReconnect` は対応済みだが、遅延の細かい制御は固定値で十分と判断。 |
| AutoComPortReconnectDelayIllegal | F | 異常切断時の再接続遅延。同上。 |
| AutoComPortReconnectRetryInterval | F | 再接続リトライ間隔。同上。 |
| AutoComPortReconnectRetryCount | F | 再接続リトライ回数。同上。 |
| FlowCtrlRTS | A | RTS ラインの詳細制御 (DTR/RTS の個別設定)。macOS の `IOKit` シリアル API では `termios` 構造体で制御するが、Windows の `DCB` 構造体ほど細かい RTS/DTR 個別制御はサポートされない。 |
| FlowCtrlDTR | A | DTR ラインの詳細制御。同上。 |

### ログ

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| LogRotateSizeType | F | ログローテーションのサイズ単位種別 (Byte/KB/MB)。Mac 版ではバイト単位に統一しており、単位種別の選択は不要と判断。 |
| DeferredLogWriteMode | F | 遅延ログ書込み（バッファリング）。macOS の `FileHandle` / `OutputStream` はカーネルレベルでバッファリングされるため、アプリ層での追加バッファリングの効果が薄い。 |
| LogLockExclusive | A | ログファイルの排他ロック。Windows の `LOCKFILE_EXCLUSIVE_LOCK` に相当する機能。macOS では `flock()` / `fcntl()` で可能だが、UNIX 環境では advisory lock が一般的で、Windows のような mandatory lock の需要が低い。 |

### ファイル転送

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| TransBin | F | バイナリ転送フラグ。ファイル転送全般の基本フラグだが、各プロトコル (ZMODEM 等) 側で個別に制御しているため、グローバルフラグは不要。 |
| XmodemBin | F | XMODEM バイナリモード。XMODEM 転送の基本機能は対応済みだが、テキスト/バイナリ切替は常にバイナリとして扱うため不要。 |
| XModemRcvCommand | F | XMODEM 受信コマンド文字列。リモートホストに送信する受信開始コマンド。Mac 版では手動で受信コマンドを実行する設計。 |
| YModemRcvCommand | F | YMODEM 受信コマンド文字列。同上。 |
| ZModemRcvCommand | F | ZMODEM 受信コマンド文字列。同上。 |
| ZmodemEscCtl | F | ZMODEM の制御文字エスケープ。ZMODEM の基本機能は対応済みだが、エスケープ制御の詳細設定は需要が低い。 |
| FileSendFilter | F | ファイル送信時のフィルタ（ワイルドカード等）。macOS の `NSOpenPanel` が標準のファイルフィルタ機能を提供するため、INI での指定は不要。 |
| ScpSendDir | F | SCP 送信先ディレクトリのデフォルト。SCP ダイアログで直接指定する設計のため、INI でのデフォルト保存は未実装。 |
| FTHideDialog | F | ファイル転送ダイアログの非表示。転送の進捗表示は常に表示する設計。 |

### XMODEM/YMODEM/ZMODEM タイムアウト

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| XmodemTimeouts | F | XMODEM の各フェーズのタイムアウト値。細かいタイムアウト調整は固定値で十分と判断。変更が必要なケースが報告されれば対応予定。 |
| YmodemTimeouts | F | YMODEM のタイムアウト値。同上。 |
| ZmodemTimeouts | F | ZMODEM のタイムアウト値。同上。 |

### 制御シーケンス

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| EnableStatusLine | F | DEC 端末のステータスライン (Indicator Line)。VT220 以降のステータスライン機能で、実装コストに対して需要が低いため未対応。 |
| UseInvalidDECRQSSResponse | F | 無効な DECRPSS レスポンスを返すテスト用設定。デバッグ/テスト用途のため、一般利用では不要。 |
| TabStopModifySequence | D | タブストップ変更シーケンス (HTS/TBC 等) の有効/無効。ISO 2022 のシフト機能と関連する設定で、UTF-8 環境では影響が少ない。 |
| ISO2022ShiftFunction | D | ISO 2022 のシフト機能 (SI/SO, SS2/SS3, LS2/LS3 等) の有効/無効。ISO 2022 エスケープシーケンスは JIS 等のレガシーエンコーディング用であり、UTF-8 主体の Mac 版では不要。 |

### コピー＆ペースト

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| PasteDialogSize | A | ペースト確認ダイアログのサイズ指定 (ピクセル)。macOS では `NSAlert` / `NSPanel` のサイズは Auto Layout により自動調整されるため、固定サイズ指定は不要。 |
| DelimDBCS | D | DBCS (Double-Byte Character Set) 文字をダブルクリック区切り文字とみなす設定。macOS は Unicode ベースで、DBCS の概念ではなく Unicode のカテゴリ（漢字・ひらがな等）で単語境界を判定する。 |

### URL

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| ClickableUrlBrowser | E | URL クリック時に開くブラウザのパス指定。macOS では `NSWorkspace.shared.open(url)` により、システムのデフォルトブラウザが自動的に使用される。アプリ個別のブラウザ指定は macOS の設計思想に合わない。 |
| ClickableUrlBrowserArg | E | ブラウザ起動時の引数。上記 ClickableUrlBrowser が非対応のため不要。 |

### Cygwin (Windows 専用)

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| CygwinDirectory | A | Cygwin インストールパス。Cygwin は Windows 上で UNIX 環境を提供するツールであり、macOS はネイティブに UNIX 環境を持つため完全に不要。 |

### メニュー制御 (Windows 専用)

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| EnablePopupMenu | A | ポップアップメニューの有効/無効。Windows のシステムメニュー・ポップアップメニューに対応する設定。macOS ではメニューバーが画面上部に常駐し、右クリックコンテキストメニューは OS 標準動作のため個別制御不要。 |
| EnableShowMenu | A | メニュー表示の有効/無効。macOS ではメニューバーは常に表示される OS 標準仕様。 |
| WindowMenu | A | ウィンドウメニューの表示/非表示。macOS では「ウィンドウ」メニューは AppKit 標準で自動生成される。 |
| DisableAcceleratorSendBreak | A | Break 送信のキーボードアクセラレータ無効化。Windows のアクセラレータテーブルに対応する設定。macOS ではメニューのキーボードショートカットとして実装され、メニュー項目の有効/無効で制御。 |
| DisableAcceleratorDuplicateSession | A | セッション複製アクセラレータ無効化。同上。 |
| AcceleratorNewConnection | A | 新規接続アクセラレータ有効化。同上。 |
| AcceleratorCygwinConnection | A | Cygwin 接続アクセラレータ。Cygwin 自体が非対応。 |
| DisableMenuSendBreak | A | Break メニュー項目の無効化。macOS ではメニュー項目の `isEnabled` で個別制御可能だが、INI からの制御は需要が低い。 |
| DisableMenuDuplicateSession | A | セッション複製メニュー無効化。同上。 |
| DisableMenuNewConnection | A | 新規接続メニュー無効化。同上。 |

### プリンタ (Windows 専用)

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| PassThruDelay | A | パススルー印刷遅延。Windows のプリンタスプーラへの直接書き込み機能。macOS では `NSPrintOperation` / CUPS を介した印刷が標準で、パススルー印刷の概念がない。 |
| PassThruPort | A | パススルー印刷ポート (LPT1 等)。Windows のパラレルポート/USB プリンタポートに直接出力する設定。macOS では CUPS がプリンタ管理を担当。 |
| PrnMargin | A | 印刷マージン。Windows の `DEVMODE` / `SetWindowExtEx` による印刷マージン設定。macOS では印刷ダイアログの「ページ設定」で標準的に設定可能。 |
| PrnConvFF | A | フォームフィード (FF) を改行 (NL) に変換。印刷制御コードの変換で、現代の印刷環境では不要。 |
| VTPPI | A | VT 端末印刷時の PPI (Pixels Per Inch) 設定。macOS では Retina 対応を含め、印刷解像度は OS が自動管理。 |
| TEKPPI | B | TEK 印刷 PPI。TEK 自体が非対応。 |

### Kermit

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| KmtLog | C | Kermit プロトコルのログ。Kermit は 1980 年代に開発されたファイル転送プロトコルで、現在は SCP/SFTP に置き換えられている。Mac 版では Kermit プロトコル自体を非対応とした。 |
| KmtLongPacket | C | Kermit 長パケットモード。同上。 |
| KmtFileAttr | C | Kermit ファイル属性転送。同上。 |

### B-Plus

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| BPAuto | C | B-Plus プロトコル自動起動。B-Plus は CompuServe 用のファイル転送プロトコルで、CompuServe サービス終了 (2009年) 以降は実質的に使用されていない。 |
| BPEscCtl | C | B-Plus ESC 制御フラグ。同上。 |
| BPLog | C | B-Plus ログ。同上。 |

### Quick-VAN

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| QVLog | C | Quick-VAN ログ。Quick-VAN は日本の VAN (Value Added Network) 時代のファイル転送プロトコルで、現在はほぼ使用されていない。 |
| QVWinSize | C | Quick-VAN ウィンドウサイズ。同上。 |

### プロトコル制御ログ

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| TelLog | G | Telnet プロトコルのデバッグログ。Telnet の詳細デバッグは需要が低い。将来 Telnet 対応を強化する場合に検討。 |
| XmodemLog | F | XMODEM のデバッグログ。ファイル転送プロトコルのデバッグログは一般利用で不要。 |
| YmodemLog | F | YMODEM のデバッグログ。同上。 |
| ZmodemLog | F | ZMODEM のデバッグログ。同上。 |

### その他特殊オプション

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| AutoWinSwitch | B | VT/TEK ウィンドウの自動切り替え。TEK 自体が非対応。 |
| CtrlInKanji | D | 漢字 (マルチバイト文字) シーケンス中の制御コード処理。Shift_JIS / EUC-JP のマルチバイトシーケンス内に制御コードが含まれる場合の処理。UTF-8 ではマルチバイトシーケンスに ASCII 制御コードが含まれない設計のため不要。 |
| FixedJIS | D | 固定 JIS モード。JIS (ISO-2022-JP) の状態遷移を固定するモード。UTF-8 環境では不要。 |
| AutoInvoke | C | 自動インボーク。B-Plus / Quick-VAN の自動起動トリガー。これらのプロトコルが非対応のため不要。 |
| VTIcon | A | VT ウィンドウのアイコン指定。Windows のウィンドウアイコン (タスクバー/タイトルバー) に対応。macOS では Dock アイコンはアプリ単位で固定であり、ウィンドウ個別のアイコン設定は OS の設計にない。 |
| TEKIcon | B | TEK ウィンドウのアイコン。TEK 自体が非対応。 |
| TEKGINMouseCode | B | TEK GIN (Graphic Input) モードのマウスキーコード。TEK 自体が非対応。 |
| SendBreakTime | F | Break シグナルの送信時間 (ms)。Break 送信機能は実装済みだが、送信時間の調整は固定値 (500ms) で十分と判断。 |
| MaximizedBugTweak | A | Windows の最大化時のバグ回避ワークアラウンド。Windows 固有の描画バグに対応する設定で、macOS では該当する問題がない。 |
| DuplicateSession | A | セッション複製。Windows の `CreateProcess` でプロセスを複製する機能。Mac 版は新規ウィンドウ + 接続情報コピーで対応可能だが、仕組みが異なるため INI 設定としては非対応。 |
| Wait4allMacroCommand | F | マクロの全コマンド完了待ち。TTL マクロの実行制御で、マクロ機能が限定的な Mac 版では不要。 |
| FileSendHighSpeedMode | F | 高速ファイル送信モード。Windows 版ではバッファサイズやスレッド制御で高速化するが、Mac 版は標準の送信処理で十分な速度が出ている。 |
| StartupMacro | F | 起動時に自動実行するマクロファイル指定。TTL マクロ機能が限定的なため未対応。将来マクロ機能を拡充する場合に検討。 |
| AutoScrollOnlyInBottomLine | F | カーソルが最終行にある場合のみ自動スクロールする設定。実装コストに対して需要が少ないため未対応。 |
| JumpList | A | Windows 7+ のジャンプリスト (タスクバー右クリックメニュー) への接続先表示。macOS の Dock メニューに相当するが、Dock メニューへの動的項目追加は `NSDockTilePlugIn` で可能ながら未実装。 |
| LockTUID | F | 端末 UID のロック (セッション間で変更しない)。`TerminalUID` 自体が非対応のため不要。 |
| IniAutoBackup | F | INI ファイル保存時の自動バックアップ。macOS では Time Machine やバージョン管理が OS レベルで提供されるため、アプリ独自のバックアップは優先度が低い。 |

### Unicode 設定

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| UnicodeToDecSpMapping | F | Unicode から DEC Special Graphics 文字 (罫線文字等) へのマッピング方法。DEC 特殊文字をフォントのグリフで描画するか Unicode 文字で描画するかの選択。Mac 版はフォントの Unicode グリフを直接使用する設計。 |
| DecSpMappingDir | F | DEC 特殊マッピングの方向 (Unicode→DEC or DEC→Unicode)。上記 UnicodeToDecSpMapping が非対応のため不要。 |

### Sendfile 設定

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| SendfileDelayType | F | ファイル送信時の遅延種別 (なし/文字毎/行毎/送信サイズ毎)。Mac 版のファイル送信は `PasteDelayPerLine` / `DelayPerChar` 等で統一的にカバーしており、Sendfile 独自の遅延設定は未実装。 |
| SendfileDelayTick | F | 送信遅延の Tick 値。上記 SendfileDelayType が非対応のため不要。 |
| SendfileSize | F | 1回の送信サイズ (バイト)。固定値で運用。 |
| SendfileSequential | F | 順次送信モード (複数ファイルを順番に送信)。Mac 版のファイル送信は1ファイルずつの操作を想定。 |
| SendfileSkipOptionDialog | F | ファイル送信オプションダイアログのスキップ。ダイアログの設計が Windows 版と異なるため不要。 |

### Receivefile 設定

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| FileReceiveFilter | F | 受信ファイルのフィルタ。macOS の `NSSavePanel` で保存先を指定する設計のため、INI でのフィルタ指定は不要。 |
| ReceivefileSkipOptionDialog | F | 受信オプションダイアログのスキップ。Sendfile と同様。 |
| ReceivefileAutoStopWaitTime | F | 自動停止待機時間。受信完了検出の待機秒数で、Mac 版は固定値で運用。 |

### [BG] テーマ

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| BGNoCopyBits | A | Windows GDI の `BitBlt` / `ScrollWindow` の CopyBits 無効化。ウィンドウのスクロール・リサイズ時に背景画像の残像を防ぐ Windows 固有の描画最適化設定。macOS の Core Animation / Metal レンダリングでは該当する問題がない。 |

### [Experimental]

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| TreePropertySheet | A | 設定ダイアログをツリー形式のプロパティシートで表示する Windows UI の実験的機能。macOS では `NSTabView` / `NSToolbar` ベースの設定画面が標準であり、ツリー形式のプロパティシートは macOS の HIG に合わない。 |

---

## 未対応理由の統計

| 分類 | 略称 | 件数 |
|------|------|------|
| A | Windows 専用 | 35 |
| B | TEK 非対応 | 8 |
| C | レガシープロトコル | 9 |
| D | JIS/カタカナ固有 | 8 |
| E | macOS 標準で代替 | 5 |
| F | 優先度低・将来検討 | 44 |
| G | Telnet 固有 | 7 |
| **合計** | | **116** |

### 考察

- **約 45% (A+B+C+D)** は技術的・設計的な理由で macOS 版に移植する意味がない設定。Windows API 依存、TEK グラフィック端末、レガシープロトコル、JIS エンコーディング固有機能がこれに該当する。
- **約 4% (E)** は macOS の標準機能が同等以上の機能を提供しているため不要。
- **約 38% (F)** は技術的に実装可能だが、需要の低さから優先度を下げている項目。ユーザーからのリクエストに応じて順次対応を検討する。
- **約 6% (G)** は Telnet プロトコル固有の設定で、SSH 中心の現代的な利用形態では優先度が低い。
