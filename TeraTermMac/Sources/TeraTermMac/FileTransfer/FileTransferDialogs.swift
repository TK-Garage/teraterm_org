/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * File transfer dialogs — faithful reproduction of Tera Term 5.6 file
 * selection and transfer progress dialogs.
 *
 * Original dialogs ported:
 *   - _GetXFname (XMODEM file dialog with IDD_XOPT option panel)
 *   - _GetMultiFname (ZMODEM/Kermit file dialog with IDD_FOPT option panel)
 *   - IDD_PROTDLG (protocol transfer progress)
 *   - IDD_FILETRANSDLG (file send/log transfer progress)
 *   - IDD_GETFNDLG (Kermit GET remote filename input)
 *   - IDD_SENDFILEDLG (send file dialog with delay/read options)
 *   - IDD_RECVFILEDLG (receive file dialog with auto-stop option)
 */

#if canImport(AppKit)
import AppKit

// MARK: - XMODEM Option Panel

/// Accessory view for NSOpenPanel / NSSavePanel when using XMODEM.
///
///  ┌─Option─────────────────────────────────────┐
///  │ ◉ Checksum  ○ CRC   ☑ 1K   ☑ Binary       │
///  └────────────────────────────────────────────┘
///
/// Maps to Tera Term IDD_XOPT.
final class XMODEMOptionAccessory: NSView {
    let checksumRadio: NSButton
    let crcRadio: NSButton
    let oneKCheck: NSButton
    let binaryCheck: NSButton

    /// Current XMODEM mode derived from the radio/checkbox state.
    var selectedProtocol: TransferProtocolType {
        if oneKCheck.state == .on { return .xmodem1K }
        if crcRadio.state == .on { return .xmodemCRC }
        return .xmodem
    }

    var isBinary: Bool { binaryCheck.state == .on }

    /// - Parameters:
    ///   - isSend: true for send dialog, false for receive.
    ///   - defaultCRC: initial radio selection (true = CRC, false = checksum).
    init(isSend: Bool, defaultCRC: Bool = true) {
        checksumRadio = NSView.makeRadioButton(
            NSLocalizedString("dialog.xopt.checksum", value: "Checksum", comment: ""), tag: 0)
        crcRadio = NSView.makeRadioButton(
            NSLocalizedString("dialog.xopt.crc", value: "CRC", comment: ""), tag: 1)
        oneKCheck = NSView.makeCheckbox(
            NSLocalizedString("dialog.xopt.1k", value: "1K", comment: ""))
        binaryCheck = NSView.makeCheckbox(
            NSLocalizedString("dialog.xopt.binary", value: "Binary", comment: ""), checked: true)

        super.init(frame: NSRect(x: 0, y: 0, width: 440, height: 52))

        // GroupBox
        let box = NSView.makeGroupBox(
            title: NSLocalizedString("dialog.xopt.option", value: "Option", comment: ""))
        addSubview(box)
        box.translatesAutoresizingMaskIntoConstraints = false

        // Radio default
        if defaultCRC {
            crcRadio.state = .on
            checksumRadio.state = .off
        } else {
            checksumRadio.state = .on
            crcRadio.state = .off
        }

        // Wire radios
        checksumRadio.target = self
        checksumRadio.action = #selector(radioChanged(_:))
        crcRadio.target = self
        crcRadio.action = #selector(radioChanged(_:))

        let row = NSStackView(views: [checksumRadio, crcRadio, oneKCheck, binaryCheck])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 16
        row.alignment = .firstBaseline

        let content = box.contentView!
        content.addSubview(row)

        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor),
            box.leadingAnchor.constraint(equalTo: leadingAnchor),
            box.trailingAnchor.constraint(equalTo: trailingAnchor),
            box.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -8),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func radioChanged(_ sender: NSButton) {
        checksumRadio.state = (sender === checksumRadio) ? .on : .off
        crcRadio.state = (sender === crcRadio) ? .on : .off
    }
}

// MARK: - General File Option Panel

/// Accessory view for NSOpenPanel / NSSavePanel when using ZMODEM / Kermit.
///
///  ┌─Option──────────────────────┐
///  │ ☑ Binary                    │
///  └─────────────────────────────┘
///
/// Maps to Tera Term IDD_FOPT (simplified for macOS — only Binary is relevant).
final class FileOptionAccessory: NSView {
    let binaryCheck: NSButton

    var isBinary: Bool { binaryCheck.state == .on }

    init() {
        binaryCheck = NSView.makeCheckbox(
            NSLocalizedString("dialog.fopt.binary", value: "Binary", comment: ""), checked: true)

        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 52))

        let box = NSView.makeGroupBox(
            title: NSLocalizedString("dialog.fopt.option", value: "Option", comment: ""))
        addSubview(box)
        box.translatesAutoresizingMaskIntoConstraints = false

        let content = box.contentView!
        content.addSubview(binaryCheck)

        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor),
            box.leadingAnchor.constraint(equalTo: leadingAnchor),
            box.trailingAnchor.constraint(equalTo: trailingAnchor),
            box.bottomAnchor.constraint(equalTo: bottomAnchor),

            binaryCheck.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            binaryCheck.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            binaryCheck.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Protocol Transfer Progress Panel (IDD_PROTDLG)

/// Floating panel that shows protocol (XMODEM/ZMODEM/Kermit) transfer progress.
///
///  Filename:           test.bin
///  Protocol:        XMODEM-CRC
///  Packet#:                  42
///  Bytes transferred:     5376
///  Elapsed time:  0:12 (448.0KB/s)
///  [════════════════════════] 75%
///                    [Cancel]
///
/// Maps to Tera Term IDD_PROTDLG (142×95 DLU).
final class ProtocolTransferPanel {

    private var panel: NSPanel?
    private var filenameField: NSTextField?
    private var protocolLabel: NSTextField?
    private var packetLabel: NSTextField?
    private var bytesLabel: NSTextField?
    private var elapsedLabel: NSTextField?
    private var percentLabel: NSTextField?
    private var progressBar: NSProgressIndicator?

    var onCancel: (() -> Void)?

    private var startTime: Date?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(fileName: String, protocolName: String) {
        if panel == nil { buildPanel() }
        filenameField?.stringValue = fileName
        protocolLabel?.stringValue = protocolName
        packetLabel?.stringValue = "0"
        bytesLabel?.stringValue = "0"
        elapsedLabel?.stringValue = "0:00"
        percentLabel?.stringValue = ""
        progressBar?.doubleValue = 0
        startTime = Date()
        panel?.orderFront(nil)
    }

    func update(packetNum: Int, bytesTransferred: Int64, totalBytes: Int64?) {
        packetLabel?.stringValue = "\(packetNum)"

        if let total = totalBytes, total > 0 {
            let pct = Double(bytesTransferred) / Double(total) * 100
            bytesLabel?.stringValue = "\(bytesTransferred) (\(String(format: "%.1f%%", pct)))"
            progressBar?.isIndeterminate = false
            progressBar?.doubleValue = pct
            percentLabel?.stringValue = String(format: "%d%%", Int(pct))
        } else {
            bytesLabel?.stringValue = "\(bytesTransferred)"
            progressBar?.isIndeterminate = true
            progressBar?.startAnimation(nil)
            percentLabel?.stringValue = ""
        }

        // Elapsed time + rate
        if let start = startTime {
            let elapsed = Int(Date().timeIntervalSince(start))
            let rate = elapsed > 0 ? bytesTransferred / Int64(elapsed) : 0
            let rateStr: String
            if rate < 1200 {
                rateStr = "\(rate)B/s"
            } else if rate < 1_200_000 {
                rateStr = String(format: "%.2fKB/s", Double(rate) / 1000)
            } else {
                rateStr = String(format: "%.2fMB/s", Double(rate) / 1_000_000)
            }
            elapsedLabel?.stringValue = "\(elapsed / 60):\(String(format: "%02d", elapsed % 60)) (\(rateStr))"
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false)
        p.title = "Tera Term: File Transfer"
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false

        let cv = p.contentView!
        let pad: CGFloat = 16

        // Grid: label | value
        let fnTitle = NSView.makeLabel(
            NSLocalizedString("dialog.prot.filename", value: "Filename:", comment: ""))
        let fnField = NSTextField(labelWithString: "")
        fnField.lineBreakMode = .byTruncatingMiddle
        fnField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        filenameField = fnField

        let prTitle = NSView.makeLabel(
            NSLocalizedString("dialog.prot.protocol", value: "Protocol:", comment: ""))
        let prField = NSTextField(labelWithString: "")
        prField.alignment = .right
        protocolLabel = prField

        let pkTitle = NSView.makeLabel(
            NSLocalizedString("dialog.prot.packet", value: "Packet#:", comment: ""))
        let pkField = NSTextField(labelWithString: "0")
        pkField.alignment = .right
        packetLabel = pkField

        let btTitle = NSView.makeLabel(
            NSLocalizedString("dialog.prot.bytesTransferred", value: "Bytes transferred:", comment: ""))
        let btField = NSTextField(labelWithString: "0")
        btField.alignment = .right
        bytesLabel = btField

        let etTitle = NSView.makeLabel(
            NSLocalizedString("dialog.prot.elapsed", value: "Elapsed time:", comment: ""))
        let etField = NSTextField(labelWithString: "0:00")
        etField.alignment = .right
        elapsedLabel = etField

        let grid = NSGridView(views: [
            [fnTitle, fnField],
            [prTitle, prField],
            [pkTitle, pkField],
            [btTitle, btField],
            [etTitle, etField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = 4
        grid.columnSpacing = 8
        cv.addSubview(grid)

        // Progress bar
        let progress = NSProgressIndicator()
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 100
        progress.isIndeterminate = true
        progressBar = progress
        cv.addSubview(progress)

        let pctLabel = NSTextField(labelWithString: "")
        pctLabel.translatesAutoresizingMaskIntoConstraints = false
        pctLabel.alignment = .right
        pctLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percentLabel = pctLabel
        cv.addSubview(pctLabel)

        // Cancel button
        let cancelBtn = NSButton(
            title: NSLocalizedString("dialog.prot.cancel", value: "Cancel", comment: ""),
            target: self, action: #selector(cancelClicked(_:)))
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}" // Esc
        cv.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: cv.topAnchor, constant: pad),
            grid.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            grid.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),

            progress.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12),
            progress.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            progress.trailingAnchor.constraint(equalTo: pctLabel.leadingAnchor, constant: -8),

            pctLabel.centerYAnchor.constraint(equalTo: progress.centerYAnchor),
            pctLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
            pctLabel.widthAnchor.constraint(equalToConstant: 40),

            cancelBtn.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 16),
            cancelBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            cancelBtn.widthAnchor.constraint(equalToConstant: 80),
            cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad),
        ])

        p.center()
        self.panel = p
    }

    @objc private func cancelClicked(_ sender: Any?) {
        onCancel?()
        close()
    }
}

// MARK: - File Transfer Progress Panel (IDD_FILETRANSDLG)

/// Panel for file send / log progress — more detailed than ProtocolTransferPanel.
///
///  Filename:           test.bin
///  Fullpath:      /Users/.../test.bin
///  Bytes transferred:    12345 (50.0%)
///  Elapsed time:   0:05 (2.41KB/s)
///  [══════════════════════════════]
///  [Close]  [Pause]  [Help]
///
/// Maps to Tera Term IDD_FILETRANSDLG (176×96 DLU).
final class FileTransferProgressPanel {

    private var panel: NSPanel?
    private var filenameField: NSTextField?
    private var fullpathField: NSTextField?
    private var bytesLabel: NSTextField?
    private var elapsedLabel: NSTextField?
    private var progressBar: NSProgressIndicator?
    private var pauseButton: NSButton?

    var onClose: (() -> Void)?
    var onPauseResume: ((_ paused: Bool) -> Void)?

    private var startTime: Date?
    private var isPaused = false

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(fileName: String, fullPath: String, forSend: Bool) {
        if panel == nil { buildPanel() }
        filenameField?.stringValue = fileName
        fullpathField?.stringValue = fullPath
        bytesLabel?.stringValue = "0"
        elapsedLabel?.stringValue = "0:00"
        progressBar?.doubleValue = 0
        progressBar?.isHidden = !forSend
        startTime = Date()
        isPaused = false
        updatePauseButton()
        panel?.orderFront(nil)
    }

    func update(fileSize: Int64, byteCount: Int64) {
        if fileSize > 0 {
            let pct = Double(byteCount) / Double(fileSize) * 100
            bytesLabel?.stringValue = "\(byteCount) (\(String(format: "%.1f%%", pct)))"
            progressBar?.isIndeterminate = false
            progressBar?.doubleValue = pct
        } else {
            bytesLabel?.stringValue = "\(byteCount)"
        }

        if let start = startTime {
            let elapsed = Int(Date().timeIntervalSince(start))
            if elapsed > 0 {
                let rate = byteCount / Int64(elapsed)
                let rateStr: String
                if rate < 1200 {
                    rateStr = "\(rate)Bytes/s"
                } else if rate < 1_200_000 {
                    rateStr = String(format: "%d.%02dKB/s", rate / 1000, rate / 10 % 100)
                } else {
                    rateStr = String(format: "%d.%02dMB/s", rate / 1_000_000, rate / 10000 % 100)
                }
                elapsedLabel?.stringValue = "\(elapsed / 60):\(String(format: "%02d", elapsed % 60)) (\(rateStr))"
            }
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.titled, .closable, .miniaturizable, .utilityWindow],
            backing: .buffered, defer: false)
        p.title = "Tera Term: File Transfer"
        p.isFloatingPanel = false
        p.isReleasedWhenClosed = false

        let cv = p.contentView!
        let pad: CGFloat = 16

        let fnTitle = NSView.makeLabel(
            NSLocalizedString("dialog.ftrans.filename", value: "Filename:", comment: ""))
        let fnField = NSTextField(labelWithString: "")
        fnField.lineBreakMode = .byTruncatingMiddle
        fnField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        filenameField = fnField

        let fpTitle = NSView.makeLabel(
            NSLocalizedString("dialog.ftrans.fullpath", value: "Fullpath:", comment: ""))
        let fpField = NSTextField(labelWithString: "")
        fpField.lineBreakMode = .byTruncatingMiddle
        fpField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fullpathField = fpField

        let btTitle = NSView.makeLabel(
            NSLocalizedString("dialog.ftrans.bytesTransferred", value: "Bytes transferred:", comment: ""))
        let btField = NSTextField(labelWithString: "0")
        btField.alignment = .right
        bytesLabel = btField

        let etTitle = NSView.makeLabel(
            NSLocalizedString("dialog.ftrans.elapsed", value: "Elapsed time:", comment: ""))
        let etField = NSTextField(labelWithString: "0:00")
        etField.alignment = .right
        elapsedLabel = etField

        let grid = NSGridView(views: [
            [fnTitle, fnField],
            [fpTitle, fpField],
            [btTitle, btField],
            [etTitle, etField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = 4
        grid.columnSpacing = 8
        cv.addSubview(grid)

        let progress = NSProgressIndicator()
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 100
        progress.isIndeterminate = false
        progressBar = progress
        cv.addSubview(progress)

        // Buttons: [Close] [Pause] [Help]
        let closeBtn = NSButton(
            title: NSLocalizedString("dialog.ftrans.close", value: "Close", comment: ""),
            target: self, action: #selector(closeClicked(_:)))
        closeBtn.bezelStyle = .rounded
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        let pauseBtn = NSButton(
            title: NSLocalizedString("dialog.ftrans.pause", value: "Pause", comment: ""),
            target: self, action: #selector(pauseClicked(_:)))
        pauseBtn.bezelStyle = .rounded
        pauseBtn.translatesAutoresizingMaskIntoConstraints = false
        pauseButton = pauseBtn

        let helpBtn = NSButton(
            title: NSLocalizedString("dialog.ftrans.help", value: "Help", comment: ""),
            target: nil, action: nil)
        helpBtn.bezelStyle = .rounded
        helpBtn.translatesAutoresizingMaskIntoConstraints = false

        let btnStack = NSStackView(views: [closeBtn, pauseBtn, helpBtn])
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        btnStack.orientation = .horizontal
        btnStack.spacing = 12
        btnStack.distribution = .fillEqually
        cv.addSubview(btnStack)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: cv.topAnchor, constant: pad),
            grid.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            grid.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),

            progress.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12),
            progress.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            progress.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),

            btnStack.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 16),
            btnStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            btnStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
            btnStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad),
        ])

        p.center()
        self.panel = p
    }

    @objc private func closeClicked(_ sender: Any?) {
        onClose?()
        close()
    }

    @objc private func pauseClicked(_ sender: Any?) {
        isPaused.toggle()
        updatePauseButton()
        onPauseResume?(isPaused)
    }

    private func updatePauseButton() {
        pauseButton?.title = isPaused
            ? NSLocalizedString("dialog.ftrans.resume", value: "Resume", comment: "")
            : NSLocalizedString("dialog.ftrans.pause", value: "Pause", comment: "")
    }
}

// MARK: - Kermit Get Dialog (IDD_GETFNDLG)

/// Modal dialog for Kermit GET — prompts user for remote filename.
///
///   Filename: [__________________]
///   [OK]  [Cancel]  [Help]
///
/// Maps to Tera Term IDD_GETFNDLG (150×59 DLU).
final class KermitGetDialogController: BaseSetupDialogController {

    private var filenameField: NSTextField!

    /// Result: nil if cancelled, otherwise the entered filename.
    var resultFilename: String?

    init() {
        super.init(nibName: nil, bundle: nil)
        self.title = "Tera Term: Kermit Get"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        contentArea.widthAnchor.constraint(equalToConstant: 340).isActive = true

        let fnLabel = NSView.makeLabel(
            NSLocalizedString("dialog.kermitGet.filename", value: "Filename:", comment: ""),
            alignment: .right)
        fnLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        filenameField = NSView.makeTextField(value: "")
        filenameField.placeholderString = "remote_file.txt"

        let row = NSStackView(views: [fnLabel, filenameField])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline
        contentArea.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentArea.topAnchor),
            row.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])
    }

    override func applySettings() {
        let name = filenameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        resultFilename = name.isEmpty ? nil : name
    }
}

// MARK: - File Transfer Dialog Helper

/// Static helpers to present file selection dialogs for each protocol,
/// matching the original Tera Term behaviour.
enum FileTransferDialogHelper {

    // MARK: - XMODEM Send

    /// Present an XMODEM send file open panel with protocol option accessory.
    /// Calls completion with the chosen URL and protocol type, or nil if cancelled.
    static func presentXMODEMSendPanel(
        on window: NSWindow,
        completion: @escaping (URL, TransferProtocolType) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = NSLocalizedString("dialog.xmodem.sendTitle",
            value: "Tera Term: XMODEM Send", comment: "")

        let accessory = XMODEMOptionAccessory(isSend: true, defaultCRC: true)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url, accessory.selectedProtocol)
        }
    }

    // MARK: - XMODEM Receive

    /// Present an XMODEM receive file save panel with protocol option accessory.
    static func presentXMODEMReceivePanel(
        on window: NSWindow,
        completion: @escaping (URL, TransferProtocolType) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = NSLocalizedString("dialog.xmodem.receiveTitle",
            value: "Tera Term: XMODEM Receive", comment: "")

        let accessory = XMODEMOptionAccessory(isSend: false, defaultCRC: true)
        panel.accessoryView = accessory

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url, accessory.selectedProtocol)
        }
    }

    // MARK: - ZMODEM / Kermit Send

    /// Present a ZMODEM or Kermit send file open panel with binary option.
    static func presentMultiSendPanel(
        on window: NSWindow,
        protocolType: TransferProtocolType,
        completion: @escaping (URL, TransferProtocolType) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let protoName: String
        switch protocolType {
        case .zmodem:   protoName = "ZMODEM"
        case .kermit:   protoName = "Kermit"
        case .bplus:    protoName = "B-Plus"
        case .quickVAN: protoName = "Quick-VAN"
        default:        protoName = "File Transfer"
        }
        panel.title = String(format: NSLocalizedString("dialog.multi.sendTitle",
            value: "Tera Term: %@ Send", comment: ""), protoName)

        let accessory = FileOptionAccessory()
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url, protocolType)
        }
    }

    // MARK: - ZMODEM / Kermit Receive

    /// Present a ZMODEM or Kermit receive file save panel with binary option.
    static func presentMultiReceivePanel(
        on window: NSWindow,
        protocolType: TransferProtocolType,
        completion: @escaping (URL, TransferProtocolType) -> Void
    ) {
        let panel = NSSavePanel()

        let protoName: String
        switch protocolType {
        case .zmodem:   protoName = "ZMODEM"
        case .kermit:   protoName = "Kermit"
        case .bplus:    protoName = "B-Plus"
        case .quickVAN: protoName = "Quick-VAN"
        default:        protoName = "File Transfer"
        }
        panel.title = String(format: NSLocalizedString("dialog.multi.receiveTitle",
            value: "Tera Term: %@ Receive", comment: ""), protoName)

        let accessory = FileOptionAccessory()
        panel.accessoryView = accessory

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url, protocolType)
        }
    }

    // MARK: - Kermit Get

    /// Present the Kermit Get dialog (prompts for remote filename).
    static func presentKermitGetDialog(
        on window: NSWindow,
        completion: @escaping (String?) -> Void
    ) {
        let vc = KermitGetDialogController()
        vc.presentAsSheet(on: window)

        // BaseSetupDialogController dismisses on OK/Cancel, we
        // read the result after dismissal via DispatchQueue.
        DispatchQueue.main.async {
            completion(vc.resultFilename)
        }
    }

    // MARK: - Send File Dialog

    /// Present the Send File dialog (IDD_SENDFILEDLG).
    static func presentSendFileDialog(
        on window: NSWindow,
        completion: @escaping (SendFileDialogController.Result?) -> Void
    ) {
        let vc = SendFileDialogController()
        vc.presentAsSheet(on: window)

        DispatchQueue.main.async {
            completion(vc.result)
        }
    }

    // MARK: - Receive File Dialog

    /// Present the Receive File dialog (IDD_RECVFILEDLG).
    static func presentRecvFileDialog(
        on window: NSWindow,
        completion: @escaping (RecvFileDialogController.Result?) -> Void
    ) {
        let vc = RecvFileDialogController()
        vc.presentAsSheet(on: window)

        DispatchQueue.main.async {
            completion(vc.result)
        }
    }
}

// MARK: - Send File Dialog Controller (IDD_SENDFILEDLG)

/// Modal dialog for sending a file — provides filename selection,
/// reading method, binary mode, delay type/time, and send size options.
///
///  Filename: [______________] [...]
///  File reading method:
///    ◉ Bulk read    ○ Sequential read
///  ☑ Binary
///  Delay type:  [No delay ▾]
///  Send size:   [All ▾]
///  Delay time(ms): [0___]
///  [OK]  [Cancel]  [Help]
///
/// Maps to Tera Term IDD_SENDFILEDLG (271×227 DLU).
final class SendFileDialogController: BaseSetupDialogController {

    /// Delay type options matching original Tera Term.
    enum DelayType: Int, CaseIterable {
        case noDelay = 0
        case perChar
        case perLine

        var localizedTitle: String {
            switch self {
            case .noDelay: return NSLocalizedString("dialog.sendFile.delayNone", value: "No delay", comment: "")
            case .perChar: return NSLocalizedString("dialog.sendFile.delayPerChar", value: "Per character", comment: "")
            case .perLine: return NSLocalizedString("dialog.sendFile.delayPerLine", value: "Per line", comment: "")
            }
        }
    }

    /// Result returned after user clicks OK.
    struct Result {
        let fileURL: URL
        let bulkRead: Bool
        let binary: Bool
        let delayType: DelayType
        let sendSize: Int   // 0 = all
        let delayTimeMs: Int
    }

    private var filenameField: NSTextField!
    private var bulkRadio: NSButton!
    private var sequentialRadio: NSButton!
    private var binaryCheck: NSButton!
    private var delayTypePopup: NSPopUpButton!
    private var sendSizePopup: NSPopUpButton!
    private var delayTimeField: NSTextField!

    private(set) var result: Result?

    init() {
        super.init(nibName: nil, bundle: nil)
        self.title = NSLocalizedString("dialog.sendFile.title",
            value: "Send file", comment: "")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        contentArea.widthAnchor.constraint(equalToConstant: 420).isActive = true

        // --- Filename row ---
        let fnLabel = NSView.makeLabel(
            NSLocalizedString("dialog.sendFile.filename",
                value: "Filename (drop file in this dialog):", comment: ""))
        fnLabel.alignment = .left

        filenameField = NSView.makeTextField(value: "", placeholder: "")
        filenameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let browseBtn = NSButton(
            title: "...", target: self, action: #selector(browseFile(_:)))
        browseBtn.translatesAutoresizingMaskIntoConstraints = false
        browseBtn.bezelStyle = .rounded
        browseBtn.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let fnRow = NSStackView(views: [filenameField, browseBtn])
        fnRow.translatesAutoresizingMaskIntoConstraints = false
        fnRow.orientation = .horizontal
        fnRow.spacing = 4

        // --- Reading method ---
        let readLabel = NSView.makeLabel(
            NSLocalizedString("dialog.sendFile.readingMethod",
                value: "File reading method:", comment: ""))
        readLabel.alignment = .left

        bulkRadio = NSView.makeRadioButton(
            NSLocalizedString("dialog.sendFile.bulkRead",
                value: "Bulk read", comment: ""), tag: 0)
        bulkRadio.state = .on
        bulkRadio.target = self
        bulkRadio.action = #selector(readMethodChanged(_:))

        sequentialRadio = NSView.makeRadioButton(
            NSLocalizedString("dialog.sendFile.sequentialRead",
                value: "Sequential read", comment: ""), tag: 1)
        sequentialRadio.state = .off
        sequentialRadio.target = self
        sequentialRadio.action = #selector(readMethodChanged(_:))

        let radioRow = NSStackView(views: [bulkRadio, sequentialRadio])
        radioRow.translatesAutoresizingMaskIntoConstraints = false
        radioRow.orientation = .horizontal
        radioRow.spacing = 16

        // --- Binary checkbox ---
        binaryCheck = NSView.makeCheckbox(
            NSLocalizedString("dialog.sendFile.binary",
                value: "Binary", comment: ""), checked: false)

        // --- Delay type ---
        let delayLabel = NSView.makeLabel(
            NSLocalizedString("dialog.sendFile.delayType",
                value: "Delay type:", comment: ""))
        delayLabel.alignment = .left

        delayTypePopup = NSView.makePopUpButton(
            items: DelayType.allCases.map { $0.localizedTitle }, width: 140)

        let delayRow = NSStackView(views: [delayLabel, delayTypePopup])
        delayRow.translatesAutoresizingMaskIntoConstraints = false
        delayRow.orientation = .horizontal
        delayRow.spacing = 8

        // --- Send size ---
        let sizeLabel = NSView.makeLabel(
            NSLocalizedString("dialog.sendFile.sendSize",
                value: "Send size(bytes):", comment: ""))
        sizeLabel.alignment = .left

        let sizeItems = ["All", "80", "160", "320", "640", "1280", "2560", "5120", "10240"]
        sendSizePopup = NSView.makePopUpButton(items: sizeItems, width: 140)

        let sizeRow = NSStackView(views: [sizeLabel, sendSizePopup])
        sizeRow.translatesAutoresizingMaskIntoConstraints = false
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 8

        // --- Delay time ---
        let timeLabel = NSView.makeLabel(
            NSLocalizedString("dialog.sendFile.delayTime",
                value: "Delay time(ms):", comment: ""))
        timeLabel.alignment = .left

        delayTimeField = NSView.makeTextField(value: "0", width: 60)

        let timeRow = NSStackView(views: [timeLabel, delayTimeField])
        timeRow.translatesAutoresizingMaskIntoConstraints = false
        timeRow.orientation = .horizontal
        timeRow.spacing = 8

        // --- Assemble ---
        let stack = NSStackView(views: [
            fnLabel, fnRow, readLabel, radioRow,
            binaryCheck, delayRow, sizeRow, timeRow
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentArea.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            fnRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func readMethodChanged(_ sender: NSButton) {
        bulkRadio.state = (sender === bulkRadio) ? .on : .off
        sequentialRadio.state = (sender === sequentialRadio) ? .on : .off
    }

    @objc private func browseFile(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        if openPanel.runModal() == .OK, let url = openPanel.url {
            filenameField.stringValue = url.path
        }
    }

    override func applySettings() {
        let path = filenameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { result = nil; return }
        let url = URL(fileURLWithPath: path)

        let delayType = DelayType(rawValue: delayTypePopup.indexOfSelectedItem) ?? .noDelay

        let sizeStr = sendSizePopup.titleOfSelectedItem ?? "All"
        let sendSize = (sizeStr == "All") ? 0 : (Int(sizeStr) ?? 0)

        let delayMs = Int(delayTimeField.stringValue) ?? 0

        result = Result(
            fileURL: url,
            bulkRead: bulkRadio.state == .on,
            binary: binaryCheck.state == .on,
            delayType: delayType,
            sendSize: sendSize,
            delayTimeMs: delayMs
        )
    }
}

// MARK: - Receive File Dialog Controller (IDD_RECVFILEDLG)

/// Modal dialog for receiving a file — provides filename selection,
/// binary mode, and auto-stop wait time.
///
///  Filename: [______________] [...]
///  ☑ Binary
///  Auto-stop wait time(sec): [0___]
///  [OK]  [Cancel]  [Help]
///
/// Maps to Tera Term IDD_RECVFILEDLG (271×102 DLU).
final class RecvFileDialogController: BaseSetupDialogController {

    struct Result {
        let fileURL: URL
        let binary: Bool
        let autoStopWaitSec: Int
    }

    private var filenameField: NSTextField!
    private var binaryCheck: NSButton!
    private var autoStopField: NSTextField!

    private(set) var result: Result?

    init() {
        super.init(nibName: nil, bundle: nil)
        self.title = NSLocalizedString("dialog.recvFile.title",
            value: "Receive file", comment: "")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        contentArea.widthAnchor.constraint(equalToConstant: 420).isActive = true

        // --- Filename row ---
        let fnLabel = NSView.makeLabel(
            NSLocalizedString("dialog.recvFile.filename",
                value: "Filename (drop file in this dialog):", comment: ""))
        fnLabel.alignment = .left

        filenameField = NSView.makeTextField(value: "", placeholder: "")
        filenameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let browseBtn = NSButton(
            title: "...", target: self, action: #selector(browseFile(_:)))
        browseBtn.translatesAutoresizingMaskIntoConstraints = false
        browseBtn.bezelStyle = .rounded
        browseBtn.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let fnRow = NSStackView(views: [filenameField, browseBtn])
        fnRow.translatesAutoresizingMaskIntoConstraints = false
        fnRow.orientation = .horizontal
        fnRow.spacing = 4

        // --- Binary checkbox ---
        binaryCheck = NSView.makeCheckbox(
            NSLocalizedString("dialog.recvFile.binary",
                value: "Binary", comment: ""), checked: false)

        // --- Auto-stop wait time ---
        let autoLabel = NSView.makeLabel(
            NSLocalizedString("dialog.recvFile.autoStop",
                value: "Auto-stop wait time(sec):", comment: ""))
        autoLabel.alignment = .left

        autoStopField = NSView.makeTextField(value: "0", width: 60)

        let autoRow = NSStackView(views: [autoLabel, autoStopField])
        autoRow.translatesAutoresizingMaskIntoConstraints = false
        autoRow.orientation = .horizontal
        autoRow.spacing = 8

        // --- Assemble ---
        let stack = NSStackView(views: [fnLabel, fnRow, binaryCheck, autoRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentArea.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            fnRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func browseFile(_ sender: Any?) {
        let savePanel = NSSavePanel()
        if savePanel.runModal() == .OK, let url = savePanel.url {
            filenameField.stringValue = url.path
        }
    }

    override func applySettings() {
        let path = filenameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { result = nil; return }
        let url = URL(fileURLWithPath: path)

        result = Result(
            fileURL: url,
            binary: binaryCheck.state == .on,
            autoStopWaitSec: Int(autoStopField.stringValue) ?? 0
        )
    }
}

// MARK: - YMODEM Option Panel

/// Accessory view for NSOpenPanel / NSSavePanel when using YMODEM.
///
///  ┌─Option──────────────────────────────────────┐
///  │ ◉ YMODEM  ○ YMODEM-G   ☑ Binary             │
///  └─────────────────────────────────────────────┘
///
/// Maps to Tera Term YMODEM option (Yopt1K / YoptG / YoptSingle).
final class YMODEMOptionAccessory: NSView {
    let standardRadio: NSButton
    let ymodemGRadio: NSButton
    let binaryCheck: NSButton

    var selectedProtocol: TransferProtocolType {
        if ymodemGRadio.state == .on { return .ymodemG }
        return .ymodem
    }

    var isBinary: Bool { binaryCheck.state == .on }

    init(defaultStandard: Bool = true) {
        standardRadio = NSView.makeRadioButton(
            NSLocalizedString("dialog.yopt.ymodem", value: "YMODEM", comment: ""), tag: 0)
        ymodemGRadio = NSView.makeRadioButton(
            NSLocalizedString("dialog.yopt.ymodemG", value: "YMODEM-G", comment: ""), tag: 1)
        binaryCheck = NSView.makeCheckbox(
            NSLocalizedString("dialog.yopt.binary", value: "Binary", comment: ""), checked: true)

        super.init(frame: NSRect(x: 0, y: 0, width: 440, height: 52))

        let box = NSView.makeGroupBox(
            title: NSLocalizedString("dialog.yopt.option", value: "Option", comment: ""))
        addSubview(box)
        box.translatesAutoresizingMaskIntoConstraints = false

        if defaultStandard {
            standardRadio.state = .on
            ymodemGRadio.state = .off
        } else {
            standardRadio.state = .off
            ymodemGRadio.state = .on
        }

        standardRadio.target = self
        standardRadio.action = #selector(radioChanged(_:))
        ymodemGRadio.target = self
        ymodemGRadio.action = #selector(radioChanged(_:))

        let row = NSStackView(views: [standardRadio, ymodemGRadio, binaryCheck])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 16
        row.alignment = .firstBaseline

        let content = box.contentView!
        content.addSubview(row)

        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor),
            box.leadingAnchor.constraint(equalTo: leadingAnchor),
            box.trailingAnchor.constraint(equalTo: trailingAnchor),
            box.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -8),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func radioChanged(_ sender: NSButton) {
        standardRadio.state = (sender === standardRadio) ? .on : .off
        ymodemGRadio.state = (sender === ymodemGRadio) ? .on : .off
    }
}

// MARK: - YMODEM Dialog Helpers (in FileTransferDialogHelper extension)

extension FileTransferDialogHelper {

    // MARK: - YMODEM Send

    /// Present a YMODEM send file open panel with YMODEM option accessory.
    static func presentYMODEMSendPanel(
        on window: NSWindow,
        completion: @escaping (URL, TransferProtocolType) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = NSLocalizedString("dialog.ymodem.sendTitle",
            value: "Tera Term: YMODEM Send", comment: "")

        let accessory = YMODEMOptionAccessory(defaultStandard: true)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url, accessory.selectedProtocol)
        }
    }

    // MARK: - YMODEM Receive

    /// Present a YMODEM receive directory selection panel.
    /// YMODEM provides filename in block 0, so user picks a directory.
    static func presentYMODEMReceivePanel(
        on window: NSWindow,
        completion: @escaping (URL) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = NSLocalizedString("dialog.ymodem.receiveTitle",
            value: "Tera Term: YMODEM Receive", comment: "")
        panel.nameFieldStringValue = "received_file"

        let accessory = YMODEMOptionAccessory(defaultStandard: true)
        panel.accessoryView = accessory

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }
}

#endif
