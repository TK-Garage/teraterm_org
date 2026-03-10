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
        // Snapshot generation mode (invoked by build script)
        if CommandLine.arguments.contains("--generate-snapshots") {
            SnapshotGenerator.generateAll()
            NSApplication.shared.terminate(nil)
            return
        }

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

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
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
        let sendFileItem = fileMenu.addItem(withTitle: L("menu.file.sendFile"), action: #selector(showSendFileDialog(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: sendFileItem)
        let recvFileItem = fileMenu.addItem(withTitle: L("menu.file.receiveFile"), action: #selector(showRecvFileDialog(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: recvFileItem)
        fileMenu.addItem(NSMenuItem.separator())
        let logItem = fileMenu.addItem(withTitle: L("menu.file.log"), action: #selector(showLogDialog(_:)), keyEquivalent: "")
        setSymbol("doc.text", for: logItem)
        let pauseLogItem = fileMenu.addItem(withTitle: L("menu.file.pauseLog"), action: #selector(pauseLog(_:)), keyEquivalent: "")
        setSymbol("pause.circle", for: pauseLogItem)
        let commentLogItem = fileMenu.addItem(withTitle: L("menu.file.commentToLog"), action: #selector(commentToLog(_:)), keyEquivalent: "")
        setSymbol("text.bubble", for: commentLogItem)
        let viewLogItem = fileMenu.addItem(withTitle: L("menu.file.viewLog"), action: #selector(viewLog(_:)), keyEquivalent: "")
        setSymbol("eye.circle", for: viewLogItem)
        let showLogDlgItem = fileMenu.addItem(withTitle: L("menu.file.showLogDialog"), action: #selector(showLogProgressDialog(_:)), keyEquivalent: "")
        setSymbol("chart.bar.doc.horizontal", for: showLogDlgItem)
        let stopLogItem = fileMenu.addItem(withTitle: L("menu.file.stopLog"), action: #selector(stopLog(_:)), keyEquivalent: "")
        setSymbol("doc.text.fill", for: stopLogItem)
        fileMenu.addItem(NSMenuItem.separator())
        let changeDirItem = fileMenu.addItem(withTitle: L("menu.file.changeDir"), action: #selector(showChangeDir(_:)), keyEquivalent: "")
        setSymbol("folder", for: changeDirItem)
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
        let scpItem = fileMenu.addItem(withTitle: L("menu.file.sshSCP"), action: #selector(showSCPDialog(_:)), keyEquivalent: "")
        setSymbol("lock.doc", for: scpItem)
        fileMenu.addItem(NSMenuItem.separator())
        let printItem = fileMenu.addItem(withTitle: L("menu.file.print"), action: #selector(printTerminal(_:)), keyEquivalent: "p")
        setSymbol("printer", for: printItem)
        fileMenu.addItem(NSMenuItem.separator())
        let disconnItem = fileMenu.addItem(withTitle: L("menu.file.disconnect"), action: #selector(doDisconnect(_:)), keyEquivalent: "")
        setSymbol("xmark.circle", for: disconnItem)
        fileMenu.addItem(NSMenuItem.separator())
        let quitAllItem = fileMenu.addItem(withTitle: L("menu.file.quitAll"), action: #selector(quitAllTeraTerm(_:)), keyEquivalent: "")
        setSymbol("xmark.square.fill", for: quitAllItem)
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
        editMenu.addItem(NSMenuItem.separator())
        let editHistoryItem = editMenu.addItem(withTitle: L("menu.edit.editHistory"), action: #selector(showEditHistory(_:)), keyEquivalent: "")
        setSymbol("clock.arrow.circlepath", for: editHistoryItem)

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
        let tcpipItem = setupMenu.addItem(withTitle: L("menu.setup.tcpip"), action: #selector(setupTCPIP(_:)), keyEquivalent: "")
        setSymbol("network", for: tcpipItem)
        setupMenu.addItem(NSMenuItem.separator())
        let proxyItem = setupMenu.addItem(withTitle: L("menu.setup.proxy"), action: #selector(setupProxy(_:)), keyEquivalent: "")
        setSymbol("globe", for: proxyItem)
        let sshSetupItem = setupMenu.addItem(withTitle: L("menu.setup.ssh"), action: #selector(setupSSH(_:)), keyEquivalent: "")
        setSymbol("lock.shield", for: sshSetupItem)
        let sshAuthSetupItem = setupMenu.addItem(withTitle: L("menu.setup.sshAuth"), action: #selector(setupSSHAuth(_:)), keyEquivalent: "")
        setSymbol("person.badge.key", for: sshAuthSetupItem)
        let sshFwdItem = setupMenu.addItem(withTitle: L("menu.setup.sshForward"), action: #selector(setupSSHForwarding(_:)), keyEquivalent: "")
        setSymbol("arrow.triangle.branch", for: sshFwdItem)
        let sshKeyGenItem = setupMenu.addItem(withTitle: L("menu.setup.sshKeyGen"), action: #selector(setupSSHKeyGen(_:)), keyEquivalent: "")
        setSymbol("key", for: sshKeyGenItem)
        setupMenu.addItem(NSMenuItem.separator())
        let generalItem = setupMenu.addItem(withTitle: L("menu.setup.general"), action: #selector(setupGeneral(_:)), keyEquivalent: "")
        setSymbol("gearshape", for: generalItem)
        setupMenu.addItem(NSMenuItem.separator())
        let additionalItem = setupMenu.addItem(withTitle: L("menu.setup.additionalSettings"), action: #selector(setupAdditional(_:)), keyEquivalent: "")
        setSymbol("slider.horizontal.3", for: additionalItem)
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
        let stopMacroItem = controlMenu.addItem(withTitle: L("menu.control.stopMacro"), action: #selector(stopMacro(_:)), keyEquivalent: "")
        setSymbol("stop.circle", for: stopMacroItem)
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
        windowMenu.addItem(NSMenuItem.separator())
        let winListItem = windowMenu.addItem(withTitle: L("menu.window.windowList"), action: #selector(showWindowList(_:)), keyEquivalent: "")
        setSymbol("list.bullet.rectangle", for: winListItem)
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

    @objc func showSendFileDialog(_ sender: Any?) {
        guard let wc = activeWindowController, let win = wc.window else { return }
        FileTransferDialogHelper.presentSendFileDialog(on: win) { result in
            // result handled by window controller
        }
    }

    @objc func showRecvFileDialog(_ sender: Any?) {
        guard let wc = activeWindowController, let win = wc.window else { return }
        FileTransferDialogHelper.presentRecvFileDialog(on: win) { result in
            // result handled by window controller
        }
    }

    @objc func showLogDialog(_ sender: Any?) {
        guard let wc = activeWindowController, let win = wc.window else { return }
        let vc = LogDialogController()
        vc.okHandler = { [weak wc, weak vc] in
            guard let result = vc?.result else { return }
            // Apply log settings to window controller
            _ = result
            wc?.startLog()
        }
        currentSetupSheet = vc.presentAsSheet(on: win)
    }

    @objc func stopLog(_ sender: Any?) {
        activeWindowController?.stopLog()
    }

    // MARK: - Log Pause / Resume (port of vtwin.cpp OnFilePause)

    @objc func pauseLog(_ sender: Any?) {
        guard let wc = activeWindowController else { return }
        let logger = wc.logger!
        if logger.state == .paused {
            logger.resumeLogging()
        } else if logger.state == .active {
            logger.pauseLogging()
        }
        logProgressPanel?.updateState(logger)
    }

    // MARK: - Comment to Log (port of vtwin.cpp OnCommentToLog / IDD_COMMENT_DIALOG)

    @objc func commentToLog(_ sender: Any?) {
        guard let wc = activeWindowController, let win = wc.window else { return }
        let logger = wc.logger!
        guard logger.state == .active || logger.state == .paused else { return }

        let alert = NSAlert()
        alert.messageText = L("dialog.logComment.title")
        alert.informativeText = L("dialog.logComment.message")
        alert.addButton(withTitle: L("dialog.logComment.ok"))
        alert.addButton(withTitle: L("dialog.logComment.cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = L("dialog.logComment.placeholder")
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        alert.beginSheetModal(for: win) { response in
            guard response == .alertFirstButtonReturn else { return }
            let comment = textField.stringValue
            guard !comment.isEmpty else { return }
            logger.logComment(comment)
        }
    }

    // MARK: - View Log (port of vtwin.cpp OnViewLog)

    @objc func viewLog(_ sender: Any?) {
        guard let wc = activeWindowController else { return }
        let logger = wc.logger!
        guard let path = logger.logFilePath else { return }

        let url = URL(fileURLWithPath: path)
        // Open the log file with the default editor (matching original Tera Term behavior
        // which uses the configured log viewer or system default)
        NSWorkspace.shared.open(url)
    }

    // MARK: - Show Log Progress Dialog (port of IDD_FOPT_LOGDLG)

    private var logProgressPanel: LogProgressPanel?

    @objc func showLogProgressDialog(_ sender: Any?) {
        guard let wc = activeWindowController else { return }
        let logger = wc.logger!
        guard logger.state != .inactive else { return }

        if let panel = logProgressPanel, panel.isVisible {
            panel.orderFront(nil)
            return
        }

        let panel = LogProgressPanel(logger: logger)
        panel.onPause = { [weak self] in
            self?.pauseLog(nil)
        }
        panel.onComment = { [weak self] in
            self?.commentToLog(nil)
        }
        panel.onClose = { [weak self] in
            self?.activeWindowController?.stopLog()
            self?.logProgressPanel?.close()
            self?.logProgressPanel = nil
        }
        logProgressPanel = panel
        panel.orderFront(nil)
    }

    // MARK: - Quit All Tera Term (port of vtwin.cpp OnAllClose)

    @objc func quitAllTeraTerm(_ sender: Any?) {
        let count = windowControllers.count
        if count == 0 { return }

        // Confirm before closing all windows
        let alert = NSAlert()
        alert.messageText = L("dialog.quitAll.title")
        alert.informativeText = String(format: L("dialog.quitAll.message"), count)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("dialog.quitAll.quit"))
        alert.addButton(withTitle: L("dialog.quitAll.cancel"))

        if alert.runModal() == .alertSecondButtonReturn { return }

        // Close all windows (this triggers disconnect via windowWillClose)
        let controllers = windowControllers
        for wc in controllers {
            wc.disconnect()
            wc.window?.close()
        }
    }

    @objc func showChangeDir(_ sender: Any?) {
        guard let wc = activeWindowController, let win = wc.window else { return }
        let currentDir = FileManager.default.currentDirectoryPath
        ChangeDirectoryDialog.show(currentDir: currentDir, on: win) { newDir in
            guard let dir = newDir else { return }
            FileManager.default.changeCurrentDirectoryPath(dir)
            // Send cd command if connected
            if wc.connectionManager.state == .connected {
                wc.connectionManager.send(Data("cd \(dir)\r".utf8))
            }
        }
    }

    @objc func showEditHistory(_ sender: Any?) {
        guard let win = activeWindowController?.window else { return }
        dismissCurrentSetupSheet()
        let vc = EditHistoryDialogController(history: settings.hostHistory)
        vc.okHandler = { [weak self, weak vc] in
            guard let self = self, let vc = vc else { return }
            self.settings.hostHistory = vc.resultHistory
        }
        currentSetupSheet = vc.presentAsSheet(on: win)
    }

    @objc func showWindowList(_ sender: Any?) {
        guard let win = activeWindowController?.window else { return }
        WindowListDialog.show(on: win) { _ in }
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

    @objc func setupTCPIP(_ sender: Any?) {
        showTCPIPDialog()
    }

    @objc func setupAdditional(_ sender: Any?) {
        showAdditionalSettingsDialog()
    }

    @objc func setupFont(_ sender: Any?) {
        guard activeWindowController != nil else { return }
        dismissCurrentSetupSheet()
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
        activeWindowController?.applySettings()
    }

    @objc func setupKeyboard(_ sender: Any?) {
        showKeyboardSetupDialog()
    }

    @objc func setupSerialPort(_ sender: Any?) {
        showSerialPortDialog()
    }

    @objc func setupProxy(_ sender: Any?) {
        showProxySetupDialog()
    }

    @objc func setupSSH(_ sender: Any?) {
        showSSHSetupDialog()
    }

    @objc func setupSSHAuth(_ sender: Any?) {
        showSSHAuthSetupDialog()
    }

    @objc func setupSSHForwarding(_ sender: Any?) {
        showSSHForwardingSetupDialog()
    }

    @objc func setupSSHKeyGen(_ sender: Any?) {
        showSSHKeyGenDialog()
    }

    @objc func setupGeneral(_ sender: Any?) {
        showGeneralSetupDialog()
    }

    @objc func showSCPDialog(_ sender: Any?) {
        showSSHSCPDialog()
    }

    @objc func printTerminal(_ sender: Any?) {
        guard let wc = activeWindowController, let win = wc.window else { return }
        TerminalPrintHelper.printTerminalContent(from: wc, window: win)
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
            // When loading a new settings object, update the window controller's reference
            if let self = self, let wc = self.activeWindowController {
                wc.settings = self.settings
                wc.applySettings()
            }
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
        // .ttl ファイルを選択可能にするためカスタムUTTypeを追加
        let ttlType = UTType(filenameExtension: "ttl") ?? .plainText
        panel.allowedContentTypes = [ttlType, .plainText]
        panel.title = L("dialog.macro.title")
        panel.message = L("dialog.macro.message")
        panel.beginSheetModal(for: wc.window!) { response in
            guard response == .OK, let url = panel.url else { return }
            wc.runMacro(at: url)
        }
    }

    @objc func stopMacro(_ sender: Any?) {
        activeWindowController?.stopMacro()
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

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: L("dialog.broadcast.label"))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = L("dialog.broadcast.placeholder")
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.target = self
        textField.action = #selector(broadcastFieldAction(_:))
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        broadcastTextField = textField

        let sendButton = NSButton(title: L("dialog.broadcast.send"), target: self, action: #selector(broadcastSendAction(_:)))
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        sendButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Horizontal row: [textField] - 8 - [sendButton]
        let inputRow = NSStackView(views: [textField, sendButton])
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        inputRow.orientation = .horizontal
        inputRow.spacing = DialogLayout.buttonSpacing
        inputRow.alignment = .firstBaseline

        // Vertical stack: [label] - 8 - [inputRow]
        let vStack = NSStackView(views: [label, inputRow])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = DialogLayout.rowSpacing

        contentView.addSubview(vStack)

        let m = DialogLayout.margin
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: m),
            vStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: m),
            vStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -m),
            vStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -m),
            inputRow.widthAnchor.constraint(equalTo: vStack.widthAnchor),
        ])

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
        activeWindowController?.applySettings()
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
        case #selector(stopMacro(_:)):
            return activeWindowController?.macroInterpreter != nil

        // Log menu items: enabled only when logging is active
        case #selector(pauseLog(_:)):
            let logState = activeWindowController?.logger.state ?? .inactive
            if logState == .paused {
                menuItem.title = L("menu.file.resumeLog")
            } else {
                menuItem.title = L("menu.file.pauseLog")
            }
            return logState == .active || logState == .paused
        case #selector(commentToLog(_:)):
            let logState = activeWindowController?.logger.state ?? .inactive
            return logState == .active || logState == .paused
        case #selector(viewLog(_:)):
            return activeWindowController?.logger.logFilePath != nil
        case #selector(showLogProgressDialog(_:)):
            let logState = activeWindowController?.logger.state ?? .inactive
            return logState != .inactive
        case #selector(stopLog(_:)):
            let logState = activeWindowController?.logger.state ?? .inactive
            return logState != .inactive

        case #selector(quitAllTeraTerm(_:)):
            return !windowControllers.isEmpty

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

        let accessoryView = NSView()
        accessoryView.translatesAutoresizingMaskIntoConstraints = false

        // ── TCP/IP Group Box ──
        let tcpBox = NSBox()
        tcpBox.translatesAutoresizingMaskIntoConstraints = false
        tcpBox.titlePosition = .noTitle
        accessoryView.addSubview(tcpBox)

        let tcpContent = NSView()
        tcpContent.translatesAutoresizingMaskIntoConstraints = false

        // Row 1: [TCP/IP radio] [Host:] [combobox]
        let tcpRadio = NSView.makeRadioButton(L("dialog.connection.tcpip"), tag: 0)
        tcpRadio.target = helper
        tcpRadio.action = #selector(ConnectionDialogHelper.connectionTypeChanged(_:))
        tcpRadio.state = (settings.portType != .serial) ? .on : .off

        let hostLabel = NSView.makeLabel(L("dialog.connection.host"))

        let hostCombo = NSComboBox()
        hostCombo.translatesAutoresizingMaskIntoConstraints = false
        hostCombo.isEditable = true
        hostCombo.completes = true
        hostCombo.stringValue = settings.hostname
        hostCombo.placeholderString = L("dialog.connection.hostPlaceholder")
        hostCombo.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for h in settings.hostHistory {
            hostCombo.addItem(withObjectValue: h)
        }

        let hostRow = NSStackView(views: [tcpRadio, hostLabel, hostCombo])
        hostRow.translatesAutoresizingMaskIntoConstraints = false
        hostRow.orientation = .horizontal
        hostRow.spacing = DialogLayout.labelTrailing
        hostRow.alignment = .firstBaseline

        // Row 2: [Service:] [Telnet radio]  [TCP port#:] [port field]
        let serviceLabel = NSView.makeLabel(L("dialog.connection.service"))

        let telnetRadio = NSView.makeRadioButton(L("dialog.connection.telnet"), tag: 0)
        telnetRadio.target = helper
        telnetRadio.action = #selector(ConnectionDialogHelper.serviceChanged(_:))
        telnetRadio.state = (settings.serviceType == .telnet) ? .on : .off

        let tcpPortLabel = NSView.makeLabel(L("dialog.connection.tcpPort"))

        let tcpPortField = NSView.makeNumberField(value: settings.defaultPort, width: DialogLayout.narrowFieldWidth)
        helper.tcpPortField = tcpPortField

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

        // Row 3: [spacer] [SSH radio]  [SSH version:] [popup]
        let sshRadio = NSView.makeRadioButton("SSH", tag: 1)
        sshRadio.target = helper
        sshRadio.action = #selector(ConnectionDialogHelper.serviceChanged(_:))
        sshRadio.state = (settings.serviceType == .ssh) ? .on : .off

        let sshVerLabel = NSView.makeLabel(L("dialog.connection.sshVersion"))
        sshVerLabel.isEnabled = (settings.serviceType == .ssh)
        helper.sshVersionLabel = sshVerLabel

        let sshVerPopup = NSView.makePopUpButton(
            items: SSHVersion.allCases.map { $0.displayName },
            selected: settings.sshVersion.displayName)
        sshVerPopup.isEnabled = (settings.serviceType == .ssh)
        helper.sshVersionPopup = sshVerPopup

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

        // Row 4: [spacer] [Other radio]  [IP version:] [popup]
        let otherRadio = NSView.makeRadioButton(L("dialog.connection.other"), tag: 2)
        otherRadio.target = helper
        otherRadio.action = #selector(ConnectionDialogHelper.serviceChanged(_:))
        otherRadio.state = (settings.serviceType == .other) ? .on : .off

        let ipVerLabel = NSView.makeLabel(L("dialog.connection.ipVersion"))

        let ipVerPopup = NSView.makePopUpButton(
            items: ProtocolFamily.allCases.map { $0.displayName },
            selected: settings.protocolFamily.displayName)

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

        // Service rows: align radio buttons with leading indent
        // Ensure radio buttons have enough width for labels
        for radio in [telnetRadio, sshRadio, otherRadio] {
            radio.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        }

        let serviceStack = NSStackView(views: [row2, row3, row4])
        serviceStack.translatesAutoresizingMaskIntoConstraints = false
        serviceStack.orientation = .vertical
        serviceStack.alignment = .leading
        serviceStack.spacing = DialogLayout.rowSpacing

        // TCP content: hostRow + serviceStack
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

        // Align service radio rows under the host combobox column
        NSLayoutConstraint.activate([
            serviceLabel.trailingAnchor.constraint(equalTo: tcpRadio.trailingAnchor),
            sshRow.leadingAnchor.constraint(equalTo: serviceRow.leadingAnchor),
            sshRow.widthAnchor.constraint(equalTo: serviceRow.widthAnchor),
            otherRow.leadingAnchor.constraint(equalTo: serviceRow.leadingAnchor),
            otherRow.widthAnchor.constraint(equalTo: serviceRow.widthAnchor),
            hostCombo.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])

        helper.tcpControls = [hostLabel, hostCombo, serviceLabel,
                              telnetRadio, sshRadio, otherRadio,
                              tcpPortLabel, tcpPortField,
                              sshVerLabel, sshVerPopup,
                              ipVerLabel, ipVerPopup]

        // ── Serial Group Box ──
        let serialBox = NSBox()
        serialBox.translatesAutoresizingMaskIntoConstraints = false
        serialBox.titlePosition = .noTitle
        accessoryView.addSubview(serialBox)

        let serialContent = NSView()
        serialContent.translatesAutoresizingMaskIntoConstraints = false

        let serialRadio = NSView.makeRadioButton(L("dialog.connection.serial"), tag: 1)
        serialRadio.target = helper
        serialRadio.action = #selector(ConnectionDialogHelper.connectionTypeChanged(_:))
        serialRadio.state = (settings.portType == .serial) ? .on : .off

        let serialPortLabel = NSView.makeLabel(L("dialog.connection.serialPort"))

        let serialPortPopup = NSPopUpButton()
        serialPortPopup.translatesAutoresizingMaskIntoConstraints = false
        serialPortPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
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

        helper.serialControls = [serialPortLabel, serialPortPopup]

        // ── Main vertical stack: [tcpBox] - 12 - [serialBox] ──
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

                    if service == .ssh {
                        self.showSSHAuthDialog(wc: wc, host: host, port: port)
                    } else {
                        wc.connectTCP(host: host, port: port, telnet: service == .telnet)
                    }
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

    /// Show SSH authentication dialog, then connect on OK.
    private func showSSHAuthDialog(wc: TerminalWindowController, host: String, port: Int) {
        let vc = SSHAuthViewController(settings: settings)
        vc.onAuthenticate = { [weak self, weak wc] username, passphrase, authMethod, keyFile in
            guard let self = self, let wc = wc else { return }
            // Store auth settings
            self.settings.sshUsername = username
            self.settings.sshAuthMethod = authMethod
            self.settings.sshKeyFile = keyFile
            // Connect via SSH using system OpenSSH
            wc.connectSSH(
                host: host, port: port,
                username: username, password: passphrase,
                authMethod: authMethod, keyFile: keyFile,
                forwardAgent: self.settings.sshForwardAgent)
        }
        vc.cancelHandler = {
            // User chose "Disconnect" — do nothing
        }
        if let win = wc.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    /// 現在開いている設定シートやフォントパネルをOK（値保存）で閉じる
    private func dismissCurrentSetupSheet() {
        // フォントパネルが開いていれば閉じる
        let fontPanel = NSFontPanel.shared
        if fontPanel.isVisible {
            fontPanel.orderOut(nil)
        }
        // 設定シートが開いていればOKとして閉じる（applySettings + okHandler が呼ばれる）
        if let sheet = currentSetupSheet, let parent = sheet.sheetParent {
            parent.endSheet(sheet, returnCode: .OK)
        }
        currentSetupSheet = nil
    }

    private func showTerminalSetupDialog() {
        dismissCurrentSetupSheet()
        let vc = TerminalSetupViewController(settings: settings)
        vc.okHandler = { [weak self] in
            self?.activeWindowController?.applySettings()
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
            self?.activeWindowController?.applySettings()
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

        // ── Labels (right-aligned) ──
        let bsLabel = NSView.makeLabel(L("dialog.keyboardSetup.bsKey"))
        let delLabel = NSView.makeLabel(L("dialog.keyboardSetup.deleteKey"))
        let metaLabel = NSView.makeLabel(L("dialog.keyboardSetup.metaKey"))
        let ansLabel = NSView.makeLabel(L("dialog.keyboardSetup.answerback"))

        // ── Controls ──
        let kbPopupWidth: CGFloat = 180
        let bsPopup = NSView.makePopUpButton(
            items: ["BS (0x08)", "DEL (0x7F)"],
            width: kbPopupWidth)
        bsPopup.selectItem(at: settings.bsKey == 8 ? 0 : 1)

        let delPopup = NSView.makePopUpButton(
            items: ["DEL (0x7F)", "BS (0x08)", L("dialog.keyboardSetup.deleteEscSeq")],
            width: kbPopupWidth)
        delPopup.selectItem(at: settings.deleteKey == 127 ? 0 : (settings.deleteKey == 8 ? 1 : 2))

        let metaPopup = NSView.makePopUpButton(
            items: [L("dialog.keyboardSetup.metaOff"), L("dialog.keyboardSetup.metaOn")],
            width: kbPopupWidth)
        metaPopup.selectItem(at: settings.metaKey)

        let ansField = NSView.makeTextField(
            value: settings.answerback,
            placeholder: L("dialog.keyboardSetup.answerbackPlaceholder"),
            width: DialogLayout.wideFieldWidth)

        // ── NSGridView: 4 rows x 2 columns (label | control) ──
        let grid = NSGridView(views: [
            [bsLabel,   bsPopup],
            [delLabel,  delPopup],
            [metaLabel, metaPopup],
            [ansLabel,  ansField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12  // 24pt row height with controls
        grid.columnSpacing = 10  // label-to-control spacing >= 10pt
        grid.column(at: 0).xPlacement = .trailing   // labels right-aligned
        grid.column(at: 1).xPlacement = .leading     // controls left-aligned
        // Fixed label column width for consistent alignment
        grid.column(at: 0).width = 140
        // Baseline alignment per row
        for i in 0..<grid.numberOfRows {
            grid.row(at: i).rowAlignment = .firstBaseline
            grid.row(at: i).height = 24  // 24pt per row for vertical spacing
        }

        // Wrap grid in a padded container (20pt EdgeInsets)
        let paddedContainer = NSView()
        paddedContainer.translatesAutoresizingMaskIntoConstraints = false
        paddedContainer.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: paddedContainer.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: paddedContainer.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: paddedContainer.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(equalTo: paddedContainer.bottomAnchor, constant: -20),
            paddedContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 500),
        ])

        alert.accessoryView = paddedContainer
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

            activeWindowController?.applySettings()
        }
    }

    private func showSerialPortDialog() {
        dismissCurrentSetupSheet()
        let vc = SerialPortSetupViewController(settings: settings)
        vc.okHandler = { [weak self] in
            guard let self = self else { return }
            self.activeWindowController?.applySettings()
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

    // MARK: TCP/IP Setup Dialog

    private func showTCPIPDialog() {
        dismissCurrentSetupSheet()
        let vc = TCPIPDialogController(settings: settings)
        vc.okHandler = { [weak self] in
            self?.activeWindowController?.applySettings()
        }
        if let win = activeWindowController?.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: Additional Settings Dialog

    private var additionalSettingsController: AdditionalSettingsController?

    private func showAdditionalSettingsDialog() {
        dismissCurrentSetupSheet()
        let controller = AdditionalSettingsController(settings: settings)
        controller.onApply = { [weak self] in
            self?.activeWindowController?.applySettings()
        }
        additionalSettingsController = controller
        if let win = activeWindowController?.window {
            controller.showAsSheet(on: win)
        } else {
            controller.showModal()
        }
    }

    // MARK: Proxy Setup Dialog

    private func showProxySetupDialog() {
        dismissCurrentSetupSheet()
        let vc = ProxySetupDialogController(settings: settings)
        vc.okHandler = { [weak self] in
            self?.activeWindowController?.applySettings()
        }
        if let win = activeWindowController?.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: SSH Setup Dialog

    private func showSSHSetupDialog() {
        dismissCurrentSetupSheet()
        let vc = SSHSetupDialogController(settings: settings)
        vc.okHandler = { [weak self] in
            self?.activeWindowController?.applySettings()
        }
        if let win = activeWindowController?.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: SSH Authentication Setup Dialog

    private func showSSHAuthSetupDialog() {
        dismissCurrentSetupSheet()
        let vc = SSHAuthSetupDialogController(settings: settings)
        vc.okHandler = { [weak self] in
            self?.activeWindowController?.applySettings()
        }
        if let win = activeWindowController?.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: SSH Forwarding Setup Dialog

    private func showSSHForwardingSetupDialog() {
        dismissCurrentSetupSheet()
        let vc = SSHForwardingSetupDialogController(settings: settings)
        vc.okHandler = { [weak self] in
            self?.activeWindowController?.applySettings()
        }
        if let win = activeWindowController?.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: SSH Key Generation Dialog

    private func showSSHKeyGenDialog() {
        dismissCurrentSetupSheet()
        let vc = SSHKeyGenDialogController()
        if let win = activeWindowController?.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: General Setup Dialog

    private func showGeneralSetupDialog() {
        dismissCurrentSetupSheet()
        let vc = GeneralSetupDialogController(settings: settings)
        vc.okHandler = { [weak self] in
            self?.activeWindowController?.applySettings()
        }
        if let win = activeWindowController?.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: SSH SCP Dialog

    private func showSSHSCPDialog() {
        guard let wc = activeWindowController else { return }

        // Check if connected via SSH
        guard wc.connectionManager.currentConnection is SSHConnection else {
            let alert = NSAlert()
            alert.messageText = L("dialog.scp.error.notConnected")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("OK"))
            if let win = wc.window {
                alert.beginSheetModal(for: win, completionHandler: nil)
            } else {
                alert.runModal()
            }
            return
        }

        let ssh = wc.connectionManager.currentConnection as! SSHConnection
        let vc = SCPDialogController(settings: settings)
        vc.onSend = { [weak self] localPath, remotePath in
            SCPDialogController.executeSCP(
                send: true, localPath: localPath, remotePath: remotePath,
                host: ssh.host, port: ssh.port, username: ssh.username
            ) { success, error in
                guard !success else { return }
                self?.showSCPErrorAlert(error)
            }
        }
        vc.onReceive = { [weak self] remotePath, localDir in
            SCPDialogController.executeSCP(
                send: false, localPath: localDir, remotePath: remotePath,
                host: ssh.host, port: ssh.port, username: ssh.username
            ) { success, error in
                guard !success else { return }
                self?.showSCPErrorAlert(error)
            }
        }
        if let win = wc.window {
            currentSetupSheet = vc.presentAsSheet(on: win)
        }
    }

    private func showSCPErrorAlert(_ detail: String) {
        let alert = NSAlert()
        alert.messageText = "SCP"
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }

    private func findSerialPorts() -> [String] {
        return SerialPortSetupViewController.findSerialPorts()
    }
}
#endif
