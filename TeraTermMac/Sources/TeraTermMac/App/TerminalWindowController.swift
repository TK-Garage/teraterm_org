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

// MARK: - Localization Helper

private func L(_ key: String) -> String {
    #if SWIFT_PACKAGE
    return NSLocalizedString(key, bundle: Bundle.module, comment: "")
    #else
    return NSLocalizedString(key, bundle: Bundle.main, comment: "")
    #endif
}

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

    // Settings
    var settings: TerminalSettings

    // State
    private var useTelnet: Bool = false
    private var isConnected: Bool = false

    // MARK: - Initialization

    init(settings: TerminalSettings = TerminalSettings()) {
        self.settings = settings

        // Create a temporary window; real size set after font metrics are known
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = settings.title
        window.minSize = NSSize(width: 200, height: 100)
        window.isReleasedWhenClosed = false

        // Modern macOS appearance: glass titlebar integrated with content
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
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

        logger = TerminalLogger()
    }

    private func setupTerminalView() {
        guard let window = window else { return }

        // NSVisualEffectView provides macOS glass/vibrancy effect as the
        // window backdrop. TerminalView draws on top with a semi-transparent
        // background so the effect shows through.
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
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
                    title += " - " + L("window.title.localShell")
                } else if let tcp = conn as? TCPConnection {
                    title += " - \(tcp.host):\(tcp.port)"
                } else if let serial = conn as? SerialConnection {
                    title += " - \(serial.device)"
                }
            }
        } else {
            title += " - [\(L("window.title.disconnected"))]"
        }
        window?.title = title
    }

    // MARK: - Log Actions

    func startLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "teraterm.log"
        panel.allowedContentTypes = [.plainText]

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            _ = self?.logger.startLogging(to: url.path)
        }
    }

    func stopLog() {
        logger.stopLogging()
    }

    // MARK: - File Transfer Actions

    func sendFile(protocol type: TransferProtocolType) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.fileTransferManager.delegate = self
            self?.fileTransferManager.startTransfer(protocol: type, direction: .send, filePath: url.path)
        }
    }

    func receiveFile(protocol type: TransferProtocolType) {
        let panel = NSSavePanel()
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.fileTransferManager.delegate = self
            self?.fileTransferManager.startTransfer(protocol: type, direction: .receive, filePath: url.path)
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
        terminalView.refresh()
    }

    // MARK: - Resize handling

    private func handleResize() {
        let size = terminalView.terminalSize
        guard size.columns > 0 && size.rows > 0 else { return }

        terminalEmulator.resize(width: size.columns, height: size.rows)

        if let pty = connectionManager.currentConnection as? LocalShellConnection {
            pty.resize(cols: UInt16(size.columns), rows: UInt16(size.rows))
        }

        if useTelnet {
            telnetProtocol.updateWindowSize(width: size.columns, height: size.rows)
        }

        terminalView.refresh()
    }
}

// MARK: - NSWindowDelegate

extension TerminalWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        handleResize()
    }

    func windowWillClose(_ notification: Notification) {
        disconnect()
        logger.stopLogging()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let data = keyboardHandler.focusIn() {
            connectionManager.send(data)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let data = keyboardHandler.focusOut() {
            connectionManager.send(data)
        }
    }
}

// MARK: - TerminalEmulatorDelegate

extension TerminalWindowController: TerminalEmulatorDelegate {
    func terminalDidUpdateDisplay() {
        terminalView.modes = terminalEmulator.modes
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

        let alert = NSAlert()
        alert.messageText = L("error.connection.title")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("error.connection.ok"))
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

        if useTelnet {
            let escaped = telnetProtocol.escapeData(data)
            connectionManager.send(escaped)
        } else {
            connectionManager.send(data)
        }
    }

    func terminalViewDidReceiveMouseEvent(button: Int, x: Int, y: Int, isRelease: Bool, modifiers: TerminalKeyEvent.KeyModifiers) {
        if let data = keyboardHandler.mouseEvent(button: button, x: x, y: y, isRelease: isRelease, modifiers: modifiers) {
            connectionManager.send(data)
        }
    }

    func terminalViewDidReceiveScrollEvent(direction: Int, x: Int, y: Int, modifiers: TerminalKeyEvent.KeyModifiers) {
        if let data = keyboardHandler.scrollEvent(direction: direction, x: x, y: y, modifiers: modifiers) {
            connectionManager.send(data)
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
            connectionManager.send(data)
        }
    }

    func terminalViewDidLoseFocus() {
        if let data = keyboardHandler.focusOut() {
            connectionManager.send(data)
        }
    }

    private func sendPasteText(_ text: String) {
        var data = Data()
        data.append(keyboardHandler.bracketedPasteStart())
        data.append(Data(text.utf8))
        data.append(keyboardHandler.bracketedPasteEnd())

        if useTelnet {
            let escaped = telnetProtocol.escapeData(data)
            connectionManager.send(escaped)
        } else {
            connectionManager.send(data)
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
            switch state {
            case .inProgress(let bytes, let total, let name):
                let progress = total.map { "\(bytes)/\($0)" } ?? "\(bytes) bytes"
                self?.window?.title = "Transfer: \(name) - \(progress)"
            case .completed(let name, let bytes):
                self?.updateWindowTitle()
                let alert = NSAlert()
                alert.messageText = L("transfer.complete.title")
                alert.informativeText = String(format: L("transfer.complete.message"), name, bytes)
                alert.alertStyle = .informational
                alert.addButton(withTitle: L("transfer.ok"))
                if let win = self?.window {
                    alert.beginSheetModal(for: win)
                }
            case .failed(let error):
                self?.updateWindowTitle()
                let alert = NSAlert()
                alert.messageText = L("transfer.failed.title")
                alert.informativeText = error
                alert.alertStyle = .warning
                alert.addButton(withTitle: L("transfer.ok"))
                if let win = self?.window {
                    alert.beginSheetModal(for: win)
                }
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
    }

    func transferDidFail(error: String) {
        updateWindowTitle()
    }
}
#endif
