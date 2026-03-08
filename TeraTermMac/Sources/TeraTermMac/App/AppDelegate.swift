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
import UniformTypeIdentifiers

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

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    // Window controllers
    private var windowControllers: [TerminalWindowController] = []
    private var settings: TerminalSettings = TerminalSettings()

    /// 現在開いている設定シート（排他制御用）
    private weak var currentSetupSheet: NSWindow?

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

    /// Assign an SF Symbol image to an NSMenuItem (macOS 11+).
    private func setSymbol(_ name: String, for item: NSMenuItem) {
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = appMenu.addItem(withTitle: L("menu.app.about"), action: #selector(showAbout(_:)), keyEquivalent: "")
        setSymbol("info.circle", for: aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        let prefItem = appMenu.addItem(withTitle: L("menu.app.preferences"), action: #selector(showPreferences(_:)), keyEquivalent: ",")
        setSymbol("gearshape", for: prefItem)
        appMenu.addItem(NSMenuItem.separator())
        let hideItem = appMenu.addItem(withTitle: L("menu.app.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        setSymbol("eye.slash", for: hideItem)
        let hideOthers = NSMenuItem(title: L("menu.app.hideOthers"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        setSymbol("eye.slash.circle", for: hideOthers)
        appMenu.addItem(hideOthers)
        let showAllItem = appMenu.addItem(withTitle: L("menu.app.showAll"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        setSymbol("eye", for: showAllItem)
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = appMenu.addItem(withTitle: L("menu.app.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        setSymbol("power", for: quitItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: L("menu.file"))
        fileMenuItem.submenu = fileMenu

        let newConnItem = fileMenu.addItem(withTitle: L("menu.file.newConnection"), action: #selector(newConnection(_:)), keyEquivalent: "n")
        setSymbol("network", for: newConnItem)
        let newWinItem = fileMenu.addItem(withTitle: L("menu.file.newWindow"), action: #selector(newWindow(_:)), keyEquivalent: "t")
        setSymbol("macwindow.badge.plus", for: newWinItem)
        let dupItem = fileMenu.addItem(withTitle: L("menu.file.duplicateSession"), action: #selector(duplicateSession(_:)), keyEquivalent: "d")
        setSymbol("doc.on.doc", for: dupItem)
        fileMenu.addItem(NSMenuItem.separator())
        let logItem = fileMenu.addItem(withTitle: L("menu.file.log"), action: #selector(startLog(_:)), keyEquivalent: "")
        setSymbol("doc.text", for: logItem)
        let stopLogItem = fileMenu.addItem(withTitle: L("menu.file.stopLog"), action: #selector(stopLog(_:)), keyEquivalent: "")
        setSymbol("doc.text.fill", for: stopLogItem)
        fileMenu.addItem(NSMenuItem.separator())

        // File transfer submenu
        let transferMenu = NSMenu(title: L("menu.file.fileTransfer"))
        let transferMenuItem = NSMenuItem(title: L("menu.file.fileTransfer"), action: nil, keyEquivalent: "")
        setSymbol("arrow.left.arrow.right", for: transferMenuItem)
        transferMenuItem.submenu = transferMenu
        fileMenu.addItem(transferMenuItem)

        let xmSend = transferMenu.addItem(withTitle: L("menu.file.xmodemSend"), action: #selector(xmodemSend(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: xmSend)
        let xmRecv = transferMenu.addItem(withTitle: L("menu.file.xmodemReceive"), action: #selector(xmodemRecv(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: xmRecv)
        transferMenu.addItem(NSMenuItem.separator())
        let zmSend = transferMenu.addItem(withTitle: L("menu.file.zmodemSend"), action: #selector(zmodemSend(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: zmSend)
        let zmRecv = transferMenu.addItem(withTitle: L("menu.file.zmodemReceive"), action: #selector(zmodemRecv(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: zmRecv)
        transferMenu.addItem(NSMenuItem.separator())
        let kmSend = transferMenu.addItem(withTitle: L("menu.file.kermitSend"), action: #selector(kermitSend(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: kmSend)
        let kmRecv = transferMenu.addItem(withTitle: L("menu.file.kermitReceive"), action: #selector(kermitRecv(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: kmRecv)

        fileMenu.addItem(NSMenuItem.separator())
        let disconnItem = fileMenu.addItem(withTitle: L("menu.file.disconnect"), action: #selector(doDisconnect(_:)), keyEquivalent: "")
        setSymbol("xmark.circle", for: disconnItem)
        fileMenu.addItem(NSMenuItem.separator())
        let closeItem = fileMenu.addItem(withTitle: L("menu.file.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        setSymbol("xmark.square", for: closeItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L("menu.edit"))
        editMenuItem.submenu = editMenu

        let copyItem = editMenu.addItem(withTitle: L("menu.edit.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        setSymbol("doc.on.doc", for: copyItem)
        let copyTableItem = editMenu.addItem(withTitle: L("menu.edit.copyAsTable"), action: #selector(copyAsTable(_:)), keyEquivalent: "")
        setSymbol("tablecells", for: copyTableItem)
        let pasteItem = editMenu.addItem(withTitle: L("menu.edit.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        setSymbol("doc.on.clipboard", for: pasteItem)
        let pasteSpecialItem = editMenu.addItem(withTitle: L("menu.edit.pasteSpecial"), action: #selector(pasteSpecial(_:)), keyEquivalent: "")
        setSymbol("doc.on.clipboard.fill", for: pasteSpecialItem)
        editMenu.addItem(NSMenuItem.separator())
        let clsItem = editMenu.addItem(withTitle: L("menu.edit.clearScreen"), action: #selector(clearScreen(_:)), keyEquivalent: "")
        setSymbol("rectangle.slash", for: clsItem)
        let clbItem = editMenu.addItem(withTitle: L("menu.edit.clearBuffer"), action: #selector(clearBuffer(_:)), keyEquivalent: "")
        setSymbol("trash", for: clbItem)
        editMenu.addItem(NSMenuItem.separator())
        let selAllItem = editMenu.addItem(withTitle: L("menu.edit.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        setSymbol("selection.pin.in.out", for: selAllItem)

        // Setup menu
        let setupMenuItem = NSMenuItem()
        mainMenu.addItem(setupMenuItem)
        let setupMenu = NSMenu(title: L("menu.setup"))
        setupMenuItem.submenu = setupMenu

        let termItem = setupMenu.addItem(withTitle: L("menu.setup.terminal"), action: #selector(setupTerminal(_:)), keyEquivalent: "")
        setSymbol("terminal", for: termItem)
        let winItem = setupMenu.addItem(withTitle: L("menu.setup.window"), action: #selector(setupWindow(_:)), keyEquivalent: "")
        setSymbol("macwindow", for: winItem)
        let fontItem = setupMenu.addItem(withTitle: L("menu.setup.font"), action: #selector(setupFont(_:)), keyEquivalent: "")
        setSymbol("textformat.size", for: fontItem)
        let kbItem = setupMenu.addItem(withTitle: L("menu.setup.keyboard"), action: #selector(setupKeyboard(_:)), keyEquivalent: "")
        setSymbol("keyboard", for: kbItem)
        let serialItem = setupMenu.addItem(withTitle: L("menu.setup.serialPort"), action: #selector(setupSerialPort(_:)), keyEquivalent: "")
        setSymbol("cable.connector", for: serialItem)
        setupMenu.addItem(NSMenuItem.separator())
        let saveItem = setupMenu.addItem(withTitle: L("menu.setup.saveSetup"), action: #selector(saveSetup(_:)), keyEquivalent: "")
        setSymbol("square.and.arrow.down", for: saveItem)
        let restoreItem = setupMenu.addItem(withTitle: L("menu.setup.restoreSetup"), action: #selector(restoreSetup(_:)), keyEquivalent: "")
        setSymbol("square.and.arrow.up", for: restoreItem)

        // Code menu (encoding selection)
        let codeMenuItem = NSMenuItem()
        mainMenu.addItem(codeMenuItem)
        let codeMenu = NSMenu(title: L("menu.code"))
        codeMenuItem.submenu = codeMenu
        buildCodeMenu(codeMenu)

        // Control menu
        let controlMenuItem = NSMenuItem()
        mainMenu.addItem(controlMenuItem)
        let controlMenu = NSMenu(title: L("menu.control"))
        controlMenuItem.submenu = controlMenu

        let resetItem = controlMenu.addItem(withTitle: L("menu.control.resetTerminal"), action: #selector(resetTerminal(_:)), keyEquivalent: "")
        setSymbol("arrow.counterclockwise", for: resetItem)
        let aytItem = controlMenu.addItem(withTitle: L("menu.control.areYouThere"), action: #selector(areYouThere(_:)), keyEquivalent: "")
        setSymbol("questionmark.circle", for: aytItem)
        let breakItem = controlMenu.addItem(withTitle: L("menu.control.sendBreak"), action: #selector(sendBreak(_:)), keyEquivalent: "")
        setSymbol("exclamationmark.triangle", for: breakItem)
        let portResetItem = controlMenu.addItem(withTitle: L("menu.control.resetPort"), action: #selector(resetPort(_:)), keyEquivalent: "")
        setSymbol("arrow.triangle.2.circlepath", for: portResetItem)

        controlMenu.addItem(NSMenuItem.separator())

        let macroItem = controlMenu.addItem(withTitle: L("menu.control.macro"), action: #selector(runMacro(_:)), keyEquivalent: "m")
        macroItem.keyEquivalentModifierMask = [.command, .shift]
        setSymbol("applescript", for: macroItem)
        let replayItem = controlMenu.addItem(withTitle: L("menu.control.replayLog"), action: #selector(replayLog(_:)), keyEquivalent: "")
        setSymbol("play.rectangle", for: replayItem)

        controlMenu.addItem(NSMenuItem.separator())

        let broadcastItem = controlMenu.addItem(withTitle: L("menu.control.broadcast"), action: #selector(toggleBroadcast(_:)), keyEquivalent: "")
        setSymbol("antenna.radiowaves.left.and.right", for: broadcastItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: L("menu.window"))
        windowMenuItem.submenu = windowMenu

        let minItem = windowMenu.addItem(withTitle: L("menu.window.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        setSymbol("minus.square", for: minItem)
        let zoomItem = windowMenu.addItem(withTitle: L("menu.window.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        setSymbol("arrow.up.left.and.arrow.down.right", for: zoomItem)
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: L("menu.help"))
        helpMenuItem.submenu = helpMenu

        let helpItem = helpMenu.addItem(withTitle: L("menu.help.help"), action: #selector(showHelp(_:)), keyEquivalent: "?")
        setSymbol("questionmark.circle", for: helpItem)
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

    @objc func copyAsTable(_ sender: Any?) {
        activeWindowController?.copyAsTable()
    }

    @objc func pasteSpecial(_ sender: Any?) {
        guard let wc = activeWindowController, let win = wc.window else { return }

        let alert = NSAlert()
        alert.messageText = L("dialog.pasteSpecial.title")
        alert.informativeText = L("dialog.pasteSpecial.message")

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        accessoryView.addSubview(scrollView)

        // Pre-fill from clipboard
        if let clipText = NSPasteboard.general.string(forType: .string) {
            textView.string = clipText
        }

        alert.accessoryView = accessoryView
        alert.addButton(withTitle: L("dialog.pasteSpecial.send"))
        alert.addButton(withTitle: L("Cancel"))

        alert.beginSheetModal(for: win) { response in
            guard response == .alertFirstButtonReturn else { return }
            let text = textView.string
            guard !text.isEmpty else { return }
            wc.connectionManager.send(Data(text.utf8))
        }
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
        showWindowSetupDialog()
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
        showKeyboardSetupDialog()
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

    @objc func resetPort(_ sender: Any?) {
        activeWindowController?.resetPort()
    }

    @objc func runMacro(_ sender: Any?) {
        guard let wc = activeWindowController else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.title = L("dialog.macro.title")
        panel.message = L("dialog.macro.message")
        panel.beginSheetModal(for: wc.window!) { response in
            guard response == .OK, let url = panel.url else { return }
            wc.runMacro(at: url)
        }
    }

    @objc func replayLog(_ sender: Any?) {
        guard let wc = activeWindowController else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .log]
        panel.title = L("dialog.replayLog.title")
        panel.beginSheetModal(for: wc.window!) { response in
            guard response == .OK, let url = panel.url else { return }
            wc.replayLog(at: url)
        }
    }

    // MARK: - Command Broadcast

    private var broadcastPanel: NSPanel?
    private var broadcastTextField: NSTextField?

    @objc func toggleBroadcast(_ sender: Any?) {
        if let panel = broadcastPanel, panel.isVisible {
            panel.close()
            broadcastPanel = nil
            return
        }
        showBroadcastPanel()
    }

    private func showBroadcastPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 90),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.title = L("menu.control.broadcast")
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 90))

        let label = NSTextField(labelWithString: L("dialog.broadcast.label"))
        label.frame = NSRect(x: 16, y: 58, width: 390, height: 17)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        contentView.addSubview(label)

        let textField = NSTextField(frame: NSRect(x: 16, y: 10, width: 310, height: 24))
        textField.placeholderString = L("dialog.broadcast.placeholder")
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.target = self
        textField.action = #selector(broadcastFieldAction(_:))
        contentView.addSubview(textField)
        broadcastTextField = textField

        let sendButton = NSButton(title: L("dialog.broadcast.send"), target: self, action: #selector(broadcastSendAction(_:)))
        sendButton.frame = NSRect(x: 334, y: 8, width: 72, height: 28)
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        contentView.addSubview(sendButton)

        panel.contentView = contentView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        broadcastPanel = panel
    }

    @objc private func broadcastFieldAction(_ sender: NSTextField) {
        broadcastCommand(sender.stringValue)
        sender.stringValue = ""
    }

    @objc private func broadcastSendAction(_ sender: Any?) {
        guard let text = broadcastTextField?.stringValue else { return }
        broadcastCommand(text)
        broadcastTextField?.stringValue = ""
    }

    private func broadcastCommand(_ command: String) {
        guard !command.isEmpty else { return }
        let data = Data((command + "\r").utf8)
        for wc in windowControllers where wc.connectionManager.state == .connected {
            wc.connectionManager.send(data)
        }
    }

    @objc func showHelp(_ sender: Any?) {
        if let url = URL(string: "https://teratermproject.github.io/") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Code Menu (Encoding)

    /// Tag encoding: direction in upper bits, CharacterEncoding rawValue in lower bits.
    /// direction: 0 = both, 1 = receive only, 2 = send only
    private static let encodingTagShift = 8

    private func buildCodeMenu(_ menu: NSMenu) {
        // "Send & Receive" submenu (changes both)
        let bothItem = NSMenuItem(title: L("menu.code.both"), action: nil, keyEquivalent: "")
        setSymbol("arrow.left.arrow.right", for: bothItem)
        bothItem.submenu = makeEncodingSubmenu(direction: 0)
        menu.addItem(bothItem)

        // "Receive" submenu
        let recvItem = NSMenuItem(title: L("menu.code.receive"), action: nil, keyEquivalent: "")
        setSymbol("arrow.down.circle", for: recvItem)
        recvItem.submenu = makeEncodingSubmenu(direction: 1)
        menu.addItem(recvItem)

        // "Send" submenu
        let sendItem = NSMenuItem(title: L("menu.code.send"), action: nil, keyEquivalent: "")
        setSymbol("arrow.up.circle", for: sendItem)
        sendItem.submenu = makeEncodingSubmenu(direction: 2)
        menu.addItem(sendItem)
    }

    private func makeEncodingSubmenu(direction: Int) -> NSMenu {
        let menu = NSMenu()

        let groupOrder: [CharacterEncoding.Group] = [
            .unicode, .japanese, .chinese, .korean, .western, .dosWindows
        ]
        let groupNames: [CharacterEncoding.Group: String] = [
            .unicode:    L("menu.code.group.unicode"),
            .japanese:   L("menu.code.group.japanese"),
            .chinese:    L("menu.code.group.chinese"),
            .korean:     L("menu.code.group.korean"),
            .western:    L("menu.code.group.western"),
            .dosWindows: L("menu.code.group.dosWindows"),
        ]

        for (index, group) in groupOrder.enumerated() {
            if index > 0 { menu.addItem(NSMenuItem.separator()) }

            let headerItem = NSMenuItem(title: groupNames[group] ?? "", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)

            for enc in CharacterEncoding.encodings(in: group) {
                let item = NSMenuItem(
                    title: enc.displayName,
                    action: #selector(changeEncoding(_:)),
                    keyEquivalent: "")
                item.tag = (direction << AppDelegate.encodingTagShift) | enc.rawValue
                menu.addItem(item)
            }
        }

        return menu
    }

    @objc func changeEncoding(_ sender: NSMenuItem) {
        let direction = sender.tag >> AppDelegate.encodingTagShift
        let rawValue = sender.tag & ((1 << AppDelegate.encodingTagShift) - 1)
        guard let encoding = CharacterEncoding(rawValue: rawValue) else { return }

        switch direction {
        case 0: // both
            settings.encoding = encoding
            settings.sendEncoding = encoding
        case 1: // receive
            settings.encoding = encoding
        case 2: // send
            settings.sendEncoding = encoding
        default:
            break
        }

        // Apply to active window
        activeWindowController?.terminalView.settings = settings
    }

    // MARK: - Menu Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let connected = activeWindowController?.connectionManager.state == .connected
        let hasWindow = activeWindowController != nil

        switch menuItem.action {
        case #selector(areYouThere(_:)),
             #selector(sendBreak(_:)),
             #selector(resetPort(_:)):
            return connected
        case #selector(resetTerminal(_:)):
            return hasWindow
        case #selector(runMacro(_:)),
             #selector(replayLog(_:)):
            return hasWindow
        case #selector(toggleBroadcast(_:)):
            // Update checkmark state
            menuItem.state = (broadcastPanel?.isVisible == true) ? .on : .off
            return true
        case #selector(changeEncoding(_:)):
            // Checkmark the currently active encoding
            let direction = menuItem.tag >> AppDelegate.encodingTagShift
            let rawValue = menuItem.tag & ((1 << AppDelegate.encodingTagShift) - 1)
            guard let encoding = CharacterEncoding(rawValue: rawValue) else { return false }
            switch direction {
            case 0:
                menuItem.state = (settings.encoding == encoding && settings.sendEncoding == encoding) ? .on : .off
            case 1:
                menuItem.state = (settings.encoding == encoding) ? .on : .off
            case 2:
                menuItem.state = (settings.sendEncoding == encoding) ? .on : .off
            default:
                break
            }
            return true
        default:
            return true
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

    /// 現在開いている設定シートをOK（値保存）で閉じる
    private func dismissCurrentSetupSheet() {
        guard let sheet = currentSetupSheet, let parent = sheet.sheetParent else { return }
        // OKとして閉じることで applySettings + okHandler が呼ばれる
        parent.endSheet(sheet, returnCode: .OK)
        currentSetupSheet = nil
    }

    private func showTerminalSetupDialog() {
        dismissCurrentSetupSheet()
        let vc = TerminalSetupViewController(settings: settings)
        vc.okHandler = { [weak self] in
            guard let self = self else { return }
            if let wc = self.activeWindowController {
                wc.terminalView.settings = self.settings
                wc.terminalView.updateFont()
                // termIsWin が有効なら端末サイズに合わせてウィンドウをリサイズ
                if self.settings.termIsWin {
                    let size = wc.terminalView.preferredSize(
                        columns: self.settings.terminalWidth,
                        rows: self.settings.terminalHeight
                    )
                    wc.window?.setContentSize(size)
                }
            }
        }
        if let win = activeWindowController?.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: Window Setup Dialog (port of ttpdlg Window dialog)

    private func showWindowSetupDialog() {
        dismissCurrentSetupSheet()
        let vc = WindowSetupViewController(settings: settings)
        vc.okHandler = { [weak self] in
            guard let self = self else { return }
            if let wc = self.activeWindowController {
                wc.terminalView.settings = self.settings
                wc.terminalView.needsDisplay = true
                wc.window?.title = self.settings.title
                wc.window?.alphaValue = CGFloat(self.settings.windowAlpha)
            }
        }
        if let win = activeWindowController?.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: Keyboard Setup Dialog (port of ttpdlg Keyboard dialog)

    private func showKeyboardSetupDialog() {
        dismissCurrentSetupSheet()
        let alert = NSAlert()
        alert.messageText = L("dialog.keyboardSetup.title")
        alert.informativeText = ""

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 130))

        // ── Backspace Key ──
        let bsLabel = NSTextField(labelWithString: L("dialog.keyboardSetup.bsKey"))
        bsLabel.frame = NSRect(x: 0, y: 102, width: 120, height: 20)
        accessoryView.addSubview(bsLabel)

        let bsPopup = NSPopUpButton(frame: NSRect(x: 130, y: 100, width: 140, height: 24))
        bsPopup.addItem(withTitle: "BS (0x08)")
        bsPopup.addItem(withTitle: "DEL (0x7F)")
        bsPopup.selectItem(at: settings.bsKey == 8 ? 0 : 1)
        accessoryView.addSubview(bsPopup)

        // ── Delete Key ──
        let delLabel = NSTextField(labelWithString: L("dialog.keyboardSetup.deleteKey"))
        delLabel.frame = NSRect(x: 0, y: 68, width: 120, height: 20)
        accessoryView.addSubview(delLabel)

        let delPopup = NSPopUpButton(frame: NSRect(x: 130, y: 66, width: 140, height: 24))
        delPopup.addItem(withTitle: "DEL (0x7F)")
        delPopup.addItem(withTitle: "BS (0x08)")
        delPopup.addItem(withTitle: L("dialog.keyboardSetup.deleteEscSeq"))
        delPopup.selectItem(at: settings.deleteKey == 127 ? 0 : (settings.deleteKey == 8 ? 1 : 2))
        accessoryView.addSubview(delPopup)

        // ── Meta Key ──
        let metaLabel = NSTextField(labelWithString: L("dialog.keyboardSetup.metaKey"))
        metaLabel.frame = NSRect(x: 0, y: 34, width: 120, height: 20)
        accessoryView.addSubview(metaLabel)

        let metaPopup = NSPopUpButton(frame: NSRect(x: 130, y: 32, width: 140, height: 24))
        metaPopup.addItem(withTitle: L("dialog.keyboardSetup.metaOff"))
        metaPopup.addItem(withTitle: L("dialog.keyboardSetup.metaOn"))
        metaPopup.selectItem(at: settings.metaKey)
        accessoryView.addSubview(metaPopup)

        // ── Answerback ──
        let ansLabel = NSTextField(labelWithString: L("dialog.keyboardSetup.answerback"))
        ansLabel.frame = NSRect(x: 0, y: 2, width: 120, height: 20)
        accessoryView.addSubview(ansLabel)

        let ansField = NSTextField(frame: NSRect(x: 130, y: 0, width: 200, height: 24))
        ansField.stringValue = settings.answerback
        ansField.placeholderString = L("dialog.keyboardSetup.answerbackPlaceholder")
        accessoryView.addSubview(ansField)

        alert.accessoryView = accessoryView
        alert.addButton(withTitle: L("dialog.keyboardSetup.ok"))
        alert.addButton(withTitle: L("dialog.keyboardSetup.cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            settings.bsKey = bsPopup.indexOfSelectedItem == 0 ? 8 : 127
            switch delPopup.indexOfSelectedItem {
            case 0: settings.deleteKey = 127
            case 1: settings.deleteKey = 8
            default: settings.deleteKey = 0  // escape sequence
            }
            settings.metaKey = metaPopup.indexOfSelectedItem
            settings.answerback = ansField.stringValue

            if let wc = activeWindowController {
                wc.terminalView.settings = settings
            }
        }
    }

    private func showSerialPortDialog() {
        dismissCurrentSetupSheet()
        let vc = SerialPortSetupViewController(settings: settings)
        vc.okHandler = { [weak self] in
            guard let self = self else { return }
            if let port = self.settings.serialPort.isEmpty ? nil : self.settings.serialPort {
                self.activeWindowController?.connectSerial(device: port)
            }
        }
        if let win = activeWindowController?.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    private func findSerialPorts() -> [String] {
        return SerialPortSetupViewController.findSerialPorts()
    }
}
#endif
