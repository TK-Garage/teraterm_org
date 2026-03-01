/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of commlib.c to Swift/macOS
 * Communication layer - TCP/IP, Serial, SSH connections
 */

import Foundation

// MARK: - Connection State

enum ConnectionState {
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
        case .file, .namedPipe:
            break
        }
    }

    func connectLocalShell() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        connect(type: .localShell(command: shell, arguments: ["-l"], environment: [:]))
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
    private var readQueue = DispatchQueue(label: "com.teraterm.tcp.read")
    private var writeQueue = DispatchQueue(label: "com.teraterm.tcp.write")
    private var isRunning = false

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
                DispatchQueue.main.async {
                    self.state = .error("Failed to create streams")
                    self.delegate?.connectionDidFail(error: ConnectionError.streamCreationFailed)
                }
                return
            }

            self.inputStream = input
            self.outputStream = output

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
                self.isRunning = true
                DispatchQueue.main.async {
                    self.state = .connected
                    self.delegate?.connectionDidConnect()
                }
                self.startReading()
            } else {
                DispatchQueue.main.async {
                    self.state = .error("Connection failed")
                    self.delegate?.connectionDidFail(error: input.streamError ?? ConnectionError.connectionFailed)
                }
            }
        }
    }

    func disconnect() {
        isRunning = false
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        state = .disconnected
        delegate?.connectionDidDisconnect()
    }

    func send(_ data: Data) {
        guard isConnected, let output = outputStream else { return }
        writeQueue.async {
            data.withUnsafeBytes { buffer in
                guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                output.write(ptr, maxLength: data.count)
            }
        }
    }

    func send(_ string: String) {
        send(Data(string.utf8))
    }

    private func startReading() {
        readQueue.async { [weak self] in
            guard let self = self else { return }
            let bufferSize = 16384  // 16KB matching original CommInQueSize
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            while self.isRunning {
                guard let input = self.inputStream else { break }
                guard input.hasBytesAvailable else {
                    Thread.sleep(forTimeInterval: 0.01)
                    continue
                }

                let bytesRead = input.read(&buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    DispatchQueue.main.async {
                        self.delegate?.connectionDidReceiveData(data)
                    }
                } else if bytesRead < 0 {
                    DispatchQueue.main.async {
                        self.disconnect()
                    }
                    break
                } else {
                    // EOF
                    DispatchQueue.main.async {
                        self.disconnect()
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
    private var fileDescriptor: Int32 = -1
    private var readQueue = DispatchQueue(label: "com.teraterm.serial.read")
    private var isRunning = false

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
            self.fileDescriptor = open(self.device, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard self.fileDescriptor >= 0 else {
                DispatchQueue.main.async {
                    self.state = .error("Failed to open \(self.device)")
                    self.delegate?.connectionDidFail(error: ConnectionError.serialPortOpenFailed)
                }
                return
            }

            // Configure serial port
            var options = termios()
            tcgetattr(self.fileDescriptor, &options)

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

            tcsetattr(self.fileDescriptor, TCSANOW, &options)

            // Clear O_NONBLOCK after configuration
            var flags = fcntl(self.fileDescriptor, F_GETFL)
            flags &= ~O_NONBLOCK
            fcntl(self.fileDescriptor, F_SETFL, flags)

            self.isRunning = true
            DispatchQueue.main.async {
                self.state = .connected
                self.delegate?.connectionDidConnect()
            }
            self.startReading()
        }
    }

    func disconnect() {
        isRunning = false
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        state = .disconnected
        delegate?.connectionDidDisconnect()
    }

    func send(_ data: Data) {
        guard isConnected && fileDescriptor >= 0 else { return }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            write(fileDescriptor, ptr, data.count)
        }
    }

    func send(_ string: String) {
        send(Data(string.utf8))
    }

    private func startReading() {
        readQueue.async { [weak self] in
            guard let self = self else { return }
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            while self.isRunning && self.fileDescriptor >= 0 {
                let bytesRead = read(self.fileDescriptor, &buffer, bufferSize)
                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    DispatchQueue.main.async {
                        self.delegate?.connectionDidReceiveData(data)
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
    private var slaveFD: Int32 = -1
    private var childPID: pid_t = 0
    private var readQueue = DispatchQueue(label: "com.teraterm.pty.read")
    private var isRunning = false

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    // Window size for PTY
    var windowSize: (cols: UInt16, rows: UInt16) = (80, 24) {
        didSet {
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
        var slaveFD: Int32 = 0

        var ws = winsize()
        ws.ws_col = windowSize.cols
        ws.ws_row = windowSize.rows
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0

        // Use forkpty to create PTY and fork
        let pid = forkpty(&masterFD, nil, nil, &ws)

        if pid < 0 {
            state = .error("forkpty failed")
            delegate?.connectionDidFail(error: ConnectionError.ptyCreationFailed)
            return
        }

        if pid == 0 {
            // Child process
            // Set environment
            for (key, value) in environment {
                setenv(key, value, 1)
            }

            // Set TERM
            setenv("TERM", "xterm-256color", 1)

            // Set LANG for UTF-8
            if getenv("LANG") == nil {
                setenv("LANG", "en_US.UTF-8", 1)
            }

            // Execute shell
            var args = [command] + arguments
            let cArgs = args.map { strdup($0) } + [nil]
            execvp(command, cArgs)

            // If exec fails
            _exit(1)
        }

        // Parent process
        self.masterFD = masterFD
        self.childPID = pid
        self.isRunning = true

        // Set non-blocking
        let flags = fcntl(masterFD, F_GETFL)
        fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

        state = .connected
        delegate?.connectionDidConnect()

        startReading()
    }

    func disconnect() {
        isRunning = false

        if childPID > 0 {
            kill(childPID, SIGHUP)
            var status: Int32 = 0
            waitpid(childPID, &status, WNOHANG)
            childPID = 0
        }

        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }

        state = .disconnected
        delegate?.connectionDidDisconnect()
    }

    func send(_ data: Data) {
        guard isConnected && masterFD >= 0 else { return }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            write(masterFD, ptr, data.count)
        }
    }

    func send(_ string: String) {
        send(Data(string.utf8))
    }

    func updateWindowSize() {
        guard masterFD >= 0 else { return }
        var ws = winsize()
        ws.ws_col = windowSize.cols
        ws.ws_row = windowSize.rows
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0
        ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    func resize(cols: UInt16, rows: UInt16) {
        windowSize = (cols, rows)
    }

    private func startReading() {
        readQueue.async { [weak self] in
            guard let self = self else { return }
            let bufferSize = 16384
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            while self.isRunning && self.masterFD >= 0 {
                let bytesRead = read(self.masterFD, &buffer, bufferSize)
                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    DispatchQueue.main.async {
                        self.delegate?.connectionDidReceiveData(data)
                    }
                } else if bytesRead < 0 {
                    if errno == EAGAIN || errno == EINTR {
                        Thread.sleep(forTimeInterval: 0.005)
                        continue
                    }
                    // Process likely exited
                    DispatchQueue.main.async {
                        self.disconnect()
                    }
                    break
                } else {
                    // EOF - process exited
                    DispatchQueue.main.async {
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
    case streamCreationFailed
    case connectionFailed
    case serialPortOpenFailed
    case ptyCreationFailed
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .streamCreationFailed: return "Failed to create network streams"
        case .connectionFailed: return "Connection failed"
        case .serialPortOpenFailed: return "Failed to open serial port"
        case .ptyCreationFailed: return "Failed to create pseudo-terminal"
        case .sendFailed: return "Failed to send data"
        }
    }
}
