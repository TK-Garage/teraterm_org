/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of commlib.c to Swift/macOS
 * Communication layer - TCP/IP, Serial, SSH connections
 */

import Foundation
import os

// MARK: - Connection State

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error(String)
}


// MARK: - Connection Type

enum ConnectionType {
    case tcpip(host: String, port: Int)
    case serial(device: String, baudRate: Int, dataBits: Int, parity: Parity, stopBits: Int, flowControl: FlowControl)
    case localShell(command: String, arguments: [String], environment: [String: String])
    case ssh(host: String, port: Int, username: String, password: String,
             authMethod: SSHAuthMethod, keyFile: String, forwardAgent: Bool)
}

// MARK: - Connection Delegate

protocol ConnectionDelegate: AnyObject {
    func connectionDidConnect()
    func connectionDidDisconnect()
    func connectionDidReceiveData(_ data: Data)
    func connectionDidFail(error: Error)
    func connectionStateChanged(_ state: ConnectionState)
}

// MARK: - Connection Protocol

protocol Connection: AnyObject {
    var delegate: ConnectionDelegate? { get set }
    var state: ConnectionState { get }
    var isConnected: Bool { get }

    func connect()
    func disconnect()
    func send(_ data: Data)
    func send(_ string: String)
}

// MARK: - Connection Manager (port of commlib.c)

class ConnectionManager {
    weak var delegate: ConnectionDelegate?

    private(set) var currentConnection: Connection?
    private(set) var state: ConnectionState = .disconnected

    var settings: TerminalSettings

    init(settings: TerminalSettings) {
        self.settings = settings
    }

    // MARK: - Connect

    func connect(type: ConnectionType) {
        disconnect()

        let connection: Connection
        switch type {
        case .tcpip(let host, let port):
            connection = TCPConnection(host: host, port: port)
        case .serial(let device, let baudRate, let dataBits, let parity, let stopBits, let flowControl):
            connection = SerialConnection(
                device: device, baudRate: baudRate, dataBits: dataBits,
                parity: parity, stopBits: stopBits, flowControl: flowControl
            )
        case .localShell(let command, let arguments, let environment):
            connection = LocalShellConnection(command: command, arguments: arguments, environment: environment)
        case .ssh(let host, let port, let username, let password, let authMethod, let keyFile, let forwardAgent):
            connection = SSHConnection(
                host: host, port: port, username: username, password: password,
                authMethod: authMethod, keyFile: keyFile, forwardAgent: forwardAgent,
                termType: settings.termType)
        }

        connection.delegate = self
        currentConnection = connection
        connection.connect()
    }

    func connectWithSettings() {
        switch settings.portType {
        case .tcpip:
            connect(type: .tcpip(host: settings.hostname, port: settings.defaultPort))
        case .serial:
            connect(type: .serial(
                device: settings.serialPort,
                baudRate: settings.baudRate,
                dataBits: settings.dataBits,
                parity: settings.parity,
                stopBits: settings.stopBits,
                flowControl: settings.flowControl
            ))
        case .localShell:
            connectLocalShell()
        case .file, .namedPipe:
            break
        }
    }

    func connectLocalShell() {
        let shellPath: String
        if settings.localShellPath.isEmpty {
            shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        } else {
            shellPath = settings.localShellPath
        }

        var args: [String] = []
        if settings.localShellLoginShell {
            args.append("-l")
        }

        var env: [String: String] = [:]
        env["TERM"] = settings.localShellTermEnv

        // Parse custom environment variables (KEY=VALUE format)
        for envStr in [settings.localShellEnv1, settings.localShellEnv2] {
            if !envStr.isEmpty, let eqIdx = envStr.firstIndex(of: "=") {
                let key = String(envStr[envStr.startIndex..<eqIdx])
                let value = String(envStr[envStr.index(after: eqIdx)...])
                if !key.isEmpty {
                    env[key] = value
                }
            }
        }

        // chdir to HOME
        if settings.localShellHomeChdir {
            env["__TERATERM_HOME_CHDIR"] = "1"
        }

        connect(type: .localShell(command: shellPath, arguments: args, environment: env))
    }

    // MARK: - Disconnect

    func disconnect() {
        currentConnection?.disconnect()
        currentConnection = nil
        state = .disconnected
    }

    // MARK: - Send

    func send(_ data: Data) {
        currentConnection?.send(data)
    }

    func send(_ string: String) {
        currentConnection?.send(string)
    }

    func sendBreak() {
        if let tcp = currentConnection as? TCPConnection {
            // Send Telnet Break
            tcp.send(Data([0xFF, 0xF3])) // IAC BREAK
        } else if let serial = currentConnection as? SerialConnection {
            serial.sendBreak()
        } else if let ssh = currentConnection as? SSHConnection {
            ssh.sendBreak()
        }
    }

    /// Reset (close and immediately re-open) the current port/connection.
    func resetPort() {
        guard let conn = currentConnection else { return }

        if let serial = conn as? SerialConnection {
            let device = serial.device
            let baud = serial.baudRate
            let data = serial.dataBits
            let par = serial.parity
            let stop = serial.stopBits
            let flow = serial.flowControl
            serial.disconnect()
            let newConn = SerialConnection(
                device: device, baudRate: baud, dataBits: data,
                parity: par, stopBits: stop, flowControl: flow)
            newConn.delegate = self
            currentConnection = newConn
            newConn.connect()
        } else if let tcp = conn as? TCPConnection {
            let host = tcp.host
            let port = tcp.port
            tcp.disconnect()
            let newConn = TCPConnection(host: host, port: port)
            newConn.delegate = self
            currentConnection = newConn
            newConn.connect()
        } else if let pty = conn as? LocalShellConnection {
            let cmd = pty.command
            let args = pty.arguments
            let env = pty.environment
            pty.disconnect()
            let newConn = LocalShellConnection(command: cmd, arguments: args, environment: env)
            newConn.delegate = self
            currentConnection = newConn
            newConn.connect()
        } else if let ssh = conn as? SSHConnection {
            let h = ssh.host
            let p = ssh.port
            let u = ssh.username
            let pw = ssh.password  // reset後も認証情報を維持
            let m = ssh.authMethod
            let k = ssh.keyFile
            let f = ssh.forwardAgent
            let t = ssh.termType
            ssh.disconnect()
            let newConn = SSHConnection(
                host: h, port: p, username: u, password: pw,
                authMethod: m, keyFile: k, forwardAgent: f, termType: t)
            newConn.delegate = self
            currentConnection = newConn
            newConn.connect()
        }
    }
}

// MARK: - ConnectionDelegate

extension ConnectionManager: ConnectionDelegate {
    func connectionDidConnect() {
        state = .connected
        delegate?.connectionDidConnect()
    }

    func connectionDidDisconnect() {
        state = .disconnected
        delegate?.connectionDidDisconnect()
    }

    func connectionDidReceiveData(_ data: Data) {
        delegate?.connectionDidReceiveData(data)
    }

    func connectionDidFail(error: Error) {
        state = .error(error.localizedDescription)
        delegate?.connectionDidFail(error: error)
    }

    func connectionStateChanged(_ newState: ConnectionState) {
        state = newState
        delegate?.connectionStateChanged(newState)
    }
}

// MARK: - TCP Connection (port of commlib.c TCP/IP handling + ttwsk.c)

class TCPConnection: Connection {
    weak var delegate: ConnectionDelegate?

    let host: String
    let port: Int

    private(set) var state: ConnectionState = .disconnected
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let readQueue = DispatchQueue(label: "com.teraterm.tcp.read")
    private let writeQueue = DispatchQueue(label: "com.teraterm.tcp.write")

    // Thread safety: lock protects _isRunning and stream access from read/write queues
    private let stateLock = NSLock()
    private var _isRunning = false
    private var _disconnected = false

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func connect() {
        state = .connecting
        delegate?.connectionStateChanged(state)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?

            CFStreamCreatePairWithSocketToHost(
                kCFAllocatorDefault,
                self.host as CFString,
                UInt32(self.port),
                &readStream,
                &writeStream
            )

            guard let input = readStream?.takeRetainedValue() as InputStream?,
                  let output = writeStream?.takeRetainedValue() as OutputStream? else {
                let error = ConnectionError.streamCreationFailed(host: self.host, port: self.port)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.state = .error(error.localizedDescription)
                    self.delegate?.connectionDidFail(error: error)
                }
                return
            }

            self.stateLock.lock()
            self.inputStream = input
            self.outputStream = output
            self.stateLock.unlock()

            // Enable SSL/TLS if needed (can be extended)
            input.open()
            output.open()

            // Wait for connection
            var attempts = 0
            while input.streamStatus == .opening && attempts < 100 {
                Thread.sleep(forTimeInterval: 0.1)
                attempts += 1
            }

            if input.streamStatus == .open {
                self.stateLock.lock()
                self._isRunning = true
                self.stateLock.unlock()

                DispatchQueue.main.async { [weak self] in
                    self?.state = .connected
                    self?.delegate?.connectionDidConnect()
                }
                self.startReading()
            } else {
                let error = self.classifyStreamError(
                    streamError: input.streamError, host: self.host, port: self.port)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.state = .error(error.localizedDescription)
                    self.delegate?.connectionDidFail(error: error)
                }
            }
        }
    }

    func disconnect() {
        stateLock.lock()
        let wasRunning = _isRunning
        _isRunning = false
        let input = inputStream
        let output = outputStream
        inputStream = nil
        outputStream = nil
        let alreadyDisconnected = _disconnected
        _disconnected = true
        stateLock.unlock()

        guard !alreadyDisconnected else { return }

        input?.close()
        output?.close()

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

    /// TCP 送信時の n==0 (バッファフル) リトライ上限。
    /// 各リトライは 1ms sleep するため、最大約 5 秒間待機する。
    /// ネットワーク混雑やリモート側の受信遅延を考慮し、十分な猶予を確保。
    private static let sendMaxRetries = 5000

    func send(_ data: Data) {
        stateLock.lock()
        let running = _isRunning
        let output = outputStream
        stateLock.unlock()

        guard running, let output = output else { return }
        writeQueue.async { [weak self] in
            // 全バイト送信完了までループ（部分書き込み対応）
            data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                guard let basePtr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                var offset = 0
                let total = data.count
                var retries = 0
                while offset < total {
                    let n = output.write(basePtr + offset, maxLength: total - offset)
                    if n > 0 {
                        offset += n
                        retries = 0
                    } else if n == 0 {
                        // ストリームが一時的に書き込み不可
                        retries += 1
                        if retries > TCPConnection.sendMaxRetries {
                            // リトライ上限到達 → 送信失敗として切断・通知
                            TTLog.tcp.error("Write retry exceeded: retries=\(retries) offset=\(offset) total=\(total)")
                            DispatchQueue.main.async { [weak self] in
                                self?.delegate?.connectionDidFail(error: ConnectionError.sendFailed)
                                self?.disconnect()
                            }
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.001)
                    } else {
                        // 書き込みエラー → 切断
                        DispatchQueue.main.async { [weak self] in
                            self?.disconnect()
                        }
                        return
                    }
                }
            }
        }
    }

    func send(_ string: String) {
        send(Data(string.utf8))
    }

    /// Classify a stream error into a specific ConnectionError with host/port context.
    private func classifyStreamError(streamError: Error?, host: String, port: Int) -> ConnectionError {
        if let nsError = streamError as NSError? {
            let desc = nsError.localizedDescription.lowercased()
            // POSIX error domain
            if nsError.domain == NSPOSIXErrorDomain {
                switch nsError.code {
                case Int(ECONNREFUSED):
                    return .connectionRefused(host: host, port: port)
                case Int(ETIMEDOUT):
                    return .connectionTimeout(host: host, port: port)
                default:
                    break
                }
            }
            // Check for DNS / host-not-found patterns in any domain
            if desc.contains("nodename nor servname") || desc.contains("host not found")
                || desc.contains("no address associated") || desc.contains("name or service not known") {
                return .hostNotFound(host: host)
            }
            if desc.contains("connection refused") || desc.contains("actively refused") {
                return .connectionRefused(host: host, port: port)
            }
            if desc.contains("timed out") || desc.contains("timeout") {
                return .connectionTimeout(host: host, port: port)
            }
            return .connectionFailed(host: host, port: port, detail: nsError.localizedDescription)
        }
        return .connectionFailed(host: host, port: port, detail: nil)
    }

    private func startReading() {
        readQueue.async { [weak self] in
            let bufferSize = 16384  // 16KB matching original CommInQueSize
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            while true {
                guard let self = self else { break }

                self.stateLock.lock()
                let running = self._isRunning
                let input = self.inputStream
                self.stateLock.unlock()

                guard running, let input = input else { break }

                guard input.hasBytesAvailable else {
                    Thread.sleep(forTimeInterval: 0.01)
                    continue
                }

                let bytesRead = input.read(&buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.connectionDidReceiveData(data)
                    }
                } else if bytesRead < 0 {
                    DispatchQueue.main.async { [weak self] in
                        self?.disconnect()
                    }
                    break
                } else {
                    // EOF
                    DispatchQueue.main.async { [weak self] in
                        self?.disconnect()
                    }
                    break
                }
            }
        }
    }
}

// MARK: - Serial Connection (port of commlib.c serial handling)

class SerialConnection: Connection {
    weak var delegate: ConnectionDelegate?

    let device: String
    let baudRate: Int
    let dataBits: Int
    let parity: Parity
    let stopBits: Int
    let flowControl: FlowControl

    private(set) var state: ConnectionState = .disconnected
    private(set) var fileDescriptor: Int32 = -1
    private let readQueue = DispatchQueue(label: "com.teraterm.serial.read")
    private let writeQueue = DispatchQueue(label: "com.teraterm.serial.write")

    // Thread safety
    private let stateLock = NSLock()
    private var _isRunning = false
    private var _disconnected = false

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    init(device: String, baudRate: Int, dataBits: Int, parity: Parity, stopBits: Int, flowControl: FlowControl) {
        self.device = device
        self.baudRate = baudRate
        self.dataBits = dataBits
        self.parity = parity
        self.stopBits = stopBits
        self.flowControl = flowControl
    }

    func connect() {
        state = .connecting
        delegate?.connectionStateChanged(state)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Open serial port
            let fd = open(self.device, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard fd >= 0 else {
                let posixError = String(cString: strerror(errno))
                let error = ConnectionError.serialPortOpenFailed(
                    device: self.device, detail: posixError)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.state = .error(error.localizedDescription)
                    self.delegate?.connectionDidFail(error: error)
                }
                return
            }

            self.stateLock.lock()
            self.fileDescriptor = fd
            self.stateLock.unlock()

            // Configure serial port
            var options = termios()
            tcgetattr(fd, &options)

            // Set baud rate
            let speed = self.speedConstant(for: self.baudRate)
            cfsetispeed(&options, speed)
            cfsetospeed(&options, speed)

            // Set data bits
            options.c_cflag &= ~UInt(CSIZE)
            switch self.dataBits {
            case 5: options.c_cflag |= UInt(CS5)
            case 6: options.c_cflag |= UInt(CS6)
            case 7: options.c_cflag |= UInt(CS7)
            default: options.c_cflag |= UInt(CS8)
            }

            // Set parity
            switch self.parity {
            case .none:
                options.c_cflag &= ~UInt(PARENB)
            case .even:
                options.c_cflag |= UInt(PARENB)
                options.c_cflag &= ~UInt(PARODD)
            case .odd:
                options.c_cflag |= UInt(PARENB)
                options.c_cflag |= UInt(PARODD)
            default:
                options.c_cflag &= ~UInt(PARENB)
            }

            // Set stop bits
            if self.stopBits == 2 {
                options.c_cflag |= UInt(CSTOPB)
            } else {
                options.c_cflag &= ~UInt(CSTOPB)
            }

            // Set flow control
            switch self.flowControl {
            case .hardware:
                options.c_cflag |= UInt(CRTSCTS)
            case .xonXoff:
                options.c_iflag |= UInt(IXON | IXOFF)
            case .none:
                options.c_cflag &= ~UInt(CRTSCTS)
                options.c_iflag &= ~UInt(IXON | IXOFF)
            }

            // Raw mode
            options.c_lflag &= ~UInt(ICANON | ECHO | ECHOE | ISIG)
            options.c_iflag &= ~UInt(INLCR | ICRNL | IGNCR)
            options.c_oflag &= ~UInt(OPOST)

            // Enable receiver, local mode
            options.c_cflag |= UInt(CLOCAL | CREAD)

            // Set VMIN and VTIME
            options.c_cc.16 = 1   // VMIN
            options.c_cc.17 = 0   // VTIME

            tcsetattr(fd, TCSANOW, &options)

            // Clear O_NONBLOCK after configuration
            var flags = fcntl(fd, F_GETFL)
            flags &= ~O_NONBLOCK
            _ = fcntl(fd, F_SETFL, flags)

            self.stateLock.lock()
            self._isRunning = true
            self.stateLock.unlock()

            DispatchQueue.main.async { [weak self] in
                self?.state = .connected
                self?.delegate?.connectionDidConnect()
            }
            self.startReading()
        }
    }

    func disconnect() {
        stateLock.lock()
        let wasRunning = _isRunning
        _isRunning = false
        let fd = fileDescriptor
        fileDescriptor = -1
        let alreadyDisconnected = _disconnected
        _disconnected = true
        stateLock.unlock()

        guard !alreadyDisconnected else { return }

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

    func send(_ data: Data) {
        stateLock.lock()
        let running = _isRunning
        let fd = fileDescriptor
        stateLock.unlock()

        guard running, fd >= 0 else { return }
        writeQueue.async { [weak self] in
            data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
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
                        DispatchQueue.main.async { [weak self] in
                            self?.disconnect()
                        }
                        return
                    }
                }
            }
        }
    }

    func send(_ string: String) {
        send(Data(string.utf8))
    }

    func sendBreak() {
        stateLock.lock()
        let running = _isRunning
        let fd = fileDescriptor
        stateLock.unlock()

        guard running, fd >= 0 else { return }
        // tcsendbreak(fd, 0) sends a break for 0.25–0.5 seconds
        tcsendbreak(fd, 0)
    }

    private func startReading() {
        readQueue.async { [weak self] in
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            while true {
                guard let self = self else { break }

                self.stateLock.lock()
                let running = self._isRunning
                let fd = self.fileDescriptor
                self.stateLock.unlock()

                guard running, fd >= 0 else { break }

                let bytesRead = read(fd, &buffer, bufferSize)
                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.connectionDidReceiveData(data)
                    }
                } else if bytesRead < 0 {
                    if errno == EAGAIN || errno == EINTR {
                        Thread.sleep(forTimeInterval: 0.01)
                        continue
                    }
                    break
                } else {
                    break
                }
            }
        }
    }

    private func speedConstant(for baudRate: Int) -> speed_t {
        switch baudRate {
        case 300: return speed_t(B300)
        case 600: return speed_t(B600)
        case 1200: return speed_t(B1200)
        case 2400: return speed_t(B2400)
        case 4800: return speed_t(B4800)
        case 9600: return speed_t(B9600)
        case 19200: return speed_t(B19200)
        case 38400: return speed_t(B38400)
        case 57600: return speed_t(B57600)
        case 115200: return speed_t(B115200)
        case 230400: return speed_t(B230400)
        default: return speed_t(B9600)
        }
    }
}

// MARK: - Local Shell Connection (PTY-based)

class LocalShellConnection: Connection {
    weak var delegate: ConnectionDelegate?

    let command: String
    let arguments: [String]
    let environment: [String: String]

    private(set) var state: ConnectionState = .disconnected
    private var masterFD: Int32 = -1
    private var childPID: pid_t = 0
    private let readQueue = DispatchQueue(label: "com.teraterm.pty.read")
    private let writeQueue = DispatchQueue(label: "com.teraterm.pty.write")

    // Thread safety
    private let stateLock = NSLock()
    private var _isRunning = false
    private var _disconnected = false
    /// 接続通知済みフラグ（readQueue 上でのみ更新、main queue へは通知のみ投げる）
    private var _hasNotifiedConnect = false

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    // Window size for PTY
    private var _windowSize: (cols: UInt16, rows: UInt16) = (80, 24)
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

    init(command: String, arguments: [String], environment: [String: String]) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }

    func connect() {
        state = .connecting
        delegate?.connectionStateChanged(state)

        // Create PTY pair
        var masterFD: Int32 = 0

        stateLock.lock()
        let winSize = _windowSize
        stateLock.unlock()

        var ws = winsize()
        ws.ws_col = winSize.cols
        ws.ws_row = winSize.rows
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0

        // Use forkpty to create PTY and fork
        let pid = forkpty(&masterFD, nil, nil, &ws)

        if pid < 0 {
            state = .error(TTL("error.connection.ptyFailed"))
            delegate?.connectionDidFail(error: ConnectionError.ptyCreationFailed)
            return
        }

        if pid == 0 {
            // Child process
            // chdir to HOME if requested
            var shouldChdir = false

            // Set environment
            for (key, value) in environment {
                if key == "__TERATERM_HOME_CHDIR" {
                    shouldChdir = true
                } else {
                    setenv(key, value, 1)
                }
            }

            // Set TERM if not already set by environment
            if environment["TERM"] == nil {
                setenv("TERM", "xterm-256color", 1)
            }

            // Set LANG for UTF-8
            if getenv("LANG") == nil {
                setenv("LANG", "en_US.UTF-8", 1)
            }

            // chdir to HOME
            if shouldChdir, let home = getenv("HOME") {
                _ = chdir(home)
            }

            // Execute shell
            let args = [command] + arguments
            let cArgs = args.map { strdup($0) } + [nil]
            execvp(command, cArgs)

            // If exec fails
            _exit(1)
        }

        // Parent process
        stateLock.lock()
        self.masterFD = masterFD
        self.childPID = pid
        self._isRunning = true
        stateLock.unlock()

        // Set non-blocking
        let flags = fcntl(masterFD, F_GETFL)
        _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

        // 接続通知は startReading 内で子プロセスの生存確認後に行う
        startReading()
    }

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

    func send(_ data: Data) {
        stateLock.lock()
        let running = _isRunning
        let fd = masterFD
        stateLock.unlock()

        guard running, fd >= 0 else { return }
        writeQueue.async { [weak self] in
            data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
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
                        DispatchQueue.main.async { [weak self] in
                            self?.disconnect()
                        }
                        return
                    }
                }
            }
        }
    }

    func send(_ string: String) {
        send(Data(string.utf8))
    }

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

    private func startReading() {
        readQueue.async { [weak self] in
            let bufferSize = 16384
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            while true {
                guard let self = self else { break }

                self.stateLock.lock()
                let running = self._isRunning
                let fd = self.masterFD
                self.stateLock.unlock()

                guard running, fd >= 0 else { break }

                let bytesRead = read(fd, &buffer, bufferSize)
                if bytesRead > 0 {
                    // 接続通知の判定・更新は readQueue 上で完結させる
                    let needsConnectNotify: Bool
                    if !self._hasNotifiedConnect {
                        self._hasNotifiedConnect = true
                        needsConnectNotify = true
                    } else {
                        needsConnectNotify = false
                    }
                    let data = Data(buffer[0..<bytesRead])
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if needsConnectNotify {
                            // 初回データ受信で子プロセス生存を確認してから通知（1回だけ）
                            self.state = .connected
                            self.delegate?.connectionDidConnect()
                        }
                        self.delegate?.connectionDidReceiveData(data)
                    }
                } else if bytesRead < 0 {
                    if errno == EAGAIN || errno == EINTR {
                        // 接続待ち中は子プロセスの生存を確認
                        if !self._hasNotifiedConnect {
                            var status: Int32 = 0
                            let r = waitpid(self.childPID, &status, WNOHANG)
                            if r > 0 {
                                // 子プロセスが既に終了 (execvp 失敗等)
                                DispatchQueue.main.async { [weak self] in
                                    guard let self = self else { return }
                                    self.state = .error(TTL("error.connection.shellLaunchFailed"))
                                    self.delegate?.connectionDidFail(
                                        error: ConnectionError.ptyCreationFailed)
                                    self.disconnect()
                                }
                                break
                            }
                        }
                        Thread.sleep(forTimeInterval: 0.005)
                        continue
                    }
                    // Process likely exited
                    let wasConnected = self._hasNotifiedConnect
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if !wasConnected {
                            self.state = .error(TTL("error.connection.shellLaunchFailed"))
                            self.delegate?.connectionDidFail(
                                error: ConnectionError.ptyCreationFailed)
                        }
                        self.disconnect()
                    }
                    break
                } else {
                    // EOF - process exited
                    let wasConnected = self._hasNotifiedConnect
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if !wasConnected {
                            self.state = .error(TTL("error.connection.shellExitedImmediately"))
                            self.delegate?.connectionDidFail(
                                error: ConnectionError.ptyCreationFailed)
                        }
                        self.disconnect()
                    }
                    break
                }
            }
        }
    }
}

// MARK: - Connection Errors

enum ConnectionError: LocalizedError {
    case streamCreationFailed(host: String, port: Int)
    case connectionFailed(host: String, port: Int, detail: String?)
    case connectionRefused(host: String, port: Int)
    case connectionTimeout(host: String, port: Int)
    case hostNotFound(host: String)
    case sshNotSupported(host: String, port: Int)
    case sshConnectionFailed(host: String, port: Int, detail: String?)
    case sshForkFailed(detail: String?)
    case sshNotFound
    case serialPortOpenFailed(device: String, detail: String?)
    case ptyCreationFailed
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .streamCreationFailed(let host, let port):
            return TTL("error.connection.streamFailed", host, port)
        case .connectionFailed(let host, let port, let detail):
            let base = TTL("error.connection.failed", host, port)
            if let detail = detail { return "\(base)\n\(detail)" }
            return base
        case .connectionRefused(let host, let port):
            return TTL("error.connection.refused", host, port)
        case .connectionTimeout(let host, let port):
            return TTL("error.connection.timeout", host, port)
        case .hostNotFound(let host):
            return TTL("error.connection.hostNotFound", host)
        case .sshNotSupported(let host, let port):
            return TTL("error.connection.sshNotSupported", host, port)
        case .sshConnectionFailed(let host, let port, let detail):
            let base = TTL("error.connection.sshFailed", host, port)
            if let detail = detail { return "\(base)\n\(detail)" }
            return base
        case .sshForkFailed(let detail):
            let base = TTL("error.connection.sshProcessFailed")
            if let detail = detail { return "\(base)\n\(detail)" }
            return base
        case .sshNotFound:
            return TTL("error.connection.sshNotFound")
        case .serialPortOpenFailed(let device, let detail):
            let base = TTL("error.connection.serialFailed", device)
            if let detail = detail { return "\(base)\n\(detail)" }
            return base
        case .ptyCreationFailed:
            return TTL("error.connection.ptyFailed")
        case .sendFailed:
            return TTL("error.connection.sendFailed")
        }
    }

    /// Title string for the error alert dialog (port of original Tera Term MessageBox titles).
    var alertTitle: String {
        switch self {
        case .hostNotFound:
            return TTL("error.connection.title.dns")
        case .connectionRefused:
            return TTL("error.connection.title.refused")
        case .connectionTimeout:
            return TTL("error.connection.title.timeout")
        case .sshNotSupported:
            return TTL("error.connection.title.ssh")
        case .sshConnectionFailed, .sshForkFailed, .sshNotFound:
            return TTL("error.connection.title.sshError")
        case .serialPortOpenFailed:
            return TTL("error.connection.title.serial")
        default:
            return TTL("error.connection.title")
        }
    }
}
