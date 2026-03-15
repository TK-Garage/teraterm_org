# TTL Exhaustive Command Test (exhaustive_command_test.ttl)

TTLCommandReference.md に記載された**全コマンド**の引数パターン・境界値・制御構造を網羅的に検証するテストスクリプト。

## 概要

| 項目 | 値 |
|------|------|
| テストケース数 | 147 |
| 行数 | 2,734 |
| セクション数 | 19 |
| 結果出力先 | `/tmp/ttl_exhaustive_test.log` |
| 接続要否 | **不要**（オフライン完結） |

---

## セクション一覧

### Section 1: Control Flow（制御フロー）— 10 tests
| # | テスト内容 | 検証ポイント |
|---|---|---|
| 1-1 | `if`/`then`/`endif` 真分岐 | 基本条件分岐 |
| 1-2 | `if`/`else` 偽分岐 | else 分岐 |
| 1-3 | 10段 `elseif` チェイン | 最大 elseif ネスト |
| 1-4 | 5段ネスト `if` | 深層 if ネスト |
| 1-5 | `goto` 前方ジャンプ | ラベル前方参照 |
| 1-6 | `goto` 後方ループ | ラベル後方参照 |
| 1-7 | `call`/`return` 基本 | サブルーチン呼び出し |
| 1-8 | `call` 10段ネスト | コールスタック最大深度 |
| 1-9 | `ifdefined` 既存変数 | result=1 |
| 1-10 | `ifdefined` 未定義変数 | result=0 |

### Section 2: Loops（ループ）— 13 tests
| # | テスト内容 | 検証ポイント |
|---|---|---|
| 2-1 | `for`/`next` 1..100 合計 | 基本 for ループ |
| 2-2 | `for` 単一反復 (5..5) | 境界: 開始=終了 |
| 2-3 | `while`/`endwhile` 50回 | while ループ |
| 2-4 | `while` 条件偽 (0回実行) | 境界: 0回ループ |
| 2-5 | `until`/`enduntil` | until ループ |
| 2-6 | `do`/`loop until` | 後判定 until |
| 2-7 | `do`/`loop while` | 後判定 while |
| 2-8 | `break` from `for` | for 中断 |
| 2-9 | `break` from `while` | while 中断 |
| 2-10 | `continue` in `for` | 奇数合計 |
| 2-11 | 3重ネスト `for` (10³) | 最大ネスト 1000回 |
| 2-12 | `for`-`while`-`if` 混合 | 異種ネスト |
| 2-13 | **STRESS** 10000回ループ | 高負荷反復 |

### Section 3: Expressions & Operators（式と演算子）— 15 tests
| # | テスト内容 | 検証ポイント |
|---|---|---|
| 3-1 | `+` `-` `*` `/` `%` | 全算術演算子 |
| 3-2 | 演算子優先順位 2+3*4 | 乗算優先 |
| 3-3 | 括弧 (2+3)*4 | 括弧による優先度変更 |
| 3-4 | 5段括弧ネスト | 深層括弧式 |
| 3-5 | `==` `!=` `<` `>` `<=` `>=` | 全比較演算子 |
| 3-6 | `<>` 不等号 | TeraTerm固有演算子 |
| 3-7 | `&&` `\|\|` 論理演算 | AND/OR 全パターン |
| 3-8 | `&` `\|` `^` ビット演算 | AND/OR/XOR |
| 3-9 | `<<` `>>` シフト | 左右シフト |
| 3-10 | INT32最大値 2147483647 | 整数境界 |
| 3-11 | `$7FFFFFFF` hex最大 | 16進リテラル境界 |
| 3-12 | 負数 `0 - 100` | 負数演算 |
| 3-13 | ゼロ値 | 境界値 |
| 3-14 | `#65#66#67` 文字コード | charコードリテラル |
| 3-15 | シングル/ダブルクォート | 文字列リテラル種別 |

### Section 4: String Operations（文字列操作）— 22 tests
| # | テスト内容 | 検証ポイント |
|---|---|---|
| 4-1 | `strlen` 通常/空/UTF-8 | 境界: 0文字, 日本語 |
| 4-2 | `strconcat` 基本+空文字 | 連結+空文字no-op |
| 4-3 | **STRESS** `strconcat` 2000文字 | 大文字列構築 |
| 4-4 | `strcopy` 先頭/中間/末尾 | 全位置パターン |
| 4-5 | `strcompare` 等/小/大 | 全比較結果 |
| 4-6 | `strscan` 発見/未発見 | 位置=7, 0 |
| 4-7 | `strmatch` マッチ/不一致 | 正規表現 |
| 4-8 | `str2int` 正/hex/負/不正 | 全変換パターン |
| 4-9 | `int2str` 正/負/0 | 全変換パターン |
| 4-10 | `str2code`/`code2str` ASCII+Unicode | 65='A', 12354='あ' |
| 4-11 | `strinsert` 先頭/中間 | 全挿入位置 |
| 4-12 | `strremove` | 部分削除 |
| 4-13 | `strreplace` マッチ/不一致/削除 | 3引数全パターン |
| 4-14 | `strspecial` エスケープ展開 | `\n` -> 改行 |
| 4-15 | `strtrim` 0/1/2 (両/先頭/末尾) | 全trimType |
| 4-16 | `strsplit`/`strjoin` 往復 | strArray方式 |
| 4-17 | `strsplit` 区切り文字なし | 境界: 1要素 |
| 4-18 | `strsplit` 10セグメント | 大量分割 |
| 4-19 | `strjoin` 異なる区切り文字 | 区切り変更 |
| 4-20 | `tolower`/`toupper` | 大文字小文字変換 |
| 4-21 | `sprintf` (inputstr格納) | 旧API |
| 4-22 | `sprintf2` `%d`/`%s`/`%x`/`%%` | 全書式指定子 |

### Section 5: Arrays（配列）— 5 tests
| # | テスト内容 | 検証ポイント |
|---|---|---|
| 5-1 | `intdim` 10要素 | 基本整数配列 |
| 5-2 | `strdim` 5要素 | 基本文字列配列 |
| 5-3 | **STRESS** `intdim` 1024 | 最大境界 |
| 5-4 | **STRESS** `strdim` 1024 | 最大境界 |
| 5-5 | 配列100要素 fill+verify | 全要素検証 |

### Section 6: File I/O（ファイル操作）— 19 tests
| # | テスト内容 | 検証ポイント |
|---|---|---|
| 6-1 | `fileopen`/`filewriteln`/`filereadln` | 基本 write→read |
| 6-2 | `filereadln` EOF検出 | result=1 |
| 6-3 | `fileopen` 追記モード(1) | append |
| 6-4 | `filewrite` 改行なし | raw書き込み |
| 6-5 | `fileread` Nバイト | バイト指定読み |
| 6-6 | `filecreate` 空ファイル | ファイル新規作成 |
| 6-7 | `filedelete` | ファイル削除 |
| 6-8 | `filecopy` | ファイルコピー |
| 6-9 | `filerename` | ファイル名変更 |
| 6-10 | `fileconcat` | ファイル連結 |
| 6-11 | `filesearch` 存在/非存在 | 存在確認 |
| 6-12 | `fileseek` 位置指定 | シーク操作 |
| 6-13 | `filemarkptr` | マーカー設定 |
| 6-14 | `filestat` (destVar first) | ファイルサイズ取得 |
| 6-15 | `filetruncate` | ファイル切り詰め |
| 6-16 | `filestrseek` 前方検索 | 文字列位置シーク |
| 6-17 | `filestrseek2` 後方検索 | 逆方向シーク |
| 6-18 | `filelock`/`fileunlock` スタブ | result=0 |
| 6-19 | **STRESS** 500行 write→read | 大量行I/O |

### Section 7: Directory Operations（ディレクトリ）— 3 tests
| # | テスト内容 | 検証ポイント |
|---|---|---|
| 7-1 | `foldercreate`/`foldersearch`/`folderdelete` | フォルダ操作一巡 |
| 7-2 | `findfirst`/`findnext`/`findclose` | ファイル列挙 |
| 7-3 | `changedir`+`getdir` | ディレクトリ変更 |

### Section 8: System/Environment（システム）— 26 tests
| # | テスト内容 | 検証ポイント |
|---|---|---|
| 8-1〜8-4 | `getdate`/`gettime`/`getdir`/`setdir` | 基本システム情報 |
| 8-5〜8-7 | `getenv`/`setenv` HOME/round-trip/非存在 | 環境変数全パターン |
| 8-8 | `expandenv` | `%VAR%` 展開 |
| 8-9〜8-10 | `getver` 非空/dot含有 | バージョン文字列 |
| 8-11〜8-12 | `gethostname`/`getttdir` | ホスト名/アプリディレクトリ |
| 8-13〜8-16 | `getspecialfolder` 0/1/2/3 | 全フォルダID |
| 8-17 | `getipv4addr` | IP取得(環境依存) |
| 8-18〜8-19 | `getfileattr`/`setfileattr` | ファイル属性 |
| 8-20 | `getmodemstatus` スタブ | result=0 |
| 8-21 | `uptime` | 稼働時間 > 0 |
| 8-22〜8-23 | `random` 範囲/非定数 | 乱数検証 |
| 8-24〜8-26 | `setdate`/`settime` 全フォーマット | 常に -1 (macOS) |

### Section 9: Path Operations — 3 tests
`makepath`, `basename`, `dirname`

### Section 10: Clipboard — 1 test
`var2clipb`/`clipb2var` (ヘッドレス環境対応)

### Section 11: Bit Rotation — 2 tests
`rotateleft`/`rotateright` round-trip + overflow

### Section 12: Checksum/CRC — 8 tests
`checksum8`/`16`/`32`, `crc16`/`32`, `crc32file`, 一貫性検証, **STRESS** 50段階CRC

### Section 13: External Commands — 3 tests
`exec`, `setexitcode`, `regexoption`

### Section 14: Pause/Timing — 1 test
`mpause` 50ms

### Section 15: Connection (offline) — 3 tests
`testlink`, `disconnect`, `cygconnect` (環境依存)

### Section 16: Other — 2 tests
`beep`, `setdebug` on/off

### Section 17: Combined Stress — 8 tests
| # | テスト内容 | 検証ポイント |
|---|---|---|
| 17-1 | Fibonacci(12)=144 | 複合演算 |
| 17-2 | 5x5行列積 C[0,0]=80 | 3重ネスト+配列 |
| 17-3 | 50ファイル高速I/O | ファイル操作ストレス |
| 17-4 | `strsplit`→`str2int`→合計 | コマンドチェイン |
| 17-5 | `getenv`→`strsplit`→`strjoin` | 環境変数→分割→結合 |
| 17-6 | `code2str`チェイン→"Hi!" | 文字コード構築 |
| 17-7 | **STRESS** 5000回 mod 合計 | 高負荷算術 |
| 17-8 | **STRESS** 100個フォーマット文字列 | sprintf2+配列 |

### Section 18: FileLock Stress — 1 test
10回 `filelock`/`fileunlock` サイクル

### Section 19: setdate/settime Exhaustive — 2 tests
全フォーマットパターン (空文字, 不正値含む)

---

## 実装とドキュメントの相違点（発見事項）

テスト作成中に発見した、**実装**と**TTLCommandReference.md**の引数順の不一致。
**テストはドキュメント準拠で記述** — 実装側を後日修正予定。

| コマンド | ドキュメント記載 | 実装の実際の動作 | テストでの対応 | 要修正 |
|---|---|---|---|---|
| `filestat` | `filestat <filepath> <destVar>` | `filestat <destVar> <filepath>` (逆順) | **ドキュメント準拠** | 実装修正必要 |
| `getfileattr` | `getfileattr <filepath> <destVar>` | `getfileattr <destVar> <filepath>` (逆順) | **ドキュメント準拠** | 実装修正必要 |
| `getenv` | `getenv <envName> <destVar>` (§11) | `getenv <destVar> <envName>` (destVar first) | 実装準拠 ※ | ドキュメント修正済み |
| `strreplace` | 4引数 `strreplace <var> <index> <regex> <newstr>` | 3引数 `strreplace <var> <target> <replacement>` | 実装準拠 | ドキュメント修正必要 |
| `strtrim` | `strtrim <var> <trimchars>` (文字列指定) | `strtrim <var> [<trimType>]` (整数: 0=両端, 1=先頭, 2=末尾) | 実装準拠 | ドキュメント修正必要 |
| `foldersearch` | `foldersearch <destVar> <pattern>` (2引数) | `foldersearch <path>` (1引数, ディレクトリ存在確認) | 実装準拠 | ドキュメント修正必要 |

> ※ `getenv` は他の多くのコマンド（`str2code`, `code2str` 等）と同じ destVar-first パターンなのでドキュメント側の記載が古い

---

## 実行方法

TeraTermMac でマクロファイルを開いて実行するか、TTL インタプリタから直接実行。

```
結果ログ: /tmp/ttl_exhaustive_test.log
```

## 接続が必要なコマンド（テスト対象外）

以下のコマンドは接続状態が必要なため、このオフラインテストには含まれていません：

- `send` / `sendln` / `sendtext` / `sendbinary` / `sendbreak` / `sendkcode` / `sendfile`
- `recvln` / `recvfile` / `flushrecv`
- `wait` / `waitln` / `waitregex` / `waitn` / `waitrecv` / `wait4all` / `waitevent`
- `connect` / `disconnect` (基本テストのみ実施)
- `logopen` / `logclose` / `logpause` / `logstart` / `logwrite` / `loginfo` / `logrotate` / `logautoclosemode`
- `clearscreen` / `dispstr` / `settitle` / `gettitle` / `setecho` / `setsync` / `show` / `showtt` / `closett`
- `enablekeyb` / `setbaud` / `setflowctrl` / `setdtr` / `setrts` / `setserialdelaychar` / `setserialdelayline`
- `callmenu` / `restoresetup` / `loadkeymap`
- `xmodemrecv` / `xmodemsend` / `ymodemrecv` / `ymodemsend` / `zmodemrecv` / `zmodemsend`
- `bplusrecv` / `bplussend` / `kmtrecv` / `kmtsend` / `kmtget` / `kmtfinish`
- `quickvanrecv` / `quickvansend` / `scpsend` / `scprecv`
- `getpassword` / `setpassword` / `delpassword` / `ispassword` (Keychain対話操作)
- `sendbroadcast` / `sendlnbroadcast` / `sendmulticast` / `sendlnmulticast` / `setmulticastname`
- ダイアログ系: `inputbox` / `passwordbox` / `messagebox` / `yesnobox` / `listbox` / `statusbox` / `closesbox` / `filenamebox` / `dirnamebox` / `bringupbox` / `setdlgpos`
- `include` / `exit` / `execcmnd` (間接実行)
