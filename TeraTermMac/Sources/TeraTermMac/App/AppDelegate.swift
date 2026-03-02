/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of teraterm.cpp / ttermpro main to Swift/macOS
 * Application delegate - main application lifecycle
 */

#if canImport(AppKit)
import AppKit

// MARK: - Localization Helper

private func L(_ key: String) -> String {
    #if SWIFT_PACKAGE
    return NSLocalizedString(key, bundle: Bundle.module, comment: "")
    #else
    return NSLocalizedString(key, bundle: Bundle.main, comment: "")
    #endif
}

// MARK: - Connection Dialog Helper (radio button group controller)

private class ConnectionDialogHelper: NSObject {
    var tcpControls: [NSControl] = []
    var serialControls: [NSControl] = []
    weak var tcpPortField: NSTextField?
    weak var sshVersionLabel: NSTextField?
    weak var sshVersionPopup: NSPopUpButton?

    /// TCP/IP vs Serial radio (tag 0=TCP, 1=Serial)
    @objc func connectionTypeChanged(_ sender: NSButton) {
        let isTCP = sender.tag == 0
        for ctrl in tcpControls { ctrl.isEnabled = isTCP }
        for ctrl in serialControls { ctrl.isEnabled = !isTCP }
    }

    /// Service radio: Telnet(tag=0) / SSH(tag=1) / Other(tag=2)
    @objc func serviceChanged(_ sender: NSButton) {
        switch sender.tag {
        case 0: // Telnet
            tcpPortField?.integerValue = 23
            sshVersionLabel?.isEnabled = false
            sshVersionPopup?.isEnabled = false
        case 1: // SSH
            tcpPortField?.integerValue = 22
            sshVersionLabel?.isEnabled = true
            sshVersionPopup?.isEnabled = true
        default: // Other
            sshVersionLabel?.isEnabled = false
            sshVersionPopup?.isEnabled = false
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // Window controllers
    private var windowControllers: [TerminalWindowController] = []
    private var settings: TerminalSettings = TerminalSettings()

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load settings
        settings = TerminalSettings.load()

        // Build main menu
        buildMainMenu()

        // Open first terminal window (disconnected)
        let wc = newTerminalWindow()

        // Show connection dialog so user can choose where to connect
        showConnectionDialog(for: wc)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save settings
        settings.save()

        // Close all connections
        for wc in windowControllers {
            wc.disconnect()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check for active connections
        let activeConnections = windowControllers.filter { $0.connectionManager.state != .disconnected }
        if !activeConnections.isEmpty && settings.confirmOnDisconnect {
            let alert = NSAlert()
            alert.messageText = L("dialog.quit.title")
            alert.informativeText = String(format: L("dialog.quit.message"), activeConnections.count)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("dialog.quit.quit"))
            alert.addButton(withTitle: L("dialog.quit.cancel"))
            if alert.runModal() == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }
        return .terminateNow
    }

    // MARK: - Window Management

    @discardableResult
    func newTerminalWindow() -> TerminalWindowController {
        let wc = TerminalWindowController(settings: settings)
        windowControllers.append(wc)
        wc.showWindow(self)

        // Clean up when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: wc.window,
            queue: .main
        ) { [weak self] notification in
            self?.windowControllers.removeAll { $0.window == notification.object as? NSWindow }
        }

        return wc
    }

    private var activeWindowController: TerminalWindowController? {
        guard let keyWindow = NSApp.keyWindow else { return windowControllers.first }
        return windowControllers.first { $0.window == keyWindow }
    }

    // MARK: - Main Menu (port of vtwin.cpp InitMenu)

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: L("menu.app.about"), action: #selector(showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L("menu.app.preferences"), action: #selector(showPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L("menu.app.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: L("menu.app.hideOthers"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: L("menu.app.showAll"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L("menu.app.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: L("menu.file"))
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: L("menu.file.newConnection"), action: #selector(newConnection(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: L("menu.file.newWindow"), action: #selector(newWindow(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: L("menu.file.duplicateSession"), action: #selector(duplicateSession(_:)), keyEquivalent: "d")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: L("menu.file.log"), action: #selector(startLog(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: L("menu.file.stopLog"), action: #selector(stopLog(_:)), keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())

        // File transfer submenu
        let transferMenu = NSMenu(title: L("menu.file.fileTransfer"))
        let transferMenuItem = NSMenuItem(title: L("menu.file.fileTransfer"), action: nil, keyEquivalent: "")
        transferMenuItem.submenu = transferMenu
        fileMenu.addItem(transferMenuItem)
        transferMenu.addItem(withTitle: L("menu.file.xmodemSend"), action: #selector(xmodemSend(_:)), keyEquivalent: "")
        transferMenu.addItem(withTitle: L("menu.file.xmodemReceive"), action: #selector(xmodemRecv(_:)), keyEquivalent: "")
        transferMenu.addItem(NSMenuItem.separator())
        transferMenu.addItem(withTitle: L("menu.file.zmodemSend"), action: #selector(zmodemSend(_:)), keyEquivalent: "")
        transferMenu.addItem(withTitle: L("menu.file.zmodemReceive"), action: #selector(zmodemRecv(_:)), keyEquivalent: "")
        transferMenu.addItem(NSMenuItem.separator())
        transferMenu.addItem(withTitle: L("menu.file.kermitSend"), action: #selector(kermitSend(_:)), keyEquivalent: "")
        transferMenu.addItem(withTitle: L("menu.file.kermitReceive"), action: #selector(kermitRecv(_:)), keyEquivalent: "")

        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: L("menu.file.disconnect"), action: #selector(doDisconnect(_:)), keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: L("menu.file.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L("menu.edit"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: L("menu.edit.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("menu.edit.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("menu.edit.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: L("menu.edit.clearScreen"), action: #selector(clearScreen(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: L("menu.edit.clearBuffer"), action: #selector(clearBuffer(_:)), keyEquivalent: "k")

        // Setup menu
        let setupMenuItem = NSMenuItem()
        mainMenu.addItem(setupMenuItem)
        let setupMenu = NSMenu(title: L("menu.setup"))
        setupMenuItem.submenu = setupMenu
        setupMenu.addItem(withTitle: L("menu.setup.terminal"), action: #selector(setupTerminal(_:)), keyEquivalent: "")
        setupMenu.addItem(withTitle: L("menu.setup.window"), action: #selector(setupWindow(_:)), keyEquivalent: "")
        setupMenu.addItem(withTitle: L("menu.setup.font"), action: #selector(setupFont(_:)), keyEquivalent: "")
        setupMenu.addItem(withTitle: L("menu.setup.keyboard"), action: #selector(setupKeyboard(_:)), keyEquivalent: "")
        setupMenu.addItem(withTitle: L("menu.setup.serialPort"), action: #selector(setupSerialPort(_:)), keyEquivalent: "")
        setupMenu.addItem(NSMenuItem.separator())
        setupMenu.addItem(withTitle: L("menu.setup.saveSetup"), action: #selector(saveSetup(_:)), keyEquivalent: "")
        setupMenu.addItem(withTitle: L("menu.setup.restoreSetup"), action: #selector(restoreSetup(_:)), keyEquivalent: "")

        // Control menu
        let controlMenuItem = NSMenuItem()
        mainMenu.addItem(controlMenuItem)
        let controlMenu = NSMenu(title: L("menu.control"))
        controlMenuItem.submenu = controlMenu
        controlMenu.addItem(withTitle: L("menu.control.resetTerminal"), action: #selector(resetTerminal(_:)), keyEquivalent: "")
        controlMenu.addItem(withTitle: L("menu.control.areYouThere"), action: #selector(areYouThere(_:)), keyEquivalent: "")
        controlMenu.addItem(withTitle: L("menu.control.sendBreak"), action: #selector(sendBreak(_:)), keyEquivalent: "")

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: L("menu.window"))
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: L("menu.window.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L("menu.window.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: L("menu.help"))
        helpMenuItem.submenu = helpMenu
        helpMenu.addItem(withTitle: L("menu.help.help"), action: #selector(showHelp(_:)), keyEquivalent: "?")
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

    @objc func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = L("dialog.about.title")
        alert.informativeText = L("dialog.about.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("dialog.about.ok"))
        alert.runModal()
    }

    @objc func showPreferences(_ sender: Any?) {
        showTerminalSetupDialog()
    }

    @objc func newConnection(_ sender: Any?) {
        showConnectionDialog(for: activeWindowController)
    }

    @objc func newWindow(_ sender: Any?) {
        let wc = newTerminalWindow()
        showConnectionDialog(for: wc)
    }

    @objc func duplicateSession(_ sender: Any?) {
        let wc = newTerminalWindow()
        if let active = activeWindowController {
            if let tcp = active.connectionManager.currentConnection as? TCPConnection {
                wc.connectTCP(host: tcp.host, port: tcp.port, telnet: false)
            } else {
                wc.connectLocalShell()
            }
        } else {
            wc.connectLocalShell()
        }
    }

    @objc func startLog(_ sender: Any?) {
        activeWindowController?.startLog()
    }

    @objc func stopLog(_ sender: Any?) {
        activeWindowController?.stopLog()
    }

    @objc func xmodemSend(_ sender: Any?) { activeWindowController?.sendFile(protocol: .xmodemCRC) }
    @objc func xmodemRecv(_ sender: Any?) { activeWindowController?.receiveFile(protocol: .xmodemCRC) }
    @objc func zmodemSend(_ sender: Any?) { activeWindowController?.sendFile(protocol: .zmodem) }
    @objc func zmodemRecv(_ sender: Any?) { activeWindowController?.receiveFile(protocol: .zmodem) }
    @objc func kermitSend(_ sender: Any?) { activeWindowController?.sendFile(protocol: .kermit) }
    @objc func kermitRecv(_ sender: Any?) { activeWindowController?.receiveFile(protocol: .kermit) }

    @objc func doDisconnect(_ sender: Any?) {
        activeWindowController?.disconnect()
    }

    @objc func clearScreen(_ sender: Any?) {
        activeWindowController?.clearScreen()
    }

    @objc func clearBuffer(_ sender: Any?) {
        activeWindowController?.clearBuffer()
    }

    @objc func setupTerminal(_ sender: Any?) {
        showTerminalSetupDialog()
    }

    @objc func setupWindow(_ sender: Any?) {
        showTerminalSetupDialog()
    }

    @objc func setupFont(_ sender: Any?) {
        guard activeWindowController != nil else { return }
        let fontManager = NSFontManager.shared
        fontManager.target = self
        fontManager.action = #selector(changeFont(_:))

        let font = NSFont(name: settings.fontName, size: CGFloat(settings.fontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(settings.fontSize), weight: .regular)
        fontManager.setSelectedFont(font, isMultiple: false)
        fontManager.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager else { return }
        let currentFont = NSFont(name: settings.fontName, size: CGFloat(settings.fontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(settings.fontSize), weight: .regular)
        let newFont = fontManager.convert(currentFont)
        settings.fontName = newFont.fontName
        settings.fontSize = Double(newFont.pointSize)
        activeWindowController?.terminalView.settings = settings
        activeWindowController?.terminalView.updateFont()
    }

    @objc func setupKeyboard(_ sender: Any?) {
        showTerminalSetupDialog()
    }

    @objc func setupSerialPort(_ sender: Any?) {
        showSerialPortDialog()
    }

    @objc func saveSetup(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "settings.json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.settings.save(to: url)
        }
    }

    @objc func restoreSetup(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.settings = TerminalSettings.load(from: url)
            self?.activeWindowController?.terminalView.settings = self!.settings
            self?.activeWindowController?.terminalView.updateFont()
        }
    }

    @objc func resetTerminal(_ sender: Any?) {
        activeWindowController?.resetTerminal()
    }

    @objc func areYouThere(_ sender: Any?) {
        activeWindowController?.connectionManager.send(Data([0xFF, 0xF6]))
    }

    @objc func sendBreak(_ sender: Any?) {
        activeWindowController?.connectionManager.sendBreak()
    }

    @objc func showHelp(_ sender: Any?) {
        if let url = URL(string: "https://teratermproject.github.io/") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Dialogs (port of ttpdlg)

    private func showConnectionDialog(for targetWC: TerminalWindowController? = nil) {
        let alert = NSAlert()
        alert.messageText = L("dialog.connection.title")
        alert.informativeText = ""

        // Helper retains target/action for radio button groups
        let helper = ConnectionDialogHelper()
        objc_setAssociatedObject(alert, "helper", helper, .OBJC_ASSOCIATION_RETAIN)

        // Layout matches original TTSSH IDD_HOSTDLG exactly:
        //   y=8:  TCP/IP radio  | Host: [combobox]
        //   y=34: Service: (*) Telnet          TCP port#: [  ]
        //   y=46:          ( ) SSH             SSH ver: [v]
        //   y=58:          ( ) Other           IP ver:  [v]
        //   y=87: Serial radio  | Port: [combobox]
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 195))

        // ── TCP/IP Group Box (original: GroupBox 4,0,228,78) ──
        let tcpBox = NSBox(frame: NSRect(x: 0, y: 55, width: 420, height: 140))
        tcpBox.title = ""
        tcpBox.titlePosition = .noTitle
        accessoryView.addSubview(tcpBox)

        // Row 1: TCP/IP radio + Host (original y=8-10)
        let tcpRadio = NSButton(radioButtonWithTitle: L("dialog.connection.tcpip"),
                                target: helper, action: #selector(ConnectionDialogHelper.connectionTypeChanged(_:)))
        tcpRadio.frame = NSRect(x: 8, y: 172, width: 75, height: 18)
        tcpRadio.tag = 0
        tcpRadio.state = (settings.portType != .serial) ? .on : .off
        accessoryView.addSubview(tcpRadio)

        let hostLabel = NSTextField(labelWithString: L("dialog.connection.host"))
        hostLabel.frame = NSRect(x: 68, y: 172, width: 45, height: 17)
        hostLabel.alignment = .right
        accessoryView.addSubview(hostLabel)

        let hostCombo = NSComboBox(frame: NSRect(x: 118, y: 169, width: 290, height: 24))
        hostCombo.isEditable = true
        hostCombo.completes = true
        hostCombo.stringValue = settings.hostname
        hostCombo.placeholderString = L("dialog.connection.hostPlaceholder")
        for h in settings.hostHistory {
            hostCombo.addItem(withObjectValue: h)
        }
        accessoryView.addSubview(hostCombo)

        // Row 2: Service: Telnet | TCP port# (original y=28-34)
        let serviceLabel = NSTextField(labelWithString: L("dialog.connection.service"))
        serviceLabel.frame = NSRect(x: 20, y: 140, width: 90, height: 17)
        serviceLabel.alignment = .right
        accessoryView.addSubview(serviceLabel)

        let telnetRadio = NSButton(radioButtonWithTitle: L("dialog.connection.telnet"),
                                   target: helper, action: #selector(ConnectionDialogHelper.serviceChanged(_:)))
        telnetRadio.frame = NSRect(x: 118, y: 140, width: 70, height: 18)
        telnetRadio.tag = 0
        telnetRadio.state = (settings.serviceType == .telnet) ? .on : .off
        accessoryView.addSubview(telnetRadio)

        let tcpPortLabel = NSTextField(labelWithString: L("dialog.connection.tcpPort"))
        tcpPortLabel.frame = NSRect(x: 240, y: 140, width: 90, height: 17)
        tcpPortLabel.alignment = .right
        accessoryView.addSubview(tcpPortLabel)

        let tcpPortField = NSTextField(frame: NSRect(x: 335, y: 137, width: 55, height: 24))
        tcpPortField.integerValue = settings.defaultPort
        accessoryView.addSubview(tcpPortField)
        helper.tcpPortField = tcpPortField

        // Row 3: SSH | SSH version (original y=45-46)
        let sshRadio = NSButton(radioButtonWithTitle: "SSH",
                                target: helper, action: #selector(ConnectionDialogHelper.serviceChanged(_:)))
        sshRadio.frame = NSRect(x: 118, y: 116, width: 50, height: 18)
        sshRadio.tag = 1
        sshRadio.state = (settings.serviceType == .ssh) ? .on : .off
        accessoryView.addSubview(sshRadio)

        let sshVerLabel = NSTextField(labelWithString: L("dialog.connection.sshVersion"))
        sshVerLabel.frame = NSRect(x: 210, y: 116, width: 120, height: 17)
        sshVerLabel.alignment = .right
        sshVerLabel.isEnabled = (settings.serviceType == .ssh)
        accessoryView.addSubview(sshVerLabel)
        helper.sshVersionLabel = sshVerLabel

        let sshVerPopup = NSPopUpButton(frame: NSRect(x: 335, y: 113, width: 75, height: 24))
        for v in SSHVersion.allCases {
            sshVerPopup.addItem(withTitle: v.displayName)
        }
        sshVerPopup.selectItem(withTitle: settings.sshVersion.displayName)
        sshVerPopup.isEnabled = (settings.serviceType == .ssh)
        accessoryView.addSubview(sshVerPopup)
        helper.sshVersionPopup = sshVerPopup

        // Row 4: Other | IP version (original y=58-63)
        let otherRadio = NSButton(radioButtonWithTitle: L("dialog.connection.other"),
                                  target: helper, action: #selector(ConnectionDialogHelper.serviceChanged(_:)))
        otherRadio.frame = NSRect(x: 118, y: 92, width: 70, height: 18)
        otherRadio.tag = 2
        otherRadio.state = (settings.serviceType == .other) ? .on : .off
        accessoryView.addSubview(otherRadio)

        let ipVerLabel = NSTextField(labelWithString: L("dialog.connection.ipVersion"))
        ipVerLabel.frame = NSRect(x: 210, y: 92, width: 120, height: 17)
        ipVerLabel.alignment = .right
        accessoryView.addSubview(ipVerLabel)

        let ipVerPopup = NSPopUpButton(frame: NSRect(x: 335, y: 89, width: 75, height: 24))
        for pf in ProtocolFamily.allCases {
            ipVerPopup.addItem(withTitle: pf.displayName)
        }
        ipVerPopup.selectItem(withTitle: settings.protocolFamily.displayName)
        accessoryView.addSubview(ipVerPopup)

        helper.tcpControls = [hostLabel, hostCombo, serviceLabel,
                              telnetRadio, sshRadio, otherRadio,
                              tcpPortLabel, tcpPortField,
                              sshVerLabel, sshVerPopup,
                              ipVerLabel, ipVerPopup]

        // ── Serial Group Box (original: GroupBox 4,79,228,24) ──
        let serialBox = NSBox(frame: NSRect(x: 0, y: 0, width: 420, height: 50))
        serialBox.title = ""
        serialBox.titlePosition = .noTitle
        accessoryView.addSubview(serialBox)

        // Row 5: Serial radio + Port (original y=87-89)
        let serialRadio = NSButton(radioButtonWithTitle: L("dialog.connection.serial"),
                                   target: helper, action: #selector(ConnectionDialogHelper.connectionTypeChanged(_:)))
        serialRadio.frame = NSRect(x: 8, y: 28, width: 80, height: 18)
        serialRadio.tag = 1
        serialRadio.state = (settings.portType == .serial) ? .on : .off
        accessoryView.addSubview(serialRadio)

        let serialPortLabel = NSTextField(labelWithString: L("dialog.connection.serialPort"))
        serialPortLabel.frame = NSRect(x: 68, y: 28, width: 45, height: 17)
        serialPortLabel.alignment = .right
        accessoryView.addSubview(serialPortLabel)

        let serialPortPopup = NSPopUpButton(frame: NSRect(x: 118, y: 25, width: 290, height: 24))
        let serialPorts = findSerialPorts()
        for port in serialPorts {
            serialPortPopup.addItem(withTitle: port)
        }
        if serialPorts.isEmpty {
            serialPortPopup.addItem(withTitle: L("dialog.serialPort.noPortsFound"))
        }
        if !settings.serialPort.isEmpty {
            serialPortPopup.selectItem(withTitle: settings.serialPort)
        }
        accessoryView.addSubview(serialPortPopup)

        helper.serialControls = [serialPortLabel, serialPortPopup]

        // Apply initial enable/disable state
        if settings.portType == .serial {
            for ctrl in helper.tcpControls { ctrl.isEnabled = false }
        } else {
            for ctrl in helper.serialControls { ctrl.isEnabled = false }
        }

        // If no serial ports available, disable Serial radio
        if serialPorts.isEmpty {
            serialRadio.isEnabled = false
            if settings.portType == .serial {
                tcpRadio.state = .on
                serialRadio.state = .off
                for ctrl in helper.tcpControls { ctrl.isEnabled = true }
                for ctrl in helper.serialControls { ctrl.isEnabled = false }
            }
        }

        alert.accessoryView = accessoryView
        alert.addButton(withTitle: L("dialog.connection.ok"))
        alert.addButton(withTitle: L("dialog.connection.cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            let wc = targetWC ?? newTerminalWindow()

            if wc.connectionManager.state != .disconnected {
                wc.disconnect()
            }

            if serialRadio.state == .on {
                if let port = serialPortPopup.selectedItem?.title, !port.starts(with: "(") {
                    settings.serialPort = port
                    settings.portType = .serial
                    wc.connectSerial(device: port)
                }
            } else {
                let host = hostCombo.stringValue
                let port = tcpPortField.integerValue

                let service: ServiceType
                if sshRadio.state == .on {
                    service = .ssh
                } else if otherRadio.state == .on {
                    service = .other
                } else {
                    service = .telnet
                }
                settings.serviceType = service
                settings.telnet = (service == .telnet)

                if let selectedSSH = SSHVersion.allCases.first(where: { $0.displayName == sshVerPopup.selectedItem?.title }) {
                    settings.sshVersion = selectedSSH
                }
                if let selectedPF = ProtocolFamily.allCases.first(where: { $0.displayName == ipVerPopup.selectedItem?.title }) {
                    settings.protocolFamily = selectedPF
                }

                if !host.isEmpty {
                    settings.hostname = host
                    settings.defaultPort = port
                    settings.portType = .tcpip
                    addToHostHistory(host)
                    wc.connectTCP(host: host, port: port, telnet: service == .telnet)
                }
            }
        }
    }

    private func addToHostHistory(_ host: String) {
        settings.hostHistory.removeAll { $0 == host }
        settings.hostHistory.insert(host, at: 0)
        // Keep max MAXHOSTLIST entries (matching original's limit)
        let maxHistory = 20
        if settings.hostHistory.count > maxHistory {
            settings.hostHistory = Array(settings.hostHistory.prefix(maxHistory))
        }
    }

    private func showTerminalSetupDialog() {
        let alert = NSAlert()
        alert.messageText = L("dialog.terminalSetup.title")
        alert.informativeText = L("dialog.terminalSetup.message")

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 180))

        // Terminal ID
        let idLabel = NSTextField(labelWithString: L("dialog.terminalSetup.terminalId"))
        idLabel.frame = NSRect(x: 0, y: 150, width: 100, height: 20)
        accessoryView.addSubview(idLabel)

        let idPopup = NSPopUpButton(frame: NSRect(x: 110, y: 148, width: 150, height: 24))
        for id in TerminalID.allCases {
            idPopup.addItem(withTitle: id.displayName)
        }
        idPopup.selectItem(withTitle: settings.terminalID.displayName)
        accessoryView.addSubview(idPopup)

        // Size
        let sizeLabel = NSTextField(labelWithString: L("dialog.terminalSetup.size"))
        sizeLabel.frame = NSRect(x: 0, y: 120, width: 100, height: 20)
        accessoryView.addSubview(sizeLabel)

        let colsField = NSTextField(frame: NSRect(x: 110, y: 118, width: 60, height: 24))
        colsField.integerValue = settings.terminalWidth
        accessoryView.addSubview(colsField)

        let xLabel = NSTextField(labelWithString: "x")
        xLabel.frame = NSRect(x: 175, y: 120, width: 15, height: 20)
        accessoryView.addSubview(xLabel)

        let rowsField = NSTextField(frame: NSRect(x: 195, y: 118, width: 60, height: 24))
        rowsField.integerValue = settings.terminalHeight
        accessoryView.addSubview(rowsField)

        // Encoding
        let encLabel = NSTextField(labelWithString: L("dialog.terminalSetup.encoding"))
        encLabel.frame = NSRect(x: 0, y: 88, width: 100, height: 20)
        accessoryView.addSubview(encLabel)

        let encPopup = NSPopUpButton(frame: NSRect(x: 110, y: 86, width: 200, height: 24))
        for enc in CharacterEncoding.allCases {
            encPopup.addItem(withTitle: enc.displayName)
        }
        encPopup.selectItem(withTitle: settings.encoding.displayName)
        accessoryView.addSubview(encPopup)

        // New Line
        let nlLabel = NSTextField(labelWithString: L("dialog.terminalSetup.newLine"))
        nlLabel.frame = NSRect(x: 0, y: 56, width: 100, height: 20)
        accessoryView.addSubview(nlLabel)

        let nlPopup = NSPopUpButton(frame: NSRect(x: 110, y: 54, width: 100, height: 24))
        nlPopup.addItem(withTitle: "CR")
        nlPopup.addItem(withTitle: "CR+LF")
        nlPopup.addItem(withTitle: "LF")
        accessoryView.addSubview(nlPopup)

        // Local echo
        let echoCheck = NSButton(checkboxWithTitle: L("dialog.terminalSetup.localEcho"), target: nil, action: nil)
        echoCheck.frame = NSRect(x: 110, y: 24, width: 140, height: 20)
        echoCheck.state = settings.localEcho ? .on : .off
        accessoryView.addSubview(echoCheck)

        // Auto wrap
        let wrapCheck = NSButton(checkboxWithTitle: L("dialog.terminalSetup.autoWrap"), target: nil, action: nil)
        wrapCheck.frame = NSRect(x: 250, y: 24, width: 120, height: 20)
        accessoryView.addSubview(wrapCheck)

        alert.accessoryView = accessoryView
        alert.addButton(withTitle: L("dialog.terminalSetup.ok"))
        alert.addButton(withTitle: L("dialog.terminalSetup.cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            if let selected = TerminalID.allCases.first(where: { $0.displayName == idPopup.selectedItem?.title }) {
                settings.terminalID = selected
            }
            settings.terminalWidth = colsField.integerValue
            settings.terminalHeight = rowsField.integerValue
            settings.localEcho = echoCheck.state == .on

            if let wc = activeWindowController {
                wc.terminalView.settings = settings
                wc.terminalView.updateFont()
            }
        }
    }

    private func showSerialPortDialog() {
        let alert = NSAlert()
        alert.messageText = L("dialog.serialPort.title")

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))

        // Port
        let portLabel = NSTextField(labelWithString: L("dialog.serialPort.port"))
        portLabel.frame = NSRect(x: 0, y: 110, width: 80, height: 20)
        accessoryView.addSubview(portLabel)

        let portPopup = NSPopUpButton(frame: NSRect(x: 85, y: 108, width: 200, height: 24))
        // Enumerate serial ports
        let serialPorts = findSerialPorts()
        for port in serialPorts {
            portPopup.addItem(withTitle: port)
        }
        if serialPorts.isEmpty {
            portPopup.addItem(withTitle: L("dialog.serialPort.noPortsFound"))
        }
        accessoryView.addSubview(portPopup)

        // Baud rate
        let baudLabel = NSTextField(labelWithString: L("dialog.serialPort.baudRate"))
        baudLabel.frame = NSRect(x: 0, y: 78, width: 80, height: 20)
        accessoryView.addSubview(baudLabel)

        let baudPopup = NSPopUpButton(frame: NSRect(x: 85, y: 76, width: 120, height: 24))
        for rate in [300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400] {
            baudPopup.addItem(withTitle: "\(rate)")
        }
        baudPopup.selectItem(withTitle: "\(settings.baudRate)")
        accessoryView.addSubview(baudPopup)

        // Data bits
        let dataLabel = NSTextField(labelWithString: L("dialog.serialPort.dataBits"))
        dataLabel.frame = NSRect(x: 0, y: 46, width: 80, height: 20)
        accessoryView.addSubview(dataLabel)

        let dataPopup = NSPopUpButton(frame: NSRect(x: 85, y: 44, width: 60, height: 24))
        for bits in [5, 6, 7, 8] {
            dataPopup.addItem(withTitle: "\(bits)")
        }
        dataPopup.selectItem(withTitle: "\(settings.dataBits)")
        accessoryView.addSubview(dataPopup)

        // Parity
        let parityLabel = NSTextField(labelWithString: L("dialog.serialPort.parity"))
        parityLabel.frame = NSRect(x: 160, y: 46, width: 50, height: 20)
        accessoryView.addSubview(parityLabel)

        let parityPopup = NSPopUpButton(frame: NSRect(x: 215, y: 44, width: 80, height: 24))
        parityPopup.addItem(withTitle: L("dialog.serialPort.parityNone"))
        parityPopup.addItem(withTitle: L("dialog.serialPort.parityOdd"))
        parityPopup.addItem(withTitle: L("dialog.serialPort.parityEven"))
        accessoryView.addSubview(parityPopup)

        // Flow control
        let flowLabel = NSTextField(labelWithString: L("dialog.serialPort.flow"))
        flowLabel.frame = NSRect(x: 0, y: 14, width: 80, height: 20)
        accessoryView.addSubview(flowLabel)

        let flowPopup = NSPopUpButton(frame: NSRect(x: 85, y: 12, width: 120, height: 24))
        flowPopup.addItem(withTitle: L("dialog.serialPort.flowNone"))
        flowPopup.addItem(withTitle: L("dialog.serialPort.flowXonXoff"))
        flowPopup.addItem(withTitle: L("dialog.serialPort.flowHardware"))
        accessoryView.addSubview(flowPopup)

        alert.accessoryView = accessoryView
        alert.addButton(withTitle: L("dialog.serialPort.connect"))
        alert.addButton(withTitle: L("dialog.serialPort.cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            if let port = portPopup.selectedItem?.title, !port.starts(with: "(") {
                settings.serialPort = port
                settings.baudRate = Int(baudPopup.selectedItem?.title ?? "9600") ?? 9600
                settings.dataBits = Int(dataPopup.selectedItem?.title ?? "8") ?? 8
                activeWindowController?.connectSerial(device: port)
            }
        }
    }

    private func findSerialPorts() -> [String] {
        var ports: [String] = []
        let devDir = "/dev"
        if let items = try? FileManager.default.contentsOfDirectory(atPath: devDir) {
            for item in items.sorted() {
                if item.hasPrefix("tty.") || item.hasPrefix("cu.") {
                    ports.append("\(devDir)/\(item)")
                }
            }
        }
        return ports
    }
}
#endif
