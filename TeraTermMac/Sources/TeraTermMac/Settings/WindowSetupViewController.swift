/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * Window Setup dialog — faithful reproduction of Tera Term 5.6 IDD_WINDLG.
 * Layout uses Auto Layout anchors to replicate the original control positions.
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
        self.title = "Tera Term: Window setup"
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

        // ── Title row ──
        let titleLabel = NSView.makeLabel(TTL("dialog.windowSetup.title_label"))
        titleField = NSView.makeTextField(value: settings.title)
        contentArea.addSubview(titleLabel)
        contentArea.addSubview(titleField)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentArea.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 45),

            titleField.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleField.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
        ])

        // ── Cursor Shape Group Box ──
        let cursorBox = NSView.makeGroupBox(title: TTL("dialog.winSetup.cursorShape"))
        contentArea.addSubview(cursorBox)

        cursorBlockRadio = NSView.makeRadioButton(TTL("dialog.windowSetup.cursorBlock"), tag: 0)
        cursorVertRadio = NSView.makeRadioButton(TTL("dialog.windowSetup.cursorVertical"), tag: 1)
        cursorHorzRadio = NSView.makeRadioButton(TTL("dialog.windowSetup.cursorHorizontal"), tag: 2)

        // Set current selection
        switch settings.cursorShape {
        case .block: cursorBlockRadio.state = .on
        case .vertical: cursorVertRadio.state = .on
        case .horizontal: cursorHorzRadio.state = .on
        }

        for radio in [cursorBlockRadio!, cursorVertRadio!, cursorHorzRadio!] {
            radio.target = self
            radio.action = #selector(cursorRadioChanged(_:))
            cursorBox.contentView!.addSubview(radio)
        }

        let cc = cursorBox.contentView!
        let tp = DialogLayout.groupBoxTopPadding
        let p = DialogLayout.groupBoxPadding

        NSLayoutConstraint.activate([
            cursorBox.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            cursorBox.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            cursorBox.widthAnchor.constraint(equalToConstant: 170),

            cursorBlockRadio.topAnchor.constraint(equalTo: cc.topAnchor, constant: tp - 6),
            cursorBlockRadio.leadingAnchor.constraint(equalTo: cc.leadingAnchor, constant: p),

            cursorVertRadio.topAnchor.constraint(equalTo: cursorBlockRadio.bottomAnchor, constant: 4),
            cursorVertRadio.leadingAnchor.constraint(equalTo: cc.leadingAnchor, constant: p),

            cursorHorzRadio.topAnchor.constraint(equalTo: cursorVertRadio.bottomAnchor, constant: 4),
            cursorHorzRadio.leadingAnchor.constraint(equalTo: cc.leadingAnchor, constant: p),
            cursorHorzRadio.bottomAnchor.constraint(equalTo: cc.bottomAnchor, constant: -p + 4),
        ])

        // ── Right-side checkboxes (aligned next to cursor box) ──
        hideTitleCheck = NSView.makeCheckbox(TTL("dialog.winSetup.hideTitleBar"))
        hideMenuCheck = NSView.makeCheckbox(TTL("dialog.winSetup.hideMenuBar"))
        pc16ColorCheck = NSView.makeCheckbox(TTL("dialog.winSetup.pc16Colors"))

        contentArea.addSubview(hideTitleCheck)
        contentArea.addSubview(hideMenuCheck)
        contentArea.addSubview(pc16ColorCheck)

        NSLayoutConstraint.activate([
            hideTitleCheck.topAnchor.constraint(equalTo: cursorBox.topAnchor, constant: 20),
            hideTitleCheck.leadingAnchor.constraint(equalTo: cursorBox.trailingAnchor, constant: 16),

            hideMenuCheck.topAnchor.constraint(equalTo: hideTitleCheck.bottomAnchor, constant: 6),
            hideMenuCheck.leadingAnchor.constraint(equalTo: hideTitleCheck.leadingAnchor),

            pc16ColorCheck.topAnchor.constraint(equalTo: hideMenuCheck.bottomAnchor, constant: 6),
            pc16ColorCheck.leadingAnchor.constraint(equalTo: hideTitleCheck.leadingAnchor),
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
            colorBox.contentView!.addSubview(radio)
        }

        swapColorsButton = NSView.makePushButton(TTL("dialog.winSetup.swapColors"))
        swapColorsButton.target = self
        swapColorsButton.action = #selector(swapColors(_:))
        swapColorsButton.keyEquivalent = ""
        colorBox.contentView!.addSubview(swapColorsButton)

        // RGB sliders
        let currentColor = textColor
        let rLabel = NSView.makeLabel("R:", alignment: .left)
        let gLabel = NSView.makeLabel("G:", alignment: .left)
        let bLabel = NSView.makeLabel("B:", alignment: .left)

        redSlider = NSView.makeSlider(min: 0, max: 255, value: Double(currentColor.r))
        greenSlider = NSView.makeSlider(min: 0, max: 255, value: Double(currentColor.g))
        blueSlider = NSView.makeSlider(min: 0, max: 255, value: Double(currentColor.b))

        redValueLabel = NSView.makeLabel("\(currentColor.r)", alignment: .left)
        greenValueLabel = NSView.makeLabel("\(currentColor.g)", alignment: .left)
        blueValueLabel = NSView.makeLabel("\(currentColor.b)", alignment: .left)

        for slider in [redSlider!, greenSlider!, blueSlider!] {
            slider.target = self
            slider.action = #selector(colorSliderChanged(_:))
        }

        // Sample area
        sampleView = NSView()
        sampleView.translatesAutoresizingMaskIntoConstraints = false
        sampleView.wantsLayer = true
        sampleView.layer?.borderColor = NSColor.separatorColor.cgColor
        sampleView.layer?.borderWidth = 1
        updateSampleView()

        let colContent = colorBox.contentView!
        for v: NSView in [rLabel, gLabel, bLabel,
                          redSlider, greenSlider, blueSlider,
                          redValueLabel, greenValueLabel, blueValueLabel,
                          sampleView] {
            colContent.addSubview(v)
        }

        // Color box layout
        let colP: CGFloat = 12
        let colTP: CGFloat = 18

        NSLayoutConstraint.activate([
            colorBox.topAnchor.constraint(equalTo: cursorBox.bottomAnchor, constant: 12),
            colorBox.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            colorBox.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),

            // Text / Background radios
            colorTextRadio.topAnchor.constraint(equalTo: colContent.topAnchor, constant: colTP - 4),
            colorTextRadio.leadingAnchor.constraint(equalTo: colContent.leadingAnchor, constant: colP),

            colorBackRadio.centerYAnchor.constraint(equalTo: colorTextRadio.centerYAnchor),
            colorBackRadio.leadingAnchor.constraint(equalTo: colorTextRadio.trailingAnchor, constant: 12),

            swapColorsButton.centerYAnchor.constraint(equalTo: colorTextRadio.centerYAnchor),
            swapColorsButton.leadingAnchor.constraint(equalTo: colorBackRadio.trailingAnchor, constant: 12),

            // Sample view
            sampleView.topAnchor.constraint(equalTo: colorTextRadio.bottomAnchor, constant: 8),
            sampleView.trailingAnchor.constraint(equalTo: colContent.trailingAnchor, constant: -colP),
            sampleView.widthAnchor.constraint(equalToConstant: 80),
            sampleView.heightAnchor.constraint(equalToConstant: 60),

            // R row
            rLabel.topAnchor.constraint(equalTo: colorTextRadio.bottomAnchor, constant: 10),
            rLabel.leadingAnchor.constraint(equalTo: colContent.leadingAnchor, constant: colP),
            rLabel.widthAnchor.constraint(equalToConstant: 20),

            redValueLabel.centerYAnchor.constraint(equalTo: rLabel.centerYAnchor),
            redValueLabel.leadingAnchor.constraint(equalTo: rLabel.trailingAnchor),
            redValueLabel.widthAnchor.constraint(equalToConstant: 30),

            redSlider.centerYAnchor.constraint(equalTo: rLabel.centerYAnchor),
            redSlider.leadingAnchor.constraint(equalTo: redValueLabel.trailingAnchor, constant: 4),
            redSlider.trailingAnchor.constraint(equalTo: sampleView.leadingAnchor, constant: -12),

            // G row
            gLabel.topAnchor.constraint(equalTo: rLabel.bottomAnchor, constant: 6),
            gLabel.leadingAnchor.constraint(equalTo: colContent.leadingAnchor, constant: colP),
            gLabel.widthAnchor.constraint(equalToConstant: 20),

            greenValueLabel.centerYAnchor.constraint(equalTo: gLabel.centerYAnchor),
            greenValueLabel.leadingAnchor.constraint(equalTo: gLabel.trailingAnchor),
            greenValueLabel.widthAnchor.constraint(equalToConstant: 30),

            greenSlider.centerYAnchor.constraint(equalTo: gLabel.centerYAnchor),
            greenSlider.leadingAnchor.constraint(equalTo: greenValueLabel.trailingAnchor, constant: 4),
            greenSlider.trailingAnchor.constraint(equalTo: sampleView.leadingAnchor, constant: -12),

            // B row
            bLabel.topAnchor.constraint(equalTo: gLabel.bottomAnchor, constant: 6),
            bLabel.leadingAnchor.constraint(equalTo: colContent.leadingAnchor, constant: colP),
            bLabel.widthAnchor.constraint(equalToConstant: 20),

            blueValueLabel.centerYAnchor.constraint(equalTo: bLabel.centerYAnchor),
            blueValueLabel.leadingAnchor.constraint(equalTo: bLabel.trailingAnchor),
            blueValueLabel.widthAnchor.constraint(equalToConstant: 30),

            blueSlider.centerYAnchor.constraint(equalTo: bLabel.centerYAnchor),
            blueSlider.leadingAnchor.constraint(equalTo: blueValueLabel.trailingAnchor, constant: 4),
            blueSlider.trailingAnchor.constraint(equalTo: sampleView.leadingAnchor, constant: -12),

            bLabel.bottomAnchor.constraint(equalTo: colContent.bottomAnchor, constant: -colP),
        ])

        // ── Scroll Buffer row ──
        scrollCheck = NSView.makeCheckbox(
            TTL("dialog.windowSetup.scrollBuffer"), checked: settings.enableScrollBuffer)
        scrollSizeField = NSView.makeNumberField(
            value: settings.scrollBufferSize, width: 70)
        let linesLabel = NSView.makeLabel(TTL("dialog.windowSetup.lines"), alignment: .left)

        contentArea.addSubview(scrollCheck)
        contentArea.addSubview(scrollSizeField)
        contentArea.addSubview(linesLabel)

        NSLayoutConstraint.activate([
            scrollCheck.topAnchor.constraint(equalTo: colorBox.bottomAnchor, constant: 12),
            scrollCheck.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),

            scrollSizeField.centerYAnchor.constraint(equalTo: scrollCheck.centerYAnchor),
            scrollSizeField.leadingAnchor.constraint(equalTo: scrollCheck.trailingAnchor, constant: 4),

            linesLabel.centerYAnchor.constraint(equalTo: scrollCheck.centerYAnchor),
            linesLabel.leadingAnchor.constraint(equalTo: scrollSizeField.trailingAnchor, constant: 4),
        ])

        // ── Alpha Blending row ──
        let alphaLabel = NSView.makeLabel(TTL("dialog.windowSetup.alpha"))
        alphaSlider = NSView.makeSlider(min: 20, max: 100, value: settings.windowAlpha * 100)
        alphaSlider.target = self
        alphaSlider.action = #selector(alphaSliderChanged(_:))
        alphaValueLabel = NSView.makeLabel(
            String(format: "%d%%", Int(settings.windowAlpha * 100)), alignment: .left)

        contentArea.addSubview(alphaLabel)
        contentArea.addSubview(alphaSlider)
        contentArea.addSubview(alphaValueLabel)

        NSLayoutConstraint.activate([
            alphaLabel.topAnchor.constraint(equalTo: scrollCheck.bottomAnchor, constant: 12),
            alphaLabel.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            alphaLabel.widthAnchor.constraint(equalToConstant: 60),

            alphaSlider.centerYAnchor.constraint(equalTo: alphaLabel.centerYAnchor),
            alphaSlider.leadingAnchor.constraint(equalTo: alphaLabel.trailingAnchor, constant: 4),
            alphaSlider.widthAnchor.constraint(equalToConstant: 200),

            alphaValueLabel.centerYAnchor.constraint(equalTo: alphaLabel.centerYAnchor),
            alphaValueLabel.leadingAnchor.constraint(equalTo: alphaSlider.trailingAnchor, constant: 8),
            alphaValueLabel.widthAnchor.constraint(equalToConstant: 50),

            alphaLabel.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
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

        // Alpha
        settings.windowAlpha = alphaSlider.doubleValue / 100.0
    }
}
#endif
