/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Status bar menu manager for TTLMacro.app.
 * Manages the menu bar status item with animation during macro execution.
 */

#if canImport(AppKit)
import AppKit
import TTLMacroShared

// MARK: - Delegate Protocol

protocol StatusBarManagerDelegate: AnyObject {
    func statusBarDidRequestOpen()
    func statusBarDidRequestPause()
    func statusBarDidRequestResume()
    func statusBarDidRequestStop()
    func statusBarDidRequestQuit()
}

// MARK: - Execution State

enum MacroUIState {
    case idle
    case running
    case paused
}

// MARK: - StatusBarManager

class StatusBarManager: NSObject, NSMenuDelegate {

    weak var delegate: StatusBarManagerDelegate?

    private var statusItem: NSStatusItem?
    private var animationTimer: Timer?
    private var animationFrame: Int = 0
    private var currentState: MacroUIState = .idle
    private var currentLineNumber: Int = 0
    private var isMenuOpen: Bool = false

    // Menu items that need updating
    private var lineNumberItem: NSMenuItem?
    private var quitItem: NSMenuItem?

    // MARK: - Lifecycle

    deinit {
        stopAnimation()
        cleanup()
    }

    func cleanup() {
        stopAnimation()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - State Management

    func showIdleMenu() {
        DispatchQueue.main.async { [weak self] in
            self?.setupIdleMenu()
        }
    }

    func showRunningMenu(macroPath: String) {
        DispatchQueue.main.async { [weak self] in
            self?.currentState = .running
            self?.setupRunningMenu()
            self?.startAnimation()
        }
    }

    func showPausedMenu() {
        DispatchQueue.main.async { [weak self] in
            self?.currentState = .paused
            self?.setupPausedMenu()
            self?.stopAnimation()
            self?.updateStatusIcon(symbolName: "pause.circle")
        }
    }

    func updateLineNumber(_ line: Int) {
        currentLineNumber = line
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lineNumberItem?.title = String(format: L("macro.menu.lineNumber"), line)
        }
    }

    // MARK: - Idle Menu

    private func setupIdleMenu() {
        currentState = .idle
        stopAnimation()
        ensureStatusItem()
        updateStatusIcon(symbolName: "applescript")

        let menu = NSMenu()
        menu.delegate = self

        let openItem = NSMenuItem(title: L("macro.menu.open"),
                                  action: #selector(openMacroAction),
                                  keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L("macro.menu.quit"),
                                  action: #selector(quitAction),
                                  keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        self.quitItem = quitItem

        statusItem?.menu = menu
    }

    // MARK: - Running Menu

    private func setupRunningMenu() {
        ensureStatusItem()

        let menu = NSMenu()
        menu.delegate = self

        let runningLabel = NSMenuItem(title: L("macro.menu.running"),
                                      action: nil, keyEquivalent: "")
        runningLabel.isEnabled = false
        menu.addItem(runningLabel)

        let lineItem = NSMenuItem(title: String(format: L("macro.menu.lineNumber"), currentLineNumber),
                                  action: nil, keyEquivalent: "")
        lineItem.isEnabled = false
        menu.addItem(lineItem)
        self.lineNumberItem = lineItem

        menu.addItem(.separator())

        let pauseItem = NSMenuItem(title: L("macro.menu.pause"),
                                   action: #selector(pauseAction),
                                   keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let stopItem = NSMenuItem(title: L("macro.menu.stop"),
                                  action: #selector(stopAction),
                                  keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L("macro.menu.quit"),
                                  action: #selector(quitAction),
                                  keyEquivalent: "")
        quitItem.target = self
        quitItem.isEnabled = false  // Disabled during execution
        menu.addItem(quitItem)
        self.quitItem = quitItem

        statusItem?.menu = menu
    }

    // MARK: - Paused Menu

    private func setupPausedMenu() {
        ensureStatusItem()

        let menu = NSMenu()
        menu.delegate = self

        let pausedLabel = NSMenuItem(title: L("macro.menu.paused"),
                                     action: nil, keyEquivalent: "")
        pausedLabel.isEnabled = false
        menu.addItem(pausedLabel)

        let lineItem = NSMenuItem(title: String(format: L("macro.menu.lineNumber"), currentLineNumber),
                                  action: nil, keyEquivalent: "")
        lineItem.isEnabled = false
        menu.addItem(lineItem)
        self.lineNumberItem = lineItem

        menu.addItem(.separator())

        let resumeItem = NSMenuItem(title: L("macro.menu.resume"),
                                    action: #selector(resumeAction),
                                    keyEquivalent: "")
        resumeItem.target = self
        menu.addItem(resumeItem)

        let stopItem = NSMenuItem(title: L("macro.menu.stop"),
                                  action: #selector(stopAction),
                                  keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L("macro.menu.quit"),
                                  action: #selector(quitAction),
                                  keyEquivalent: "")
        quitItem.target = self
        quitItem.isEnabled = false  // Disabled during pause
        menu.addItem(quitItem)
        self.quitItem = quitItem

        statusItem?.menu = menu
    }

    // MARK: - Status Item

    private func ensureStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }
    }

    private func updateStatusIcon(symbolName: String) {
        if let button = statusItem?.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: symbolName,
                                       accessibilityDescription: "TTLMacro")
            } else {
                button.title = "M"
            }
        }
    }

    // MARK: - Animation

    /// Start status bar icon animation (frame cycling at 0.3s interval).
    /// Ensures only one timer is active at a time (lesson: prevent timer accumulation).
    func startAnimation() {
        stopAnimation()  // Always stop existing timer first
        animationFrame = 0

        animationTimer = Timer.scheduledTimer(withTimeInterval: MacroConstants.animationInterval,
                                              repeats: true) { [weak self] _ in
            self?.animateIcon()
        }
    }

    /// Stop status bar icon animation and invalidate timer.
    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    /// Whether the animation timer is currently running.
    var isAnimating: Bool {
        return animationTimer != nil && animationTimer!.isValid
    }

    private func animateIcon() {
        guard let button = statusItem?.button else { return }

        let symbols: [String]
        if #available(macOS 13.0, *) {
            // Use symbol effect on macOS 13+
            symbols = ["applescript", "applescript.fill"]
        } else {
            symbols = ["circle", "circle.fill", "circle.dotted"]
        }

        let symbolName = symbols[animationFrame % symbols.count]
        animationFrame += 1

        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: symbolName,
                                   accessibilityDescription: "TTLMacro")
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    // MARK: - Actions

    @objc private func openMacroAction() {
        delegate?.statusBarDidRequestOpen()
    }

    @objc private func pauseAction() {
        delegate?.statusBarDidRequestPause()
    }

    @objc private func resumeAction() {
        delegate?.statusBarDidRequestResume()
    }

    @objc private func stopAction() {
        delegate?.statusBarDidRequestStop()
    }

    @objc private func quitAction() {
        delegate?.statusBarDidRequestQuit()
    }
}

#endif
