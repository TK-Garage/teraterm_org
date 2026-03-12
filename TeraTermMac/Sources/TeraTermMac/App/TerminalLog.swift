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
            line += "[\(formattedTimestamp())] "
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
