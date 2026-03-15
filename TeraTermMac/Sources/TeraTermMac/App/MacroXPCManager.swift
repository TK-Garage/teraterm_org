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

    /// Whether transfer is in progress (exclusion flag)
    private(set) var isTransferInProgress: Bool = false

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
                    os_log("TTLMacro.app launched successfully",
                           log: self?.logger ?? .default, type: .info)
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

            // Try to read endpoint file
            // We check all possible PID-based files
            let fm = FileManager.default
            let tmpDir = NSTemporaryDirectory()
            if let files = try? fm.contentsOfDirectory(atPath: tmpDir) {
                for file in files where file.hasPrefix("ttlmacro_endpoint_") && file.hasSuffix(".dat") {
                    let filePath = (tmpDir as NSString).appendingPathComponent(file)
                    if let data = fm.contents(atPath: filePath) {
                        if let endpoint = try? NSKeyedUnarchiver.unarchivedObject(
                            ofClass: NSXPCListenerEndpoint.self, from: data) {
                            timer.invalidate()
                            self.endpointPollTimer = nil
                            // Remove the endpoint file
                            try? fm.removeItem(atPath: filePath)
                            // Establish connection
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
        DispatchQueue.main.async {
            // Integration point: forward data to active terminal
            reply()
        }
    }

    func recvFromTerminal(timeout: Int, reply: @escaping (Data?) -> Void) {
        DispatchQueue.main.async {
            reply(nil)
        }
    }

    func showDialog(type: String, message: String, defaultValue: String,
                    reply: @escaping (Int, String) -> Void) {
        MacroDialogHelper.showDialog(type: type, message: message,
                                     defaultValue: defaultValue, completion: reply)
    }

    func setWindowTitle(title: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            // Integration point: set window title
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
        DispatchQueue.main.async {
            // Integration point: check terminal connection status
            reply(false)
        }
    }

    func getWindowTitle(reply: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            reply("")
        }
    }

    func showWindow(visible: Bool, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func clearScreen(reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func sendBreak(reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func disconnectFromHost(reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func connectToHost(param: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            // Integration point: establish connection
            reply(false)
        }
    }

    func connectLocalShell(reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            reply(false)
        }
    }

    func flushReceiveBuffer(reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func moveWindow(x: Int, y: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func resizeWindow(width: Int, height: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func bringWindowToFront(reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func getWindowPosition(reply: @escaping (Int, Int) -> Void) {
        DispatchQueue.main.async {
            reply(0, 0)
        }
    }

    func setBaudRate(rate: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func setFlowControl(mode: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func setDtr(on: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func setRts(on: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func getModemStatus(reply: @escaping (Int) -> Void) {
        DispatchQueue.main.async {
            reply(0)
        }
    }

    func setSerialDelayChar(ms: Int, reply: @escaping () -> Void) {
        reply()
    }

    func setSerialDelayLine(ms: Int, reply: @escaping () -> Void) {
        reply()
    }

    func openLog(path: String, append: Bool, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func closeLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func pauseLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func resumeLog(reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func writeToLog(text: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func getLogInfo(reply: @escaping (Int, String) -> Void) {
        DispatchQueue.main.async {
            reply(0, "")
        }
    }

    func setLogRotation(mode: String, value: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
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
        DispatchQueue.main.async {
            // Default: stop on error
            reply(true)
        }
    }

    func showStatusBox(message: String, title: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func closeStatusBox(reply: @escaping () -> Void) {
        DispatchQueue.main.async {
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
            // Integration point: start file transfer
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
            // Integration point: start file receive
            reply(true, "", "")
        }
    }

    func getTransferStatus(reply: @escaping (String, Int, Int) -> Void) {
        DispatchQueue.main.async { [weak self] in
            if self?.isTransferInProgress == true {
                reply(TransferStatusString.idle.rawValue, 0, 0)
            } else {
                reply(TransferStatusString.idle.rawValue, 0, 0)
            }
        }
    }

    func cancelTransfer(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.isTransferInProgress = false
            reply()
        }
    }

    func scpSend(localPath: String, remotePath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            // Integration point: SCP send
            reply(false)
        }
    }

    func scpRecv(remotePath: String, localPath: String, reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            // Integration point: SCP receive
            reply(false)
        }
    }

    func restoreSetup(path: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func callMenu(menuId: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func loadKeyMap(path: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func enableKeyboard(flag: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func setEcho(flag: Int, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func displayString(text: String, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            reply()
        }
    }

    func sendPasswordData(data: Data, reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            // Integration point: send password data to terminal (no logging)
            reply()
        }
    }
}

#endif
