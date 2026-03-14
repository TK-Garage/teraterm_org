/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * LocalizedTerminalSetupViewController — NSStackView-based Terminal Setup
 * dialog that dynamically adapts to label length across languages.
 *
 * Unlike the anchor-based TerminalSetupViewController, this implementation
 * uses NSStackView with compression resistance priorities to ensure that
 * longer labels (e.g., English vs Japanese) automatically push input controls
 * rather than truncating text.
 *
 * Layout strategy:
 *   - Each label+control row is an NSStackView (.horizontal)
 *   - Labels have high hugging priority → they shrink-wrap to text
 *   - Controls have low hugging priority → they expand to fill
 *   - The window resizes to fit the widest label in the current language
 *
 * Matches Tera Term 5.6 IDD_TERMDLG functionality with macOS HIG compliance.
 */

#if canImport(AppKit)
import AppKit

final class LocalizedTerminalSetupViewController: BaseSetupDialogController {

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
    private var newlineOptions: [String] {
        [TTL("dialog.termSetup.newlineCR"), TTL("dialog.termSetup.newlineCRLF"),
         TTL("dialog.termSetup.newlineLF"), TTL("dialog.termSetup.newlineAuto")]
    }

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.terminalSetup.title")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupStackBasedLayout()
    }

    // MARK: - NSStackView-Based Layout

    private func setupStackBasedLayout() {
        // ── Terminal Size Group Box ──
        let sizeBox = NSView.makeGroupBox(title: TTL("dialog.termSetup.terminalSize"))
        sizeBox.setAccessibilityIdentifier("localizedTermSetup.sizeBox")

        widthField = NSView.makeNumberField(value: settings.terminalWidth, width: 60)
        widthField.setAccessibilityIdentifier("localizedTermSetup.widthField")
        let xLabel = NSView.makeLabel("X", alignment: .center)
        heightField = NSView.makeNumberField(value: settings.terminalHeight, width: 60)
        heightField.setAccessibilityIdentifier("localizedTermSetup.heightField")

        // Size fields row using NSStackView
        let sizeRow = makeHorizontalStack([widthField, xLabel, heightField])
        sizeRow.alignment = .centerY

        termIsWinCheck = NSView.makeCheckbox(
            TTL("dialog.termSetup.termSizeIsWin"), checked: settings.termIsWin)
        termIsWinCheck.setAccessibilityIdentifier("localizedTermSetup.termIsWinCheck")

        autoResizeCheck = NSView.makeCheckbox(
            TTL("dialog.termSetup.autoResize"), checked: settings.autoWinResize)
        autoResizeCheck.setAccessibilityIdentifier("localizedTermSetup.autoResizeCheck")

        let sizeStack = makeVerticalStack([sizeRow, termIsWinCheck, autoResizeCheck])
        sizeStack.alignment = .leading
        let sizeContent = sizeBox.contentView!
        sizeContent.addSubview(sizeStack)
        sizeStack.translatesAutoresizingMaskIntoConstraints = false
        let gp = DialogLayout.groupBoxPadding
        NSLayoutConstraint.activate([
            sizeStack.topAnchor.constraint(equalTo: sizeContent.topAnchor,
                                           constant: DialogLayout.groupBoxTopPadding - 8),
            sizeStack.leadingAnchor.constraint(equalTo: sizeContent.leadingAnchor, constant: gp),
            sizeStack.trailingAnchor.constraint(lessThanOrEqualTo: sizeContent.trailingAnchor,
                                                constant: -gp),
            sizeStack.bottomAnchor.constraint(equalTo: sizeContent.bottomAnchor,
                                              constant: -gp + 4),
        ])

        // ── New-line Group Box ──
        let newlineBox = NSView.makeGroupBox(title: TTL("dialog.termSetup.newline"))
        newlineBox.setAccessibilityIdentifier("localizedTermSetup.newlineBox")

        let receiveLabel = makeDynamicLabel(TTL("dialog.termSetup.receive"))
        receivePopup = NSView.makePopUpButton(items: newlineOptions, width: 100)
        receivePopup.selectItem(at: min(settings.crReceive.rawValue, newlineOptions.count - 1))
        receivePopup.setAccessibilityIdentifier("localizedTermSetup.receivePopup")
        receivePopup.setAccessibilityLabel(TTL("dialog.termSetup.receive"))

        let transmitLabel = makeDynamicLabel(TTL("dialog.termSetup.transmit"))
        transmitPopup = NSView.makePopUpButton(items: newlineOptions, width: 100)
        transmitPopup.selectItem(at: min(settings.crSend.rawValue, newlineOptions.count - 1))
        transmitPopup.setAccessibilityIdentifier("localizedTermSetup.transmitPopup")
        transmitPopup.setAccessibilityLabel(TTL("dialog.termSetup.transmit"))

        let receiveRow = makeLabeledRow(label: receiveLabel, control: receivePopup)
        let transmitRow = makeLabeledRow(label: transmitLabel, control: transmitPopup)

        let newlineStack = makeVerticalStack([receiveRow, transmitRow])
        newlineStack.alignment = .leading
        let nlContent = newlineBox.contentView!
        nlContent.addSubview(newlineStack)
        newlineStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            newlineStack.topAnchor.constraint(equalTo: nlContent.topAnchor,
                                              constant: DialogLayout.groupBoxTopPadding - 8),
            newlineStack.leadingAnchor.constraint(equalTo: nlContent.leadingAnchor, constant: gp),
            newlineStack.trailingAnchor.constraint(lessThanOrEqualTo: nlContent.trailingAnchor,
                                                   constant: -gp),
            newlineStack.bottomAnchor.constraint(equalTo: nlContent.bottomAnchor,
                                                 constant: -gp + 4),
        ])

        // ── Top row: side-by-side group boxes ──
        let topRow = makeHorizontalStack([sizeBox, newlineBox])
        topRow.distribution = .fill
        topRow.spacing = 12

        // ── Terminal ID row (NSStackView for dynamic label width) ──
        let idLabel = makeDynamicLabel(TTL("dialog.termSetup.terminalId"))
        terminalIDPopup = NSView.makePopUpButton(
            items: TerminalID.allCases.map { $0.displayName },
            selected: settings.terminalID.displayName,
            width: 100)
        terminalIDPopup.setAccessibilityIdentifier("localizedTermSetup.terminalIDPopup")
        terminalIDPopup.setAccessibilityLabel(TTL("dialog.termSetup.terminalId"))

        localEchoCheck = NSView.makeCheckbox(
            TTL("dialog.terminalSetup.localEcho"), checked: settings.localEcho)
        localEchoCheck.setAccessibilityIdentifier("localizedTermSetup.localEchoCheck")

        let spacer1 = NSView()
        spacer1.translatesAutoresizingMaskIntoConstraints = false
        spacer1.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let idRow = makeHorizontalStack([idLabel, terminalIDPopup, spacer1, localEchoCheck])
        idRow.alignment = .firstBaseline

        // ── Answerback row ──
        let ansLabel = makeDynamicLabel(TTL("dialog.termSetup.answerback"))
        answerbackField = NSView.makeTextField(value: settings.answerback)
        answerbackField.setAccessibilityIdentifier("localizedTermSetup.answerbackField")
        answerbackField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        answerbackField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        autoSwitchCheck = NSView.makeCheckbox(
            TTL("dialog.termSetup.autoSwitch"), checked: false)
        autoSwitchCheck.setAccessibilityIdentifier("localizedTermSetup.autoSwitchCheck")

        let spacer2 = NSView()
        spacer2.translatesAutoresizingMaskIntoConstraints = false
        spacer2.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let ansRow = makeHorizontalStack([ansLabel, answerbackField, spacer2, autoSwitchCheck])
        ansRow.alignment = .firstBaseline

        // ── Main vertical stack ──
        let mainStack = makeVerticalStack([topRow, idRow, ansRow])
        mainStack.spacing = 14
        mainStack.alignment = .leading

        contentArea.addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            contentArea.widthAnchor.constraint(greaterThanOrEqualToConstant: 500),
        ])

        // Align label widths between Terminal ID and Answerback rows
        idLabel.widthAnchor.constraint(equalTo: ansLabel.widthAnchor).isActive = true
    }

    // MARK: - Dynamic Layout Helpers

    /// Create a label with high content hugging so it shrink-wraps to text,
    /// and high compression resistance so it never truncates.
    private func makeDynamicLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .right
        // High hugging = label shrinks to fit text
        label.setContentHuggingPriority(.defaultHigh + 1, for: .horizontal)
        // High compression resistance = label never truncates
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.lineBreakMode = .byClipping
        return label
    }

    /// Create a horizontal stack with a label and control, where the label
    /// adapts to its text and the control fills remaining space.
    private func makeLabeledRow(label: NSTextField, control: NSView) -> NSStackView {
        let stack = NSStackView(views: [label, control])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = DialogLayout.labelTrailing
        stack.alignment = .firstBaseline
        stack.distribution = .fill
        return stack
    }

    private func makeHorizontalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = DialogLayout.rowSpacing
        return stack
    }

    private func makeVerticalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = DialogLayout.rowSpacing
        return stack
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

        if let tid = TerminalID.allCases.first(where: {
            $0.displayName == terminalIDPopup.selectedItem?.title
        }) {
            settings.terminalID = tid
        }
        settings.localEcho = localEchoCheck.state == .on
        settings.answerback = answerbackField.stringValue
    }
}
#endif
