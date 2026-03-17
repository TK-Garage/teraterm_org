/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * XPC connection manager for TeraTermMac.app (client side).
 * Manages the connection to TTLMacro.app for macro execution.
 *
 * Uses anonymous listener + endpoint sharing for XPC connection.
 * The endpoint is passed via a temporary file (NSKeyedArchiver serialization).
 */

#if canImport(AppKit)
import AppKit
import os
import TTLMacroShared

// MARK: - MacroXPCManager

/// Manages the XPC connection from TeraTermMac.app to TTLMacro.app.
/// Handles launching TTLMacro.app, establishing XPC connection via
/// anonymous listener endpoint, and forwarding macro service calls.
class MacroXPCManager: NSObject {

    private var connection: NSXPCConnection?
    private var reconnectAttempts: Int = 0
    private let logger = OSLog(subsystem: MacroConstants.teraTermMacBundleId, category: "MacroXPC")
    private var endpointPollTimer: Timer?

    /// PID of the launched TTLMacro process, used to read the correct endpoint file
    private var launchedMacroPID: Int32?

    /// Whether transfer is in progress (exclusion flag)
    private(set) var isTransferInProgress: Bool = false

<<<<<<< HEAD
    /// Receive buffer for macro wait commands
    private var receiveBuffer: String = ""
    private let receiveBufferLock = NSLock()

    /// Terminal data subscribers (for event-driven wait)
    private var terminalDataHandler: ((Data) -> Void)?

    /// Active window controller accessor
    private var activeWindowController: TerminalWindowController? {
        guard let delegate = NSApp.delegate as? AppDelegate else { return nil }
        return delegate.activeTerminalWindowController
    }
=======
    /// Current transfer state reported by FileTransferDelegate
    private var currentTransferState: TransferState = .idle

    /// Current transfer direction (send or receive)
    private var currentTransferDirection: TransferDirection = .send

    /// Weak reference to the terminal's FileTransferManager for progress queries
    weak var fileTransferManager: FileTransferManager?

    /// Weak reference to the owning TerminalWindowController for terminal operations
    weak var terminalController: TerminalWindowController?
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346

    /// The remote macro service proxy
    var macroService: MacroServiceProtocol? {
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            os_log("XPC error: %{public}@", log: self?.logger ?? .default, type: .error,
                   error.localizedDescription)
            self?.handleConnectionError()
        } as? MacroServiceProtocol
    }

    /// Whether the connection is active
    var isConnected: Bool {
        return connection != nil
    }

    // MARK: - Connection Management

    /// Launch TTLMacro.app and establish XPC connection via anonymous listener endpoint.
    func connect(completion: @escaping (Bool) -> Void) {
        // Find TTLMacro.app bundle
        guard let macroAppURL = findTTLMacroApp() else {
            os_log("TTLMacro.app not found", log: logger, type: .error)
            completion(false)
            return
        }

        // Launch TTLMacro.app with --xpc-mode argument
        launchTTLMacro(at: macroAppURL) { [weak self] success in
            guard success else {
                completion(false)
                return
            }
            // Poll for endpoint file from TTLMacro.app
            self?.pollForEndpoint(completion: completion)
        }
    }

    /// Disconnect from TTLMacro.app.
    func disconnect() {
        endpointPollTimer?.invalidate()
        endpointPollTimer = nil
        connection?.invalidate()
        connection = nil
        reconnectAttempts = 0
        isTransferInProgress = false
        currentTransferState = .idle
    }

    // MARK: - TTLMacro.app Launch

    private func findTTLMacroApp() -> URL? {
        // Look for TTLMacro.app in the same directory as TeraTermMac.app
        let mainBundle = Bundle.main
        if let bundlePath = mainBundle.bundlePath as String? {
            let parentDir = (bundlePath as NSString).deletingLastPathComponent
            let macroAppPath = (parentDir as NSString).appendingPathComponent("TTLMacro.app")
            if FileManager.default.fileExists(atPath: macroAppPath) {
                return URL(fileURLWithPath: macroAppPath)
            }
        }

        // Also check in the build products directory
        #if DEBUG
        if let execURL = mainBundle.executableURL {
            let buildDir = execURL.deletingLastPathComponent()
            let macroURL = buildDir.appendingPathComponent("TTLMacro")
            if FileManager.default.fileExists(atPath: macroURL.path) {
                return macroURL
            }
        }
        #endif

        return nil
    }

    private func launchTTLMacro(at url: URL, completion: @escaping (Bool) -> Void) {
        if #available(macOS 10.15, *) {
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = [MacroConstants.xpcModeArgument]
            config.activates = false

            NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] app, error in
                if let error = error {
                    os_log("Failed to launch TTLMacro: %{public}@",
                           log: self?.logger ?? .default, type: .error,
                           error.localizedDescription)
                    completion(false)
                } else {
                    if let pid = app?.processIdentifier {
                        self?.launchedMacroPID = pid
                        os_log("TTLMacro.app launched with PID %d",
                               log: self?.logger ?? .default, type: .info, pid)
                    }
                    completion(true)
                }
            }
        } else {
            completion(false)
        }
    }

    // MARK: - Endpoint-Based XPC Connection

    /// Poll for the endpoint file written by TTLMacro.app
    private func pollForEndpoint(completion: @escaping (Bool) -> Void) {
        let startTime = Date()
        let timeout = MacroXPCEndpoint.connectionTimeout

        endpointPollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            // Check timeout
            if Date().timeIntervalSince(startTime) > timeout {
                timer.invalidate()
                self.endpointPollTimer = nil
                os_log("XPC endpoint poll timeout", log: self.logger, type: .error)
                // Report failure via macroDidFail
                completion(false)
                return
            }

            // Try to read endpoint file for the specific launched PID
            let fm = FileManager.default
            if let pid = self.launchedMacroPID {
                // Use PID-specific endpoint file to avoid connecting to wrong instance
                let filePath = MacroXPCEndpoint.endpointFilePath(pid: pid)
                if let data = fm.contents(atPath: filePath),
                   let endpoint = try? NSKeyedUnarchiver.unarchivedObject(
                       ofClass: NSXPCListenerEndpoint.self, from: data) {
                    timer.invalidate()
                    self.endpointPollTimer = nil
                    try? fm.removeItem(atPath: filePath)
                    self.establishXPCConnection(endpoint: endpoint)
                    completion(true)
                    return
                }
            } else {
                // Fallback: scan all endpoint files (when PID is unknown)
                let tmpDir = NSTemporaryDirectory()
                if let files = try? fm.contentsOfDirectory(atPath: tmpDir) {
                    for file in files where file.hasPrefix("ttlmacro_endpoint_") && file.hasSuffix(".dat") {
                        let filePath = (tmpDir as NSString).appendingPathComponent(file)
                        if let data = fm.contents(atPath: filePath),
                           let endpoint = try? NSKeyedUnarchiver.unarchivedObject(
                               ofClass: NSXPCListenerEndpoint.self, from: data) {
                            timer.invalidate()
                            self.endpointPollTimer = nil
                            try? fm.removeItem(atPath: filePath)
                            self.establishXPCConnection(endpoint: endpoint)
                            completion(true)
                            return
                        }
                    }
                }
            }
        }
    }

    /// Establish XPC connection using the endpoint from TTLMacro.app's anonymous listener.
    private func establishXPCConnection(endpoint: NSXPCListenerEndpoint) {
        let conn = NSXPCConnection(listenerEndpoint: endpoint)

        // What we provide (MacroClientProtocol)
        conn.exportedInterface = MacroXPCInterface.clientInterface()
        conn.exportedObject = self

        // What TTLMacro provides (MacroServiceProtocol)
        conn.remoteObjectInterface = MacroXPCInterface.serviceInterface()

        conn.invalidationHandler = { [weak self] in
            os_log("XPC connection invalidated", log: self?.logger ?? .default, type: .info)
            self?.connection = nil
            self?.handleConnectionError()
        }

        conn.interruptionHandler = { [weak self] in
            os_log("XPC connection interrupted", log: self?.logger ?? .default, type: .error)
            self?.handleConnectionError()
        }

        conn.resume()
        connection = conn
        reconnectAttempts = 0

        os_log("XPC connection established via anonymous listener endpoint",
               log: logger, type: .info)
    }

    /// Callback invoked when XPC connection is lost and recovery fails.
    var onConnectionLost: (() -> Void)?

    /// The last macro script path, used for auto-recovery after crash.
    private var lastMacroScriptPath: String?

    // MARK: - Error Handling & Reconnection

    private func handleConnectionError() {
        DispatchQueue.main.async { [weak self] in
            self?._handleConnectionErrorOnMain()
        }
    }

    private func _handleConnectionErrorOnMain() {
        guard reconnectAttempts < MacroConstants.maxReconnectAttempts else {
            os_log("Max reconnection attempts (%d) reached, giving up",
                   log: logger, type: .error, MacroConstants.maxReconnectAttempts)
            connection = nil
            isTransferInProgress = false
            onConnectionLost?()
            return
        }

        reconnectAttempts += 1
        let delay = MacroConstants.reconnectInterval * Double(reconnectAttempts)

        os_log("XPC connection lost. Attempting reconnection %d/%d in %.1f seconds",
               log: logger, type: .info,
               reconnectAttempts, MacroConstants.maxReconnectAttempts, delay)

        // Invalidate stale connection
        connection?.invalidate()
        connection = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }

            guard let macroAppURL = self.findTTLMacroApp() else {
                os_log("TTLMacro.app not found during reconnection",
                       log: self.logger, type: .error)
                self.onConnectionLost?()
                return
            }

            os_log("Re-launching TTLMacro.app for reconnection",
                   log: self.logger, type: .info)

            self.launchTTLMacro(at: macroAppURL) { [weak self] success in
                guard let self = self, success else {
                    os_log("Failed to re-launch TTLMacro.app",
                           log: self?.logger ?? .default, type: .error)
                    self?.handleConnectionError()
                    return
                }
                self.pollForEndpoint { [weak self] connected in
                    if connected {
                        os_log("XPC reconnection successful (attempt %d)",
                               log: self?.logger ?? .default, type: .info,
                               self?.reconnectAttempts ?? 0)
                        self?.reconnectAttempts = 0

                        // Re-run the macro if one was active
                        if let scriptPath = self?.lastMacroScriptPath {
                            self?.macroService?.runMacro(scriptPath: scriptPath) { error in
                                if let error = error {
                                    os_log("Failed to re-run macro after reconnection: %{public}@",
                                           log: self?.logger ?? .default, type: .error,
                                           error.localizedDescription)
                                }
                            }
                        }
                    } else {
                        self?.handleConnectionError()
                    }
                }
            }
        }
    }

    /// Record the script path for auto-recovery after crash.
    func setActiveMacroPath(_ path: String?) {
        lastMacroScriptPath = path
    }
}

// MARK: - MacroClientProtocol Implementation

extension MacroXPCManager: MacroClientProtocol {

    // MARK: - Data Transfer

    func sendToTerminal(data: Data, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.connectionManager.send(data)
=======
            self?.terminalController?.connectionManager.send(data)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func recvFromTerminal(timeout: Int, reply: @escaping (Data?) -> Void) {
<<<<<<< HEAD
        receiveBufferLock.lock()
        if !receiveBuffer.isEmpty {
            let data = receiveBuffer.data(using: .utf8)
            receiveBuffer = ""
            receiveBufferLock.unlock()
            reply(data)
        } else {
            receiveBufferLock.unlock()
            if timeout <= 0 {
                reply(nil)
            } else {
                // Set up handler for next data arrival
                terminalDataHandler = { data in
                    reply(data)
                }
                // Timeout fallback
                DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(timeout)) { [weak self] in
                    if let handler = self?.terminalDataHandler {
                        self?.terminalDataHandler = nil
                        handler(Data())
                    }
                }
=======
        DispatchQueue.main.async { [weak self] in
            guard let ctrl = self?.terminalController else {
                reply(nil)
                return
            }
            let data = ctrl.terminalEmulator.macroReceiveBuffer
            if !data.isEmpty {
                ctrl.terminalEmulator.macroReceiveBuffer = ""
                reply(Data(data.utf8))
            } else {
                reply(nil)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            }
        }
    }

    /// Called by TerminalWindowController when data is received from terminal
    func terminalDidReceiveData(_ data: Data) {
        if let handler = terminalDataHandler {
            terminalDataHandler = nil
            handler(data)
        }
        if let str = String(data: data, encoding: .utf8) {
            receiveBufferLock.lock()
            receiveBuffer += str
            receiveBufferLock.unlock()
        }
    }

    // MARK: - Dialog

    func showDialog(type: String, message: String, defaultValue: String,
                    reply: @escaping (Int, String) -> Void) {
        MacroDialogHelper.showDialog(type: type, message: message,
                                     defaultValue: defaultValue, completion: reply)
    }

    // MARK: - Window Title

    func setWindowTitle(title: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.window?.title = title
=======
            self?.terminalController?.window?.title = title
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    // MARK: - Lifecycle Notifications

    func macroDidFinish(exitCode: Int, reply: @escaping () -> Void) {
        os_log("Macro finished with exit code %d", log: logger, type: .info, exitCode)
        reply()
    }

    func macroDidFail(error: String, line: Int, reply: @escaping () -> Void) {
        os_log("Macro failed at line %d: %{public}@", log: logger, type: .error, line, error)
        reply()
    }

    func logMessage(level: String, text: String, reply: @escaping () -> Void) {
        os_log("Macro [%{public}@]: %{public}@", log: logger, type: .info, level, text)
        reply()
    }

    func terminateApp(reply: @escaping () -> Void) {
        os_log("Received terminate request from macro", log: logger, type: .info)
        DispatchQueue.main.async {
            reply()
            NSApp.terminate(nil)
        }
    }

    func getAppVersion(reply: @escaping (String) -> Void) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        reply(version)
    }

    func didExecuteLine(lineNumber: Int, lineText: String, reply: @escaping () -> Void) {
        reply()
    }

    // MARK: - Terminal Operations

    func isConnected(reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            let connected = self?.activeWindowController?.isConnected ?? false
            reply(connected)
=======
            reply(self?.terminalController?.isConnected ?? false)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
        }
    }

    func isXPCLinked(reply: @escaping (Bool) -> Void) {
        // XPC link is active if this manager has a valid connection
        reply(connection != nil)
    }

    func getWindowTitle(reply: @escaping (String) -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            let title = self?.activeWindowController?.window?.title ?? ""
            reply(title)
=======
            reply(self?.terminalController?.window?.title ?? "")
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
        }
    }

    func showWindow(visible: Bool, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            if visible {
<<<<<<< HEAD
                self?.activeWindowController?.window?.orderFront(nil)
            } else {
                self?.activeWindowController?.window?.orderOut(nil)
=======
                self?.terminalController?.window?.makeKeyAndOrderFront(nil)
            } else {
                self?.terminalController?.window?.orderOut(nil)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            }
            reply()
        }
    }

    func clearScreen(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.clearScreen()
=======
            self?.terminalController?.clearScreen()
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func sendBreak(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.connectionManager.sendBreak()
=======
            self?.terminalController?.connectionManager.sendBreak()
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    // MARK: - Connection

    func disconnectFromHost(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.disconnect()
=======
            self?.terminalController?.disconnect()
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func connectToHost(param: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            guard let wc = self?.activeWindowController else {
                reply(false)
                return
            }
            // Parse connection param: "host:port" or "/C=N" for serial
            let parts = param.components(separatedBy: ":")
            if parts.count >= 2, let port = Int(parts[1]) {
                wc.connectTCP(host: parts[0], port: port)
                reply(true)
            } else if param.hasPrefix("/C=") {
                let device = String(param.dropFirst(3))
                wc.connectSerial(device: device)
                reply(true)
            } else if !param.isEmpty {
                wc.connectTCP(host: param, port: 23)
                reply(true)
            } else {
                reply(false)
            }
=======
            guard let ctrl = self?.terminalController else {
                reply(false)
                return
            }
            // Parse connection string: "host:port" or "/dev/ttyXXX"
            if param.hasPrefix("/dev/") {
                ctrl.connectSerial(device: param)
            } else {
                let parts = param.components(separatedBy: ":")
                let host = parts.first ?? "localhost"
                let port = parts.count > 1 ? (Int(parts[1]) ?? 23) : 23
                ctrl.connectTCP(host: host, port: port)
            }
            // Connection is async; report success that the attempt was initiated
            reply(true)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
        }
    }

    func connectLocalShell(reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.connectLocalShell()
=======
            guard let ctrl = self?.terminalController else {
                reply(false)
                return
            }
            ctrl.connectLocalShell()
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply(true)
        }
    }

    func flushReceiveBuffer(reply: @escaping () -> Void) {
<<<<<<< HEAD
        receiveBufferLock.lock()
        receiveBuffer = ""
        receiveBufferLock.unlock()
        reply()
=======
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.terminalEmulator.macroReceiveBuffer = ""
            reply()
        }
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
    }

    // MARK: - Window Operations

    func moveWindow(x: Int, y: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.window?.setFrameOrigin(NSPoint(x: x, y: y))
=======
            self?.terminalController?.window?.setFrameOrigin(NSPoint(x: x, y: y))
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func resizeWindow(width: Int, height: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            guard let window = self?.activeWindowController?.window else {
                reply()
                return
            }
            var frame = window.frame
            frame.size = NSSize(width: width, height: height)
            window.setFrame(frame, display: true)
=======
            guard let win = self?.terminalController?.window else {
                reply()
                return
            }
            var frame = win.frame
            frame.size = NSSize(width: width, height: height)
            win.setFrame(frame, display: true)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func bringWindowToFront(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
=======
            self?.terminalController?.window?.makeKeyAndOrderFront(nil)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func getWindowPosition(reply: @escaping (Int, Int) -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            let origin = self?.activeWindowController?.window?.frame.origin ?? .zero
=======
            let origin = self?.terminalController?.window?.frame.origin ?? .zero
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply(Int(origin.x), Int(origin.y))
        }
    }

    // MARK: - Serial Settings

    func setBaudRate(rate: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.settings.baudRate = rate
=======
            self?.terminalController?.settings.baudRate = rate
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func setFlowControl(mode: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            if let fc = FlowControl(rawValue: mode) {
                self?.activeWindowController?.settings.flowControl = fc
            }
=======
            self?.terminalController?.ttlSetFlowCtrl(mode)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func setDtr(on: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.connectionManager.setControlSignal(.dtr, value: on != 0)
=======
            self?.terminalController?.ttlSetDtr(on)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func setRts(on: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.connectionManager.setControlSignal(.rts, value: on != 0)
=======
            self?.terminalController?.ttlSetRts(on)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func getModemStatus(reply: @escaping (Int) -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            let status = self?.activeWindowController?.connectionManager.getModemStatus() ?? 0
            reply(status)
=======
            guard let ctrl = self?.terminalController,
                  let serial = ctrl.connectionManager.currentConnection as? SerialConnection else {
                // Not a serial connection — return 0
                reply(0)
                return
            }
            reply(serial.getModemStatus())
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
        }
    }

    func setSerialDelayChar(ms: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.settings.serialDelayPerChar = ms
=======
            self?.terminalController?.settings.serialDelayPerChar = ms
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func setSerialDelayLine(ms: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.settings.serialDelayPerLine = ms
=======
            self?.terminalController?.settings.serialDelayPerLine = ms
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    // MARK: - Log Operations

    func openLog(path: String, append: Bool, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            _ = self?.activeWindowController?.logger.startLogging(to: path)
=======
            self?.terminalController?.ttlLogOpen(path, append: append)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func closeLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.logger.stopLogging()
=======
            self?.terminalController?.ttlLogClose()
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func pauseLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.logger.pauseLogging()
=======
            self?.terminalController?.ttlLogPause()
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func resumeLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.logger.resumeLogging()
=======
            self?.terminalController?.ttlLogStart()
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func writeToLog(text: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            if let data = text.data(using: .utf8) {
                self?.activeWindowController?.logger.logData(data)
            }
=======
            self?.terminalController?.ttlLogWrite(text)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func getLogInfo(reply: @escaping (Int, String) -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            let loggerObj = self?.activeWindowController?.logger
            let stateVal: Int
            switch loggerObj?.state {
            case .active: stateVal = 1
            case .paused: stateVal = 2
            default: stateVal = 0
            }
            let path = loggerObj?.logFilePath ?? ""
            reply(stateVal, path)
=======
            let info = self?.terminalController?.ttlLogInfo() ?? (state: -1, filePath: "")
            reply(info.state, info.filePath)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
        }
    }

    func setLogRotation(mode: String, value: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            if mode == "size" {
                self?.activeWindowController?.logger.setRotation(size: value)
            }
=======
            self?.terminalController?.ttlLogRotateSet(mode: mode, value: value)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    // MARK: - Clipboard

    func getClipboard(reply: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            reply(text)
        }
    }

    func setClipboard(text: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            reply()
        }
    }

    // MARK: - System Info

    func getHostname(reply: @escaping (String) -> Void) {
        reply(ProcessInfo.processInfo.hostName)
    }

    func getAppDirectory(reply: @escaping (String) -> Void) {
        let dir = Bundle.main.bundlePath
        reply((dir as NSString).deletingLastPathComponent)
    }

    // MARK: - Error Display

    func showError(message: String, line: Int, lineText: String, fileName: String,
                   reply: @escaping (Bool) -> Void) {
<<<<<<< HEAD
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Macro Error (line \(line))"
            alert.informativeText = "\(message)\n\n\(lineText)\n\nFile: \(fileName)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Stop")
            alert.addButton(withTitle: "Continue")
            let response = alert.runModal()
            reply(response == .alertFirstButtonReturn)
=======
        DispatchQueue.main.async { [weak self] in
            guard let ctrl = self?.terminalController else {
                reply(true)
                return
            }
            ctrl.ttlShowError(message, line: line, lineText: lineText, fileName: fileName, completion: reply)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
        }
    }

    func showStatusBox(message: String, title: String, reply: @escaping () -> Void) {
<<<<<<< HEAD
        DispatchQueue.main.async {
            // Show a non-modal status window
            let alert = NSAlert()
            alert.messageText = title.isEmpty ? "Status" : title
            alert.informativeText = message
            alert.alertStyle = .informational
            // Don't run modal - just show the window
            let window = alert.window
            window.orderFront(nil)
=======
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlShowStatusBox(message, title: title)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func closeStatusBox(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlCloseStatusBox()
            reply()
        }
    }

    // MARK: - File Transfer

    func startFileSend(protocolName: String, localPath: String, option: String,
                       reply: @escaping (Bool, String) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                reply(false, "Manager deallocated")
                return
            }
            guard !self.isTransferInProgress else {
                reply(false, "Transfer already in progress")
                return
            }
            guard let wc = self.activeWindowController else {
                reply(false, "No active terminal window")
                return
            }
            self.isTransferInProgress = true
<<<<<<< HEAD
            if let protocolType = TransferProtocolType.from(name: protocolName) {
                wc.fileTransferManager.startTransfer(protocol: protocolType, direction: .send, filePath: localPath)
                reply(true, "")
            } else {
                self.isTransferInProgress = false
                reply(false, "Unknown protocol: \(protocolName)")
            }
=======
            self.currentTransferDirection = .send
            self.currentTransferState = .starting

            guard let ctrl = self.terminalController,
                  let protocolType = TransferProtocolType.from(protocolName) else {
                self.isTransferInProgress = false
                reply(false, "Invalid protocol or no terminal")
                return
            }

            // Take over as FileTransferManager delegate during XPC transfer
            // so that currentTransferState is updated for status polling.
            // Delegate is restored in transferDidComplete/transferDidFail.
            ctrl.fileTransferManager.delegate = self

            ctrl.ttlStartFileTransfer(
                protocol: protocolType, direction: .send, filePath: localPath
            ) { [weak self] success in
                if !success {
                    self?.isTransferInProgress = false
                    self?.currentTransferState = .idle
                    self?.restoreTerminalDelegate()
                }
            }
            reply(true, "")
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
        }
    }

    func startFileRecv(protocolName: String, localDir: String,
                       reply: @escaping (Bool, String, String) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                reply(false, "Manager deallocated", "")
                return
            }
            guard !self.isTransferInProgress else {
                reply(false, "Transfer already in progress", "")
                return
            }
            guard let wc = self.activeWindowController else {
                reply(false, "No active terminal window", "")
                return
            }
            self.isTransferInProgress = true
<<<<<<< HEAD
            if let protocolType = TransferProtocolType.from(name: protocolName) {
                wc.fileTransferManager.startTransfer(protocol: protocolType, direction: .receive, filePath: localDir)
                reply(true, "", "")
            } else {
                self.isTransferInProgress = false
                reply(false, "Unknown protocol: \(protocolName)", "")
            }
=======
            self.currentTransferDirection = .receive
            self.currentTransferState = .starting

            guard let ctrl = self.terminalController,
                  let protocolType = TransferProtocolType.from(protocolName) else {
                self.isTransferInProgress = false
                reply(false, "Invalid protocol or no terminal", "")
                return
            }

            // Take over as FileTransferManager delegate during XPC transfer
            ctrl.fileTransferManager.delegate = self

            ctrl.ttlStartFileTransfer(
                protocol: protocolType, direction: .receive, filePath: localDir
            ) { [weak self] success in
                if !success {
                    self?.isTransferInProgress = false
                    self?.currentTransferState = .idle
                    self?.restoreTerminalDelegate()
                }
            }
            reply(true, "", "")
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
        }
    }

    func getTransferStatus(reply: @escaping (String, Int64, Int64) -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            if self?.isTransferInProgress == true {
<<<<<<< HEAD
                // TODO: Track actual transfer progress (bytes transferred, total size)
                reply(TransferStatusString.sending.rawValue, 0, 0)
=======
                let ftm = self?.activeWindowController?.fileTransferManager
                let isActive = ftm?.isTransferActive ?? false
                if isActive {
                    reply(TransferStatusString.sending.rawValue, 0, 0)
                } else {
                    self?.isTransferInProgress = false
                    reply(TransferStatusString.done.rawValue, 0, 0)
                }
>>>>>>> 14ace800810249512edfe0279d0f325844bf0b8e
            } else {
=======
            guard let self = self else {
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
                reply(TransferStatusString.idle.rawValue, 0, 0)
                return
            }

            switch self.currentTransferState {
            case .inProgress(let bytesTransferred, let totalBytes, _):
                let status: TransferStatusString =
                    self.currentTransferDirection == .send ? .sending : .receiving
                reply(status.rawValue, bytesTransferred, totalBytes ?? 0)

            case .completed:
                self.isTransferInProgress = false
                reply(TransferStatusString.done.rawValue, 0, 0)

            case .failed:
                self.isTransferInProgress = false
                reply(TransferStatusString.error.rawValue, 0, 0)

            case .cancelled:
                self.isTransferInProgress = false
                reply(TransferStatusString.idle.rawValue, 0, 0)

            case .starting, .completing:
                reply(TransferStatusString.sending.rawValue, 0, 0)

            case .idle:
                if self.isTransferInProgress {
                    reply(TransferStatusString.sending.rawValue, 0, 0)
                } else {
                    reply(TransferStatusString.idle.rawValue, 0, 0)
                }
            }
        }
    }

    func cancelTransfer(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.fileTransferManager.cancelCurrentTransfer()
=======
            self?.fileTransferManager?.cancelTransfer()
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            self?.isTransferInProgress = false
            self?.currentTransferState = .idle
            reply()
        }
    }

    // MARK: - SCP

    func scpSend(localPath: String, remotePath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            guard let wc = self?.activeWindowController else {
                reply(false)
                return
            }
            // SCP requires SSH connection
            wc.connectionManager.scpSend(localPath: localPath, remotePath: remotePath) { success in
=======
            guard let ctrl = self?.terminalController else {
                reply(false)
                return
            }
            ctrl.ttlScpSend(localPath: localPath, remotePath: remotePath) { success in
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
                reply(success)
            }
        }
    }

    func scpRecv(remotePath: String, localPath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            guard let wc = self?.activeWindowController else {
                reply(false)
                return
            }
            wc.connectionManager.scpRecv(remotePath: remotePath, localPath: localPath) { success in
=======
            guard let ctrl = self?.terminalController else {
                reply(false)
                return
            }
            ctrl.ttlScpRecv(remotePath: remotePath, localPath: localPath) { success in
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
                reply(success)
            }
        }
    }

    // MARK: - Settings

    func restoreSetup(path: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            let settings = TerminalSettings.load(from: URL(fileURLWithPath: path))
            self?.activeWindowController?.settings = settings
=======
            self?.terminalController?.ttlRestoreSetup(from: path)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func callMenu(menuId: Int, reply: @escaping () -> Void) {
<<<<<<< HEAD
        DispatchQueue.main.async {
            // Search menu items recursively by tag
            func findItem(in menu: NSMenu, tag: Int) -> NSMenuItem? {
                for item in menu.items {
                    if item.tag == tag { return item }
                    if let sub = item.submenu, let found = findItem(in: sub, tag: tag) {
                        return found
                    }
                }
                return nil
            }
            if let mainMenu = NSApp.mainMenu,
               let item = findItem(in: mainMenu, tag: menuId),
               let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
            }
=======
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlCallMenu(menuId: menuId)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func loadKeyMap(path: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.keyboardHandler.loadKeyMapping(from: path)
=======
            self?.terminalController?.ttlLoadKeyMap(from: path)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func enableKeyboard(flag: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.keyboardHandler.keyboardEnabled = (flag != 0)
=======
            self?.terminalController?.keyboardHandler.isEnabled = (flag != 0)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func setEcho(flag: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            self?.activeWindowController?.settings.localEcho = (flag != 0)
=======
            self?.terminalController?.settings.localEcho = (flag != 0)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func displayString(text: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            if let data = text.data(using: .utf8) {
                self?.activeWindowController?.terminalEmulator.processData(data)
                self?.activeWindowController?.terminalView.refresh()
            }
=======
            self?.terminalController?.terminalEmulator.processData(Data(text.utf8))
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func sendPasswordData(data: Data, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
<<<<<<< HEAD
            // Send password data directly without logging
            self?.activeWindowController?.connectionManager.send(data)
            reply()
        }
    }

    // MARK: - Broadcast / Multicast

    func broadcastData(data: Data, reply: @escaping (Int) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let count = self?.broadcastData(data) ?? 0
            reply(count)
        }
    }

    func setMulticastName(name: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.multicastGroupName = name
            reply()
        }
    }

    func multicastData(groupName: String, data: Data, reply: @escaping (Int) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let count = self?.multicastData(data, groupName: groupName) ?? 0
            reply(count)
        }
    }

    func getSessionList(reply: @escaping ([String]) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let sessions = self?.getSessionList() ?? []
            reply(sessions)
        }
    }

    func sendToSession(sessionId: String, data: Data, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let delegate = NSApp.delegate as? AppDelegate else {
                reply(false)
                return
            }
            if let wc = delegate.allTerminalWindowControllers.first(where: { $0.sessionId == sessionId }) {
                wc.connectionManager.send(data)
                reply(true)
            } else {
                reply(false)
            }
        }
    }

    func subscribeToTerminalData(reply: @escaping (Data) -> Void) {
        // Set the handler for event-driven terminal data reception
        terminalDataHandler = reply
    }

    func setTerminalSize(cols: Int, rows: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.terminalView.setTerminalSize(cols: cols, rows: rows)
=======
            // Send password data directly to terminal without logging
            self?.terminalController?.connectionManager.send(data)
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
            reply()
        }
    }

    func waitWindowEvent(timeout: Int, reply: @escaping (Int) -> Void) {
        let timeoutSec = max(timeout, 0)
        let deadline = Date().addingTimeInterval(Double(timeoutSec))

        func poll() {
            DispatchQueue.main.async { [weak self] in
                guard let ctrl = self?.terminalController else {
                    reply(0)
                    return
                }
                let event = ctrl.dequeueWindowEvent()
                if event != 0 {
                    reply(event)
                    return
                }
                if Date() >= deadline {
                    reply(0) // timeout
                    return
                }
                // Poll every 100ms
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    poll()
                }
            }
        }
        poll()
    }
}

// MARK: - FileTransferDelegate

extension MacroXPCManager: FileTransferDelegate {

    func transferDidUpdateState(_ state: TransferState) {
        currentTransferState = state
    }

    func transferDidRequestSend(_ data: Data) {
        // Forward send requests to the terminal's connection manager
        terminalController?.connectionManager.send(data)
    }

    func transferDidComplete(fileName: String, bytes: Int64) {
        currentTransferState = .completed(fileName: fileName, bytes: bytes)
        isTransferInProgress = false
        // Also notify the terminal controller (for UI updates like panel close)
        terminalController?.transferDidComplete(fileName: fileName, bytes: bytes)
        restoreTerminalDelegate()
    }

    func transferDidFail(error: String) {
        currentTransferState = .failed(error: error)
        isTransferInProgress = false
        terminalController?.transferDidFail(error: error)
        restoreTerminalDelegate()
    }

    /// Restore the FileTransferManager delegate back to TerminalWindowController
    /// after XPC-initiated transfer completes.
    private func restoreTerminalDelegate() {
        if let ctrl = terminalController {
            fileTransferManager?.delegate = ctrl
        }
    }
}

#endif
