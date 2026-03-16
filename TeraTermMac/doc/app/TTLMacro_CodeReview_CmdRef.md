# TTLMacro.app コードレビュー（TTLCommandReference.md 基準）

TTLCommandReference.md のコマンド仕様と MacroRunner.swift 実装の照合結果。
コマンドの引数順序・戻り値・動作仕様の不一致、バグ、パフォーマンス問題を分類して記載する。

---

## 1. クリティカル：引数順序・セマンティクスの不一致

### 1.1 sprintf / sprintf2 の入出力先が逆

**リファレンス:**
- `sprintf` → 結果を `inputstr` に格納
- `sprintf2` → 結果を指定変数に格納

**実装 (MacroRunner.swift:2203-2272):**
```swift
func cmdSprintf(_ args: [String], mode: Int) {
    // ...
    if mode == 0 {
        variables[destVar] = .string(result)   // sprintf → 変数に格納
    } else {
        inputStr = result
        variables["inputstr"] = .string(result) // sprintf2 → inputstr に格納
    }
}
```

`sprintf` が変数に、`sprintf2` が `inputstr` に格納しており、リファレンスと**完全に逆**。
既存マクロスクリプトで `sprintf` 後に `inputstr` を参照するパターンが多く、互換性に重大な影響がある。

---

### 1.2 fileopen の引数セマンティクスが異なる

**リファレンス:**
```
fileopen <handlevar> <filename> <append> [<readonly>]
  append: 0=新規/上書き, 1=追記
  readonly: 1=読み取り専用
```

**実装 (MacroRunner.swift:2434-2470):**
```swift
// 第3引数を mode として扱う
let mode = resolveInt(args[2])
switch mode {
case 0: // read
case 1: // write (create/truncate)
case 2: // read+write
case 3: // append
}
```

リファレンスでは第3引数は `append` フラグ (0/1)、第4引数が `readonly` フラグだが、
実装では第3引数を独自の `mode` 値 (0-3) として解釈している。

**影響:** `fileopen fh 'file.txt' 0` — リファレンスでは「新規/上書き」、実装では「読み取り」。完全に異なる動作。

---

### 1.3 filesearch の動作が根本的に異なる

**リファレンス:**
```
filesearch '/tmp/data.txt' 'pattern'
```
ファイル**内**の文字列を検索する。

**実装 (MacroRunner.swift:2667-2672):**
```swift
func cmdFileSearch(_ args: [String]) {
    let filePath = resolveString(args[0])
    resultValue = FileManager.default.fileExists(atPath: filePath) ? 1 : 0
}
```

ファイルの**存在確認**のみ行い、ファイル内の文字列検索を行わない。

---

### 1.4 str2int の引数順序が逆

**リファレンス:** `str2int '42' val` （文字列が先、変数が後）

**実装 (MacroRunner.swift:2032-2039):**
```swift
func cmdStr2Int(_ args: [String]) {
    let destVar = args[0].lowercased()  // ← 変数が先
    let str = resolveString(args[1])     // ← 文字列が後
}
```

---

### 1.5 str2code の引数順序が逆

**リファレンス:** `str2code 'A' code` （文字列が先、変数が後）

**実装 (MacroRunner.swift:2053-2058):**
```swift
func cmdStr2Code(_ args: [String]) {
    let destVar = args[0].lowercased()  // ← 変数が先
    let str = resolveString(args[1])     // ← 文字列が後
}
```

---

### 1.6 code2str の引数順序が逆

**リファレンス:** `code2str 65 ch` （コードが先、変数が後）

**実装 (MacroRunner.swift:2063-2071):**
```swift
func cmdCode2Str(_ args: [String]) {
    let destVar = args[0].lowercased()  // ← 変数が先
    let code = resolveInt(args[1])       // ← コードが後
}
```

---

### 1.7 filestat の引数順序が逆

**リファレンス:** `filestat '/tmp/data.txt' size` （パスが先、変数が後）

**実装 (MacroRunner.swift:2727-2741):**
```swift
func cmdFileStat(_ args: [String]) {
    let destVar = args[0].lowercased()   // ← 変数が先
    let filePath = resolveString(args[1]) // ← パスが後
}
```

---

### 1.8 getspecialfolder のフォルダ番号が不一致

**リファレンス:**
| 番号 | パス |
|------|------|
| 0 | デスクトップ |
| 1 | Application Support |
| 2 | Documents |
| 3 | Downloads |

**実装 (MacroRunner.swift:3230-3245):**
| 番号 | パス |
|------|------|
| 0 | デスクトップ |
| 1 | Documents |
| 2 | Application Support |
| 3 | Home |
| 4 | Temp |
| 5 | Downloads |

番号 1 と 2 が入れ替わっている。番号 3 がリファレンスでは Downloads だが実装では Home。

---

### 1.9 getver の戻り値形式が異なる

**リファレンス:** `major*10000 + minor*100 + patch` （例: 5.0.0 → 50000）

**実装 (MacroRunner.swift:3186-3189):**
```swift
let parts = version.split(separator: ".")
let major = Int(parts.first ?? "0") ?? 0
self.resultValue = major  // ← major のみ返す
```

バージョン文字列から major 部分のみ抽出。`minor*100 + patch` の計算がない。

---

## 2. 仕様不一致：戻り値・動作差異

### 2.1 strmatch の result が位置ではなくフラグ

**リファレンス:** `result`: マッチ位置（1起算）、0=マッチなし

**実装 (MacroRunner.swift:2011):**
```swift
resultValue = 1  // ← 位置ではなく、マッチ有無の 0/1 フラグ
```

---

### 2.2 strsplit が groupmatchstr に結果を格納しない

**リファレンス:** `result = 4; groupmatchstr1='a', groupmatchstr2='b', ...`

**実装 (MacroRunner.swift:2157-2165):**
```swift
func cmdStrSplit(_ args: [String]) {
    let parts = srcStr.components(separatedBy: delimiter)
    variables[destVar] = .strArray(parts)  // ← strArray に格納
    resultValue = parts.count
    // groupmatchstr1..N は未設定
}
```

---

### 2.3 strjoin の引数形式が異なる

**リファレンス:** `strjoin buf ',' 'apple' 'banana' 'cherry'` （可変長リテラル引数）

**実装 (MacroRunner.swift:2170-2181):**
```swift
func cmdStrJoin(_ args: [String]) {
    let destVar = args[0].lowercased()
    let srcVar = args[1].lowercased()      // ← 配列変数名を受け取る
    let delimiter = resolveString(args[2])  // ← デリミタは第3引数
}
```

リファレンスでは可変長のリテラル文字列を連結するが、実装では配列変数を連結する。

---

### 2.4 strreplace が正規表現ではなく単純文字列置換

**リファレンス:** `正規表現で置換`

**実装 (MacroRunner.swift:2114):**
```swift
base = base.replacingOccurrences(of: target, with: replacement)
```

`NSRegularExpression` を使わず、`String.replacingOccurrences` による単純置換。

---

### 2.5 strtrim の第2引数が文字列ではなく整数

**リファレンス:**
```
strtrim s ' ' 1    ; 第2引数: 除去する文字（文字列）
                     ; 第3引数: trimtype (0/1/2)
```

**実装 (MacroRunner.swift:2138-2153):**
```swift
func cmdStrTrim(_ args: [String]) {
    let trimType = args.count > 1 ? resolveInt(args[1]) : 0  // ← 第2引数を trimType として使用
}
```

除去文字の指定が無視され、第2引数が直接 trimType として使われている。
`strtrim s ' ' 1` → 空白文字ではなく `' '` を Int 変換して 0（両端トリム）。

---

### 2.6 sendln が CR+LF を送信（リファレンスは CR のみ）

**リファレンス:** `文字列 + CR を送信`

**実装 (MacroRunner.swift:1395):**
```swift
if addCR { text += "\r\n" }  // ← CR+LF
```

---

### 2.7 sendbinary が16進文字列ではなく整数引数

**リファレンス:** `sendbinary '48656C6C6F'` （16進文字列）

**実装 (MacroRunner.swift:1418-1424):**
```swift
func cmdSendBinary(_ args: [String]) {
    var bytes: [UInt8] = []
    for arg in args {
        let val = resolveInt(arg)         // ← 各引数を整数として解釈
        bytes.append(UInt8(val & 0xFF))
    }
}
```

16進文字列のパースがなく、各引数を個別の整数値として処理している。

---

### 2.8 send の `#13` 文字コード構文が未実装

**リファレンス:** `send 'ATZ' #13` （`#13` = CR）

**実装:** `resolveValue` で `#` プレフィックスの処理がない。`$XX` (16進) と `0xXX` は対応しているが、`#XX` (10進文字コード) は未対応。

---

### 2.9 setdate / settime が result を設定しない

**リファレンス:** `result = -1 (macOS では常に失敗)`

**実装 (MacroRunner.swift:3341-3354):**
```swift
func cmdSetDate(_ args: [String]) {
    if !args.isEmpty {
        variables["_setdate"] = .string(resolveString(args[0]))
    }
    // ← result 未設定
}
```

---

### 2.10 ifdefined が result を設定しない

**リファレンス:** `result: 1 = 存在する、0 = 存在しない`

**実装 (MacroRunner.swift:1360-1370):**
```swift
func cmdIfDefined(_ args: [String]) {
    ifNest += 1
    if variables[varName] == nil {
        elseFlag = 1
    }
    // ← result 未設定（ブロック if として動作）
}
```

リファレンスでは `result` に存在フラグを設定し、後続の `if result` で参照する形式。
実装では `ifdefined` 自体が if ブロックを開始するため、仕様が異なる。

---

### 2.11 foldersearch がパターン検索ではなくディレクトリ存在確認

**リファレンス:** `foldersearch dirname '/tmp/test*'` — パターンでフォルダ検索

**実装 (MacroRunner.swift:2931-2937):**
```swift
func cmdFolderSearch(_ args: [String]) {
    let path = resolveString(args[0])
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    resultValue = (exists && isDir.boolValue) ? 1 : 0
}
```

ワイルドカードパターン検索ではなく、単一パスのディレクトリ存在確認のみ。

---

### 2.12 recvfile の動作が仕様と大きく異なる

**リファレンス:**
```
recvfile filename binary_flag autostop_seconds
; 接続から受信したデータを直接ファイルに保存、autostop で自動停止
```

**実装 (MacroRunner.swift:4152-4156):**
```swift
func cmdRecvFile(_ args: [String]) {
    let localDir = args.isEmpty ? "" : resolveString(args[0])
    cmdFileTransferRecv([localDir], proto: "zmodem")  // ← ZMODEM に委譲
}
```

リファレンスでは受信データを直接ファイルに書き込む（プロトコルなし）だが、
実装は ZMODEM ファイル転送に丸投げしている。

---

### 2.13 logrotate / logautoclosemode のコマンド名・引数

**リファレンス:** `logrotate` — 引数なし / `logautoclosemode 1`

**実装:**
- `logrotate` — 2引数 (mode, value) を要求
- コマンド名 `logautoclose` で登録（`logautoclosemode` ではない）

---

## 3. 未実装のシステム変数

### 3.1 mtimeout 未実装

**リファレンス:** `mtimeout` — タイムアウトの追加ミリ秒部分

**実装:** `timeout` のみ使用。wait 系コマンドで `mtimeout` を加算する処理がない。

---

### 3.2 paramcnt / param1〜param9 未実装

**リファレンス:** マクロ起動時の引数を `param1`〜`param9` に格納、`paramcnt` に個数

**実装:** `resetState()` でこれらの変数を初期化していない。コマンドライン引数の解析もなし。

---

## 4. パフォーマンス問題

### 4.1 Timer ベースの行実行（1ms インターバル）

**ファイル:** `MacroRunner.swift:365`

```swift
execTimer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { ... }
```

各行の実行間に 1ms Timer を挟む。Timer の最小解像度は RunLoop 依存で通常 1〜5ms。
10,000 行のループで最低 10〜50 秒のオーバーヘッドが発生する。

**高速化案:**
- 同期コマンド（制御フロー、文字列操作、ファイルI/O等）はタイマーを経由せず直接ループ実行
- 非同期コマンド到達時のみ RunLoop に戻す
- バッチ実行上限（例: 1000行/回）を設け、UI レスポンスを維持

---

### 4.2 syncVariablesToParser / syncVariablesFromParser の全変数コピー

**ファイル:** `MacroRunner.swift:582-641`

式評価のたびに全変数を MacroRunner ↔ TTLParser 間でコピーする O(n) 操作。
変数が数百個になると顕著なオーバーヘッド。

**高速化案:**
- 変数ストレージを統合し、二重管理を廃止
- または dirty フラグで変更変数のみ同期

---

### 4.3 filereadln のバイト単位読み込み

**ファイル:** `MacroRunner.swift:2541-2553`

```swift
while true {
    let byte = handle.readData(ofLength: 1)  // ← 1バイトずつシステムコール
}
```

**高速化案:** 4KB〜16KB バッファで一括読み込み、メモリ上で改行検索。

---

### 4.4 filestrseek (reverse) の O(n×m) シーク

**ファイル:** `MacroRunner.swift:2770-2781`

1バイトずつ seek + read を繰り返す逆方向検索。

**高速化案:** チャンク単位（4KB）で逆方向読み込み、メモリ上で検索。

---

### 4.5 sprintf の文字列操作が非効率

**ファイル:** `MacroRunner.swift:2209-2263`

`String.Index` ベースで `replaceSubrange` を繰り返す。各置換で O(n) コピーが発生。

**高速化案:** 1パスで出力バッファに書き込む方式に変更。

---

### 4.6 CRC 計算にルックアップテーブル未使用

**ファイル:** `MacroRunner.swift:3644-3690`

ビット単位ループ。テーブル使用で約8倍高速化可能。

---

### 4.7 expandenv の全環境変数ループ

**ファイル:** `MacroRunner.swift:3073-3075`

全環境変数（数十〜数百個）に対して `replacingOccurrences` を実行。

**高速化案:** `%...%` パターンを検出し、該当変数のみ置換。

---

## 5. クラッシュリスク

### 5.1 TTLMacroApp.swift の Force Unwrap

**ファイル:** `TTLMacroApp.swift:122, 132`

```swift
if !self!.isXPCMode {  // ← self が nil なら即クラッシュ
```

`[weak self]` でキャプチャしているのに `self!` を使用。

---

### 5.2 exec コマンドがメインスレッドをブロック

**ファイル:** `MacroRunner.swift:3092-3093`

```swift
try process.run()
process.waitUntilExit()  // ← メインスレッドブロック
```

外部コマンドが長時間実行されると RunLoop が停止し、XPC 通信・UI更新がすべて凍結。

---

### 5.3 fileseek の SEEK_CUR で負のオフセットが機能しない

**ファイル:** `MacroRunner.swift:2679`

```swift
let offset = UInt64(resolveInt(args[1]))  // ← 負値が巨大正値に
```

---

## 6. 論理バグ

### 6.1 strspecial のエスケープ処理順序

**ファイル:** `MacroRunner.swift:2127-2131`

`\\` の変換が最後のため、`"\\n"` が `"\n"` に誤変換される。

---

### 6.2 ラベルとユーザー変数の名前空間衝突

**ファイル:** `MacroRunner.swift:348-358`

ラベルが `variables` 辞書に格納され、`result` 等のシステム変数と衝突する可能性。

---

### 6.3 wait コマンドの subscribeToTerminalData 未解除

**ファイル:** `MacroRunner.swift:1597-1631`

パターンマッチ成功後もコールバックが発火し続ける可能性。

---

### 6.4 include のエンコーディング固定

**ファイル:** `MacroRunner.swift:1344`

```swift
guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8)
```

UTF-8 固定。`MacroFileLoader`（Shift-JIS/EUC-JP 自動検出）を使っていない。

---

### 6.5 findclose が全検索結果を一括クリア

**ファイル:** `MacroRunner.swift:2895-2898`

検索ID指定なしで全エントリを破棄。複数検索の並行使用で問題。

---

### 6.6 fileopen の maxFileHandles 未チェック

**ファイル:** `MacroRunner.swift:2434`

`maxFileHandles = 16` が定義されているが `cmdFileOpen` でハンドル数を確認していない。

---

## 7. セキュリティ

### 7.1 getpassword/setpassword の引数数がリファレンスと不一致

**リファレンス:** `getpassword pass 'Enter password'`（2引数）

**実装:** 3引数（filename, keyname, varname）を要求。
マクロスクリプトが2引数で呼び出した場合、args[2] アクセスで空文字が返りパスワードが失われる。

---

### 7.2 パスワードが変数辞書に平文保存

**ファイル:** `MacroRunner.swift:3823`

```swift
variables[varName] = .string(password)
```

Swift String はヒープに残り、ゼロ化不可能。

---

### 7.3 XPC エンドポイントファイルのパーミッション未設定

**ファイル:** `XPCServiceHandler.swift:68`

```swift
try data.write(to: URL(fileURLWithPath: filePath))
// ← パーミッション指定なし（デフォルト 0644）
```

他ユーザーが読み取り可能。`0600` に制限すべき。

---

## 8. サマリー

| 分類 | 件数 | 重要度 |
|------|------|--------|
| 引数順序/セマンティクス不一致 | 9 | **Critical** |
| 戻り値/動作差異 | 13 | **High** |
| 未実装システム変数 | 2 | **Medium** |
| パフォーマンス問題 | 7 | **Medium** |
| クラッシュリスク | 3 | **Critical** |
| 論理バグ | 6 | **High** |
| セキュリティ | 3 | **Medium** |
| **合計** | **43** | |

---

## 9. 優先対応推奨

### 即時対応（Critical）

| # | 項目 | 影響 |
|---|------|------|
| 1.1 | sprintf/sprintf2 の入出力先修正 | 既存マクロの動作が壊れる |
| 1.2 | fileopen の引数解釈修正 | ファイル操作が意図と逆になる |
| 1.3 | filesearch のファイル内検索実装 | 機能が根本的に欠落 |
| 5.1 | force unwrap クラッシュ修正 | アプリが落ちる |
| 5.2 | exec のメインスレッドブロック修正 | 長時間コマンドで凍結 |

### 高優先度（High）

| # | 項目 |
|---|------|
| 1.4-1.7 | str2int/str2code/code2str/filestat の引数順序修正 |
| 1.8 | getspecialfolder の番号修正 |
| 1.9 | getver の計算式修正 |
| 2.7 | sendbinary の16進文字列パース実装 |
| 2.8 | `#13` 文字コード構文の実装 |

### 中優先度（Medium）

| # | 項目 |
|---|------|
| 2.1 | strmatch の result を位置に変更 |
| 2.2 | strsplit の groupmatchstr 設定 |
| 2.4 | strreplace の正規表現対応 |
| 2.6 | sendln の CR のみ送信 |
| 3.1-3.2 | mtimeout / paramcnt / param1-9 実装 |
| 4.1 | Timer ベース実行の高速化 |
