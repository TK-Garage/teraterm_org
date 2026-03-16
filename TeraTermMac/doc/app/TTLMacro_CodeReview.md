# TTLMacro.app コードレビュー

TTLMacro_SPEC.md と実装コードの照合に基づくコードレビュー結果。
不備(Bug/Risk)・パフォーマンス問題・改善提案を分類して記載する。

---

## 1. クリティカル：クラッシュリスク

### 1.1 Force Unwrap による強制アンラップクラッシュ

**ファイル:** `TTLMacroApp.swift:122, 132`

```swift
// onComplete コールバック内
if !self!.isXPCMode {   // ← self が nil なら即クラッシュ
    NSApp.terminate(nil)
}
```

`onComplete` と `onError` コールバック内で `self!` が使われている。`[weak self]` でキャプチャしているにもかかわらず、`self!` で強制アンラップしているため、AppDelegate が先に解放された場合にクラッシュする。

**修正:** `guard let self = self else { return }` パターンに変更する。

---

### 1.2 exec コマンドによるメインスレッドブロック

**ファイル:** `MacroRunner.swift:3092-3093`

```swift
try process.run()
process.waitUntilExit()  // ← メインスレッドでブロック
```

`cmdExec` は `Process.waitUntilExit()` をメインスレッド(Timer コールバック)上で呼び出している。外部コマンドが長時間実行された場合、RunLoop がブロックされ、UI更新やXPCコールバック処理がすべて停止する。StatusBar のアニメーションも止まる。

**修正:** バックグラウンドキューで実行し、完了後に `scheduleNextLine()` を呼ぶ。

---

## 2. バグ：論理的不備

### 2.1 strspecial のエスケープ処理順序バグ

**ファイル:** `MacroRunner.swift:2127-2131`

```swift
str = str.replacingOccurrences(of: "\\n", with: "\n")   // 1st
str = str.replacingOccurrences(of: "\\r", with: "\r")   // 2nd
str = str.replacingOccurrences(of: "\\t", with: "\t")   // 3rd
str = str.replacingOccurrences(of: "\\\\", with: "\\")  // 4th ← 遅い
```

`\\\\` の変換が最後に実行される。入力文字列 `"\\n"` (バックスラッシュ + n) は、先に `\\n` → `\n`(改行)に変換されてしまう。正しくは `\\` を先に処理するか、1パスで処理する必要がある。

**修正:** `\\\\` の変換を最初に実行する。または1パスの状態機械で処理する。

---

### 2.2 fileseek の SEEK_CUR で負のオフセットが機能しない

**ファイル:** `MacroRunner.swift:2679, 2691`

```swift
let offset = UInt64(resolveInt(args[1]))  // ← 負の値が UInt64 で巨大値に
// ...
case 1: handle.seek(toFileOffset: handle.offsetInFile + offset) // SEEK_CUR
```

`resolveInt` は負の値を返しうるが、`UInt64()` 変換で巨大な正値になる。SEEK_CUR で「現在位置から N バイト戻る」操作が不可能。

**修正:** `Int64` として扱い、SEEK_CUR の場合は加減算する。

---

### 2.3 ラベルとユーザー変数の名前空間衝突

**ファイル:** `MacroRunner.swift:348-358`

```swift
private func prescanLabels() {
    for (idx, line) in scriptLines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(":") {
            let label = ...
            variables[label.lowercased()] = .integer(idx)  // ← 変数辞書に格納
        }
    }
}
```

ラベルが通常の変数と同じ辞書に格納される。ユーザーが `result = 0` のような一般的な名前のラベルを定義した場合、システム変数 `result` が上書きされる。逆にマクロ実行中に `goto` 先のラベルが変数代入で壊される可能性がある。

**修正:** ラベル用の別辞書 `labels: [String: Int]` を設ける。

---

### 2.4 findclose が全検索結果を一括クリア

**ファイル:** `MacroRunner.swift:2895-2898`

```swift
func cmdFindClose() {
    dirSearchResults.removeAll()  // ← 全部消える
    dirSearchIndex.removeAll()
}
```

TeraTerm オリジナルでは `findclose` は特定の検索ハンドルを閉じるが、現実装では全検索結果を破棄する。複数の `findfirst` を並行使用する場合に問題になる。

**修正:** 検索 ID を引数で受け取り、該当エントリのみ削除する。

---

### 2.5 wait コマンドの subscribeToTerminalData コールバック未解除

**ファイル:** `MacroRunner.swift:1597-1631`

`subscribeToTerminalData` はコールバックベースだが、パターンマッチ成功後やタイムアウト後にサブスクリプションを解除する仕組みがない。マッチ成功後もデータが届くたびにコールバックが発火し続ける可能性がある。

**修正:** マッチまたはタイムアウト時にフラグをセットし、コールバック冒頭でチェックする。もしくは unsubscribe メカニズムを MacroClientProtocol に追加する。

---

### 2.6 include 時のエンコーディング固定

**ファイル:** `MacroRunner.swift:1344`

```swift
guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
```

`include` コマンドは UTF-8 固定でファイルを読み込む。しかし TTLMacroShared には `MacroFileLoader` が実装されており、Shift-JIS / EUC-JP 等のレガシーエンコーディングを自動検出する。`run()` メソッド(行 187)も同様に UTF-8 固定。

**修正:** `MacroFileLoader.loadFile(from:)` を使用する。

---

### 2.7 do/loop の無限ループ判定漏れ

**ファイル:** `MacroRunner.swift:1294-1298`

```swift
} else {
    // Infinite loop (loop without condition)
    currentLineNumber = frame.lineIndex
    loopStack.removeLast()
}
```

条件なしの `loop` は `do` 行に戻り `loopStack` から削除する。しかし `do` 行に戻ると再び `cmdDo()` が実行されスタックに push されるため、実質無限ループとなる。これ自体は仕様通りだが、`break` が無い限りスクリプトが終了しない。マクロキャンセル以外の脱出手段が保証されているか要確認。

---

## 3. パフォーマンス問題

### 3.1 syncVariablesToParser / syncVariablesFromParser の O(n) コピー

**ファイル:** `MacroRunner.swift:582-641`

式評価のたびに全変数を MacroRunner → TTLParser にコピーし、評価後に全変数を戻す。変数が数百個になると各式評価に顕著なオーバーヘッドが発生する。

```swift
private func syncVariablesToParser() {
    parser.variables.removeAll()       // ← 全クリア
    parser.initSystemVariables()       // ← 再初期化
    // ...
    for (name, value) in variables {   // ← 全変数ループ
        // ...
    }
}
```

**高速化案:**
- Dirty フラグで変更のあった変数のみ同期する
- TTLParser と MacroRunner で変数ストレージを統合する（二重管理をやめる）
- 式評価時に変数参照をプロキシ経由で遅延解決する

---

### 3.2 filereadln のバイト単位読み込み

**ファイル:** `MacroRunner.swift:2541-2553`

```swift
while true {
    let byte = handle.readData(ofLength: 1)  // ← 1バイトずつ read
    if byte.isEmpty { ... }
    if byte[0] == 0x0A { break }
    if byte[0] != 0x0D { lineData.append(byte) }
}
```

ファイルから 1 バイトずつ読み込んでいる。`FileHandle.readData(ofLength: 1)` は各呼び出しでシステムコールが発生する。大きなファイルの行読み込みでは極端に遅い。

**高速化案:**
- 4KB〜16KB のバッファを使い、改行位置を検索する
- 読み過ぎた分は `seekToFileOffset` で巻き戻す
- あるいは `fgets` 相当のバッファリング層を追加する

---

### 3.3 filestrseek (reverse) の O(n*m) シーク

**ファイル:** `MacroRunner.swift:2770-2781`

```swift
while pos > 0 {
    pos -= 1
    handle.seek(toFileOffset: pos)          // ← 各位置で seek
    let chunk = handle.readData(ofLength: searchData.count)  // ← 各位置で read
    if chunk == searchData { ... }
}
```

逆方向検索で、1バイトずつ位置を戻しながら `seek` + `read` を繰り返す。ファイルが大きく検索文字列がファイル先頭付近にある場合、数百万回のシステムコールが発生する。

**高速化案:**
- 逆方向からチャンク単位(例: 4KB)で読み込み、メモリ上で逆方向検索する
- Boyer-Moore 等のアルゴリズムを使用する

---

### 3.4 Timer ベースの行実行 (0.001秒インターバル)

**ファイル:** `MacroRunner.swift:365`

```swift
execTimer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { [weak self] _ in
    self?.executeNextLine()
}
```

各行の実行間に 1ms の Timer を使用している。Timer の精度は RunLoop 依存で、実際には 1ms 以上の遅延が発生する。ループが 10,000 回繰り返す場合、Timer オーバーヘッドだけで最低 10 秒以上かかる。

**高速化案:**
- 同期コマンド（制御フロー、文字列操作、ファイルI/O等）は Timer を経由せず直接次の行を実行する
- `DispatchQueue.main.async` に置き換える（Timer より軽量）
- バッチ実行：非同期コマンドに到達するまで連続実行する

---

### 3.5 expandenv の全環境変数ループ

**ファイル:** `MacroRunner.swift:3073-3075`

```swift
let env = ProcessInfo.processInfo.environment
for (key, value) in env {
    str = str.replacingOccurrences(of: "%\(key)%", with: value)
}
```

環境変数は数十〜数百個あり、各変数に対して `replacingOccurrences` (O(n) 文字列走査) を実行する。

**高速化案:** 文字列中の `%...%` パターンを正規表現で検出し、見つかった変数名のみ置換する。

---

### 3.6 CRC 計算にルックアップテーブル未使用

**ファイル:** `MacroRunner.swift:3644-3670`

CRC16/CRC32 がビット単位のループで計算されている。256 エントリのルックアップテーブルを使えば、バイト単位で計算でき約 8 倍高速化される。

---

## 4. スレッドセーフティ

### 4.1 MacroRunner の状態保護なし

`MacroRunner` のプロパティ (`isRunning`, `isPaused`, `isCancelled`, `variables`, `currentLineNumber` 等) は、メインスレッドの Timer コールバックと XPC reply コールバック（不定スレッド）の両方からアクセスされるが、ロックや同期機構がない。

XPC reply は `DispatchQueue.main` で返される保証がないため、以下のようなレース条件が発生しうる：

- `cmdRecv` の reply が `variables["inputstr"]` を書き込む最中に、次のコマンドが `variables` を読む
- `isCancelled` が他スレッドから `true` にセットされても、Timer コールバック側で即座に反映されない

**修正案:**
- XPC reply をすべて `DispatchQueue.main.async` でラップする（現状一部はされているが不統一）
- あるいは `@MainActor` を使用する（Swift Concurrency 導入時）

---

## 5. スペックとの差異

### 5.1 recv コマンドの引数不一致

**スペック:** `recv` は引数を取らない（タイムアウトは `settimeout` で設定）
**実装:** `cmdRecv(_ args: [String])` は args を受け取るが使用していない（正しい動作だが、引数が渡された場合に警告を出すべき）

### 5.2 str2code / code2str の引数順序

**スペック:** `str2code <string> <intvar>` / `code2str <intcode> <strvar>`
**実装:** `cmdStr2Code` は `args[0]` を dest、`args[1]` を source として使用 → スペックと逆

```swift
func cmdStr2Code(_ args: [String]) {
    let destVar = args[0].lowercased()    // ← スペックでは string が先
    let str = resolveString(args[1])      // ← スペックでは intvar が後
}
```

**修正:** スペックに合わせるか、スペックを実装に合わせて更新する。

### 5.3 strsplit の結果格納先

**スペック:** `result`: element count; `groupmatchstr1..N`: elements
**実装:** 結果を `strArray` として指定変数に格納。`groupmatchstr` は未設定。

```swift
func cmdStrSplit(_ args: [String]) {
    let parts = srcStr.components(separatedBy: delimiter)
    variables[destVar] = .strArray(parts)     // ← strArray に格納
    resultValue = parts.count
    // groupmatchstr は未設定  ← スペック違反
}
```

### 5.4 strreplace が正規表現ではなく単純置換

**スペック:** "Regex replace"
**実装:** `replacingOccurrences(of:with:)` による単純文字列置換

### 5.5 sendln の改行コード

**スペック:** `Send string + CR to terminal`
**実装:** `text += "\r\n"` (CR+LF)

TeraTerm オリジナルでは `sendln` は CR のみ送信する。CR+LF だと余分な LF が送られる。

### 5.6 strmatch の result 値

**スペック:** `result: match position (1-based), 0=no match`
**実装:** `resultValue = 1` (マッチ有無のみ、位置ではない)

---

## 6. セキュリティ

### 6.1 getpassword で変数にパスワードが平文保存される

**ファイル:** `MacroRunner.swift:3823`

```swift
variables[varName] = .string(password)  // ← Swift String としてヒープに残る
```

パスワードは `TTLKeychainManager.zeroData` で Data を消去しているが、`variables` 辞書内の `String` はゼロ化されない。Swift の `String` は CoW (Copy-on-Write) でメモリ管理されるため、明示的なゼロ化が困難。

**緩和策:** パスワード変数には専用の `TTLValue.secureString` ケースを追加し、使用後に可能な限りメモリをクリアする。

### 6.2 XPC エンドポイントファイルの競合状態

**ファイル:** `XPCServiceHandler.swift:58-72`

エンドポイントを `/tmp/ttlmacro_endpoint_<pid>.dat` に NSKeyedArchiver で書き出す。他プロセスが同じファイルを読み書きするレースウィンドウが存在する。ファイルのパーミッションも明示設定されていない。

**修正:** ファイル作成時に `0600` パーミッションを設定する。あるいは `NSXPCListener.endpoint` を直接渡す仕組み（Mach port 等）に変更する。

---

## 7. 改善提案（低優先度）

| # | 項目 | 説明 |
|---|------|------|
| 7.1 | DateFormatter のキャッシュ | `cmdGetDate`/`cmdGetTime` で毎回 `DateFormatter` を生成している。プロパティとしてキャッシュすべき。 |
| 7.2 | parseLine の文字列走査 | `String.Index` ベースの走査は O(n) だが、UTF-8 の場合 `[UInt8]` ベースの方が高速。 |
| 7.3 | rotateLeft/rotateRight の 64bit 問題 | `Int` は macOS で 64bit だが、シフト量は 32bit 前提 `(32 - bits)`。`MemoryLayout<Int>.size * 8` を使うべき。 |
| 7.4 | sendln の CR のみ送信オプション | スペック通り CR のみにするか、設定で CR/CRLF を切り替え可能にする。 |
| 7.5 | fileopen の maxFileHandles 未チェック | `maxFileHandles = 16` が定義されているが、`cmdFileOpen` でチェックされていない。 |
| 7.6 | エラーメッセージの国際化 | `reportError` のメッセージが英語ハードコードされている。`L()` ローカライゼーション関数を使うべき。 |
| 7.7 | sprintf の書式指定子が不完全 | `%o`(8進数）、`%c`（文字）、幅指定（`%10s`, `%-20d`）が未実装。 |

---

## 8. サマリー

| 分類 | 件数 | 重要度 |
|------|------|--------|
| クラッシュリスク | 2 | Critical |
| 論理バグ | 7 | High |
| パフォーマンス | 6 | Medium |
| スレッドセーフティ | 1 | High |
| スペック差異 | 6 | Medium |
| セキュリティ | 2 | Medium |
| 改善提案 | 7 | Low |
| **合計** | **31** | |

### 優先対応推奨

1. **1.1** Force unwrap クラッシュ修正（即時）
2. **1.2** exec のメインスレッドブロック修正
3. **2.1** strspecial エスケープ順序修正
4. **2.5** wait コマンドのサブスクリプション解除
5. **3.4** Timer ベース実行の高速化（バッチ実行化）
6. **2.2** fileseek の負オフセット対応
7. **2.6** include のエンコーディング自動検出
