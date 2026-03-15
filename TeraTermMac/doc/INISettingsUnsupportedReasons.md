# TERATERM.INI 未対応設定 — 詳細理由

INISettingsMapping.md で `x`（未対応）となっている設定項目について、
未対応の理由を分類・詳述する。

---

## 理由分類

| 分類 | 略称 | 説明 |
|------|------|------|
| A | Windows 専用 | Windows API・UI 機構に依存しており、macOS に該当概念がない |
| E | macOS 標準で代替 | macOS の標準機能（IME、ブラウザ連携等）が同等機能を提供 |

> **注記**: 以前は B (TEK 非対応)、C (レガシープロトコル)、D (JIS/カタカナ固有)、F (優先度低・将来検討)、G (Telnet 固有) の分類が存在したが、これらに該当する設定は全て INI 互換プロパティ (`TeraTermConfig`) として対応済みとなったため、本ドキュメントからは削除した。

---

## セクション: [Tera Term]

### ウィンドウ表示

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| HideTitle | A | タイトルバー非表示。macOS ではウィンドウのタイトルバーは OS 標準の操作体系（閉じる/最小化/最大化ボタン）と密接に関連しており、非表示にするとユーザビリティが著しく低下する。`NSWindow.styleMask` で技術的には可能だが、macOS の HIG に反するため非対応。 |
| PopupMenu | A | ポップアップメニューモード。Windows 版ではタイトルバーを非表示にした際にメニューを右クリックで表示する機能。macOS ではメニューバーが画面上部に常駐するため不要。 |
| VTPos | A | VT ウィンドウの絶対座標位置指定。macOS ではウィンドウ位置は `NSWindow.setFrameAutosaveName` による自動保存が標準。ピクセル座標の直接指定は Retina 対応等の問題もあり非対応。 |

### フォント

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| PrnFont | A | プリンタ用フォント指定。macOS の印刷機構は `NSPrintOperation` を使用し、画面フォントがそのまま使われる。プリンタ専用フォントの概念がない。 |

### キーボード

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| IME | E | IME の有効/無効。macOS では入力メソッド（日本語入力等）はシステムレベルで管理され、アプリが個別に制御する必要がない。 |
| IMEInline | E | IME インライン入力。macOS の `NSTextInputClient` プロトコルにより、インライン入力は標準動作として提供される。 |

### 接続 (TCP/IP)

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| HostDialogOnStartup | E | 起動時に接続ダイアログを自動表示。Mac 版は起動時に新規ウィンドウを開く macOS 標準の動作に従い、メニューから接続を開始する設計。 |

### シリアルポート

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| MaxComPort | A | 最大 COM ポート番号 (Windows の COM1〜COM256)。macOS ではシリアルポートは `/dev/tty.*` / `/dev/cu.*` のデバイスファイルとして列挙されるため、番号上限の概念がない。 |
| FlowCtrlRTS | A | RTS ラインの詳細制御 (DTR/RTS の個別設定)。macOS の `IOKit` シリアル API では `termios` 構造体で制御するが、Windows の `DCB` 構造体ほど細かい RTS/DTR 個別制御はサポートされない。 |
| FlowCtrlDTR | A | DTR ラインの詳細制御。同上。 |

### ログ

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| LogLockExclusive | A | ログファイルの排他ロック。Windows の `LOCKFILE_EXCLUSIVE_LOCK` に相当する機能。macOS では `flock()` / `fcntl()` で可能だが、UNIX 環境では advisory lock が一般的で、Windows のような mandatory lock の需要が低い。 |

### コピー＆ペースト

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| PasteDialogSize | A | ペースト確認ダイアログのサイズ指定 (ピクセル)。macOS では `NSAlert` / `NSPanel` のサイズは Auto Layout により自動調整されるため、固定サイズ指定は不要。 |

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

### その他特殊オプション

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| VTIcon | A | VT ウィンドウのアイコン指定。Windows のウィンドウアイコン (タスクバー/タイトルバー) に対応。macOS では Dock アイコンはアプリ単位で固定であり、ウィンドウ個別のアイコン設定は OS の設計にない。 |
| MaximizedBugTweak | A | Windows の最大化時のバグ回避ワークアラウンド。Windows 固有の描画バグに対応する設定で、macOS では該当する問題がない。 |
| DuplicateSession | A | セッション複製。Windows の `CreateProcess` でプロセスを複製する機能。Mac 版は新規ウィンドウ + 接続情報コピーで対応可能だが、仕組みが異なるため INI 設定としては非対応。 |
| JumpList | A | Windows 7+ のジャンプリスト (タスクバー右クリックメニュー) への接続先表示。macOS の Dock メニューに相当するが、Dock メニューへの動的項目追加は `NSDockTilePlugIn` で可能ながら未実装。 |

---

## セクション: [BG]

### テーマ

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| BGNoCopyBits | A | Windows GDI の `BitBlt` / `ScrollWindow` の CopyBits 無効化。ウィンドウのスクロール・リサイズ時に背景画像の残像を防ぐ Windows 固有の描画最適化設定。macOS の Core Animation / Metal レンダリングでは該当する問題がない。 |

---

## セクション: [Experimental]

| INI キー | 分類 | 未対応理由 |
|---------|------|----------|
| TreePropertySheet | A | 設定ダイアログをツリー形式のプロパティシートで表示する Windows UI の実験的機能。macOS では `NSTabView` / `NSToolbar` ベースの設定画面が標準であり、ツリー形式のプロパティシートは macOS の HIG に合わない。 |

---

## 未対応理由の統計

| 分類 | 略称 | 件数 |
|------|------|------|
| A | Windows 専用 | 31 |
| E | macOS 標準で代替 | 5 |
| **合計** | | **36** |

### 考察

- **約 86% (A)** は Windows API・UI 機構に依存しており、macOS に該当概念がないため移植する意味がない設定。メニュー制御 (10 件) とプリンタ (5 件) が大きな割合を占める。
- **約 14% (E)** は macOS の標準機能が同等以上の機能を提供しているため不要な設定。IME やブラウザ連携が該当する。
- 以前存在した分類 B (TEK 非対応)、C (レガシープロトコル)、D (JIS/カタカナ固有)、F (優先度低・将来検討)、G (Telnet 固有) に分類されていた設定は、全て `TeraTermConfig` の INI 互換プロパティとして対応済みとなった。これにより未対応項目数は 116 件から 36 件に大幅削減された。
