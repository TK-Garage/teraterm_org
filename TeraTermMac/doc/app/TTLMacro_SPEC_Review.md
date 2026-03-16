# TTLMacro_SPEC.md 問題点レビュー

> **基準文書**: `TTLCommandReference.md`（権威的リファレンス）
> **対象文書**: `TTLMacro_SPEC.md`（TTLCommandReference.md に基づき記載された仕様書）
> **レビュー日**: 2026-03-16

---

## 概要

TTLCommandReference.md を正とし、TTLMacro_SPEC.md に存在する問題点・不整合を分類して列挙する。

| 重大度 | 件数 |
|--------|------|
| Critical（動作が正反対） | 2 |
| Major（コマンド名・引数の相違） | 8 |
| Minor（記述不足・表記差異） | 12 |
| Info（構成上の欠落） | 5 |
| **合計** | **27** |

---

## Critical（動作が正反対）

### C-1. sprintf / sprintf2 の入出力先が逆

**CommandReference の定義:**
- `sprintf` — 引数: `<format> [<args>...]`、結果は **`inputstr`** に格納。変数名引数なし。
  ```ttl
  sprintf 'Count: %d, Name: %s' 42 'Alice'
  ; inputstr = 'Count: 42, Name: Alice'
  ```
- `sprintf2` — 引数: `<strvar> <format> [<args>...]`、結果は **指定変数** に格納。
  ```ttl
  sprintf2 buf 'Error %d: %s' 404 'Not Found'
  ; buf = 'Error 404: Not Found'
  ```

**SPEC の記述 (line 145-146):**
- `sprintf` — `<strvar> <format> [<args>...]` → "Format string into **named variable**"
- `sprintf2` — `<strvar> <format> [<args>...]` → "Format string, store result in **`inputstr`**"

**問題:** 格納先が完全に逆。さらに SPEC は `sprintf` に存在しない `<strvar>` 引数を追加している。これは TeraTerm Windows 版との互換性を破壊する。

---

### C-2. logautoclose vs logautoclosemode — コマンド名が異なる

**CommandReference (line 1576-1581):**
```ttl
logautoclosemode 1
```

**SPEC (line 322):**
```
| `logautoclose` | `<mode>` (int) | -- | Set log auto-close mode. |
```

**問題:** CommandReference は `logautoclosemode` だが、SPEC は `logautoclose` と記載。コマンド名が異なるため、どちらかに基づいて実装するとスクリプト互換性が壊れる。

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

### M-2. `filesearch` のセマンティクスが曖昧

**CommandReference (line 735-741):**
```ttl
filesearch '/tmp/data.txt' 'pattern'
```
"ファイル内を検索" — 引数は `<filepath> <pattern>`、ファイル **内容** を検索する意味。

**SPEC (line 218):**
```
| `filesearch` | `<filepath> <pattern>` | -- | Search within file. |
```

**問題:** 両者とも「ファイル内検索」と読めるが、return 値の記述がない。既存コードレビュー（TTLMacro_CodeReview_CmdRef.md）では、実装がファイル **存在チェック** になっている可能性が指摘されている。SPEC は CommandReference に合わせて return 値（result: 1=found, 0=not found など）を明記すべき。

---

### M-3. `str2int` の引数順序が曖昧

**CommandReference (line 477-486):**
```ttl
str2int '42' val
; val = 42, result = 1
```
引数順: `<string> <intvar>` — 文字列が先、変数が後。

**SPEC (line 132, 182):**
```
| `str2int` | `<intvar> <string>` | `result`: 1=success, 0=failure | ... |
```
引数順: `<intvar> <string>` — **変数が先、文字列が後**。

**問題:** 引数順が逆。CommandReference のサンプルコードでは `str2int '42' val` だが、SPEC では `<intvar> <string>` と記載。

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

### M-5. `str2code` / `code2str` の引数順序

**CommandReference (line 498-513):**
```ttl
str2code 'A' code    ; code = 65
code2str 65 ch       ; ch = 'A'
```
- `str2code`: `<string> <intvar>` — 入力が先
- `code2str`: `<intcode> <strvar>` — 入力が先

**SPEC (line 134-135):**
```
| `str2code` | `<string> <intvar>` | -- | ... |
| `code2str` | `<intcode> <strvar>` | -- | ... |
```

**問題:** 引数順は一致。ただし SPEC が2箇所（String Operations テーブルと Variables テーブル）で重複記載しており、不整合のリスクがある。

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

### M-7. `getver` の計算式に補足なし

**CommandReference (line 1037-1043):**
```ttl
getver ver
; ver = 50000  (5.0.0 の場合)
```
計算式: `major*10000 + minor*100 + patch`

**SPEC (line 278):**
```
| `getver` | `<intvar>` | -- | Get version number (major*10000 + minor*100 + patch). |
```

**問題:** 計算式自体は記載されているが、コードレビュー（TTLMacro_CodeReview_CmdRef.md）で実装が `major*10000 + minor*100 + patch` ではなく異なる計算をしている可能性が指摘されている。SPEC はコード実装と CommandReference の両方と整合を取る必要がある。

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

**問題:** 値自体は一致しているが、コードレビュー（TTLMacro_CodeReview_CmdRef.md）で実装のフォルダ番号が Windows TeraTerm と異なる可能性が指摘されている。Windows 版 TeraTerm では 0=AllUsersDesktop, 1=AllUsersPrograms 等の異なるマッピングを使用する。SPEC は macOS 固有マッピングであることを明記すべき。

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

### m-8. MacroClientProtocol のメソッド数の不一致

**SPEC (line 434):**
> "64 methods total."

**SPEC の XPC メソッドテーブル:**
- TTLInterpreterDelegate マッピング: #1〜#41
- Additional XPC methods: #42〜#70

実際のリスト: **70 メソッド** が列挙されている。

**問題:** "64 methods total" という記述と、テーブルの70行が矛盾。

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

### m-11. `sendbinary` のデータ形式の説明不足

**CommandReference (line 236-242):**
```ttl
sendbinary '48656C6C6F'    ; "Hello"
sendbinary '0D0A'          ; CR LF
```
16進文字列でバイナリデータを送信。

**SPEC (line 120):**
```
| `sendbinary` | `<hexstring>` | -- | Send binary data as hex string (e.g., '48656C6C6F'). |
```

**問題:** コードレビュー（TTLMacro_CodeReview_CmdRef.md）で、実装が16進文字列のパースをせず UTF-8 バイトをそのまま送信している可能性が指摘されている。SPEC は仕様（16進パース）と実装の乖離を認識していない。

---

### m-12. `for` ループの例で `sprintf` の使い方が CommandReference と矛盾

**CommandReference (line 126-135):**
```ttl
for i 1 10
  sprintf '%d ' i
  dispstr inputstr
next
```
ここでは `sprintf` の結果を `inputstr` から `dispstr` で表示 — CommandReference の sprintf 定義（結果は inputstr）と一致。

**SPEC (line 145):**
SPEC の `sprintf` 定義では結果が named variable に入るとされるため、上記の `dispstr inputstr` パターンが成立しない。

**問題:** CommandReference のサンプルコードとSPECの仕様定義が矛盾する。

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

以下は SPEC に記載があるが CommandReference には記載がない:

| 項目 | SPEC の記述 |
|---|---|
| `makedir` | `foldercreate` のエイリアス (line 240) |
| `protocolrecv` / `protocolsend` | 未実装として記載 (line 357-358) |
| Pattern A / Pattern B 起動フロー | SPEC 独自仕様 (line 49-105) |
| Keychain 完全仕様 | SPEC 独自仕様 (line 775-815) |
| ファイル転送 XPC フロー | SPEC 独自仕様 (line 818-905) |
| デバッガ仕様 | SPEC 独自仕様 (line 976-1030) |
| VariableWatchPanel | SPEC 独自仕様 (line 1011-1020) |
| BreakpointStore | SPEC 独自仕様 (line 1022-1030) |
| TransferErrorDetail | SPEC 独自仕様 (line 1032-1039) |

これらは SPEC の独自拡張であり、CommandReference にフィードバックすべきか、SPEC 固有の実装仕様として分離すべき。

---

## 修正推奨の優先順位

### 即時対応（Critical）

1. **sprintf / sprintf2 を CommandReference に合わせる** — 結果格納先を修正、sprintf から `<strvar>` 引数を削除
2. **logautoclose → logautoclosemode に修正** — コマンド名を CommandReference に合わせる

### 早期対応（Major）

3. **getpassword の引数セマンティクスを明確化** — CommandReference との差異（スタブ vs Keychain）を意図的な拡張として明記
4. **str2int の引数順を確認・修正** — CommandReference のサンプルコードに合わせる
5. **MacroClientProtocol メソッド数を修正** — "64 methods" → 実際の数に更新

### 計画対応（Minor）

6. **システム変数セクションを追加** — `timeout`, `mtimeout`, `paramcnt`, `param1`〜`param9`, `result`, `inputstr`, `matchstr`, `groupmatchstr1..N`
7. **式と演算子セクションを追加** — `#XX` 文字コードリテラルを含む
8. **macOS 固有動作差異セクションを追加**
9. **重複コマンド記載を整理**
10. **sendbinary の実装とSPECの整合を確認**
