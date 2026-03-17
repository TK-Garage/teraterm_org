# TTLMacro_SPEC.md 問題点レビュー

> **基準文書**: `TTLCommandReference.md`（権威的リファレンス）
> **対象文書**: `TTLMacro_SPEC.md`（TTLCommandReference.md に基づき記載された仕様書）
> **レビュー日**: 2026-03-16
> **検証日**: 2026-03-17（実ソースと突合検証済み）

---

## 概要

TTLCommandReference.md を正とし、TTLMacro_SPEC.md に存在する問題点・不整合を分類して列挙する。

> **検証結果**: 元の27件中3件（C-1, C-2, m-12）は実ソース検証で INVALID と判定。
> 有効件数は **24件**。3件は記述に誤りがあり修正済み（M-3, M-5, m-8）。

| 重大度 | 元件数 | 有効件数 | 備考 |
|--------|--------|----------|------|
| Critical（動作が正反対） | 2 | **0** | 両件とも SPEC で既に修正済み |
| Major（コマンド名・引数の相違） | 8 | **8** | 3件で説明を修正 |
| Minor（記述不足・表記差異） | 12 | **11** | m-12 は INVALID |
| Info（構成上の欠落） | 5 | **5** | 全件有効 |
| **合計** | **27** | **24** |

---

## Critical（動作が正反対）

> **2026-03-17 検証結果: 2件とも INVALID。SPEC は既に修正済みで CommandReference と一致。**

### C-1. sprintf / sprintf2 の入出力先が逆 — ~~INVALID（検証済み）~~

**CommandReference の定義:**
- `sprintf` — 引数: `<format> [<args>...]`、結果は **`inputstr`** に格納。
- `sprintf2` — 引数: `<strvar> <format> [<args>...]`、結果は **指定変数** に格納。

**SPEC の現在の記述 (line 143-144):**
- `sprintf` — `<format> [<args>...]` | `inputstr: 書式化文字列`
- `sprintf2` — `<strvar> <format> [<args>...]` | `--` (書式化結果を指定変数に格納)

**検証結果:** SPEC は既に CommandReference と一致している。格納先は正しく、`sprintf` に `<strvar>` 引数は含まれていない。本指摘は旧版 SPEC に対するものであり、現行版では解消済み。

---

### C-2. logautoclose vs logautoclosemode — ~~INVALID（検証済み）~~

**CommandReference:** `logautoclosemode`

**SPEC の現在の記述 (line 320):** `logautoclosemode`

**検証結果:** SPEC は既に `logautoclosemode` と正しく記載されている。本指摘は旧版 SPEC に対するものであり、現行版では解消済み。

---

## Major（コマンド名・引数の相違）

### M-1. getpassword の第2引数の意味が異なる

**CommandReference (line 1668-1671):**
```ttl
getpassword pass 'Enter password for server'
```
第2引数はプロンプト文字列/説明文。Section 20 の冒頭に「macOS 版ではスタブ実装です」との記載あり。

**SPEC (line 366):**
```
| `getpassword` | `<strvar> <account>` | -- | Keychain からパスワード取得。未保存時はダイアログ表示後に保存。|
```
第2引数は Keychain の **account 名**。完全な Keychain 実装として仕様化。

**問題:**
1. 引数の意味が異なる（プロンプト文字列 vs アカウント名）
2. CommandReference は「スタブ」、SPEC は「Keychain 完全実装」と矛盾

---

### M-2. `filesearch` のセマンティクスが異なる — **CONFIRMED（検証で悪化判定）**

**CommandReference (line 796-809):**
```ttl
filesearch '/tmp/data.txt'
; result = 1 (存在する) or 0 (存在しない)
```
"ファイルの存在を確認する" — 引数は `<filename>` **1引数**。return 値: `result: 1=存在, 0=不在`。

**SPEC (line 216):**
```
| `filesearch` | `<filepath> <pattern>` | -- | ファイル内を検索 |
```
**2引数**で、操作がファイル **内容検索**。return 値なし。

**問題:** 元のレビューでは「両者ともファイル内検索」としていたが、実際には CommandReference は **ファイル存在チェック**（1引数）、SPEC は **ファイル内検索**（2引数）と操作自体が完全に異なる。引数の数、操作の意味、return 値の全てが不一致。

---

### M-3. `str2int` の引数順序が逆 — **CONFIRMED（レビュー記述を修正）**

**CommandReference (line 481-493):**
```ttl
str2int val '42'
; val = 42, result = 1
```
引数順: `<intvar> <string>` — **変数が先、文字列が後**。

**SPEC (line 130, 180):**
```
| `str2int` | `<string> <intvar>` | `result`: 1=成功, 0=失敗 | ... |
```
引数順: `<string> <intvar>` — **文字列が先、変数が後**。

**問題:** 引数順が逆。元のレビューではどちらがどちらか記載が逆だったため修正。CommandReference は `str2int val '42'`（変数先）、SPEC は `<string> <intvar>`（文字列先）。

---

### M-4. `int2str` の引数順序の確認

**CommandReference (line 490-495):**
```ttl
int2str buf 1234
; buf = '1234'
```
引数順: `<strvar> <int>` — 変数が先。

**SPEC (line 133, 181):**
```
| `int2str` | `<strvar> <int>` | -- | ... |
```

**問題:** この場合は一致している。ただし `str2int` と `int2str` で引数パターンの一貫性が SPEC 内で崩れている（str2int は変数先、int2str も変数先だが、CommandReference では str2int は文字列先）。

---

### M-5. `str2code` / `code2str` の引数順序 — **CONFIRMED（レビュー記述を修正）**

**CommandReference (line 504-520):**
```ttl
str2code code 'A'    ; code = 65
code2str ch 65       ; ch = 'A'
```
- `str2code`: `<intvar> <string>` — **出力変数が先**
- `code2str`: `<strvar> <intcode>` — **出力変数が先**

**SPEC (line 132-133):**
```
| `str2code` | `<string> <intvar>` | -- | ... |
| `code2str` | `<intcode> <strvar>` | -- | ... |
```
- `str2code`: **入力が先**
- `code2str`: **入力が先**

**問題:** 元のレビューでは「引数順は一致」と記載したが、実際には **不一致**。CommandReference は全て出力変数が先（M-3 の str2int と同じパターン）、SPEC は入力が先。加えて SPEC は2箇所で重複記載しており不整合リスクがある。

---

### M-6. `recvfile` の引数記述の不一致

**CommandReference (line 1469-1480):**
```ttl
recvfile filename binary_flag autostop_seconds
recvfile '/tmp/received.dat' 1 5
; binary: 常に 1 (バイナリモード固定)
; autostop_seconds: 指定秒間データなしで自動停止 (0=無限)
```
引数: `<filepath> <binary> <autostop_sec>` — 3引数。

**SPEC (line 356):**
```
| `recvfile` | `<filepath> <binary> <autostop_sec>` | `result`: 0=success, 1=failure | ... |
```

**問題:** 引数は一致するが、SPEC の Description が "Receive data to file. autostop: 0=infinite." と簡略化されすぎ。CommandReference にある「binary: 常に 1（バイナリモード固定）」の重要な補足情報が欠落。

---

### M-7. `getver` の戻り値の型が異なる — **CONFIRMED（検証で悪化判定）**

**CommandReference (line 1193-1202):**
```ttl
getver ver
; ver = '1.0.0'
```
結果: **文字列**（CFBundleShortVersionString）。

**SPEC (line 276):**
```
| `getver` | `<intvar>` | -- | バージョン番号を取得（major*10000 + minor*100 + patch） |
```
結果: **整数**（計算式による）。

**実装（TTLInterpreter.swift line 2982-2987, MacroRunner.swift line 3246-3254）:**
`getStrVar()` / `setStrVal()` を使用 — **文字列を返す**。

**問題:** SPEC は `<intvar>` で整数計算式と記載しているが、CommandReference と実装の両方が **文字列**（バージョン文字列）を返す。SPEC の変数型と計算式が誤り。

---

### M-8. `getspecialfolder` のフォルダ番号

**CommandReference (line 1061-1077):**
| フォルダ番号 | パス |
|---|---|
| 0 | デスクトップ |
| 1 | Application Support |
| 2 | Documents |
| 3 | Downloads |

**SPEC (line 301):**
```
| `getspecialfolder` | `<strvar> <folderid>` | -- | Get special folder path. 0=Desktop, 1=App Support, 2=Documents, 3=Downloads. |
```

**問題（検証で悪化判定）:** フォルダ番号マッピングが4つのソース間で不一致:

| ID | CommandRef | SPEC | TTLInterpreter.swift | MacroRunner.swift |
|----|-----------|------|---------------------|------------------|
| 0 | Desktop | Desktop | Desktop | Desktop |
| 1 | Documents | App Support | App Support | Documents |
| 2 | App Support | Documents | Documents | App Support |
| 3 | Home | Downloads | Downloads | Home |

SPEC と TTLInterpreter は一致するが、CommandReference と MacroRunner は別のマッピング。**実装ファイル間でも不一致**がある。SPEC は macOS 固有マッピングであることを明記し、実装を統一すべき。

---

## Minor（記述不足・表記差異）

### m-1. `#XX` 文字コードリテラル構文の未記載

**CommandReference (line 1835):**
```
| `#65` | 文字コード | `send #13` |
```
`#XX` は数値リテラルとして文字コードを指定する構文（`send 'ATZ' #13` で CR 送信）。

**SPEC:** `#XX` 構文の説明が一切ない。send コマンドの説明で `#13 = CR` と記載はあるが、これが TTL の数値リテラル構文であることは説明されていない。

---

### m-2. システム変数セクションの欠落

**CommandReference (section 23, line 1767-1780):**
| 変数名 | 型 | 説明 |
|---|---|---|
| `result` | 整数 | コマンドの実行結果 |
| `inputstr` | 文字列 | ダイアログ入力、受信データ、sprintf 結果 |
| `matchstr` | 文字列 | strmatch/waitregex でマッチした文字列 |
| `timeout` | 整数 | wait 系のタイムアウト（秒） |
| `mtimeout` | 整数 | タイムアウトの追加ミリ秒部分 |
| `paramcnt` | 整数 | マクロに渡された引数の数 |
| `param1`〜`param9` | 文字列 | マクロに渡された引数 |

**SPEC:** システム変数の専用セクションが存在しない。`result` や `inputstr` は各コマンドの Return 列で個別に言及されるが、`mtimeout`、`paramcnt`、`param1`〜`param9` は一切記載されていない。

---

### m-3. 式と演算子セクションの欠落

**CommandReference (section 24, line 1783-1842):**
- 算術演算子: `+`, `-`, `*`, `/`, `%`
- 比較演算子: `==`, `!=`/`<>`, `<`, `>`, `<=`, `>=`
- 論理演算子: `&&`/`and`, `||`/`or`, `^^`/`xor`, `!`/`not`
- ビット演算子: `&`, `|`, `^`, `~`, `<<`, `>>`, `>>>`
- 数値リテラル: `123`（10進）, `$FF`（16進）, `#65`（文字コード）
- 文字列リテラル: `'single'`, `"double"`

**SPEC:** 式と演算子の専用セクションが存在しない。TTL マクロの基本構文要素であるため欠落は重大。

---

### m-4. macOS 固有動作差異セクションの欠落

**CommandReference (section 25, line 1846-1857):**
| コマンド | オリジナル (Windows) | macOS 版 |
|---|---|---|
| `cygconnect` | Cygwin 接続 | ローカルシェル (PTY) |
| `setdate` | システム日付変更 | 常に result = -1 |
| `settime` | システム時刻変更 | 常に result = -1 |
| `filelock`/`fileunlock` | 排他ロック | スタブ (advisory lock のみ) |
| `getmodemstatus` | モデム状態取得 | スタブ (常に 0) |

**SPEC:** 各コマンドの個別記述に "(stub)" の注記はあるが、macOS 固有の差異をまとめた専用セクションがない。移植性を考慮するマクロ作成者にとって重要な情報。

---

### m-5. `groupmatchstr1..N` キャプチャグループ変数の説明不足

**CommandReference (line 331-334):**
```ttl
waitregex 'IP: ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)'
; matchstr にマッチ全体、groupmatchstr1 にキャプチャグループ
```

**CommandReference (line 585-588):**
```ttl
strsplit 'a,b,c,d' ','
; result = 4
; groupmatchstr1='a', groupmatchstr2='b', ...
```

**SPEC:** `groupmatchstr1..N` 変数は `strsplit` の Return 列で言及されるが（line 141）、`waitregex` の Return 列（line 264）では `groupmatchstr1..N` の明記がない。また、これらがシステム変数であることの統一的な説明もない。

---

### m-6. `waitregex` の return 値記載の不一致

**CommandReference (line 329-334):**
- `matchstr`: マッチした文字列全体
- （暗黙に `groupmatchstr1..N`: キャプチャグループ）

**SPEC (line 264):**
```
| `waitregex` | `<regex>` | `matchstr`: full match; `groupmatchstr1..N`: capture groups | ... |
```

**問題:** SPEC は `groupmatchstr1..N` を記載しているが、`result` の値（0=timeout, 1=matched 等）を記載していない。CommandReference も明示していないが、wait 系コマンド共通の `result` 動作が適用されるはず。

---

### m-7. `makedir` コマンドが CommandReference に未記載

**SPEC (line 240):**
```
| `makedir` | `<path>` | -- | Create directory (alias). |
```

**CommandReference:** `makedir` コマンドは記載されていない。`foldercreate` のみ記載。

**問題:** SPEC が CommandReference にないコマンドを仕様化している。実装の根拠が不明。

---

### m-8. MacroClientProtocol のメソッド数記述 — **PARTIALLY CONFIRMED（レビュー記述を修正）**

**SPEC (line 1179):**
> "MacroClientProtocol（57 メソッド）"

**問題:** 元のレビューでは「SPEC (line 434) に "64 methods total" と記載」と指摘していたが、実際にはその記述は line 434 に存在しない。SPEC line 1179 では「57 メソッド」と記載。XPC マッピングテーブルの実際のメソッド数と照合し、正確な数を確認する必要がある。

---

### m-9. アーキテクチャ図の MacroClientProtocol メソッドリストが不完全

**SPEC (line 41-44):**
```
MacroClientProtocol: TTLMacro.app --> TeraTermMac.app
  (sendToTerminal, recvFromTerminal, showDialog, setWindowTitle,
   macroDidFinish, macroDidFail, logMessage, terminateApp,
   getAppVersion, didExecuteLine)
```

**問題:** 10メソッドしか列挙されていないが、実際には70メソッド。概要図として代表的なものを列挙するならその旨を明記すべき（「等」「...を含む」など）。

---

### m-10. `sendtext` の説明が不十分

**CommandReference (line 228-233):**
```ttl
sendtext 'raw text data'
```
"文字列式を送信" — `send` との違いは `#13` 等の特殊コード解釈をしないこと。

**SPEC (line 119):**
```
| `sendtext` | `<string>` | -- | Send string expression to terminal. |
```

**問題:** `send` との違い（特殊コード解釈の有無）が説明されていない。

---

### m-11. `sendbinary` のデータ形式の実装乖離 — **CONFIRMED（検証で実装確認済み）**

**CommandReference (line 236-242):**
```ttl
sendbinary '48656C6C6F'    ; "Hello"
sendbinary '0D0A'          ; CR LF
```
16進文字列でバイナリデータを送信。

**SPEC (line 118):**
```
| `sendbinary` | `<hexstring>` | -- | 16 進文字列としてバイナリデータを送信 |
```

**実装（MacroRunner.swift line 1266-1277）:**
```swift
func cmdSendBinary(_ args: [String]) {
    var bytes: [UInt8] = []
    for arg in args {
        let val = resolveInt(arg)
        bytes.append(UInt8(val & 0xFF))
    }
    ...
}
```
各引数を `resolveInt` で整数として解釈し、下位1バイトを抽出。**16進文字列のパースは行っていない**。

**問題:** 両ドキュメントは16進文字列形式（`'48656C6C6F'`）を記載しているが、実装は引数ごとに1整数→1バイトの変換。仕様と実装が完全に乖離している。

---

### m-12. `for` ループの例で `sprintf` の使い方が CommandReference と矛盾 — ~~INVALID（検証済み）~~

**CommandReference (line 126-135):**
```ttl
for i 1 10
  sprintf '%d ' i
  dispstr inputstr
next
```
`sprintf` の結果を `inputstr` から `dispstr` で表示 — CommandReference の sprintf 定義と一致。

**SPEC (line 143):**
SPEC の `sprintf` 定義は `<format> [<args>...]` | `inputstr: 書式化文字列` と正しく記載。

**検証結果:** C-1 が INVALID（SPEC の sprintf 定義は既に正しい）であるため、この矛盾も存在しない。`dispstr inputstr` パターンは SPEC の定義と整合する。

---

## Info（構成上の欠落）

### I-1. コマンドの重複記載

SPEC の All Macro Commands セクションで以下のコマンドが複数テーブルに重複して記載されている:

- `str2int` — String Operations テーブル (line 132) と Variables テーブル (line 182)
- `int2str` — String Operations テーブル (line 133) と Variables テーブル (line 181)
- `str2code` — String Operations テーブル (line 134) と Variables テーブル (line 183)
- `code2str` — String Operations テーブル (line 135) と Variables テーブル (line 184)

重複は不整合リスクを高める。1箇所に統合し、もう1箇所はリファレンスのみにすべき。

---

### I-2. `strsplit` / `strjoin` の例が CommandReference にあるが SPEC の例が欠落

**CommandReference (line 583-599):**
`strsplit` と `strjoin` の詳細な例とサンプルコードが記載。

**SPEC (line 141-142):**
テーブルの1行のみで、例なし。

---

### I-3. `waitrecv` / `waitevent` の仕様が不明確

**CommandReference / SPEC とも:** `waitrecv` と `waitevent` は "任意のデータ受信を待機" / "ターミナルイベントを待機" としか記載がなく、return 値、タイムアウト動作、`waitrecv` と `wait` / `waitln` との使い分けが不明。

---

### I-4. SPEC の `TTLInterpreterDelegate → XPC Mapping Table` に対応する CommandReference の記述なし

SPEC (line 619-720) に 70 メソッドの XPC マッピングテーブルがあるが、CommandReference は XPC 層に言及しない。これは SPEC 固有の実装仕様であり、CommandReference のスコープ外ではあるが、SPEC が「CommandReference に基づき記載」とされるなら、このセクションは SPEC 独自の追加仕様であることを明記すべき。

---

### I-5. SPEC にのみ存在するコマンド・概念

以下は SPEC に記載があるが CommandReference には記載がない（2026-03-17 検証済み）:

| 項目 | SPEC の記述 | 検証結果 |
|---|---|---|
| `makedir` | `foldercreate` のエイリアス (line 238) | **SPEC 独自**（CommandRef に未記載） |
| Pattern A / Pattern B 起動フロー | SPEC 独自仕様 (line 49-105) | **SPEC 独自**（CommandRef に未記載） |
| ファイル転送 XPC フロー | SPEC 独自仕様 (line 818-905) | **SPEC 独自**（実装アーキテクチャ仕様） |
| `protocolrecv` / `protocolsend` | 未実装として記載 (line 355-356) | ~~SPEC独自ではない~~ — CommandRef にも記載あり |
| Keychain 仕様 | SPEC 独自仕様 | ~~SPEC独自ではない~~ — CommandRef section 20 に詳細記載あり |
| ~~VariableWatchPanel~~ | ~~SPEC 独自仕様~~ | **該当なし** — SPEC にも存在しない |
| ~~BreakpointStore~~ | ~~SPEC 独自仕様~~ | **該当なし** — SPEC にも存在しない |

SPEC 独自の実装仕様（Pattern A/B、XPC フロー等）はその旨を明記すべき。

---

## 修正推奨の優先順位

### ~~即時対応（Critical）~~ — 解消済み

1. ~~sprintf / sprintf2~~ — SPEC は既に CommandReference と一致（INVALID）
2. ~~logautoclose → logautoclosemode~~ — SPEC は既に正しい（INVALID）

### 即時対応（Major — 実装への影響大）

3. **filesearch の定義を CommandReference に合わせる** — ファイル存在チェック(1引数)に修正、result値を記載
4. **str2int / str2code / code2str の引数順を CommandReference に合わせる** — 出力変数を先に
5. **getver を文字列型に修正** — `<intvar>` → `<strvar>`、計算式を削除
6. **getspecialfolder のマッピングを統一** — CommandRef/SPEC/実装間の不一致を解消
7. **getpassword の引数セマンティクスを明確化** — CommandReference との差異を明記

### 早期対応（Minor — ドキュメント品質）

8. **システム変数セクションを追加** — `timeout`, `mtimeout`, `paramcnt`, `param1`〜`param9`, `result`, `inputstr`, `matchstr`, `groupmatchstr1..N`
9. **式と演算子セクションを追加** — `#XX` 文字コードリテラルを含む
10. **macOS 固有動作差異セクションを追加**
11. **重複コマンド記載を整理** — `str2int` 等の2テーブル重複を解消
12. **recvfile の binary 引数説明を補足** — 「常にバイナリモード固定」を追記
13. **sendtext の send との違いを説明** — 特殊コード解釈の有無
14. **sendbinary の実装とSPECの整合を確認** — 16進パースの実装状況
