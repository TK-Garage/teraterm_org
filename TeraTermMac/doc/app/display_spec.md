# TeraTerm Mac.app - 表示・入力実装仕様

## 概要

TeraTerm Mac の表示レイヤーは、オリジナル Windows 版 `vtdisp.c`/`vtterm.c`/`buffer.c`/`keyboard.c` を
Swift/macOS (AppKit + Core Text) にポートしたものである。

ソースコード:
- `Sources/TeraTermMac/View/TerminalView.swift` — 描画ビュー
- `Sources/TeraTermMac/Terminal/TerminalEmulator.swift` — VT エミュレータ
- `Sources/TeraTermMac/Terminal/VTParser.swift` — エスケープシーケンスパーサ
- `Sources/TeraTermMac/Buffer/TerminalBuffer.swift` — スクロールバッファ
- `Sources/TeraTermMac/Keyboard/KeyboardHandler.swift` — キー入力処理
- `Sources/TeraTermMac/Keyboard/KeymapLoader.swift` — キーマップ読み込み
- `Sources/TeraTermMac/Encoding/EncodingConverter.swift` — 文字エンコーディング変換

---

## データフローパイプライン

```
受信データ (Data)
  ↓
VTParser (バイト単位ステートマシン)
  ├── 印字文字 → printBuffer に蓄積 → flush → TerminalEmulator.printString()
  ├── CSI シーケンス → TerminalEmulator.handleCSI()
  ├── ESC シーケンス → TerminalEmulator.handleEscape()
  ├── OSC 文字列 → TerminalEmulator.handleOSC()
  └── DCS パススルー → TerminalEmulator.handleDCS()
  ↓
TerminalEmulator (VT100/220/320/420/520 状態管理)
  ↓
TerminalBuffer (セル配列 + スクロールバック)
  ↓
TerminalView (Core Text 描画 → NSView)
```

---

## 1. TerminalView (描画ビュー)

### クラス構成

```swift
class TerminalView: NSView {
    // フォント
    var ctFont, boldFont, italicFont: CTFont?
    var cellWidth: CGFloat = 8.0     // セル幅（ピクセル）
    var cellHeight: CGFloat = 16.0   // セル高さ（ピクセル）
    var fontAscent: CGFloat = 12.0
    var fontDescent: CGFloat = 4.0

    // 画面サイズ
    var columns: Int = 80
    var rows: Int = 24

    // カーソル
    var cursorBlinkTimer: Timer?
    var cursorVisible: Bool

    // 選択
    var startX, startY, endX, endY: Int
    var rectangularSelection: Bool
}

protocol TerminalViewDelegate: AnyObject { ... }
```

### 描画方式

- **Core Text フレームワーク** を使用
  - `CTFont` でフォント管理（通常/太字/斜体の 3 バリアント）
  - `CTLine` ベースのテキスト描画
  - NSView の `draw(_:)` オーバーライドで全画面再描画

### カーソル描画

- タイマーベースのブリンク制御 (`cursorBlinkTimer`)
- カーソル形状: ブロック / 水平バー / 垂直バー（設定で選択可）
- `cursorVisible` フラグのトグルで点滅

### テキスト選択

- マウスドラッグによる範囲選択
- 矩形選択モード対応 (`rectangularSelection`)
- `getSelectedText()` でコピー用テキスト取得

### フォント処理

| 項目 | 実装 |
|------|------|
| フォント生成 | `CTFontCreateWithName` |
| メトリクス | `CTFontGetAscent/Descent` からセルサイズ算出 |
| 太字 | `CTFontCreateCopyWithSymbolicTraits(.bold)` |
| 斜体 | `CTFontCreateCopyWithSymbolicTraits(.italic)` |
| プロポーショナル対応 | `vtFontProportional` 設定で有効化可能 |
| 文字間隔 | `charSpaceH`, `charSpaceV` で調整可能 |

---

## 2. TerminalEmulator (VT エミュレータ)

### 対応ターミナル ID

VT100, VT100J, VT101, VT102, VT102J, VT220, VT220J, VT320, VT382, VT420, VT520, VT525

### 主要構造体

```swift
struct TerminalModes {
    var decckm: Bool      // カーソルキーモード (Application/Normal)
    var decanm: Bool      // ANSI モード
    var deccolm: Bool     // 132/80 カラムモード
    var decsclm: Bool     // スムーズスクロール
    var decscnm: Bool     // スクリーン反転
    var decom: Bool       // Origin モード
    var decawm: Bool      // 自動折り返し
    var decarm: Bool      // Auto Repeat
    var dectcem: Bool     // カーソル表示
    var irm: Bool         // 挿入/置換モード
    var srm: Bool         // 送信制御モード
    var lnm: Bool         // 改行モード
    // ... 40+ フラグ
}

struct CharSetState {
    var g0, g1, g2, g3: CharSet
    var gl, gr: Int       // ロッキングシフト
    var singleShift: Int? // シングルシフト (SS2/SS3)
}

struct CSIParams {
    var params: [Int]
    var subParams: [[Int]]
    var intermediates: [UInt8]
    var privateMarker: UInt8?
}
```

### CSI シーケンスサポート

| カテゴリ | シーケンス |
|---------|-----------|
| カーソル移動 | CUU, CUD, CUF, CUB, CHA, CUP, CNL, CPL, HVP |
| 消去 | ED (0/1/2/3), EL (0/1/2) |
| 挿入/削除 | ICH, IL, DL, DCH |
| スクロール | SU, SD |
| タブ | HT, CHT, CBT, TBC |
| デバイスステータス | DA (Primary/Secondary/Tertiary), DSR |
| スクロール領域 | DECSTBM, DECSLRM |
| カーソルスタイル | DECSCUSR (0-6) |
| マウスモード | X10(9), Normal(1000), Button(1002), Any(1003), Focus(1004), SGR(1006), URXVT(1015), SGR-Pixels(1016) |
| 代替画面 | 47, 1047, 1048, 1049 |

### SGR (文字属性) サポート

| 属性 | SGR コード |
|------|-----------|
| 太字 | 1 |
| 暗い | 2 |
| 斜体 | 3 |
| 下線 | 4 |
| 二重下線 | 4:2 / 21 |
| 波線下線 | 4:3 |
| 点線下線 | 4:4 |
| 破線下線 | 4:5 |
| 点滅 | 5, 6 |
| 反転 | 7 |
| 不可視 | 8 |
| 取消線 | 9 |
| 上線 | 53 |
| 標準色 | 30-37 (前景), 40-47 (背景) |
| 高輝度色 | 90-97 (前景), 100-107 (背景) |
| 256色 | 38;5;n / 48;5;n |
| TrueColor (24bit) | 38;2;r;g;b / 48;2;r;g;b |

### ESC シーケンスサポート

| シーケンス | 機能 |
|-----------|------|
| ESC 7 / ESC 8 | DECSC / DECRC (カーソル保存/復元) |
| ESC D | IND (改行) |
| ESC E | NEL (復帰改行) |
| ESC M | RI (逆改行) |
| ESC H | HTS (タブ設定) |
| ESC ( ) * + <charset> | 文字セット指定 (G0-G3) |
| ESC # 3-6 | 倍幅/倍高 |
| ESC # 8 | 画面アライメントテスト |

### OSC シーケンスサポート

| OSC コマンド | 機能 |
|-------------|------|
| 0, 1, 2 | タイトル変更 |
| 4 | カラーパレット変更 |
| 10, 11, 12 | 前景/背景/カーソル色変更 |
| 52 | クリップボード操作 (base64) |
| 133 | シェル統合 (スタブ) |

### CR/LF 受信モード

| モード | 動作 |
|--------|------|
| 標準 | LF は LF のみ（LNM モードで CR+LF） |
| `lf` | LF → CR+LF |
| `auto_` | CR/LF いずれも CR+LF（CR+LF 重複を除去） |

### マクロ受信バッファ

マクロ実行時の受信データバッファ上限: **1MB** (`1_048_576` bytes)

---

## 3. VTParser (エスケープシーケンスパーサ)

### ステートマシン (ECMA-48 準拠)

```
ground → escape → escapeIntermediate
       → csiEntry → csiParam → csiIntermediate → dispatchCSI
       → dcsEntry → dcsParam → dcsIntermediate → dcsPassthrough
       → oscString → dispatchOSC
       → utf8 (マルチバイトシーケンス)
```

### パーサ状態

```swift
enum ParserState {
    case ground
    case escape, escapeIntermediate
    case csiEntry, csiParam, csiIntermediate
    case dcsEntry, dcsParam, dcsIntermediate, dcsPassthrough
    case oscString
    case utf8
}
```

### 処理モデル

1. **バイト単位ステートマシン** (`processByte`)
   - C0 制御文字 (0x00-0x1F): ほとんどの状態を中断
   - C1 制御文字 (0x80-0x9F): 8bit CSI/DCS/OSC として処理
   - ASCII 印字文字 (0x20-0x7E): printBuffer に蓄積
   - UTF-8 マルチバイト (0x80+): utf8 状態で継続バイト収集

2. **UTF-8 デコード**
   - 先頭バイトからシーケンス長判定
   - 継続バイト (0x80-0xBF) の検証
   - 有効コードポイントを printBuffer に追加

3. **印字バッファ最適化**
   - 連続する印字文字を `printBuffer` (String) に蓄積
   - 制御シーケンス検出時にフラッシュ → デリゲートコールバック削減
   - テキスト主体のストリームで大幅な性能向上

4. **CSI パラメータ解析**
   - 数字蓄積 (0x30-0x39)
   - `;` でパラメータ区切り
   - `:` でサブパラメータ区切り
   - `?`/`<`/`=`/`>` プライベートマーカー
   - 0x20-0x2F 中間バイト

---

## 4. TerminalBuffer (スクロールバッファ)

### データ構造

```swift
struct BufferCharacter {
    var character: Character
    var unicodeScalar: UnicodeScalar
    var combiningCharacters: [UnicodeScalar]  // 結合文字
    var attributes: CharAttributes             // 17 ビットフラグ
    var color: ColorIndex                      // FG/BG + 256/RGB
    var isModified: Bool                       // ダーティフラグ
}

struct BufferLine {
    var cells: [BufferCharacter]    // 幅分の配列
    var isWrapped: Bool             // 折り返し行
    var isModified: Bool            // 行ダーティフラグ
}

struct ColorIndex {
    var foreground, background: UInt8
    var isFgDefault, isBgDefault: Bool
    var isFg256, isBg256: Bool      // xterm 256 色モード
    var isFgRGB, isBgRGB: Bool      // TrueColor (24bit)
    var fgR, fgG, fgB: UInt8       // RGB コンポーネント
    var bgR, bgG, bgB: UInt8
}
```

### 文字属性フラグ (CharAttributes)

bold, dim, italic, underline, blink, reverse, invisible, strikethrough, protected, overline,
doubleUnderline, curlyUnderline, dottedUnderline, dashedUnderline,
wideChar, wideTrail, url (計 17 フラグ)

### バッファ構成

```
lines[0..n-1]: スクロールバック履歴行 (古い順)
lines[n..n+height-1]: 表示領域 (visibleStartLine + 0..height-1)
```

- **プライマリバッファ**: `lines: [BufferLine]`
- **代替バッファ**: `altLines: [BufferLine]?`（代替画面モード用）
- **デフォルトスクロールバックサイズ**: **10,000 行**

### メモリ管理

```swift
func scrollUp(_ n: Int = 1) {
    // 全画面スクロール時
    if scrollTop == 0 && scrollBottom == height - 1 {
        lines.append(BufferLine(width: width))
        let maxLines = height + scrollBufferSize
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
    // 領域スクロール: remove/insert
}
```

### メモリ使用量見積もり

| 構成 | サイズ |
|------|--------|
| デフォルト (80×24 + 10,000行) | 約 24MB |
| 1文字あたり | 約 100 bytes |
| 計算式 | 80 × (24 + 10,000) × 100 bytes |

### カーソル管理

| メソッド | 動作 |
|---------|------|
| `moveCursorTo(x, y)` | 絶対位置指定（マージン考慮） |
| `carriageReturn()` | scrollLeft (マージン有効時) または 0 列目へ |
| `lineFeed()` | 1 行下 or スクロール |
| `reverseLineFeed()` | 1 行上 or 逆スクロール |
| `tab()` | 次のタブストップへ |
| `wrapPending` | 折り返し遅延フラグ（次文字入力まで保留） |

### 文字入力 (putChar)

1. wrapPending があれば折り返し処理
2. 文字幅判定 (CJK 検出)
3. 全角文字: 主セル + trail セル (padding)
4. 前のワイド文字 trail の上書き処理
5. カーソルが右マージン超過時に wrapPending 設定

### 文字幅判定

| Unicode 範囲 | 幅 |
|-------------|-----|
| 制御文字 | 0 |
| CJK 統合漢字 (4E00-9FFF) | 2 |
| ハングル (AC00-D7AF) | 2 |
| 全角形 (FF01-FF60) | 2 |
| ひらがな/カタカナ (3040-30FF) | 2 |
| CJK 互換 (2E80-303E) | 2 |
| 絵文字 (1F300-1FAFF) | 2 |
| その他 | 1 |

### 代替画面バッファ

- 切替時: 表示部分を `altLines` に保存 → 新バッファをクリア
- 復帰時: `altLines` から復元

---

## 5. KeyboardHandler (キー入力処理)

### 入力パイプライン

```
NSEvent (macOS) → TerminalKeyEvent → processKeyEvent() → Data (UTF-8/ESC シーケンス)
```

### 処理優先順位

1. ユーザ定義キー (UDK)
2. 特殊キー（ファンクション、矢印、キーパッド）
3. 修飾キー付き組み合わせ (Ctrl/Alt)
4. 通常文字入力

### 特殊キーマッピング

| macOS キーコード | 機能 |
|----------------|------|
| 0x7E/0x7D/0x7C/0x7B | 上/下/右/左 矢印 |
| 0x73/0x77 | Home/End |
| 0x74/0x79 | Page Up/Down |
| 0x72/0x75 | Insert/Delete |
| 0x33 | Backspace |
| 0x24 | Return |
| 0x35 | Escape |
| 0x7A-0x6F | F1-F12 (F13-F15 含む) |
| 0x52-0x5C, 0x41, 0x43, 0x45, 0x4B, 0x4E, 0x4C | テンキー 0-9, ., *, /, -, +, Enter |

### カーソルキーシーケンス

| モード | 形式 | 例 (上) |
|--------|------|---------|
| Normal | `CSI <key>` | `ESC [ A` |
| Application (DECCKM) | `ESC O <key>` | `ESC O A` |
| 修飾付き | `CSI 1;<mod><key>` | `ESC [ 1;2A` (Shift+上) |

### xterm 修飾エンコーディング

```
mod = 1
+ 1 (Shift)
+ 2 (Alt)
+ 4 (Ctrl)
+ 8 (Meta)
```

### ファンクションキーシーケンス

F1-F12 → コード 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 23, 24
形式: `CSI <code>~` or `CSI <code>;<mod>~`

### テンキー

| モード | 動作 |
|--------|------|
| Numeric (DECKPNM) | 数字文字を直接送信 |
| Application (DECKPAM) | `ESC O p`-`ESC O y` (0-9) |

### Backspace / Return

| キー | 動作 |
|------|------|
| Backspace | 設定で BS(0x08) or DEL(0x7F) 選択 |
| Alt+Backspace | `ESC BS` or `ESC DEL` |
| Return | CR / CRLF / LF / auto（設定依存） |

### マウスイベントエンコーディング

**X11 標準形式:**
```
CSI M <button+mods> <x+33> <y+33>
```

**SGR 拡張形式:**
```
CSI < <button>;<x>;<y>M (press) / m (release)
```

### ブラケットペースト

有効時 (mode 2004): `CSI 200~` + ペーストテキスト + `CSI 201~`

---

## 6. KeymapLoader (キーマップ読み込み)

### ファイル形式

オリジナル Windows TeraTerm の `.cnf` (KEYBOARD.CNF) と互換。

```ini
[VT editor keypad]
Up = 38
Down = 40

[VT function keys]
F6 = 63

[User keys]
User1 = 1, 0, telnet$20host$0D
```

### エンコーディング自動検出

1. BOM 検出 (UTF-8, UTF-16LE/BE)
2. UTF-8 検証
3. Shift_JIS 判定
4. EUC-JP 判定
5. ISO-8859-1 フォールバック

### ユーザキー値デコード

`$HH` 形式の 16 進エスケープを展開:
例: `telnet$20host$0D` → `"telnet host\r"`

---

## 7. EncodingConverter (文字エンコーディング変換)

### サポートエンコーディング (60+)

| カテゴリ | エンコーディング |
|---------|-----------------|
| Unicode | UTF-8, UTF-16 (LE/BE), UTF-32 (LE/BE) |
| 日本語 | Shift_JIS (CP932), EUC-JP, ISO-2022-JP |
| 中国語 | GB2312, GBK, Big5, Big5-HKSCS |
| 韓国語 | EUC-KR |
| 西欧 | ISO-8859-1〜16, CP437, CP1252 |
| その他 | CP1251 (キリル), CP1253 (ギリシャ), CP866, KOI8-R |

### DEC Special Graphics マッピング

ASCII 0x60-0x7E → 罫線文字・記号（┘ ┐ ┌ └ ┼ ─ ├ ┤ ┴ ┬ │ 等）

---

## デバイス属性レスポンス

| 種類 | レスポンス例 |
|------|------------|
| Primary DA | `CSI ? 62;1;2;6;7;8;9 c` (VT220) |
| Secondary DA | `CSI > 1;5700;0 c` (xterm 互換) |
| Tertiary DA | `DCS ! \| <ID> ST` (Tera Term 固有) |
