/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * SSH connection using macOS system OpenSSH (/usr/bin/ssh) via PTY.
 * Provides full SSH2 protocol support including password, public key,
 * and keyboard-interactive authentication.
 *
 * Architecture:
 *   forkpty() → exec /usr/bin/ssh → PTY data stream
 *   Authentication handled via SSH_ASKPASS mechanism (OpenSSH 8.4+)
 */

import Foundation

// POSIX wait status macros (C macros not imported into Swift)
private func WIFEXITED(_ status: Int32) -> Bool {
    return (status & 0x7F) == 0
}

private func WEXITSTATUS(_ status: Int32) -> Int32 {
    return (status >> 8) & 0xFF
}

// MARK: - SSH Connection (system ssh via PTY)

class SSHConnection: Connection {
    weak var delegate: ConnectionDelegate?

    let host: String
    let port: Int
    let username: String
    let authMethod: SSHAuthMethod
    let forwardAgent: Bool
    let termType: String

    // password は resetPort() で再利用するため internal(set) で公開
    private(set) var password: String
    let keyFile: String

    private(set) var state: ConnectionState = .disconnected
    private var masterFD: Int32 = -1
    private var childPID: pid_t = 0
    private let readQueue = DispatchQueue(label: "com.teraterm.ssh.read")

    // Thread safety
    private let stateLock = NSLock()
    private var _isRunning = false
    private var _disconnected = false

    // Window size for PTY
    private var _windowSize: (cols: UInt16, rows: UInt16) = (80, 24)

    // ASKPASS helper
    private var askpassPath: String?

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    var windowSize: (cols: UInt16, rows: UInt16) {
        get {
            stateLock.lock()
            let size = _windowSize
            stateLock.unlock()
            return size
        }
        set {
            stateLock.lock()
            _windowSize = newValue
            stateLock.unlock()
            updateWindowSize()
        }
    }

    init(host: String, port: Int, username: String, password: String,
         authMethod: SSHAuthMethod, keyFile: String, forwardAgent: Bool,
         termType: String = "xterm-256color") {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.authMethod = authMethod
        self.keyFile = keyFile
        self.forwardAgent = forwardAgent
        self.termType = termType
    }

    deinit {
        cleanupAskpass()
    }

    // MARK: - Connect

    func connect() {
        state = .connecting
        delegate?.connectionStateChanged(state)

        // Create ASKPASS helper if password/passphrase is provided
        if !password.isEmpty {
            askpassPath = createAskpassHelper(password: password)
        }

        // Capture values for use after fork
        let sshArgs = buildSSHArguments()
        let askpass = askpassPath
        let term = termType

        stateLock.lock()
        let winSize = _windowSize
        stateLock.unlock()

        var ws = winsize()
        ws.ws_col = winSize.cols
        ws.ws_row = winSize.rows
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0

        // forkpty creates PTY pair and forks
        var masterFD: Int32 = 0
        let pid = forkpty(&masterFD, nil, nil, &ws)

        if pid < 0 {
            let detail = String(cString: strerror(errno))
            let error = ConnectionError.sshForkFailed(detail: detail)
            state = .error(error.localizedDescription)
            delegate?.connectionDidFail(error: error)
            cleanupAskpass()
            return
        }

        if pid == 0 {
            // ── Child process ──

            // Set terminal type
            setenv("TERM", term, 1)

            // Set LANG for UTF-8 if not already set
            if getenv("LANG") == nil {
                setenv("LANG", "en_US.UTF-8", 1)
            }

            // Configure SSH_ASKPASS for automatic password/passphrase entry
            if let askpath = askpass {
                setenv("SSH_ASKPASS", askpath, 1)
                setenv("SSH_ASKPASS_REQUIRE", "force", 1)
                // DISPLAY is required for SSH_ASKPASS (even without X11)
                setenv("DISPLAY", ":", 1)
            }

            // Build C-style argument array
            let cArgs = sshArgs.map { strdup($0) } + [nil]
            execvp("/usr/bin/ssh", cArgs)

            // If exec fails (should never happen on macOS)
            _exit(127)
        }

        // ── Parent process ──
        stateLock.lock()
        self.masterFD = masterFD
        self.childPID = pid
        self._isRunning = true
        stateLock.unlock()

        // Set non-blocking I/O on the master PTY
        let flags = fcntl(masterFD, F_GETFL)
        _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

        // 接続通知は startReading 内で子プロセスの生存確認後に行う
        startReading()

        // Clean up ASKPASS helper after ssh has had time to authenticate
        DispatchQueue.global().asyncAfter(deadline: .now() + 10.0) { [weak self] in
            self?.cleanupAskpass()
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        stateLock.lock()
        let wasRunning = _isRunning
        _isRunning = false
        let fd = masterFD
        masterFD = -1
        let pid = childPID
        childPID = 0
        let alreadyDisconnected = _disconnected
        _disconnected = true
        stateLock.unlock()

        guard !alreadyDisconnected else { return }

        cleanupAskpass()

        // Send SIGHUP to ssh process and wait for it to exit
        if pid > 0 {
            kill(pid, SIGHUP)
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
        }

        if fd >= 0 {
            close(fd)
        }

        if wasRunning || state != .disconnected {
            let notifyDelegate = { [weak self] in
                self?.state = .disconnected
                self?.delegate?.connectionDidDisconnect()
            }
            if Thread.isMainThread {
                notifyDelegate()
            } else {
                DispatchQueue.main.async(execute: notifyDelegate)
            }
        }
    }

    // MARK: - Send

    func send(_ data: Data) {
        stateLock.lock()
        let running = _isRunning
        let fd = masterFD
        stateLock.unlock()

        guard running, fd >= 0 else { return }
        // 全バイト送信完了までループ（部分書き込み対応）
        data.withUnsafeBytes { buffer in
            guard let basePtr = buffer.baseAddress else { return }
            var offset = 0
            let total = data.count
            while offset < total {
                let n = write(fd, basePtr + offset, total - offset)
                if n > 0 {
                    offset += n
                } else if n < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN {
                        Thread.sleep(forTimeInterval: 0.001)
                        continue
                    }
                    // 書き込みエラー → 切断
                    DispatchQueue.main.async { [weak self] in
                        self?.disconnect()
                    }
                    return
                }
            }
        }
    }

    func send(_ string: String) {
        send(Data(string.utf8))
    }

    // MARK: - Send Break

    /// Send SSH break via the ssh escape sequence.
    /// In OpenSSH, `~B` at the start of a line sends a break to the remote.
    func sendBreak() {
        // Send Enter + ~B to trigger ssh's built-in break escape
        send(Data([0x0D]))  // CR
        Thread.sleep(forTimeInterval: 0.05)
        send(Data("~B".utf8))
    }

    // MARK: - Window Resize

    func updateWindowSize() {
        stateLock.lock()
        let fd = masterFD
        let size = _windowSize
        stateLock.unlock()

        guard fd >= 0 else { return }
        var ws = winsize()
        ws.ws_col = size.cols
        ws.ws_row = size.rows
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0
        _ = ioctl(fd, TIOCSWINSZ, &ws)
    }

    func resize(cols: UInt16, rows: UInt16) {
        windowSize = (cols, rows)
    }

    // MARK: - SSH Arguments

    private func buildSSHArguments() -> [String] {
        var args = ["/usr/bin/ssh"]

        // Force PTY allocation for interactive session
        args += ["-tt"]

        // Port
        args += ["-p", "\(port)"]

        // Username
        args += ["-l", username]

        // Auto-accept new host keys (reject changed keys for MITM protection)
        args += ["-o", "StrictHostKeyChecking=accept-new"]

        // Keep-alive to detect dead connections
        args += ["-o", "ServerAliveInterval=60"]
        args += ["-o", "ServerAliveCountMax=3"]

        // Auth method specific options
        switch authMethod {
        case .password:
            // Prefer password and keyboard-interactive auth
            args += ["-o", "PreferredAuthentications=password,keyboard-interactive"]
            // Disable public key auth to avoid trying keys first
            args += ["-o", "PubkeyAuthentication=no"]

        case .publicKey:
            // Use specified key file
            if !keyFile.isEmpty {
                args += ["-i", keyFile]
            }
            args += ["-o", "PreferredAuthentications=publickey"]

        case .challengeResponse:
            // keyboard-interactive only
            args += ["-o", "PreferredAuthentications=keyboard-interactive"]
            args += ["-o", "PubkeyAuthentication=no"]

        case .pageant:
            // On macOS, use ssh-agent (Pageant equivalent)
            // SSH agent is used by default when available
            args += ["-o", "PreferredAuthentications=publickey"]

        case .rhosts:
            // Legacy SSH1 rhosts - not commonly used
            args += ["-o", "PreferredAuthentications=hostbased"]
        }

        // Agent forwarding
        if forwardAgent {
            args += ["-A"]
        } else {
            args += ["-a"]
        }

        // Target host
        args += [host]

        return args
    }

    // MARK: - ASKPASS Helper

    /// Create a temporary script that outputs the password for SSH_ASKPASS.
    /// The script is chmod 0700 and contains only a printf statement.
    private func createAskpassHelper(password: String) -> String? {
        let tempDir = NSTemporaryDirectory()
        let pid = ProcessInfo.processInfo.processIdentifier
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let path = (tempDir as NSString).appendingPathComponent(
            "teraterm_askpass_\(pid)_\(ts)")

        // Escape single quotes for shell safety: ' → '\''
        let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/sh\nprintf '%s\\n' '\(escaped)'\n"

        do {
            try script.write(toFile: path, atomically: true, encoding: .utf8)
            // Set executable permission (owner only)
            chmod(path, 0o700)
            return path
        } catch {
            return nil
        }
    }

    /// Remove the temporary ASKPASS helper script.
    private func cleanupAskpass() {
        guard let path = askpassPath else { return }
        // Overwrite contents before deleting for security
        if let data = Data(count: 256) as Data? {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        try? FileManager.default.removeItem(atPath: path)
        askpassPath = nil
    }

    // MARK: - Read Loop

    private func startReading() {
        readQueue.async { [weak self] in
            let bufferSize = 16384
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            var connected = false  // 接続通知済みフラグ

            while true {
                guard let self = self else { break }

                self.stateLock.lock()
                let running = self._isRunning
                let fd = self.masterFD
                self.stateLock.unlock()

                guard running, fd >= 0 else { break }

                let bytesRead = read(fd, &buffer, bufferSize)
                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if !connected {
                            // 初回データ受信で子プロセス生存を確認してから通知
                            connected = true
                            self.state = .connected
                            self.delegate?.connectionDidConnect()
                        }
                        self.delegate?.connectionDidReceiveData(data)
                    }
                } else if bytesRead < 0 {
                    if errno == EAGAIN || errno == EINTR {
                        // 接続待ち中の EAGAIN は子プロセスの生存を確認
                        if !connected {
                            var status: Int32 = 0
                            let r = waitpid(self.childPID, &status, WNOHANG)
                            if r > 0 {
                                // 子プロセスが既に終了 (execvp 失敗等)
                                DispatchQueue.main.async { [weak self] in
                                    self?.handleSSHExit()
                                }
                                break
                            }
                        }
                        Thread.sleep(forTimeInterval: 0.005)
                        continue
                    }
                    // SSH process likely exited
                    DispatchQueue.main.async { [weak self] in
                        if !connected {
                            // 接続完了前にエラー → 失敗通知
                            self?.state = .error("SSH connection failed")
                            self?.delegate?.connectionDidFail(
                                error: ConnectionError.sshConnectionFailed(
                                    host: self?.host ?? "", port: self?.port ?? 0,
                                    detail: "PTY read error before connection established"))
                        }
                        self?.handleSSHExit()
                    }
                    break
                } else {
                    // EOF - SSH process exited
                    DispatchQueue.main.async { [weak self] in
                        if !connected {
                            self?.state = .error("SSH connection failed")
                            self?.delegate?.connectionDidFail(
                                error: ConnectionError.sshConnectionFailed(
                                    host: self?.host ?? "", port: self?.port ?? 0,
                                    detail: "SSH process exited before connection established"))
                        }
                        self?.handleSSHExit()
                    }
                    break
                }
            }
        }
    }

    /// Handle SSH process exit - check exit status and report errors.
    private func handleSSHExit() {
        stateLock.lock()
        let pid = childPID
        stateLock.unlock()

        var exitStatus: Int32 = 0
        if pid > 0 {
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
            if WIFEXITED(status) {
                exitStatus = WEXITSTATUS(status)
            }
        }

        if exitStatus != 0 && state == .connected {
            // SSH exited with error - provide context in the error
            let error: ConnectionError
            switch exitStatus {
            case 255:
                // SSH general error (connection refused, auth failed, etc.)
                error = .sshConnectionFailed(
                    host: host, port: port,
                    detail: "SSH connection terminated (exit code 255)")
            case 127:
                error = .sshNotFound
            default:
                error = .sshConnectionFailed(
                    host: host, port: port,
                    detail: "SSH exited with code \(exitStatus)")
            }
            state = .error(error.localizedDescription)
            delegate?.connectionDidFail(error: error)
        }

        disconnect()
    }
}
