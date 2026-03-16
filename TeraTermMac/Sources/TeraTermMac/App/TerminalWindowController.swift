/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of vtwin.cpp to Swift/macOS
 * Main terminal window controller - integrates all components
 */

#if canImport(AppKit)
import AppKit

// [KEY-INPUT-AUDIT]
// keyDown 実装: TerminalView.swift:832 (override keyDown)
// keyDown→delegate: TerminalView.swift:868 → terminalDelegate?.terminalViewDidReceiveKeyEvent
// insertText (IME): TerminalView.swift:1169 → terminalDelegate?.terminalViewDidReceiveKeyEvent
// delegate処理: TerminalWindowController.swift:859 → keyboardHandler.processKeyEvent → connectionManager.send
// flagsChanged: TerminalView.swift:875 (空実装)
// monitor 登録: なし（keyDownオーバーライドで直接受け取り）
// observer 登録: AppDelegate.swift:146 (NSWindow.willCloseNotification) × 解除なし（objectベースで自動解除される）
// Timer 生成: TerminalView.swift:813 (cursorBlinkTimer) × invalidateあり
// Timer 生成: TerminalView.swift:1127 (refreshTimer/DispatchSourceTimer) × cancelあり
// Timer 生成: TerminalWindowController.swift:585 (resizeHideTimer) × invalidateあり
// Timer 生成: TerminalWindowController.swift:1272 (macroRecvTimer) × invalidateあり
// 送信キュー: なし（メインスレッドで同期送信）★問題箇所

// [KEY-INPUT-ROOT-CAUSE]
// 原因1: TerminalWindowController.terminalViewDidReceiveKeyEvent() で connectionManager.send() を
//         メインスレッド上で同期的に呼んでいる。SerialConnection.send() と LocalShellConnection.send() は
//         write() を同期ループで呼ぶため、ネットワーク遅延やバッファフルでメインスレッドがブロックされる。
//         ★根本原因
// 原因2: TerminalWindowController に deinit がなく、windowWillClose で resizeHideTimer と
//         macroRecvTimer の invalidate が漏れている。Timer リーク・再接続時の累積の可能性。要注意
// 原因3: AppDelegate.swift:146 の NotificationCenter observer が addObserver(forName:object:queue:)
//         形式で登録。戻り値を保持していないため removeObserver できなかった。→ 修正済み
// 原因4: TelnetProtocol の binaryMode/echoMode/suppressGA が processIncoming()(メインスレッド)と
//         escapeData()(sendQueue)から保護なく読み書きされていた → NSLock で保護済み

// [KEY-INPUT-FIX-PLAN]
// 修正1: TerminalWindowController.swift:859 キー送信をメインスレッドで同期実行 → 専用sendQueueで非同期送信
// 修正2: TerminalWindowController.swift:新規 deinit追加 → resizeHideTimer/macroRecvTimer を確実にinvalidate
// 修正3: TerminalWindowController.swift:590 windowWillClose → Timer の invalidate を追加
// 修正4: SerialConnection/LocalShellConnection の send() もwriteQueueで非同期化
// 修正5: TerminalView.swift insertText で文字ごとにデリゲート呼び出し → 一括送信に最適化

// MARK: - Terminal Window Controller (port of CVTWindow)

class TerminalWindowController: NSWindowController {
    // Core components
    private(set) var terminalEmulator: TerminalEmulator!
    private(set) var terminalView: TerminalView!
    private(set) var connectionManager: ConnectionManager!
    private(set) var keyboardHandler: KeyboardHandler!
    private(set) var telnetProtocol: TelnetProtocol!
    private(set) var fileTransferManager: FileTransferManager!
    private(set) var logger: TerminalLogger!
    private(set) var protocolTransferPanel = ProtocolTransferPanel()
    private var packetCount: Int = 0

    // Settings
    var settings: TerminalSettings

    // State
    private var useTelnet: Bool = false
    private(set) var isConnected: Bool = false

    // Key input send queue — offloads network I/O from the main thread
    // to prevent blocking UI during key input handling.
    private let sendQueue = DispatchQueue(
        label: "com.teraterm.TeraTermMac.sendQueue", qos: .userInteractive)

    // Resize tooltip
    private var resizeTooltipWindow: NSWindow?
    private var resizeTooltipLabel: NSTextField?
    private var resizeHideTimer: Timer?

    // Macro XPC manager for external macro app communication
    private(set) var macroXPCManager: MacroXPCManager?

    /// Window event queue for waitevent command
    /// Event types: 1=resize, 2=move, 3=close, 4=focus, 5=unfocus
    private(set) var pendingWindowEvents: [Int] = []
    private let windowEventLock = NSLock()

    // Macro file transfer state
    var macroTransferCompletion: ((Bool) -> Void)?
    var macroRecvFileHandle: FileHandle?
    var macroRecvAutoStopSec: Int = 0
    var macroRecvLastDataTime: Date?
    var macroRecvTimer: Timer?

    // MARK: - Initialization

    init(settings: TerminalSettings = TerminalSettings()) {
        self.settings = settings

        // Create a temporary window; real size set after font metrics are known
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = settings.title
        window.minSize = NSSize(width: 200, height: 100)
        window.isReleasedWhenClosed = false
        window.isRestorable = false

        // macOS HIG: OS標準の外観モードに追従
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.animationBehavior = .documentWindow

        super.init(window: window)

        setupComponents()
        setupTerminalView()

        window.delegate = self
        window.alphaValue = CGFloat(settings.windowAlpha)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        resizeHideTimer?.invalidate()
        resizeHideTimer = nil
        macroRecvTimer?.invalidate()
        macroRecvTimer = nil
        macroXPCManager?.disconnect()
        macroXPCManager = nil
    }

    // MARK: - Component Setup

    private func setupComponents() {
        terminalEmulator = TerminalEmulator(settings: settings)
        terminalEmulator.delegate = self

        connectionManager = ConnectionManager(settings: settings)
        connectionManager.delegate = self

        keyboardHandler = KeyboardHandler(settings: settings)

        telnetProtocol = TelnetProtocol()
        telnetProtocol.terminalType = settings.termType
        telnetProtocol.delegate = self

        fileTransferManager = FileTransferManager()

        logger = TerminalLogger(options: LogOptions.from(settings))
    }

    private func setupTerminalView() {
        guard let window = window else { return }

        // NSVisualEffectView provides macOS glass/vibrancy effect as the
        // window backdrop. TerminalView draws on top with a semi-transparent
        // background so the effect shows through.
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        window.contentView = visualEffect

        // Place TerminalView inside the visual effect view.
        // Scrollback is handled internally by TerminalBuffer / TerminalView.
        terminalView = TerminalView(frame: visualEffect.bounds)
        terminalView.autoresizingMask = [.width, .height]
        terminalView.buffer = terminalEmulator.buffer
        terminalView.settings = settings
        terminalView.terminalDelegate = self
        visualEffect.addSubview(terminalView)

        // With a standard (non-transparent) title bar, the content area
        // starts below the title bar, so no topInset is needed.
        terminalView.topInset = 0

        // Now that the view is in a window, compute font metrics and resize
        terminalView.updateFont()
        let preferredSize = terminalView.preferredSize(
            columns: settings.terminalWidth,
            rows: settings.terminalHeight
        )
        window.setContentSize(preferredSize)

        window.makeFirstResponder(terminalView)
    }

    // MARK: - Connection Actions

    func connectLocalShell() {
        connectionManager.connectLocalShell()

        // Tell the PTY about the current terminal size
        if let pty = connectionManager.currentConnection as? LocalShellConnection {
            let size = terminalView.terminalSize
            pty.resize(cols: UInt16(size.columns), rows: UInt16(size.rows))
        }

        updateWindowTitle()
    }

    func connectTCP(host: String, port: Int, telnet: Bool = false) {
        settings.hostname = host
        settings.defaultPort = port
        useTelnet = telnet
        connectionManager.connect(type: .tcpip(host: host, port: port))
        updateWindowTitle()
    }

    func connectSSH(host: String, port: Int, username: String, password: String,
                     authMethod: SSHAuthMethod, keyFile: String, forwardAgent: Bool) {
        settings.hostname = host
        settings.defaultPort = port
        useTelnet = false
        connectionManager.connect(type: .ssh(
            host: host, port: port, username: username, password: password,
            authMethod: authMethod, keyFile: keyFile, forwardAgent: forwardAgent))

        // Set initial PTY window size
        if let ssh = connectionManager.currentConnection as? SSHConnection {
            let size = terminalView.terminalSize
            ssh.resize(cols: UInt16(size.columns), rows: UInt16(size.rows))
        }

        updateWindowTitle()
    }

    func connectSerial(device: String) {
        settings.serialPort = device
        connectionManager.connect(type: .serial(
            device: device,
            baudRate: settings.baudRate,
            dataBits: settings.dataBits,
            parity: settings.parity,
            stopBits: settings.stopBits,
            flowControl: settings.flowControl
        ))
        updateWindowTitle()
    }

    func disconnect() {
        connectionManager.disconnect()
        isConnected = false
        updateWindowTitle()
    }

    // MARK: - Window Title

    private func updateWindowTitle() {
        var title = settings.title
        if isConnected {
            if let conn = connectionManager.currentConnection {
                if conn is LocalShellConnection {
                    title += " - " + TTL("window.title.localShell")
                } else if let ssh = conn as? SSHConnection {
                    title += " - \(ssh.username)@\(ssh.host):\(ssh.port) (SSH)"
                } else if let tcp = conn as? TCPConnection {
                    title += " - \(tcp.host):\(tcp.port)"
                } else if let serial = conn as? SerialConnection {
                    title += " - \(serial.device) \(serial.baudRate)bps"
                }
            }
        } else {
            title += " - [\(TTL("window.title.disconnected"))]"
        }
        window?.title = title
    }

    // MARK: - Log Actions

    func startLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "teraterm.log"
        panel.allowedContentTypes = [.plainText]

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            let opts = LogOptions.from(self.settings)
            _ = self.logger.startLogging(to: url.path, options: opts)
        }
    }

    /// Start logging with a pre-selected path and options (called from LogDialog).
    func startLog(path: String, options: LogOptions) {
        _ = logger.startLogging(to: path, options: options)
    }

    func stopLog() {
        logger.stopLogging()
    }

    // MARK: - File Transfer Actions

    func sendFile(protocol type: TransferProtocolType) {
        guard let win = window else { return }
        switch type {
        case .xmodem, .xmodemCRC, .xmodem1K:
            FileTransferDialogHelper.presentXMODEMSendPanel(on: win) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .send, url: url)
            }
        case .zmodem:
            FileTransferDialogHelper.presentMultiSendPanel(on: win, protocolType: .zmodem) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .send, url: url)
            }
        case .kermit:
            FileTransferDialogHelper.presentMultiSendPanel(on: win, protocolType: .kermit) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .send, url: url)
            }
        case .ymodem, .ymodemG:
            FileTransferDialogHelper.presentYMODEMSendPanel(on: win) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .send, url: url)
            }
        case .bplus:
            FileTransferDialogHelper.presentMultiSendPanel(on: win, protocolType: .bplus) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .send, url: url)
            }
        case .quickVAN:
            FileTransferDialogHelper.presentMultiSendPanel(on: win, protocolType: .quickVAN) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .send, url: url)
            }
        }
    }

    func receiveFile(protocol type: TransferProtocolType) {
        guard let win = window else { return }
        switch type {
        case .xmodem, .xmodemCRC, .xmodem1K:
            FileTransferDialogHelper.presentXMODEMReceivePanel(on: win) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .receive, url: url)
            }
        case .zmodem:
            FileTransferDialogHelper.presentMultiReceivePanel(on: win, protocolType: .zmodem) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .receive, url: url)
            }
        case .kermit:
            FileTransferDialogHelper.presentMultiReceivePanel(on: win, protocolType: .kermit) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .receive, url: url)
            }
        case .ymodem, .ymodemG:
            FileTransferDialogHelper.presentYMODEMReceivePanel(on: win) { [weak self] url in
                self?.startTransfer(.ymodem, direction: .receive, url: url)
            }
        case .bplus:
            FileTransferDialogHelper.presentMultiReceivePanel(on: win, protocolType: .bplus) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .receive, url: url)
            }
        case .quickVAN:
            FileTransferDialogHelper.presentMultiReceivePanel(on: win, protocolType: .quickVAN) { [weak self] url, proto in
                self?.startTransfer(proto, direction: .receive, url: url)
            }
        }
    }

    func kermitGet() {
        guard let win = window else { return }
        FileTransferDialogHelper.presentKermitGetDialog(on: win) { [weak self] remoteFileName in
            guard let self = self, let name = remoteFileName else { return }
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = name
            savePanel.beginSheetModal(for: win) { response in
                guard response == .OK, let url = savePanel.url else { return }
                self.fileTransferManager.delegate = self
                self.fileTransferManager.startKermitGet(remoteFileName: name, localPath: url.path)
                self.protocolTransferPanel.onCancel = { [weak self] in
                    self?.fileTransferManager.cancelTransfer()
                }
                self.protocolTransferPanel.show(fileName: name, protocolName: "Kermit Get")
            }
        }
    }

    func kermitFinish() {
        fileTransferManager.delegate = self
        fileTransferManager.startKermitFinish()
    }

    private func startTransfer(_ type: TransferProtocolType, direction: TransferDirection, url: URL) {
        fileTransferManager.delegate = self
        fileTransferManager.startTransfer(protocol: type, direction: direction, filePath: url.path)

        // Show protocol progress panel
        let protoName: String
        switch type {
        case .xmodem:    protoName = "XMODEM"
        case .xmodemCRC: protoName = "XMODEM-CRC"
        case .xmodem1K:  protoName = "XMODEM-1K"
        case .ymodem:    protoName = "YMODEM"
        case .ymodemG:   protoName = "YMODEM-G"
        case .zmodem:    protoName = "ZMODEM"
        case .kermit:    protoName = "Kermit"
        case .bplus:     protoName = "B-Plus"
        case .quickVAN:  protoName = "Quick-VAN"
        }
        let fileName = url.lastPathComponent
        protocolTransferPanel.onCancel = { [weak self] in
            self?.fileTransferManager.cancelTransfer()
        }
        protocolTransferPanel.show(fileName: fileName, protocolName: protoName)
    }

    // MARK: - Apply Settings to Active Window

    /// Apply all current settings immediately to the terminal window.
    /// Called when any settings dialog closes with OK.
    /// This ensures the frontmost active terminal reflects changes instantly.
    func applySettings() {
        // Push settings to all components (they hold references, but
        // some cache values that need explicit refresh)
        terminalView.settings = settings
        terminalEmulator.settings = settings
        keyboardHandler.settings = settings

        // Font and cell metrics
        terminalView.updateFont()

        // Terminal dimensions: resize window to match new column/row settings
        let preferredSize = terminalView.preferredSize(
            columns: settings.terminalWidth,
            rows: settings.terminalHeight
        )
        window?.setContentSize(preferredSize)

        // Resize the emulator buffer to match
        let viewSize = terminalView.terminalSize
        if viewSize.columns > 0 && viewSize.rows > 0 {
            terminalEmulator.resize(width: viewSize.columns, height: viewSize.rows)
        }

        // Window appearance
        window?.title = settings.title
        window?.alphaValue = CGFloat(settings.windowAlpha)

        // Cursor blink / shape — TerminalView reads from settings on draw,
        // but we trigger a refresh to pick up changes immediately
        terminalView.refresh()

        // Telnet terminal type
        telnetProtocol.terminalType = settings.termType

        // Notify the PTY of any size change
        if let pty = connectionManager.currentConnection as? LocalShellConnection {
            let size = terminalView.terminalSize
            if size.columns > 0 && size.rows > 0 {
                pty.resize(cols: UInt16(size.columns), rows: UInt16(size.rows))
            }
        } else if let ssh = connectionManager.currentConnection as? SSHConnection {
            let size = terminalView.terminalSize
            if size.columns > 0 && size.rows > 0 {
                ssh.resize(cols: UInt16(size.columns), rows: UInt16(size.rows))
            }
        }

        // Telnet NAWS update
        if useTelnet {
            let size = terminalView.terminalSize
            telnetProtocol.updateWindowSize(width: size.columns, height: size.rows)
        }
    }

    /// Apply a loaded keymap (.cnf) to the keyboard handler.
    func applyKeyMap(_ keyMap: KeyMap) {
        // Apply user-defined keys from the keymap
        for entry in keyMap.userKeys {
            let decoded = KeymapLoader.decodeUserKeyValue(entry.value)
            if let str = String(data: decoded, encoding: .utf8) {
                keyboardHandler.setUserDefinedKey(
                    keyCode: UInt16(entry.pcKeyCode),
                    modifiers: [],
                    value: str
                )
            }
        }
    }

    // MARK: - Terminal Actions

    func resetTerminal() {
        terminalEmulator.hardReset()
        terminalView.refresh()
    }

    func clearScreen() {
        terminalEmulator.buffer.eraseInDisplay(2)
        terminalEmulator.buffer.moveCursorTo(x: 0, y: 0)
        terminalView.refresh()
    }

    func clearBuffer() {
        terminalEmulator.buffer.eraseInDisplay(3)
        terminalEmulator.buffer.eraseInDisplay(2)
        terminalEmulator.buffer.moveCursorTo(x: 0, y: 0)
        terminalView.refresh()
    }

    func copyAsTable() {
        guard let text = terminalEmulator.buffer.getSelectedText() else { return }
        // Convert whitespace runs (2+ spaces) into tabs for spreadsheet pasting
        var result = ""
        for line in text.components(separatedBy: "\n") {
            let tabbed = line.replacingOccurrences(
                of: " {2,}", with: "\t",
                options: .regularExpression)
            if !result.isEmpty { result += "\n" }
            result += tabbed
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(result, forType: .string)
    }

    func resetPort() {
        connectionManager.resetPort()
        updateWindowTitle()
    }

    // MARK: - XPC Macro Management

    /// Launch TTLMacro.app and establish XPC connection for external macro execution.
    func connectMacroXPC(completion: @escaping (Bool) -> Void) {
        let manager = MacroXPCManager()
        manager.terminalController = self
        manager.fileTransferManager = fileTransferManager
        macroXPCManager = manager

        manager.connect { success in
            if !success {
                self.macroXPCManager = nil
            }
            completion(success)
        }
    }

    /// Disconnect from TTLMacro.app XPC service.
    func disconnectMacroXPC() {
        macroXPCManager?.disconnect()
        macroXPCManager = nil
    }

    // MARK: - Macro Actions

    private(set) var macroInterpreter: TTLInterpreter?

    func runMacro(at url: URL) {
        // Stop any running macro
        macroInterpreter?.stop()

        let interpreter = TTLInterpreter()
        interpreter.delegate = self
        do {
            try interpreter.loadScript(from: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = TTL("macro.error.title")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: TTL("OK"))
            if let win = window { alert.beginSheetModal(for: win) }
            return
        }

        interpreter.prescanLabels()

        interpreter.onComplete = { [weak self] in
            self?.macroInterpreter = nil
            self?.terminalEmulator.macroReceiveEnabled = false
            self?.terminalEmulator.macroReceiveBuffer = ""
        }
        interpreter.onError = { [weak self] msg, line in
            // Called when user chose "Stop" in the error dialog.
            self?.macroInterpreter = nil
            self?.terminalEmulator.macroReceiveEnabled = false
            self?.terminalEmulator.macroReceiveBuffer = ""
        }

        macroInterpreter = interpreter
        terminalEmulator.macroReceiveEnabled = true
        terminalEmulator.macroReceiveBuffer = ""
        interpreter.run()
    }

    func stopMacro() {
        macroInterpreter?.stop()
        macroInterpreter = nil
        terminalEmulator.macroReceiveEnabled = false
        terminalEmulator.macroReceiveBuffer = ""
    }

    // MARK: - Log Replay

    func replayLog(at url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        // Replay log data through the terminal emulator to reproduce the session
        let chunkSize = 4096
        let queue = DispatchQueue(label: "com.teraterm.replay")

        queue.async { [weak self] in
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                let chunk = data[offset..<end]
                DispatchQueue.main.async {
                    self?.terminalEmulator.processData(Data(chunk))
                }
                offset = end
                // Small delay for visual playback (≈ 115200 baud)
                Thread.sleep(forTimeInterval: 0.035)
            }
        }
    }

    // MARK: - Resize handling

    /// Notification posted when the terminal window is resized.
    /// `userInfo` contains "columns" and "rows" as Int values.
    static let terminalDidResizeNotification = Notification.Name("TerminalWindowControllerDidResize")

    private func handleResize() {
        let size = terminalView.terminalSize
        guard size.columns > 0 && size.rows > 0 else { return }

        terminalEmulator.resize(width: size.columns, height: size.rows)

        if let pty = connectionManager.currentConnection as? LocalShellConnection {
            pty.resize(cols: UInt16(size.columns), rows: UInt16(size.rows))
        } else if let ssh = connectionManager.currentConnection as? SSHConnection {
            ssh.resize(cols: UInt16(size.columns), rows: UInt16(size.rows))
        }

        if useTelnet {
            telnetProtocol.updateWindowSize(width: size.columns, height: size.rows)
        }

        terminalView.refresh()

        // 設定ダイアログが開いている場合にサイズ変更を通知する
        NotificationCenter.default.post(
            name: Self.terminalDidResizeNotification,
            object: self,
            userInfo: ["columns": size.columns, "rows": size.rows]
        )
    }
}

// MARK: - NSWindowDelegate

extension TerminalWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        handleResize()
        if window?.inLiveResize == true {
            showResizeTooltip()
        }
        enqueueWindowEvent(1) // resize
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        // Keep tooltip visible briefly after resize ends
        resizeHideTimer?.invalidate()
        resizeHideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.hideResizeTooltip()
        }
    }

    func windowWillClose(_ notification: Notification) {
        hideResizeTooltip()
        resizeHideTimer?.invalidate()
        resizeHideTimer = nil
        macroRecvTimer?.invalidate()
        macroRecvTimer = nil
        enqueueWindowEvent(3) // close
        disconnect()
        logger.stopLogging()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.alphaValue = CGFloat(settings.windowAlpha)
        if let data = keyboardHandler.focusIn() {
            sendQueue.async { [weak self] in
                self?.connectionManager.send(data)
            }
        }
        enqueueWindowEvent(4) // focus
    }

    func windowDidResignKey(_ notification: Notification) {
        window?.alphaValue = CGFloat(settings.windowAlphaInactive)
        if let data = keyboardHandler.focusOut() {
            sendQueue.async { [weak self] in
                self?.connectionManager.send(data)
            }
        }
        enqueueWindowEvent(5) // unfocus
    }

    /// Add windowDidMove delegate to track move events
    func windowDidMove(_ notification: Notification) {
        enqueueWindowEvent(2) // move
    }

    /// Enqueue a window event for the waitevent command
    private func enqueueWindowEvent(_ eventType: Int) {
        windowEventLock.lock()
        pendingWindowEvents.append(eventType)
        // Keep only last 32 events to prevent unbounded growth
        if pendingWindowEvents.count > 32 {
            pendingWindowEvents.removeFirst(pendingWindowEvents.count - 32)
        }
        windowEventLock.unlock()

        // Push event to TTLMacro via XPC (non-blocking, fire-and-forget)
        macroXPCManager?.macroService?.notifyTerminalEvent(eventType: eventType, reply: {})
    }

    /// Dequeue the oldest window event, returns 0 if none
    func dequeueWindowEvent() -> Int {
        windowEventLock.lock()
        defer { windowEventLock.unlock() }
        if pendingWindowEvents.isEmpty { return 0 }
        return pendingWindowEvents.removeFirst()
    }

    // MARK: - Resize Tooltip

    private func showResizeTooltip() {
        let size = terminalView.terminalSize
        let text = "\(size.columns) x \(size.rows)"

        if resizeTooltipWindow == nil {
            let label = NSTextField(labelWithString: text)
            label.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.isBezeled = false
            label.isEditable = false
            label.drawsBackground = false

            let padding: CGFloat = 12
            let labelSize = label.intrinsicContentSize
            let panelWidth = labelSize.width + padding * 2
            let panelHeight = labelSize.height + padding

            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false

            let bgView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
            bgView.wantsLayer = true
            bgView.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.85).cgColor
            bgView.layer?.cornerRadius = 10
            bgView.layer?.masksToBounds = true
            panel.contentView = bgView

            label.frame = NSRect(x: padding, y: padding / 2, width: labelSize.width, height: labelSize.height)
            bgView.addSubview(label)

            resizeTooltipWindow = panel
            resizeTooltipLabel = label
        }

        // Update text and refit
        resizeTooltipLabel?.stringValue = text
        resizeTooltipLabel?.sizeToFit()

        let padding: CGFloat = 12
        let labelSize = resizeTooltipLabel?.intrinsicContentSize ?? .zero
        let panelWidth = labelSize.width + padding * 2
        let panelHeight = labelSize.height + padding
        resizeTooltipLabel?.frame = NSRect(x: padding, y: padding / 2, width: labelSize.width, height: labelSize.height)

        // Position at center of window
        if let mainWindow = window {
            let windowFrame = mainWindow.frame
            let tooltipX = windowFrame.midX - panelWidth / 2
            let tooltipY = windowFrame.midY - panelHeight / 2
            resizeTooltipWindow?.setFrame(NSRect(x: tooltipX, y: tooltipY, width: panelWidth, height: panelHeight), display: true)
        }

        resizeTooltipWindow?.orderFront(nil)

        // Cancel any pending hide
        resizeHideTimer?.invalidate()
        resizeHideTimer = nil
    }

    private func hideResizeTooltip() {
        resizeHideTimer?.invalidate()
        resizeHideTimer = nil
        resizeTooltipWindow?.orderOut(nil)
    }
}

// MARK: - TerminalEmulatorDelegate

extension TerminalWindowController: TerminalEmulatorDelegate {
    func terminalDidUpdateDisplay() {
        terminalView.modes = terminalEmulator.modes
        // 新しいデータ到着時、スクロール位置を最下行に戻す
        // (autoScrollOnOutput 設定に基づく)
        if settings.autoScrollOnOutput {
            terminalView.scrollToBottom()
        }
        terminalView.refresh()
    }

    func terminalDidChangeCursorPosition(x: Int, y: Int) {
        terminalView.refresh()
    }

    func terminalDidChangeTitle(_ title: String) {
        window?.title = title
    }

    func terminalDidChangeIconTitle(_ title: String) {
        window?.miniwindowTitle = title
    }

    func terminalDidRing() {
        switch settings.beepType {
        case .system:
            NSSound.beep()
        case .visual:
            let overlay = NSView(frame: terminalView.bounds)
            overlay.wantsLayer = true
            overlay.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
            terminalView.addSubview(overlay)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                overlay.removeFromSuperview()
            }
        case .none:
            break
        }
    }

    func terminalDidRequestResize(width: Int, height: Int) {
        let size = terminalView.preferredSize(columns: width, rows: height)
        window?.setContentSize(size)
    }

    func terminalDidRequestResponse(_ data: Data) {
        if useTelnet {
            let escaped = telnetProtocol.escapeData(data)
            connectionManager.send(escaped)
        } else {
            connectionManager.send(data)
        }
    }

    func terminalDidChangeMode(_ modes: TerminalModes) {
        keyboardHandler.modes = modes
        terminalView.modes = modes
        terminalView.refresh()
    }

    func terminalDidRequestPaste() {
        if let text = NSPasteboard.general.string(forType: .string) {
            sendPasteText(text)
        }
    }

    func terminalDidRequestCopy(_ text: String) {
        if !text.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    func terminalDidChangeColors() {
        terminalView.refresh()
    }
}

// MARK: - ConnectionDelegate

extension TerminalWindowController: ConnectionDelegate {
    func connectionDidConnect() {
        isConnected = true
        updateWindowTitle()

        if settings.beepOnConnect {
            NSSound.beep()
        }
    }

    func connectionDidDisconnect() {
        isConnected = false
        updateWindowTitle()
    }

    func connectionDidReceiveData(_ data: Data) {
        logger.logData(data)

        // Macro recvfile: write incoming data directly to file
        if let handle = macroRecvFileHandle {
            handle.write(data)
            macroRecvLastDataTime = Date()
            return
        }

        if useTelnet {
            let terminalData = telnetProtocol.processIncoming(data)
            if !terminalData.isEmpty {
                if fileTransferManager.isTransferActive {
                    fileTransferManager.processIncomingData(terminalData)
                } else {
                    terminalEmulator.processData(terminalData)
                }
            }
        } else {
            if fileTransferManager.isTransferActive {
                fileTransferManager.processIncomingData(data)
            } else {
                terminalEmulator.processData(data)
            }
        }
    }

    func connectionDidFail(error: Error) {
        isConnected = false
        updateWindowTitle()

        // Port of original Tera Term MessageBox error dialogs.
        // The original used MB_TASKMODAL | MB_ICONEXCLAMATION for connection
        // errors, presented via CommDlgProc / PostMessage in commlib.c.
        // macOS equivalent: NSAlert sheet modal with .warning style.
        let alert = NSAlert()
        alert.addButton(withTitle: TTL("error.connection.ok"))

        if let connError = error as? ConnectionError {
            alert.messageText = connError.alertTitle
            alert.informativeText = connError.localizedDescription

            // Match original Tera Term icon style:
            // DNS/host errors and SSH-not-supported use .warning (MB_ICONEXCLAMATION)
            // Connection refused/timeout use .warning
            // Fatal errors (stream/pty failed) use .critical (MB_ICONERROR)
            switch connError {
            case .streamCreationFailed, .ptyCreationFailed, .sendFailed,
                 .sshNotFound, .sshForkFailed:
                alert.alertStyle = .critical
            default:
                alert.alertStyle = .warning
            }
        } else {
            alert.messageText = TTL("error.connection.title")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
        }

        if let win = window {
            alert.beginSheetModal(for: win)
        }
    }

    func connectionStateChanged(_ state: ConnectionState) {
        // Update UI if needed
    }
}

// MARK: - TerminalViewDelegate

extension TerminalWindowController: TerminalViewDelegate {
    func terminalViewDidReceiveKeyEvent(_ event: TerminalKeyEvent) {
        guard let data = keyboardHandler.processKeyEvent(event) else { return }

        if settings.localEcho {
            terminalEmulator.processData(data)
        }

        // Send data on a background queue to avoid blocking the main thread.
        // Network I/O (especially serial/PTY write) can stall, and doing it
        // synchronously on the main thread was the root cause of progressive
        // key input lag.
        let telnet = useTelnet
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            if telnet {
                let escaped = self.telnetProtocol.escapeData(data)
                self.connectionManager.send(escaped)
            } else {
                self.connectionManager.send(data)
            }
        }
    }

    func terminalViewDidReceiveMouseEvent(button: Int, x: Int, y: Int, isRelease: Bool, modifiers: TerminalKeyEvent.KeyModifiers) {
        if let data = keyboardHandler.mouseEvent(button: button, x: x, y: y, isRelease: isRelease, modifiers: modifiers) {
            sendQueue.async { [weak self] in
                self?.connectionManager.send(data)
            }
        }
    }

    func terminalViewDidReceiveScrollEvent(direction: Int, x: Int, y: Int, modifiers: TerminalKeyEvent.KeyModifiers) {
        if let data = keyboardHandler.scrollEvent(direction: direction, x: x, y: y, modifiers: modifiers) {
            sendQueue.async { [weak self] in
                self?.connectionManager.send(data)
            }
        }
    }

    func terminalViewDidResize(columns: Int, rows: Int) {
        handleResize()
    }

    func terminalViewDidRequestPaste(_ text: String) {
        sendPasteText(text)
    }

    func terminalViewDidGainFocus() {
        if let data = keyboardHandler.focusIn() {
            sendQueue.async { [weak self] in
                self?.connectionManager.send(data)
            }
        }
    }

    func terminalViewDidLoseFocus() {
        if let data = keyboardHandler.focusOut() {
            sendQueue.async { [weak self] in
                self?.connectionManager.send(data)
            }
        }
    }

    private func sendPasteText(_ text: String) {
        var data = Data()
        data.append(keyboardHandler.bracketedPasteStart())
        data.append(Data(text.utf8))
        data.append(keyboardHandler.bracketedPasteEnd())

        let telnet = useTelnet
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            if telnet {
                let escaped = self.telnetProtocol.escapeData(data)
                self.connectionManager.send(escaped)
            } else {
                self.connectionManager.send(data)
            }
        }
    }
}

// MARK: - TelnetProtocolDelegate

extension TerminalWindowController: TelnetProtocolDelegate {
    func telnetDidReceiveData(_ data: Data) {
        terminalEmulator.processData(data)
    }

    func telnetDidRequestSend(_ data: Data) {
        connectionManager.send(data)
    }

    func telnetDidChangeTerminalSize(width: Int, height: Int) {
        // Terminal size change from remote
    }
}

// MARK: - FileTransferDelegate

extension TerminalWindowController: FileTransferDelegate {
    func transferDidUpdateState(_ state: TransferState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch state {
            case .starting:
                self.packetCount = 0
            case .inProgress(let bytes, let total, let name):
                self.packetCount += 1
                self.protocolTransferPanel.update(
                    packetNum: self.packetCount,
                    bytesTransferred: bytes,
                    totalBytes: total)
                let progress = total.map { "\(bytes)/\($0)" } ?? "\(bytes) bytes"
                self.window?.title = String(format: TTL("window.title.transfer"), name, progress)
            case .completed(let name, let bytes):
                self.protocolTransferPanel.close()
                self.updateWindowTitle()
                let alert = NSAlert()
                alert.messageText = TTL("transfer.complete.title")
                alert.informativeText = String(format: TTL("transfer.complete.message"), name, bytes)
                alert.alertStyle = .informational
                alert.addButton(withTitle: TTL("transfer.ok"))
                if let win = self.window {
                    alert.beginSheetModal(for: win)
                }
            case .failed(let error):
                self.protocolTransferPanel.close()
                self.updateWindowTitle()
                let alert = NSAlert()
                alert.messageText = TTL("transfer.failed.title")
                alert.informativeText = error
                alert.alertStyle = .warning
                alert.addButton(withTitle: TTL("transfer.ok"))
                if let win = self.window {
                    alert.beginSheetModal(for: win)
                }
            case .cancelled:
                self.protocolTransferPanel.close()
                self.updateWindowTitle()
            default:
                break
            }
        }
    }

    func transferDidRequestSend(_ data: Data) {
        connectionManager.send(data)
    }

    func transferDidComplete(fileName: String, bytes: Int64) {
        updateWindowTitle()
        macroTransferCompletion?(true)
        macroTransferCompletion = nil
    }

    func transferDidFail(error: String) {
        updateWindowTitle()
        macroTransferCompletion?(false)
        macroTransferCompletion = nil
    }
}

// MARK: - TTLInterpreterDelegate

extension TerminalWindowController: TTLInterpreterDelegate {
    func ttlSendData(_ data: Data) {
        connectionManager.send(data)
    }

    func ttlSendString(_ text: String) {
        connectionManager.send(Data(text.utf8))
    }

    func ttlSendLine(_ text: String) {
        connectionManager.send(Data((text + "\r").utf8))
    }

    func ttlIsConnected() -> Bool {
        return isConnected
    }

    func ttlGetReceivedData(clear: Bool) -> String {
        // Return buffered received data for macro wait commands
        let data = terminalEmulator.macroReceiveBuffer
        if clear { terminalEmulator.macroReceiveBuffer = "" }
        return data
    }

    func ttlFlushReceiveBuffer() {
        terminalEmulator.macroReceiveBuffer = ""
    }

    func ttlDisconnect() {
        disconnect()
    }

    func ttlConnect(_ param: String) {
        // Parse connection string: "host:port" or "/dev/ttyXXX"
        if param.hasPrefix("/dev/") {
            connectSerial(device: param)
        } else {
            let parts = param.components(separatedBy: ":")
            let host = parts.first ?? "localhost"
            let port = parts.count > 1 ? (Int(parts[1]) ?? 23) : 23
            connectTCP(host: host, port: port)
        }
    }

    func ttlConnectLocalShell() {
        connectLocalShell()
    }

    func ttlSetTitle(_ title: String) {
        window?.title = title
    }

    func ttlGetTitle() -> String {
        return window?.title ?? ""
    }

    func ttlShowWindow(_ show: Bool) {
        if show {
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderOut(nil)
        }
    }

    func ttlClearScreen() {
        clearScreen()
    }

    func ttlSendBreak() {
        connectionManager.sendBreak()
    }

    func ttlLogOpen(_ path: String, append: Bool) {
        var opts = LogOptions.from(settings)
        opts.appendMode = append
        _ = logger.startLogging(to: path, options: opts)
    }

    func ttlLogClose() {
        logger.stopLogging()
    }

    func ttlLogPause() {
        logger.pauseLogging()
    }

    func ttlLogStart() {
        logger.resumeLogging()
    }

    func ttlLogWrite(_ text: String) {
        logger.logData(Data(text.utf8))
    }

    func ttlLogInfo() -> (state: Int, filePath: String) {
        let stateValue: Int
        switch logger.state {
        case .inactive:
            stateValue = -1
        case .active:
            stateValue = 0
        case .paused:
            stateValue = 1
        }
        return (state: stateValue, filePath: logger.logFilePath ?? "")
    }

    func ttlLogRotateSet(mode: String, value: Int) {
        switch mode {
        case "size":
            logger.setRotation(mode: .size, size: value)
        case "rotate":
            logger.setRotation(step: value)
        case "halt":
            logger.setRotation(mode: .some(.none))
        default:
            break
        }
    }

    func ttlShowError(_ message: String, line: Int, lineText: String, fileName: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = TTL("macro.error.title")
            // Build informative text like the original: filename:line: error message + line content
            var info = "\(fileName):\(line): \(message)"
            if !lineText.isEmpty {
                info += "\n\n\(lineText)"
            }
            alert.informativeText = info
            alert.alertStyle = .warning
            // Original Tera Term buttons: Stop (IDOK), Continue (IDCANCEL)
            alert.addButton(withTitle: TTL("macro.error.stop"))      // First button (returnCode 1000)
            alert.addButton(withTitle: TTL("macro.error.continue"))  // Second button (returnCode 1001)
            if let win = self?.window {
                alert.beginSheetModal(for: win) { response in
                    // NSApplication.ModalResponse.alertFirstButtonReturn = 1000 = Stop
                    let shouldStop = (response == .alertFirstButtonReturn)
                    completion(shouldStop)
                }
            } else {
                // No window available, stop by default
                completion(true)
            }
        }
    }

    func ttlShowStatusBox(_ message: String, title: String) {
        // Status box shown as floating panel
    }

    func ttlCloseStatusBox() {
        // Close status box
    }

    func ttlGetClipboard() -> String {
        return NSPasteboard.general.string(forType: .string) ?? ""
    }

    func ttlSetClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func ttlSetBaud(_ baud: Int) {
        settings.baudRate = baud
    }

    func ttlSetFlowCtrl(_ mode: Int) {
        if let serial = connectionManager.currentConnection as? SerialConnection {
            let fc = FlowControl(rawValue: mode) ?? .none
            serial.setFlowControl(fc)
        }
    }

    func ttlSetDtr(_ on: Int) {
        if let serial = connectionManager.currentConnection as? SerialConnection {
            serial.setDtr(on != 0)
        }
    }

    func ttlSetRts(_ on: Int) {
        if let serial = connectionManager.currentConnection as? SerialConnection {
            serial.setRts(on != 0)
        }
    }

    func ttlStartFileTransfer(protocol type: TransferProtocolType, direction: TransferDirection, filePath: String, completion: @escaping (Bool) -> Void) {
        fileTransferManager.delegate = self
        fileTransferManager.startTransfer(protocol: type, direction: direction, filePath: filePath)

        // Show progress panel
        let protoName: String
        switch type {
        case .xmodem:    protoName = "XMODEM"
        case .xmodemCRC: protoName = "XMODEM-CRC"
        case .xmodem1K:  protoName = "XMODEM-1K"
        case .ymodem:    protoName = "YMODEM"
        case .ymodemG:   protoName = "YMODEM-G"
        case .zmodem:    protoName = "ZMODEM"
        case .kermit:    protoName = "Kermit"
        case .bplus:     protoName = "B-Plus"
        case .quickVAN:  protoName = "Quick-VAN"
        }
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        protocolTransferPanel.onCancel = { [weak self] in
            self?.fileTransferManager.cancelTransfer()
            completion(false)
        }
        protocolTransferPanel.show(fileName: fileName, protocolName: protoName)

        // Store completion for when transfer finishes
        macroTransferCompletion = completion
    }

    func ttlKermitGet(remoteFileName: String, localPath: String, completion: @escaping (Bool) -> Void) {
        fileTransferManager.delegate = self
        fileTransferManager.startKermitGet(remoteFileName: remoteFileName, localPath: localPath)
        protocolTransferPanel.onCancel = { [weak self] in
            self?.fileTransferManager.cancelTransfer()
            completion(false)
        }
        protocolTransferPanel.show(fileName: remoteFileName, protocolName: "Kermit Get")
        macroTransferCompletion = completion
    }

    func ttlKermitFinish(completion: @escaping (Bool) -> Void) {
        fileTransferManager.delegate = self
        fileTransferManager.startKermitFinish()
        macroTransferCompletion = completion
    }

    func ttlScpSend(localPath: String, remotePath: String, completion: @escaping (Bool) -> Void) {
        guard let ssh = connectionManager.currentConnection as? SSHConnection else {
            completion(false)
            return
        }
        SCPDialogController.executeSCP(
            send: true, localPath: localPath, remotePath: remotePath,
            host: ssh.host, port: ssh.port, username: ssh.username
        ) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    func ttlScpRecv(remotePath: String, localPath: String, completion: @escaping (Bool) -> Void) {
        guard let ssh = connectionManager.currentConnection as? SSHConnection else {
            completion(false)
            return
        }
        SCPDialogController.executeSCP(
            send: false, localPath: localPath, remotePath: remotePath,
            host: ssh.host, port: ssh.port, username: ssh.username
        ) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    func ttlRecvFile(filePath: String, binary: Bool, autoStopSec: Int, completion: @escaping (Bool) -> Void) {
        // Open file for writing received data
        FileManager.default.createFile(atPath: filePath, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: filePath) else {
            completion(false)
            return
        }

        // Start receiving data to file
        macroRecvFileHandle = handle
        macroRecvAutoStopSec = autoStopSec
        macroRecvLastDataTime = Date()
        macroTransferCompletion = completion

        // Schedule auto-stop check timer
        if autoStopSec > 0 {
            macroRecvTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                if let lastTime = self.macroRecvLastDataTime,
                   Date().timeIntervalSince(lastTime) >= Double(self.macroRecvAutoStopSec) {
                    timer.invalidate()
                    self.macroRecvFileHandle?.closeFile()
                    self.macroRecvFileHandle = nil
                    self.macroRecvTimer = nil
                    self.macroTransferCompletion?(true)
                    self.macroTransferCompletion = nil
                }
            }
        }
    }

    func ttlRestoreSetup(from path: String) {
        let url = URL(fileURLWithPath: path)
        settings = TerminalSettings.load(from: url)
        applySettings()
    }

    func ttlLoadKeyMap(from path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            let keyMap = try KeymapLoader.load(from: url)
            applyKeyMap(keyMap)
            if !keyMap.warnings.isEmpty {
                NSLog("[KeyMap] %@", TTL("debug.keymap.warnings", keyMap.warnings.joined(separator: ", ")))
            }
        } catch {
            NSLog("[KeyMap] %@", TTL("debug.keymap.loadFailed", error.localizedDescription))
        }
    }

    func ttlCallMenu(menuId: Int) {
        // Map Tera Term menu IDs to macOS menu actions
        // Common menu IDs from the original:
        // 50110=New Connection, 50210=Copy, 50220=Paste, etc.
        // Dispatch via NSApp menu structure by tag
        DispatchQueue.main.async {
            if let mainMenu = NSApp.mainMenu {
                for item in mainMenu.items {
                    if let submenu = item.submenu {
                        for subItem in submenu.items {
                            if subItem.tag == menuId, let action = subItem.action {
                                NSApp.sendAction(action, to: subItem.target, from: nil)
                                return
                            }
                        }
                    }
                }
            }
        }
    }

    func ttlSetSerialDelayChar(_ ms: Int) {
        settings.serialDelayPerChar = ms
    }

    func ttlSetSerialDelayLine(_ ms: Int) {
        settings.serialDelayPerLine = ms
    }
}
#endif
