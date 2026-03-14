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

// MARK: - Connection Dialog Helper (radio button group controller)

private class ConnectionDialogHelper: NSObject {
    var tcpControls: [NSControl] = []
    var serialControls: [NSControl] = []
    var localShellControls: [NSControl] = []
    weak var tcpPortField: NSTextField?
    weak var sshVersionLabel: NSTextField?
    weak var sshVersionPopup: NSPopUpButton?

    // 接続タイプラジオボタン（別々の NSBox に配置されるため手動排他が必要）
    weak var tcpRadio: NSButton?
    weak var serialRadio: NSButton?
    weak var shellRadio: NSButton?

    // サービスタイプラジオボタン（別々の NSStackView 行に配置されるため手動排他が必要）
    weak var telnetRadio: NSButton?
    weak var sshRadio: NSButton?
    weak var otherRadio: NSButton?

    /// TCP/IP(tag=0) vs Serial(tag=1) vs Local Shell(tag=2)
    @objc func connectionTypeChanged(_ sender: NSButton) {
        let tag = sender.tag
        // 別々の NSBox に配置されたラジオボタンは自動排他にならないため手動で制御
        tcpRadio?.state = (tag == 0) ? .on : .off
        serialRadio?.state = (tag == 1) ? .on : .off
        shellRadio?.state = (tag == 2) ? .on : .off

        for ctrl in tcpControls { ctrl.isEnabled = (tag == 0) }
        for ctrl in serialControls { ctrl.isEnabled = (tag == 1) }
        for ctrl in localShellControls { ctrl.isEnabled = (tag == 2) }
    }

    /// Service radio: Telnet(tag=0) / SSH(tag=1) / Other(tag=2)
    @objc func serviceChanged(_ sender: NSButton) {
        let tag = sender.tag
        // 別々の NSStackView 行に配置されたラジオボタンは自動排他にならないため手動で制御
        telnetRadio?.state = (tag == 0) ? .on : .off
        sshRadio?.state = (tag == 1) ? .on : .off
        otherRadio?.state = (tag == 2) ? .on : .off

        switch tag {
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
    private weak var currentSetupDialog: NSWindow?

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
            alert.messageText = TTL("dialog.quit.title")
            alert.informativeText = String(format: TTL("dialog.quit.message"), activeConnections.count)
            alert.alertStyle = .warning
            alert.addButton(withTitle: TTL("dialog.quit.quit"))
            alert.addButton(withTitle: TTL("dialog.quit.cancel"))
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

        let aboutItem = appMenu.addItem(withTitle: TTL("menu.app.about"), action: #selector(showAbout(_:)), keyEquivalent: "")
        setSymbol("info.circle", for: aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        let prefItem = appMenu.addItem(withTitle: TTL("menu.app.preferences"), action: #selector(showPreferences(_:)), keyEquivalent: ",")
        setSymbol("gearshape", for: prefItem)
        appMenu.addItem(NSMenuItem.separator())
        let hideItem = appMenu.addItem(withTitle: TTL("menu.app.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        setSymbol("eye.slash", for: hideItem)
        let hideOthers = NSMenuItem(title: TTL("menu.app.hideOthers"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        setSymbol("eye.slash.circle", for: hideOthers)
        appMenu.addItem(hideOthers)
        let showAllItem = appMenu.addItem(withTitle: TTL("menu.app.showAll"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        setSymbol("eye", for: showAllItem)
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = appMenu.addItem(withTitle: TTL("menu.app.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        setSymbol("power", for: quitItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: TTL("menu.file"))
        fileMenuItem.submenu = fileMenu

        let newConnItem = fileMenu.addItem(withTitle: TTL("menu.file.newConnection"), action: #selector(newConnection(_:)), keyEquivalent: "n")
        setSymbol("network", for: newConnItem)
        let newWinItem = fileMenu.addItem(withTitle: TTL("menu.file.newWindow"), action: #selector(newWindow(_:)), keyEquivalent: "t")
        setSymbol("macwindow.badge.plus", for: newWinItem)
        let dupItem = fileMenu.addItem(withTitle: TTL("menu.file.duplicateSession"), action: #selector(duplicateSession(_:)), keyEquivalent: "d")
        setSymbol("doc.on.doc", for: dupItem)
        fileMenu.addItem(NSMenuItem.separator())
        let sendFileItem = fileMenu.addItem(withTitle: TTL("menu.file.sendFile"), action: #selector(showSendFileDialog(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: sendFileItem)
        let recvFileItem = fileMenu.addItem(withTitle: TTL("menu.file.receiveFile"), action: #selector(showRecvFileDialog(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: recvFileItem)
        fileMenu.addItem(NSMenuItem.separator())
        let logItem = fileMenu.addItem(withTitle: TTL("menu.file.log"), action: #selector(showLogDialog(_:)), keyEquivalent: "")
        setSymbol("doc.text", for: logItem)
        let pauseLogItem = fileMenu.addItem(withTitle: TTL("menu.file.pauseLog"), action: #selector(pauseLog(_:)), keyEquivalent: "")
        setSymbol("pause.circle", for: pauseLogItem)
        let commentLogItem = fileMenu.addItem(withTitle: TTL("menu.file.commentToLog"), action: #selector(commentToLog(_:)), keyEquivalent: "")
        setSymbol("text.bubble", for: commentLogItem)
        let viewLogItem = fileMenu.addItem(withTitle: TTL("menu.file.viewLog"), action: #selector(viewLog(_:)), keyEquivalent: "")
        setSymbol("eye.circle", for: viewLogItem)
        let showLogDlgItem = fileMenu.addItem(withTitle: TTL("menu.file.showLogDialog"), action: #selector(showLogProgressDialog(_:)), keyEquivalent: "")
        setSymbol("chart.bar.doc.horizontal", for: showLogDlgItem)
        let stopLogItem = fileMenu.addItem(withTitle: TTL("menu.file.stopLog"), action: #selector(stopLog(_:)), keyEquivalent: "")
        setSymbol("doc.text.fill", for: stopLogItem)
        fileMenu.addItem(NSMenuItem.separator())
        let changeDirItem = fileMenu.addItem(withTitle: TTL("menu.file.changeDir"), action: #selector(showChangeDir(_:)), keyEquivalent: "")
        setSymbol("folder", for: changeDirItem)
        fileMenu.addItem(NSMenuItem.separator())

        // File transfer submenu
        let transferMenu = NSMenu(title: TTL("menu.file.fileTransfer"))
        let transferMenuItem = NSMenuItem(title: TTL("menu.file.fileTransfer"), action: nil, keyEquivalent: "")
        setSymbol("arrow.left.arrow.right", for: transferMenuItem)
        transferMenuItem.submenu = transferMenu
        fileMenu.addItem(transferMenuItem)

        let xmSend = transferMenu.addItem(withTitle: TTL("menu.file.xmodemSend"), action: #selector(xmodemSend(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: xmSend)
        let xmRecv = transferMenu.addItem(withTitle: TTL("menu.file.xmodemReceive"), action: #selector(xmodemRecv(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: xmRecv)
        transferMenu.addItem(NSMenuItem.separator())
        let zmSend = transferMenu.addItem(withTitle: TTL("menu.file.zmodemSend"), action: #selector(zmodemSend(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: zmSend)
        let zmRecv = transferMenu.addItem(withTitle: TTL("menu.file.zmodemReceive"), action: #selector(zmodemRecv(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: zmRecv)
        transferMenu.addItem(NSMenuItem.separator())
        let kmSend = transferMenu.addItem(withTitle: TTL("menu.file.kermitSend"), action: #selector(kermitSend(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: kmSend)
        let kmRecv = transferMenu.addItem(withTitle: TTL("menu.file.kermitReceive"), action: #selector(kermitRecv(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: kmRecv)
        let kmGet = transferMenu.addItem(withTitle: TTL("menu.file.kermitGet"), action: #selector(kermitGet(_:)), keyEquivalent: "")
        setSymbol("arrow.down.to.line", for: kmGet)
        let kmFinish = transferMenu.addItem(withTitle: TTL("menu.file.kermitFinish"), action: #selector(kermitFinish(_:)), keyEquivalent: "")
        setSymbol("stop.circle", for: kmFinish)
        transferMenu.addItem(NSMenuItem.separator())
        let ymSend = transferMenu.addItem(withTitle: TTL("menu.file.ymodemSend"), action: #selector(ymodemSend(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: ymSend)
        let ymRecv = transferMenu.addItem(withTitle: TTL("menu.file.ymodemReceive"), action: #selector(ymodemRecv(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: ymRecv)
        transferMenu.addItem(NSMenuItem.separator())
        let bpSend = transferMenu.addItem(withTitle: TTL("menu.file.bplusSend"), action: #selector(bplusSend(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: bpSend)
        let bpRecv = transferMenu.addItem(withTitle: TTL("menu.file.bplusReceive"), action: #selector(bplusRecv(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: bpRecv)
        transferMenu.addItem(NSMenuItem.separator())
        let qvSend = transferMenu.addItem(withTitle: TTL("menu.file.quickvanSend"), action: #selector(quickvanSend(_:)), keyEquivalent: "")
        setSymbol("arrow.up.doc", for: qvSend)
        let qvRecv = transferMenu.addItem(withTitle: TTL("menu.file.quickvanReceive"), action: #selector(quickvanRecv(_:)), keyEquivalent: "")
        setSymbol("arrow.down.doc", for: qvRecv)

        fileMenu.addItem(NSMenuItem.separator())
        let scpItem = fileMenu.addItem(withTitle: TTL("menu.file.sshSCP"), action: #selector(showSCPDialog(_:)), keyEquivalent: "")
        setSymbol("lock.doc", for: scpItem)
        fileMenu.addItem(NSMenuItem.separator())
        let printItem = fileMenu.addItem(withTitle: TTL("menu.file.print"), action: #selector(printTerminal(_:)), keyEquivalent: "p")
        setSymbol("printer", for: printItem)
        let tekPrintItem = fileMenu.addItem(withTitle: TTL("menu.file.printTEK"), action: #selector(printTEKWindow(_:)), keyEquivalent: "")
        setSymbol("printer", for: tekPrintItem)
        fileMenu.addItem(NSMenuItem.separator())
        let disconnItem = fileMenu.addItem(withTitle: TTL("menu.file.disconnect"), action: #selector(doDisconnect(_:)), keyEquivalent: "")
        setSymbol("xmark.circle", for: disconnItem)
        fileMenu.addItem(NSMenuItem.separator())
        let quitAllItem = fileMenu.addItem(withTitle: TTL("menu.file.quitAll"), action: #selector(quitAllTeraTerm(_:)), keyEquivalent: "")
        setSymbol("xmark.square.fill", for: quitAllItem)
        let closeItem = fileMenu.addItem(withTitle: TTL("menu.file.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        setSymbol("xmark.square", for: closeItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: TTL("menu.edit"))
        editMenuItem.submenu = editMenu

        let copyItem = editMenu.addItem(withTitle: TTL("menu.edit.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        setSymbol("doc.on.doc", for: copyItem)
        let copyTableItem = editMenu.addItem(withTitle: TTL("menu.edit.copyAsTable"), action: #selector(copyAsTable(_:)), keyEquivalent: "")
        setSymbol("tablecells", for: copyTableItem)
        let pasteItem = editMenu.addItem(withTitle: TTL("menu.edit.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        setSymbol("doc.on.clipboard", for: pasteItem)
        let pasteSpecialItem = editMenu.addItem(withTitle: TTL("menu.edit.pasteSpecial"), action: #selector(pasteSpecial(_:)), keyEquivalent: "")
        setSymbol("doc.on.clipboard.fill", for: pasteSpecialItem)
        let pasteCRItem = editMenu.addItem(withTitle: TTL("menu.edit.pasteCR"), action: #selector(pasteCR(_:)), keyEquivalent: "")
        setSymbol("return", for: pasteCRItem)
        editMenu.addItem(NSMenuItem.separator())
        let clsItem = editMenu.addItem(withTitle: TTL("menu.edit.clearScreen"), action: #selector(clearScreen(_:)), keyEquivalent: "")
        setSymbol("rectangle.slash", for: clsItem)
        let clbItem = editMenu.addItem(withTitle: TTL("menu.edit.clearBuffer"), action: #selector(clearBuffer(_:)), keyEquivalent: "")
        setSymbol("trash", for: clbItem)
        editMenu.addItem(NSMenuItem.separator())
        let selAllItem = editMenu.addItem(withTitle: TTL("menu.edit.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        setSymbol("selection.pin.in.out", for: selAllItem)
        let deselectItem = editMenu.addItem(withTitle: TTL("menu.edit.deselect"), action: #selector(deselect(_:)), keyEquivalent: "")
        setSymbol("xmark.rectangle", for: deselectItem)
        let selectScreenItem = editMenu.addItem(withTitle: TTL("menu.edit.selectScreen"), action: #selector(selectScreen(_:)), keyEquivalent: "")
        setSymbol("rectangle.dashed", for: selectScreenItem)
        editMenu.addItem(NSMenuItem.separator())
        let editHistoryItem = editMenu.addItem(withTitle: TTL("menu.edit.editHistory"), action: #selector(showEditHistory(_:)), keyEquivalent: "")
        setSymbol("clock.arrow.circlepath", for: editHistoryItem)

        // Setup menu
        let setupMenuItem = NSMenuItem()
        mainMenu.addItem(setupMenuItem)
        let setupMenu = NSMenu(title: TTL("menu.setup"))
        setupMenuItem.submenu = setupMenu

        let termItem = setupMenu.addItem(withTitle: TTL("menu.setup.terminal"), action: #selector(setupTerminal(_:)), keyEquivalent: "")
        setSymbol("terminal", for: termItem)
        let winItem = setupMenu.addItem(withTitle: TTL("menu.setup.window"), action: #selector(setupWindow(_:)), keyEquivalent: "")
        setSymbol("macwindow", for: winItem)
        let fontItem = setupMenu.addItem(withTitle: TTL("menu.setup.font"), action: #selector(setupFont(_:)), keyEquivalent: "")
        setSymbol("textformat.size", for: fontItem)
        let kbItem = setupMenu.addItem(withTitle: TTL("menu.setup.keyboard"), action: #selector(setupKeyboard(_:)), keyEquivalent: "")
        setSymbol("keyboard", for: kbItem)
        let serialItem = setupMenu.addItem(withTitle: TTL("menu.setup.serialPort"), action: #selector(setupSerialPort(_:)), keyEquivalent: "")
        setSymbol("cable.connector", for: serialItem)
        let tcpipItem = setupMenu.addItem(withTitle: TTL("menu.setup.tcpip"), action: #selector(setupTCPIP(_:)), keyEquivalent: "")
        setSymbol("network", for: tcpipItem)
        setupMenu.addItem(NSMenuItem.separator())
        let proxyItem = setupMenu.addItem(withTitle: TTL("menu.setup.proxy"), action: #selector(setupProxy(_:)), keyEquivalent: "")
        setSymbol("globe", for: proxyItem)
        let sshSetupItem = setupMenu.addItem(withTitle: TTL("menu.setup.ssh"), action: #selector(setupSSH(_:)), keyEquivalent: "")
        setSymbol("lock.shield", for: sshSetupItem)
        let sshAuthSetupItem = setupMenu.addItem(withTitle: TTL("menu.setup.sshAuth"), action: #selector(setupSSHAuth(_:)), keyEquivalent: "")
        setSymbol("person.badge.key", for: sshAuthSetupItem)
        let sshFwdItem = setupMenu.addItem(withTitle: TTL("menu.setup.sshForward"), action: #selector(setupSSHForwarding(_:)), keyEquivalent: "")
        setSymbol("arrow.triangle.branch", for: sshFwdItem)
        let sshKeyGenItem = setupMenu.addItem(withTitle: TTL("menu.setup.sshKeyGen"), action: #selector(setupSSHKeyGen(_:)), keyEquivalent: "")
        setSymbol("key", for: sshKeyGenItem)
        setupMenu.addItem(NSMenuItem.separator())
        let generalItem = setupMenu.addItem(withTitle: TTL("menu.setup.general"), action: #selector(setupGeneral(_:)), keyEquivalent: "")
        setSymbol("gearshape", for: generalItem)
        setupMenu.addItem(NSMenuItem.separator())
        let additionalItem = setupMenu.addItem(withTitle: TTL("menu.setup.additionalSettings"), action: #selector(setupAdditional(_:)), keyEquivalent: "")
        setSymbol("slider.horizontal.3", for: additionalItem)
        setupMenu.addItem(NSMenuItem.separator())
        let loadKeymapItem = setupMenu.addItem(withTitle: TTL("menu.setup.loadKeymap"), action: #selector(loadKeymap(_:)), keyEquivalent: "")
        setSymbol("doc.text", for: loadKeymapItem)
        let saveItem = setupMenu.addItem(withTitle: TTL("menu.setup.saveSetup"), action: #selector(saveSetup(_:)), keyEquivalent: "")
        setSymbol("square.and.arrow.down", for: saveItem)
        let restoreItem = setupMenu.addItem(withTitle: TTL("menu.setup.restoreSetup"), action: #selector(restoreSetup(_:)), keyEquivalent: "")
        setSymbol("square.and.arrow.up", for: restoreItem)
        setupMenu.addItem(NSMenuItem.separator())
        let openConfigItem = setupMenu.addItem(withTitle: TTL("menu.setup.openConfigFolder"), action: #selector(openConfigFolder(_:)), keyEquivalent: "")
        setSymbol("folder", for: openConfigItem)

        // Code menu (encoding selection)
        let codeMenuItem = NSMenuItem()
        mainMenu.addItem(codeMenuItem)
        let codeMenu = NSMenu(title: TTL("menu.code"))
        codeMenuItem.submenu = codeMenu
        buildCodeMenu(codeMenu)

        // Control menu
        let controlMenuItem = NSMenuItem()
        mainMenu.addItem(controlMenuItem)
        let controlMenu = NSMenu(title: TTL("menu.control"))
        controlMenuItem.submenu = controlMenu

        let resetItem = controlMenu.addItem(withTitle: TTL("menu.control.resetTerminal"), action: #selector(resetTerminal(_:)), keyEquivalent: "")
        setSymbol("arrow.counterclockwise", for: resetItem)
        let aytItem = controlMenu.addItem(withTitle: TTL("menu.control.areYouThere"), action: #selector(areYouThere(_:)), keyEquivalent: "")
        setSymbol("questionmark.circle", for: aytItem)
        let breakItem = controlMenu.addItem(withTitle: TTL("menu.control.sendBreak"), action: #selector(sendBreak(_:)), keyEquivalent: "")
        setSymbol("exclamationmark.triangle", for: breakItem)
        let portResetItem = controlMenu.addItem(withTitle: TTL("menu.control.resetPort"), action: #selector(resetPort(_:)), keyEquivalent: "")
        setSymbol("arrow.triangle.2.circlepath", for: portResetItem)

        controlMenu.addItem(NSMenuItem.separator())

        let macroItem = controlMenu.addItem(withTitle: TTL("menu.control.macro"), action: #selector(runMacro(_:)), keyEquivalent: "m")
        macroItem.keyEquivalentModifierMask = [.command, .shift]
        setSymbol("applescript", for: macroItem)
        let stopMacroItem = controlMenu.addItem(withTitle: TTL("menu.control.stopMacro"), action: #selector(stopMacro(_:)), keyEquivalent: "")
        setSymbol("stop.circle", for: stopMacroItem)
        let replayItem = controlMenu.addItem(withTitle: TTL("menu.control.replayLog"), action: #selector(replayLog(_:)), keyEquivalent: "")
        setSymbol("play.rectangle", for: replayItem)

        controlMenu.addItem(NSMenuItem.separator())

        let resetTitleItem = controlMenu.addItem(withTitle: TTL("menu.control.resetRemoteTitle"), action: #selector(resetRemoteTitle(_:)), keyEquivalent: "")
        setSymbol("textformat", for: resetTitleItem)
        let tekItem = controlMenu.addItem(withTitle: TTL("menu.control.tekWindow"), action: #selector(toggleTEKWindow(_:)), keyEquivalent: "")
        setSymbol("rectangle.on.rectangle", for: tekItem)
        let showMacroItem = controlMenu.addItem(withTitle: TTL("menu.control.showMacroWindow"), action: #selector(showMacroWindow(_:)), keyEquivalent: "")
        setSymbol("text.rectangle", for: showMacroItem)

        controlMenu.addItem(NSMenuItem.separator())

        let broadcastItem = controlMenu.addItem(withTitle: TTL("menu.control.broadcast"), action: #selector(toggleBroadcast(_:)), keyEquivalent: "")
        setSymbol("antenna.radiowaves.left.and.right", for: broadcastItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: TTL("menu.window"))
        windowMenuItem.submenu = windowMenu

        let minItem = windowMenu.addItem(withTitle: TTL("menu.window.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        setSymbol("minus.square", for: minItem)
        let zoomItem = windowMenu.addItem(withTitle: TTL("menu.window.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        setSymbol("arrow.up.left.and.arrow.down.right", for: zoomItem)
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem.separator())
        let minAllItem = windowMenu.addItem(withTitle: TTL("menu.window.minimizeAll"), action: #selector(minimizeAllWindows(_:)), keyEquivalent: "")
        setSymbol("arrow.down.to.line.compact", for: minAllItem)
        let cascadeItem = windowMenu.addItem(withTitle: TTL("menu.window.cascade"), action: #selector(cascadeAllWindows(_:)), keyEquivalent: "")
        setSymbol("square.on.square", for: cascadeItem)
        let tileVItem = windowMenu.addItem(withTitle: TTL("menu.window.tileVertical"), action: #selector(tileWindowsVertically(_:)), keyEquivalent: "")
        setSymbol("rectangle.split.1x2", for: tileVItem)
        let tileHItem = windowMenu.addItem(withTitle: TTL("menu.window.tileHorizontal"), action: #selector(tileWindowsHorizontally(_:)), keyEquivalent: "")
        setSymbol("rectangle.split.2x1", for: tileHItem)
        let restoreAllItem = windowMenu.addItem(withTitle: TTL("menu.window.restoreAll"), action: #selector(restoreAllWindows(_:)), keyEquivalent: "")
        setSymbol("arrow.up.to.line.compact", for: restoreAllItem)
        windowMenu.addItem(NSMenuItem.separator())
        let winListItem = windowMenu.addItem(withTitle: TTL("menu.window.windowList"), action: #selector(showWindowList(_:)), keyEquivalent: "")
        setSymbol("list.bullet.rectangle", for: winListItem)
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: TTL("menu.help"))
        helpMenuItem.submenu = helpMenu

        let helpItem = helpMenu.addItem(withTitle: TTL("menu.help.help"), action: #selector(showHelp(_:)), keyEquivalent: "?")
        setSymbol("questionmark.circle", for: helpItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

    @objc func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = TTL("dialog.about.title")
        alert.informativeText = TTL("dialog.about.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: TTL("dialog.about.ok"))
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
        currentSetupDialog = vc.presentAsModal(on: win)
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
        alert.messageText = TTL("dialog.logComment.title")
        alert.informativeText = TTL("dialog.logComment.message")
        alert.addButton(withTitle: TTL("dialog.logComment.ok"))
        alert.addButton(withTitle: TTL("dialog.logComment.cancel"))

        let textField = NSView.makeTextField(value: "", placeholder: TTL("dialog.logComment.placeholder"))
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
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
        alert.messageText = TTL("dialog.quitAll.title")
        alert.informativeText = String(format: TTL("dialog.quitAll.message"), count)
        alert.alertStyle = .warning
        alert.addButton(withTitle: TTL("dialog.quitAll.quit"))
        alert.addButton(withTitle: TTL("dialog.quitAll.cancel"))

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
        currentSetupDialog = vc.presentAsModal(on: win)
    }

    @objc func showWindowList(_ sender: Any?) {
        guard let win = activeWindowController?.window else { return }
        WindowListDialog.show(on: win) { _ in }
    }

    // MARK: - Window Arrangement (port of ID_WINDOW_MINIMIZEALL / CASCADE / STACKED / SIDEBYSIDE / RESTOREALL)

    /// Minimize all Tera Term windows (port of OnWindowMinimizeAll → ShowAllWin(SW_MINIMIZE))
    @objc func minimizeAllWindows(_ sender: Any?) {
        for wc in windowControllers {
            wc.window?.miniaturize(nil)
        }
    }

    /// Cascade all Tera Term windows (port of OnWindowCascade → ShowAllWinCascade)
    @objc func cascadeAllWindows(_ sender: Any?) {
        // Restore any minimized windows first
        for wc in windowControllers {
            if wc.window?.isMiniaturized == true {
                wc.window?.deminiaturize(nil)
            }
        }
        // Use macOS standard cascade: NSWindow.cascadeTopLeftFrom(_:)
        var topLeft = NSPoint.zero
        for wc in windowControllers {
            guard let win = wc.window else { continue }
            topLeft = win.cascadeTopLeft(from: topLeft)
        }
    }

    /// Tile all Tera Term windows vertically / stacked (port of OnWindowStacked → TileWindows MDITILE_HORIZONTAL)
    /// Note: Windows "Stacked" = vertically stacked = split screen top/bottom
    @objc func tileWindowsVertically(_ sender: Any?) {
        tileWindows(horizontal: false)
    }

    /// Tile all Tera Term windows horizontally / side by side (port of OnWindowSidebySide → TileWindows MDITILE_VERTICAL)
    /// Note: Windows "Side by Side" = horizontally side-by-side = split screen left/right
    @objc func tileWindowsHorizontally(_ sender: Any?) {
        tileWindows(horizontal: true)
    }

    /// Restore all Tera Term windows (port of OnWindowRestoreAll → ShowAllWin(SW_RESTORE))
    @objc func restoreAllWindows(_ sender: Any?) {
        for wc in windowControllers {
            if wc.window?.isMiniaturized == true {
                wc.window?.deminiaturize(nil)
            }
            if wc.window?.isZoomed == true {
                wc.window?.zoom(nil)
            }
        }
    }

    /// Tile windows in a grid layout on the main screen.
    private func tileWindows(horizontal: Bool) {
        let visibleControllers = windowControllers.filter { $0.window != nil }
        guard !visibleControllers.isEmpty else { return }

        // Restore minimized windows first
        for wc in visibleControllers {
            if wc.window?.isMiniaturized == true {
                wc.window?.deminiaturize(nil)
            }
        }

        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let count = visibleControllers.count

        if horizontal {
            // Side by side: split horizontally (left/right)
            let width = frame.width / CGFloat(count)
            for (i, wc) in visibleControllers.enumerated() {
                let rect = NSRect(
                    x: frame.origin.x + width * CGFloat(i),
                    y: frame.origin.y,
                    width: width,
                    height: frame.height)
                wc.window?.setFrame(rect, display: true)
            }
        } else {
            // Stacked: split vertically (top/bottom)
            let height = frame.height / CGFloat(count)
            for (i, wc) in visibleControllers.enumerated() {
                let rect = NSRect(
                    x: frame.origin.x,
                    y: frame.origin.y + height * CGFloat(count - 1 - i),
                    width: frame.width,
                    height: height)
                wc.window?.setFrame(rect, display: true)
            }
        }
    }

    @objc func xmodemSend(_ sender: Any?) { activeWindowController?.sendFile(protocol: .xmodemCRC) }
    @objc func xmodemRecv(_ sender: Any?) { activeWindowController?.receiveFile(protocol: .xmodemCRC) }
    @objc func zmodemSend(_ sender: Any?) { activeWindowController?.sendFile(protocol: .zmodem) }
    @objc func zmodemRecv(_ sender: Any?) { activeWindowController?.receiveFile(protocol: .zmodem) }
    @objc func kermitSend(_ sender: Any?) { activeWindowController?.sendFile(protocol: .kermit) }
    @objc func kermitRecv(_ sender: Any?) { activeWindowController?.receiveFile(protocol: .kermit) }
    @objc func kermitGet(_ sender: Any?) { activeWindowController?.kermitGet() }
    @objc func kermitFinish(_ sender: Any?) { activeWindowController?.kermitFinish() }
    @objc func ymodemSend(_ sender: Any?) { activeWindowController?.sendFile(protocol: .ymodem) }
    @objc func ymodemRecv(_ sender: Any?) { activeWindowController?.receiveFile(protocol: .ymodem) }
    @objc func bplusSend(_ sender: Any?) { activeWindowController?.sendFile(protocol: .bplus) }
    @objc func bplusRecv(_ sender: Any?) { activeWindowController?.receiveFile(protocol: .bplus) }
    @objc func quickvanSend(_ sender: Any?) { activeWindowController?.sendFile(protocol: .quickVAN) }
    @objc func quickvanRecv(_ sender: Any?) { activeWindowController?.receiveFile(protocol: .quickVAN) }

    @objc func doDisconnect(_ sender: Any?) {
        activeWindowController?.disconnect()
    }

    @objc func copyAsTable(_ sender: Any?) {
        activeWindowController?.copyAsTable()
    }

    @objc func pasteSpecial(_ sender: Any?) {
        guard let wc = activeWindowController else { return }

        let m = DialogLayout.margin

        // NSPanel ベースのモーダルダイアログ
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        panel.title = TTL("dialog.pasteSpecial.title")
        panel.isReleasedWhenClosed = false

        guard let root = panel.contentView else { return }

        // 説明ラベル
        let messageLabel = NSTextField(labelWithString: TTL("dialog.pasteSpecial.message"))
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = NSFont.systemFont(ofSize: 13)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.addSubview(messageLabel)

        // テキストビュー
        let textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        root.addSubview(scrollView)

        // クリップボードから事前入力
        if let clipText = NSPasteboard.general.string(forType: .string) {
            textView.string = clipText
        }

        // セパレータ
        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        root.addSubview(separator)

        // ボタンバー: [spacer] [Cancel] [Send]
        let sendButton = NSView.makePushButton(TTL("dialog.pasteSpecial.send"), keyEquivalent: "\r")
        let cancelButton = NSView.makePushButton(TTL("Cancel"), keyEquivalent: "\u{1b}")

        let buttonSpacer = NSView()
        buttonSpacer.translatesAutoresizingMaskIntoConstraints = false
        buttonSpacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)

        let buttonBar = NSStackView(views: [buttonSpacer, cancelButton, sendButton])
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.orientation = .horizontal
        buttonBar.spacing = DialogLayout.buttonSpacing
        buttonBar.alignment = .centerY
        root.addSubview(buttonBar)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: m),
            messageLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            messageLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),

            scrollView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: DialogLayout.rowSpacing),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),

            separator.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: m),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            buttonBar.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: m * 0.75),
            buttonBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            buttonBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),
            buttonBar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -m * 0.75),

            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),
        ])

        sendButton.target = nil
        sendButton.action = #selector(AppDelegate.connectionDialogOK(_:))
        cancelButton.target = nil
        cancelButton.action = #selector(AppDelegate.connectionDialogCancel(_:))

        root.layoutSubtreeIfNeeded()
        panel.setContentSize(root.fittingSize)
        panel.center()

        let response = NSApp.runModal(for: panel)
        panel.close()

        if response == .OK {
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

    /// Paste clipboard text with CR appended to each line (port of ID_EDIT_PASTE2)
    @objc func pasteCR(_ sender: Any?) {
        guard let wc = activeWindowController else { return }
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        // Append CR to each line, matching Windows Tera Term "Paste<CR>" behavior
        var result = ""
        let lines = text.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            result += line
            // Add CR at the end of every line (including last)
            if i < lines.count - 1 || !line.isEmpty {
                result += "\r"
            }
        }
        wc.connectionManager.send(Data(result.utf8))
    }

    /// Cancel current selection (port of ID_EDIT_CANCELSELECTION)
    @objc func deselect(_ sender: Any?) {
        guard let wc = activeWindowController else { return }
        wc.terminalEmulator.buffer.selection = BufferSelection()
        wc.terminalView.refresh()
    }

    /// Select only the visible screen area (port of ID_EDIT_SELECTSCREEN)
    @objc func selectScreen(_ sender: Any?) {
        guard let wc = activeWindowController else { return }
        let buffer = wc.terminalEmulator.buffer
        let size = wc.terminalView.terminalSize
        buffer.selection.isActive = true
        buffer.selection.startX = 0
        buffer.selection.startY = 0
        buffer.selection.endX = size.columns
        buffer.selection.endY = size.rows - 1
        wc.terminalView.refresh()
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

    @objc func printTEKWindow(_ sender: Any?) {
        tekWindowController?.printTEKWindow()
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

    @objc func loadKeymap(_ sender: Any?) {
        dismissCurrentSetupSheet()
        guard let win = activeWindowController?.window ?? NSApp.keyWindow else { return }
        let panel = NSOpenPanel()
        let cnfType = UTType(filenameExtension: "cnf") ?? .plainText
        panel.allowedContentTypes = [cnfType, .plainText]
        panel.title = TTL("dialog.loadKeymap.title")
        panel.message = TTL("dialog.loadKeymap.message")
        panel.beginSheetModal(for: win) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.performLoadKeymap(from: url, parentWindow: win)
        }
    }

    private func performLoadKeymap(from url: URL, parentWindow: NSWindow) {
        do {
            let keyMap = try KeymapLoader.load(from: url)

            // Count assigned mappings
            let assignedCount = keyMap.map.filter { $0 != 0xFFFF }.count
            let userKeyCount = keyMap.userKeys.count

            if keyMap.warnings.isEmpty {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = TTL("dialog.loadKeymap.success")
                alert.informativeText = String(
                    format: TTL("dialog.loadKeymap.successDetail"),
                    assignedCount, userKeyCount
                )
                alert.beginSheetModal(for: parentWindow)
            } else {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = TTL("dialog.loadKeymap.warning")
                alert.informativeText = keyMap.warnings.joined(separator: "\n")
                alert.beginSheetModal(for: parentWindow)
            }

            // Notify the active window controller about the loaded keymap
            if let wc = activeWindowController {
                wc.applyKeyMap(keyMap)
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = TTL("dialog.loadKeymap.error")
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: parentWindow)
        }
    }

    @objc func openConfigFolder(_ sender: Any?) {
        let configManager = ConfigPersistenceManager()
        let dir = configManager.appSupportDirectory
        // Ensure directory exists before opening
        try? configManager.ensureDirectory()
        NSWorkspace.shared.open(dir)
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
        panel.title = TTL("dialog.macro.title")
        panel.message = TTL("dialog.macro.message")
        panel.beginSheetModal(for: wc.window!) { response in
            guard response == .OK, let url = panel.url else { return }
            wc.runMacro(at: url)
        }
    }

    @objc func stopMacro(_ sender: Any?) {
        activeWindowController?.stopMacro()
    }

    /// Reset window title to the default, clearing any remote-set title (port of ID_CONTROL_RESETTITLE)
    @objc func resetRemoteTitle(_ sender: Any?) {
        guard let wc = activeWindowController else { return }
        // Reset emulator-side stored titles
        wc.terminalEmulator.windowTitle = wc.settings.title
        wc.terminalEmulator.iconTitle = wc.settings.title
        // Reset the actual window title & miniwindow title
        wc.window?.title = wc.settings.title
        wc.window?.miniwindowTitle = wc.settings.title
    }

    /// Toggle TEK 4014 emulation window (port of ID_CONTROL_OPENTEKWIN / ID_CONTROL_CLOSETEKWIN)
    private var tekWindowController: TEKWindowController?

    @objc func toggleTEKWindow(_ sender: Any?) {
        if let tek = tekWindowController, tek.window?.isVisible == true {
            tek.close()
            tekWindowController = nil
        } else {
            let tek = TEKWindowController(settings: settings)
            tek.showWindow(self)
            tekWindowController = tek
        }
    }

    /// Show/hide the macro status panel (port of ID_CONTROL_MACROWINDOW)
    @objc func showMacroWindow(_ sender: Any?) {
        guard let wc = activeWindowController, let interpreter = wc.macroInterpreter else { return }
        // Re-show the interpreter's own status panel (brings it to front)
        let macroName = interpreter.macroFileName.isEmpty ? "Macro" : interpreter.macroFileName
        interpreter.statusPanel.show(macroName: macroName)
    }

    @objc func replayLog(_ sender: Any?) {
        guard let wc = activeWindowController else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .log]
        panel.title = TTL("dialog.replayLog.title")
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
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true

        let label = NSTextField(labelWithString: TTL("dialog.broadcast.label"))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = TTL("dialog.broadcast.placeholder")
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.target = self
        textField.action = #selector(broadcastFieldAction(_:))
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        broadcastTextField = textField

        let sendButton = NSButton(title: TTL("dialog.broadcast.send"), target: self, action: #selector(broadcastSendAction(_:)))
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

        // Content-driven panel sizing
        let vc = NSViewController()
        vc.view = contentView
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.contentViewController = vc
        panel.title = TTL("menu.control.broadcast")
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
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
        let bothItem = NSMenuItem(title: TTL("menu.code.both"), action: nil, keyEquivalent: "")
        setSymbol("arrow.left.arrow.right", for: bothItem)
        bothItem.submenu = makeEncodingSubmenu(direction: 0)
        menu.addItem(bothItem)

        // "Receive" submenu
        let recvItem = NSMenuItem(title: TTL("menu.code.receive"), action: nil, keyEquivalent: "")
        setSymbol("arrow.down.circle", for: recvItem)
        recvItem.submenu = makeEncodingSubmenu(direction: 1)
        menu.addItem(recvItem)

        // "Send" submenu
        let sendItem = NSMenuItem(title: TTL("menu.code.send"), action: nil, keyEquivalent: "")
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
            .unicode:    TTL("menu.code.group.unicode"),
            .japanese:   TTL("menu.code.group.japanese"),
            .chinese:    TTL("menu.code.group.chinese"),
            .korean:     TTL("menu.code.group.korean"),
            .western:    TTL("menu.code.group.western"),
            .dosWindows: TTL("menu.code.group.dosWindows"),
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
        case #selector(showMacroWindow(_:)):
            return activeWindowController?.macroInterpreter != nil

        // Edit menu: paste with CR requires clipboard content
        case #selector(pasteCR(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        // Edit menu: deselect requires active selection
        case #selector(deselect(_:)):
            return activeWindowController?.terminalEmulator.buffer.selection.isActive == true
        case #selector(selectScreen(_:)):
            return hasWindow

        // TEK window printing: enabled only when TEK window is visible
        case #selector(printTEKWindow(_:)):
            return tekWindowController?.window?.isVisible == true

        // Control menu: reset remote title
        case #selector(resetRemoteTitle(_:)):
            return hasWindow
        // Control menu: TEK window toggle - update title based on state
        case #selector(toggleTEKWindow(_:)):
            if tekWindowController?.window?.isVisible == true {
                menuItem.title = TTL("menu.control.closeTekWindow")
            } else {
                menuItem.title = TTL("menu.control.tekWindow")
            }
            return true

        // Log menu items: enabled only when logging is active
        case #selector(pauseLog(_:)):
            let logState = activeWindowController?.logger.state ?? .inactive
            if logState == .paused {
                menuItem.title = TTL("menu.file.resumeLog")
            } else {
                menuItem.title = TTL("menu.file.pauseLog")
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
        case #selector(minimizeAllWindows(_:)),
             #selector(cascadeAllWindows(_:)),
             #selector(tileWindowsVertically(_:)),
             #selector(tileWindowsHorizontally(_:)),
             #selector(restoreAllWindows(_:)):
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
        // ── NSPanel ベースのモーダルダイアログ ──
        // NSAlert は accessoryView の Auto Layout を破壊するため使用不可
        let helper = ConnectionDialogHelper()

        let m = DialogLayout.margin
        let innerM = DialogLayout.innerMargin

        // パネルを先に作成し、既存の contentView にサブビューを追加する
        // （contentView を置き換えるとウィンドウのフレーム管理が壊れる）
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        panel.title = TTL("dialog.connection.title")
        panel.isReleasedWhenClosed = false

        guard let root = panel.contentView else { return }

        // helper をパネルに関連付けて保持（ラジオボタンの target/action 用）
        objc_setAssociatedObject(panel, "helper", helper, .OBJC_ASSOCIATION_RETAIN)

        // ── TCP/IP セクション ──

        // Row 1: [TCP/IP radio] [Host:] [combobox]
        let tcpRadio = NSView.makeRadioButton(TTL("dialog.connection.tcpip"), tag: 0)
        tcpRadio.target = helper
        tcpRadio.action = #selector(ConnectionDialogHelper.connectionTypeChanged(_:))
        tcpRadio.state = (settings.portType == .tcpip || settings.portType == .file || settings.portType == .namedPipe) ? .on : .off

        let hostLabel = NSView.makeLabel(TTL("dialog.connection.host"))

        let hostCombo = NSComboBox()
        hostCombo.translatesAutoresizingMaskIntoConstraints = false
        hostCombo.isEditable = true
        hostCombo.completes = true
        hostCombo.stringValue = settings.hostname
        hostCombo.placeholderString = TTL("dialog.connection.hostPlaceholder")
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
        let serviceLabel = NSView.makeLabel(TTL("dialog.connection.service"))

        let telnetRadio = NSView.makeRadioButton(TTL("dialog.connection.telnet"), tag: 0)
        telnetRadio.target = helper
        telnetRadio.action = #selector(ConnectionDialogHelper.serviceChanged(_:))
        telnetRadio.state = (settings.serviceType == .telnet) ? .on : .off
        helper.telnetRadio = telnetRadio

        let tcpPortLabel = NSView.makeLabel(TTL("dialog.connection.tcpPort"))

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

        // Row 3: [SSH radio]  [SSH version:] [popup]
        let sshRadio = NSView.makeRadioButton("SSH", tag: 1)
        sshRadio.target = helper
        sshRadio.action = #selector(ConnectionDialogHelper.serviceChanged(_:))
        sshRadio.state = (settings.serviceType == .ssh) ? .on : .off
        helper.sshRadio = sshRadio

        let sshVerLabel = NSView.makeLabel(TTL("dialog.connection.sshVersion"))
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

        // Row 4: [Other radio]  [IP version:] [popup]
        let otherRadio = NSView.makeRadioButton(TTL("dialog.connection.other"), tag: 2)
        otherRadio.target = helper
        otherRadio.action = #selector(ConnectionDialogHelper.serviceChanged(_:))
        otherRadio.state = (settings.serviceType == .other) ? .on : .off
        helper.otherRadio = otherRadio

        let ipVerLabel = NSView.makeLabel(TTL("dialog.connection.ipVersion"))

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

        // ラジオボタンの最小幅を揃える
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

        // TCP/IP グループボックス — tcpStack を直接 addSubview し、NSBox に対して制約
        let tcpBox = NSBox()
        tcpBox.translatesAutoresizingMaskIntoConstraints = false
        tcpBox.titlePosition = .noTitle
        tcpBox.addSubview(tcpStack)
        root.addSubview(tcpBox)

        NSLayoutConstraint.activate([
            tcpStack.topAnchor.constraint(equalTo: tcpBox.topAnchor, constant: innerM),
            tcpStack.leadingAnchor.constraint(equalTo: tcpBox.leadingAnchor, constant: innerM),
            tcpStack.trailingAnchor.constraint(lessThanOrEqualTo: tcpBox.trailingAnchor, constant: -innerM),
            tcpStack.bottomAnchor.constraint(equalTo: tcpBox.bottomAnchor, constant: -innerM),
        ])

        // サービス行をホストコンボボックス列に揃える
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

        // tcpRadio のみ先に登録（serialRadio/shellRadio は後で追加）
        helper.tcpRadio = tcpRadio

        // ── Serial セクション ──
        let serialRadio = NSView.makeRadioButton(TTL("dialog.connection.serial"), tag: 1)
        serialRadio.target = helper
        serialRadio.action = #selector(ConnectionDialogHelper.connectionTypeChanged(_:))
        serialRadio.state = (settings.portType == .serial) ? .on : .off
        helper.serialRadio = serialRadio

        let serialPortLabel = NSView.makeLabel(TTL("dialog.connection.serialPort"))

        let serialPortPopup = NSPopUpButton()
        serialPortPopup.translatesAutoresizingMaskIntoConstraints = false
        serialPortPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let serialPorts = findSerialPorts()
        for port in serialPorts {
            serialPortPopup.addItem(withTitle: port)
        }
        if serialPorts.isEmpty {
            serialPortPopup.addItem(withTitle: TTL("dialog.serialPort.noPortsFound"))
        }
        if !settings.serialPort.isEmpty {
            serialPortPopup.selectItem(withTitle: settings.serialPort)
        }

        let serialRow = NSStackView(views: [serialRadio, serialPortLabel, serialPortPopup])
        serialRow.translatesAutoresizingMaskIntoConstraints = false
        serialRow.orientation = .horizontal
        serialRow.spacing = DialogLayout.labelTrailing
        serialRow.alignment = .firstBaseline

        let serialBox = NSBox()
        serialBox.translatesAutoresizingMaskIntoConstraints = false
        serialBox.titlePosition = .noTitle
        serialBox.addSubview(serialRow)
        root.addSubview(serialBox)

        NSLayoutConstraint.activate([
            serialRow.topAnchor.constraint(equalTo: serialBox.topAnchor, constant: innerM),
            serialRow.leadingAnchor.constraint(equalTo: serialBox.leadingAnchor, constant: innerM),
            serialRow.trailingAnchor.constraint(equalTo: serialBox.trailingAnchor, constant: -innerM),
            serialRow.bottomAnchor.constraint(equalTo: serialBox.bottomAnchor, constant: -innerM),
        ])

        helper.serialControls = [serialPortLabel, serialPortPopup]

        // ── Local Shell セクション ──
        let shellRadio = NSView.makeRadioButton(TTL("dialog.connection.localShell"), tag: 2)
        shellRadio.target = helper
        shellRadio.action = #selector(ConnectionDialogHelper.connectionTypeChanged(_:))
        shellRadio.state = (settings.portType == .localShell) ? .on : .off
        helper.shellRadio = shellRadio

        let shellPathLabel = NSView.makeLabel(TTL("dialog.connection.shellPath"))
        let defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellPathField = NSView.makeTextField(
            value: settings.localShellPath.isEmpty ? defaultShell : settings.localShellPath)
        shellPathField.placeholderString = defaultShell
        shellPathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        shellPathField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let shellRow = NSStackView(views: [shellRadio, shellPathLabel, shellPathField])
        shellRow.translatesAutoresizingMaskIntoConstraints = false
        shellRow.orientation = .horizontal
        shellRow.spacing = DialogLayout.labelTrailing
        shellRow.alignment = .firstBaseline

        let shellBox = NSBox()
        shellBox.translatesAutoresizingMaskIntoConstraints = false
        shellBox.titlePosition = .noTitle
        shellBox.addSubview(shellRow)
        root.addSubview(shellBox)

        NSLayoutConstraint.activate([
            shellRow.topAnchor.constraint(equalTo: shellBox.topAnchor, constant: innerM),
            shellRow.leadingAnchor.constraint(equalTo: shellBox.leadingAnchor, constant: innerM),
            shellRow.trailingAnchor.constraint(equalTo: shellBox.trailingAnchor, constant: -innerM),
            shellRow.bottomAnchor.constraint(equalTo: shellBox.bottomAnchor, constant: -innerM),
        ])

        helper.localShellControls = [shellPathLabel, shellPathField]

        // ── セパレータ ──
        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        root.addSubview(separator)

        // ── ボタンバー: [spacer] [Cancel] [OK] ──
        let okButton = NSView.makePushButton(TTL("dialog.connection.ok"), keyEquivalent: "\r")
        let cancelButton = NSView.makePushButton(TTL("dialog.connection.cancel"), keyEquivalent: "\u{1b}")

        let buttonSpacer = NSView()
        buttonSpacer.translatesAutoresizingMaskIntoConstraints = false
        buttonSpacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)

        let buttonBar = NSStackView(views: [buttonSpacer, cancelButton, okButton])
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.orientation = .horizontal
        buttonBar.spacing = DialogLayout.buttonSpacing
        buttonBar.alignment = .centerY
        root.addSubview(buttonBar)

        // ── メインレイアウト: root に対して制約を張る ──
        NSLayoutConstraint.activate([
            // TCP/IP ボックス（最上部）
            tcpBox.topAnchor.constraint(equalTo: root.topAnchor, constant: m),
            tcpBox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            tcpBox.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),

            // Serial ボックス
            serialBox.topAnchor.constraint(equalTo: tcpBox.bottomAnchor, constant: innerM),
            serialBox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            serialBox.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),

            // Local Shell ボックス
            shellBox.topAnchor.constraint(equalTo: serialBox.bottomAnchor, constant: innerM),
            shellBox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            shellBox.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),

            // セパレータ
            separator.topAnchor.constraint(equalTo: shellBox.bottomAnchor, constant: m),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            // ボタンバー
            buttonBar.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: m * 0.75),
            buttonBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            buttonBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),
            buttonBar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -m * 0.75),

            // 最小幅
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
        ])

        // 初期有効/無効状態を適用
        let activeTag: Int
        switch settings.portType {
        case .serial: activeTag = 1
        case .localShell: activeTag = 2
        default: activeTag = 0
        }
        for ctrl in helper.tcpControls { ctrl.isEnabled = (activeTag == 0) }
        for ctrl in helper.serialControls { ctrl.isEnabled = (activeTag == 1) }
        for ctrl in helper.localShellControls { ctrl.isEnabled = (activeTag == 2) }

        // シリアルポートが無い場合は Serial ラジオを無効化
        if serialPorts.isEmpty {
            serialRadio.isEnabled = false
            if settings.portType == .serial {
                tcpRadio.state = .on
                serialRadio.state = .off
                for ctrl in helper.tcpControls { ctrl.isEnabled = true }
                for ctrl in helper.serialControls { ctrl.isEnabled = false }
            }
        }

        // ボタンアクション: レスポンダチェーン経由で AppDelegate に到達
        okButton.target = nil
        okButton.action = #selector(AppDelegate.connectionDialogOK(_:))
        cancelButton.target = nil
        cancelButton.action = #selector(AppDelegate.connectionDialogCancel(_:))

        // Auto Layout でサイズを決定してからセンタリング
        root.layoutSubtreeIfNeeded()
        panel.setContentSize(root.fittingSize)
        panel.center()

        let response = NSApp.runModal(for: panel)
        panel.close()

        if response == .OK {
            let wc = targetWC ?? newTerminalWindow()

            if wc.connectionManager.state != .disconnected {
                wc.disconnect()
            }

            if shellRadio.state == .on {
                let path = shellPathField.stringValue
                if !path.isEmpty && path != defaultShell {
                    settings.localShellPath = path
                }
                settings.portType = .localShell
                wc.connectLocalShell()
            } else if serialRadio.state == .on {
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

    @objc private func connectionDialogOK(_ sender: NSButton) {
        NSApp.stopModal(withCode: .OK)
    }

    @objc private func connectionDialogCancel(_ sender: NSButton) {
        NSApp.stopModal(withCode: .cancel)
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
            currentSetupDialog = vc.presentAsModal(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    /// 現在開いている設定ダイアログやフォントパネルをOK（値保存）で閉じる
    private func dismissCurrentSetupSheet() {
        // フォントパネルが開いていれば閉じる
        let fontPanel = NSFontPanel.shared
        if fontPanel.isVisible {
            fontPanel.orderOut(nil)
        }
        // 設定ダイアログが開いていれば閉じる
        if let sheet = currentSetupDialog {
            if let parent = sheet.sheetParent {
                // シートとして表示されている場合
                parent.endSheet(sheet, returnCode: .OK)
            } else if sheet.isVisible {
                // モーダルウィンドウとして表示されている場合
                NSApplication.shared.stopModal(withCode: .OK)
                sheet.close()
            }
        }
        currentSetupDialog = nil
    }

    private func showTerminalSetupDialog() {
        dismissCurrentSetupSheet()
        let vc = TerminalSetupViewController(settings: settings)
        vc.okHandler = { [weak self] in
            self?.activeWindowController?.applySettings()
        }
        if let win = activeWindowController?.window {
            currentSetupDialog = vc.presentAsModal(on: win)
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
            currentSetupDialog = vc.presentAsModal(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: Keyboard Setup Dialog (port of ttpdlg Keyboard dialog)

    private func showKeyboardSetupDialog() {
        dismissCurrentSetupSheet()
        let vc = KeyboardSetupDialogController(settings: settings)
        vc.okHandler = { [weak self] in
            // Apply terminal ID to emulator
            if let self = self {
                self.activeWindowController?.terminalEmulator.terminalID = self.settings.terminalID
                self.activeWindowController?.applySettings()
            }
        }
        if let win = activeWindowController?.window {
            currentSetupDialog = vc.presentAsModal(on: win)
        } else {
            _ = vc.presentModal()
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
            currentSetupDialog = vc.presentAsModal(on: win)
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
            currentSetupDialog = vc.presentAsModal(on: win)
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
            // 排他制御: showAsSheet（モーダルウィンドウ）の戻り値を currentSetupDialog に代入
            currentSetupDialog = controller.showAsSheet(on: win)
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
            currentSetupDialog = vc.presentAsModal(on: win)
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
            currentSetupDialog = vc.presentAsModal(on: win)
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
            currentSetupDialog = vc.presentAsModal(on: win)
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
            currentSetupDialog = vc.presentAsModal(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: SSH Key Generation Dialog

    private func showSSHKeyGenDialog() {
        dismissCurrentSetupSheet()
        let vc = SSHKeyGenDialogController()
        if let win = activeWindowController?.window {
            currentSetupDialog = vc.presentAsModal(on: win)
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
            currentSetupDialog = vc.presentAsModal(on: win)
        } else {
            _ = vc.presentModal()
        }
    }

    // MARK: SSH SCP Dialog

    private func showSSHSCPDialog() {
        guard let wc = activeWindowController else { return }

        // 安全キャストで SSH 接続を取得（失敗時は警告表示）
        guard let ssh = wc.connectionManager.currentConnection as? SSHConnection else {
            let alert = NSAlert()
            alert.messageText = TTL("dialog.scp.error.notConnected")
            alert.alertStyle = .warning
            alert.addButton(withTitle: TTL("OK"))
            if let win = wc.window {
                alert.beginSheetModal(for: win, completionHandler: nil)
            } else {
                alert.runModal()
            }
            return
        }
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
            currentSetupDialog = vc.presentAsModal(on: win)
        }
    }

    private func showSCPErrorAlert(_ detail: String) {
        let alert = NSAlert()
        alert.messageText = "SCP"  // protocol name, not localized
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: TTL("OK"))
        alert.runModal()
    }

    private func findSerialPorts() -> [String] {
        return SerialPortSetupViewController.findSerialPorts()
    }
}
#endif
