/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * SnapshotGenerator — renders each dialog to a PNG image for visual
 * verification that controls fit within the specified window size.
 *
 * Usage:
 *   SnapshotGenerator.generateAll()
 *
 * Output goes to ~/Desktop/TT_UI_Preview/
 */

#if canImport(AppKit)
import AppKit

final class SnapshotGenerator {

    // MARK: - Snapshot Specs

    private struct Spec {
        let name: String
        let width: CGFloat
        let height: CGFloat
        let viewBuilder: () -> NSView
    }

    // MARK: - Public API

    /// Generate PNG snapshots for all three dialog views.
    /// - Parameter outputDir: Optional output directory.  Defaults to
    ///   the project `img/` directory or `~/Desktop/TT_UI_Preview/`.
    static func generateAll(outputDir: URL? = nil) {
        let specs: [Spec] = [
            Spec(name: "01_NewConnection",
                 width: 520, height: 260,
                 viewBuilder: { buildConnectionAccessoryView() }),
            Spec(name: "02_TerminalSetup",
                 width: 500, height: 420,
                 viewBuilder: { buildTerminalSetupView() }),
            Spec(name: "03_KeyboardSetup",
                 width: 540, height: 450,
                 viewBuilder: { buildKeyboardSetupView() }),
        ]

        for spec in specs {
            let view = spec.viewBuilder()
            let containerFrame = NSRect(x: 0, y: 0,
                                        width: spec.width, height: spec.height)

            // Host the view in an offscreen window so Auto Layout resolves
            let window = NSWindow(
                contentRect: containerFrame,
                styleMask: [.titled],
                backing: .buffered,
                defer: false)
            window.contentView = view
            view.frame = containerFrame

            // Force layout
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()

            // Snapshot
            view.saveToDebugPNG(name: spec.name, outputDir: outputDir)

            // Also verify intrinsic fitting vs spec size
            let fitting = view.fittingSize
            if fitting.width > spec.width || fitting.height > spec.height {
                NSLog("[SnapshotGenerator] WARNING: \(spec.name) fittingSize "
                    + "(\(fitting.width)x\(fitting.height)) exceeds spec "
                    + "(\(spec.width)x\(spec.height))")
            }
        }

        NSLog("[SnapshotGenerator] All snapshots generated.")
    }

    // MARK: - Connection Dialog Accessory View

    private static func buildConnectionAccessoryView() -> NSView {
        let _ = TerminalSettings()

        let accessoryView = NSView()
        accessoryView.translatesAutoresizingMaskIntoConstraints = false

        // ── TCP/IP Group Box ──
        let tcpBox = NSBox()
        tcpBox.translatesAutoresizingMaskIntoConstraints = false
        tcpBox.titlePosition = .noTitle
        accessoryView.addSubview(tcpBox)

        let tcpContent = NSView()
        tcpContent.translatesAutoresizingMaskIntoConstraints = false

        let tcpRadio = NSView.makeRadioButton(TTL("dialog.connection.tcpip"), tag: 0)
        tcpRadio.state = .on

        let hostLabel = NSView.makeLabel(TTL("dialog.connection.host"))

        let hostCombo = NSComboBox()
        hostCombo.translatesAutoresizingMaskIntoConstraints = false
        hostCombo.isEditable = true
        hostCombo.completes = true
        hostCombo.stringValue = "example.host.com"
        hostCombo.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let hostRow = NSStackView(views: [tcpRadio, hostLabel, hostCombo])
        hostRow.translatesAutoresizingMaskIntoConstraints = false
        hostRow.orientation = .horizontal
        hostRow.spacing = DialogLayout.labelTrailing
        hostRow.alignment = .firstBaseline

        // Service row
        let serviceLabel = NSView.makeLabel(TTL("dialog.connection.service"))
        let telnetRadio = NSView.makeRadioButton(TTL("dialog.connection.telnet"), tag: 0)
        telnetRadio.state = .on
        let tcpPortLabel = NSView.makeLabel(TTL("dialog.connection.tcpPort"))
        let tcpPortField = NSView.makeNumberField(value: 23, width: DialogLayout.narrowFieldWidth)

        let serviceRow = NSStackView(views: [serviceLabel, telnetRadio])
        serviceRow.translatesAutoresizingMaskIntoConstraints = false
        serviceRow.orientation = .horizontal
        serviceRow.spacing = DialogLayout.labelTrailing
        serviceRow.alignment = .firstBaseline

        let portRow = NSStackView(views: [tcpPortLabel, tcpPortField])
        portRow.translatesAutoresizingMaskIntoConstraints = false
        portRow.orientation = .horizontal
        portRow.spacing = DialogLayout.labelTrailing
        portRow.alignment = .firstBaseline

        let row2 = NSStackView(views: [serviceRow, portRow])
        row2.translatesAutoresizingMaskIntoConstraints = false
        row2.orientation = .horizontal
        row2.spacing = DialogLayout.sectionSpacing
        row2.alignment = .firstBaseline

        // SSH row
        let sshRadio = NSView.makeRadioButton("SSH", tag: 1)
        let sshVerLabel = NSView.makeLabel(TTL("dialog.connection.sshVersion"))
        let sshVerPopup = NSView.makePopUpButton(
            items: SSHVersion.allCases.map { $0.displayName })

        let sshRow = NSStackView(views: [sshRadio])
        sshRow.translatesAutoresizingMaskIntoConstraints = false
        sshRow.orientation = .horizontal
        sshRow.spacing = DialogLayout.labelTrailing
        sshRow.alignment = .firstBaseline

        let sshVerRow = NSStackView(views: [sshVerLabel, sshVerPopup])
        sshVerRow.translatesAutoresizingMaskIntoConstraints = false
        sshVerRow.orientation = .horizontal
        sshVerRow.spacing = DialogLayout.labelTrailing
        sshVerRow.alignment = .firstBaseline

        let row3 = NSStackView(views: [sshRow, sshVerRow])
        row3.translatesAutoresizingMaskIntoConstraints = false
        row3.orientation = .horizontal
        row3.spacing = DialogLayout.sectionSpacing
        row3.alignment = .firstBaseline

        // Other row
        let otherRadio = NSView.makeRadioButton(TTL("dialog.connection.other"), tag: 2)
        let ipVerLabel = NSView.makeLabel(TTL("dialog.connection.ipVersion"))
        let ipVerPopup = NSView.makePopUpButton(
            items: ProtocolFamily.allCases.map { $0.displayName })

        let otherRow = NSStackView(views: [otherRadio])
        otherRow.translatesAutoresizingMaskIntoConstraints = false
        otherRow.orientation = .horizontal
        otherRow.spacing = DialogLayout.labelTrailing
        otherRow.alignment = .firstBaseline

        let ipVerRow = NSStackView(views: [ipVerLabel, ipVerPopup])
        ipVerRow.translatesAutoresizingMaskIntoConstraints = false
        ipVerRow.orientation = .horizontal
        ipVerRow.spacing = DialogLayout.labelTrailing
        ipVerRow.alignment = .firstBaseline

        let row4 = NSStackView(views: [otherRow, ipVerRow])
        row4.translatesAutoresizingMaskIntoConstraints = false
        row4.orientation = .horizontal
        row4.spacing = DialogLayout.sectionSpacing
        row4.alignment = .firstBaseline

        // Radio button minimum widths
        for radio in [telnetRadio, sshRadio, otherRadio] {
            radio.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        }

        let serviceStack = NSStackView(views: [row2, row3, row4])
        serviceStack.translatesAutoresizingMaskIntoConstraints = false
        serviceStack.orientation = .vertical
        serviceStack.alignment = .leading
        serviceStack.spacing = DialogLayout.rowSpacing

        let tcpStack = NSStackView(views: [hostRow, serviceStack])
        tcpStack.translatesAutoresizingMaskIntoConstraints = false
        tcpStack.orientation = .vertical
        tcpStack.alignment = .leading
        tcpStack.spacing = DialogLayout.rowSpacing

        tcpContent.addSubview(tcpStack)
        let innerM = DialogLayout.innerMargin
        NSLayoutConstraint.activate([
            tcpStack.topAnchor.constraint(equalTo: tcpContent.topAnchor, constant: innerM),
            tcpStack.leadingAnchor.constraint(equalTo: tcpContent.leadingAnchor, constant: innerM),
            tcpStack.trailingAnchor.constraint(lessThanOrEqualTo: tcpContent.trailingAnchor, constant: -innerM),
            tcpStack.bottomAnchor.constraint(equalTo: tcpContent.bottomAnchor, constant: -innerM),
        ])

        tcpBox.contentView = tcpContent

        NSLayoutConstraint.activate([
            serviceLabel.trailingAnchor.constraint(equalTo: tcpRadio.trailingAnchor),
            sshRow.leadingAnchor.constraint(equalTo: serviceRow.leadingAnchor),
            sshRow.widthAnchor.constraint(equalTo: serviceRow.widthAnchor),
            otherRow.leadingAnchor.constraint(equalTo: serviceRow.leadingAnchor),
            otherRow.widthAnchor.constraint(equalTo: serviceRow.widthAnchor),
            hostCombo.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])

        // ── Serial Group Box ──
        let serialBox = NSBox()
        serialBox.translatesAutoresizingMaskIntoConstraints = false
        serialBox.titlePosition = .noTitle
        accessoryView.addSubview(serialBox)

        let serialContent = NSView()
        serialContent.translatesAutoresizingMaskIntoConstraints = false

        let serialRadio = NSView.makeRadioButton(TTL("dialog.connection.serial"), tag: 1)
        let serialPortLabel = NSView.makeLabel(TTL("dialog.connection.serialPort"))
        let serialPortPopup = NSPopUpButton()
        serialPortPopup.translatesAutoresizingMaskIntoConstraints = false
        serialPortPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        serialPortPopup.addItem(withTitle: "/dev/tty.usbserial-XXXX")

        let serialRow = NSStackView(views: [serialRadio, serialPortLabel, serialPortPopup])
        serialRow.translatesAutoresizingMaskIntoConstraints = false
        serialRow.orientation = .horizontal
        serialRow.spacing = DialogLayout.labelTrailing
        serialRow.alignment = .firstBaseline

        serialContent.addSubview(serialRow)
        NSLayoutConstraint.activate([
            serialRow.topAnchor.constraint(equalTo: serialContent.topAnchor, constant: innerM),
            serialRow.leadingAnchor.constraint(equalTo: serialContent.leadingAnchor, constant: innerM),
            serialRow.trailingAnchor.constraint(equalTo: serialContent.trailingAnchor, constant: -innerM),
            serialRow.bottomAnchor.constraint(equalTo: serialContent.bottomAnchor, constant: -innerM),
        ])
        serialBox.contentView = serialContent

        // ── Main layout ──
        NSLayoutConstraint.activate([
            tcpBox.topAnchor.constraint(equalTo: accessoryView.topAnchor),
            tcpBox.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor),
            tcpBox.trailingAnchor.constraint(equalTo: accessoryView.trailingAnchor),

            serialBox.topAnchor.constraint(equalTo: tcpBox.bottomAnchor, constant: DialogLayout.innerMargin),
            serialBox.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor),
            serialBox.trailingAnchor.constraint(equalTo: accessoryView.trailingAnchor),
            serialBox.bottomAnchor.constraint(equalTo: accessoryView.bottomAnchor),

            accessoryView.widthAnchor.constraint(greaterThanOrEqualToConstant: 520),
        ])

        return accessoryView
    }

    // MARK: - Terminal Setup View

    private static func buildTerminalSetupView() -> NSView {
        let settings = TerminalSettings()
        let vc = TerminalSetupViewController(settings: settings)
        _ = vc.view // force view load
        return vc.view
    }

    // MARK: - Keyboard Setup View

    private static func buildKeyboardSetupView() -> NSView {
        let bsLabel = NSView.makeLabel(TTL("dialog.keyboardSetup.bsKey"))
        let delLabel = NSView.makeLabel(TTL("dialog.keyboardSetup.deleteKey"))
        let metaLabel = NSView.makeLabel(TTL("dialog.keyboardSetup.metaKey"))
        let ansLabel = NSView.makeLabel(TTL("dialog.keyboardSetup.answerback"))

        let kbPopupWidth: CGFloat = 180
        let bsPopup = NSView.makePopUpButton(
            items: ["BS (0x08)", "DEL (0x7F)"], width: kbPopupWidth)
        let delPopup = NSView.makePopUpButton(
            items: ["DEL (0x7F)", "BS (0x08)", TTL("dialog.keyboardSetup.deleteEscSeq")],
            width: kbPopupWidth)
        let metaPopup = NSView.makePopUpButton(
            items: [TTL("dialog.keyboardSetup.metaOff"), TTL("dialog.keyboardSetup.metaOn")],
            width: kbPopupWidth)
        let ansField = NSView.makeTextField(
            value: "", placeholder: TTL("dialog.keyboardSetup.answerbackPlaceholder"),
            width: DialogLayout.wideFieldWidth)

        let grid = NSGridView(views: [
            [bsLabel,   bsPopup],
            [delLabel,  delPopup],
            [metaLabel, metaPopup],
            [ansLabel,  ansField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 0).width = 140
        for i in 0..<grid.numberOfRows {
            grid.row(at: i).rowAlignment = .firstBaseline
            grid.row(at: i).height = 24
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 500),
        ])

        return container
    }
}
#endif
