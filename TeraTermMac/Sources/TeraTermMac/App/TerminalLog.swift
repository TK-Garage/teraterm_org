/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of filesys_log.cpp to Swift/macOS
 * Terminal session logging
 */

import Foundation
#if canImport(AppKit)
import AppKit
#endif

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
    var writeBOM: Bool = false           // Write UTF-8 BOM at start
    var timestampType: LogTimestampType = .local  // Timestamp type: local/UTC/elapsed
}

// MARK: - Terminal Logger (port of filesys_log.cpp)

/// Log rotation mode (port of rotate_mode enum from filesys_log.cpp)
enum LogRotateMode {
    case none
    case size
}

class TerminalLogger {
    private(set) var state: LogState = .inactive
    private(set) var logFilePath: String?
    private(set) var bytesLogged: Int64 = 0

    private var fileHandle: FileHandle?
    private var options: LogOptions
    private let dateFormatter = DateFormatter()

    // Log rotation state
    private var rotateMode: LogRotateMode = .none
    private var rotateSize: Int = 0
    private var rotateStep: Int = 0

    // Strip ESC sequences for plain text logging
    private var escapeState: EscapeStripState = .normal

    /// Tracks whether we are at the beginning of a new line (for timestamp insertion)
    private var atLineStart: Bool = true

    enum EscapeStripState {
        case normal
        case escape
        case csi
        case oscString
    }

    var onStateChanged: ((LogState) -> Void)?

    private var logStartTime: Date = Date()

    init(options: LogOptions = LogOptions()) {
        self.options = options
        configureDateFormatter()
    }

    private func configureDateFormatter() {
        switch options.timestampType {
        case .local:
            dateFormatter.dateFormat = options.timestampFormat
            dateFormatter.timeZone = .current
        case .utc:
            dateFormatter.dateFormat = options.timestampFormat
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
        case .elapsed:
            dateFormatter.dateFormat = options.timestampFormat
        }
    }

    func formattedTimestamp() -> String {
        switch options.timestampType {
        case .local, .utc:
            return dateFormatter.string(from: Date())
        case .elapsed:
            let elapsed = Date().timeIntervalSince(logStartTime)
            let hours = Int(elapsed) / 3600
            let minutes = (Int(elapsed) % 3600) / 60
            let seconds = Int(elapsed) % 60
            let ms = Int((elapsed.truncatingRemainder(dividingBy: 1)) * 1000)
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, ms)
        }
    }

    // MARK: - Start/Stop Logging

    func startLogging(to path: String, options: LogOptions? = nil) -> Bool {
        if let opts = options {
            self.options = opts
            configureDateFormatter()
        }

        let fileManager = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if self.options.appendMode && fileManager.fileExists(atPath: path) {
            // Convert existing file to UTF-8 (OS standard) with LF line endings
            if let existingData = fileManager.contents(atPath: path), !existingData.isEmpty {
                let converted = TerminalLogger.convertToUTF8WithLF(existingData)
                if converted != existingData {
                    try? converted.write(to: URL(fileURLWithPath: path))
                }
            }
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
        atLineStart = true
        pendingCR = false
        logStartTime = Date()

        // Write UTF-8 BOM if configured
        if self.options.writeBOM && !self.options.appendMode {
            let bom = Data([0xEF, 0xBB, 0xBF])
            writeRawToLog(bom)
        }

        // Write log header
        let header = "=== Tera Term Mac Log Start: \(formattedTimestamp()) ===\n"
        writeToLog(header)

        onStateChanged?(.active)
        return true
    }

    func stopLogging() {
        guard state != .inactive else { return }

        // Write log footer
        let footer = "\n=== Tera Term Mac Log End: \(formattedTimestamp()) ===\n"
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
            if options.addTimestamp {
                writeWithTimestamp(stripped)
            } else {
                // Normalize CR/CRLF → LF even without timestamp
                let normalized = normalizeLineEndings(stripped)
                writeToLog(normalized)
            }
        } else {
            // Binary mode — normalize line endings but write raw otherwise
            let normalized = TerminalLogger.normalizeLineEndingsInData(data)
            writeRawToLog(normalized)
        }
    }

    func logString(_ string: String) {
        guard let data = string.data(using: TerminalLogger.logEncoding) else { return }
        logData(data)
    }

    func logComment(_ comment: String) {
        guard state == .active else { return }
        var line = "\n"
        line += "[\(formattedCommentTimestamp())] "
        line += "# \(comment)\n\n"
        writeToLog(line)
    }

    /// Format a timestamp for comments, always including date (yyyy-MM-dd HH:mm:ss).
    private func formattedCommentTimestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        switch options.timestampType {
        case .local:
            fmt.timeZone = .current
        case .utc:
            fmt.timeZone = TimeZone(identifier: "UTC")
        case .elapsed:
            fmt.timeZone = .current
        }
        return fmt.string(from: Date())
    }

    // MARK: - Log Rotation (port of LogRotate() in filesys_log.cpp)

    /// Configure log rotation mode and size threshold.
    func setRotation(mode: LogRotateMode? = nil, size: Int? = nil, step: Int? = nil) {
        if let mode = mode { rotateMode = mode }
        if let size = size { rotateSize = size }
        if let step = step { rotateStep = step }
    }

    /// Perform log file rotation when size limit exceeded.
    private func performRotation() {
        guard rotateMode == .size, rotateSize > 0, bytesLogged > Int64(rotateSize) else { return }
        guard let currentPath = logFilePath else { return }

        fileHandle?.closeFile()
        fileHandle = nil
        bytesLogged = 0

        let fm = FileManager.default

        // Rotate files: .log.N → .log.(N+1), current → .log.1
        let maxGen = rotateStep > 0 ? rotateStep : 10
        for i in stride(from: maxGen - 1, through: 1, by: -1) {
            let src = "\(currentPath).\(i)"
            let dst = "\(currentPath).\(i + 1)"
            try? fm.removeItem(atPath: dst)
            if fm.fileExists(atPath: src) {
                try? fm.moveItem(atPath: src, toPath: dst)
            }
        }

        // Move current log to .1
        let rotatedPath = "\(currentPath).1"
        try? fm.removeItem(atPath: rotatedPath)
        try? fm.moveItem(atPath: currentPath, toPath: rotatedPath)

        // Create new log file
        fm.createFile(atPath: currentPath, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: currentPath)
    }

    // MARK: - Encoding Detection & Conversion

    /// The OS-standard encoding used for all log output (UTF-8 on macOS).
    static let logEncoding: String.Encoding = .utf8

    /// Detect the encoding of raw file data and convert to UTF-8 with LF line endings.
    /// Tries BOM detection first, then NSString auto-detection, then common encodings.
    static func convertToUTF8WithLF(_ data: Data) -> Data {
        // Already UTF-8? Just normalize line endings.
        if let _ = String(data: data, encoding: .utf8) {
            return normalizeLineEndingsInData(data)
        }

        // Try BOM-based detection
        if let decoded = decodeBOM(data) {
            let utf8 = Data(decoded.utf8)
            return normalizeLineEndingsInData(utf8)
        }

        // Try NSString auto-detection
        var usedEncoding: UInt = 0
        if let nsStr = NSString(data: data, usedEncoding: &usedEncoding) {
            let utf8 = Data((nsStr as String).utf8)
            return normalizeLineEndingsInData(utf8)
        }

        // Fallback: try common encodings in order
        let fallbacks: [String.Encoding] = [
            .shiftJIS, .japaneseEUC, .iso2022JP,     // Japanese
            .windowsCP1252, .isoLatin1,                // Western
            .utf16, .utf16BigEndian, .utf16LittleEndian,
        ]
        for enc in fallbacks {
            if let decoded = String(data: data, encoding: enc) {
                let utf8 = Data(decoded.utf8)
                return normalizeLineEndingsInData(utf8)
            }
        }

        // Could not decode — normalize line endings on raw bytes as last resort
        return normalizeLineEndingsInData(data)
    }

    /// Decode data that starts with a BOM (Byte Order Mark).
    private static func decodeBOM(_ data: Data) -> String? {
        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            // UTF-8 BOM — strip and decode
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.count >= 4 && data[0] == 0x00 && data[1] == 0x00 && data[2] == 0xFE && data[3] == 0xFF {
            return String(data: data, encoding: .utf32BigEndian)
        }
        if data.count >= 4 && data[0] == 0xFF && data[1] == 0xFE && data[2] == 0x00 && data[3] == 0x00 {
            return String(data: data, encoding: .utf32LittleEndian)
        }
        if data.count >= 2 && data[0] == 0xFE && data[1] == 0xFF {
            return String(data: data, encoding: .utf16BigEndian)
        }
        if data.count >= 2 && data[0] == 0xFF && data[1] == 0xFE {
            return String(data: data, encoding: .utf16LittleEndian)
        }
        return nil
    }

    // MARK: - Line Ending Normalization

    /// Normalize CR+LF and standalone CR to LF.
    /// Handles split CR/LF across successive data chunks via `pendingCR`.
    private var pendingCR: Bool = false

    private func normalizeLineEndings(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for ch in text {
            if ch == "\r" {
                // Emit LF; mark pending in case next char is LF (which we skip)
                result.append("\n")
                pendingCR = true
            } else if ch == "\n" && pendingCR {
                // LF that followed a CR — already emitted as LF, skip this one
                pendingCR = false
            } else {
                pendingCR = false
                result.append(ch)
            }
        }
        return result
    }

    /// Normalize line endings in raw Data (used for existing file content on append).
    private static func normalizeLineEndingsInData(_ data: Data) -> Data {
        var result = Data()
        result.reserveCapacity(data.count)
        var i = 0
        while i < data.count {
            let byte = data[i]
            if byte == 0x0D { // CR
                result.append(0x0A) // LF
                // Skip following LF if present (CR+LF → LF)
                if i + 1 < data.count && data[i + 1] == 0x0A {
                    i += 1
                }
            } else {
                result.append(byte)
            }
            i += 1
        }
        return result
    }

    // MARK: - Private Methods

    /// Write text with timestamps prepended at line boundaries.
    private func writeWithTimestamp(_ text: String) {
        let normalized = normalizeLineEndings(text)
        var output = ""
        for ch in normalized {
            if atLineStart {
                output += "[\(formattedTimestamp())] "
                atLineStart = false
            }
            output.append(ch)
            if ch == "\n" {
                atLineStart = true
            }
        }
        writeToLog(output)
    }

    private func writeToLog(_ string: String) {
        guard let data = string.data(using: TerminalLogger.logEncoding) else { return }
        writeRawToLog(data)
    }

    private func writeRawToLog(_ data: Data) {
        fileHandle?.write(data)
        bytesLogged += Int64(data.count)
        // Check rotation after writing
        if rotateMode == .size {
            performRotation()
        }
    }

    private func stripEscapeSequences(_ data: Data) -> String {
        var result = ""

        for byte in data {
            switch escapeState {
            case .normal:
                if byte == 0x1B {
                    escapeState = .escape
                } else if byte >= 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                    let scalar = UnicodeScalar(byte)
                    result.append(Character(scalar))
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
                } else if byte == 0x1B {
                    // ESC inside OSC — likely start of two-byte ST (ESC \)
                    escapeState = .escape
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

// MARK: - Log Progress Panel (port of IDD_FOPT_LOGDLG)

#if canImport(AppKit)

/// Floating panel that shows log recording status, similar to the original
/// Tera Term log dialog (IDD_FOPT_LOGDLG / IDD_LOGDLG).
///
/// Uses Auto Layout throughout — the panel sizes itself to fit its content
/// and expands automatically if localized labels are longer.
final class LogProgressPanel: NSPanel {

    private var filenameField: NSTextField = NSTextField(labelWithString: "")
    private var fullpathField: NSTextField = NSTextField(labelWithString: "")
    private var bytesField: NSTextField = NSTextField(labelWithString: "0")
    private var elapsedField: NSTextField = NSTextField(labelWithString: "0:00")
    private var stateField: NSTextField = NSTextField(labelWithString: "")
    private var pauseButton: NSButton!

    private var startTime: Date = Date()
    private var updateTimer: Timer?

    var onPause: (() -> Void)?
    var onComment: (() -> Void)?
    var onClose: (() -> Void)?

    private weak var observedLogger: TerminalLogger?

    override var isVisible: Bool { isKeyWindow || isMainWindow || super.isVisible }

    convenience init(logger: TerminalLogger) {
        // Build the content view controller so the panel sizes to content
        let vc = NSViewController()
        vc.view = NSView()
        vc.view.translatesAutoresizingMaskIntoConstraints = false

        self.init(contentViewController: vc)
        self.styleMask = [.titled, .closable, .utilityWindow]
        self.title = TTL("dialog.logProgress.title")
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
        self.isReleasedWhenClosed = false

        observedLogger = logger
        buildUI()
        updateState(logger)
        startTimer()
        center()
    }

    deinit {
        updateTimer?.invalidate()
    }

    func updateState(_ logger: TerminalLogger) {
        guard let path = logger.logFilePath else { return }
        let url = URL(fileURLWithPath: path)
        filenameField.stringValue = url.lastPathComponent
        fullpathField.stringValue = path
        fullpathField.toolTip = path
        bytesField.stringValue = formatBytes(logger.bytesLogged)

        switch logger.state {
        case .active:
            stateField.stringValue = TTL("dialog.logProgress.stateActive")
            stateField.textColor = .systemGreen
            pauseButton.title = TTL("dialog.logProgress.pause")
        case .paused:
            stateField.stringValue = TTL("dialog.logProgress.statePaused")
            stateField.textColor = .systemOrange
            pauseButton.title = TTL("dialog.logProgress.resume")
        case .inactive:
            stateField.stringValue = "—"
            stateField.textColor = .secondaryLabelColor
        }
    }

    private func buildUI() {
        let cv = contentView!
        let pad: CGFloat = DialogLayout.margin

        // Grid labels — all use TTL() for localization
        let fnTitle = NSView.makeLabel(TTL("dialog.logProgress.filename"), alignment: .right)
        fnTitle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        fnTitle.setContentCompressionResistancePriority(.required, for: .horizontal)
        let fnField = NSTextField(labelWithString: "")
        fnField.lineBreakMode = .byTruncatingMiddle
        fnField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        filenameField = fnField

        let fpTitle = NSView.makeLabel(TTL("dialog.logProgress.fullpath"), alignment: .right)
        fpTitle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        fpTitle.setContentCompressionResistancePriority(.required, for: .horizontal)
        let fpField = NSTextField(labelWithString: "")
        fpField.lineBreakMode = .byTruncatingMiddle
        fpField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fullpathField = fpField

        let btTitle = NSView.makeLabel(TTL("dialog.logProgress.bytesLogged"), alignment: .right)
        btTitle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        btTitle.setContentCompressionResistancePriority(.required, for: .horizontal)
        let btField = NSTextField(labelWithString: "0")
        btField.alignment = .right
        bytesField = btField

        let etTitle = NSView.makeLabel(TTL("dialog.logProgress.elapsed"), alignment: .right)
        etTitle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        etTitle.setContentCompressionResistancePriority(.required, for: .horizontal)
        let etField = NSTextField(labelWithString: "0:00")
        etField.alignment = .right
        elapsedField = etField

        let stTitle = NSView.makeLabel(TTL("dialog.logProgress.state"), alignment: .right)
        stTitle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        stTitle.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stField = NSTextField(labelWithString: "")
        stField.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        stateField = stField

        let grid = NSGridView(views: [
            [fnTitle, fnField],
            [fpTitle, fpField],
            [btTitle, btField],
            [etTitle, etField],
            [stTitle, stField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowSpacing = 6
        grid.columnSpacing = DialogLayout.labelTrailing
        for i in 0..<grid.numberOfRows {
            grid.row(at: i).rowAlignment = .firstBaseline
        }
        cv.addSubview(grid)

        // Buttons: [Pause] [Comment] [Close]
        let pBtn = NSView.makePushButton(TTL("dialog.logProgress.pause"))
        pBtn.target = self
        pBtn.action = #selector(pauseAction)
        pauseButton = pBtn

        let cBtn = NSView.makePushButton(TTL("dialog.logProgress.comment"))
        cBtn.target = self
        cBtn.action = #selector(commentAction)

        let clBtn = NSView.makePushButton(TTL("dialog.logProgress.close"))
        clBtn.target = self
        clBtn.action = #selector(closeAction)

        let buttonRow = NSStackView(views: [pBtn, cBtn, clBtn])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = DialogLayout.buttonSpacing
        cv.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: cv.topAnchor, constant: pad),
            grid.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            grid.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),

            // Ensure minimum width for the value column
            grid.widthAnchor.constraint(greaterThanOrEqualToConstant: 340),

            buttonRow.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: pad),
            buttonRow.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad),
        ])
    }

    @objc private func pauseAction() { onPause?() }
    @objc private func commentAction() { onComment?() }
    @objc private func closeAction() { onClose?() }

    private func startTimer() {
        startTime = Date()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.timerTick()
        }
    }

    private func timerTick() {
        guard let logger = observedLogger else { return }
        let elapsed = Int(Date().timeIntervalSince(startTime))
        elapsedField.stringValue = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        bytesField.stringValue = formatBytes(logger.bytesLogged)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1_048_576 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.2f MB", Double(bytes) / 1_048_576)
        }
    }
}
#endif
