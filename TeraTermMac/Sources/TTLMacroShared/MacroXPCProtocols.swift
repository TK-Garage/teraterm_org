/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * XPC Protocol definitions for TeraTermMac ↔ TTLMacro communication.
 */

import Foundation

// MARK: - XPC Service Identifier

public let kTTLMacroXPCServiceName = "com.yourapp.TeraTermMac.TTLMacro"

// MARK: - Dialog Types

public enum MacroDialogType: String {
    case messagebox = "messagebox"
    case inputbox = "inputbox"
    case yesnobox = "yesnobox"
    case passwordbox = "passwordbox"
    case listbox = "listbox"
    case filenamebox = "filenamebox"
    case dirnamebox = "dirnamebox"
    case statusbox = "statusbox"
}

// MARK: - Macro Status

public enum MacroExecutionStatus: String {
    case idle = "idle"
    case running = "running"
    case paused = "paused"
    case stopped = "stopped"
    case error = "error"
}

// MARK: - MacroServiceProtocol (TeraTermMac → TTLMacro direction)
// Methods that TeraTermMac.app calls on TTLMacro.app

@objc public protocol MacroServiceProtocol {
    /// Execute a macro file at the given path
    func runMacro(scriptPath: String, reply: @escaping (NSError?) -> Void)

    /// Force stop the running macro
    func stopMacro(reply: @escaping () -> Void)

    /// Pause the running macro
    func pauseMacro(reply: @escaping () -> Void)

    /// Resume a paused macro
    func resumeMacro(reply: @escaping () -> Void)

    /// Get current macro execution status
    func macroStatus(reply: @escaping (String) -> Void)

    /// Pass a variable to the macro environment
    func sendVariable(name: String, value: String, reply: @escaping () -> Void)
}

// MARK: - MacroClientProtocol (TTLMacro → TeraTermMac direction)
// Methods that TTLMacro.app calls on TeraTermMac.app

@objc public protocol MacroClientProtocol {
    /// Send data to the terminal
    func sendToTerminal(data: Data, reply: @escaping () -> Void)

    /// Receive data from the terminal with timeout
    func recvFromTerminal(timeout: Int, reply: @escaping (Data?) -> Void)

    /// Show a dialog on the terminal side
    func showDialog(type: String, message: String, defaultValue: String,
                    reply: @escaping (Int, String) -> Void)

    /// Set the terminal window title
    func setWindowTitle(title: String, reply: @escaping () -> Void)

    /// Notify that macro execution completed normally
    func macroDidFinish(exitCode: Int, reply: @escaping () -> Void)

    /// Notify that macro execution failed with an error
    func macroDidFail(error: String, line: Int, reply: @escaping () -> Void)

    /// Send a log message
    func logMessage(level: String, text: String, reply: @escaping () -> Void)

    /// Request the terminal app to terminate
    func terminateApp(reply: @escaping () -> Void)

    /// Get the terminal app version string
    func getAppVersion(reply: @escaping (String) -> Void)

    /// Notify that a line was executed (for status bar updates)
    func didExecuteLine(lineNumber: Int, lineText: String, reply: @escaping () -> Void)
}

// MARK: - XPC Interface Helpers

public enum MacroXPCInterface {
    /// Create the NSXPCInterface for MacroServiceProtocol
    public static func serviceInterface() -> NSXPCInterface {
        return NSXPCInterface(with: MacroServiceProtocol.self)
    }

    /// Create the NSXPCInterface for MacroClientProtocol
    public static func clientInterface() -> NSXPCInterface {
        return NSXPCInterface(with: MacroClientProtocol.self)
    }
}
