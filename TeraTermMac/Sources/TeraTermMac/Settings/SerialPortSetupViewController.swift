/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * Serial Port Setup dialog — faithful reproduction of Tera Term 5.6 IDD_SERIALDLG.
 * Layout uses Auto Layout anchors to replicate the original left-label / right-dropdown grid.
 *
 * Original dialog: 276 x 269 DLU
 *
 * Port:          [/dev/cu.usbserial  ▾]
 * Speed:         [9600               ▾]
 * Data:          [8                  ▾]
 * Parity:        [None               ▾]
 * Stop bits:     [1                  ▾]
 * Flow control:  [None               ▾]
 *
 * ┌─Transmit delay─────────────────────┐
 * │ [  0] msec/char   [  0] msec/line  │
 * └────────────────────────────────────┘
 *
 *                        [Help]  [Cancel]  [OK]
 */

#if canImport(AppKit)
import AppKit

class SerialPortSetupViewController: BaseSetupDialogController {

    private var settings: TerminalSettings

    // Controls
    private var portPopup: NSPopUpButton!
    private var baudPopup: NSPopUpButton!
    private var dataPopup: NSPopUpButton!
    private var parityPopup: NSPopUpButton!
    private var stopPopup: NSPopUpButton!
    private var flowPopup: NSPopUpButton!
    private var delayCharField: NSTextField!
    private var delayLineField: NSTextField!

    // Available serial ports
    private var serialPorts: [String] = []

    // Standard baud rates matching Tera Term
    private let baudRates = [
        "110", "300", "600", "1200", "2400", "4800",
        "9600", "14400", "19200", "38400", "57600",
        "115200", "230400", "460800", "921600"
    ]

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = "Tera Term: Serial port setup"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        serialPorts = Self.findSerialPorts()
        setupControls()
    }

    private func setupControls() {
        let labelWidth: CGFloat = 90
        let popupWidth: CGFloat = 180

        // ── Row labels (right-aligned, like Tera Term) ──
        let portLabel = NSView.makeLabel(TTL("dialog.serialPort.port"))
        let baudLabel = NSView.makeLabel(TTL("dialog.serialSetup.speed"))
        let dataLabel = NSView.makeLabel(TTL("dialog.serialPort.dataBits"))
        let parityLabel = NSView.makeLabel(TTL("dialog.serialPort.parity"))
        let stopLabel = NSView.makeLabel(TTL("dialog.serialSetup.stopBits"))
        let flowLabel = NSView.makeLabel(TTL("dialog.serialSetup.flowControl"))

        let labels = [portLabel, baudLabel, dataLabel, parityLabel, stopLabel, flowLabel]
        for label in labels {
            contentArea.addSubview(label)
        }

        // ── Dropdowns ──
        let portItems = serialPorts.isEmpty
            ? [TTL("dialog.serialPort.noPortsFound")]
            : serialPorts
        portPopup = NSView.makePopUpButton(items: portItems,
            selected: settings.serialPort, width: popupWidth)

        baudPopup = NSView.makePopUpButton(items: baudRates,
            selected: "\(settings.baudRate)", width: popupWidth)

        dataPopup = NSView.makePopUpButton(items: ["7", "8"],
            selected: "\(settings.dataBits)", width: popupWidth)

        parityPopup = NSView.makePopUpButton(
            items: [TTL("dialog.serialPort.parityNone"),
                    TTL("dialog.serialPort.parityOdd"),
                    TTL("dialog.serialPort.parityEven"),
                    "Mark", "Space"],
            width: popupWidth)
        parityPopup.selectItem(at: settings.parity.rawValue)

        stopPopup = NSView.makePopUpButton(items: ["1", "1.5", "2"],
            selected: "\(settings.stopBits)", width: popupWidth)

        flowPopup = NSView.makePopUpButton(
            items: [TTL("dialog.serialPort.flowNone"),
                    TTL("dialog.serialPort.flowXonXoff"),
                    TTL("dialog.serialPort.flowHardware")],
            width: popupWidth)
        flowPopup.selectItem(at: settings.flowControl.rawValue)

        let popups = [portPopup!, baudPopup!, dataPopup!, parityPopup!, stopPopup!, flowPopup!]
        for popup in popups {
            contentArea.addSubview(popup)
        }

        // Enable/disable baud rate when port changes
        portPopup.target = self
        portPopup.action = #selector(portChanged(_:))

        // ── Transmit Delay Group Box ──
        let delayBox = NSView.makeGroupBox(title: TTL("dialog.serialSetup.transmitDelay"))
        contentArea.addSubview(delayBox)

        delayCharField = NSView.makeNumberField(value: 0, width: 50)
        let charLabel = NSView.makeLabel(TTL("dialog.serialSetup.msecChar"), alignment: .left)
        delayLineField = NSView.makeNumberField(value: 0, width: 50)
        let lineLabel = NSView.makeLabel(TTL("dialog.serialSetup.msecLine"), alignment: .left)

        for v: NSView in [delayCharField, charLabel, delayLineField, lineLabel] {
            delayBox.contentView!.addSubview(v)
        }

        // ── Layout ──
        let dialogWidth: CGFloat = 360
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        // Build label-popup grid rows
        var previousAnchor = contentArea.topAnchor
        let rowSpacing: CGFloat = 10

        for i in 0..<labels.count {
            let label = labels[i]
            let popup = popups[i]
            let isFirst = (i == 0)

            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: previousAnchor, constant: isFirst ? 0 : rowSpacing),
                label.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
                label.widthAnchor.constraint(equalToConstant: labelWidth),

                popup.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                popup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: DialogLayout.labelTrailing),
            ])
            previousAnchor = label.bottomAnchor
        }

        // Delay box
        let delayP: CGFloat = 12
        NSLayoutConstraint.activate([
            delayBox.topAnchor.constraint(equalTo: previousAnchor, constant: 16),
            delayBox.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            delayBox.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
        ])

        let dc = delayBox.contentView!
        NSLayoutConstraint.activate([
            delayCharField.topAnchor.constraint(equalTo: dc.topAnchor, constant: DialogLayout.groupBoxTopPadding - 4),
            delayCharField.leadingAnchor.constraint(equalTo: dc.leadingAnchor, constant: delayP),

            charLabel.centerYAnchor.constraint(equalTo: delayCharField.centerYAnchor),
            charLabel.leadingAnchor.constraint(equalTo: delayCharField.trailingAnchor, constant: 4),

            delayLineField.centerYAnchor.constraint(equalTo: delayCharField.centerYAnchor),
            delayLineField.leadingAnchor.constraint(equalTo: dc.centerXAnchor, constant: 10),

            lineLabel.centerYAnchor.constraint(equalTo: delayCharField.centerYAnchor),
            lineLabel.leadingAnchor.constraint(equalTo: delayLineField.trailingAnchor, constant: 4),

            delayCharField.bottomAnchor.constraint(equalTo: dc.bottomAnchor, constant: -delayP + 4),
        ])

        delayBox.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor).isActive = true
    }

    @objc private func portChanged(_ sender: NSPopUpButton) {
        let hasPort = !serialPorts.isEmpty
            && sender.selectedItem?.title != TTL("dialog.serialPort.noPortsFound")
        baudPopup.isEnabled = hasPort
        dataPopup.isEnabled = hasPort
        parityPopup.isEnabled = hasPort
        stopPopup.isEnabled = hasPort
        flowPopup.isEnabled = hasPort
    }

    // MARK: - Apply

    override func applySettings() {
        if let port = portPopup.selectedItem?.title,
           !port.starts(with: "(") {
            settings.serialPort = port
        }
        settings.baudRate = Int(baudPopup.selectedItem?.title ?? "9600") ?? 9600
        settings.dataBits = Int(dataPopup.selectedItem?.title ?? "8") ?? 8
        settings.parity = Parity(rawValue: parityPopup.indexOfSelectedItem) ?? .none
        settings.stopBits = Int(stopPopup.selectedItem?.title ?? "1") ?? 1
        settings.flowControl = FlowControl(rawValue: flowPopup.indexOfSelectedItem) ?? .none
    }

    // MARK: - Serial Port Discovery

    static func findSerialPorts() -> [String] {
        var ports: [String] = []
        let devDir = "/dev"
        if let items = try? FileManager.default.contentsOfDirectory(atPath: devDir) {
            for item in items.sorted() {
                // macOSでは各ポートが tty.* と cu.* の2つで現れる。
                // cu.* (call-up) は発信用でDCDを待たないため、
                // ターミナルエミュレータでは cu.* のみ使用する。
                if item.hasPrefix("cu.") {
                    ports.append("\(devDir)/\(item)")
                }
            }
        }
        return ports
    }
}
#endif
