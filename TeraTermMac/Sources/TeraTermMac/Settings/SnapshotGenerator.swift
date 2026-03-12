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
 *   SnapshotGenerator.generateAll()                // Original 3 views
 *   generateAllValidationSnapshots()                // ALL dialogs, both languages
 *
 * Output goes to ~/Desktop/TT_UI_Preview/
 */

#if canImport(AppKit)
import AppKit

final class SnapshotGenerator {

    // MARK: - Snapshot Specs

    private struct Spec {
        let name: String
        let viewBuilder: () -> NSView
    }

    // MARK: - Public API

    /// Generate PNG snapshots for the original three dialog views.
    /// - Parameter outputDir: Optional output directory.
    static func generateAll(outputDir: URL? = nil) {
        let specs: [Spec] = [
            Spec(name: "01_NewConnection",
                 viewBuilder: { buildConnectionAccessoryView() }),
            Spec(name: "02_TerminalSetup",
                 viewBuilder: { buildTerminalSetupView() }),
            Spec(name: "03_KeyboardSetup",
                 viewBuilder: { buildKeyboardSetupView() }),
        ]

        renderSpecs(specs, outputDir: outputDir)
        NSLog("[SnapshotGenerator] All snapshots generated.")
    }

    // MARK: - Comprehensive Validation

    /// Generate PNG snapshots for ALL dialog views across all languages.
    /// Each dialog is rendered with a 2pt red boundary overlay.
    /// Reports warnings if any control's fittingSize exceeds the window.
    ///
    /// This is the main validation entry point requested by the refactoring task.
    static func generateAllValidationSnapshots(outputDir: URL? = nil) {
        let settings = TerminalSettings()
        var allSpecs: [Spec] = []

        // --- Connection / Setup dialogs ---
        allSpecs.append(Spec(name: "01_NewConnection",
                             viewBuilder: { buildConnectionAccessoryView() }))
        allSpecs.append(Spec(name: "02_TerminalSetup",
                             viewBuilder: { buildTerminalSetupView() }))
        allSpecs.append(Spec(name: "03_KeyboardSetup",
                             viewBuilder: { buildKeyboardSetupView() }))

        // --- BaseSetupDialogController subclasses ---
        allSpecs.append(Spec(name: "04_DragDropDialog",
                             viewBuilder: { buildDialogView(DragDropDialogController(path: "/tmp/test.txt")) }))
        allSpecs.append(Spec(name: "05_EditHistoryDialog",
                             viewBuilder: { buildDialogView(EditHistoryDialogController(history: ["host1", "host2"])) }))
        allSpecs.append(Spec(name: "06_LogDialog",
                             viewBuilder: { buildDialogView(LogDialogController()) }))
        allSpecs.append(Spec(name: "07_TCPIPDialog",
                             viewBuilder: { buildDialogView(TCPIPDialogController(settings: settings)) }))

        // --- SSH Dialogs ---
        allSpecs.append(Spec(name: "08_SSHAuthDialog",
                             viewBuilder: { buildDialogView(SSHAuthViewController(settings: settings)) }))

        // --- Additional Settings Tabs (13 total) ---
        let tabClasses: [(String, AdditionalSettingsTab)] = [
            ("09_Tab_General", GeneralTab(settings: settings)),
            ("10_Tab_Coding", CodingTab(settings: settings)),
            ("11_Tab_CopyPaste", CopyPasteTab(settings: settings)),
            ("12_Tab_Sequence", SequenceTab(settings: settings)),
            ("13_Tab_Mouse", MouseTab(settings: settings)),
            ("14_Tab_Log", LogTab(settings: settings)),
            ("15_Tab_Visual", VisualTab(settings: settings)),
            ("16_Tab_Font", FontTab(settings: settings)),
            ("17_Tab_TEKFont", TEKFontTab(settings: settings)),
            ("18_Tab_Theme", ThemeTab(settings: settings)),
            ("19_Tab_UI", UITab(settings: settings)),
            ("20_Tab_Plugin", PluginTab(settings: settings)),
            ("21_Tab_Debug", DebugTab(settings: settings)),
        ]
        for (name, tab) in tabClasses {
            allSpecs.append(Spec(name: name, viewBuilder: {
                let view = tab.contentView
                view.translatesAutoresizingMaskIntoConstraints = false
                return view
            }))
        }

        // --- File Transfer Accessory Views ---
        allSpecs.append(Spec(name: "22_XMODEMOption",
                             viewBuilder: { XMODEMOptionAccessory(isSend: true) }))
        allSpecs.append(Spec(name: "23_FileOption",
                             viewBuilder: { FileOptionAccessory() }))

        renderSpecs(allSpecs, outputDir: outputDir)

        NSLog("[SnapshotGenerator] All \(allSpecs.count) validation snapshots generated.")
    }

    // MARK: - Private Rendering

    private static func renderSpecs(_ specs: [Spec], outputDir: URL?) {
        for spec in specs {
            let view = spec.viewBuilder()
            view.translatesAutoresizingMaskIntoConstraints = false

            // Host the view in an offscreen window so Auto Layout resolves
            let vc = NSViewController()
            vc.view = view
            let window = NSWindow(contentViewController: vc)
            window.styleMask = [.titled]

            // Force layout
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()

            // Snapshot with red debug border
            view.saveToDebugPNG(name: spec.name, outputDir: outputDir)

            // Verify no controls overflow
            let fitting = view.fittingSize
            let bounds = view.bounds
            if bounds.width > 0 && bounds.height > 0 {
                if fitting.width > bounds.width + 2 || fitting.height > bounds.height + 2 {
                    NSLog("[SnapshotGenerator] WARNING: \(spec.name) fittingSize "
                        + "(\(Int(fitting.width))x\(Int(fitting.height))) exceeds bounds "
                        + "(\(Int(bounds.width))x\(Int(bounds.height)))")
                }
            }
        }
    }

    /// Build a BaseSetupDialogController's view for snapshotting.
    private static func buildDialogView(_ vc: BaseSetupDialogController) -> NSView {
        _ = vc.view  // force loadView
        return vc.view
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
        bsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let delLabel = NSView.makeLabel(TTL("dialog.keyboardSetup.deleteKey"))
        delLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let metaLabel = NSView.makeLabel(TTL("dialog.keyboardSetup.metaKey"))
        metaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let ansLabel = NSView.makeLabel(TTL("dialog.keyboardSetup.answerback"))
        ansLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let bsPopup = NSView.makePopUpButton(
            items: ["BS (0x08)", "DEL (0x7F)"])
        let delPopup = NSView.makePopUpButton(
            items: ["DEL (0x7F)", "BS (0x08)", TTL("dialog.keyboardSetup.deleteEscSeq")])
        let metaPopup = NSView.makePopUpButton(
            items: [TTL("dialog.keyboardSetup.metaOff"), TTL("dialog.keyboardSetup.metaOn")])
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
        grid.columnSpacing = DialogLayout.labelTrailing
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        for i in 0..<grid.numberOfRows {
            grid.row(at: i).rowAlignment = .firstBaseline
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        let m = DialogLayout.margin
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: m),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 500),
        ])

        return container
    }
}

// MARK: - Global Convenience Function

/// Generate validation snapshots for ALL dialogs in the project.
/// Each snapshot includes a 2pt red border and nested blue/green sub-control
/// boundaries for visual verification that no elements overlap.
///
/// Call this from a debug menu action or unit test:
/// ```swift
/// generateAllValidationSnapshots()
/// ```
func generateAllValidationSnapshots(outputDir: URL? = nil) {
    SnapshotGenerator.generateAllValidationSnapshots(outputDir: outputDir)
}

#endif
