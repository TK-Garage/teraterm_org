# TeraTerm Mac.app - 通信実装仕様

## 概要

TeraTerm Mac の通信レイヤーは、オリジナル Windows 版 `commlib.c` を Swift/macOS にポートしたものである。
TCP/IP（Telnet/SSH）、シリアルポート、ローカルシェル（PTY）の 4 種類の接続方式をサポートする。

ソースコード: `Sources/TeraTermMac/Communication/`

---

## アーキテクチャ

```
TerminalWindowController
    ↓ connect / disconnect / send
ConnectionManager (接続ファクトリ + デリゲート中継)
    ├── TCPConnection      (CFStream ベース TCP)
    ├── SSHConnection      (forkpty + /usr/bin/ssh)
    ├── SerialConnection   (POSIX termios)
    └── LocalShellConnection (forkpty + ユーザシェル)
        ↓ ConnectionDelegate
    TerminalWindowController → TerminalEmulator → TerminalView
```

### プロトコル定義

```swift
protocol Connection: AnyObject {
    var delegate: ConnectionDelegate? { get set }
    var state: ConnectionState { get }
    var isConnected: Bool { get }
    func connect()
    func disconnect()
    func send(_ data: Data)
    func send(_ string: String)
}

protocol ConnectionDelegate: AnyObject {
    func connectionDidConnect()
    func connectionDidDisconnect()
    func connectionDidReceiveData(_ data: Data)
    func connectionDidFail(error: Error)
    func connectionStateChanged(_ state: ConnectionState)
}
```

### 接続状態

```swift
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error(String)
}
```

---

## ConnectionManager

ファイル: `ConnectionManager.swift` (236行目まで)

設定 (`TerminalSettings`) に基づいて適切な `Connection` 実装を生成し、デリゲートを中継する。

### 主要メソッド

| メソッド | 説明 |
|---------|------|
| `connect(type:)` | ConnectionType enum で接続種別を指定して接続 |
| `connectWithSettings()` | 現在の TerminalSettings に基づき自動判定して接続 |
| `connectLocalShell()` | ローカルシェル接続（SHELL 環境変数 or 設定値） |
| `disconnect()` | 現在の接続を切断 |
| `send(_:)` | Data または String を送信 |
| `sendBreak()` | 接続種別に応じたブレーク信号送信 |
| `resetPort()` | 現在の接続を切断→同じパラメータで再接続 |

### 接続種別 (ConnectionType)

```swift
enum ConnectionType {
    case tcpip(host: String, port: Int)
    case serial(device: String, baudRate: Int, dataBits: Int,
                parity: Parity, stopBits: Int, flowControl: FlowControl)
    case localShell(command: String, arguments: [String],
                    environment: [String: String])
    case ssh(host: String, port: Int, username: String, password: String,
             authMethod: SSHAuthMethod, keyFile: String, forwardAgent: Bool)
}
```

---

## TCP 接続 (TCPConnection)

ファイル: `ConnectionManager.swift` (268行目〜)

### 実装方式

- `CFStreamCreatePairWithSocketToHost` で `InputStream`/`OutputStream` ペアを作成
- 接続待ち: 最大 10 秒 (100回 × 0.1秒) のポーリング
- 読み取り: 専用 `DispatchQueue`（`com.teraterm.tcp.read`）でブロッキングリード
- 書き込み: 専用 `DispatchQueue`（`com.teraterm.tcp.write`）で非同期書き込み

### バッファサイズ

| パラメータ | サイズ | 備考 |
|-----------|--------|------|
| 受信バッファ | 16,384 bytes (16KB) | オリジナル `CommInQueSize` と同一 |
| 送信リトライ | 最大 5,000 回 × 1ms | 約 5 秒の送信待ち猶予 |

### スレッドセーフティ

- `NSLock`（`stateLock`）で `_isRunning`、ストリーム参照を保護
- デリゲート通知は全て `DispatchQueue.main.async` 経由
- 切断重複防止フラグ (`_disconnected`)

### 送信処理

部分書き込みに対応したループ処理:

```
送信データ → writeQueue.async → output.write() ループ
  ├── n > 0: offset += n, リトライカウンタリセット
  ├── n == 0: 1ms スリープ後リトライ (最大5000回)
  └── n < 0: 書き込みエラー → disconnect
```

### エラー分類

`classifyStreamError()` によるきめ細かなエラー判定:

| エラー種別 | 判定基準 |
|-----------|---------|
| `hostNotFound` | DNS 解決失敗パターン文字列検出 |
| `connectionRefused` | `ECONNREFUSED` または文字列マッチ |
| `connectionTimeout` | `ETIMEDOUT` または文字列マッチ |
| `connectionFailed` | 上記以外の一般エラー |

---

## SSH 接続 (SSHConnection)

ファイル: `SSHConnection.swift`

### 実装方式

Windows 版の TTSSH プラグイン（libssh2 ベース）とは異なり、macOS システムの `/usr/bin/ssh` を PTY 経由で実行する方式を採用。

```
forkpty() → 子プロセス: execvp("/usr/bin/ssh", args)
         → 親プロセス: masterFD で PTY データストリーム読み書き
```

### 認証方式

| SSHAuthMethod | SSH オプション |
|---------------|---------------|
| `.password` | `PreferredAuthentications=password,keyboard-interactive`, PubkeyAuthentication=no |
| `.publicKey` | `-i keyFile`, `PreferredAuthentications=publickey` |
| `.challengeResponse` | `PreferredAuthentications=keyboard-interactive`, PubkeyAuthentication=no |
| `.pageant` | `PreferredAuthentications=publickey`（macOS ssh-agent 利用） |
| `.rhosts` | `PreferredAuthentications=hostbased` |

### SSH_ASKPASS メカニズム

パスワード/パスフレーズの自動入力に SSH_ASKPASS を利用:

1. 一時スクリプトを作成 (`/tmp/teraterm_askpass_<pid>_<ts>`)
2. スクリプト内容: `#!/bin/sh\nprintf '%s\n' '<password>'`
3. パーミッション: 0700（オーナーのみ実行可）
4. 環境変数設定: `SSH_ASKPASS`, `SSH_ASKPASS_REQUIRE=force`, `DISPLAY=:`
5. 認証完了後 10 秒で自動クリーンアップ

### セキュリティ対策

- **SecurePasswordBuffer**: パスワードを `UnsafeMutableBufferPointer` で管理
  - deinit 時にバイト単位でゼロクリア
  - Swift String の CoW によるメモリ残留を防止
- ASKPASS ファイル削除前に 256 バイトのゼロデータで上書き
- disconnect 時にパスワードバッファをゼロクリア

### SSH 引数構築

```
/usr/bin/ssh -tt                          # PTY 強制割り当て
    -p <port>                             # ポート指定
    -l <username>                         # ユーザ名
    -o StrictHostKeyChecking=accept-new   # 新規ホストキー自動承認
    -o ServerAliveInterval=60             # キープアライブ
    -o ServerAliveCountMax=3
    [-i <keyFile>]                        # 公開鍵ファイル
    [-A | -a]                             # エージェント転送
    <host>
```

### ブレーク送信

OpenSSH のエスケープシーケンスを利用: `CR` → 50ms 待ち → `~B`

### 接続通知

初回データ受信時に `connectionDidConnect()` を通知（子プロセスの生存確認を兼ねる）

### 終了コード処理

| 終了コード | 意味 |
|-----------|------|
| 0 | 正常終了 |
| 127 | ssh コマンドが見つからない |
| 255 | SSH 一般エラー（接続拒否、認証失敗等） |

---

## シリアル接続 (SerialConnection)

ファイル: `ConnectionManager.swift` (521行目〜)

### 実装方式

POSIX `termios` API による直接制御。

### 接続フロー

1. `open(device, O_RDWR | O_NOCTTY | O_NONBLOCK)`
2. `tcgetattr` で現在設定取得
3. ボーレート、データビット、パリティ、ストップビット、フロー制御を設定
4. Raw モード設定 (`ICANON`, `ECHO`, `ISIG` 無効化)
5. `CLOCAL | CREAD` 有効化
6. `VMIN=1`, `VTIME=0` 設定
7. `tcsetattr(TCSANOW)` で適用
8. `O_NONBLOCK` フラグ解除（ブロッキングリードに切替）

### バッファサイズ

| パラメータ | サイズ |
|-----------|--------|
| 受信バッファ | 4,096 bytes (4KB) |

### サポートボーレート

300, 600, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400

### パリティ設定

| Parity | c_cflag |
|--------|---------|
| `.none` | PARENB off |
| `.even` | PARENB on, PARODD off |
| `.odd` | PARENB on, PARODD on |

### フロー制御

| FlowControl | 設定 |
|-------------|------|
| `.hardware` | CRTSCTS on |
| `.xonXoff` | IXON, IXOFF on |
| `.none` | CRTSCTS off, IXON/IXOFF off |

### ブレーク送信

`tcsendbreak(fd, 0)` — 0.25〜0.5 秒間のブレーク信号

---

## ローカルシェル接続 (LocalShellConnection)

ファイル: `ConnectionManager.swift` (791行目〜)

### 実装方式

`forkpty()` で PTY ペアを作成し、ユーザ指定のシェルを実行。
Windows 版の Cygwin 接続に相当する macOS ネイティブ実装。

### 接続フロー

1. `forkpty(&masterFD, nil, nil, &winsize)` で PTY 作成 + フォーク
2. 子プロセス: 環境変数設定 → `TERM`/`LANG` 設定 → HOME chdir → `execvp(shell)`
3. 親プロセス: masterFD を `O_NONBLOCK` に設定 → 読み取りループ開始

### 環境変数

| 変数 | デフォルト値 | 説明 |
|------|------------|------|
| `TERM` | 設定値 or `xterm-256color` | ターミナルタイプ |
| `LANG` | `en_US.UTF-8` | ロケール |
| カスタム | settings.localShellEnv1/2 | `KEY=VALUE` 形式で指定 |

### バッファサイズ

| パラメータ | サイズ |
|-----------|--------|
| 受信バッファ | 16,384 bytes (16KB) |

### ウィンドウサイズ変更

`ioctl(fd, TIOCSWINSZ, &winsize)` で PTY ウィンドウサイズを更新。
`resize(cols:rows:)` メソッドで外部から変更可能。

### 子プロセス終了検出

- 読み取りループ中に `EAGAIN` 発生時、`waitpid(WNOHANG)` で子プロセスの生存確認
- EOF 受信 → プロセス終了と判定 → `disconnect()`
- 接続通知前の終了 → `connectionDidFail` でエラー通知

---

## Telnet プロトコル (TelnetProtocol)

ファイル: `TelnetProtocol.swift`

### 準拠 RFC

RFC 854 (Telnet), RFC 855 (Option), RFC 857 (Echo), RFC 858 (SGA), RFC 1073 (NAWS), RFC 1091 (Terminal-Type), RFC 1143 (Q Method)

### IAC ステートマシン

```
normal → iac → will/wont/do/dont → normal
              → sb → sbData → sbIAC → normal (SE受信)
```

### サポートオプション

| オプション | DO/WILL | 動作 |
|-----------|---------|------|
| Echo (1) | WILL → DO 応答 | echoMode フラグ更新 |
| Suppress Go Ahead (3) | WILL → DO 応答 | suppressGA フラグ更新 |
| Binary Transmission (0) | WILL/DO → 応答 | binaryMode フラグ更新 |
| Terminal Type (24) | DO → WILL 応答 | SB で端末タイプ送信 |
| Window Size (31) | DO → WILL + NAWS 送信 | ウィンドウサイズ通知 |
| Terminal Speed (32) | DO → WILL 応答 | SB で "38400,38400" 送信 |
| New Environment (39) | DO → WILL 応答 | SB で空環境送信 |

### サブネゴシエーション

- **Terminal Type**: `IAC SB 24 IS <type> IAC SE`（デフォルト: `xterm-256color`）
- **NAWS**: `IAC SB 31 <width:2bytes> <height:2bytes> IAC SE`（0xFF はエスケープ）
- **Terminal Speed**: `IAC SB 32 IS 38400,38400 IAC SE`
- **Environment**: `IAC SB 39 IS IAC SE`（空環境）

### IAC エスケープ

バイナリモード時、送信データ中の `0xFF` を `0xFF 0xFF` にエスケープ。

### AYT (Are You There) 応答

`[Yes]\r\n` を返送。

---

## ファイル転送 (FileTransferProtocol)

ファイル: `Sources/TeraTermMac/FileTransfer/FileTransferProtocol.swift`

### サポートプロトコル

| プロトコル | 送信 | 受信 | 状態 |
|-----------|------|------|------|
| XMODEM | 対応 | 対応 | 実装済み |
| YMODEM | 対応 | 対応 | 実装済み |
| ZMODEM | 対応 | 対応 | 実装済み（自動受信含む） |
| Kermit | スタブ | スタブ | 部分実装 |
| B-Plus | 未実装 | 未実装 | - |
| Quick-VAN | 未実装 | 未実装 | - |
| SCP | 対応 | 対応 | ssh コマンド経由 |

---

## エラーハンドリング

### ConnectionError enum

| エラー | 説明 |
|--------|------|
| `streamCreationFailed` | CFStream 作成失敗 |
| `connectionFailed` | 一般的な接続失敗 |
| `connectionRefused` | 接続拒否 |
| `connectionTimeout` | 接続タイムアウト |
| `hostNotFound` | DNS 解決失敗 |
| `sshNotSupported` | SSH 非サポート |
| `sshConnectionFailed` | SSH 接続失敗 |
| `sshForkFailed` | SSH プロセス fork 失敗 |
| `sshNotFound` | ssh コマンドが見つからない |
| `serialPortOpenFailed` | シリアルポートオープン失敗 |
| `ptyCreationFailed` | PTY 作成失敗 |
| `sendFailed` | 送信リトライ超過 |

各エラーには `alertTitle`（ダイアログタイトル用）と `errorDescription`（詳細メッセージ）を持つ。

---

## スレッドモデル

```
メインスレッド: UI 操作、デリゲート通知受信
readQueue:     受信データの読み取りループ（接続種別ごとに個別キュー）
writeQueue:    送信データの書き込み（TCP/Serial は個別キュー）
グローバルQoS:  接続処理（userInitiated）
```

全てのデリゲート通知は `DispatchQueue.main.async` で配信される。
