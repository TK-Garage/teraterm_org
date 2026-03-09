/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * Terminal Setup dialog — faithful reproduction of Tera Term 5.6 IDD_TERMDLG.
 * Layout uses Auto Layout anchors to replicate the original control positions.
 *
 * Original dialog: 254 x 152 DLU (≈ 508 x 304 pt at 2× scale)
 *
 * ┌─Terminal size──────────┐  ┌─New-line───────────────┐
 * │ [80] X [24]            │  │ Receive:  [CR   ▾]     │
 * │ ☑ Term size = win size │  │ Transmit: [CR   ▾]     │
 * │ ☑ Auto window resize   │  └────────────────────────┘
 * └────────────────────────┘
 * Terminal ID: [VT100  ▾]       ☑ Local echo
 * Answerback:  [________]       ☑ Auto switch (VT<->TEK)
 *
 *                       [Help]  [Cancel]  [OK]
 */

#if canImport(AppKit)
import AppKit

class TerminalSetupViewController: BaseSetupDialogController {

    private var settings: TerminalSettings

    // Controls — Terminal Size group
    private var widthField: NSTextField!
    private var heightField: NSTextField!
    private var termIsWinCheck: NSButton!
    private var autoResizeCheck: NSButton!

    // Controls — New-line group
    private var receivePopup: NSPopUpButton!
    private var transmitPopup: NSPopUpButton!

    // Controls — Terminal ID
    private var terminalIDPopup: NSPopUpButton!
    private var localEchoCheck: NSButton!

    // Controls — Answerback
    private var answerbackField: NSTextField!
    private var autoSwitchCheck: NSButton!

    // New-line options matching Tera Term
    private let newlineOptions = ["CR", "CR+LF", "LF", "AUTO"]

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = "Tera Term: Terminal setup"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        // ── Terminal Size Group Box ──
        let sizeBox = NSView.makeGroupBox(title: TTL("dialog.termSetup.terminalSize"))
        contentArea.addSubview(sizeBox)

        widthField = NSView.makeNumberField(value: settings.terminalWidth, width: 60)
        let xLabel = NSView.makeLabel("X", alignment: .center)
        heightField = NSView.makeNumberField(value: settings.terminalHeight, width: 60)
        termIsWinCheck = NSView.makeCheckbox(
            TTL("dialog.termSetup.termSizeIsWin"), checked: settings.termIsWin)
        autoResizeCheck = NSView.makeCheckbox(
            TTL("dialog.termSetup.autoResize"), checked: settings.autoWinResize)

        for v: NSView in [widthField, xLabel, heightField, termIsWinCheck, autoResizeCheck] {
            sizeBox.contentView!.addSubview(v)
        }

        // ── New-line Group Box ──
        let newlineBox = NSView.makeGroupBox(title: TTL("dialog.termSetup.newline"))
        contentArea.addSubview(newlineBox)

        let receiveLabel = NSView.makeLabel(TTL("dialog.termSetup.receive"))
        receivePopup = NSView.makePopUpButton(items: newlineOptions, width: 100)
        receivePopup.selectItem(at: min(settings.crReceive.rawValue, newlineOptions.count - 1))

        let transmitLabel = NSView.makeLabel(TTL("dialog.termSetup.transmit"))
        transmitPopup = NSView.makePopUpButton(items: newlineOptions, width: 100)
        transmitPopup.selectItem(at: min(settings.crSend.rawValue, newlineOptions.count - 1))

        for v: NSView in [receiveLabel, receivePopup, transmitLabel, transmitPopup] {
            newlineBox.contentView!.addSubview(v)
        }

        // ── Terminal ID row ──
        let idLabel = NSView.makeLabel(TTL("dialog.termSetup.terminalId"))
        terminalIDPopup = NSView.makePopUpButton(
            items: TerminalID.allCases.map { $0.displayName },
            selected: settings.terminalID.displayName,
            width: 100)
        localEchoCheck = NSView.makeCheckbox(
            TTL("dialog.terminalSetup.localEcho"), checked: settings.localEcho)
        contentArea.addSubview(idLabel)
        contentArea.addSubview(terminalIDPopup)
        contentArea.addSubview(localEchoCheck)

        // ── Answerback row ──
        let ansLabel = NSView.makeLabel(TTL("dialog.termSetup.answerback"))
        answerbackField = NSView.makeTextField(value: settings.answerback)
        autoSwitchCheck = NSView.makeCheckbox(
            TTL("dialog.termSetup.autoSwitch"), checked: false)
        contentArea.addSubview(ansLabel)
        contentArea.addSubview(answerbackField)
        contentArea.addSubview(autoSwitchCheck)

        // ── Accessibility: labelFor relationships ──
        terminalIDPopup.setAccessibilityLabel(TTL("dialog.termSetup.terminalId"))
        receivePopup.setAccessibilityLabel(TTL("dialog.termSetup.receive"))
        transmitPopup.setAccessibilityLabel(TTL("dialog.termSetup.transmit"))

        // ── Layout ──
        layoutControls(
            sizeBox: sizeBox, newlineBox: newlineBox,
            idLabel: idLabel, ansLabel: ansLabel,
            receiveLabel: receiveLabel, transmitLabel: transmitLabel,
            xLabel: xLabel)
    }

    // MARK: - Auto Layout

    private func layoutControls(
        sizeBox: NSBox, newlineBox: NSBox,
        idLabel: NSTextField, ansLabel: NSTextField,
        receiveLabel: NSTextField, transmitLabel: NSTextField,
        xLabel: NSTextField
    ) {
        let p = DialogLayout.groupBoxPadding
        let tp = DialogLayout.groupBoxTopPadding
        let rs = DialogLayout.rowSpacing

        // Dialog content width (expanded for macOS standard control sizes)
        let dialogWidth: CGFloat = 500
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        // ── Size Box: top-left ──
        NSLayoutConstraint.activate([
            sizeBox.topAnchor.constraint(equalTo: contentArea.topAnchor),
            sizeBox.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            sizeBox.widthAnchor.constraint(equalToConstant: 220),
        ])

        // Size box content
        let sizeContent = sizeBox.contentView!
        NSLayoutConstraint.activate([
            widthField.topAnchor.constraint(equalTo: sizeContent.topAnchor, constant: tp - 8),
            widthField.leadingAnchor.constraint(equalTo: sizeContent.leadingAnchor, constant: p),

            xLabel.centerYAnchor.constraint(equalTo: widthField.centerYAnchor),
            xLabel.leadingAnchor.constraint(equalTo: widthField.trailingAnchor, constant: 6),
            xLabel.widthAnchor.constraint(equalToConstant: 14),

            heightField.centerYAnchor.constraint(equalTo: widthField.centerYAnchor),
            heightField.leadingAnchor.constraint(equalTo: xLabel.trailingAnchor, constant: 6),

            termIsWinCheck.topAnchor.constraint(equalTo: widthField.bottomAnchor, constant: rs + 10),
            termIsWinCheck.leadingAnchor.constraint(equalTo: sizeContent.leadingAnchor, constant: p),
            termIsWinCheck.trailingAnchor.constraint(lessThanOrEqualTo: sizeContent.trailingAnchor, constant: -p),

            autoResizeCheck.topAnchor.constraint(equalTo: termIsWinCheck.bottomAnchor, constant: 4),
            autoResizeCheck.leadingAnchor.constraint(equalTo: sizeContent.leadingAnchor, constant: p),
            autoResizeCheck.trailingAnchor.constraint(lessThanOrEqualTo: sizeContent.trailingAnchor, constant: -p),
            autoResizeCheck.bottomAnchor.constraint(equalTo: sizeContent.bottomAnchor, constant: -p + 4),
        ])

        // ── New-line Box: top-right ──
        NSLayoutConstraint.activate([
            newlineBox.topAnchor.constraint(equalTo: contentArea.topAnchor),
            newlineBox.leadingAnchor.constraint(equalTo: sizeBox.trailingAnchor, constant: 12),
            newlineBox.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
        ])

        // New-line box content
        let nlContent = newlineBox.contentView!
        NSLayoutConstraint.activate([
            receiveLabel.topAnchor.constraint(equalTo: nlContent.topAnchor, constant: tp - 8),
            receiveLabel.leadingAnchor.constraint(equalTo: nlContent.leadingAnchor, constant: p),
            receiveLabel.widthAnchor.constraint(equalToConstant: 65),

            receivePopup.centerYAnchor.constraint(equalTo: receiveLabel.centerYAnchor),
            receivePopup.leadingAnchor.constraint(equalTo: receiveLabel.trailingAnchor, constant: 4),

            transmitLabel.topAnchor.constraint(equalTo: receiveLabel.bottomAnchor, constant: rs),
            transmitLabel.leadingAnchor.constraint(equalTo: nlContent.leadingAnchor, constant: p),
            transmitLabel.widthAnchor.constraint(equalTo: receiveLabel.widthAnchor),

            transmitPopup.centerYAnchor.constraint(equalTo: transmitLabel.centerYAnchor),
            transmitPopup.leadingAnchor.constraint(equalTo: transmitLabel.trailingAnchor, constant: 4),
            transmitPopup.bottomAnchor.constraint(equalTo: nlContent.bottomAnchor, constant: -p + 4),
        ])

        // Make boxes the same height
        sizeBox.bottomAnchor.constraint(equalTo: newlineBox.bottomAnchor).isActive = true

        // ── Terminal ID row ──
        NSLayoutConstraint.activate([
            idLabel.topAnchor.constraint(equalTo: sizeBox.bottomAnchor, constant: 14),
            idLabel.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            idLabel.widthAnchor.constraint(equalToConstant: 90),

            terminalIDPopup.centerYAnchor.constraint(equalTo: idLabel.centerYAnchor),
            terminalIDPopup.leadingAnchor.constraint(equalTo: idLabel.trailingAnchor, constant: 4),

            localEchoCheck.centerYAnchor.constraint(equalTo: idLabel.centerYAnchor),
            localEchoCheck.leadingAnchor.constraint(equalTo: sizeBox.trailingAnchor, constant: 24),
        ])

        // ── Answerback row ──
        NSLayoutConstraint.activate([
            ansLabel.topAnchor.constraint(equalTo: idLabel.bottomAnchor, constant: 12),
            ansLabel.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            ansLabel.widthAnchor.constraint(equalToConstant: 90),

            answerbackField.centerYAnchor.constraint(equalTo: ansLabel.centerYAnchor),
            answerbackField.leadingAnchor.constraint(equalTo: ansLabel.trailingAnchor, constant: 4),
            answerbackField.widthAnchor.constraint(equalToConstant: 120),

            autoSwitchCheck.centerYAnchor.constraint(equalTo: ansLabel.centerYAnchor),
            autoSwitchCheck.leadingAnchor.constraint(equalTo: localEchoCheck.leadingAnchor),

            ansLabel.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])
    }

    // MARK: - Apply

    override func applySettings() {
        settings.terminalWidth = max(1, widthField.integerValue)
        settings.terminalHeight = max(1, heightField.integerValue)
        settings.termIsWin = termIsWinCheck.state == .on
        settings.autoWinResize = autoResizeCheck.state == .on

        if let nl = NewLineMode(rawValue: receivePopup.indexOfSelectedItem) {
            settings.crReceive = nl
        }
        if let nl = NewLineMode(rawValue: transmitPopup.indexOfSelectedItem) {
            settings.crSend = nl
        }

        if let tid = TerminalID.allCases.first(where: { $0.displayName == terminalIDPopup.selectedItem?.title }) {
            settings.terminalID = tid
        }
        settings.localEcho = localEchoCheck.state == .on
        settings.answerback = answerbackField.stringValue
    }
}
#endif
