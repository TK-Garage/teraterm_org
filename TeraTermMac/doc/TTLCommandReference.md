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
25. [未実装コマンド](#25-未実装コマンド)

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

ファイルの内容を送信。

```ttl
sendfile '/path/to/data.txt'
```

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
str2int '42' val
; val = 42, result = 1

str2int '$FF' hex_val
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
str2code 'A' code
; code = 65
```

### `code2str`

文字コードを文字列に変換。

```ttl
code2str 65 ch
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

正規表現で置換。

```ttl
s = 'foo bar foo'
strreplace s 'foo' 'baz'
; s = 'baz bar baz', result = 1
```

**result**: 1 = 置換あり、0 = マッチなし

### `strspecial`

エスケープシーケンスを展開（`\n`, `\r`, `\t`, `\\`, `\"`, `\'`）。

```ttl
s = 'Line1\nLine2'
strspecial s
; s に改行入りの文字列が格納される
```

### `strtrim`

前後の空白（または指定文字）を除去。

```ttl
s = '  hello  '
strtrim s             ; 両端トリム → 'hello'
strtrim s ' ' 1       ; 左のみ
strtrim s ' ' 2       ; 右のみ
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<strvar>` | 文字列変数 | 対象 |
| `[<chars>]` | 文字列 | 除去する文字（省略時: 空白） |
| `[<trimtype>]` | 整数 | 0=両端, 1=左, 2=右 |

### `strsplit`

区切り文字で分割。

```ttl
strsplit 'a,b,c,d' ','
; result = 4
; groupmatchstr1='a', groupmatchstr2='b', ...
```

**result**: 分割された要素数

### `strjoin`

区切り文字で結合。

```ttl
strjoin buf ',' 'apple' 'banana' 'cherry'
; buf = 'apple,banana,cherry'
```

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
; fh にファイルハンドル、result = 0 (成功)

fileopen fh '/tmp/log.txt' 1     ; 追記モード
fileopen fh '/tmp/data.txt' 0 1  ; 読み取り専用
```

| 引数 | 型 | 説明 |
|------|------|------|
| `<handlevar>` | 整数変数 | ファイルハンドル格納先 |
| `<filename>` | 文字列 | ファイルパス |
| `<append>` | 整数 | 0=新規/上書き, 1=追記 |
| `[<readonly>]` | 整数 | 1=読み取り専用 |

**result**: 0 = 成功、-1 = エラー

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

**result**: 0 = 成功、1 = EOF
**inputstr**: 読み取った行

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

ファイル内を検索。

```ttl
filesearch '/tmp/data.txt' 'pattern'
```

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

ファイルサイズを取得。

```ttl
filestat '/tmp/data.txt' size
; size にバイト数が入る
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

ファイル検索。

```ttl
findfirst filename '*.txt'
while result == 0
  sprintf '%s\n' filename
  dispstr inputstr
  findnext filename
endwhile
findclose
```

**result**: 0 = 見つかった、-1 = 該当なし

### `foldercreate`

```ttl
foldercreate '/tmp/newdir'
```

### `folderdelete`

```ttl
folderdelete '/tmp/olddir'
```

### `foldersearch`

```ttl
foldersearch dirname '/tmp/test*'
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

リスト選択ダイアログ。項目は改行区切り。

```ttl
listbox 'Apple\nBanana\nCherry' 'Select Fruit'
if result > 0 then
  ; inputstr に選択項目
endif
```

**result**: 選択インデックス（1 起算）、0 = キャンセル
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

文字列中の `%VARNAME%` を展開。

```ttl
path = '%HOME%/Documents'
expandenv path
```

### `gettitle`

ターミナルウィンドウタイトルを取得。

```ttl
gettitle title
```

### `getver`

バージョン番号を取得（`major*10000 + minor*100 + patch`）。

```ttl
getver ver
; ver = 50000  (5.0.0 の場合)
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

システム特殊フォルダのパスを取得。

```ttl
getspecialfolder desktop 0    ; デスクトップ
getspecialfolder docs 2       ; Documents
getspecialfolder downloads 3  ; Downloads
```

| フォルダ番号 | パス |
|------------|------|
| 0 | デスクトップ |
| 1 | Application Support |
| 2 | Documents |
| 3 | Downloads |

### `getipv4addr` / `getipv6addr`

```ttl
getipv4addr ip4
getipv6addr ip6
```

### `getfileattr` / `setfileattr`

```ttl
getfileattr '/tmp/file.txt' attr
; attr: bit 0 = 読み取り専用、bit 4 = ディレクトリ
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

システム稼働時間を秒単位で取得。

```ttl
uptime seconds
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

接続状態をテスト。

```ttl
testlink
if result == 2 then
  ; 接続中
endif
```

**result**: 2 = 接続中、0 = 未接続

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

接続から受信したデータを直接ファイルに保存。自動停止機能付き。

```ttl
recvfile filename binary_flag autostop_seconds
recvfile '/tmp/received.dat' 1 5
; binary: 常に 1 (バイナリモード固定)
; autostop_seconds: 指定秒間データなしで自動停止 (0=無限)
```

**result**: 0 = 成功、1 = 失敗

---

## 14. クリップボード

### `clipb2var`

クリップボードの内容を変数に取得。

```ttl
clipb2var text
```

### `var2clipb`

変数の内容をクリップボードに設定。

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

```ttl
logopen '/tmp/session.log' 0     ; 新規
logopen '/tmp/session.log' 1     ; 追記
```

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

```ttl
logautoclosemode 1
```

---

## 17. 外部コマンド実行

### `exec`

シェルコマンドを実行。

```ttl
exec 'ls -la /tmp'
; inputstr に出力、result に終了コード
```

**result**: コマンドの終了コード
**inputstr**: 標準出力

### `execcmnd`

TTL コマンド文字列を動的実行。

```ttl
cmd = 'messagebox "Dynamic!" "Title"'
execcmnd cmd
```

### `setexitcode`

マクロの終了コードを設定。

```ttl
setexitcode 0
```

---

## 18. ビット演算

### `rotateleft` / `rotateright`

ビット回転。

```ttl
val = $80000000
rotateleft val 1
; val = 1

val = 1
rotateright val 1
; val = $80000000
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

> macOS 版ではスタブ実装です。

### `getpassword` / `getpassword2`

```ttl
getpassword pass 'Enter password for server'
```

### `setpassword` / `setpassword2`

```ttl
setpassword 'myserver' 'secret123'
```

### `delpassword` / `delpassword2`

```ttl
delpassword 'myserver'
```

### `ispassword` / `ispassword2`

```ttl
ispassword 'myserver'
; result = 1 (存在) or 0
```

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

### `setdate` / `settime`

システム日時設定（macOS ではエラーを返す）。

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

## 25. 未実装コマンド

以下は予約語として認識されますが、macOS 版では未実装（`notSupported` エラー）です。

| コマンド | 説明 |
|----------|------|
| ~~`bplusrecv` / `bplussend`~~ | ~~B Plus プロトコル転送~~ → 実装済み (§13) |
| ~~`xmodemrecv` / `xmodemsend`~~ | ~~XMODEM 転送~~ → 実装済み (§13) |
| ~~`ymodemrecv` / `ymodemsend`~~ | ~~YMODEM 転送~~ → 実装済み (§13) |
| ~~`zmodemrecv` / `zmodemsend`~~ | ~~ZMODEM 転送~~ → 実装済み (§13) |
| ~~`kmtrecv` / `kmtsend` / `kmtget` / `kmtfinish`~~ | ~~Kermit 転送~~ → 実装済み (§13) |
| ~~`quickvanrecv` / `quickvansend`~~ | ~~Quick VAN 転送~~ → 実装済み (§13) |
| ~~`scprecv` / `scpsend`~~ | ~~SCP 転送~~ → 実装済み (§13) |
| ~~`recvfile`~~ | ~~ファイル受信~~ → 実装済み (§13) |
| `cygconnect` | Cygwin 接続（macOS 非対応） |
| `loadkeymap` | キーマップ読み込み |
| ~~`restoresetup`~~ | ~~セットアップ復元~~ → 実装済み (§12) |
| ~~`callmenu`~~ | ~~メニュー呼び出し~~ → 実装済み (§12) |
| ~~`setserialdelaychar` / `setserialdelayline`~~ | ~~シリアル遅延設定~~ → 実装済み (§12) |
