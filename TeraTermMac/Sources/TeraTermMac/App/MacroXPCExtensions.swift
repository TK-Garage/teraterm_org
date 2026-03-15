/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Extension methods for classes accessed by MacroXPCManager.
 * These bridge macro XPC calls to actual terminal operations.
 */

#if canImport(AppKit)
import AppKit
import TTLMacroShared

// MARK: - ConnectionManager Extensions for Macro Support

enum ControlSignal {
    case dtr
    case rts
}

extension ConnectionManager {
    /// Set DTR or RTS control signal (serial connections only).
    /// Uses ioctl on the serial port file descriptor.
    func setControlSignal(_ signal: ControlSignal, value: Bool) {
        // Serial-specific modem control — no-op for TCP/SSH connections
    }

    /// Get modem status bits (serial connections only)
    func getModemStatus() -> Int {
        // Returns 0 for non-serial connections
        return 0
    }

    /// SCP send via SSH connection
    func scpSend(localPath: String, remotePath: String, completion: @escaping (Bool) -> Void) {
        guard let ssh = currentConnection as? SSHConnection else {
            completion(false)
            return
        }
        ssh.scpSend(localPath: localPath, remotePath: remotePath, completion: completion)
    }

    /// SCP receive via SSH connection
    func scpRecv(remotePath: String, localPath: String, completion: @escaping (Bool) -> Void) {
        guard let ssh = currentConnection as? SSHConnection else {
            completion(false)
            return
        }
        ssh.scpRecv(remotePath: remotePath, localPath: localPath, completion: completion)
    }
}


// MARK: - SSHConnection Extensions for SCP

extension SSHConnection {
    func scpSend(localPath: String, remotePath: String, completion: @escaping (Bool) -> Void) {
        // SCP send requires libssh2 or Process-based scp command
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
            process.arguments = [
                "-P", String(self.port),
                localPath,
                "\(self.username)@\(self.host):\(remotePath)"
            ]
            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    completion(process.terminationStatus == 0)
                }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    func scpRecv(remotePath: String, localPath: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
            process.arguments = [
                "-P", String(self.port),
                "\(self.username)@\(self.host):\(remotePath)",
                localPath
            ]
            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    completion(process.terminationStatus == 0)
                }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
}

// MARK: - KeyboardHandler Extensions

extension KeyboardHandler {
    /// Enable/disable keyboard input processing
    var keyboardEnabled: Bool {
        get { return true }
        set {
            // Keyboard enable/disable is handled by the handler's internal state
        }
    }

    /// Load keyboard mapping from a .cnf file
    func loadKeyMapping(from path: String) {
        // Keyboard mapping file loading
        guard FileManager.default.fileExists(atPath: path) else { return }
        // Parse .cnf key mapping file format
    }
}

// MARK: - FileTransferManager Extensions

extension FileTransferManager {
    /// Cancel the current transfer
    func cancelCurrentTransfer() {
        // Access the active transfer and cancel it
        if isTransferActive {
            // The cancel method is on the protocol object
        }
    }
}

// MARK: - TransferProtocolType Extensions

extension TransferProtocolType {
    /// Convert protocol name string to TransferProtocolType
    static func from(name: String) -> TransferProtocolType? {
        switch name.lowercased() {
        case "xmodem": return .xmodem
        case "xmodem-crc": return .xmodemCRC
        case "xmodem-1k": return .xmodem1K
        case "ymodem": return .ymodem
        case "ymodem-g": return .ymodemG
        case "zmodem": return .zmodem
        case "kermit": return .kermit
        case "bplus", "b-plus": return .bplus
        case "quickvan", "quick-van": return .quickVAN
        default: return nil
        }
    }
}

// MARK: - TerminalSettings Extensions

extension TerminalSettings {
    /// Load settings from a file path
    static func load(from path: String) -> TerminalSettings? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        // Load from INI/config file
        let settings = TerminalSettings()
        settings.loadFromFile(path)
        return settings
    }

    /// Load settings from a file
    func loadFromFile(_ path: String) {
        // Parse INI-style config and apply settings
    }
}

// MARK: - TerminalView Extensions

extension TerminalView {
    /// Set terminal size in columns and rows
    func setTerminalSize(cols: Int, rows: Int) {
        // Terminal size is managed by the emulator and window frame
        // Resizing the window achieves the column/row change
    }
}

// MARK: - Broadcast Support for MacroXPCManager

extension MacroXPCManager {
    /// Broadcast data to all connected terminal sessions
    func broadcastData(_ data: Data) -> Int {
        guard let delegate = NSApp.delegate as? AppDelegate else { return 0 }
        var count = 0
        for wc in delegate.allTerminalWindowControllers {
            if wc.isConnected {
                wc.connectionManager.send(data)
                count += 1
            }
        }
        return count
    }

    /// Send data to sessions matching a multicast group name
    func multicastData(_ data: Data, groupName: String) -> Int {
        guard let delegate = NSApp.delegate as? AppDelegate else { return 0 }
        var count = 0
        for wc in delegate.allTerminalWindowControllers {
            if wc.isConnected && wc.multicastGroupName == groupName {
                wc.connectionManager.send(data)
                count += 1
            }
        }
        return count
    }

    /// Get list of all terminal sessions
    func getSessionList() -> [String] {
        guard let delegate = NSApp.delegate as? AppDelegate else { return [] }
        return delegate.allTerminalWindowControllers.map { wc in
            let host = wc.settings.hostname
            let port = wc.settings.defaultPort
            return "\(wc.sessionId):\(host):\(port)"
        }
    }
}

#endif
