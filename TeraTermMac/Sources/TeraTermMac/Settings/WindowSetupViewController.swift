/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * Window Setup dialog — faithful reproduction of Tera Term 5.6 IDD_WINDLG.
 * Layout uses NSStackView / NSGridView with proper Auto Layout constraints.
 *
 * Original dialog: 240 x 237 DLU
 *
 * Title: [_________________________]
 *
 * ┌─Cursor shape──────┐   ☑ Hide title bar
 * │ ◉ Block           │   ☑ Hide menu bar
 * │ ○ Vertical line   │   ☑ 16 Colors (PC style)
 * │ ○ Horizontal line │
 * └───────────────────┘
 *
 * ┌─Color──────────────────────────────────────────┐
 * │ ◉ Text  ○ Background  [Swap colors]   ┌─────┐ │
 * │ R: [255] ══════════════                │     │ │
 * │ G: [255] ══════════════    (sample)    │     │ │
 * │ B: [255] ══════════════                └─────┘ │
 * └────────────────────────────────────────────────┘
 *
 * ☑ Scroll buffer: [10000] lines
 *
 *                            [Help]  [Cancel]  [OK]
 */

#if canImport(AppKit)
import AppKit

class WindowSetupViewController: BaseSetupDialogController {

    private var settings: TerminalSettings

    // Title
    private var titleField: NSTextField!

    // Cursor
    private var cursorBlockRadio: NSButton!
    private var cursorVertRadio: NSButton!
    private var cursorHorzRadio: NSButton!

    // Checkboxes
    private var hideTitleCheck: NSButton!
    private var hideMenuCheck: NSButton!
    private var pc16ColorCheck: NSButton!

    // Color
    private var colorTextRadio: NSButton!
    private var colorBackRadio: NSButton!
    private var swapColorsButton: NSButton!
    private var redSlider: NSSlider!
    private var greenSlider: NSSlider!
    private var blueSlider: NSSlider!
    private var redValueLabel: NSTextField!
    private var greenValueLabel: NSTextField!
    private var blueValueLabel: NSTextField!
    private var sampleView: NSView!

    // Scroll buffer
    private var scrollCheck: NSButton!
    private var scrollSizeField: NSTextField!

    // Alpha blending
    private var alphaSlider: NSSlider!
    private var alphaValueLabel: NSTextField!

    // Track which color is being edited
    private var isEditingText = true
    private var textColor: TerminalColor
    private var backgroundColor: TerminalColor

    init(settings: TerminalSettings) {
        self.settings = settings
        self.textColor = settings.colorTheme.foreground
        self.backgroundColor = settings.colorTheme.background
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.windowSetup.title")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        let dialogWidth: CGFloat = 460
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        // ── Title row: [Title:] [___________] ──
        let titleLabel = NSView.makeLabel(TTL("dialog.windowSetup.title_label"))
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleField = NSView.makeTextField(value: settings.title)

        let titleRow = NSStackView(views: [titleLabel, titleField])
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.orientation = .horizontal
        titleRow.spacing = DialogLayout.labelTrailing
        titleRow.alignment = .firstBaseline
        contentArea.addSubview(titleRow)

        NSLayoutConstraint.activate([
            titleRow.topAnchor.constraint(equalTo: contentArea.topAnchor),
            titleRow.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            titleRow.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
        ])

        // ── Cursor Shape Group Box ──
        let cursorBox = NSView.makeGroupBox(title: TTL("dialog.winSetup.cursorShape"))
        contentArea.addSubview(cursorBox)

        cursorBlockRadio = NSView.makeRadioButton(TTL("dialog.windowSetup.cursorBlock"), tag: 0)
        cursorVertRadio = NSView.makeRadioButton(TTL("dialog.windowSetup.cursorVertical"), tag: 1)
        cursorHorzRadio = NSView.makeRadioButton(TTL("dialog.windowSetup.cursorHorizontal"), tag: 2)

        switch settings.cursorShape {
        case .block: cursorBlockRadio.state = .on
        case .vertical: cursorVertRadio.state = .on
        case .horizontal: cursorHorzRadio.state = .on
        }

        for radio in [cursorBlockRadio!, cursorVertRadio!, cursorHorzRadio!] {
            radio.target = self
            radio.action = #selector(cursorRadioChanged(_:))
        }

        let cursorStack = NSStackView(views: [cursorBlockRadio, cursorVertRadio, cursorHorzRadio])
        cursorStack.translatesAutoresizingMaskIntoConstraints = false
        cursorStack.orientation = .vertical
        cursorStack.alignment = .leading
        cursorStack.spacing = 4

        let cc = cursorBox.contentView!
        cc.addSubview(cursorStack)
        let boxPad = DialogLayout.groupBoxPadding

        NSLayoutConstraint.activate([
            cursorStack.topAnchor.constraint(equalTo: cc.topAnchor, constant: boxPad),
            cursorStack.leadingAnchor.constraint(equalTo: cc.leadingAnchor, constant: boxPad),
            cursorStack.trailingAnchor.constraint(lessThanOrEqualTo: cc.trailingAnchor, constant: -boxPad),
            cursorStack.bottomAnchor.constraint(equalTo: cc.bottomAnchor, constant: -boxPad),
        ])

        NSLayoutConstraint.activate([
            cursorBox.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: DialogLayout.sectionSpacing),
            cursorBox.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
        ])

        // ── Right-side checkboxes (aligned next to cursor box) ──
        hideTitleCheck = NSView.makeCheckbox(TTL("dialog.winSetup.hideTitleBar"), checked: settings.hideTitleBar)
        hideMenuCheck = NSView.makeCheckbox(TTL("dialog.winSetup.hideMenuBar"), checked: settings.hideMenuBar)
        pc16ColorCheck = NSView.makeCheckbox(TTL("dialog.winSetup.pc16Colors"), checked: settings.pcBoldColor)

        let checkStack = NSStackView(views: [hideTitleCheck, hideMenuCheck, pc16ColorCheck])
        checkStack.translatesAutoresizingMaskIntoConstraints = false
        checkStack.orientation = .vertical
        checkStack.alignment = .leading
        checkStack.spacing = 6
        contentArea.addSubview(checkStack)

        NSLayoutConstraint.activate([
            checkStack.topAnchor.constraint(equalTo: cursorBox.topAnchor, constant: 20),
            checkStack.leadingAnchor.constraint(equalTo: cursorBox.trailingAnchor, constant: DialogLayout.sectionSpacing),
            checkStack.trailingAnchor.constraint(lessThanOrEqualTo: contentArea.trailingAnchor),
        ])

        // ── Color Group Box ──
        let colorBox = NSView.makeGroupBox(title: TTL("dialog.windowSetup.colors"))
        contentArea.addSubview(colorBox)

        colorTextRadio = NSView.makeRadioButton(TTL("dialog.winSetup.text"), tag: 0)
        colorBackRadio = NSView.makeRadioButton(TTL("dialog.winSetup.background"), tag: 1)
        colorTextRadio.state = .on

        for radio in [colorTextRadio!, colorBackRadio!] {
            radio.target = self
            radio.action = #selector(colorTargetChanged(_:))
        }

        swapColorsButton = NSView.makePushButton(TTL("dialog.winSetup.swapColors"))
        swapColorsButton.target = self
        swapColorsButton.action = #selector(swapColors(_:))
        swapColorsButton.keyEquivalent = ""

        // Top row: [Text] [Background] [Swap Colors]
        let colorRadioRow = NSStackView(views: [colorTextRadio, colorBackRadio, swapColorsButton])
        colorRadioRow.translatesAutoresizingMaskIntoConstraints = false
        colorRadioRow.orientation = .horizontal
        colorRadioRow.spacing = 12
        colorRadioRow.alignment = .firstBaseline

        // RGB sliders
        let currentColor = textColor

        let rLabel = NSView.makeLabel("R:", alignment: .right)
        let gLabel = NSView.makeLabel("G:", alignment: .right)
        let bLabel = NSView.makeLabel("B:", alignment: .right)
        rLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        gLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        redSlider = NSView.makeSlider(min: 0, max: 255, value: Double(currentColor.r))
        greenSlider = NSView.makeSlider(min: 0, max: 255, value: Double(currentColor.g))
        blueSlider = NSView.makeSlider(min: 0, max: 255, value: Double(currentColor.b))

        redValueLabel = NSView.makeLabel("\(currentColor.r)", alignment: .right)
        greenValueLabel = NSView.makeLabel("\(currentColor.g)", alignment: .right)
        blueValueLabel = NSView.makeLabel("\(currentColor.b)", alignment: .right)

        // Fixed width for value labels so they don't jump around
        for lbl in [redValueLabel!, greenValueLabel!, blueValueLabel!] {
            lbl.widthAnchor.constraint(equalToConstant: 36).isActive = true
            lbl.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        for slider in [redSlider!, greenSlider!, blueSlider!] {
            slider.target = self
            slider.action = #selector(colorSliderChanged(_:))
            slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        // Sample area
        sampleView = NSView()
        sampleView.translatesAutoresizingMaskIntoConstraints = false
        sampleView.wantsLayer = true
        sampleView.layer?.borderColor = NSColor.separatorColor.cgColor
        sampleView.layer?.borderWidth = 1
        updateSampleView()

        NSLayoutConstraint.activate([
            sampleView.widthAnchor.constraint(equalToConstant: 80),
            sampleView.heightAnchor.constraint(equalToConstant: 60),
        ])

        // Build RGB grid: [label] [value] [slider]
        let rgbGrid = NSGridView(views: [
            [rLabel, redValueLabel,   redSlider],
            [gLabel, greenValueLabel, greenSlider],
            [bLabel, blueValueLabel,  blueSlider],
        ])
        rgbGrid.translatesAutoresizingMaskIntoConstraints = false
        rgbGrid.rowSpacing = 6
        rgbGrid.columnSpacing = 4
        rgbGrid.column(at: 0).xPlacement = .trailing
        rgbGrid.column(at: 1).xPlacement = .trailing
        rgbGrid.column(at: 2).xPlacement = .fill
        for i in 0..<rgbGrid.numberOfRows {
            rgbGrid.row(at: i).rowAlignment = .firstBaseline
        }

        // Slider area: [rgbGrid] [sampleView] side by side
        let sliderRow = NSStackView(views: [rgbGrid, sampleView])
        sliderRow.translatesAutoresizingMaskIntoConstraints = false
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 12
        sliderRow.alignment = .centerY

        // Color box content: vertical [radioRow, sliderRow]
        let colorStack = NSStackView(views: [colorRadioRow, sliderRow])
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        colorStack.orientation = .vertical
        colorStack.alignment = .leading
        colorStack.spacing = DialogLayout.rowSpacing

        let colContent = colorBox.contentView!
        colContent.addSubview(colorStack)

        let colP: CGFloat = 12
        NSLayoutConstraint.activate([
            colorStack.topAnchor.constraint(equalTo: colContent.topAnchor, constant: colP),
            colorStack.leadingAnchor.constraint(equalTo: colContent.leadingAnchor, constant: colP),
            colorStack.trailingAnchor.constraint(equalTo: colContent.trailingAnchor, constant: -colP),
            colorStack.bottomAnchor.constraint(equalTo: colContent.bottomAnchor, constant: -colP),
        ])

        NSLayoutConstraint.activate([
            colorBox.topAnchor.constraint(equalTo: cursorBox.bottomAnchor, constant: DialogLayout.innerMargin),
            colorBox.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            colorBox.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
        ])

        // ── Scroll Buffer row: [☑ Scroll buffer:] [10000] [lines] ──
        scrollCheck = NSView.makeCheckbox(
            TTL("dialog.windowSetup.scrollBuffer"), checked: settings.enableScrollBuffer)
        scrollSizeField = NSView.makeNumberField(
            value: settings.scrollBufferSize, width: 70)
        let linesLabel = NSView.makeLabel(TTL("dialog.windowSetup.lines"), alignment: .left)
        linesLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let scrollRow = NSStackView(views: [scrollCheck, scrollSizeField, linesLabel])
        scrollRow.translatesAutoresizingMaskIntoConstraints = false
        scrollRow.orientation = .horizontal
        scrollRow.spacing = 4
        scrollRow.alignment = .firstBaseline
        contentArea.addSubview(scrollRow)

        NSLayoutConstraint.activate([
            scrollRow.topAnchor.constraint(equalTo: colorBox.bottomAnchor, constant: DialogLayout.innerMargin),
            scrollRow.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
        ])

        // ── Alpha Blending row: [Alpha:] [═══slider═══] [100%] ──
        let alphaLabel = NSView.makeLabel(TTL("dialog.windowSetup.alpha"))
        alphaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        alphaSlider = NSView.makeSlider(min: 20, max: 100, value: settings.windowAlpha * 100)
        alphaSlider.target = self
        alphaSlider.action = #selector(alphaSliderChanged(_:))
        alphaValueLabel = NSView.makeLabel(
            String(format: "%d%%", Int(settings.windowAlpha * 100)), alignment: .left)
        alphaValueLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true
        alphaSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let alphaRow = NSStackView(views: [alphaLabel, alphaSlider, alphaValueLabel])
        alphaRow.translatesAutoresizingMaskIntoConstraints = false
        alphaRow.orientation = .horizontal
        alphaRow.spacing = DialogLayout.rowSpacing
        alphaRow.alignment = .firstBaseline
        contentArea.addSubview(alphaRow)

        NSLayoutConstraint.activate([
            alphaRow.topAnchor.constraint(equalTo: scrollRow.bottomAnchor, constant: DialogLayout.innerMargin),
            alphaRow.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            alphaRow.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func cursorRadioChanged(_ sender: NSButton) {
        for radio in [cursorBlockRadio!, cursorVertRadio!, cursorHorzRadio!] {
            radio.state = (radio === sender) ? .on : .off
        }
    }

    @objc private func colorTargetChanged(_ sender: NSButton) {
        // Save current slider values to the active color
        saveCurrentSliderColor()

        isEditingText = (sender.tag == 0)
        colorTextRadio.state = isEditingText ? .on : .off
        colorBackRadio.state = isEditingText ? .off : .on

        // Load the other color into sliders
        loadColorToSliders()
    }

    @objc private func swapColors(_ sender: Any?) {
        saveCurrentSliderColor()
        let temp = textColor
        textColor = backgroundColor
        backgroundColor = temp
        loadColorToSliders()
        updateSampleView()
    }

    @objc private func colorSliderChanged(_ sender: NSSlider) {
        redValueLabel.stringValue = "\(Int(redSlider.doubleValue))"
        greenValueLabel.stringValue = "\(Int(greenSlider.doubleValue))"
        blueValueLabel.stringValue = "\(Int(blueSlider.doubleValue))"
        saveCurrentSliderColor()
        updateSampleView()
    }

    @objc private func alphaSliderChanged(_ sender: NSSlider) {
        alphaValueLabel.stringValue = String(format: "%d%%", Int(sender.doubleValue))
    }

    private func saveCurrentSliderColor() {
        let color = TerminalColor(
            r: UInt8(clamping: Int(redSlider.doubleValue)),
            g: UInt8(clamping: Int(greenSlider.doubleValue)),
            b: UInt8(clamping: Int(blueSlider.doubleValue)))
        if isEditingText {
            textColor = color
        } else {
            backgroundColor = color
        }
    }

    private func loadColorToSliders() {
        let c = isEditingText ? textColor : backgroundColor
        redSlider.doubleValue = Double(c.r)
        greenSlider.doubleValue = Double(c.g)
        blueSlider.doubleValue = Double(c.b)
        redValueLabel.stringValue = "\(c.r)"
        greenValueLabel.stringValue = "\(c.g)"
        blueValueLabel.stringValue = "\(c.b)"
    }

    private func updateSampleView() {
        let bg = NSColor(
            red: CGFloat(backgroundColor.r) / 255,
            green: CGFloat(backgroundColor.g) / 255,
            blue: CGFloat(backgroundColor.b) / 255,
            alpha: 1)
        sampleView.layer?.backgroundColor = bg.cgColor
    }

    // MARK: - Apply

    override func applySettings() {
        settings.title = titleField.stringValue

        // Cursor shape
        if cursorBlockRadio.state == .on {
            settings.cursorShape = .block
        } else if cursorVertRadio.state == .on {
            settings.cursorShape = .vertical
        } else {
            settings.cursorShape = .horizontal
        }

        // Colors
        saveCurrentSliderColor()
        settings.colorTheme.foreground = textColor
        settings.colorTheme.background = backgroundColor

        // Scroll buffer
        settings.enableScrollBuffer = scrollCheck.state == .on
        settings.scrollBufferSize = scrollSizeField.integerValue

        // Checkboxes
        settings.hideTitleBar = hideTitleCheck.state == .on
        settings.hideMenuBar = hideMenuCheck.state == .on
        settings.pcBoldColor = pc16ColorCheck.state == .on

        // Alpha
        settings.windowAlpha = alphaSlider.doubleValue / 100.0
    }
}
#endif
