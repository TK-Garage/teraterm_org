/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * XPC connection manager for TeraTermMac.app (client side).
 * Manages the connection to TTLMacro.app for macro execution.
 */

#if canImport(AppKit)
import AppKit
import os
import TTLMacroShared

// MARK: - MacroXPCManager

/// Manages the XPC connection from TeraTermMac.app to TTLMacro.app.
/// Handles launching TTLMacro.app, establishing XPC connection,
/// and forwarding macro service calls.
class MacroXPCManager: NSObject {

    private var connection: NSXPCConnection?
    private var reconnectAttempts: Int = 0
    private let logger = OSLog(subsystem: MacroConstants.teraTermMacBundleId, category: "MacroXPC")

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

    /// Launch TTLMacro.app and establish XPC connection.
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
            self?.establishXPCConnection()
            completion(true)
        }
    }

    /// Disconnect from TTLMacro.app.
    func disconnect() {
        connection?.invalidate()
        connection = nil
        reconnectAttempts = 0
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

    // MARK: - XPC Connection

    private func establishXPCConnection() {
        let conn = NSXPCConnection(serviceName: kTTLMacroXPCServiceName)

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
            self?.establishXPCConnection()
        }
    }
}

// MARK: - MacroClientProtocol Implementation

extension MacroXPCManager: MacroClientProtocol {

    func sendToTerminal(data: Data, reply: @escaping () -> Void) {
        // Forward to terminal window controller
        DispatchQueue.main.async {
            // Integration point: forward data to active terminal
            reply()
        }
    }

    func recvFromTerminal(timeout: Int, reply: @escaping (Data?) -> Void) {
        // Forward to terminal receive buffer
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
        // Status tracking - can be forwarded to UI if needed
        reply()
    }
}

#endif
