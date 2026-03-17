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
            self?.activeWindowController?.connectionManager.send(data)
            reply()
        }
    }

    func recvFromTerminal(timeout: Int, reply: @escaping (Data?) -> Void) {
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
            self?.activeWindowController?.window?.title = title
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
            let connected = self?.activeWindowController?.isConnected ?? false
            reply(connected)
        }
    }

    func getWindowTitle(reply: @escaping (String) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let title = self?.activeWindowController?.window?.title ?? ""
            reply(title)
        }
    }

    func showWindow(visible: Bool, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            if visible {
                self?.activeWindowController?.window?.orderFront(nil)
            } else {
                self?.activeWindowController?.window?.orderOut(nil)
            }
            reply()
        }
    }

    func clearScreen(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.clearScreen()
            reply()
        }
    }

    func sendBreak(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.connectionManager.sendBreak()
            reply()
        }
    }

    // MARK: - Connection

    func disconnectFromHost(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.disconnect()
            reply()
        }
    }

    func connectToHost(param: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
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
        }
    }

    func connectLocalShell(reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.connectLocalShell()
            reply(true)
        }
    }

    func flushReceiveBuffer(reply: @escaping () -> Void) {
        receiveBufferLock.lock()
        receiveBuffer = ""
        receiveBufferLock.unlock()
        reply()
    }

    // MARK: - Window Operations

    func moveWindow(x: Int, y: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.window?.setFrameOrigin(NSPoint(x: x, y: y))
            reply()
        }
    }

    func resizeWindow(width: Int, height: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.activeWindowController?.window else {
                reply()
                return
            }
            var frame = window.frame
            frame.size = NSSize(width: width, height: height)
            window.setFrame(frame, display: true)
            reply()
        }
    }

    func bringWindowToFront(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            reply()
        }
    }

    func getWindowPosition(reply: @escaping (Int, Int) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let origin = self?.activeWindowController?.window?.frame.origin ?? .zero
            reply(Int(origin.x), Int(origin.y))
        }
    }

    // MARK: - Serial Settings

    func setBaudRate(rate: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.settings.baudRate = rate
            reply()
        }
    }

    func setFlowControl(mode: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            if let fc = FlowControl(rawValue: mode) {
                self?.activeWindowController?.settings.flowControl = fc
            }
            reply()
        }
    }

    func setDtr(on: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.connectionManager.setControlSignal(.dtr, value: on != 0)
            reply()
        }
    }

    func setRts(on: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.connectionManager.setControlSignal(.rts, value: on != 0)
            reply()
        }
    }

    func getModemStatus(reply: @escaping (Int) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let status = self?.activeWindowController?.connectionManager.getModemStatus() ?? 0
            reply(status)
        }
    }

    func setSerialDelayChar(ms: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.settings.serialDelayPerChar = ms
            reply()
        }
    }

    func setSerialDelayLine(ms: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.settings.serialDelayPerLine = ms
            reply()
        }
    }

    // MARK: - Log Operations

    func openLog(path: String, append: Bool, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            _ = self?.activeWindowController?.logger.startLogging(to: path)
            reply()
        }
    }

    func closeLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.logger.stopLogging()
            reply()
        }
    }

    func pauseLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.logger.pauseLogging()
            reply()
        }
    }

    func resumeLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.logger.resumeLogging()
            reply()
        }
    }

    func writeToLog(text: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            if let data = text.data(using: .utf8) {
                self?.activeWindowController?.logger.logData(data)
            }
            reply()
        }
    }

    func getLogInfo(reply: @escaping (Int, String) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let loggerObj = self?.activeWindowController?.logger
            let stateVal: Int
            switch loggerObj?.state {
            case .active: stateVal = 1
            case .paused: stateVal = 2
            default: stateVal = 0
            }
            let path = loggerObj?.logFilePath ?? ""
            reply(stateVal, path)
        }
    }

    func setLogRotation(mode: String, value: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            if mode == "size" {
                self?.activeWindowController?.logger.setRotation(size: value)
            }
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
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Macro Error (line \(line))"
            alert.informativeText = "\(message)\n\n\(lineText)\n\nFile: \(fileName)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Stop")
            alert.addButton(withTitle: "Continue")
            let response = alert.runModal()
            reply(response == .alertFirstButtonReturn)
        }
    }

    func showStatusBox(message: String, title: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            // Show a non-modal status window
            let alert = NSAlert()
            alert.messageText = title.isEmpty ? "Status" : title
            alert.informativeText = message
            alert.alertStyle = .informational
            // Don't run modal - just show the window
            let window = alert.window
            window.orderFront(nil)
            reply()
        }
    }

    func closeStatusBox(reply: @escaping () -> Void) {
        DispatchQueue.main.async {
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
            if let protocolType = TransferProtocolType.from(name: protocolName) {
                wc.fileTransferManager.startTransfer(protocol: protocolType, direction: .send, filePath: localPath)
                reply(true, "")
            } else {
                self.isTransferInProgress = false
                reply(false, "Unknown protocol: \(protocolName)")
            }
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
            if let protocolType = TransferProtocolType.from(name: protocolName) {
                wc.fileTransferManager.startTransfer(protocol: protocolType, direction: .receive, filePath: localDir)
                reply(true, "", "")
            } else {
                self.isTransferInProgress = false
                reply(false, "Unknown protocol: \(protocolName)", "")
            }
        }
    }

    func getTransferStatus(reply: @escaping (String, Int, Int) -> Void) {
        DispatchQueue.main.async { [weak self] in
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
                reply(TransferStatusString.idle.rawValue, 0, 0)
            }
        }
    }

    func cancelTransfer(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.fileTransferManager.cancelCurrentTransfer()
            self?.isTransferInProgress = false
            reply()
        }
    }

    // MARK: - SCP

    func scpSend(localPath: String, remotePath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let wc = self?.activeWindowController else {
                reply(false)
                return
            }
            // SCP requires SSH connection
            wc.connectionManager.scpSend(localPath: localPath, remotePath: remotePath) { success in
                reply(success)
            }
        }
    }

    func scpRecv(remotePath: String, localPath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let wc = self?.activeWindowController else {
                reply(false)
                return
            }
            wc.connectionManager.scpRecv(remotePath: remotePath, localPath: localPath) { success in
                reply(success)
            }
        }
    }

    // MARK: - Settings

    func restoreSetup(path: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            let settings = TerminalSettings.load(from: URL(fileURLWithPath: path))
            self?.activeWindowController?.settings = settings
            reply()
        }
    }

    func callMenu(menuId: Int, reply: @escaping () -> Void) {
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
            reply()
        }
    }

    func loadKeyMap(path: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.keyboardHandler.loadKeyMapping(from: path)
            reply()
        }
    }

    func enableKeyboard(flag: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.keyboardHandler.keyboardEnabled = (flag != 0)
            reply()
        }
    }

    func setEcho(flag: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.activeWindowController?.settings.localEcho = (flag != 0)
            reply()
        }
    }

    func displayString(text: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            if let data = text.data(using: .utf8) {
                self?.activeWindowController?.terminalEmulator.processData(data)
                self?.activeWindowController?.terminalView.refresh()
            }
            reply()
        }
    }

    func sendPasswordData(data: Data, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
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
            reply()
        }
    }
}

#endif
