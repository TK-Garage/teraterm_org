/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * XPC service handler for TTLMacro.app (listener side).
 * Uses anonymous listener + endpoint sharing for XPC connection.
 * Receives commands from TeraTermMac.app and delegates to MacroRunner.
 */

import Foundation
import os
import TTLMacroShared

private let logger = Logger(subsystem: "com.teraterm.ttlmacro", category: "XPC")

// MARK: - XPC Service Handler

class XPCServiceHandler: NSObject {

    private var listener: NSXPCListener?
    private weak var macroRunner: MacroRunner?
    private var activeConnection: NSXPCConnection?
    private var endpointFilePath: String?

    init(macroRunner: MacroRunner) {
        self.macroRunner = macroRunner
        super.init()
    }

    func startListener() {
        // Use an anonymous listener for peer-to-peer XPC
        listener = NSXPCListener.anonymous()
        listener?.delegate = self
        listener?.resume()

        // Write endpoint to temporary file for TeraTermMac.app to discover
        writeEndpointToFile()
    }

    func stopListener() {
        listener?.invalidate()
        listener = nil
        activeConnection?.invalidate()
        activeConnection = nil
        cleanupEndpointFile()
    }

    /// The endpoint for the listener, used by TeraTermMac to connect
    var endpoint: NSXPCListenerEndpoint? {
        return listener?.endpoint
    }

    // MARK: - Endpoint File Management

    /// Serialize the endpoint to a temporary file for TeraTermMac.app to read.
    /// Uses NSKeyedArchiver for serialization.
    private func writeEndpointToFile() {
        guard let endpoint = listener?.endpoint else { return }

        let filePath = MacroXPCEndpoint.endpointFilePath(pid: ProcessInfo.processInfo.processIdentifier)
        self.endpointFilePath = filePath

        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: endpoint,
                requiringSecureCoding: true)
            try data.write(to: URL(fileURLWithPath: filePath))
        } catch {
            // Log error but continue - connection may still work via other means
            logger.error("Failed to write XPC endpoint file: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Remove the endpoint file on cleanup
    private func cleanupEndpointFile() {
        if let path = endpointFilePath {
            try? FileManager.default.removeItem(atPath: path)
            endpointFilePath = nil
        }
    }
}

// MARK: - NSXPCListenerDelegate

extension XPCServiceHandler: NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {

        // Set the exported interface (what TTLMacro provides)
        newConnection.exportedInterface = MacroXPCInterface.serviceInterface()
        newConnection.exportedObject = self

        // Set the remote object interface (what TeraTermMac provides)
        newConnection.remoteObjectInterface = MacroXPCInterface.clientInterface()

        newConnection.invalidationHandler = { [weak self] in
            self?.activeConnection = nil
        }

        newConnection.interruptionHandler = { [weak self] in
            self?.activeConnection = nil
        }

        activeConnection = newConnection
        newConnection.resume()

        // Set the client proxy on the macro runner
        if let proxy = newConnection.remoteObjectProxy as? MacroClientProtocol {
            macroRunner?.clientProxy = proxy
        }

        // Clean up endpoint file after connection is established
        cleanupEndpointFile()

        return true
    }
}

// MARK: - MacroServiceProtocol Implementation

extension XPCServiceHandler: MacroServiceProtocol {

    func runMacro(scriptPath: String, reply: @escaping (NSError?) -> Void) {
        guard let runner = macroRunner else {
            reply(NSError(domain: kTTLMacroXPCServiceName, code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "MacroRunner not available"]))
            return
        }

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            reply(NSError(domain: kTTLMacroXPCServiceName, code: -2,
                          userInfo: [NSLocalizedDescriptionKey: L("macro.error.noFile")]))
            return
        }

        runner.run(scriptPath: scriptPath)
        reply(nil)
    }

    func stopMacro(reply: @escaping () -> Void) {
        macroRunner?.stop()
        reply()
    }

    func pauseMacro(reply: @escaping () -> Void) {
        macroRunner?.pause()
        reply()
    }

    func resumeMacro(reply: @escaping () -> Void) {
        macroRunner?.resume()
        reply()
    }

    func macroStatus(reply: @escaping (String) -> Void) {
        let status = macroRunner?.status ?? .idle
        reply(status.rawValue)
    }

    func sendVariable(name: String, value: String, reply: @escaping () -> Void) {
        macroRunner?.setVariable(name: name, value: value)
        reply()
    }

<<<<<<< HEAD
    // MARK: - Debugger

    func stepLine(reply: @escaping () -> Void) {
        macroRunner?.stepLine()
        reply()
    }

    func stepOver(reply: @escaping () -> Void) {
        macroRunner?.stepOver()
        reply()
    }

    func stepOut(reply: @escaping () -> Void) {
        macroRunner?.stepOut()
        reply()
    }

    func addBreakpoint(line: Int, reply: @escaping () -> Void) {
        macroRunner?.addBreakpoint(at: line)
        reply()
    }

    func removeBreakpoint(line: Int, reply: @escaping () -> Void) {
        macroRunner?.removeBreakpoint(at: line)
        reply()
    }

    func clearBreakpoints(reply: @escaping () -> Void) {
        macroRunner?.clearBreakpoints()
        reply()
    }

    func getVariables(reply: @escaping ([String: String]) -> Void) {
        let vars = macroRunner?.getVariables() ?? [:]
        reply(vars)
    }
=======
    func notifyTerminalEvent(eventType: Int, reply: @escaping () -> Void) {
        macroRunner?.enqueueTerminalEvent(eventType)
        reply()
    }
>>>>>>> 35bbf5e9f062c7ea9c28214c385b1235f86b8346
}
