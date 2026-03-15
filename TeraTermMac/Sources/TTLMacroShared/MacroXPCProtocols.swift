/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * XPC Protocol definitions for TeraTermMac ↔ TTLMacro communication.
 *
 * MacroClientProtocol: 56 methods (terminal ops, file transfer, broadcast)
 * MacroServiceProtocol: 13 methods (macro control + debugger)
 */

import Foundation

// MARK: - XPC Service Identifier

public let kTTLMacroXPCServiceName = "com.teraterm.mac.TTLMacro"

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

// MARK: - Transfer Status (for XPC)

public enum TransferStatusString: String {
    case idle = "idle"
    case sending = "sending"
    case receiving = "receiving"
    case done = "done"
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

    // --- Debugger methods ---

    /// Execute one line then pause (step into)
    func stepLine(reply: @escaping () -> Void)

    /// Execute until call stack returns to current depth (step over)
    func stepOver(reply: @escaping () -> Void)

    /// Execute until call stack becomes shallower (step out)
    func stepOut(reply: @escaping () -> Void)

    /// Add a breakpoint at the given line number (1-based)
    func addBreakpoint(line: Int, reply: @escaping () -> Void)

    /// Remove a breakpoint at the given line number (1-based)
    func removeBreakpoint(line: Int, reply: @escaping () -> Void)

    /// Remove all breakpoints
    func clearBreakpoints(reply: @escaping () -> Void)

    /// Get current variable values for debugger inspection
    func getVariables(reply: @escaping ([String: String]) -> Void)
}

// MARK: - MacroClientProtocol (TTLMacro → TeraTermMac direction)
// Methods that TTLMacro.app calls on TeraTermMac.app
// Expanded to cover all TTLInterpreterDelegate methods that need terminal-side processing.

@objc public protocol MacroClientProtocol {
    // --- Existing methods ---

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

    // --- Terminal operation methods (new) ---

    /// Check if terminal is connected
    func isConnected(reply: @escaping (Bool) -> Void)

    /// Get terminal window title
    func getWindowTitle(reply: @escaping (String) -> Void)

    /// Show or hide terminal window
    func showWindow(visible: Bool, reply: @escaping () -> Void)

    /// Clear terminal screen
    func clearScreen(reply: @escaping () -> Void)

    /// Send break signal
    func sendBreak(reply: @escaping () -> Void)

    /// Disconnect from terminal
    func disconnectFromHost(reply: @escaping () -> Void)

    /// Connect to host
    func connectToHost(param: String, reply: @escaping (Bool) -> Void)

    /// Connect local shell (macOS PTY)
    func connectLocalShell(reply: @escaping (Bool) -> Void)

    /// Flush receive buffer
    func flushReceiveBuffer(reply: @escaping () -> Void)

    // --- Window operation methods ---

    /// Move terminal window
    func moveWindow(x: Int, y: Int, reply: @escaping () -> Void)

    /// Resize terminal window
    func resizeWindow(width: Int, height: Int, reply: @escaping () -> Void)

    /// Bring terminal window to front
    func bringWindowToFront(reply: @escaping () -> Void)

    /// Get terminal window position
    func getWindowPosition(reply: @escaping (Int, Int) -> Void)

    // --- Serial/connection settings ---

    /// Set baud rate
    func setBaudRate(rate: Int, reply: @escaping () -> Void)

    /// Set flow control mode
    func setFlowControl(mode: Int, reply: @escaping () -> Void)

    /// Set DTR signal
    func setDtr(on: Int, reply: @escaping () -> Void)

    /// Set RTS signal
    func setRts(on: Int, reply: @escaping () -> Void)

    /// Get modem status
    func getModemStatus(reply: @escaping (Int) -> Void)

    /// Set serial transmit delay per character (ms)
    func setSerialDelayChar(ms: Int, reply: @escaping () -> Void)

    /// Set serial transmit delay per line (ms)
    func setSerialDelayLine(ms: Int, reply: @escaping () -> Void)

    // --- Log operation methods ---

    /// Open log file
    func openLog(path: String, append: Bool, reply: @escaping () -> Void)

    /// Close log file
    func closeLog(reply: @escaping () -> Void)

    /// Pause logging
    func pauseLog(reply: @escaping () -> Void)

    /// Resume logging
    func resumeLog(reply: @escaping () -> Void)

    /// Write text to log
    func writeToLog(text: String, reply: @escaping () -> Void)

    /// Get log info (state, filePath)
    func getLogInfo(reply: @escaping (Int, String) -> Void)

    /// Set log rotation
    func setLogRotation(mode: String, value: Int, reply: @escaping () -> Void)

    // --- Clipboard methods ---

    /// Get clipboard text
    func getClipboard(reply: @escaping (String) -> Void)

    /// Set clipboard text
    func setClipboard(text: String, reply: @escaping () -> Void)

    // --- System info methods ---

    /// Get hostname
    func getHostname(reply: @escaping (String) -> Void)

    /// Get app directory
    func getAppDirectory(reply: @escaping (String) -> Void)

    // --- Display methods ---

    /// Show error dialog, returns true to stop
    func showError(message: String, line: Int, lineText: String, fileName: String,
                   reply: @escaping (Bool) -> Void)

    /// Show status box
    func showStatusBox(message: String, title: String, reply: @escaping () -> Void)

    /// Close status box
    func closeStatusBox(reply: @escaping () -> Void)

    // --- File transfer methods ---

    /// Start file send
    func startFileSend(protocolName: String, localPath: String, option: String,
                       reply: @escaping (Bool, String) -> Void)

    /// Start file receive
    func startFileRecv(protocolName: String, localDir: String,
                       reply: @escaping (Bool, String, String) -> Void)

    /// Get transfer status
    func getTransferStatus(reply: @escaping (String, Int, Int) -> Void)

    /// Cancel current transfer
    func cancelTransfer(reply: @escaping () -> Void)

    // --- SCP methods ---

    /// SCP send
    func scpSend(localPath: String, remotePath: String, reply: @escaping (Bool) -> Void)

    /// SCP receive
    func scpRecv(remotePath: String, localPath: String, reply: @escaping (Bool) -> Void)

    // --- Settings methods ---

    /// Restore terminal settings from file
    func restoreSetup(path: String, reply: @escaping () -> Void)

    /// Call menu item by ID
    func callMenu(menuId: Int, reply: @escaping () -> Void)

    /// Load keyboard mapping file
    func loadKeyMap(path: String, reply: @escaping () -> Void)

    /// Enable/disable keyboard input
    func enableKeyboard(flag: Int, reply: @escaping () -> Void)

    /// Set local echo mode
    func setEcho(flag: Int, reply: @escaping () -> Void)

    /// Display string on terminal (without sending to remote)
    func displayString(text: String, reply: @escaping () -> Void)

    // --- Password methods (secure data transfer) ---

    /// Send password data to terminal (secure, no logging)
    func sendPasswordData(data: Data, reply: @escaping () -> Void)

    // --- Broadcast / Multicast methods ---

    /// Send data to all connected terminal sessions
    func broadcastData(data: Data, reply: @escaping (Int) -> Void)

    /// Set multicast group name for the active session
    func setMulticastName(name: String, reply: @escaping () -> Void)

    /// Send data to sessions matching a multicast group name
    func multicastData(groupName: String, data: Data, reply: @escaping (Int) -> Void)

    /// Get list of all terminal sessions ("sessionId:host:port" format)
    func getSessionList(reply: @escaping ([String]) -> Void)

    /// Send data to a specific session by ID
    func sendToSession(sessionId: String, data: Data, reply: @escaping (Bool) -> Void)

    /// Subscribe to terminal data (event-driven receive for wait commands)
    func subscribeToTerminalData(reply: @escaping (Data) -> Void)

    /// Set terminal size (columns x rows)
    func setTerminalSize(cols: Int, rows: Int, reply: @escaping () -> Void)
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

// MARK: - XPC Endpoint File Path

public enum MacroXPCEndpoint {
    /// Temporary file path for endpoint sharing between TeraTermMac and TTLMacro
    public static func endpointFilePath(pid: Int32) -> String {
        return NSTemporaryDirectory() + "ttlmacro_endpoint_\(pid).dat"
    }

    /// Timeout for XPC connection establishment (seconds)
    public static let connectionTimeout: TimeInterval = 10.0

    /// Polling interval for transfer status (seconds)
    public static let transferPollInterval: TimeInterval = 0.5

    /// Default transfer timeout (seconds)
    public static let defaultTransferTimeout: TimeInterval = 600.0
}
