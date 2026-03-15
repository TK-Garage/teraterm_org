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
26. [実装と仕様の差異一覧（要修正）](#26-実装と仕様の差異一覧要修正)

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

ファイルの内容を送信。第 2 引数でバイナリ/テキストモードを指定。

```ttl
sendfile '/path/to/data.txt' 0    ; テキストモード（改行変換あり）
sendfile '/tmp/data.bin' 1        ; バイナリモード（生データ送信）
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | 送信するファイルのパス |
| `<binary_flag>` | 整数 | 0=テキストモード（改行変換）, 1=バイナリモード（生データ） |

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

正規表現による文字列置換。指定位置から検索し、最初にマッチした箇所を置換する。

```ttl
strreplace <strvar> <index> <regex> <newstr>

s = 'foo bar foo'
strreplace s 1 'foo' 'baz'
; s = 'baz bar foo', result = 1, matchstr = 'foo'

s = 'abc123def'
strreplace s 1 '[0-9]+' ''
; s = 'abcdef', result = 1, matchstr = '123'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | 検索・置換対象の文字列 |
| `<index>` | 整数 | 検索開始位置（1 起算） |
| `<regex>` | 文字列 | 検索する正規表現パターン |
| `<newstr>` | 文字列 | 置換文字列（空文字列でマッチ部分を削除） |

**result**: 1 = 置換成功、0 = パターンが見つからない、-1 = 無効な正規表現
**matchstr**: マッチした文字列が格納される

### `strspecial`

エスケープシーケンスを展開（`\n`, `\r`, `\t`, `\\`, `\"`, `\'`）。

```ttl
s = 'Line1\nLine2'
strspecial s
; s に改行入りの文字列が格納される
```

### `strtrim`

文字列の前後から指定文字を除去する。

```ttl
strtrim <strvar> <trimchars>

s = '  hello  '
strtrim s ' '
; s = 'hello'（前後のスペースを除去）

s = '---title---'
strtrim s '-'
; s = 'title'（前後のハイフンを除去）

s = '##*info*##'
strtrim s '#*'
; s = 'info'（前後の # と * を除去）
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | トリム対象の文字列 |
| `<trimchars>` | 文字列 | 除去する文字のセット（各文字が個別に除去対象） |

### `strsplit`

区切り文字で文字列を分割し、`groupmatchstr1`〜`groupmatchstr9` に格納する。

```ttl
strsplit <strval> <separator> [<count>]

strsplit 'a,b,c,d' ','
; result = 4
; groupmatchstr1 = 'a', groupmatchstr2 = 'b'
; groupmatchstr3 = 'c', groupmatchstr4 = 'd'

strsplit 'a,b,c,d' ',' 2
; result = 2
; groupmatchstr1 = 'a', groupmatchstr2 = 'b,c,d'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strval>` | 文字列 | 分割する文字列 |
| `<separator>` | 文字列 | 区切り文字（1 文字） |
| `[<count>]` | 整数 | 最大分割数（1〜9、デフォルト 9） |

**result**: 分割された要素数（9 を超える場合は 10）
**groupmatchstr1〜9**: 分割結果。未使用の変数は空文字列にクリアされる。`count` を超える残りは最後の変数にまとめられる。

### `strjoin`

`groupmatchstr1`〜`groupmatchstr9` を区切り文字で結合する（`strsplit` の逆操作）。

```ttl
strjoin <strvar> <separator> [<count>]

; strsplit で分割した結果を再結合
strsplit 'a,b,c' ','
strjoin buf ','
; buf = 'a,b,c'

; 最初の 2 要素のみ結合
strjoin buf ',' 2
; buf = 'a,b'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | 結合結果の格納先 |
| `<separator>` | 文字列 | 区切り文字 |
| `[<count>]` | 整数 | 結合する `groupmatchstr` の数（デフォルト 9） |

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

リスト選択ダイアログ。`strdim` で作成した文字列配列から項目を選択する。

```ttl
listbox <message> <title> <string array> [<selected>]

strdim items 3
items[0] = 'Apple'
items[1] = 'Banana'
items[2] = 'Cherry'
listbox '果物を選んでください' 'Select Fruit' items
if result >= 0 then
  ; result = 選択インデックス（0 起算）
endif

; 初期選択指定
listbox 'Select' 'Title' items 1   ; Banana を初期選択
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<message>` | 文字列 | ダイアログに表示するメッセージ |
| `<title>` | 文字列 | ダイアログのタイトル |
| `<string array>` | 文字列配列 | `strdim` で作成した選択肢の配列 |
| `[<selected>]` | 整数 | 初期選択インデックス（0 起算） |

**result**: 選択インデックス（0 起算）、-1 = キャンセル

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

ファイル選択ダイアログ。選択結果は `inputstr` に格納される。

```ttl
filenamebox <title> [<dialogtype> [<initialdir>]]

filenamebox 'Select a file'
if result > 0 then
  ; inputstr に選択されたファイルパスが入る
endif

; 保存ダイアログ
filenamebox 'Save as' 1

; 初期ディレクトリ指定
filenamebox 'Open file' 0 '/tmp'
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<title>` | 文字列 | ダイアログのタイトル |
| `[<dialogtype>]` | 整数 | 0=開くダイアログ（デフォルト）、0 以外=保存ダイアログ |
| `[<initialdir>]` | 文字列 | 初期ディレクトリパス |

**result**: 0 以外 = ファイル選択、0 = キャンセル
**inputstr**: 選択されたファイルパス

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

接続から受信したデータを直接ファイルに保存。指定時間データがなければ自動停止する。

```ttl
recvfile <filename> <binary_flag> <autostop_seconds>

recvfile '/tmp/received.dat' 0 10   ; 10秒無通信で自動停止
recvfile '/tmp/received.dat' 1 5    ; 5秒無通信で自動停止
recvfile '/tmp/received.dat' 0 0    ; 自動停止なし（手動停止）
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<filename>` | 文字列 | 保存先ファイルパス（相対パスはファイル転送フォルダ基準） |
| `<binary_flag>` | 整数 | 無視される（常にバイナリモードで保存） |
| `<autostop_seconds>` | 整数 | 指定秒間データなしで自動停止（0 以下=無制限待機） |

**result**: 0 = 正常完了、1 = タイムアウト（指定秒間データなし）

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

ログ記録を開始する。多段オプション形式で詳細制御。

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

ビット回転（32ビット整数の循環シフト）。

```ttl
rotateleft <intvar> <intval> <count>
rotateright <intvar> <intval> <count>
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<intvar>` | 整数変数 | 結果の格納先 |
| `<intval>` | 整数 | 回転する値 |
| `<count>` | 整数 | 回転ビット数 |

```ttl
rotateleft res $80000000 1
; res = 1

rotateright res 1 1
; res = $80000000

; 同じ変数に格納も可能
val = $80000000
rotateleft val val 1
; val = 1
```

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
差異の理由を分類する。

### 分類凡例

| 分類 | 意味 |
|------|------|
| **OS** | macOS / Windows の OS レベルの違いに起因（API・権限・概念の非互換） |
| **安全** | セキュリティ向上を目的とした意図的な変更 |

### 差異一覧

| コマンド | 分類 | オリジナル (Windows) | macOS 版 | 差異の理由 |
|----------|:----:|---------------------|----------|-----------|
| `cygconnect` | OS | Cygwin 環境への接続 | ローカルシェル（PTY）接続として動作（§12 参照） | macOS に Cygwin は存在しない。同等のローカルシェル接続を PTY 経由で提供する。 |
| `setdate` | OS | システム日付を変更 | 常に `result = -1` を返す | macOS では root 権限なしにシステム日付を変更できない。サンドボックス環境では原理的に不可。 |
| `settime` | OS | システム時刻を変更 | 常に `result = -1` を返す | 同上。 |
| `filelock` / `fileunlock` | OS | ファイルの排他ロック | スタブ実装（常に `result = 0`） | macOS のファイルロックは advisory lock（`flock`）のみで、Windows の mandatory lock と互換性がない。TTL スクリプトの互換性のためスタブで受け入れる。 |
| `getmodemstatus` | OS | モデム制御線（DSR, CTS 等）の状態取得 | スタブ実装（常に 0 を返す） | macOS の PTY にはモデム制御線の概念がない。シリアルポート直接接続は未対応。 |
| `getspecialfolder` | OS | 文字列名で指定（CSIDL: `"Desktop"` 等） | 数値 ID で指定（0=Desktop, 1=Documents, 2=AppSupport, 3=Home） | Windows の CSIDL 定数体系が macOS に存在しない。`NSSearchPathForDirectoriesInDomains` による macOS ネイティブなフォルダ解決に置換した。 |
| `getpassword` 等 | 安全 | パスワードファイルに暗号化保存・復号 | macOS Keychain に保存。XPC 経由で安全に送信。 | macOS の Keychain はOS レベルの暗号化ストレージを提供し、ファイルベースの自前暗号化よりセキュアかつ OS のパスワード管理と統合される。引数の互換性（`filename`, `keyname`）は維持し、内部で `filename:keyname` をアカウント名として Keychain に格納する。 |

---

## 26. 実装と仕様の差異一覧（要修正）

以下は本ドキュメント（TTLCommandReference.md）の仕様と実際の Swift 実装（MacroRunner.swift / TTLInterpreter.swift）を比較して検出した差異の一覧。
§25 の OS/安全による意図的差異とは異なり、修正すべき実装バグまたはドキュメント誤りである。

### 分類凡例

| 分類 | 意味 |
|------|------|
| **MR** | MacroRunner.swift（XPC プロセス側）のみの差異 |
| **TI** | TTLInterpreter.swift（インプロセス側）のみの差異 |
| **両方** | 両インタプリタ共通の差異 |
| **Doc** | ドキュメント記述自体の誤り（実装が正しい） |

### 26.1 引数の順序・形式の不一致

| コマンド | 分類 | 仕様（本ドキュメント） | 実装 | 備考 |
|----------|:----:|----------------------|------|------|
| `getenv` | MR | `getenv <envname> <strvar>` | `args[0]`=destVar, `args[1]`=envName（逆順） | TTLInterpreter は仕様通り |
| `fileopen` | MR | `fileopen <handle> <filename> <append> [<readonly>]` — append: 0=先頭, 1=末尾 | mode 列挙（0=read, 1=write, 2=rw, 3=append）で動作 | TTLInterpreter は仕様通り |
| `filestat` | MR | `filestat <filename> <size> [<mtime> [<drive>]]` | `args[0]`=destVar, `args[1]`=filePath（逆順） | TTLInterpreter は仕様通り |
| `getfileattr` | MR | `getfileattr <filename>` — result に属性値 | `args[0]`=destVar, `args[1]`=filePath（2引数、result ではなく変数に格納） | TTLInterpreter も別形式 `(filename, intvar)` |
| `getfileattr` | TI | `getfileattr <filename>` — result に属性値 | `(filename, intvar)` の 2 引数（result ではなく intvar に格納） | 仕様では result のみ |
| `dirnamebox` | MR | `dirnamebox <strvar> <title>` | `args[0]`=message, `args[1]`=defaultDir（strvar なし、inputstr に格納） | TTLInterpreter は仕様通り |

### 26.2 result / 戻り値の不一致

| コマンド | 分類 | 仕様（本ドキュメント） | 実装 | 備考 |
|----------|:----:|----------------------|------|------|
| `ifdefined` | MR | `result` に 1（存在）/ 0（不存在）を設定 | 条件ブロック制御（`ifNest += 1, elseFlag`）を操作。`result` を設定しない | TTLInterpreter は仕様通り |
| `recvln` | TI | result: 0=データなし, 1=受信成功 | result: 0=受信成功, 1=データなし（反転） | MacroRunner は仕様通り |
| `testlink` | 両方 | result: 0=未リンク, 1=リンク済み・未接続, 2=リンク済み・接続中 | 0 または 2 のみ返す（1 を返せない） | リンク状態と接続状態を区別する機構がない |
| `clipb2var` | 両方 | result: 0=データなし, 1=成功, 2=切り詰め | result を設定しない | offset パラメータも未対応（後述） |
| `var2clipb` | 両方 | result: 0=失敗, 1=成功 | result を設定しない | |
| `getver` | TI | 文字列変数に `'1.0.0'` 等のバージョン文字列を格納 | `getIntVar()` で整数変数に `50000` を格納 | MacroRunner は XPC 経由で文字列を返し仕様通り |

### 26.3 未対応のパラメータ・機能

| コマンド | 分類 | 仕様（本ドキュメント） | 実装 | 備考 |
|----------|:----:|----------------------|------|------|
| `clipb2var` | 両方 | 第 2 引数 `[<offset>]`（チャンク分割読み取り） | offset パラメータ未対応 | |
| `expandenv` | 両方 | 2 引数形式 `expandenv <strvar> <strval>` | 1 引数形式のみ対応 | |
| `filestat` | 両方 | 省略可能な `[<mtime> [<drive>]]` パラメータ | size のみ取得。mtime / drive 未対応 | |
| `fileseekback` | TI | `fileseekback <handle> <bytes>` — 指定バイト数後退 | `filemarkptr` で記録した位置へ戻る（bytes 引数を無視） | MacroRunner は仕様通り |

### 26.4 送信動作の差異

| コマンド | 分類 | 仕様（本ドキュメント） | 実装 | 備考 |
|----------|:----:|----------------------|------|------|
| `sendln` | MR | 文字列 + CR を送信 | `\r\n`（CR+LF）を付加 | TTLInterpreter は delegate 経由で CR のみ |

### 26.5 ドキュメント記述の誤り

| コマンド | 分類 | 現在の記述 | 正しい仕様 | 備考 |
|----------|:----:|----------|----------|------|
| `logrotate` | Doc | "引数なし" | 引数あり: `logrotate <mode> [<value>]`（mode: "size"/"rotate"/"halt"） | 両実装とも引数を取る |
| `loginfo` | Doc | "引数なし" | MacroRunner は引数なし（result + inputstr）、TTLInterpreter は `<strvar>` を取る | TTLInterpreter 側も要修正の可能性 |

### 26.6 未ドキュメントコマンド

以下のコマンドは両インタプリタのディスパッチテーブルに存在するが、本ドキュメントに記載がない。

| コマンド | 実装内容 | 備考 |
|----------|---------|------|
| `inc` | 整数変数をインクリメント（`inc <intvar>`） | |
| `dec` | 整数変数をデクリメント（`dec <intvar>`） | |
| `recv` | データを受信（タイムアウト付き）。result + inputstr に格納 | `recvln` の行区切りなし版 |
| `waitmatch` | `waitregex` のエイリアス | |
| `settimeout` / `timeout` | タイムアウト値を設定（`settimeout <seconds>`）。システム変数 `timeout` にも反映 | `timeout` 変数への代入と同等 |
