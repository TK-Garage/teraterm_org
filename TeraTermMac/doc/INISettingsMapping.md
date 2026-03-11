# TERATERM.INI 設定項目マッピング

オリジナル Tera Term (Windows) の `TERATERM.INI` 設定フォーマットと、
Tera Term Mac での対応状況を記載する。

INI ファイル保存先: `~/Library/Application Support/com.teraterm.mac/TERATERM.INI`
改行コード: LF

---

## セクション: [Tera Term]

### バージョン・メタ情報

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| Version | string | "5.6" | 設定ファイルのバージョン | o | TeraTermConfig.version |
| Port | string | "tcpip" | 接続タイプ ("tcpip" / "serial") | o | portType |

### 端末エミュレーション

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| TerminalSize | string | "80,24" | 端末サイズ "幅,高さ" | o | terminalWidth, terminalHeight |
| TermIsWin | on/off | off | 端末サイズ=ウィンドウサイズ | o | termIsWin (default: true) |
| AutoWinResize | on/off | off | 自動ウィンドウリサイズ | o | autoWinResize |
| TerminalID | string | "" | 端末ID (VT100/VT220/etc.) | o | terminalID |
| Answerback | string | "" | ENQ 応答文字列 (Hex エンコード) | o | answerback |
| TermType | string | "xterm" | Telnet/SSH 端末タイプ | o | termType |
| TerminalUID | string | "FFFFFFFF" | 端末ユニークID (8桁Hex) | x | - |
| TerminalSpeed | string | "38400" | 端末速度 (Telnet/SSH用) | x | - |

### 改行設定

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| CRReceive | string | "CR" | 受信改行 ("CR"/"CRLF"/"LF"/"AUTO") | o | crReceive |
| CRSend | string | "CR" | 送信改行 ("CR"/"CRLF"/"LF") | o | crSend |

### 文字コード

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| KanjiReceive | string | "" | 受信漢字コード (UTF-8/SJIS/EUC/JIS等) | o | encoding |
| KanjiSend | string | "" | 送信漢字コード | o | sendEncoding |
| KatakanaReceive | string | "8" | 受信カタカナ ("7"=7bit/"8"=8bit) | x | - |
| KatakanaSend | string | "8" | 送信カタカナ | x | - |
| KanjiIn | string | "B" | JIS KanjiIn designator ("@"/"B") | x | - |
| KanjiOut | string | "J" | JIS KanjiOut designator ("J"/"B"/"H") | x | - |

### ローカルエコー

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| LocalEcho | on/off | off | ローカルエコー有効 | o | localEcho |

### カーソル

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| CursorShape | string | "block" | カーソル形状 ("block"/"vertical"/"horizontal") | o | cursorShape |
| NonblinkingCursor | on/off | off | カーソル点滅無効 | o | cursorBlink (反転) |
| KillFocusCursor | on/off | on | フォーカス喪失時ポリゴンカーソル | x | - |

### ウィンドウ表示

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| Title | string | "Tera Term" | ウィンドウタイトル | o | title |
| TitleFormat | int | 13 | タイトル書式ビットフィールド | o | titleFormat |
| HideTitle | on/off | off | タイトルバー非表示 | x | - |
| PopupMenu | on/off | off | ポップアップメニュー有効 | x | - |
| VTPos | string | "-2147483648,-2147483648" | VTウィンドウ位置 "x,y" | x | - |
| TEKPos | string | "-2147483648,-2147483648" | TEKウィンドウ位置 "x,y" | x | - |
| SaveVTWinPos | on/off | off | VTウィンドウ位置を保存 | x | - |

### スクロール

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| EnableScrollBuff | on/off | on | スクロールバッファ有効 | o | enableScrollBuffer |
| ScrollBuffSize | int | 100 | スクロールバッファ行数 | o | scrollBufferSize (default: 10000) |
| MaxBuffSize | int | 10000 | スクロールバッファ最大値 | o | scrollBufferMax (default: 500000) |
| ScrollThreshold | int | 12 | スクロール閾値 | x | - |
| ScrollWindowClearScreen | on/off | on | スクロール時画面クリア | x | - |

### 色設定

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| VTColor | string | "0,0,0,255,255,255" | VT文字色/背景色 "fg_r,fg_g,fg_b,bg_r,bg_g,bg_b" | o | vtColor / colorTheme |
| VTBoldColor | string | "0,0,255,255,255,255" | 太字色/背景色 | o | attrColorBold |
| VTBlinkColor | string | "255,0,0,255,255,255" | 点滅色/背景色 | o | attrColorBlink |
| VTReverseColor | string | "255,255,255,0,0,0" | 反転色/背景色 | o | attrColorReverse |
| VTUnderlineColor | string | "255,0,255,255,255,255" | 下線色/背景色 | o | attrColorUnderline |
| URLColor | string | "0,255,0,255,255,255" | URL色/背景色 | o | attrColorURL / urlColor |
| TEKColor | string | "0,0,0,255,255,255" | TEK文字色/背景色 | x | - |
| ANSIColor | string | (16色定義) | ANSI 16色パレット "id,r,g,b,..." | o | colorTheme.ansiColors |
| EnableBoldAttrColor | on/off | on | 太字属性色有効 | o | enableBoldColor |
| EnableBlinkAttrColor | on/off | on | 点滅属性色有効 | o | enableBlinkColor |
| EnableReverseAttrColor | on/off | off | 反転属性色有効 | o | enableReverseColor |
| EnableURLColor | on/off | on | URL色有効 | o | enableURLColor |
| EnableANSIColor | on/off | on | ANSIカラー有効 | o | enableANSIColor |
| PcBoldColor | on/off | off | PC式太字カラーマッピング | x | - |
| Aixterm16Color | on/off | off | aixterm 16色モード | o | enableAixtermColors |
| Xterm256Color | on/off | on | xterm 256色モード | o | enableXterm256Colors |
| UseTextColor | on/off | off | テキスト色をANSIカラーに使用 | x | - |
| UseNormalBGColor | on/off | off | 標準背景色を常に使用 | o | useStandardBGColor |
| TEKColorEmulation | on/off | off | TEKカラーエミュレーション | x | - |

### フォント

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| VTFont | string | "Terminal,0,-13,1" | VTフォント "name,width,height,charset" | o | fontName, fontSize |
| TEKFont | string | "Courier,0,-13,0" | TEKフォント | o | tekFontName, tekFontSize |
| EnableBold | on/off | on | 太字フォント描画有効 | o | enableBoldFont |
| URLUnderline | on/off | on | URL下線表示 | o | enableURLUnderline |
| UnderlineAttrFont | on/off | on | 下線属性フォント有効 | o | enableUnderlineDecoration |
| UnderlineAttrColor | on/off | on | 下線属性色有効 | o | enableUnderlineColor |
| VTFontSpace | string | "0,0,0,0" | フォント間隔 "dx,dw,dy,dh" | o | charSpaceH, charSpaceV |
| PrnFont | string | NULL | プリンタフォント | x | - |
| FontQuality | string | "default" | フォント品質 ("default"/"nonantialiased"/"antialiased"/"cleartype") | o | fontQuality |
| FontScaling | on/off | off | フォントスケーリング | o | resizeFontToFitWidth |
| DrawingResizedFont | on/off | on | リサイズフォント描画 | o | resizeFontToFitWidth |
| DlgFont | string | NULL | ダイアログフォント "name,point,charset" | o | dialogFontName, dialogFontSize |
| VTDrawAPI | string | "Auto" | 描画API ("Auto"/"GDI"/"DirectWrite") | o | drawingAPI |
| VTDrawACP | int | 0 | 描画ANSI コードページ (0=自動) | o | codePage |

### キーボード

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| BSKey | string | "BS" | BSキー送信 ("BS"/"DEL") | o | bsKey |
| DeleteKey | on/off | off | Deleteキー有効 | o | deleteKey |
| MetaKey | string | "off" | Metaキー ("off"/"on"/"left"/"right") | o | metaKey |
| Meta8Bit | string | "off" | Meta 8bit設定 ("off"/"raw"/"text") | x | - |
| DisableAppKeypad | on/off | off | アプリケーションキーパッド無効 | o | disableAppKeypad |
| DisableAppCursor | on/off | off | アプリケーションカーソル無効 | o | disableAppCursor |
| StrictKeyMapping | on/off | off | 厳密キーマッピング | x | - |
| RussKeyb | string | "" | ロシア語キーボード | x | - |
| IME | on/off | on | IME有効 (Windows専用) | x | - |
| IMEInline | on/off | on | IMEインライン入力 (Windows専用) | x | - |
| IMERelatedCursor | on/off | off | IME連動カーソル変更 | o | cursorChangeIME |

### ビープ

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| Beep | string | "on" | ビープ種別 ("on"/"off"/"visual") | o | beepType |
| BeepOnConnect | on/off | off | 接続時ビープ | o | beepOnConnect |
| BeepOverUsedCount | int | 5 | ビープ過多検知回数 | x | - |
| BeepOverUsedTime | int | 2 | ビープ過多検知時間 (秒) | x | - |
| BeepSuppressTime | int | 5 | ビープ抑制時間 (秒) | x | - |
| BeepVBellWait | int | 10 | ビジュアルベル待機時間 (ms) | x | - |
| NotifySound | on/off | on | 通知音有効 | o | notifySound |

### 接続 (TCP/IP)

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| Telnet | on/off | on | Telnet有効 | o | telnet |
| TCPPort | int | 23 | TCPポート番号 | o | tcpPort / defaultPort |
| TelPort | int | 23 | Telnetポート番号 | x | - |
| AutoWinClose | on/off | on | 切断時自動ウィンドウ閉じ | o | autoWindowClose |
| HistoryList | on/off | off | 接続履歴リスト | o | hostHistory |
| ConnectingTimeout | int | 0 | 接続タイムアウト (秒, 0=無限) | x | - |
| TelAutoDetect | on/off | on | Telnet自動検出 | x | - |
| TelBin | on/off | off | Telnetバイナリフラグ | x | - |
| TelEcho | on/off | off | Telnetエコーフラグ | x | - |
| TelKeepAliveInterval | int | 300 | Telnetキープアライブ間隔 (秒) | o | tcpKeepAliveInterval |
| TCPLocalEcho | on/off | off | 非Telnetローカルエコー | x | - |
| TCPCRSend | string | "" | 非Telnet改行送信 ("CR"/"CRLF"/"") | x | - |
| DisableTCPEchoCR | - | FALSE | TCPLocalEcho/TCPCRSend無効 | x | - |
| HostDialogOnStartup | on/off | on | 起動時接続ダイアログ表示 | x | - |

### シリアルポート

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| ComPort | int | 1 | COMポート番号 | o | serialPort |
| BaudRate | int | 9600 | ボーレート | o | baudRate |
| Parity | string | "none" | パリティ ("none"/"odd"/"even"/"mark"/"space") | o | parity |
| DataBit | string | "8" | データビット ("7"/"8") | o | dataBits |
| StopBit | string | "1" | ストップビット ("1"/"2") | o | stopBits |
| FlowCtrl | string | "none" | フロー制御 ("none"/"x"/"hard"/"rtscts"/"dsrdtr") | o | flowControl |
| DelayPerChar | int | 0 | 文字遅延 (ms) | o | serialDelayPerChar |
| DelayPerLine | int | 0 | 行遅延 (ms) | o | serialDelayPerLine |
| MaxComPort | int | 256 | 最大COMポート番号 | x | - |
| ClearComBuffOnOpen | on/off | on | ポートオープン時バッファクリア | x | - |
| WaitCom | on/off | off | COMポート接続待ち | x | - |
| AutoComPortReconnect | on/off | on | シリアルポート自動再接続 | x | - |
| AutoComPortReconnectDelayNormal | int | 500 | 自動再接続遅延 (ms) | x | - |
| AutoComPortReconnectDelayIllegal | int | 2000 | 異常時再接続遅延 (ms) | x | - |
| AutoComPortReconnectRetryInterval | int | 1000 | 再接続リトライ間隔 (ms) | x | - |
| AutoComPortReconnectRetryCount | int | 3 | 再接続リトライ回数 | x | - |
| FlowCtrlRTS | int | -1 | RTS フロー制御詳細設定 | x | - |
| FlowCtrlDTR | int | -1 | DTR フロー制御詳細設定 | x | - |

### ログ

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| LogAutoStart | on/off | off | ログ自動開始 | o | logAutoStart |
| LogDefaultName | string | "teraterm.log" | デフォルトログファイル名 | o | logDefaultName |
| LogDefaultPath | string | (LogDir) | デフォルトログ保存先パス | o | logDefaultDirectory |
| LogTimestamp | on/off | off | タイムスタンプ付加 | o | logTimestamp |
| LogTimestampFormat | string | "%Y-%m-%d %H:%M:%S.%N" | タイムスタンプ書式 | x | - |
| LogTimestampType | string | "Local" | タイムスタンプ種別 ("Local"/"UTC"/"LoggingElapsed"/"ConnectionElapsed") | o | logTimestampType |
| LogTypePlainText | on/off | off | プレーンテキストログ | o | logPlainText (default: true) |
| LogBinary | on/off | off | バイナリログ | o | logBinary |
| LogAppend | on/off | off | ログ追記モード | o | logAppend |
| LogHideDialog | on/off | off | ログダイアログ非表示 | o | logHideDialog |
| LogIncludeScreenBuffer | on/off | off | 画面バッファ含む | o | logIncludeScreenBuffer |
| LogRotate | int | 0 | ログローテーションモード | o | logRotateEnabled |
| LogRotateSize | int | 0 | ローテーションサイズ | o | logRotateSize |
| LogRotateSizeType | int | 0 | ローテーションサイズ種別 | x | - |
| LogRotateStep | int | 0 | ローテーションステップ | o | logRotateStep |
| DeferredLogWriteMode | on/off | on | 遅延ログ書込みモード | x | - |
| LogLockExclusive | on/off | on | ログファイル排他ロック | x | - |
| ViewlogEditor | string | "notepad.exe" | ログビューアエディタ | o | logViewEditor |
| ViewlogEditorArg | string | NULL | ログビューア引数 | o | logEditorArguments |
| LogBOM | - | - | UTF-8 BOM 書き込み | o | logBOM |

### ファイル転送

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| TransBin | on/off | off | バイナリ転送フラグ | x | - |
| XmodemOpt | string | "checksum" | XMODEM方式 ("checksum"/"crc"/"1k"/"1ksum") | o | xmodemOption |
| XmodemBin | on/off | on | XMODEMバイナリ | x | - |
| XModemRcvCommand | string | "" | XMODEM受信コマンド | x | - |
| YModemRcvCommand | string | "rb" | YMODEM受信コマンド | x | - |
| ZmodemDataLen | int | 1024 | ZMODEMデータ長 | o | zmodemDataLen |
| ZmodemWinSize | int | 32767 | ZMODEMウィンドウサイズ | o | zmodemWindowSize |
| ZModemRcvCommand | string | "rz" | ZMODEM受信コマンド | x | - |
| ZmodemAuto | on/off | off | ZMODEM自動起動 | x | - |
| ZmodemEscCtl | on/off | off | ZMODEM ESCCTLフラグ | x | - |
| FileDir | string | "" | ファイル転送ディレクトリ | o | fileTransferFolder |
| FileSendFilter | string | "" | ファイル送信フィルタ | x | - |
| ScpSendDir | string | "" | SCP送信先ディレクトリ | x | - |
| FTHideDialog | on/off | off | ファイル転送ダイアログ非表示 | x | - |
| AutoFileRename | on/off | off | ファイル自動リネーム | x | - |
| ConfirmFileDragAndDrop | on/off | on | D&Dファイル送信確認 | x | - |

### XMODEM/YMODEM/ZMODEMタイムアウト

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| XmodemTimeouts | string | "10,3,10,20,60" | XMODEMタイムアウト (init,initCRC,short,long,vlong) | x |
| YmodemTimeouts | string | "10,3,10,20,60" | YMODEMタイムアウト | x |
| ZmodemTimeouts | string | "10,0,10,3" | ZMODEMタイムアウト (normal,tcpip,init,fin) | x |

### 制御シーケンス

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| Accept8BitCtrl | on/off | on | 8bit制御コード受付 | x | - |
| AllowWrongSequence | on/off | off | 不正シーケンス許可 | x | - |
| AcceptTitleChangeRequest | string | "overwrite" | タイトル変更要求 ("off"/"overwrite"/"ahead"/"last") | o | titleChangeRequest, titleChangeMode |
| WindowCtrlSequence | on/off | on | ウィンドウ制御シーケンス | o | windowControlSequence |
| CursorCtrlSequence | on/off | off | カーソル制御シーケンス | o | cursorControlSequence |
| WindowReportSequence | on/off | on | ウィンドウレポートシーケンス | o | windowInfoReportSequence |
| TitleReportSequence | string | "Empty" | タイトルレポート ("accept"/"ignore"/"empty") | o | titleReportRequest |
| ClipboardAccessFromRemote | string | "off" | リモートクリップボード ("off"/"read"/"write"/"on") | o | clipboardAccessFromRemote, clipboardAccessMode |
| NotifyClipboardAccess | on/off | on | クリップボードアクセス通知 | o | notifyClipboardAccess |
| ClearScrollBufferFromRemote | on/off | on | リモートスクロールバッファクリア | o | acceptScrollBufferClear |
| ClearOnResize | on/off | off | リサイズ時画面クリア | o | clearOnResize |
| AlternateScreenBuffer | on/off | on | 代替スクリーンバッファ | x | - |
| EnableStatusLine | on/off | on | ステータスライン有効 | x | - |
| EnableLineMode | on/off | on | ラインモード有効 | x | - |
| PrinterCtrlSequence | on/off | off | プリンタ制御シーケンス受付 | o | disablePrintSequence (反転) |
| UseInvalidDECRQSSResponse | on/off | off | 無効DECRPSS (テスト用) | x | - |
| TabStopModifySequence | string | "on" | タブストップ変更シーケンス | x | - |
| ISO2022ShiftFunction | string | "on" | ISO2022シフト機能 | x | - |
| MaxOSCBufferSize | int | 4096 | OSCバッファ最大サイズ | x | - |
| Send8BitCtrl | on/off | off | 8bit制御シーケンス送信 | x | - |

### コピー＆ペースト

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| AutoTextCopy | on/off | on | 選択時自動コピー | o | autoTextCopy |
| EnableContinuedLineCopy | on/off | off | 連続行コピー | o | continuedLineCopy (default: true) |
| SelectOnlyByLButton | on/off | on | 左ボタンのみ選択 | o | leftClickOnlySelection |
| SelectOnActivate | on/off | on | アクティブ化時選択有効 | o | enableSelectionOnActivate |
| DisablePasteMouseRButton | on/off | off | 右クリックペースト無効 | o | disableRightClickPaste |
| DisablePasteMouseMButton | on/off | on | 中クリックペースト無効 | o | disableMiddleClickPaste |
| ConfirmPasteMouseRButton | on/off | off | 右クリックペースト確認 | o | confirmRightClickPaste |
| ConfirmChangePaste | on/off | on | ペースト変更確認 | o | clipboardConfirmPaste |
| ConfirmChangePasteCR | on/off | on | 改行付きペースト確認 | o | confirmPasteNewLine |
| ConfirmChangePasteStringFile | string | "" | 危険文字列判定ファイル | o | dangerousKeywordFile |
| TrimTrailingNLonPaste | on/off | off | ペースト末尾改行削除 | o | trimTrailingNewline |
| PasteDelayPerLine | int | 10 | ペースト行遅延 (ms, 0-5000) | o | pasteDelay (default: 5) |
| PasteDialogSize | string | "330,220" | ペースト確認ダイアログサイズ "w,h" | x | - |
| DelimList | string | (Hex encoded) | ダブルクリック区切り文字 | o | delimiterList |
| DelimDBCS | on/off | on | DBCS文字を区切りとみなす | x | - |
| MouseSelectStartDelay | int | 0 | マウス選択開始遅延 (ms) | x | - |

### マウス

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| MouseEventTracking | on/off | on | マウスイベントトラッキング | o | mouseTracking |
| MouseWheelScrollLine | int | 3 | ホイールスクロール行数 | o | mouseWheelScrollLines |
| MouseCursor | string | "IBEAM" | マウスカーソル形状 | o | mouseCursorType |
| TranslateWheelToCursor | on/off | on | ホイールをカーソルキーに変換 | x | - |
| DisableMouseTrackingByCtrl | on/off | on | Ctrl時マウストラッキング無効 | o | disableControlKeyMouseEvent |
| DisableWheelToCursorByCtrl | on/off | on | Ctrl時ホイール→カーソル無効 | x | - |

### ウィンドウ透過度

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| AlphaBlend | int | 255 | 非アクティブ時透過度 (0-255) | o | windowOpacityInactive |
| AlphaBlendActive | int | (=AlphaBlend) | アクティブ時透過度 (0-255) | o | windowOpacityActive |

### ブロードキャスト

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| BroadcastCommandHistory | on/off | off | ブロードキャストコマンド履歴 | o | broadcastHistory |
| AcceptBroadcast | on/off | on | ブロードキャスト受信 | o | broadcastSendToThisOnly (反転) |
| MaxBroadcatHistory | int | 99 | 最大ブロードキャスト履歴数 | x | - |

### デバッグ

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| Debug | on/off | off | デバッグモード | o | debugCharInfoPopup |
| DebugModes | string | "all" | デバッグモード種別 ("all"/"none"/"normal"/"hex"/"noout") | x | - |

### URL

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| EnableClickableUrl | on/off | off | クリック可能URL有効 | o | enableURLColor / enableURLUnderline |
| ClickableUrlBrowser | string | "" | URLブラウザパス | x | - |
| ClickableUrlBrowserArg | string | "" | URLブラウザ引数 | x | - |
| JoinSplitURL | on/off | off | 分割URL結合 | x | - |
| JoinSplitURLIgnoreEOLChar | string | "\\" | 分割URL行末無視文字 | x | - |

### Cygwin (Windows専用)

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| CygwinDirectory | string | "c:\\cygwin" | Cygwinインストールパス | x |

### メニュー制御 (Windows専用)

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| EnablePopupMenu | on/off | on | ポップアップメニュー有効 | x |
| EnableShowMenu | on/off | on | メニュー表示有効 | x |
| WindowMenu | on/off | on | ウィンドウメニュー表示 | x |
| DisableAcceleratorSendBreak | on/off | off | Breakアクセラレータ無効 | x |
| DisableAcceleratorDuplicateSession | on/off | off | セッション複製アクセラレータ無効 | x |
| AcceleratorNewConnection | on/off | on | 新規接続アクセラレータ | x |
| AcceleratorCygwinConnection | on/off | on | Cygwin接続アクセラレータ | x |
| DisableMenuSendBreak | on/off | off | Breakメニュー無効 | x |
| DisableMenuDuplicateSession | on/off | off | セッション複製メニュー無効 | x |
| DisableMenuNewConnection | on/off | off | 新規接続メニュー無効 | x |

### プリンタ (Windows専用)

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| PassThruDelay | int | 3 | パススルー印刷遅延 | x |
| PassThruPort | string | "" | パススルー印刷ポート | x |
| PrnMargin | string | "50,50,50,50" | 印刷マージン "左,右,上,下" | x |
| PrnConvFF | on/off | off | FFをNLに変換 | x |
| VTPPI | string | "0,0" | VT印刷PPI | x |
| TEKPPI | string | "0,0" | TEK印刷PPI | x |

### Kermit

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| KmtLog | on/off | off | Kermitログ | x |
| KmtLongPacket | on/off | off | Kermit長パケット | x |
| KmtFileAttr | on/off | off | Kermitファイル属性 | x |

### B-Plus

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| BPAuto | on/off | off | B-Plus自動起動 | x |
| BPEscCtl | on/off | off | B-Plus ESCCTLフラグ | x |
| BPLog | on/off | off | B-Plusログ | x |

### Quick-VAN

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| QVLog | on/off | off | Quick-VANログ | x |
| QVWinSize | int | 8 | Quick-VANウィンドウサイズ | x |

### プロトコル制御ログ

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| TelLog | on/off | off | Telnetログ | x |
| XmodemLog | on/off | off | XMODEMログ | x |
| YmodemLog | on/off | off | YMODEMログ | x |
| ZmodemLog | on/off | off | ZMODEMログ | x |

### その他特殊オプション

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| AutoWinSwitch | on/off | off | VT/TEK自動切り替え | x | - |
| CtrlInKanji | on/off | on | 漢字中の制御コード | x | - |
| FixedJIS | on/off | off | 固定JIS | x | - |
| BackWrap | on/off | off | バックラップ | x | - |
| AutoInvoke | on/off | off | 自動インボーク | x | - |
| ConfirmDisconnect | on/off | on | 切断確認 | o | confirmOnDisconnect |
| VTCompatTab | on/off | off | VT互換タブ | x | - |
| VTIcon | string | "Default" | VTウィンドウアイコン | x | - |
| TEKIcon | string | "Default" | TEKウィンドウアイコン | x | - |
| TEKGINMouseCode | int | 32 | TEK GINマウスキーコード | x | - |
| SendBreakTime | int | 1000 | Breakシグナル時間 (ms) | x | - |
| MaximizedBugTweak | int | 2 | 最大化バグ回避 (Windows専用) | x | - |
| DuplicateSession | - | - | セッション複製 (Windows専用) | x | - |
| Wait4allMacroCommand | on/off | off | 全マクロコマンド待ち | x | - |
| ClearScreenOnCloseConnection | on/off | off | 接続終了時画面クリア | x | - |
| FileSendHighSpeedMode | on/off | on | 高速ファイル送信 | x | - |
| FallbackToCP932 | on/off | off | CP932フォールバック | x | - |
| StartupMacro | string | "" | 起動時マクロファイル | x | - |
| AutoScrollOnlyInBottomLine | on/off | off | 最終行のみ自動スクロール | x | - |
| JumpList | on/off | on | ジャンプリスト (Windows専用) | x | - |
| LockTUID | on/off | on | 端末UID固定 | x | - |
| WindowCornerDontround | on/off | off | ウィンドウ角丸め禁止 | o | cornerRounding |
| IniAutoBackup | on/off | on | INI自動バックアップ | x | - |
| BracketedSupport | on/off | on | Bracketed paste mode対応 | x | - |
| BracketedControlOnly | on/off | off | Bracketedモード制御のみ | x | - |

### Unicode設定

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| UnicodeAmbiguousWidth | int | 0 (=auto) | 曖昧幅 (1=半角, 2=全角, 0=自動) | o | unicodeAmbiguousWidth |
| UnicodeEmojiOverride | on/off | off | 絵文字幅オーバーライド | x | - |
| UnicodeEmojiWidth | int | 0 (=auto) | 絵文字幅 (1=半角, 2=全角) | o | unicodeEmojiWidth |
| UnicodeToDecSpMapping | int | 3 | Unicode→DEC特殊文字マッピング | x | - |
| DecSpMappingDir | int | 2 | DEC特殊マッピング方向 | x | - |

### Sendfile設定

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| SendfileDelayType | string | "NoDelay" | 送信遅延種別 ("NoDelay"/"PerChar"/"PerLine"/"PerSendSize") | x |
| SendfileDelayTick | int | 0 | 送信遅延Tick | x |
| SendfileSize | int | 4096 | 送信サイズ | x |
| SendfileSequential | on/off | off | 順次送信 | x |
| SendfileSkipOptionDialog | on/off | off | オプションダイアログスキップ | x |

### Receivefile設定

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| FileReceiveFilter | string | "" | 受信ファイルフィルタ | x |
| ReceivefileSkipOptionDialog | on/off | off | オプションダイアログスキップ | x |
| ReceivefileAutoStopWaitTime | int | 5 | 自動停止待機時間 (秒) | x |

### UI言語

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| UILanguageFile | string | "" | UI言語ファイルパス | o | language |

---

## セクション: [BG]

テーマ / 背景画像設定 (eterm_lookfeel)

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| BGEnable | int | 0 | 背景テーマ (0=無効/1=固定/2=ランダム) | o | themeEnabled |
| BGThemeFile | string | "" | テーマファイルパス | o | themeFile |
| BGSPIPath | string | "" | Susieプラグインパス | o | susiePath |
| BGFastSizeMove | int | 0 | 高速サイズ変更 | o | fastSizeMove |
| BGNoCopyBits | int | 0 | CopyBits無効 | x | - |
| BGNoFrame | int | 0 | フレーム無し | o | hideWindowFrame |

---

## セクション: [TTSSH] (TTSSH プラグイン)

SSH 関連設定。オリジナルは TTSSH プラグインが管理するため、`TERATERM.INI` 内の
`[TTSSH]` セクションに保存される。Mac 版では `TerminalSettings` に統合。

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| SSHVersion | int | 2 | SSHバージョン (1/2) | o | sshVersion |
| DefaultAuthMethod | int | 0 | デフォルト認証方式 | o | sshAuthMethod |
| DefaultUserName | string | "" | デフォルトユーザー名 | o | sshDefaultUsername |
| DefaultUserNameMode | int | 0 | ユーザー名入力モード | o | sshDefaultUsernameMode |
| DefaultForwarding | string | "" | デフォルトポート転送 | o | sshPortForwardings |
| HeartBeat | int | 60 | ハートビート間隔 (秒) | o | sshHeartbeat |
| ForwardAgent | on/off | off | エージェント転送 | o | sshForwardAgent |
| ConfirmForwardAgent | on/off | on | エージェント転送確認 | o | sshConfirmAgentForwarding |
| NotifyForwardAgent | on/off | off | エージェントアクセス通知 | o | sshNotifyAgentAccess |
| VerifyHostKeyDNS | on/off | off | DNSホストキー検証 | o | sshVerifyHostKeyDNS |
| KnownHostsFile | string | "" | known_hostsファイル | o | sshKnownHostsFile |
| KnownHostsReadOnlyFile | string | "" | 読み取り専用known_hosts | o | sshReadOnlyHostsFile |
| HostKeyRotation | int | 0 | ホストキーローテーション (0=無効/1=有効/2=確認) | o | sshHostKeyRotation |
| LogLevel | int | 0 | SSHログレベル | o | sshLogLevel |
| CompressionLevel | int | 0 | 圧縮レベル (0-9) | o | sshCompressionLevel |
| XForwarding | on/off | off | X転送 | o | sshXForwarding |
| CheckAuthBeforeLogin | on/off | off | ログイン前認証確認 | o | sshCheckAuthBeforeLogin |
| CipherOrder | string | (暗号リスト) | 暗号アルゴリズム優先順位 | o | sshCipherOrder |
| KexOrder | string | (鍵交換リスト) | 鍵交換アルゴリズム順位 | o | sshKexOrder |
| HostKeyOrder | string | (ホスト鍵リスト) | ホスト鍵アルゴリズム順位 | o | sshHostKeyOrder |
| MACOrder | string | (MACリスト) | MACアルゴリズム順位 | o | sshMACOrder |
| CompOrder | string | (圧縮リスト) | 圧縮アルゴリズム順位 | o | sshCompressionOrder |

---

## セクション: [Proxy] (TTSSH プラグイン)

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 | Mac プロパティ |
|---------|---|------------|------|---------|--------------|
| ProxyType | int | 0 | プロキシ種別 (0=なし/1=HTTP/2=SOCKS4/3=SOCKS5/4=Telnet) | o | proxyType |
| ProxyHost | string | "" | プロキシホスト名 | o | proxyHost |
| ProxyPort | int | 0 | プロキシポート | o | proxyPort |
| ProxyUser | string | "" | プロキシユーザー名 | o | proxyUsername |
| ProxyPass | string | "" | プロキシパスワード | o | proxyPassword |

---

## セクション: [Experimental]

| INI キー | 型 | デフォルト値 | 説明 | Mac 対応 |
|---------|---|------------|------|---------|
| TreePropertySheet | on/off | off | ツリー形式プロパティシート | x |

---

## 対応状況サマリ

| カテゴリ | オリジナル項目数 | Mac対応数 | 未対応数 |
|---------|---------------|----------|---------|
| バージョン・メタ | 2 | 2 | 0 |
| 端末エミュレーション | 8 | 6 | 2 |
| 改行 | 2 | 2 | 0 |
| 文字コード | 6 | 2 | 4 |
| ローカルエコー | 1 | 1 | 0 |
| カーソル | 3 | 2 | 1 |
| ウィンドウ表示 | 7 | 2 | 5 |
| スクロール | 5 | 3 | 2 |
| 色設定 | 17 | 13 | 4 |
| フォント | 14 | 12 | 2 |
| キーボード | 11 | 6 | 5 |
| ビープ | 7 | 3 | 4 |
| 接続 (TCP/IP) | 14 | 5 | 9 |
| シリアルポート | 18 | 8 | 10 |
| ログ | 17 | 13 | 4 |
| ファイル転送 | 16 | 4 | 12 |
| 制御シーケンス | 17 | 8 | 9 |
| コピー＆ペースト | 14 | 11 | 3 |
| マウス | 6 | 4 | 2 |
| 透過度 | 2 | 2 | 0 |
| ブロードキャスト | 3 | 2 | 1 |
| デバッグ | 2 | 1 | 1 |
| URL | 5 | 1 | 4 |
| Unicode | 5 | 2 | 3 |
| メニュー制御 | 10 | 0 | 10 |
| プリンタ | 6 | 0 | 6 |
| Kermit | 3 | 0 | 3 |
| B-Plus | 3 | 0 | 3 |
| Quick-VAN | 2 | 0 | 2 |
| プロトコルログ | 4 | 0 | 4 |
| その他特殊 | 27 | 3 | 24 |
| Sendfile/Receivefile | 8 | 0 | 8 |
| UI言語 | 1 | 1 | 0 |
| [BG] テーマ | 6 | 4 | 2 |
| [TTSSH] SSH | 22 | 21 | 1 |
| [Proxy] | 5 | 5 | 0 |
| [Experimental] | 1 | 0 | 1 |
| **合計** | **約300** | **約148** | **約152** |

### 凡例

- **o** : Mac 版で対応済み（プロパティにマッピングあり）
- **x** : Mac 版で未対応（Windows 専用機能、または未実装）
- **型**: `on/off` = GetOnOff (off=0,on=非0), `int` = GetPrivateProfileInt, `string` = GetPrivateProfileString
- INI ファイルの値は全てテキスト表現。bool は `on`/`off` 文字列で保存。

---

## 多言語対応 (Localization) 状況

全てのメニュー項目、ダイアログラベル、ボタン、ツールチップは `NSLocalizedString` 経由で
`Localizable.strings` から取得する設計。

### 対応言語

| 言語 | リソース | ステータス |
|------|---------|-----------|
| English (en) | `en.lproj/Localizable.strings` | Yes — 完全対応 |
| 日本語 (ja) | `ja.lproj/Localizable.strings` | Yes — 完全対応 |

### ローカライズ済みUIコンポーネント

| コンポーネント | ローカライズ | NSStackView動的レイアウト | テスト済み |
|--------------|------------|------------------------|----------|
| メインメニュー (File/Edit/Setup/Code/Control/Window/Help) | Yes | N/A (NSMenu) | Yes |
| 接続ダイアログ (IDD_HOSTDLG) | Yes | Yes | Yes |
| 端末設定ダイアログ (IDD_TERMDLG) | Yes | Yes (LocalizedTerminalSetupViewController) | Yes |
| ウインドウ設定ダイアログ (IDD_WINDLG) | Yes | — | Yes |
| キーボード設定ダイアログ | Yes | — | Yes |
| シリアルポート設定ダイアログ (IDD_SERIALDLG) | Yes | — | Yes |
| SSH認証ダイアログ | Yes | — | Yes |
| SSH設定ダイアログ群 (IDD_SSHSETUP等) | Yes | — | Yes |
| プロキシ設定ダイアログ (IDD_SETTING) | Yes | — | Yes |
| その他の設定 13タブ (AdditionalSettings) | Yes | — | Yes |
| ファイル転送ダイアログ群 | Yes | — | Yes |
| ブロードキャストダイアログ | Yes | — | Yes |
| セキュリティダイアログ群 (Unknown Host等) | Yes | — | Yes |
| マクロダイアログ群 (messagebox等) | Yes | — | Yes |
| SCP ダイアログ | Yes | — | Yes |

### テスト検証体制

| テスト種別 | ファイル | 内容 |
|-----------|--------|------|
| XCUITest 言語切替 | `MultilingualSettingsTests.swift` | `-AppleLanguages (ja/en)` で起動し、メニュー・ボタン翻訳を検証 |
| ローカライズキー検証 | `MultilingualSettingsTests.swift` | 全ての重要キーが en/ja 両方で値を持つことを確認 |
| はみ出し検知 | `MultilingualSnapshotTests.swift` | NSButton/NSTextField のフレーム幅 vs テキスト幅を比較 |
| PNG スナップショット | `MultilingualSnapshotTests.swift` | 各言語のダイアログ状態を PNG で保存し、視覚的に検証 |
| NSStackView検証 | `MultilingualSettingsTests.swift` | Compression Resistance が高いことを確認し、ラベル切れを防止 |

### INI の Language プロパティとの連携

INI ファイルの `UILanguageFile` キーに言語設定が保存されている場合、
`TerminalSettings.language` プロパティにマッピングされる。
アプリ起動時にこの値を `UserDefaults.standard.set(["ja"], forKey: "AppleLanguages")`
等で適用することで、INI ファイルの言語設定をシステム言語より優先させることが可能。

ただし macOS では OS 標準のローカライズ機構を尊重し、INI からの言語上書きは
Additional Settings > UI タブ の「言語」設定からのみ行う設計とする。
