# TeraTerm Mac.app - パフォーマンス改善提案

## 対象課題

1. **表示の高速化** — 大量データ受信時の描画遅延
2. **キー入力の高速化** — 高速タイピング時の応答性
3. **スクロールバッファの大容量化** — 10,000 行超のバッファ拡張

---

## 1. 表示の高速化

### 1.1 現状の課題

#### 描画パイプラインのボトルネック

```
受信データ → VTParser → TerminalEmulator → TerminalBuffer → TerminalView.draw()
                                                              ↑ 全画面再描画
```

- `TerminalView.draw(_:)` で **毎回全画面を再描画** している
- `BufferLine.isModified` / `BufferCharacter.isModified` のダーティフラグは存在するが、
  描画時に **行単位のスキップが十分に活用されていない**
- 大量データ受信時（`cat large_file`、`make` 出力等）に描画が追いつかない

#### Core Text 呼び出しコスト

- 文字ごとに `CTLine` を生成するオーバーヘッド
- フォントメトリクスの繰り返し計算
- 属性変更のたびに `NSAttributedString` 再生成

### 1.2 改善案

#### A. ダーティ領域描画 (Dirty Region Rendering)

**概要**: 変更のあった行のみ再描画する。

```swift
// 改善案: draw() 内で変更行のみ描画
override func draw(_ dirtyRect: NSRect) {
    let startRow = Int(dirtyRect.origin.y / cellHeight)
    let endRow = min(startRow + Int(dirtyRect.height / cellHeight) + 1, rows)

    for row in startRow..<endRow {
        let line = buffer.getLine(row)
        if line.isModified || forceFullRedraw {
            drawLine(row, line)
            line.isModified = false
        }
    }
}
```

**効果**: カーソル移動やプロンプト表示など部分的な変更で描画コスト大幅削減。

**ケアすべき点**:
- スクロール時は全行が「変更あり」となるため、スクロール専用パスが必要
- 選択範囲の変更も差分描画に対応させる必要がある
- `setNeedsDisplay(_ rect:)` で無効化矩形を限定する

#### B. グリフキャッシュ (Glyph Cache)

**概要**: 頻出文字の `CTLine` オブジェクトをキャッシュする。

```swift
class GlyphCache {
    // key: (character, attributes_hash) → value: CTLine
    private var cache: [GlyphKey: CTLine] = [:]
    private let maxEntries = 4096

    func getOrCreate(char: Character, attrs: CharAttributes,
                     color: ColorIndex, font: CTFont) -> CTLine {
        let key = GlyphKey(char: char, attrs: attrs, color: color)
        if let cached = cache[key] { return cached }
        let line = createCTLine(char: char, attrs: attrs, color: color, font: font)
        cache[key] = line
        return line
    }
}
```

**効果**: 同じ文字・属性の組み合わせで CTLine 生成を省略。ASCII テキストでは 90%+ のキャッシュヒット率が期待できる。

**ケアすべき点**:
- キャッシュサイズの上限管理（LRU 方式推奨）
- フォント変更時のキャッシュ全クリア
- TrueColor (24bit RGB) 使用時はキャッシュキーの爆発に注意
  → 色情報を量子化（上位 4-6 bit のみ使用）するか、色はキャッシュキーに含めない

#### C. 描画バッチング (Draw Coalescing)

**概要**: 高速データ受信時に描画リクエストを間引く。

```swift
class DrawCoalescer {
    private var pendingRedraw = false
    private let minInterval: TimeInterval = 1.0 / 60.0  // 60fps 上限

    func requestRedraw(view: TerminalView) {
        guard !pendingRedraw else { return }
        pendingRedraw = true

        DispatchQueue.main.asyncAfter(deadline: .now() + minInterval) {
            self.pendingRedraw = false
            view.setNeedsDisplay(view.bounds)
        }
    }
}
```

**効果**: `cat /dev/urandom | xxd` のような連続データでも 60fps を超えない。
CPU 使用率を大幅に削減。

**ケアすべき点**:
- 最小間隔が長すぎるとカーソル移動の応答性が悪化する
- 対話的操作（1文字入力→エコー）では即時描画が望ましい
  → 「前回描画から N ms 以内なら遅延、それ以外は即時」のハイブリッド方式

#### D. Metal / CALayer ベース描画

**概要**: Core Text + CGContext から Metal / Core Animation に移行。

```
テキストテクスチャアトラス → Metal テクスチャ → GPU 描画
```

**効果**: GPU アクセラレーションにより描画性能が桁違いに向上。
iTerm2、Alacritty、WezTerm 等の高性能端末で実績あり。

**ケアすべき点**:
- 実装コストが非常に大きい（全描画コードの書き直し）
- CJK 文字のテクスチャアトラス管理が複雑
- Retina 対応でテクスチャサイズが倍になる
- 初期段階では **C, D を先に実施** し、Metal は中長期課題とする

---

## 2. キー入力の高速化

### 2.1 現状の課題

```
NSEvent (メインスレッド) → processKeyEvent() → send() → writeQueue
                           ↑ メインスレッドで処理
```

- キー入力処理が **メインスレッドで同期実行** されている
- `processKeyEvent()` 内でキーマップ検索、修飾キー判定、エスケープシーケンス生成を行う
- 高速タイピング時にメインスレッドの描画処理とキー処理が競合

### 2.2 改善案

#### A. キー処理の軽量化

**概要**: ホットパス（通常文字入力）を最短経路にする。

```swift
func processKeyEvent(_ event: TerminalKeyEvent) -> Data? {
    // Fast path: 修飾キーなし + 通常 ASCII 文字
    if event.modifiers.isEmpty,
       let char = event.characters.first,
       char.asciiValue != nil,
       userDefinedKeys.isEmpty {
        return Data(event.characters.utf8)
    }
    // Slow path: 特殊キー / 修飾キー / UDK
    return processSpecialKey(event)
}
```

**効果**: 通常テキスト入力の処理を O(1) に短縮。

**ケアすべき点**:
- UDK (ユーザ定義キー) が設定されている場合はスキップ不可
- Ctrl+C 等の制御文字は fast path で処理できない

#### B. キーマップのルックアップテーブル化

**概要**: キーマップ検索を辞書ルックアップに最適化する。

```swift
// 現状: 線形検索
for entry in userKeys {
    if entry.pcKeyCode == keyCode && entry.controlFlag == flags { ... }
}

// 改善: ハッシュマップ
let lookupKey = (keyCode << 8) | flags
if let entry = userKeyMap[lookupKey] { ... }
```

**効果**: UDK が多数定義されている場合の検索を O(n) → O(1) に。

#### C. 入力バッファリング

**概要**: 高速タイピング時にキー入力をバッファリングし、一括送信する。

```swift
class KeyInputBuffer {
    private var buffer = Data()
    private var flushTimer: DispatchSourceTimer?
    private let flushInterval: TimeInterval = 0.002  // 2ms

    func append(_ data: Data) {
        buffer.append(data)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTimer == nil else { return }
        flushTimer = DispatchSource.makeTimerSource(queue: .main)
        flushTimer?.schedule(deadline: .now() + flushInterval)
        flushTimer?.setEventHandler { [weak self] in
            self?.flush()
        }
        flushTimer?.resume()
    }

    private func flush() {
        let data = buffer
        buffer = Data()
        flushTimer = nil
        connection.send(data)
    }
}
```

**効果**: ネットワーク送信の syscall 回数を削減。SSH 経由での高速入力で特に効果的。

**ケアすべき点**:
- フラッシュ間隔が長すぎると入力遅延を感じる（2ms 以下推奨）
- 制御文字（Ctrl+C 等）は即時送信が必須 → バッファバイパス
- ローカルエコー有効時はエコー表示もバッファリングに合わせる

---

## 3. スクロールバッファの大容量化

### 3.1 現状の課題

#### メモリ使用量

```
1 文字あたり: ~100 bytes (BufferCharacter 構造体)
  - Character: 16 bytes
  - UnicodeScalar: 8 bytes
  - combiningCharacters: [UnicodeScalar] (空配列でも 24 bytes)
  - CharAttributes: 8 bytes
  - ColorIndex: 24 bytes
  - isModified: 1 byte + パディング
  - その他

80カラム × 10,000行 = 800,000 文字 → 約 80MB
80カラム × 100,000行 = 8,000,000 文字 → 約 800MB
80カラム × 1,000,000行 = 80,000,000 文字 → 約 8GB (非現実的)
```

#### Array<BufferLine> の問題

- `lines.removeFirst()` は **O(n)** コスト（全要素のシフト）
- 大容量バッファでスクロール時に顕著な遅延
- Swift Array は連続メモリを要求するため、大量確保時にメモリフラグメンテーション発生

### 3.2 改善案

#### A. BufferCharacter の構造体サイズ削減

**概要**: 1 文字あたりのメモリ使用量を削減する。

```swift
// 現状: ~100 bytes/char
struct BufferCharacter {
    var character: Character          // 16 bytes
    var unicodeScalar: UnicodeScalar  // 8 bytes
    var combiningCharacters: [UnicodeScalar]  // 24+ bytes
    var attributes: CharAttributes    // 8 bytes
    var color: ColorIndex             // 24 bytes
    var isModified: Bool              // 1 byte + padding
}

// 改善案: ~32 bytes/char
struct CompactBufferCharacter {
    var codepoint: UInt32             // 4 bytes (BMP + SMP カバー)
    var attributes: UInt32            // 4 bytes (17 flags + 余裕)
    var fgColor: UInt32               // 4 bytes (packed ARGB or index)
    var bgColor: UInt32               // 4 bytes (packed ARGB or index)
    var combining: UInt16             // 2 bytes (結合文字テーブルへのインデックス, 0=なし)
    var flags: UInt16                 // 2 bytes (isModified, isWide, etc.)
}
// = 20 bytes + パディング → 24 bytes

// 結合文字テーブル (大半のセルは結合文字なし)
class CombiningCharacterTable {
    var entries: [[UnicodeScalar]] = []  // index → 結合文字配列
}
```

**効果**: 1 文字あたり 100 → 24 bytes (76% 削減)。
80カラム × 100,000 行 = 約 192MB (現実的なサイズ)。

**ケアすべき点**:
- `Character` 型の柔軟性を失う（grapheme cluster の直接保持ができなくなる）
- 結合文字テーブルの管理コスト
- 既存コードの大幅な書き換えが必要

#### B. リングバッファの導入

**概要**: `Array<BufferLine>` を固定サイズリングバッファに変更する。

```swift
class RingBuffer<T> {
    private var storage: [T]
    private var head: Int = 0  // 最も古い要素のインデックス
    private var count: Int = 0
    let capacity: Int

    func append(_ element: T) {
        if count < capacity {
            storage.append(element)
            count += 1
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    subscript(index: Int) -> T {
        get { storage[(head + index) % capacity] }
        set { storage[(head + index) % capacity] = newValue }
    }
}
```

**効果**:
- `removeFirst()` の O(n) → O(1)
- メモリの事前確保で断片化を防止
- オリジナル Windows 版 (`buffer.c`) と同等のリングバッファ方式

**ケアすべき点**:
- 容量を事前に決定する必要がある（動的拡張は別途対応）
- リングバッファの折り返し境界をまたぐ選択/コピーの処理
- 全行の再配置が不要になる代わりに、インデックス計算が複雑化

#### C. ページング方式 (仮想メモリ活用)

**概要**: バッファを固定サイズのページに分割し、古いページをディスクにスワップする。

```swift
class PagedBuffer {
    static let pageSize = 1000  // 1ページ = 1000行

    struct Page {
        var lines: [BufferLine]
        var isDirty: Bool = false
        var isInMemory: Bool = true
    }

    private var pages: [Page] = []
    private var memoryPageLimit = 50  // メモリ上に保持する最大ページ数
    private let cacheDir: URL        // ディスクキャッシュディレクトリ

    func getLine(absoluteIndex: Int) -> BufferLine {
        let pageIndex = absoluteIndex / Self.pageSize
        let lineIndex = absoluteIndex % Self.pageSize

        if !pages[pageIndex].isInMemory {
            loadPage(pageIndex)
        }
        return pages[pageIndex].lines[lineIndex]
    }

    private func loadPage(_ index: Int) {
        // LRU でメモリページ数を制限
        if inMemoryCount >= memoryPageLimit {
            evictOldestPage()
        }
        pages[index].lines = readFromDisk(index)
        pages[index].isInMemory = true
    }
}
```

**効果**:
- 理論上無制限のスクロールバッファ
- メモリ使用量を一定に抑制（50ページ × 1000行 × 80カラム × 24bytes ≈ 96MB）
- 100 万行以上のバッファも実現可能

**ケアすべき点**:
- ディスク I/O によるスクロール遅延（SSD 前提でも 1ms 程度）
- ページ境界をまたぐテキスト選択の処理
- ディスクキャッシュのクリーンアップ（アプリ終了時）
- 検索（Ctrl+F 相当）がページをまたぐ場合の実装
- 初期段階では **A + B を先に実装** し、ページングは 100 万行以上が必要な場合のみ

#### D. 行圧縮 (Line Compression)

**概要**: スクロールバック内の古い行を圧縮して保持する。

```swift
struct CompressedLine {
    // 全セルが同じ属性の場合、属性を 1 つだけ保持
    var uniformAttributes: CompactAttributes?
    // テキスト内容のみ UTF-8 で圧縮保持
    var compressedText: Data  // zlib 圧縮 or RLE
    var originalWidth: Int
}
```

**効果**: 空行やプロンプト行など、繰り返しパターンの多い行で 90%+ の圧縮率。

**ケアすべき点**:
- 圧縮/展開の CPU コスト（スクロールバック閲覧時）
- 属性情報の復元精度
- 実装複雑度が高い

---

## 4. 実装優先度

### Phase 1: 即効性の高い改善 (1-2 週間)

| 改善 | 対象 | 効果 | 工数 |
|------|------|------|------|
| 描画バッチング (1.2.C) | 表示 | 高速データ受信時の CPU 削減 | 小 |
| キー処理 fast path (2.2.A) | 入力 | 通常入力の応答性向上 | 小 |
| キーマップ ハッシュ化 (2.2.B) | 入力 | UDK 検索の高速化 | 小 |

### Phase 2: 構造的改善 (2-4 週間)

| 改善 | 対象 | 効果 | 工数 |
|------|------|------|------|
| ダーティ領域描画 (1.2.A) | 表示 | 部分更新での描画負荷 80%+ 削減 | 中 |
| グリフキャッシュ (1.2.B) | 表示 | Core Text 呼び出し 90%+ 削減 | 中 |
| 入力バッファリング (2.2.C) | 入力 | ネットワーク送信効率化 | 小 |
| リングバッファ (3.2.B) | バッファ | スクロール O(n) → O(1) | 中 |

### Phase 3: 大規模改善 (1-2 ヶ月)

| 改善 | 対象 | 効果 | 工数 |
|------|------|------|------|
| BufferCharacter 圧縮 (3.2.A) | バッファ | メモリ 76% 削減 | 大 |
| ページングバッファ (3.2.C) | バッファ | 100万行以上対応 | 大 |
| Metal 描画 (1.2.D) | 表示 | GPU アクセラレーション | 特大 |

---

## 5. 計測とベンチマーク

改善の効果を検証するため、以下のベンチマークを実施する。

### テストシナリオ

| テスト | コマンド | 計測項目 |
|--------|---------|---------|
| 大量テキスト表示 | `cat large_file` (10MB) | 完了時間, CPU 使用率 |
| 連続出力 | `yes \| head -100000` | フレームレート, CPU |
| 高速入力 | 100 文字/秒の自動タイピング | 入力遅延 (ms) |
| スクロールバック | 100,000 行蓄積後のスクロール | スクロール応答時間 |
| メモリ使用量 | 各バッファサイズでの RSS | メモリ (MB) |

### 計測方法

```swift
// パフォーマンス計測ユーティリティ
class PerformanceCounter {
    static func measure(_ label: String, block: () -> Void) {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        TTLog.perf.info("\(label): \(elapsed * 1000, format: .fixed(precision: 2))ms")
    }
}
```

### 目標値

| 項目 | 現状推定 | 目標 |
|------|---------|------|
| 10MB ファイル表示 | 5-10 秒 | < 2 秒 |
| フレームレート (連続出力時) | 可変 (60fps 超過) | 安定 60fps |
| キー入力遅延 | 5-15 ms | < 3 ms |
| スクロール応答 (10万行) | 100-500 ms | < 16 ms (1 frame) |
| メモリ (10万行) | ~800 MB | < 200 MB |
