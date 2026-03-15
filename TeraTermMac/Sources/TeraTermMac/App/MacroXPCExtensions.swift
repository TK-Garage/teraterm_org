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
        guard let serial = currentConnection as? SerialConnection else { return }
        serial.setModemSignal(signal, value: value)
    }

    /// Get modem status bits (serial connections only)
    func getModemStatus() -> Int {
        guard let serial = currentConnection as? SerialConnection else { return 0 }
        return serial.readModemStatus()
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

// MARK: - SerialConnection Extensions for Modem Control

extension SerialConnection {
    /// Set DTR or RTS modem control signal via ioctl.
    /// Port of commlib.c CommSetDTR / CommSetRTS.
    func setModemSignal(_ signal: ControlSignal, value: Bool) {
        let fd = getFileDescriptor()
        guard fd >= 0 else { return }

        let bit: Int32
        switch signal {
        case .dtr: bit = TIOCM_DTR
        case .rts: bit = TIOCM_RTS
        }

        var status: Int32 = 0
        _ = ioctl(fd, UInt(TIOCMGET), &status)
        if value {
            status |= bit
        } else {
            status &= ~bit
        }
        _ = ioctl(fd, UInt(TIOCMSET), &status)
    }

    /// Read modem status bits (CTS, DSR, DCD, RI) via ioctl.
    /// Port of commlib.c CommReadModemStatus.
    func readModemStatus() -> Int {
        let fd = getFileDescriptor()
        guard fd >= 0 else { return 0 }

        var status: Int32 = 0
        _ = ioctl(fd, UInt(TIOCMGET), &status)

        // Map to Windows-compatible modem status bits for TTL compatibility:
        // Bit 4: CTS, Bit 5: DSR, Bit 6: RI, Bit 7: DCD
        var result = 0
        if status & TIOCM_CTS != 0 { result |= 0x10 }
        if status & TIOCM_DSR != 0 { result |= 0x20 }
        if status & TIOCM_RI  != 0 { result |= 0x40 }
        if status & TIOCM_CD  != 0 { result |= 0x80 }
        return result
    }

    /// Access the file descriptor for ioctl operations.
    /// Returns -1 if disconnected.
    func getFileDescriptor() -> Int32 {
        return fileDescriptor
    }
}


// MARK: - SSHConnection Extensions for SCP

extension SSHConnection {
    func scpSend(localPath: String, remotePath: String, completion: @escaping (Bool) -> Void) {
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
    /// Enable/disable keyboard input processing.
    /// When disabled, processKeyEvent returns nil for all input.
    var keyboardEnabled: Bool {
        get { return inputEnabled }
        set { setInputEnabled(newValue) }
    }

    /// Load keyboard mapping from a .cnf key mapping file.
    /// Parses Tera Term keyboard configuration format:
    /// Lines of format: [User keys]\n KeyCode=offset,value
    func loadKeyMapping(from path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
        var inUserSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix(";") { continue }

            if trimmed.hasPrefix("[") {
                inUserSection = trimmed.lowercased().contains("user key")
                continue
            }

            guard inUserSection else { continue }

            // Parse: KeyCode=offset,string
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let keyStr = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let valStr = String(parts[1]).trimmingCharacters(in: .whitespaces)

            guard let keyCode = UInt16(keyStr) else { continue }
            let valueParts = valStr.split(separator: ",", maxSplits: 1)
            guard valueParts.count >= 2 else { continue }
            let value = String(valueParts[1]).trimmingCharacters(in: .whitespaces)

            setUserDefinedKey(keyCode: keyCode, modifiers: .init(rawValue: 0), value: value)
        }
    }
}

// MARK: - FileTransferManager Extensions

extension FileTransferManager {
    /// Cancel the current transfer by delegating to the protocol's cancel method.
    func cancelCurrentTransfer() {
        cancelTransfer()
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
    /// Load settings from a file path (JSON format)
    static func loadFromPath(_ path: String) -> TerminalSettings? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return TerminalSettings.load(from: url)
    }

    /// Apply settings from a JSON configuration file.
    /// Uses the existing Codable infrastructure.
    func applyFromFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return }

        let decoder = JSONDecoder()
        guard let loaded = try? decoder.decode(TerminalSettings.self, from: data) else { return }

        // Copy key properties from loaded settings
        self.hostname = loaded.hostname
        self.defaultPort = loaded.defaultPort
        self.baudRate = loaded.baudRate
        self.dataBits = loaded.dataBits
        self.parity = loaded.parity
        self.stopBits = loaded.stopBits
        self.flowControl = loaded.flowControl
        self.serialPort = loaded.serialPort
        self.bsKey = loaded.bsKey
        self.deleteKey = loaded.deleteKey
        self.metaKey = loaded.metaKey
        self.crSend = loaded.crSend
        self.fontName = loaded.fontName
        self.fontSize = loaded.fontSize
        self.terminalID = loaded.terminalID
    }
}

// MARK: - TerminalView Extensions

extension TerminalView {
    /// Set terminal size in columns and rows by resizing the containing window.
    func setTerminalSize(cols: Int, rows: Int) {
        guard let window = self.window else { return }
        let newContentSize = preferredSize(columns: cols, rows: rows)
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: newContentSize))
        var newFrame = window.frame
        // Keep top-left corner fixed (adjust origin.y for height change)
        let heightDelta = frameSize.height - newFrame.height
        newFrame.size = frameSize.size
        newFrame.origin.y -= heightDelta
        window.setFrame(newFrame, display: true, animate: false)
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
