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

    /// Current transfer state reported by FileTransferDelegate
    private var currentTransferState: TransferState = .idle

    /// Current transfer direction (send or receive)
    private var currentTransferDirection: TransferDirection = .send

    /// Weak reference to the terminal's FileTransferManager for progress queries
    weak var fileTransferManager: FileTransferManager?

    /// Weak reference to the owning TerminalWindowController for terminal operations
    weak var terminalController: TerminalWindowController?

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

    // MARK: - Error Handling & Reconnection

    private func handleConnectionError() {
        guard reconnectAttempts < MacroConstants.maxReconnectAttempts else {
            os_log("Max reconnection attempts reached", log: logger, type: .error)
            return
        }

        reconnectAttempts += 1
        let delay = MacroConstants.reconnectInterval

        os_log("Attempting reconnection %d/%d in %.1f seconds",
               log: logger, type: .info,
               reconnectAttempts, MacroConstants.maxReconnectAttempts, delay)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            // Cannot reconnect without a new endpoint, so just log
            os_log("Reconnection would require re-launch of TTLMacro",
                   log: self?.logger ?? .default, type: .error)
        }
    }
}

// MARK: - MacroClientProtocol Implementation

extension MacroXPCManager: MacroClientProtocol {

    func sendToTerminal(data: Data, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.connectionManager.send(data)
            reply()
        }
    }

    func recvFromTerminal(timeout: Int, reply: @escaping (Data?) -> Void) {
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
            }
        }
    }

    func showDialog(type: String, message: String, defaultValue: String,
                    reply: @escaping (Int, String) -> Void) {
        MacroDialogHelper.showDialog(type: type, message: message,
                                     defaultValue: defaultValue, completion: reply)
    }

    func setWindowTitle(title: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.window?.title = title
            reply()
        }
    }

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

    // --- New terminal operation methods ---

    func isConnected(reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            reply(self?.terminalController?.isConnected ?? false)
        }
    }

    func isXPCLinked(reply: @escaping (Bool) -> Void) {
        // XPC link is active if this manager has a valid connection
        reply(connection != nil)
    }

    func getWindowTitle(reply: @escaping (String) -> Void) {
        DispatchQueue.main.async { [weak self] in
            reply(self?.terminalController?.window?.title ?? "")
        }
    }

    func showWindow(visible: Bool, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            if visible {
                self?.terminalController?.window?.makeKeyAndOrderFront(nil)
            } else {
                self?.terminalController?.window?.orderOut(nil)
            }
            reply()
        }
    }

    func clearScreen(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.clearScreen()
            reply()
        }
    }

    func sendBreak(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.connectionManager.sendBreak()
            reply()
        }
    }

    func disconnectFromHost(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.disconnect()
            reply()
        }
    }

    func connectToHost(param: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
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
        }
    }

    func connectLocalShell(reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let ctrl = self?.terminalController else {
                reply(false)
                return
            }
            ctrl.connectLocalShell()
            reply(true)
        }
    }

    func flushReceiveBuffer(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.terminalEmulator.macroReceiveBuffer = ""
            reply()
        }
    }

    func moveWindow(x: Int, y: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.window?.setFrameOrigin(NSPoint(x: x, y: y))
            reply()
        }
    }

    func resizeWindow(width: Int, height: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let win = self?.terminalController?.window else {
                reply()
                return
            }
            var frame = win.frame
            frame.size = NSSize(width: width, height: height)
            win.setFrame(frame, display: true)
            reply()
        }
    }

    func bringWindowToFront(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.window?.makeKeyAndOrderFront(nil)
            reply()
        }
    }

    func getWindowPosition(reply: @escaping (Int, Int) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let origin = self?.terminalController?.window?.frame.origin ?? .zero
            reply(Int(origin.x), Int(origin.y))
        }
    }

    func setBaudRate(rate: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.settings.baudRate = rate
            reply()
        }
    }

    func setFlowControl(mode: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlSetFlowCtrl(mode)
            reply()
        }
    }

    func setDtr(on: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlSetDtr(on)
            reply()
        }
    }

    func setRts(on: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlSetRts(on)
            reply()
        }
    }

    func getModemStatus(reply: @escaping (Int) -> Void) {
        DispatchQueue.main.async {
            // Modem status bits not available on macOS PTY
            reply(0)
        }
    }

    func setSerialDelayChar(ms: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.settings.serialDelayPerChar = ms
            reply()
        }
    }

    func setSerialDelayLine(ms: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.settings.serialDelayPerLine = ms
            reply()
        }
    }

    func openLog(path: String, append: Bool, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlLogOpen(path, append: append)
            reply()
        }
    }

    func closeLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlLogClose()
            reply()
        }
    }

    func pauseLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlLogPause()
            reply()
        }
    }

    func resumeLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlLogStart()
            reply()
        }
    }

    func writeToLog(text: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlLogWrite(text)
            reply()
        }
    }

    func getLogInfo(reply: @escaping (Int, String) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let info = self?.terminalController?.ttlLogInfo() ?? (state: -1, filePath: "")
            reply(info.state, info.filePath)
        }
    }

    func setLogRotation(mode: String, value: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlLogRotateSet(mode: mode, value: value)
            reply()
        }
    }

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

    func getHostname(reply: @escaping (String) -> Void) {
        reply(ProcessInfo.processInfo.hostName)
    }

    func getAppDirectory(reply: @escaping (String) -> Void) {
        let dir = Bundle.main.bundlePath
        reply((dir as NSString).deletingLastPathComponent)
    }

    func showError(message: String, line: Int, lineText: String, fileName: String,
                   reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let ctrl = self?.terminalController else {
                reply(true)
                return
            }
            ctrl.ttlShowError(message, line: line, lineText: lineText, fileName: fileName, completion: reply)
        }
    }

    func showStatusBox(message: String, title: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlShowStatusBox(message, title: title)
            reply()
        }
    }

    func closeStatusBox(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlCloseStatusBox()
            reply()
        }
    }

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
            self.isTransferInProgress = true
            self.currentTransferDirection = .send
            self.currentTransferState = .starting

            guard let ctrl = self.terminalController,
                  let protocolType = TransferProtocolType.from(protocolName) else {
                self.isTransferInProgress = false
                reply(false, "Invalid protocol or no terminal")
                return
            }

            ctrl.ttlStartFileTransfer(
                protocol: protocolType, direction: .send, filePath: localPath
            ) { [weak self] success in
                if !success {
                    self?.isTransferInProgress = false
                    self?.currentTransferState = .idle
                }
            }
            reply(true, "")
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
            self.isTransferInProgress = true
            self.currentTransferDirection = .receive
            self.currentTransferState = .starting

            guard let ctrl = self.terminalController,
                  let protocolType = TransferProtocolType.from(protocolName) else {
                self.isTransferInProgress = false
                reply(false, "Invalid protocol or no terminal", "")
                return
            }

            ctrl.ttlStartFileTransfer(
                protocol: protocolType, direction: .receive, filePath: localDir
            ) { [weak self] success in
                if !success {
                    self?.isTransferInProgress = false
                    self?.currentTransferState = .idle
                }
            }
            reply(true, "", "")
        }
    }

    func getTransferStatus(reply: @escaping (String, Int, Int) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                reply(TransferStatusString.idle.rawValue, 0, 0)
                return
            }

            switch self.currentTransferState {
            case .inProgress(let bytesTransferred, let totalBytes, _):
                let status: TransferStatusString =
                    self.currentTransferDirection == .send ? .sending : .receiving
                reply(status.rawValue, Int(clamping: bytesTransferred),
                      Int(clamping: totalBytes ?? 0))

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
            self?.fileTransferManager?.cancelTransfer()
            self?.isTransferInProgress = false
            self?.currentTransferState = .idle
            reply()
        }
    }

    func scpSend(localPath: String, remotePath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let ctrl = self?.terminalController else {
                reply(false)
                return
            }
            ctrl.ttlScpSend(localPath: localPath, remotePath: remotePath) { success in
                reply(success)
            }
        }
    }

    func scpRecv(remotePath: String, localPath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let ctrl = self?.terminalController else {
                reply(false)
                return
            }
            ctrl.ttlScpRecv(remotePath: remotePath, localPath: localPath) { success in
                reply(success)
            }
        }
    }

    func restoreSetup(path: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlRestoreSetup(from: path)
            reply()
        }
    }

    func callMenu(menuId: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlCallMenu(menuId: menuId)
            reply()
        }
    }

    func loadKeyMap(path: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.ttlLoadKeyMap(from: path)
            reply()
        }
    }

    func enableKeyboard(flag: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.keyboardHandler.isEnabled = (flag != 0)
            reply()
        }
    }

    func setEcho(flag: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.settings.localEcho = (flag != 0)
            reply()
        }
    }

    func displayString(text: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalController?.terminalEmulator.processData(Data(text.utf8))
            reply()
        }
    }

    func sendPasswordData(data: Data, reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            // Send password data directly to terminal without logging
            self?.terminalController?.connectionManager.send(data)
            reply()
        }
    }
}

// MARK: - FileTransferDelegate

extension MacroXPCManager: FileTransferDelegate {

    func transferDidUpdateState(_ state: TransferState) {
        currentTransferState = state
    }

    func transferDidRequestSend(_ data: Data) {
        // Data sending is handled by TerminalWindowController
    }

    func transferDidComplete(fileName: String, bytes: Int64) {
        currentTransferState = .completed(fileName: fileName, bytes: bytes)
        isTransferInProgress = false
    }

    func transferDidFail(error: String) {
        currentTransferState = .failed(error: error)
        isTransferInProgress = false
    }
}

#endif
