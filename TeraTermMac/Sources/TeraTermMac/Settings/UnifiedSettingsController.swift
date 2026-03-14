/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * Unified Settings Dialog — combines all Setup menu dialogs into a single
 * tabbed window. Each tab embeds the existing dialog's view controller.
 *
 * Tabs (2 rows):
 *   Row 1: Terminal | Window | Keyboard | Serial Port | TCP/IP | General
 *   Row 2: Proxy | SSH | SSH Auth | SSH Forwarding | SSH Key Gen
 *
 * Menu items remain functional: selecting one opens this unified dialog
 * with the corresponding tab pre-selected.
 */

#if canImport(AppKit)
import AppKit

// MARK: - Tab Identifier

/// Identifies each tab in the unified settings dialog.
/// Used by menu actions to select the appropriate tab on open.
enum UnifiedSettingsTab: String, CaseIterable {
    case terminal       = "Terminal"
    case window         = "Window"
    case keyboard       = "Keyboard"
    case serialPort     = "SerialPort"
    case tcpip          = "TCPIP"
    case general        = "General"
    case proxy          = "Proxy"
    case ssh            = "SSH"
    case sshAuth        = "SSHAuth"
    case sshForwarding  = "SSHForwarding"
    case sshKeyGen      = "SSHKeyGen"

    var localizedTitle: String {
        switch self {
        case .terminal:      return TTL("menu.setup.terminal")
        case .window:        return TTL("menu.setup.window")
        case .keyboard:      return TTL("menu.setup.keyboard")
        case .serialPort:    return TTL("menu.setup.serialPort")
        case .tcpip:         return TTL("menu.setup.tcpip")
        case .general:       return TTL("menu.setup.general")
        case .proxy:         return TTL("menu.setup.proxy")
        case .ssh:           return TTL("menu.setup.ssh")
        case .sshAuth:       return TTL("menu.setup.sshAuth")
        case .sshForwarding: return TTL("menu.setup.sshForward")
        case .sshKeyGen:     return TTL("menu.setup.sshKeyGen")
        }
    }

    /// First row tabs
    static let row1: [UnifiedSettingsTab] = [
        .terminal, .window, .keyboard, .serialPort, .tcpip, .general
    ]

    /// Second row tabs
    static let row2: [UnifiedSettingsTab] = [
        .proxy, .ssh, .sshAuth, .sshForwarding, .sshKeyGen
    ]
}

// MARK: - Unified Settings Controller

final class UnifiedSettingsController: NSObject {

    private var window: NSWindow?
    private var tabView: NSTabView?
    private var settings: TerminalSettings
    private var viewControllers: [UnifiedSettingsTab: BaseSetupDialogController] = [:]
    var onApply: (() -> Void)?

    /// Callback for applying keyboard-specific settings (terminal ID)
    var onApplyKeyboard: (() -> Void)?

    /// Callback for applying serial port settings
    var onApplySerialPort: (() -> Void)?

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init()
    }

    /// Show the unified settings dialog with the specified tab selected.
    /// Returns the dialog window for exclusive control.
    @discardableResult
    func show(on parent: NSWindow, selectedTab: UnifiedSettingsTab = .terminal) -> NSWindow? {
        if let existingWindow = window {
            // Already open — just switch tab and bring to front
            selectTab(selectedTab)
            existingWindow.makeKeyAndOrderFront(nil)
            return existingWindow
        }

        buildWindow()
        guard let win = window else { return nil }

        selectTab(selectedTab)

        // Center over parent window
        win.layoutIfNeeded()
        let parentFrame = parent.frame
        let dialogSize = win.frame.size
        let x = parentFrame.midX - dialogSize.width / 2
        let y = parentFrame.midY - dialogSize.height / 2
        win.setFrameOrigin(NSPoint(x: x, y: y))

        // Keep within screen bounds
        if let screen = parent.screen ?? NSScreen.main {
            var frame = win.frame
            let visible = screen.visibleFrame
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
            win.setFrame(frame, display: true)
        }

        let response = NSApplication.shared.runModal(for: win)
        if response == .OK {
            applyAll()
            onApply?()
        }
        window = nil
        viewControllers.removeAll()
        return win
    }

    /// Show without a parent window
    func showModal(selectedTab: UnifiedSettingsTab = .terminal) {
        if window != nil { return }
        buildWindow()
        guard let win = window else { return }
        selectTab(selectedTab)
        win.center()
        let response = NSApplication.shared.runModal(for: win)
        if response == .OK {
            applyAll()
            onApply?()
        }
        window = nil
        viewControllers.removeAll()
    }

    // MARK: - Tab Selection

    private func selectTab(_ tab: UnifiedSettingsTab) {
        guard let tv = tabView else { return }
        for i in 0..<tv.numberOfTabViewItems {
            if let identifier = tv.tabViewItem(at: i).identifier as? String,
               identifier == tab.rawValue {
                tv.selectTabViewItem(at: i)
                return
            }
        }
    }

    // MARK: - Apply All

    private func applyAll() {
        for (tab, vc) in viewControllers {
            vc.applySettings()
            if tab == .keyboard {
                onApplyKeyboard?()
            }
            if tab == .serialPort {
                onApplySerialPort?()
            }
        }
    }

    // MARK: - Build Window

    private func buildWindow() {
        let tv = NSTabView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.tabViewType = .topTabsBezelBorder

        // Create view controllers for each tab
        let allTabs = UnifiedSettingsTab.row1 + UnifiedSettingsTab.row2
        for tab in allTabs {
            let vc = createViewController(for: tab)
            viewControllers[tab] = vc

            let item = NSTabViewItem(identifier: tab.rawValue)
            item.label = tab.localizedTitle

            // Load the view controller's view and extract the content
            // We embed the entire VC view (which includes OK/Cancel buttons from BaseSetupDialogController)
            // but we hide those buttons since we have our own
            vc.loadViewIfNeeded()
            item.view = vc.view
            tv.addTabViewItem(item)
        }

        // HIG button bar: [Help(?)] --- [Cancel] [OK]
        let buttonBar = DialogButtonBar.build(
            okTarget: self, okAction: #selector(okAction(_:)),
            cancelTarget: self, cancelAction: #selector(cancelAction(_:)),
            helpTarget: self, helpAction: #selector(helpAction(_:))
        )
        let footerBar = buttonBar.bar

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tv)
        container.addSubview(footerBar)

        let m: CGFloat = 16
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: container.topAnchor, constant: m),
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),

            footerBar.topAnchor.constraint(equalTo: tv.bottomAnchor, constant: m),
            footerBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
            footerBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),
            footerBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m),

            tv.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
            tv.heightAnchor.constraint(greaterThanOrEqualToConstant: 440),
        ])

        let vc = NSViewController()
        vc.view = container
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        win.contentViewController = vc
        win.isReleasedWhenClosed = false
        win.title = TTL("dialog.unifiedSettings.title")
        self.window = win
        self.tabView = tv
    }

    // MARK: - Create View Controllers

    /// Create the appropriate view controller for each tab.
    /// Each VC is a standalone BaseSetupDialogController with its footer
    /// buttons hidden (the unified dialog provides its own OK/Cancel).
    private func createViewController(for tab: UnifiedSettingsTab) -> BaseSetupDialogController {
        let vc: BaseSetupDialogController
        switch tab {
        case .terminal:
            vc = TerminalSetupViewController(settings: settings)
        case .window:
            vc = WindowSetupViewController(settings: settings)
        case .keyboard:
            vc = KeyboardSetupDialogController(settings: settings)
        case .serialPort:
            vc = SerialPortSetupViewController(settings: settings)
        case .tcpip:
            vc = TCPIPDialogController(settings: settings)
        case .general:
            vc = GeneralSetupDialogController(settings: settings)
        case .proxy:
            vc = ProxySetupDialogController(settings: settings)
        case .ssh:
            vc = SSHSetupDialogController(settings: settings)
        case .sshAuth:
            vc = SSHAuthSetupDialogController(settings: settings)
        case .sshForwarding:
            vc = SSHForwardingSetupDialogController(settings: settings)
        case .sshKeyGen:
            vc = SSHKeyGenDialogController()
        }
        // Hide the individual OK/Cancel/Help buttons — the unified
        // dialog provides its own set at the bottom.
        vc.hidesFooterButtons = true
        return vc
    }

    // MARK: - Actions

    @objc private func okAction(_ sender: Any?) {
        if let sheet = window, let parent = sheet.sheetParent {
            parent.endSheet(sheet, returnCode: .OK)
        } else if let win = window {
            NSApplication.shared.stopModal(withCode: .OK)
            win.close()
        }
    }

    @objc private func cancelAction(_ sender: Any?) {
        if let sheet = window, let parent = sheet.sheetParent {
            parent.endSheet(sheet, returnCode: .cancel)
        } else if let win = window {
            NSApplication.shared.stopModal(withCode: .cancel)
            win.close()
        }
    }

    @objc private func helpAction(_ sender: Any?) {
        if let url = URL(string: "https://teratermproject.github.io/") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
