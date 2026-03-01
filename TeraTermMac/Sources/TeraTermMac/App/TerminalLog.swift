/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of filesys_log.cpp to Swift/macOS
 * Terminal session logging
 */

import Foundation

// MARK: - Log State

enum LogState {
    case inactive
    case active
    case paused
}

// MARK: - Log Options

struct LogOptions {
    var addTimestamp: Bool = false
    var timestampFormat: String = "yyyy-MM-dd HH:mm:ss"
    var plainText: Bool = true          // Strip escape sequences
    var appendMode: Bool = false
    var autoStart: Bool = false
    var includeScreenBuffer: Bool = false
}

// MARK: - Terminal Logger (port of filesys_log.cpp)

class TerminalLogger {
    private(set) var state: LogState = .inactive
    private(set) var logFilePath: String?
    private(set) var bytesLogged: Int64 = 0

    private var fileHandle: FileHandle?
    private var options: LogOptions
    private let dateFormatter = DateFormatter()

    // Strip ESC sequences for plain text logging
    private var escapeState: EscapeStripState = .normal

    enum EscapeStripState {
        case normal
        case escape
        case csi
        case oscString
    }

    var onStateChanged: ((LogState) -> Void)?

    init(options: LogOptions = LogOptions()) {
        self.options = options
        dateFormatter.dateFormat = options.timestampFormat
    }

    // MARK: - Start/Stop Logging

    func startLogging(to path: String, options: LogOptions? = nil) -> Bool {
        if let opts = options {
            self.options = opts
        }

        let fileManager = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if self.options.appendMode && fileManager.fileExists(atPath: path) {
            guard let handle = FileHandle(forWritingAtPath: path) else { return false }
            handle.seekToEndOfFile()
            fileHandle = handle
        } else {
            fileManager.createFile(atPath: path, contents: nil)
            guard let handle = FileHandle(forWritingAtPath: path) else { return false }
            fileHandle = handle
        }

        logFilePath = path
        state = .active
        bytesLogged = 0
        escapeState = .normal

        // Write log header
        let header = "=== Tera Term Mac Log Start: \(dateFormatter.string(from: Date())) ===\n"
        writeToLog(header)

        onStateChanged?(.active)
        return true
    }

    func stopLogging() {
        guard state != .inactive else { return }

        // Write log footer
        let footer = "\n=== Tera Term Mac Log End: \(dateFormatter.string(from: Date())) ===\n"
        writeToLog(footer)

        fileHandle?.closeFile()
        fileHandle = nil
        state = .inactive
        onStateChanged?(.inactive)
    }

    func pauseLogging() {
        guard state == .active else { return }
        state = .paused
        onStateChanged?(.paused)
    }

    func resumeLogging() {
        guard state == .paused else { return }
        state = .active
        onStateChanged?(.active)
    }

    // MARK: - Log Data

    func logData(_ data: Data) {
        guard state == .active else { return }

        if options.plainText {
            let stripped = stripEscapeSequences(data)
            writeToLog(stripped)
        } else {
            writeRawToLog(data)
        }
    }

    func logString(_ string: String) {
        logData(Data(string.utf8))
    }

    func logComment(_ comment: String) {
        guard state == .active else { return }
        var line = ""
        if options.addTimestamp {
            line += "[\(dateFormatter.string(from: Date()))] "
        }
        line += "# \(comment)\n"
        writeToLog(line)
    }

    // MARK: - Private Methods

    private func writeToLog(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        writeRawToLog(data)
    }

    private func writeRawToLog(_ data: Data) {
        fileHandle?.write(data)
        bytesLogged += Int64(data.count)
    }

    private func stripEscapeSequences(_ data: Data) -> String {
        var result = ""

        for byte in data {
            switch escapeState {
            case .normal:
                if byte == 0x1B {
                    escapeState = .escape
                } else if byte >= 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                    if let scalar = UnicodeScalar(byte) {
                        result.append(Character(scalar))
                    }
                }

            case .escape:
                if byte == 0x5B { // [
                    escapeState = .csi
                } else if byte == 0x5D { // ]
                    escapeState = .oscString
                } else if byte >= 0x40 && byte <= 0x7E {
                    escapeState = .normal
                } else if byte >= 0x20 && byte <= 0x2F {
                    // Intermediate bytes, stay in escape
                } else {
                    escapeState = .normal
                }

            case .csi:
                if byte >= 0x40 && byte <= 0x7E {
                    escapeState = .normal
                }
                // Otherwise consume parameter and intermediate bytes

            case .oscString:
                if byte == 0x07 || byte == 0x9C {
                    escapeState = .normal
                }
            }
        }

        return result
    }

    // MARK: - Generate Default Log Path

    static func defaultLogPath(settings: TerminalSettings) -> String {
        let dir = settings.logDefaultDirectory.isEmpty
            ? NSHomeDirectory()
            : settings.logDefaultDirectory

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())

        return "\(dir)/teraterm_\(timestamp).log"
    }
}
