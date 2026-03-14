/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * XPC service handler for TTLMacro.app (listener side).
 * Receives commands from TeraTermMac.app and delegates to MacroRunner.
 */

import Foundation
import TTLMacroShared

// MARK: - XPC Service Handler

class XPCServiceHandler: NSObject {

    private var listener: NSXPCListener?
    private weak var macroRunner: MacroRunner?
    private var activeConnection: NSXPCConnection?

    init(macroRunner: MacroRunner) {
        self.macroRunner = macroRunner
        super.init()
    }

    func startListener() {
        // Use an anonymous listener for peer-to-peer XPC
        listener = NSXPCListener.anonymous()
        listener?.delegate = self
        listener?.resume()
    }

    func stopListener() {
        listener?.invalidate()
        listener = nil
        activeConnection?.invalidate()
        activeConnection = nil
    }

    /// The endpoint for the listener, used by TeraTermMac to connect
    var endpoint: NSXPCListenerEndpoint? {
        return listener?.endpoint
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
        // TODO: Pass variable to MacroRunner's parser environment
        reply()
    }
}
