# TTL (Tera Term Language) マクロ コマンドリファレンス

Tera Term Mac で利用可能な TTL マクロコマンドの一覧です。
コマンド名は**大文字小文字を区別しません**（`Send` = `send` = `SEND`）。

---

## 目次

1. [制御フロー](#1-制御フロー)
2. [ループ](#2-ループ)
3. [送受信](#3-送受信)
4. [待機 (Wait)](#4-待機-wait)
5. [一時停止](#5-一時停止)
6. [文字列操作](#6-文字列操作)
7. [ファイル I/O](#7-ファイル-io)
8. [ディレクトリ操作](#8-ディレクトリ操作)
9. [配列](#9-配列)
10. [ダイアログ](#10-ダイアログ)
11. [システム／環境](#11-システム環境)
12. [ターミナル操作](#12-ターミナル操作)
13. [ファイル転送](#13-ファイル転送)
14. [クリップボード](#14-クリップボード)
15. [パス操作](#15-パス操作)
16. [ログ](#16-ログ)
17. [外部コマンド実行](#17-外部コマンド実行)
18. [ビット演算](#18-ビット演算)
19. [チェックサム / CRC](#19-チェックサム--crc)
20. [パスワード (Keychain)](#20-パスワード-keychain)
21. [ブロードキャスト / マルチキャスト](#21-ブロードキャスト--マルチキャスト)
22. [その他](#22-その他)
23. [システム変数](#23-システム変数)
24. [式と演算子](#24-式と演算子)
25. [macOS 固有の動作差異](#25-macos-固有の動作差異)

---

## 1. 制御フロー

### `if` / `elseif` / `else` / `endif`

ブロック形式（`then` 付き）と単行形式の条件分岐。

```ttl
; ブロック形式
if result == 1 then
  messagebox 'Match found' 'Info'
elseif result == 2 then
  messagebox 'Second match' 'Info'
else
  messagebox 'No match' 'Info'
endif

; 単行形式（then なし → 同一行の残りを実行）
if flag send 'OK'
```

### `goto`

ラベルへ無条件ジャンプ。

```ttl
goto loop_start

:loop_start
send 'hello'
```

### `call` / `return`

サブルーチン呼び出しと復帰。`call` はスコープレベルを 1 上げる。

```ttl
call my_sub
end

:my_sub
  send 'in subroutine'
  return
```

### `include`

外部スクリプトファイルを読み込んで実行。

```ttl
include 'common_settings.ttl'
include '/path/to/library.ttl'
```

### `end`

マクロ実行を終了する。

```ttl
end
```

### `exit`

`include` されたファイルから呼び出し元へ戻る。トップレベルでは `end` と同等。

```ttl
exit
```

### `ifdefined`

変数の存在を確認する。

```ttl
ifdefined myvar
if result goto var_exists
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<varname>` | 識別子 | 存在を確認する変数名 |

**result**: 1 = 存在する、0 = 存在しない

---

## 2. ループ

### `for` / `next`

カウンタ変数による繰り返し。

```ttl
for i 1 10
  sprintf '%d ' i
  dispstr inputstr
next
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<var>` | 整数変数 | カウンタ変数 |
| `<start>` | 整数 | 開始値 |
| `<end>` | 整数 | 終了値 |

### `while` / `endwhile`

条件が真の間ループ。

```ttl
i = 0
while i < 5
  i = i + 1
endwhile
```

### `until` / `enduntil`

条件が真になるまでループ。

```ttl
count = 0
until count >= 10
  count = count + 1
enduntil
```

### `do` / `loop`

後判定ループ。`loop` に `while` または `until` を付けて条件指定。

```ttl
i = 0
do
  i = i + 1
loop while i < 5
```

### `break`

ループを中断して抜ける。

```ttl
for i 1 100
  if i == 50 break
next
```

### `continue`

ループの残りをスキップし、次の反復へ進む。

```ttl
for i 1 10
  if i == 5 continue
  sprintf '%d ' i
  dispstr inputstr
next
```

---

## 3. 送受信

> 送受信コマンドは接続状態が必要です。未接続時は `linkFirst` エラーになります。

### `send`

文字列をターミナルへ送信。複数引数は連結される。

```ttl
send 'ATZ' #13
send 'Hello, ' username #13 #10
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<arg1>` | 文字列 or 整数 | 送信データ（`#13` = CR 等） |
| `[<arg2>...]` | 文字列 or 整数 | 追加データ（連結） |

### `sendln`

文字列 + CR を送信。

```ttl
sendln 'ls -la'
sendln username
```

### `sendtext`

文字列式を送信。

```ttl
sendtext 'raw text data'
```

### `sendbinary`

16進文字列でバイナリデータを送信。

```ttl
sendbinary '48656C6C6F'    ; "Hello"
sendbinary '0D0A'          ; CR LF
```

### `sendbreak`

ブレーク信号を送信。引数なし。

```ttl
sendbreak
```

### `sendkcode`

文字コードで 1 文字送信。

```ttl
sendkcode 65    ; 'A'
sendkcode $1B   ; ESC
```

### `sendfile`

ファイルの内容を送信。Windows 版 TTL 互換: 第 2 引数でバイナリ/テキスト指定。

```ttl
sendfile '/path/to/data.txt' 0    ; テキストモード（改行変換あり）
sendfile '/tmp/data.bin' 1        ; バイナリモード（生データ送信）
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | 送信するファイルのパス |
| `<binary_flag>` | 整数 | 0=テキストモード（改行変換）, 1=バイナリモード（生データ） |

> **macOS 実装メモ**: 現在の macOS 版実装では `<binary_flag>` を無視し、常にバイナリモードで送信する。テキストモードの改行変換（CR/LF → LF 等）は未実装。

### `recvln`

1 行受信する。

```ttl
recvln
if result == 1 then
  ; inputstr に受信行が入る
endif
```

**result**: 0 = データなし、1 = 受信成功
**inputstr**: 受信した行

### `flushrecv`

受信バッファをクリア。引数なし。

```ttl
flushrecv
```

---

## 4. 待機 (Wait)

### `wait`

最大 10 個のパターンのいずれかが受信されるまで待機。

```ttl
timeout = 30
wait 'login:' 'Password:' 'failed'
if result == 1 sendln username
if result == 2 sendln password
if result == 0 goto timeout_handler
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<pattern1>` | 文字列 | マッチパターン 1 |
| `[<pattern2>...]` | 文字列 | マッチパターン 2〜10 |

**result**: 0 = タイムアウト、1〜10 = マッチしたパターン番号

### `waitln`

行単位で最大 10 パターンを待機。

```ttl
waitln 'OK' 'ERROR'
```

**result**: 0 = タイムアウト、1〜 = パターン番号
**inputstr**: マッチした行

### `waitregex`

正規表現でパターンマッチ待機。

```ttl
waitregex 'IP: ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)'
; matchstr にマッチ全体、groupmatchstr1 にキャプチャグループ
```

**matchstr**: マッチした文字列全体

### `waitn`

指定バイト数の受信を待機。

```ttl
waitn 1024
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<bytecount>` | 整数 | 待機するバイト数 |

### `waitrecv`

任意のデータ受信を待機。

```ttl
waitrecv
```

### `wait4all`

全パターンが（順序不問で）出現するまで待機。

```ttl
wait4all 'Module A OK' 'Module B OK' 'Module C OK'
```

### `waitevent`

ターミナルイベントを待機。引数なし。

```ttl
waitevent
```

> **タイムアウト**: システム変数 `timeout`（秒）と `mtimeout`（ミリ秒）で制御。

---

## 5. 一時停止

### `pause`

秒単位で一時停止。

```ttl
pause 3      ; 3 秒待機
```

### `mpause`

ミリ秒単位で一時停止。

```ttl
mpause 500   ; 0.5 秒待機
```

---

## 6. 文字列操作

### `strlen`

文字列長を取得。

```ttl
strlen 'Hello'
; result = 5
```

**result**: 文字列の長さ

### `strconcat`

文字列変数に追加連結。

```ttl
msg = 'Hello'
strconcat msg ', World!'
; msg = 'Hello, World!'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | 連結先 |
| `<string>` | 文字列 | 連結する文字列 |

### `strcopy`

部分文字列をコピー。

```ttl
strcopy 'Hello World' 7 5 sub
; sub = 'World'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<source>` | 文字列 | 元の文字列 |
| `<start>` | 整数 | 開始位置（1 起算） |
| `<length>` | 整数 | コピー長 |
| `<destvar>` | 文字列変数 | 格納先 |

### `strcompare`

文字列を比較。

```ttl
strcompare 'abc' 'def'
; result: -1 (abc < def), 0 (等しい), 1 (abc > def)
```

**result**: -1 / 0 / 1

### `strscan`

部分文字列を検索。

```ttl
strscan 'Hello World' 'World'
; result = 7 (1-based 位置)
```

**result**: 見つかった位置（1 起算）、0 = 見つからない

### `strmatch`

正規表現マッチ。

```ttl
strmatch 'Error 404: Not Found' '([0-9]+)'
; result = 7, matchstr = '404'
```

**result**: マッチ位置（1 起算）、0 = マッチなし
**matchstr**: マッチした文字列

### `str2int`

文字列を整数に変換。

```ttl
str2int val '42'
; val = 42, result = 1

str2int hex_val '$FF'
; hex_val = 255, result = 1
```

**result**: 1 = 成功、0 = 失敗

### `int2str`

整数を文字列に変換。

```ttl
int2str buf 1234
; buf = '1234'
```

### `str2code`

文字列の先頭文字をコードに変換。

```ttl
str2code code 'A'
; code = 65
```

### `code2str`

文字コードを文字列に変換。

```ttl
code2str ch 65
; ch = 'A'
```

### `strinsert`

文字列に挿入。

```ttl
s = 'Hello World'
strinsert s 6 'Beautiful '
; s = 'Hello Beautiful World'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | 対象 |
| `<position>` | 整数 | 挿入位置（1 起算） |
| `<string>` | 文字列 | 挿入する文字列 |

### `strremove`

部分文字列を削除。

```ttl
s = 'Hello World'
strremove s 6 6
; s = 'Hello'
```

### `strreplace`

文字列を置換。全出現箇所を置換する。

```ttl
s = 'foo bar foo'
strreplace s 'foo' 'baz'
; s = 'baz bar baz', result = 1

s = 'remove--dashes'
strreplace s '--' ''
; s = 'removedashes'（空文字列で削除）
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | 対象（インプレース変更） |
| `<target>` | 文字列 | 検索する文字列 |
| `<replacement>` | 文字列 | 置換文字列（空で削除） |

> **注意**: オリジナル Tera Term では `strreplace <strvar> <index> <regex> <newstr>` の 4 引数で正規表現を使用するが、macOS 版では 3 引数の単純文字列置換（§25 参照）。

**result**: 1 = 置換あり、0 = マッチなし、-1 = 無効な正規表現

### `strspecial`

エスケープシーケンスを展開（`\n`, `\r`, `\t`, `\\`, `\"`, `\'`）。

```ttl
s = 'Line1\nLine2'
strspecial s
; s に改行入りの文字列が格納される
```

### `strtrim`

前後の空白を除去。トリム方向を指定可能。

```ttl
s = '  hello  '
strtrim s
; s = 'hello'（両端）

s = '   leading'
strtrim s 1
; s = 'leading'（前方のみ）

s = 'trailing   '
strtrim s 2
; s = 'trailing'（後方のみ）
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | 対象 |
| `[<trimType>]` | 整数 | 0=両端（デフォルト）、1=前方のみ、2=後方のみ |

> **注意**: オリジナル Tera Term では `strtrim <strvar> <trimchars>` で除去文字セット（文字列）を指定するが、macOS 版では整数のトリム方向を指定する（§25 参照）。

### `strsplit`

区切り文字で分割。

> **macOS 固有動作**: オリジナル Tera Term では `groupmatchstr1`〜`groupmatchstr9` に格納される（最大 9 分割）。macOS 版では内部の文字列配列に格納される（§25 参照）。

```ttl
strsplit 'a,b,c,d' ',' destarray
; result = 4
; オリジナル TT: groupmatchstr1='a', groupmatchstr2='b', ...
; macOS 版: destarray に配列として格納
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<string>` | 文字列 | 分割する文字列 |
| `<separator>` | 文字列 | 区切り文字 |
| `<destvar>` | 変数 | 格納先（macOS 版） |

**result**: 分割された要素数

### `strjoin`

区切り文字で結合。

> **macOS 固有動作**: オリジナル Tera Term では `groupmatchstr1`〜`groupmatchstr9` を結合する（`strsplit` の逆操作）。macOS 版では文字列配列変数を指定して結合する（§25 参照）。

```ttl
strjoin buf srcarray ','
; buf = srcarray の各要素をカンマで結合した文字列
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<destvar>` | 文字列変数 | 結合結果の格納先 |
| `<srcvar>` | 変数 | 元の配列変数（macOS 版） |
| `<separator>` | 文字列 | 区切り文字 |

### `tolower`

小文字に変換。

```ttl
s = 'Hello World'
tolower s
; s = 'hello world'
```

### `toupper`

大文字に変換。

```ttl
s = 'Hello World'
toupper s
; s = 'HELLO WORLD'
```

### `sprintf`

書式付き文字列生成。結果は `inputstr` に格納。

```ttl
sprintf 'Count: %d, Name: %s' 42 'Alice'
; inputstr = 'Count: 42, Name: Alice'
```

書式指定子: `%d` (整数), `%s` (文字列), `%x` (16進), `%o` (8進), `%c` (文字), `%%` (リテラル %)

### `sprintf2`

書式付き文字列生成。結果を指定変数に格納。

```ttl
sprintf2 buf 'Error %d: %s' 404 'Not Found'
; buf = 'Error 404: Not Found'
```

---

## 7. ファイル I/O

### `fileopen`

ファイルを開く。

```ttl
fileopen fh '/tmp/data.txt' 0
; fh にファイルハンドル（失敗時 -1）

fileopen fh '/tmp/log.txt' 1     ; 追記モード
fileopen fh '/tmp/data.txt' 0 1  ; 読み取り専用
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<handlevar>` | 整数変数 | ファイルハンドル格納先 |
| `<filename>` | 文字列 | ファイルパス |
| `<append>` | 整数 | 0=ファイルポインタを先頭に設定, 1=ファイルポインタを末尾に設定（追記） |
| `[<readonly>]` | 整数 | 1=読み取り専用 |

ファイルが存在しない場合は新規作成される。失敗時は `<handlevar>` に -1 が設定される。

### `fileclose`

```ttl
fileclose fh
```

### `filereadln`

1 行読み取り。

```ttl
filereadln fh line
; line に読んだ行、result = 0 (成功) or 1 (EOF)
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<handle>` | 整数 | ファイルハンドル |
| `<strvar>` | 文字列変数 | 読み取った行の格納先 |

**result**: 0 = 成功、1 = EOF

### `fileread`

指定バイト数読み取り。

```ttl
fileread fh buf 256
```

### `filewrite` / `filewriteln`

ファイルへ書き込み。`filewriteln` は CRLF 付き。

```ttl
filewrite fh 'data without newline'
filewriteln fh 'data with newline'
```

### `filecreate`

空ファイルを作成。

```ttl
filecreate '/tmp/newfile.txt'
```

### `filedelete`

```ttl
filedelete '/tmp/oldfile.txt'
```

### `filecopy`

```ttl
filecopy '/tmp/source.txt' '/tmp/dest.txt'
```

### `filerename`

```ttl
filerename '/tmp/old.txt' '/tmp/new.txt'
```

### `fileconcat`

ソースファイルをデスティネーションに追記。

```ttl
fileconcat '/tmp/dest.txt' '/tmp/source.txt'
```

### `filesearch`

ファイルの存在を確認する。

```ttl
filesearch '/tmp/data.txt'
; result = 1 (存在する) or 0 (存在しない)
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | 確認するファイルパス |

**result**: 1 = ファイルが存在する、0 = 存在しない

### `fileseek` / `fileseekback`

```ttl
fileseek fh 0        ; 先頭に戻る
fileseekback fh 100  ; 100 バイト後退
```

### `filemarkptr`

現在位置にマーカーを設定。

```ttl
filemarkptr fh
```

### `filestat`

ファイルの統計情報を取得する。

```ttl
filestat <filename> <size> [<mtime> [<drive>]]
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | ファイルまたはフォルダのパス |
| `<size>` | 整数変数 | ファイルサイズ（バイト）の格納先 |
| `[<mtime>]` | 文字列変数 | 最終更新日時の格納先（省略可） |
| `[<drive>]` | 文字列変数 | ドライブ情報の格納先（省略可、macOS では空文字列） |

**result**: 0 = 成功、-1 = エラー

**使用例**:

```ttl
filestat '/tmp/data.txt' size mtime drv
if result == -1 then
  messagebox 'File not found' 'Error'
else
  sprintf2 msg 'Size=%d Modified=%s' size mtime
  messagebox msg 'filestat'
endif
```

### `filetruncate`

現在位置でファイルを切り詰め。

```ttl
fileseek fh 1024
filetruncate fh
```

### `filestrseek` / `filestrseek2`

ファイル内で文字列を前方/後方検索し、その位置に移動。

```ttl
filestrseek fh 'target'     ; 前方検索
filestrseek2 fh 'target'    ; 後方検索
; result = 1 (見つかった) or 0 (見つからない)
```

### `filelock` / `fileunlock`

ファイルロック（macOS ではスタブ）。

```ttl
filelock fh
fileunlock fh
```

---

## 8. ディレクトリ操作

### `findfirst` / `findnext` / `findclose`

ファイル検索（ディレクトリハンドルベース）。

```ttl
findfirst <dirhandle> <pattern> <strvar>
findnext <dirhandle> <strvar>
findclose <dirhandle>
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<dirhandle>` | 整数変数 | ディレクトリハンドル（`findfirst` が返す） |
| `<pattern>` | 文字列 | 検索パターン（`'*.txt'` 等） |
| `<strvar>` | 文字列変数 | 見つかったファイル名の格納先 |

**result**: 1 = 見つかった、0 = 該当なし（`findfirst` 失敗時 `dirhandle` は -1）

```ttl
findfirst dh '*.txt' filename
while result
  sprintf '%s\n' filename
  dispstr inputstr
  findnext dh filename
endwhile
findclose dh
```

### `foldercreate`

```ttl
foldercreate '/tmp/newdir'
```

### `folderdelete`

```ttl
folderdelete '/tmp/olddir'
```

### `foldersearch`

フォルダの存在を確認する。

```ttl
foldersearch <foldername>
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<foldername>` | 文字列 | 確認するフォルダのパス |

**result**: 1 = フォルダが存在する、0 = 存在しない

> **注意**: ファイルが同名で存在する場合は 0 を返す（フォルダのみ判定）。

```ttl
foldersearch '/tmp/mydir'
if result == 1 then
  messagebox 'Folder exists' 'Info'
endif
```

---

## 9. 配列

### `intdim`

整数配列を宣言。

```ttl
intdim data 100
data[0] = 42
data[99] = -1
```

### `strdim`

文字列配列を宣言。

```ttl
strdim names 10
names[0] = 'Alice'
names[1] = 'Bob'
```

---

## 10. ダイアログ

### `inputbox`

テキスト入力ダイアログ。

```ttl
inputbox 'Enter your name:' 'Input' 'default'
if result == 1 then
  username = inputstr
endif
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<prompt>` | 文字列 | プロンプトメッセージ |
| `[<title>]` | 文字列 | ウィンドウタイトル |
| `[<default>]` | 文字列 | デフォルト値 |

**result**: 1 = OK、0 = キャンセル
**inputstr**: 入力されたテキスト

### `passwordbox`

パスワード入力ダイアログ（マスク表示）。

```ttl
passwordbox 'Enter password:' 'Authentication'
```

### `messagebox`

メッセージダイアログ（OK ボタンのみ）。

```ttl
messagebox 'Operation complete.' 'Info'
```

### `yesnobox`

Yes / No 確認ダイアログ。

```ttl
yesnobox 'Continue?' 'Confirm'
if result == 1 then
  ; Yes が選ばれた
endif
```

**result**: 1 = Yes、0 = No

### `listbox`

リスト選択ダイアログ。

> **macOS 固有動作**: オリジナル Tera Term では `strdim` で作成した文字列配列を渡し、戻り値は 0 起算（-1 = キャンセル）。macOS 版では改行区切りの文字列を `<message>` に渡す簡略化方式を使用する（§25 参照）。

```ttl
listbox 'Apple\nBanana\nCherry' 'Select Fruit'
if result >= 0 then
  ; inputstr に選択項目
endif
```

**result**: 選択インデックス（0 起算）、-1 = キャンセル
**inputstr**: 選択された項目

### `statusbox`

ステータス表示ボックス（非モーダル）。

```ttl
statusbox 'Processing...' 'Status'
; 処理中...
closesbox
```

### `closesbox`

ステータスボックスを閉じる。引数なし。

### `filenamebox`

ファイル選択ダイアログ。

> **macOS 固有動作**: オリジナル Tera Term では `filenamebox <message> <flag> [<initdir>]` で結果を `inputstr` に格納するが、macOS 版では第1引数に格納先変数を指定する（§25 参照）。

```ttl
filenamebox filepath 'Select a file'
if result == 1 then
  ; filepath にパスが入る
endif

; 保存モード
filenamebox filepath 'Save as' 1
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | 選択パス格納先 |
| `[<title>]` | 文字列 | タイトル |
| `[<savemode>]` | 整数 | 0=開く, 1=保存 |

**result**: 1 = ファイル選択、0 = キャンセル

### `dirnamebox`

フォルダ選択ダイアログ。

```ttl
dirnamebox dirpath 'Select folder'
```

### `bringupbox`

アプリケーションを前面に表示。引数なし。

```ttl
bringupbox
```

### `setdlgpos`

ダイアログの表示位置を指定。

```ttl
setdlgpos 100 200    ; (100, 200) に表示
setdlgpos -1 -1      ; 中央（デフォルト）に戻す
```

---

## 11. システム／環境

### `getdate`

現在日付を取得（`yyyy/MM/dd` 形式）。

```ttl
getdate datestr
; datestr = '2026/03/09'
```

### `gettime`

現在時刻を取得（`HH:mm:ss` 形式）。

```ttl
gettime timestr
; timestr = '14:30:00'
```

### `getdir` / `setdir`

```ttl
getdir curdir
setdir '/tmp'
```

### `getenv` / `setenv`

```ttl
getenv 'HOME' homedir
setenv 'MY_VAR' 'value'
```

### `expandenv`

文字列中の `%VARNAME%` を環境変数の値で展開する。

```ttl
; 1引数形式: 変数の内容をその場で展開
path = '%HOME%/Documents'
expandenv path

; 2引数形式: strval を展開して strvar に格納
expandenv result '%HOME%/Documents'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | 展開結果の格納先（1引数時は対象兼格納先） |
| `[<strval>]` | 文字列 | 展開する文字列（省略時は `<strvar>` の現在値を展開） |

### `gettitle`

ターミナルウィンドウタイトルを取得。

```ttl
gettitle title
```

### `getver`

バージョン文字列を取得する。

> **macOS 固有動作**: オリジナル Tera Term ではバージョンを文字列（例: `'4.56'`）で返すが、macOS 版ではアプリの CFBundleShortVersionString を返す。

```ttl
getver ver
; ver = '1.0.0'
```

### `gethostname`

ホスト名を取得。

```ttl
gethostname host
```

### `getttdir`

アプリケーションディレクトリを取得。

```ttl
getttdir appdir
```

### `getspecialfolder`

システム特殊フォルダのパスを取得する。

> **macOS 固有動作**: オリジナル Tera Term では `<foldertype>` に文字列名（`"Desktop"`, `"MyDocuments"` 等の CSIDL 名）を指定するが、macOS 版では数値 ID を使用する（§25 参照）。

```ttl
getspecialfolder desktop 0    ; デスクトップ
getspecialfolder docs 1       ; Documents
getspecialfolder downloads 3  ; Downloads
```

| フォルダ番号 | パス |
|------------|------|
| 0 | デスクトップ |
| 1 | Documents |
| 2 | Application Support |
| 3 | Home ディレクトリ |

**result**: 1 = 成功、0 = 失敗

### `getipv4addr` / `getipv6addr`

```ttl
getipv4addr ip4
getipv6addr ip6
```

### `getfileattr` / `setfileattr`

ファイル属性を取得・設定する。

```ttl
getfileattr <filename>
; result: -1 = ファイル未検出、それ以外 = 属性値ビットマスク

setfileattr <filename> <attr>
; result: 0 = 成功、-1 = エラー
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | ファイルパス |
| `<attr>` | 整数 | 属性値（`setfileattr` 用） |

**属性ビット**:

| ビット | 16進値 | 説明 |
|--------|--------|------|
| bit 0 | `$1` | 読み取り専用 |
| bit 4 | `$10` | ディレクトリ |

**使用例**:

```ttl
; 読み取り専用チェック
getfileattr '/tmp/file.txt'
if result <> -1 then
  if result & $1 > 0 then
    messagebox 'Read-only' 'Info'
  endif
endif

; ディレクトリ判定
getfileattr '/tmp/testdir'
if result < 0 then
  messagebox 'Not found' 'Error'
elseif result & $10 then
  messagebox 'Directory' 'Info'
else
  messagebox 'File' 'Info'
endif

; 属性を保持しつつ読み取り専用を追加
getfileattr '/tmp/file.txt'
attr = result | $1
setfileattr '/tmp/file.txt' attr
```

### `getmodemstatus`

モデム状態取得（macOS ではスタブ）。

```ttl
getmodemstatus status
```

### `getttpos`

ターミナルウィンドウ位置を取得。

```ttl
getttpos xpos ypos
```

### `uptime`

システム稼働時間をミリ秒単位で取得。

```ttl
uptime <intvar>
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<intvar>` | 整数変数 | システム稼働時間（ミリ秒）の格納先 |

```ttl
; マクロ実行時間の計測
uptime t_start
; ... 処理 ...
uptime t_end
elapsed = t_end - t_start
sprintf2 msg 'Elapsed: %d ms' elapsed
messagebox msg 'Timer'
```

### `random`

乱数を生成。

```ttl
random val 100
; val = 0〜99
```

---

## 12. ターミナル操作

### `connect`

接続を確立。

```ttl
connect 'myhost.example.com:23'
```

**result**: 1 = 接続成功、0 = 失敗

### `cygconnect`

ローカルシェル（ターミナル）接続を開く。引数なし。

> **macOS 固有動作**: オリジナル Tera Term では Cygwin 環境への接続だが、macOS 版ではローカルシェル（PTY）接続として動作する。シェルパスや環境変数は Additional Settings > ローカルシェル タブの設定に従う。

```ttl
cygconnect
if result == 1 then
  ; 接続成功
endif
```

**result**: 1 = 接続成功、0 = 失敗

### `disconnect`

```ttl
disconnect
```

### `unlink`

マクロとターミナルのリンクを切断。接続中の場合のみ切断し、未接続時はエラーにならない。
`disconnect` と同等だが、未接続時にエラーを出さない点が異なる。

```ttl
unlink
```

### `testlink`

リンク・接続状態をテスト。

```ttl
testlink
if result == 0 then
  ; マクロがターミナルにリンクされていない
  connect 'myhost'
elseif result == 1 then
  ; リンク済みだが未接続
  connect 'myhost'
elseif result == 2 then
  ; リンク済みかつ接続中
endif
```

**result**: 0 = 未リンク、1 = リンク済み・未接続、2 = リンク済み・接続中

### `clearscreen`

画面をクリア。引数なし。

### `dispstr`

ターミナル画面に文字列を表示（送信はしない）。

```ttl
dispstr 'Status: OK\n'
```

### `settitle`

```ttl
settitle 'My Terminal'
```

### `setecho`

```ttl
setecho 1    ; ローカルエコー ON
setecho 0    ; OFF
```

### `setsync`

```ttl
setsync 1
```

### `show` / `showtt`

```ttl
show 1    ; 表示
show 0    ; 非表示
```

### `closett`

ターミナルウィンドウを閉じる。引数なし。

### `enablekeyb`

```ttl
enablekeyb 0    ; キーボード無効化
enablekeyb 1    ; 有効化
```

### `setbaud`

```ttl
setbaud 115200
```

### `setflowctrl`

```ttl
setflowctrl 0    ; なし
setflowctrl 1    ; XON/XOFF
setflowctrl 2    ; ハードウェア
```

### `setdtr` / `setrts`

```ttl
setdtr 1    ; DTR ON
setrts 0    ; RTS OFF
```

### `setserialdelaychar`

シリアルポート送信時の文字間遅延をミリ秒で設定。

```ttl
setserialdelaychar 10    ; 文字毎に 10ms の遅延
```

### `setserialdelayline`

シリアルポート送信時の行間遅延をミリ秒で設定。

```ttl
setserialdelayline 100    ; 行毎に 100ms の遅延
```

### `callmenu`

メニューコマンドを ID で呼び出す。

```ttl
callmenu 50110    ; メニュー ID 50110 を実行
```

### `restoresetup`

設定ファイルからターミナル設定を復元する。

```ttl
restoresetup '/path/to/settings.json'
```

### `loadkeymap`

キーボード設定ファイル (`.cnf`) を読み込む。オリジナル Tera Term と同一フォーマット。
文字コード (UTF-8 / Shift_JIS / EUC-JP / Latin-1) および改行コード (CRLF / LF / CR) を自動判定する。

```ttl
loadkeymap 'keyboard.cnf'
loadkeymap '/path/to/IBMKEYB.CNF'
```

**備考**: `.cnf` ファイルは `[VT editor keypad]`、`[VT numeric keypad]`、`[VT function keys]`、`[X function keys]`、`[Shortcut keys]`、`[User keys]` の 6 セクションからなる INI 形式ファイル。

---

## 13. ファイル転送

### `xmodemrecv`

XMODEM プロトコルでファイルを受信。

```ttl
xmodemrecv filename binary_flag option
; option: 1=Checksum, 2=CRC, 3=1K
xmodemrecv '/tmp/recv.dat' 1 2
```

**result**: 0 = 成功、1 = 失敗

### `xmodemsend`

XMODEM プロトコルでファイルを送信。

```ttl
xmodemsend filename option
; option: 2=CRC, 3=1K
xmodemsend '/tmp/send.dat' 3
```

**result**: 0 = 成功、1 = 失敗

### `ymodemrecv`

YMODEM プロトコルでファイルを受信。引数なし。

```ttl
ymodemrecv
```

**result**: 0 = 成功、1 = 失敗

### `ymodemsend`

YMODEM プロトコルでファイルを送信。

```ttl
ymodemsend '/tmp/file.bin'
```

**result**: 0 = 成功、1 = 失敗

### `zmodemrecv`

ZMODEM プロトコルでファイルを受信。引数なし。

```ttl
zmodemrecv
```

**result**: 0 = 成功、1 = 失敗

### `zmodemsend`

ZMODEM プロトコルでファイルを送信。

```ttl
zmodemsend filename binary_flag
zmodemsend '/tmp/file.bin' 1
```

**result**: 0 = 成功、1 = 失敗

### `bplusrecv`

B Plus プロトコルでファイルを受信。引数なし。

```ttl
bplusrecv
```

**result**: 0 = 成功、1 = 失敗

### `bplussend`

B Plus プロトコルでファイルを送信。

```ttl
bplussend '/tmp/file.bin'
```

**result**: 0 = 成功、1 = 失敗

### `kmtrecv`

Kermit プロトコルでファイルを受信。引数なし。

```ttl
kmtrecv
```

**result**: 0 = 成功、1 = 失敗

### `kmtsend`

Kermit プロトコルでファイルを送信。

```ttl
kmtsend '/tmp/file.bin'
```

**result**: 0 = 成功、1 = 失敗

### `kmtget`

リモート Kermit サーバーにファイル送信を要求。

```ttl
kmtget 'remote_file.txt'
```

**result**: 0 = 成功、1 = 失敗

### `kmtfinish`

リモート Kermit サーバーにサーバーモード終了を指示。引数なし。

```ttl
kmtfinish
```

**result**: 0 = 成功、1 = 失敗

### `quickvanrecv`

Quick VAN プロトコルでファイルを受信。引数なし。

```ttl
quickvanrecv
```

**result**: 0 = 成功、1 = 失敗

### `quickvansend`

Quick VAN プロトコルでファイルを送信。

```ttl
quickvansend '/tmp/file.bin'
```

**result**: 0 = 成功、1 = 失敗

### `scpsend`

SCP でファイルをリモートに送信。SSH 接続が必要。

```ttl
scpsend local_path [remote_path]
scpsend '/tmp/sample.txt' 'doc/sample.txt'
scpsend '/tmp/sample.txt'    ; リモートはファイル名のみ
```

**result**: 0 = 成功、1 = 失敗

### `scprecv`

SCP でリモートからファイルを受信。SSH 接続が必要。

```ttl
scprecv remote_path [local_path]
scprecv 'src/foo.txt' '/tmp/foo.txt'
scprecv 'src/foo.txt'    ; ローカルはカレントディレクトリ＋ファイル名
```

**result**: 0 = 成功、1 = 失敗

### `recvfile`

接続から受信したデータを直接ファイルに保存。Windows 版 TTL 互換: バイナリ/テキスト指定と自動停止機能付き。

```ttl
recvfile <filename> <binary_flag> <autostop_seconds>

recvfile '/tmp/received.txt' 0 10   ; テキストモード、10秒無通信で自動停止
recvfile '/tmp/received.dat' 1 5    ; バイナリモード、5秒無通信で自動停止
recvfile '/tmp/received.dat' 1 0    ; バイナリモード、自動停止なし（手動停止）
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | 保存先ファイルパス |
| `<binary_flag>` | 整数 | 0=テキストモード（改行変換）, 1=バイナリモード（生データ） |
| `<autostop_seconds>` | 整数 | 指定秒間データなしで自動停止（0=自動停止なし） |

> **macOS 実装メモ**: 現在の macOS 版実装では第 1 引数をローカルディレクトリとして解釈し、内部で ZMODEM プロトコル受信に委譲する。`<binary_flag>` と `<autostop_seconds>` は無視される。Windows 版の「接続データを直接ファイルに保存」する動作とは異なる。

**result**: 0 = 成功、1 = 失敗

---

## 14. クリップボード

### `clipb2var`

クリップボードの内容を変数に取得。

```ttl
clipb2var <strvar> [<offset>]
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | クリップボード内容の格納先 |
| `[<offset>]` | 整数 | 読み取り開始チャンク番号（511バイト単位、省略時 0） |

**result**: 0 = データなし、1 = 成功、2 = 切り詰め（残りあり）

```ttl
; 基本使用
clipb2var text

; 大きなクリップボード内容を分割読み取り
offset = 0
do
  clipb2var buf offset
  if result > 0 filewrite fh buf
  offset = offset + 1
loop while result == 2
```

### `var2clipb`

変数の内容をクリップボードに設定。

```ttl
var2clipb <string>
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<string>` | 文字列 | クリップボードに設定する文字列 |

**result**: 0 = 失敗、1 = 成功

```ttl
var2clipb 'copied text'
```

---

## 15. パス操作

### `makepath`

ディレクトリとファイル名を結合。

```ttl
makepath fullpath '/home/user' 'data.txt'
; fullpath = '/home/user/data.txt'
```

### `basename`

パスからファイル名を取得。

```ttl
basename name '/home/user/data.txt'
; name = 'data.txt'
```

### `dirname`

パスからディレクトリ部分を取得。

```ttl
dirname dir '/home/user/data.txt'
; dir = '/home/user'
```

### `changedir`

カレントディレクトリを変更。

```ttl
changedir '/tmp'
```

---

## 16. ログ

### `logopen`

ログ記録を開始する。Windows 版 TTL 互換: 多段オプション形式で詳細制御。

```ttl
logopen <filename> <binary> <append> [<plaintext> [<timestamp> [<hidestatus> [<include_screenbuf> [<timestamptype>]]]]]

; 基本形
logopen '/tmp/session.log' 0 0        ; テキスト・新規作成
logopen '/tmp/session.log' 0 1        ; テキスト・追記
logopen '/tmp/session.log' 1 0        ; バイナリ・新規作成
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | ログファイルのパス |
| `<binary>` | 整数 | 0=テキストモード, 1=バイナリモード |
| `<append>` | 整数 | 0=新規作成（上書き）, 1=追記 |
| `[<plaintext>]` | 整数 | 1=制御文字・エスケープシーケンスを除去 |
| `[<timestamp>]` | 整数 | 1=各行にタイムスタンプを付与 |
| `[<hidestatus>]` | 整数 | 1=ステータスバーにログ表示をしない |
| `[<include_screenbuf>]` | 整数 | 1=現在のスクリーンバッファをログに含める |
| `[<timestamptype>]` | 整数 | タイムスタンプ形式（0=ローカル時刻, 1=UTC, 2=経過時間, 3=ログ開始からの経過時間） |

> **macOS 実装メモ**: 現在の macOS 版実装では第 1 引数（`<filename>`）と第 2 引数（`<append>` として解釈）のみ対応。`<binary>`, `<plaintext>`, `<timestamp>` 等の追加オプションは無視される。Windows 版と同じ引数順でマクロを書いた場合、第 2 引数が `<binary>` ではなく `<append>` として解釈されるため注意が必要。

### `logclose`

引数なし。

### `logpause` / `logstart`

ログ記録の一時停止と再開。引数なし。

### `logwrite`

ログファイルにテキストを書き込み。

```ttl
logwrite 'Manual log entry'
```

### `loginfo`

ログ情報を取得。引数なし。

### `logrotate`

ログファイルをローテーション。引数なし。

### `logautoclosemode`

切断時にログファイルを自動的に閉じるかどうかを設定。`logopen` の前に呼び出す。

> **注意**: 現在の macOS 版実装ではコマンド名が `logautoclose`（`mode` なし）で登録されている。オリジナル Tera Term のコマンド名は `logautoclosemode`。

```ttl
logautoclosemode 1    ; 自動クローズ ON
logautoclosemode 0    ; OFF
```

---

## 17. 外部コマンド実行

### `exec`

外部アプリケーションを起動する。

```ttl
exec <command line> [<show> [<wait> [<current directory>]]]
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<command line>` | 文字列 | 実行するコマンドライン |
| `[<show>]` | 文字列/整数 | ウィンドウ表示モード（`'show'`, `'hide'`, `'minimize'`, `'maximize'`） |
| `[<wait>]` | 整数 | 1=終了を待つ、0=即座に戻る（デフォルト 0） |
| `[<current directory>]` | 文字列 | 作業ディレクトリ |

**result**: `<wait>` が 1 の場合、アプリケーションの終了コード

> **macOS 実装メモ**: macOS 版では `/bin/sh -c` 経由でコマンドを実行し、`inputstr` に標準出力、`result` に終了コードを格納する。`<show>`, `<wait>`, `<current directory>` オプションは未対応。

```ttl
exec 'ls -la /tmp'
; inputstr に出力、result に終了コード
```

### `execcmnd`

TTL コマンド文字列を動的に実行する。

```ttl
execcmnd <statement>
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<statement>` | 文字列 | 実行する TTL コマンド文字列 |

```ttl
cmd = 'messagebox "Dynamic!" "Title"'
execcmnd cmd

; 動的にコマンドを構築して実行
sprintf2 cmdstr 'send "%s"' username
execcmnd cmdstr
```

### `setexitcode`

マクロの終了コードを設定。

```ttl
setexitcode 0
```

---

## 18. ビット演算

### `rotateleft` / `rotateright`

ビット回転（32ビット整数の循環シフト）。変数の値をインプレースで回転する。

```ttl
rotateleft <intvar> <count>
rotateright <intvar> <count>
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<intvar>` | 整数変数 | 回転する値（結果もここに格納） |
| `<count>` | 整数 | 回転ビット数 |

```ttl
val = $80000000
rotateleft val 1
; val = 1

val = 1
rotateright val 1
; val = $80000000
```

> **注意**: オリジナル Tera Term では 3 引数（`rotateleft <intvar> <intval> <count>`）で入力と出力が別変数だが、macOS 版では 2 引数でインプレース操作（§25 参照）。

---

## 19. チェックサム / CRC

### 文字列版

```ttl
checksum8 result 'Hello'
checksum16 result 'Hello'
checksum32 result 'Hello'
crc16 result 'Hello'
crc32 result 'Hello'
```

### ファイル版

```ttl
checksum8file result '/tmp/data.bin'
checksum16file result '/tmp/data.bin'
checksum32file result '/tmp/data.bin'
crc16file result '/tmp/data.bin'
crc32file result '/tmp/data.bin'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<intvar>` | 整数変数 | 計算結果の格納先 |
| `<string/filename>` | 文字列 | 対象データまたはファイルパス |

---

## 20. パスワード (Keychain)

> **macOS 固有動作**: オリジナル Tera Term ではパスワードファイルに暗号化して保存するが、macOS 版では **macOS Keychain** を使用してセキュアに保存する。引数の `<filename>` と `<keyname>` を組み合わせた `filename:keyname` を Keychain のアカウント名として使用する。

### `getpassword` / `getpassword2`

Keychain からパスワードを取得する。該当エントリがない場合はパスワード入力ダイアログを表示し、入力されたパスワードを Keychain に保存する。

```ttl
getpassword 'password.dat' 'myserver' passvar
; passvar にパスワードが格納される
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | パスワードファイル名（Keychain アカウントのプレフィクス） |
| `<keyname>` | 文字列 | パスワード識別名 |
| `<varname>` | 文字列変数 | パスワード格納先 |

**result**: 1 = 成功、0 = 失敗

### `setpassword` / `setpassword2`

Keychain にパスワードを保存する。

```ttl
setpassword 'password.dat' 'myserver' 'secret123'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | パスワードファイル名 |
| `<keyname>` | 文字列 | パスワード識別名 |
| `<password>` | 文字列 | 保存するパスワード |

### `delpassword` / `delpassword2`

Keychain からパスワードを削除する。

```ttl
delpassword 'password.dat' 'myserver'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | パスワードファイル名 |
| `<keyname>` | 文字列 | パスワード識別名 |

### `ispassword` / `ispassword2`

Keychain にパスワードが存在するか確認する。

```ttl
ispassword 'password.dat' 'myserver'
; result = 1 (存在) or 0
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | パスワードファイル名 |
| `<keyname>` | 文字列 | パスワード識別名 |

**result**: 1 = 存在する、0 = 存在しない

---

## 21. ブロードキャスト / マルチキャスト

> 複数セッションへの同時送信（スタブ実装）。

```ttl
sendbroadcast 'command'
sendlnbroadcast 'command'
sendmulticast 'command'
sendlnmulticast 'command'
setmulticastname 'group1'
```

---

## 22. その他

### `beep`

システムビープ音を鳴らす。引数なし。

### `setdebug`

```ttl
setdebug 1    ; デバッグモード ON
setdebug 0    ; OFF
```

### `regexoption`

正規表現オプションを設定。

```ttl
regexoption 1    ; bit 0 = 大文字小文字無視
regexoption 0    ; デフォルト
```

### `setdate`

システム日付を設定する。

> **macOS 固有動作**: macOS ではシステム日時の変更に root 権限が必要なため、常に `result = -1`（失敗）を返す。引数は受け付けるが実際の変更は行わない。

```ttl
setdate '2026/03/14'
; result = -1 (macOS では常に失敗)
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<datestr>` | 文字列 | 日付文字列 |

**result**: 0 = 成功（macOS では不可）、-1 = 失敗

### `settime`

システム時刻を設定する。

> **macOS 固有動作**: `setdate` と同様、macOS では常に `result = -1` を返す。

```ttl
settime '14:30:00'
; result = -1 (macOS では常に失敗)
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<timestr>` | 文字列 | 時刻文字列 |

**result**: 0 = 成功（macOS では不可）、-1 = 失敗

---

## 23. システム変数

マクロ実行時に自動的に作成されるシステム変数：

| 変数名 | 型 | 説明 |
|--------|------|------|
| `result` | 整数 | コマンドの実行結果。各コマンドで意味が異なる |
| `inputstr` | 文字列 | ダイアログ入力、受信データ、`sprintf` 結果など |
| `matchstr` | 文字列 | `strmatch` / `waitregex` でマッチした文字列 |
| `timeout` | 整数 | `wait` 系コマンドのタイムアウト（秒） |
| `mtimeout` | 整数 | タイムアウトの追加ミリ秒部分 |
| `paramcnt` | 整数 | マクロに渡された引数の数 |
| `param1`〜`param9` | 文字列 | マクロに渡された引数 |
| `groupmatchstr1`〜`groupmatchstr9` | 文字列 | `waitregex`/`strmatch` のキャプチャグループ、`strsplit` の分割結果（オリジナル TT） |

---

## 24. 式と演算子

TTL では変数代入や条件式で以下の演算子が使えます。

### 算術演算子

| 演算子 | 説明 | 例 |
|--------|------|------|
| `+` | 加算 | `a = b + c` |
| `-` | 減算 | `a = b - c` |
| `*` | 乗算 | `a = b * c` |
| `/` | 除算 | `a = b / c` |
| `%` | 剰余 | `a = b % c` |

### 比較演算子

| 演算子 | 説明 | 例 |
|--------|------|------|
| `==` | 等しい | `if a == 0 then` |
| `!=` / `<>` | 等しくない | `if a != 0 then` |
| `<` | 小さい | `if a < 10 then` |
| `>` | 大きい | `if a > 10 then` |
| `<=` | 以下 | `if a <= 10 then` |
| `>=` | 以上 | `if a >= 10 then` |

### 論理演算子

| 演算子 | 説明 | 例 |
|--------|------|------|
| `&&` / `and` | 論理 AND | `if a && b then` |
| <code>&#124;&#124;</code> / `or` | 論理 OR | <code>if a &#124;&#124; b then</code> |
| `^^` / `xor` | 論理 XOR | `if a ^^ b then` |
| `!` / `not` | 論理 NOT | `if !flag then` |

### ビット演算子

| 演算子 | 説明 | 例 |
|--------|------|------|
| `&` | ビット AND | `a = b & $FF` |
| <code>&#124;</code> | ビット OR | <code>a = b &#124; $80</code> |
| `^` | ビット XOR | `a = b ^ $FF` |
| `~` | ビット NOT | `a = ~b` |
| `<<` | 左シフト | `a = b << 2` |
| `>>` | 算術右シフト | `a = b >> 2` |
| `>>>` | 論理右シフト | `a = b >>> 2` |

### 数値リテラル

| 形式 | 説明 | 例 |
|------|------|------|
| `123` | 10 進数 | `a = 255` |
| `$FF` | 16 進数 | `a = $FF` |
| `#65` | 文字コード | `send #13` |

### 文字列リテラル

```ttl
s = 'single quotes'
s = "double quotes"
```

---

## 25. macOS 固有の動作差異

以下のコマンドは macOS 版でオリジナル Tera Term (Windows) と異なる動作をする。

| コマンド | オリジナル (Windows) | macOS 版 |
|----------|---------------------|----------|
| `cygconnect` | Cygwin 環境への接続 | ローカルシェル（PTY）接続として動作（§12 参照） |
| `setdate` | システム日付を変更 | 常に `result = -1` を返す（root 権限が必要なため変更不可） |
| `settime` | システム時刻を変更 | 常に `result = -1` を返す（同上） |
| `filelock` / `fileunlock` | ファイルの排他ロック | スタブ実装（macOS では advisory lock のみ） |
| `getmodemstatus` | モデム制御線の状態取得 | スタブ実装（常に 0 を返す） |
| `listbox` | `strdim` 配列で項目指定、0 起算、-1=キャンセル | 改行区切り文字列で項目指定 |
| `getspecialfolder` | 文字列名で指定（CSIDL: `"Desktop"` 等） | 数値 ID で指定（0=Desktop, 1=Documents, 2=AppSupport, 3=Home） |
| `strsplit` | `groupmatchstr1`〜`groupmatchstr9` に格納（最大 9） | 内部文字列配列変数に格納（制限なし） |
| `strjoin` | `groupmatchstr1`〜`groupmatchstr9` を結合 | 文字列配列変数を結合 |
| `filenamebox` | `filenamebox <msg> <flag> [<dir>]`、`inputstr` に格納 | `filenamebox <strvar> <title> [<save>]`、指定変数に格納 |
| `getpassword` 等 | パスワードファイルに暗号化保存 | macOS Keychain に保存 |
| `sendfile` | `sendfile <filename> <binary_flag>`（0=テキスト, 1=バイナリ） | `<binary_flag>` を無視し常にバイナリモードで送信 |
| `logopen` | `logopen <filename> <binary> <append> [plaintext [timestamp ...]]` | 第 2 引数を `<append>` として解釈（`<binary>` 以降のオプション未対応） |
| `recvfile` | `recvfile <filename> <binary_flag> <autostop_seconds>` | 第 1 引数をディレクトリとして ZMODEM 受信に委譲（`<binary_flag>`, `<autostop>` 未対応） |
| `logautoclosemode` | コマンド名は `logautoclosemode` | 実装では `logautoclose`（`mode` なし）で登録 |
| `strreplace` | `strreplace <strvar> <index> <regex> <newstr>`（4 引数、正規表現） | `strreplace <strvar> <target> <replacement>`（3 引数、単純文字列置換） |
| `strtrim` | `strtrim <strvar> <trimchars>`（除去文字セットを文字列で指定） | `strtrim <strvar> [<trimType>]`（整数: 0=両端, 1=前方, 2=後方） |
| `rotateleft` / `rotateright` | `rotateleft <intvar> <intval> <count>`（3 引数、入出力別変数） | `rotateleft <intvar> <count>`（2 引数、インプレース操作） |
