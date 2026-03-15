# TTLMacro.app アーキテクチャ仕様書

## アーキテクチャ

TTLMacro.app は TeraTermMac のマクロ実行エンジンとして動作する独立した macOS アプリケーションである。メインのターミナルアプリケーション（TeraTermMac.app）とは Apple の XPC（Cross-Process Communication）機構を介して通信する。

- **TeraTermMac.app** -- ターミナルエミュレータ。XPC クライアントとして動作し、マクロ実行の起動と制御を行う。
- **TTLMacro.app** -- マクロ実行エンジン。MacroParser（TTLParser + TTLInterpreter）を内蔵し、`.ttl` マクロスクリプトを実行する。
- **TTLMacroShared** -- XPC プロトコル定義、ローカライズヘルパー、ダイアログ種別定数、実行状態 enum を含む共有 Swift モジュール。

```
+-----------------------------------------------------+
|                   User / .ttl file                   |
+-----------------------------------------------------+
         |                              |
         | パターン A: 直接起動         | パターン B: XPC 起動
         v                              v
+-------------------+         +--------------------+
|  TTLMacro.app     |         | TeraTermMac.app    |
|  (マクロ実行)      |<------->| (ターミナル)        |
|                   |   XPC   |                    |
| +---------------+ |         | +----------------+ |
| | TTLParser     | |         | | MacroXPC       | |
| | TTLInterpreter| |         | |   Manager      | |
| +---------------+ |         | +----------------+ |
| | StatusBar     | |         | | Terminal       | |
| |  Controller   | |         | |   Emulator     | |
| +---------------+ |         | +----------------+ |
+-------------------+         +--------------------+
         |                              |
         |       XPC Connection         |
         |  MacroServiceProtocol  ----> |
         |  <---- MacroClientProtocol   |
         +------------------------------+

   MacroServiceProtocol: TeraTermMac.app --> TTLMacro.app
     (runMacro, stopMacro, pauseMacro, resumeMacro, macroStatus, sendVariable)

   MacroClientProtocol:  TTLMacro.app --> TeraTermMac.app
     (sendToTerminal, recvFromTerminal, showDialog, setWindowTitle,
      macroDidFinish, macroDidFail, logMessage, terminateApp,
      getAppVersion, didExecuteLine)
```

---

## 起動フロー

### パターン A: ユーザーが TTLMacro.app を直接起動

1. ユーザーが TTLMacro.app をダブルクリックまたは Finder から起動する。
2. `--xpc-mode` 引数なしでアプリが起動する。
3. `.ttl` ファイル選択用の `NSOpenPanel` を表示する。
4. ユーザーがマクロファイルを選択して「実行」をクリックする。
5. TTLMacro がマクロをスタンドアロンで実行する（ターミナル接続なし）。

```
TTLMacro.app 起動
    |
    +-- CommandLine.arguments に "--xpc-mode" なし
    |
    v
NSOpenPanel 表示 (.ttl ファイル選択)
    |
    +-- ファイル選択 --> MacroParser が実行開始
    |                    --> ステータスバーに進捗表示
    |                    --> 完了/エラー --> アプリ終了
    |
    +-- キャンセル/閉じる --> NSApp.terminate(nil)
```

### パターン B: TeraTermMac.app が XPC 経由で起動

1. TeraTermMac.app が TTLMacro.app への XPC 接続を確立する。
2. TTLMacro.app が `--xpc-mode` 引数付きで起動される。
3. XPC サービスデリゲートが初期化され、ファイルピッカーは表示しない。
4. TeraTermMac.app が `runMacro(scriptPath:reply:)` を呼び出して実行を開始する。
5. TTLMacro.app が `MacroClientProtocol` 経由でターミナル I/O リクエストを送信する。
6. 完了時に `macroDidFinish(exitCode:)` または `macroDidFail(error:line:)` が呼ばれる。

```
TeraTermMac.app
    |
    +-- NSWorkspace.shared.openApplication(at:configuration:)
    |   引数: "--xpc-mode"
    |
    v
TTLMacro.app 起動
    |
    +-- CommandLine.arguments に "--xpc-mode" あり
    |
    v
NSXPCListener 開始 (接続待ち)
    |
    v
XPC 接続確立 <-- TeraTermMac.app が接続
    |
    v
runMacro(scriptPath:) 受信 --> MacroParser が実行開始
    |
    v
完了/エラー --> macroDidFinish/macroDidFail 通知 --> アイドル状態に復帰
```

---

## 全マクロコマンド一覧

コマンド名は大文字小文字を区別しない（`Send` = `send` = `SEND`）。

### 送受信・文字列操作

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `send` | `<arg1> [<arg2>...]`（文字列または整数） | -- | ターミナルに文字列を送信。複数引数は連結。`#13` = CR | Yes |
| `sendln` | `<string>` | -- | 文字列 + CR をターミナルに送信 | Yes |
| `sendtext` | `<string>` | -- | 文字列式をターミナルに送信 | Yes |
| `sendbinary` | `<hexstring>` | -- | 16 進文字列としてバイナリデータを送信（例: `'48656C6C6F'`） | Yes |
| `sendbreak` | -- | -- | ブレーク信号を送信 | Yes |
| `sendkcode` | `<charcode>`（整数） | -- | 文字コードで 1 文字送信 | Yes |
| `sendfile` | `<filepath>`（文字列） | -- | ファイル内容をターミナルに送信 | Yes |
| `recvln` | -- | `result`: 0=データなし, 1=成功; `inputstr`: 受信行 | 1 行受信 | Yes |
| `flushrecv` | -- | -- | 受信バッファをクリア | Yes |
| `strlen` | `<string>` | `result`: 文字列長 | 文字列の長さを取得 | Yes |
| `strconcat` | `<strvar> <string>` | -- | 変数に文字列を追加 | Yes |
| `strcopy` | `<source> <start> <length> <destvar>` | -- | 部分文字列をコピー（1 始まり） | Yes |
| `strcompare` | `<str1> <str2>` | `result`: -1, 0, 1 | 2 つの文字列を比較 | Yes |
| `strscan` | `<string> <pattern>` | `result`: 位置（1 始まり）, 0=未検出 | 部分文字列を検索 | Yes |
| `strmatch` | `<string> <regex>` | `result`: マッチ位置（1 始まり）, 0=不一致; `matchstr`: マッチ文字列 | 正規表現マッチ | Yes |
| `str2int` | `<string> <intvar>` | `result`: 1=成功, 0=失敗 | 文字列を整数に変換。`$FF` 16 進対応 | Yes |
| `int2str` | `<strvar> <int>` | -- | 整数を文字列に変換 | Yes |
| `str2code` | `<string> <intvar>` | -- | 先頭文字をコードに変換 | Yes |
| `code2str` | `<intcode> <strvar>` | -- | 文字コードを文字列に変換 | Yes |
| `strinsert` | `<strvar> <position> <string>` | -- | 指定位置に文字列を挿入（1 始まり） | Yes |
| `strremove` | `<strvar> <position> <length>` | -- | 部分文字列を削除 | Yes |
| `strreplace` | `<strvar> <pattern> <replacement>` | `result`: 1=置換, 0=不一致 | 正規表現置換 | Yes |
| `strspecial` | `<strvar>` | -- | エスケープシーケンスを展開（`\n`, `\r`, `\t`, `\\`, `\"`, `\'`） | Yes |
| `strtrim` | `<strvar> [<chars>] [<trimtype>]` | -- | 空白または指定文字をトリム。trimtype: 0=両端, 1=左, 2=右 | Yes |
| `strsplit` | `<string> <delimiter>` | `result`: 要素数; `groupmatchstr1..N`: 各要素 | 区切り文字で分割 | Yes |
| `strjoin` | `<strvar> <delimiter> <str1> [<str2>...]` | -- | 区切り文字で結合 | Yes |
| `tolower` | `<strvar>` | -- | 小文字に変換 | Yes |
| `toupper` | `<strvar>` | -- | 大文字に変換 | Yes |
| `sprintf` | `<format> [<args>...]` | `inputstr`: 書式化文字列 | 文字列書式化（`%d`, `%s`, `%x`, `%o`, `%c`, `%%`） | Yes |
| `sprintf2` | `<strvar> <format> [<args>...]` | -- | 書式化結果を指定変数に格納 | Yes |

### 制御フロー

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `if` | `<condition> [then]` | -- | 条件分岐。`then` 付きでブロック形式、なしで単行形式 | Yes |
| `elseif` | `<condition> [then]` | -- | else-if 分岐 | Yes |
| `else` | -- | -- | else 分岐 | Yes |
| `endif` | -- | -- | if ブロック終了 | Yes |
| `for` | `<var> <start> <end>` | -- | カウンタループ | Yes |
| `next` | -- | -- | for ループ終了 | Yes |
| `while` | `<condition>` | -- | while ループ | Yes |
| `endwhile` | -- | -- | while ループ終了 | Yes |
| `do` | -- | -- | do-loop 開始（後判定） | Yes |
| `loop` | `[while\|until <condition>]` | -- | do-loop 終了（条件付き） | Yes |
| `until` | `<condition>` | -- | 条件が真になるまでループ | Yes |
| `enduntil` | -- | -- | until ループ終了 | Yes |
| `break` | -- | -- | ループ脱出 | Yes |
| `continue` | -- | -- | 次のループ反復にスキップ | Yes |
| `goto` | `<label>` | -- | ラベルへ無条件ジャンプ | Yes |
| `call` | `<label>` | -- | サブルーチン呼び出し（スコープレベルを 1 上げる） | Yes |
| `return` | -- | -- | サブルーチンから復帰 | Yes |
| `include` | `<filepath>` | -- | 外部スクリプトファイルを読み込んで実行 | Yes |
| `end` | -- | -- | マクロ実行終了 | Yes |
| `exit` | -- | -- | include ファイルから脱出。トップレベルでは `end` と同等 | Yes |
| `ifdefined` | `<varname>` | `result`: 1=存在, 0=不存在 | 変数が定義済みか確認 | Yes |

### 変数

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| （代入） | `<var> = <expr>` | -- | 代入式で変数を設定 | Yes |
| `intdim` | `<arrayname> <size>` | -- | 整数配列を宣言 | Yes |
| `strdim` | `<arrayname> <size>` | -- | 文字列配列を宣言 | Yes |
| `int2str` | `<strvar> <int>` | -- | 整数を文字列に変換 | Yes |
| `str2int` | `<string> <intvar>` | `result`: 1=成功, 0=失敗 | 文字列を整数に変換 | Yes |
| `str2code` | `<string> <intvar>` | -- | 先頭文字をコードに変換 | Yes |
| `code2str` | `<intcode> <strvar>` | -- | コードを文字列に変換 | Yes |
| `random` | `<intvar> <max>` | -- | 0 から max-1 の乱数を生成 | Yes |

### ダイアログ

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `messagebox` | `<message> <title>` | -- | メッセージダイアログ表示（OK のみ） | Yes |
| `inputbox` | `<prompt> [<title>] [<default>]` | `result`: 1=OK, 0=キャンセル; `inputstr`: 入力テキスト | テキスト入力ダイアログ | Yes |
| `yesnobox` | `<message> <title>` | `result`: 1=Yes, 0=No | Yes/No 確認ダイアログ | Yes |
| `passwordbox` | `<prompt> [<title>]` | `result`: 1=OK, 0=キャンセル; `inputstr`: 入力テキスト | マスク付きパスワード入力ダイアログ | Yes |
| `statusbox` | `<message> <title>` | -- | 非モーダルステータス表示ボックス | Yes |
| `closesbox` | -- | -- | ステータスボックスを閉じる | Yes |
| `listbox` | `<items> <title>` | `result`: 選択インデックス（1 始まり）, 0=キャンセル; `inputstr`: 選択項目 | リスト選択ダイアログ。項目は `\n` 区切り | Yes |
| `filenamebox` | `<strvar> [<title>] [<savemode>]` | `result`: 1=選択, 0=キャンセル | ファイル選択ダイアログ。savemode: 0=開く, 1=保存 | Yes |
| `dirnamebox` | `<strvar> [<title>]` | `result`: 1=選択, 0=キャンセル | フォルダ選択ダイアログ | Yes |
| `bringupbox` | -- | -- | アプリケーションを前面に移動 | Yes |
| `setdlgpos` | `<x> <y>` | -- | ダイアログ表示位置を設定。-1,-1 = 中央 | Yes |

### ファイル I/O

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `fileopen` | `<handlevar> <filename> <append> [<readonly>]` | `result`: 0=成功, -1=エラー | ファイルを開く。append: 0=新規/上書き, 1=追記 | Yes |
| `fileclose` | `<handle>` | -- | ファイルを閉じる | Yes |
| `fileread` | `<handle> <bufvar> <bytes>` | -- | 指定バイト数を読み取り | Yes |
| `filereadln` | `<handle> <linevar>` | `result`: 0=成功, 1=EOF; `inputstr`: 行 | 1 行読み取り | Yes |
| `filewrite` | `<handle> <string>` | -- | ファイルに書き込み | Yes |
| `filewriteln` | `<handle> <string>` | -- | ファイルに CRLF 付きで書き込み | Yes |
| `filecreate` | `<filepath>` | -- | 空ファイルを作成 | Yes |
| `filedelete` | `<filepath>` | -- | ファイルを削除 | Yes |
| `filecopy` | `<source> <dest>` | -- | ファイルをコピー | Yes |
| `filerename` | `<old> <new>` | -- | ファイル名を変更 | Yes |
| `fileconcat` | `<dest> <source>` | -- | ソースファイルを宛先に追記 | Yes |
| `filesearch` | `<filepath> <pattern>` | -- | ファイル内を検索 | Yes |
| `fileseek` | `<handle> <offset>` | -- | 指定位置にシーク | Yes |
| `fileseekback` | `<handle> <bytes>` | -- | 後方にシーク | Yes |
| `filemarkptr` | `<handle>` | -- | 現在位置にマーカーを設定 | Yes |
| `filestrseek` | `<handle> <string>` | `result`: 1=検出, 0=未検出 | ファイル内を前方検索してシーク | Yes |
| `filestrseek2` | `<handle> <string>` | `result`: 1=検出, 0=未検出 | ファイル内を後方検索してシーク | Yes |
| `filestat` | `<filepath> <sizevar>` | -- | ファイルサイズ（バイト）を取得 | Yes |
| `filetruncate` | `<handle>` | -- | 現在位置でファイルを切り詰め | Yes |
| `filelock` | `<handle>` | -- | ファイルをロック（macOS ではスタブ） | Yes（スタブ） |
| `fileunlock` | `<handle>` | -- | ファイルをアンロック（macOS ではスタブ） | Yes（スタブ） |

### ディレクトリ

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `findfirst` | `<namevar> <pattern>` | `result`: 0=検出, -1=なし | ファイル検索を開始 | Yes |
| `findnext` | `<namevar>` | `result`: 0=検出, -1=なし | ファイル検索を継続 | Yes |
| `findclose` | -- | -- | ファイル検索を終了 | Yes |
| `foldercreate` | `<path>` | -- | ディレクトリを作成 | Yes |
| `folderdelete` | `<path>` | -- | ディレクトリを削除 | Yes |
| `foldersearch` | `<namevar> <pattern>` | -- | ディレクトリを検索 | Yes |
| `changedir` | `<path>` | -- | カレントディレクトリを変更 | Yes |
| `makedir` | `<path>` | -- | ディレクトリを作成（エイリアス） | Yes |
| `basename` | `<namevar> <path>` | -- | パスからファイル名を抽出 | Yes |
| `dirname` | `<dirvar> <path>` | -- | パスからディレクトリを抽出 | Yes |
| `makepath` | `<pathvar> <dir> <filename>` | -- | ディレクトリとファイル名を結合 | Yes |
| `getdir` | `<dirvar>` | -- | カレントディレクトリを取得 | Yes |
| `setdir` | `<path>` | -- | カレントディレクトリを設定 | Yes |

### 接続

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `connect` | `<hoststring>` | `result`: 1=成功, 0=失敗 | 接続を確立 | Yes |
| `disconnect` | -- | -- | 切断 | Yes |
| `cygconnect` | -- | `result`: 1=成功, 0=失敗 | ローカルシェル（PTY）接続を開く。macOS では Cygwin の代わりにローカルシェルに接続 | 部分（macOS 適応） |
| `testlink` | -- | `result`: 0=未リンク, 1=リンク済み・未接続, 2=リンク済み・接続中 | リンク状態と接続状態をテスト。XPC 接続状態（linked）とホスト接続状態（connected）を個別に判定する | Yes |
| `unlink` | -- | -- | マクロとターミナルのリンクを切断。未接続時はエラーにならない | Yes |

### 待機

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `wait` | `<pattern1> [<pattern2>...<pattern10>]` | `result`: 0=タイムアウト, 1-10=マッチしたパターン番号 | 最大 10 パターンを待機 | Yes |
| `waitln` | `<pattern1> [<pattern2>...<pattern10>]` | `result`: 0=タイムアウト, 1+=パターン番号; `inputstr`: マッチ行 | 行単位でパターンを待機 | Yes |
| `waitrecv` | -- | -- | データ受信を待機 | Yes |
| `waitregex` | `<regex>` | `matchstr`: 全体マッチ; `groupmatchstr1..N`: キャプチャグループ | 正規表現マッチを待機 | Yes |
| `waitn` | `<bytecount>`（整数） | -- | 指定バイト数の受信を待機 | Yes |
| `wait4all` | `<pattern1> [<pattern2>...]` | -- | 全パターンが出現するまで待機（順序不問） | Yes |
| `waitevent` | -- | -- | ターミナルイベントを待機 | Yes |
| `pause` | `<seconds>`（整数） | -- | 指定秒数一時停止 | Yes |
| `mpause` | `<milliseconds>`（整数） | -- | 指定ミリ秒一時停止 | Yes |

### アプリ制御

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `closett` | -- | -- | ターミナルウィンドウを閉じる | Yes |
| `show` | `<flag>`（整数） | -- | ウィンドウを表示（1）または非表示（0） | Yes |
| `showtt` | `<flag>`（整数） | -- | ターミナルの表示/非表示（エイリアス） | Yes |
| `getver` | `<intvar>` | -- | バージョン番号を取得（major*10000 + minor*100 + patch） | Yes |
| `getttdir` | `<strvar>` | -- | アプリケーションディレクトリを取得 | Yes |
| `getttpos` | `<xvar> <yvar>` | -- | ターミナルウィンドウの位置を取得 | Yes |
| `enablekeyb` | `<flag>`（整数） | -- | キーボードを有効（1）または無効（0）にする | Yes |
| `settitle` | `<title>`（文字列） | -- | ターミナルウィンドウのタイトルを設定 | Yes |
| `gettitle` | `<strvar>` | -- | ターミナルウィンドウのタイトルを取得 | Yes |
| `clearscreen` | -- | -- | ターミナル画面をクリア | Yes |
| `dispstr` | `<string>` | -- | ターミナル画面に文字列を表示（送信はしない） | Yes |

### システム

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `exec` | `<command>`（文字列） | `result`: 終了コード; `inputstr`: 標準出力 | シェルコマンドを実行 | Yes |
| `execcmnd` | `<ttlcommand>`（文字列） | -- | TTL コマンド文字列を動的に実行 | Yes |
| `getenv` | `<name> <strvar>` | -- | 環境変数を取得 | Yes |
| `setenv` | `<name> <value>` | -- | 環境変数を設定 | Yes |
| `expandenv` | `<strvar>` | -- | 文字列中の `%VARNAME%` を展開 | Yes |
| `getdate` | `<strvar>` | -- | 現在日付を取得（`yyyy/MM/dd`） | Yes |
| `gettime` | `<strvar>` | -- | 現在時刻を取得（`HH:mm:ss`） | Yes |
| `setdate` | `<datestr>` | `result`: 0=成功, -1=失敗 | システム日付を設定。macOS では常に失敗（root 権限が必要） | Yes（macOS スタブ） |
| `settime` | `<timestr>` | `result`: 0=成功, -1=失敗 | システム時刻を設定。macOS では常に失敗（root 権限が必要） | Yes（macOS スタブ） |
| `gethostname` | `<strvar>` | -- | ホスト名を取得 | Yes |
| `getspecialfolder` | `<strvar> <folderid>` | -- | 特殊フォルダのパスを取得。0=デスクトップ, 1=App Support, 2=書類, 3=ダウンロード | Yes |
| `getipv4addr` | `<strvar>` | -- | IPv4 アドレスを取得 | Yes |
| `getipv6addr` | `<strvar>` | -- | IPv6 アドレスを取得 | Yes |
| `getfileattr` | `<filepath> <intvar>` | -- | ファイル属性を取得（bit 0=読み取り専用, bit 4=ディレクトリ） | Yes |
| `setfileattr` | `<filepath> <attr>` | -- | ファイル属性を設定 | Yes |
| `getmodemstatus` | `<intvar>` | -- | モデム状態を取得（macOS ではスタブ、常に 0 を返す） | Yes（スタブ） |
| `uptime` | `<intvar>` | -- | システム稼働時間を秒で取得 | Yes |
| `clipb2var` | `<strvar>` | -- | クリップボードの内容を変数にコピー | Yes |
| `var2clipb` | `<string>` | -- | 値をクリップボードにコピー | Yes |

### ログ

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `logopen` | `<filepath> <mode>` | -- | ログファイルを開く。mode: 0=新規, 1=追記 | Yes |
| `logclose` | -- | -- | ログファイルを閉じる | Yes |
| `logpause` | -- | -- | ログ記録を一時停止 | Yes |
| `logstart` | -- | -- | ログ記録を再開 | Yes |
| `logwrite` | `<text>`（文字列） | -- | ログファイルにテキストを書き込み | Yes |
| `loginfo` | -- | -- | ログ情報を取得 | Yes |
| `logrotate` | -- | -- | ログファイルをローテーション | Yes |
| `logautoclosemode` | `<mode>`（整数） | -- | ログ自動クローズモードを設定 | Yes |

### シリアル

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `setbaud` | `<baudrate>`（整数） | -- | ボーレートを設定（例: 115200） | Yes |
| `setflowctrl` | `<mode>`（整数） | -- | フロー制御を設定。0=なし, 1=XON/XOFF, 2=ハードウェア | Yes |
| `setdtr` | `<flag>`（整数） | -- | DTR 信号を設定 | Yes |
| `setrts` | `<flag>`（整数） | -- | RTS 信号を設定 | Yes |
| `sendbreak` | -- | -- | ブレーク信号を送信 | Yes |
| `setserialdelaychar` | `<ms>`（整数） | -- | 文字間遅延をミリ秒で設定 | Yes |
| `setserialdelayline` | `<ms>`（整数） | -- | 行間遅延をミリ秒で設定 | Yes |

### ファイル転送

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `bplusrecv` | -- | `result`: 0=成功, 1=失敗 | B Plus 受信 | Yes |
| `bplussend` | `<filepath>` | `result`: 0=成功, 1=失敗 | B Plus 送信 | Yes |
| `kmtget` | `<remotefile>` | `result`: 0=成功, 1=失敗 | Kermit サーバーにファイルを要求 | Yes |
| `kmtrecv` | -- | `result`: 0=成功, 1=失敗 | Kermit 受信 | Yes |
| `kmtsend` | `<filepath>` | `result`: 0=成功, 1=失敗 | Kermit 送信 | Yes |
| `kmtfinish` | -- | `result`: 0=成功, 1=失敗 | Kermit サーバーモード終了 | Yes |
| `xmodemrecv` | `<filepath> <binary> <option>` | `result`: 0=成功, 1=失敗 | XMODEM 受信。option: 1=Checksum, 2=CRC, 3=1K | Yes |
| `xmodemsend` | `<filepath> <option>` | `result`: 0=成功, 1=失敗 | XMODEM 送信。option: 2=CRC, 3=1K | Yes |
| `ymodemrecv` | -- | `result`: 0=成功, 1=失敗 | YMODEM 受信 | Yes |
| `ymodemsend` | `<filepath>` | `result`: 0=成功, 1=失敗 | YMODEM 送信 | Yes |
| `zmodemrecv` | -- | `result`: 0=成功, 1=失敗 | ZMODEM 受信 | Yes |
| `zmodemsend` | `<filepath> <binary>` | `result`: 0=成功, 1=失敗 | ZMODEM 送信 | Yes |
| `quickvanrecv` | -- | `result`: 0=成功, 1=失敗 | Quick VAN 受信 | Yes |
| `quickvansend` | `<filepath>` | `result`: 0=成功, 1=失敗 | Quick VAN 送信 | Yes |
| `scprecv` | `<remotepath> [<localpath>]` | `result`: 0=成功, 1=失敗 | SCP 受信（SSH 接続が必要） | Yes |
| `scpsend` | `<localpath> [<remotepath>]` | `result`: 0=成功, 1=失敗 | SCP 送信（SSH 接続が必要） | Yes |
| `recvfile` | `<filepath> <binary> <autostop_sec>` | `result`: 0=成功, 1=失敗 | データをファイルに受信。autostop: 0=無制限 | Yes |
| `protocolrecv` | `<protocol> [<args>...]` | -- | 汎用プロトコル受信 | Yes |
| `protocolsend` | `<protocol> [<args>...]` | -- | 汎用プロトコル送信 | Yes |

### セキュリティ

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `getpassword` | `<strvar> <prompt>` | -- | パスワードを取得（macOS ではスタブ） | Yes（スタブ） |
| `setpassword` | `<name> <password>` | -- | パスワードを保存（macOS ではスタブ） | Yes（スタブ） |
| `delpassword` | `<name>` | -- | パスワードを削除（macOS ではスタブ） | Yes（スタブ） |
| `ispassword` | `<name>` | `result`: 1=存在, 0=不存在 | パスワードの存在確認（macOS ではスタブ） | Yes（スタブ） |
| `getpassword2` | `<strvar> <prompt>` | -- | パスワード取得バリアント 2（macOS ではスタブ） | Yes（スタブ） |
| `setpassword2` | `<name> <password>` | -- | パスワード保存バリアント 2（macOS ではスタブ） | Yes（スタブ） |
| `delpassword2` | `<name>` | -- | パスワード削除バリアント 2（macOS ではスタブ） | Yes（スタブ） |
| `ispassword2` | `<name>` | `result`: 1=存在, 0=不存在 | パスワード存在確認バリアント 2（macOS ではスタブ） | Yes（スタブ） |

### その他

| コマンド | 引数 | 戻り値 | 説明 | オリジナル TT 互換 |
|---------|------|--------|------|:------------------:|
| `beep` | -- | -- | システムビープ音を再生 | Yes |
| `setdebug` | `<flag>`（整数） | -- | デバッグモードの有効（1）/無効（0） | Yes |
| `setecho` | `<flag>`（整数） | -- | ローカルエコーの有効（1）/無効（0） | Yes |
| `setsync` | `<flag>`（整数） | -- | 同期モードを設定 | Yes |
| `setexitcode` | `<code>`（整数） | -- | マクロ終了コードを設定 | Yes |
| `restoresetup` | `<filepath>` | -- | ファイルからターミナル設定を復元 | Yes |
| `loadkeymap` | `<filepath>` | -- | キーボード設定ファイル（.cnf）を読み込み。文字コード自動判定 | Yes |
| `callmenu` | `<menuid>`（整数） | -- | メニューコマンドを ID で呼び出し | Yes |
| `regexoption` | `<flags>`（整数） | -- | 正規表現オプションを設定。bit 0 = 大文字小文字無視 | Yes |
| `rotateleft` | `<intvar> <bits>` | -- | ビット左回転 | Yes |
| `rotateright` | `<intvar> <bits>` | -- | ビット右回転 | Yes |
| `crc16` | `<intvar> <string>` | -- | 文字列の CRC-16 を計算 | Yes |
| `crc16file` | `<intvar> <filepath>` | -- | ファイルの CRC-16 を計算 | Yes |
| `crc32` | `<intvar> <string>` | -- | 文字列の CRC-32 を計算 | Yes |
| `crc32file` | `<intvar> <filepath>` | -- | ファイルの CRC-32 を計算 | Yes |
| `checksum8` | `<intvar> <string>` | -- | 文字列の 8 ビットチェックサムを計算 | Yes |
| `checksum8file` | `<intvar> <filepath>` | -- | ファイルの 8 ビットチェックサムを計算 | Yes |
| `checksum16` | `<intvar> <string>` | -- | 文字列の 16 ビットチェックサムを計算 | Yes |
| `checksum16file` | `<intvar> <filepath>` | -- | ファイルの 16 ビットチェックサムを計算 | Yes |
| `checksum32` | `<intvar> <string>` | -- | 文字列の 32 ビットチェックサムを計算 | Yes |
| `checksum32file` | `<intvar> <filepath>` | -- | ファイルの 32 ビットチェックサムを計算 | Yes |
| `sendbroadcast` | `<string>` | -- | 全セッションに送信（スタブ） | Yes（スタブ） |
| `sendmulticast` | `<string>` | -- | マルチキャストグループに送信（スタブ） | Yes（スタブ） |
| `setmulticastname` | `<groupname>` | -- | マルチキャストグループ名を設定（スタブ） | Yes（スタブ） |
| `sendlnbroadcast` | `<string>` | -- | 全セッションに文字列 + CR を送信（スタブ） | Yes（スタブ） |
| `sendlnmulticast` | `<string>` | -- | マルチキャストグループに文字列 + CR を送信（スタブ） | Yes（スタブ） |

---

## XPC プロトコル定義

XPC サービス名: `com.yourapp.TeraTermMac.TTLMacro.xpc`

### MacroServiceProtocol（TeraTermMac --> TTLMacro）

マクロ実行エンジンを制御する。`MacroServiceProtocol.swift` で定義。

| メソッド | 引数 | 応答 | 説明 |
|---------|------|------|------|
| `runMacro` | `scriptPath: String` | `(NSError?) -> Void` | マクロスクリプトファイルを実行 |
| `stopMacro` | -- | `() -> Void` | 実行中のマクロを強制停止 |
| `pauseMacro` | -- | `() -> Void` | 実行中のマクロを一時停止 |
| `resumeMacro` | -- | `() -> Void` | 一時停止中のマクロを再開 |
| `macroStatus` | -- | `(String) -> Void` | 現在のマクロ実行状態を取得 |
| `sendVariable` | `name: String, value: String` | `() -> Void` | マクロ環境に変数を渡す |

### MacroClientProtocol（TTLMacro --> TeraTermMac）

マクロエンジンからターミナルへのコールバック。`MacroClientProtocol.swift` で定義。

| メソッド | 引数 | 応答 | 説明 |
|---------|------|------|------|
| `sendToTerminal` | `data: Data` | --（oneway） | ターミナルにデータを送信 |
| `recvFromTerminal` | `timeout: Int` | `(Data?) -> Void` | タイムアウト付きでターミナルからデータを受信 |
| `showDialog` | `type: String, message: String, defaultValue: String` | `(Int, String) -> Void` | ダイアログを表示してユーザー応答を取得 |
| `setWindowTitle` | `title: String` | --（oneway） | ターミナルウィンドウのタイトルを設定 |
| `macroDidFinish` | `exitCode: Int` | --（oneway） | マクロ正常完了を通知 |
| `macroDidFail` | `error: String, line: Int` | --（oneway） | エラー情報付きでマクロ失敗を通知 |
| `logMessage` | `level: String, text: String` | --（oneway） | ターミナルにログメッセージを送信 |
| `terminateApp` | -- | `() -> Void` | ターミナルアプリの終了を要求 |
| `getAppVersion` | -- | `(String) -> Void` | ターミナルアプリのバージョン文字列を取得 |
| `didExecuteLine` | `lineNumber: Int, lineText: String` | `() -> Void` | ステータスバー更新用の行実行通知 |

---

## 通信仕様

### XPC 型制限

XPC 接続で許可される型:

- `String`（NSString）
- `Data`（NSData）
- `NSNumber`（Int, Bool, Double）
- `NSArray`
- `NSDictionary`

### 応答クロージャ

すべてのプロトコルメソッドは非同期通信に応答クロージャを使用する。oneway メソッド（`sendToTerminal`, `setWindowTitle`, `macroDidFinish`, `macroDidFail`, `logMessage`）は応答を必要としない。

### 再接続ポリシー

- 最大再接続試行回数: **3 回**
- 試行間隔: **2 秒**
- 再接続失敗時: 適切なエラーメッセージで `macroDidFail(error:line:)` を呼び出す
- XPC 接続は `interruptionHandler` と `invalidationHandler` で切断を検出する

### 実行状態

マクロエンジンは以下の状態を管理する（`MacroExecutionState` で定義）:

| 状態 | 説明 |
|------|------|
| `idle` | マクロ未読み込みまたは実行準備完了 |
| `running` | マクロ実行中 |
| `paused` | マクロ一時停止中（再開可能） |
| `stopped` | ユーザーによりマクロ停止 |
| `error` | エラーによりマクロ終了 |

### ダイアログ種別

共有ダイアログ種別定数（`MacroDialogType` で定義）:

| 種別 | 説明 |
|------|------|
| `messagebox` | メッセージ表示（OK のみ） |
| `inputbox` | テキスト入力 |
| `yesnobox` | Yes/No 確認 |
| `passwordbox` | マスク付きパスワード入力 |
| `listbox` | リスト選択 |
| `filenamebox` | ファイル選択 |
| `dirnamebox` | フォルダ選択 |
| `statusbox` | 非モーダルステータス表示 |

---

## ローカライズキー

すべてのローカライズキーは `TTLMacroShared/Resources/{en,ja}.lproj/Localizable.strings` で管理し、`MacroL()` ヘルパー関数でアクセスする。

### マクロ開くダイアログ

| キー | 英語 | 日本語 |
|------|------|--------|
| `macro.open.title` | Select Macro File | マクロファイルを選択 |
| `macro.open.prompt` | Run | 実行 |
| `macro.open.cancel` | Cancel | キャンセル |

### マクロ状態

| キー | 英語 | 日本語 |
|------|------|--------|
| `macro.status.running` | Running macro... | マクロ実行中... |
| `macro.status.paused` | Macro paused | マクロ一時停止中 |

### マクロエラー

| キー | 英語 | 日本語 |
|------|------|--------|
| `macro.error.noFile` | File not found | ファイルが見つかりません |
| `macro.error.cancelled` | Cancelled | キャンセルされました |
| `macro.error.syntaxError` | Syntax error | 構文エラー |

### 標準ダイアログボタン

| キー | 英語 | 日本語 |
|------|------|--------|
| `dialog.ok` | OK | OK |
| `dialog.cancel` | Cancel | キャンセル |
| `dialog.yes` | Yes | はい |
| `dialog.no` | No | いいえ |

### ステータスバーメニュー

| キー | 英語 | 日本語 |
|------|------|--------|
| `macro.menu.running` | Running | マクロ実行中 |
| `macro.menu.paused` | Paused | 一時停止中 |
| `macro.menu.lineNumber` | Line: %d | 実行行数: %d 行目 |
| `macro.menu.pause` | Pause | 一時停止 |
| `macro.menu.resume` | Resume | 再開 |
| `macro.menu.stop` | Stop | 中断 |
| `macro.menu.open` | Open Macro... | マクロを開く... |
| `macro.menu.quit` | Quit TTLMacro | TTLMacro を終了 |

### 停止確認

| キー | 英語 | 日本語 |
|------|------|--------|
| `macro.stop.confirm.title` | Stop macro? | マクロを中断しますか？ |
| `macro.stop.confirm.message` | The running macro will be stopped. | 実行中のマクロを中断します。 |
| `macro.stop.confirm.stop` | Stop | 中断 |
| `macro.stop.confirm.cancel` | Cancel | キャンセル |

---

## ファイル構成

```
TeraTermMac/
├── Package.swift（変更）
├── Sources/
│   ├── TeraTermMac/（既存、XPC クライアント追加）
│   │   ├── App/
│   │   │   └── MacroXPCManager.swift（新規）
│   │   └── Macro/（既存）
│   ├── TTLMacroShared/（新規 - 共有モジュール）
│   │   ├── MacroServiceProtocol.swift
│   │   ├── MacroClientProtocol.swift
│   │   ├── MacroLocalizable.swift
│   │   ├── MacroDialogHelper.swift
│   │   └── Resources/
│   │       ├── en.lproj/Localizable.strings
│   │       └── ja.lproj/Localizable.strings
│   └── TTLMacro/（新規 - マクロアプリ）
│       ├── main.swift
│       ├── TTLMacroApp.swift
│       ├── XPCServiceDelegate.swift
│       ├── StatusBarController.swift
│       ├── Info.plist
│       ├── TTLMacro.entitlements
│       └── Resources/
│           └── Assets.xcassets/
│               └── AppIcon.appiconset/
├── Tests/
│   └── TTLMacroTests/
│       ├── XPCConnectionTests.swift
│       ├── LaunchFlowTests.swift
│       ├── MacroCommandTests.swift
│       ├── StatusBarTests.swift
│       └── ...
└── TestMacros/
    ├── test_string.ttl
    ├── test_control.ttl
    └── ...
```

---

## TTLInterpreterDelegate → XPC マッピング表

TTLInterpreterDelegate の全メソッドと XPC プロトコルの対応。

処理場所:
- **TTLMacro 側**: MacroRunner / TTLMacro.app 内のローカル実行で完結
- **TeraTermMac 側**: XPC MacroClientProtocol 経由で TeraTermMac.app に委譲
- **共通**: 両側が関与

| # | delegate メソッド名 | XPC プロトコル | 処理場所 | 備考 |
|---|---|---|---|---|
| 1 | `ttlSendData(_ data: Data)` | `sendToTerminal(data:reply:)` | TeraTermMac 側 | バイナリデータ送信 |
| 2 | `ttlSendString(_ text: String)` | `sendToTerminal(data:reply:)` | TeraTermMac 側 | UTF-8 エンコードして Data 送信 |
| 3 | `ttlSendLine(_ text: String)` | `sendToTerminal(data:reply:)` | TeraTermMac 側 | text+CR を Data 送信 |
| 4 | `ttlIsConnected() -> Bool` | `isConnected(reply:)` | TeraTermMac 側 | ホスト接続状態確認 |
| 5 | `ttlGetReceivedData(clear:) -> String` | `recvFromTerminal(timeout:reply:)` | TeraTermMac 側 | 受信バッファ取得 |
| 6 | `ttlFlushReceiveBuffer()` | `flushReceiveBuffer(reply:)` | TeraTermMac 側 | バッファクリア |
| 7 | `ttlDisconnect()` | `disconnectFromHost(reply:)` | TeraTermMac 側 | 切断 |
| 8 | `ttlConnect(_ param: String)` | `connectToHost(param:reply:)` | TeraTermMac 側 | 接続 |
| 9 | `ttlConnectLocalShell()` | `connectLocalShell(reply:)` | TeraTermMac 側 | ローカルシェル（PTY）接続 |
| 10 | `ttlSetTitle(_ title: String)` | `setWindowTitle(title:reply:)` | TeraTermMac 側 | ウィンドウタイトル設定 |
| 11 | `ttlGetTitle() -> String` | `getWindowTitle(reply:)` | TeraTermMac 側 | ウィンドウタイトル取得 |
| 12 | `ttlShowWindow(_ show: Bool)` | `showWindow(visible:reply:)` | TeraTermMac 側 | 表示/非表示 |
| 13 | `ttlClearScreen()` | `clearScreen(reply:)` | TeraTermMac 側 | 画面クリア |
| 14 | `ttlSendBreak()` | `sendBreak(reply:)` | TeraTermMac 側 | ブレーク信号送信 |
| 15 | `ttlLogOpen(_ path:append:)` | `openLog(path:append:reply:)` | TeraTermMac 側 | ログファイルオープン |
| 16 | `ttlLogClose()` | `closeLog(reply:)` | TeraTermMac 側 | ログファイルクローズ |
| 17 | `ttlLogPause()` | `pauseLog(reply:)` | TeraTermMac 側 | ログ一時停止 |
| 18 | `ttlLogStart()` | `resumeLog(reply:)` | TeraTermMac 側 | ログ再開 |
| 19 | `ttlLogWrite(_ text: String)` | `writeToLog(text:reply:)` | TeraTermMac 側 | ログ書き込み |
| 20 | `ttlLogInfo() -> (state:filePath:)` | `getLogInfo(reply:)` | TeraTermMac 側 | ログ情報取得 |
| 21 | `ttlLogRotateSet(mode:value:)` | `setLogRotation(mode:value:reply:)` | TeraTermMac 側 | ログローテーション設定 |
| 22 | `ttlShowError(message:line:lineText:fileName:completion:)` | `showError(message:line:lineText:fileName:reply:)` | TeraTermMac 側 | エラーダイアログ表示 |
| 23 | `ttlShowStatusBox(message:title:)` | `showStatusBox(message:title:reply:)` | TeraTermMac 側 | ステータスボックス表示 |
| 24 | `ttlCloseStatusBox()` | `closeStatusBox(reply:)` | TeraTermMac 側 | ステータスボックスを閉じる |
| 25 | `ttlGetClipboard() -> String` | `getClipboard(reply:)` | TeraTermMac 側 | クリップボード取得 |
| 26 | `ttlSetClipboard(_ text: String)` | `setClipboard(text:reply:)` | TeraTermMac 側 | クリップボード設定 |
| 27 | `ttlSetBaud(_ baud: Int)` | `setBaudRate(rate:reply:)` | TeraTermMac 側 | ボーレート設定 |
| 28 | `ttlSetFlowCtrl(_ mode: Int)` | `setFlowControl(mode:reply:)` | TeraTermMac 側 | フロー制御設定 |
| 29 | `ttlSetDtr(_ on: Int)` | `setDtr(on:reply:)` | TeraTermMac 側 | DTR 信号設定 |
| 30 | `ttlSetRts(_ on: Int)` | `setRts(on:reply:)` | TeraTermMac 側 | RTS 信号設定 |
| 31 | `ttlStartFileTransfer(protocol:direction:filePath:completion:)` | `startFileSend/startFileRecv` | TeraTermMac 側 | ファイル転送開始 |
| 32 | `ttlKermitGet(remoteFileName:localPath:completion:)` | `startFileRecv(protocolName:"kermit"...)` | TeraTermMac 側 | Kermit GET |
| 33 | `ttlKermitFinish(completion:)` | `cancelTransfer(reply:)` | TeraTermMac 側 | Kermit FINISH |
| 34 | `ttlScpSend(localPath:remotePath:completion:)` | `scpSend(localPath:remotePath:reply:)` | TeraTermMac 側 | SCP 送信 |
| 35 | `ttlScpRecv(remotePath:localPath:completion:)` | `scpRecv(remotePath:localPath:reply:)` | TeraTermMac 側 | SCP 受信 |
| 36 | `ttlRecvFile(filePath:binary:autoStopSec:completion:)` | `startFileRecv(protocolName:"raw"...)` | TeraTermMac 側 | ファイル受信 |
| 37 | `ttlRestoreSetup(from path: String)` | `restoreSetup(path:reply:)` | TeraTermMac 側 | 設定復元 |
| 38 | `ttlCallMenu(menuId: Int)` | `callMenu(menuId:reply:)` | TeraTermMac 側 | メニュー呼び出し |
| 39 | `ttlSetSerialDelayChar(_ ms: Int)` | `setSerialDelayChar(ms:reply:)` | TeraTermMac 側 | 文字送信遅延設定 |
| 40 | `ttlSetSerialDelayLine(_ ms: Int)` | `setSerialDelayLine(ms:reply:)` | TeraTermMac 側 | 行送信遅延設定 |
| 41 | `ttlLoadKeyMap(from path: String)` | `loadKeyMap(path:reply:)` | TeraTermMac 側 | キーマップ読み込み |

### 追加 XPC メソッド（オリジナル delegate にないもの）

| # | XPC メソッド名 | 処理場所 | 備考 |
|---|---|---|---|
| 42 | `macroDidFinish(exitCode:reply:)` | TeraTermMac 側 | マクロ正常完了通知 |
| 43 | `macroDidFail(error:line:reply:)` | TeraTermMac 側 | マクロエラー通知 |
| 44 | `logMessage(level:text:reply:)` | TeraTermMac 側 | ログメッセージ送信 |
| 45 | `terminateApp(reply:)` | TeraTermMac 側 | アプリ終了要求 |
| 46 | `getAppVersion(reply:)` | TeraTermMac 側 | バージョン取得 |
| 47 | `didExecuteLine(lineNumber:lineText:reply:)` | TeraTermMac 側 | 行実行通知 |
| 48 | `moveWindow(x:y:reply:)` | TeraTermMac 側 | ウィンドウ移動 |
| 49 | `resizeWindow(width:height:reply:)` | TeraTermMac 側 | ウィンドウリサイズ |
| 50 | `bringWindowToFront(reply:)` | TeraTermMac 側 | ウィンドウ前面移動 |
| 51 | `getWindowPosition(reply:)` | TeraTermMac 側 | ウィンドウ位置取得 |
| 52 | `getModemStatus(reply:)` | TeraTermMac 側 | モデム状態取得 |
| 53 | `getClipboard(reply:)` | TeraTermMac 側 | クリップボード取得 |
| 54 | `setClipboard(text:reply:)` | TeraTermMac 側 | クリップボード設定 |
| 55 | `getHostname(reply:)` | TeraTermMac 側 | ホスト名取得 |
| 56 | `getAppDirectory(reply:)` | TeraTermMac 側 | アプリディレクトリ取得 |
| 57 | `showDialog(type:message:defaultValue:reply:)` | TeraTermMac 側 | ダイアログ表示 |
| 58 | `getTransferStatus(reply:)` | TeraTermMac 側 | 転送状態取得 |
| 59 | `cancelTransfer(reply:)` | TeraTermMac 側 | 転送キャンセル |
| 60 | `enableKeyboard(flag:reply:)` | TeraTermMac 側 | キーボード有効/無効 |
| 61 | `setEcho(flag:reply:)` | TeraTermMac 側 | ローカルエコー設定 |
| 62 | `displayString(text:reply:)` | TeraTermMac 側 | 端末表示（非送信） |
| 63 | `sendPasswordData(data:reply:)` | TeraTermMac 側 | パスワード安全送信 |

### testlink の実装方式

`testlink` コマンドはリンク状態とホスト接続状態の 2 段階を判定する。XPC アーキテクチャにおいて、オリジナル Tera Term の DDE リンクに相当する状態を自然に再現できる。

| result | 状態 | 判定方法 |
|:------:|------|----------|
| 0 | 未リンク（TTLMacro ↔ TeraTermMac 間の XPC 接続が未確立） | XPC connection が nil または invalidated |
| 1 | リンク済み・未接続（XPC 接続はあるがホスト未接続） | XPC connection が有効 かつ `isConnected(reply:)` が false |
| 2 | リンク済み・接続中（XPC 接続あり かつ ホスト接続あり） | XPC connection が有効 かつ `isConnected(reply:)` が true |

```
TTLMacro.app                          TeraTermMac.app
    |                                       |
    | 1. XPC connection 状態を確認           |
    |    connection == nil → result=0        |
    |                                       |
    | 2. XPC 経由で接続状態を問い合わせ       |
    | --- isConnected(reply:) -------------> |
    | <-- reply(false) -------------------- |  → result=1
    | <-- reply(true) --------------------- |  → result=2
```

> **オリジナル TT との対応**: オリジナルでは `Linked`（DDE リンク状態）と `ComReady`（通信ポート接続状態）の 2 変数で管理。teraterm_mac では XPC 接続状態が `Linked` に、`isConnected` の結果が `ComReady` に対応する。

### TTLMacro 側で完結するコマンド（XPC 不要）

| コマンドカテゴリ | コマンド | 備考 |
|---|---|---|
| 制御フロー | if/else/elseif/endif/for/next/while/endwhile/do/loop/until/enduntil/break/continue/goto/call/return/include/end/exit/ifdefined | パーサー内で完結 |
| 文字列操作 | strlen/strconcat/strcopy/strcompare/strscan/strmatch/str2int/int2str/str2code/code2str/strinsert/strremove/strreplace/strspecial/strtrim/strsplit/strjoin/tolower/toupper/sprintf/sprintf2 | 変数操作のみ |
| ファイル I/O | fileopen/fileclose/fileread/filereadln/filewrite/filewriteln/filecreate/filedelete/filecopy/filerename/fileconcat/filesearch/fileseek/fileseekback/filemarkptr/filestat/filetruncate/filestrseek/filestrseek2/filelock/fileunlock | FileHandle 直接操作 |
| ディレクトリ | findfirst/findnext/findclose/foldercreate/folderdelete/foldersearch/changedir/makepath/basename/dirname/getdir/setdir | FileManager 直接操作 |
| 配列 | intdim/strdim | 変数管理のみ |
| 日時/環境 | getdate/gettime/getenv/setenv/expandenv/random/uptime | Foundation API |
| チェックサム | crc16/crc32/checksum8/checksum16/checksum32（+file 版） | 計算のみ |
| ビット操作 | rotateleft/rotateright | 計算のみ |
| その他 | beep/setdebug/regexoption/setdlgpos/setexitcode/exec/execcmnd/pause/mpause | ローカル処理 |
| Keychain | getpassword/setpassword/delpassword/ispassword（+2 バリアント） | Security.framework |

---

## XPC 接続方式の変更仕様

### Anonymous Listener による接続フロー

従来の `NSXPCConnection(serviceName:)` を廃止し、anonymous listener + endpoint 共有方式に変更。

```
1. TeraTermMac.app が TTLMacro.app を起動
   NSWorkspace.shared.openApplication(at: macroAppURL, configuration: config)
   引数: "--xpc-mode"

2. TTLMacro.app が anonymous listener を作成
   let listener = NSXPCListener.anonymous()
   listener.delegate = self
   listener.resume()

3. TTLMacro.app が endpoint をシリアライズして一時ファイルに書き出し
   let endpoint = listener.endpoint  // NSXPCListenerEndpoint
   let data = try NSKeyedArchiver.archivedData(withRootObject: endpoint,
                                                requiringSecureCoding: true)
   try data.write(to: URL(fileURLWithPath: endpointFilePath))
   // endpointFilePath: /tmp/ttlmacro_endpoint_{PID}.dat

4. TeraTermMac.app が一時ファイルをポーリングで検出（0.2 秒間隔、最大 10 秒）
   let data = FileManager.default.contents(atPath: endpointFilePath)
   let endpoint = try NSKeyedUnarchiver.unarchivedObject(
       ofClass: NSXPCListenerEndpoint.self, from: data)

5. TeraTermMac.app が endpoint から NSXPCConnection を生成
   let connection = NSXPCConnection(listenerEndpoint: endpoint)
   connection.remoteObjectInterface = MacroXPCInterface.serviceInterface()
   connection.exportedInterface = MacroXPCInterface.clientInterface()
   connection.exportedObject = self
   connection.resume()

6. 一時ファイルを削除（接続確立後に両側で試みる）
```

### タイムアウト処理

- 接続確立タイムアウト: **10 秒**
- タイムアウト時: `macroDidFail(error: "XPC connection timeout", line: 0)` を呼び出し
- ポーリング間隔: 0.2 秒

### セキュリティ考慮事項

- 一時ファイルのパーミッション: ユーザーのみ読み書き可（デフォルトの NSTemporaryDirectory）
- 一時ファイルは接続確立後に即削除
- anonymous listener は同一ユーザーのみ接続可能

---

## Keychain 連携仕様

### 保存するキー情報

| 項目 | 値 |
|---|---|
| kSecClass | kSecClassGenericPassword |
| kSecAttrService | `com.yourapp.TeraTermMac.TTLMacro` |
| kSecAttrAccount | `<host>:<username>`（例: `192.168.1.1:admin`） |
| kSecAttrAccessible | kSecAttrAccessibleWhenUnlockedThisDeviceOnly |

### service 名・account 名の命名規則

```
service: "com.yourapp.TeraTermMac.TTLMacro"（固定）
account: "<接続先ホスト>:<ユーザー名>"
  例: "192.168.1.1:admin"
  例: "server.example.com:root"
  例: "serial:COM3"（シリアル接続の場合）
```

### パスワード系コマンドと Keychain API のマッピング

| TTL コマンド | Keychain API | 動作 |
|---|---|---|
| `getpassword <strvar> <account>` | `SecItemCopyMatching` → ヒットしない場合はパスワード入力ダイアログ → `SecItemAdd` | 取得（+保存） |
| `setpassword <account> <password>` | `SecItemDelete` + `SecItemAdd` | 保存（上書き） |
| `delpassword <account>` | `SecItemDelete` | 削除 |
| `ispassword <account>` | `SecItemCopyMatching`（kSecReturnData=false） | 存在確認 |
| `getpassword2` | `getpassword` と同一実装 | 互換性エイリアス |
| `setpassword2` | `setpassword` と同一実装 | 互換性エイリアス |
| `delpassword2` | `delpassword` と同一実装 | 互換性エイリアス |
| `ispassword2` | `ispassword` と同一実装 | 互換性エイリアス |

### セキュリティ要件

1. パスワードを UserDefaults / ファイル / ログに書き込まないこと
2. XPC 通信では `sendPasswordData(data:reply:)` を使用し、`sendToTerminal` は使わない
3. 受信後即座にメモリから消去: `TTLKeychainManager.zeroData(&data)`
4. kSecAttrAccessibleWhenUnlockedThisDeviceOnly で iCloud Keychain 同期を防止

---

## ファイル転送 XPC フロー制御仕様

### XPC 追加メソッド一覧

| メソッド | 引数 | 返値 | 説明 |
|---|---|---|---|
| `startFileSend` | `protocolName: String, localPath: String, option: String` | `(Bool, String)` | 送信開始。成功/失敗+エラーメッセージ |
| `startFileRecv` | `protocolName: String, localDir: String` | `(Bool, String, String)` | 受信開始。成功/失敗+エラー+保存パス |
| `getTransferStatus` | -- | `(String, Int, Int)` | 状態+転送バイト+全体バイト |
| `cancelTransfer` | -- | `()` | 転送キャンセル |
| `scpSend` | `localPath: String, remotePath: String` | `(Bool)` | SCP 送信 |
| `scpRecv` | `remotePath: String, localPath: String` | `(Bool)` | SCP 受信 |

### protocolName 値

| 値 | プロトコル |
|---|---|
| `"xmodem"` | XMODEM（Checksum） |
| `"xmodem-crc"` | XMODEM-CRC |
| `"xmodem-1k"` | XMODEM-1K |
| `"ymodem"` | YMODEM |
| `"zmodem"` | ZMODEM |
| `"kermit"` | Kermit |
| `"bplus"` | B-Plus |
| `"quickvan"` | Quick-VAN |
| `"raw"` | Raw ファイル受信 |

### 送信シーケンス図（XMODEM/ZMODEM/Kermit 共通）

```
TTLMacro.app                          TeraTermMac.app
    |                                       |
    | --- startFileSend(proto,path,opt) --> |
    |                                       | ファイル転送エンジン起動
    | <-- reply(true, "") --------------- |
    |                                       |
    | --- getTransferStatus() -----------> | (0.5 秒ポーリング)
    | <-- reply("sending", 1024, 10240) -- |
    |                                       |
    | --- getTransferStatus() -----------> |
    | <-- reply("sending", 5120, 10240) -- |
    |                                       |
    | --- getTransferStatus() -----------> |
    | <-- reply("done", 10240, 10240) ---- |
    |                                       |
    | マクロ次行へ進む                       |
```

### 受信シーケンス図

```
TTLMacro.app                          TeraTermMac.app
    |                                       |
    | --- startFileRecv(proto,dir) -------> |
    |                                       | ファイル転送エンジン起動
    | <-- reply(true, "", "") ------------ |
    |                                       |
    | --- getTransferStatus() -----------> | (0.5 秒ポーリング)
    | <-- reply("receiving", 2048, 0) ---- | (totalBytes=0: 不明)
    |                                       |
    | --- getTransferStatus() -----------> |
    | <-- reply("done", 8192, 8192) ------ |
    |                                       |
    | マクロ次行へ進む                       |
```

### エラーシーケンス図

```
TTLMacro.app                          TeraTermMac.app
    |                                       |
    | --- startFileSend(proto,path,opt) --> |
    |                                       |
    | --- getTransferStatus() -----------> |
    | <-- reply("error", 0, 0) ---------- |
    |                                       |
    | macroDidFail("Transfer failed",N)    |
```

### タイムアウトと排他制御

- ポーリング間隔: 0.5 秒
- デフォルトタイムアウト: 600 秒（システム変数 `timeout` の値を参照）
- 待機中も `pause` / `stop` を受付（DispatchQueue 非同期ポーリング + キャンセルフラグ）
- 転送中に別の転送コマンド実行時: `macroDidFail(error: "Transfer already in progress", line: N)`
- TeraTermMac.app 側で `isTransferInProgress` フラグを管理
