/*
 * KeycodeView.swift
 * Key input view for Keycode.app
 *
 * Captures keyboard events and displays the corresponding PC key code.
 * Uses NSEvent.addLocalMonitorForEvents to reliably capture all key events
 * following macOS event handling conventions.
 *
 * Port of KEYCODE.EXE's WM_KEYDOWN / WM_PAINT handling.
 */

import AppKit

/// Custom NSView that captures key events and displays PC key codes.
class KeycodeView: NSView {

    // MARK: - UI Elements

    private let promptLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 16)
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }()

    private let keyCodeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .medium)
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }()

    private let keyDescLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.textColor = .secondaryLabelColor
        return label
    }()

    private let optionHintLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11)
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.textColor = .tertiaryLabelColor
        return label
    }()

    /// Local event monitor for keyDown events
    private var keyDownMonitor: Any?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        installKeyMonitor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        installKeyMonitor()
    }

    deinit {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupUI() {
        addSubview(promptLabel)
        addSubview(keyCodeLabel)
        addSubview(keyDescLabel)
        addSubview(optionHintLabel)

        promptLabel.stringValue = L("keycode.prompt")
        keyCodeLabel.stringValue = L("keycode.initial")
        keyDescLabel.stringValue = ""
        optionHintLabel.stringValue = L("keycode.optionHint")

        NSLayoutConstraint.activate([
            // Prompt label (top area)
            promptLabel.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            promptLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            // Key code label (center)
            keyCodeLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
            keyCodeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            keyCodeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            // Key description label (below center)
            keyDescLabel.topAnchor.constraint(equalTo: keyCodeLabel.bottomAnchor, constant: 12),
            keyDescLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            keyDescLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            // Option hint label (bottom)
            optionHintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            optionHintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            optionHintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Key Event Monitor

    /// Install a local event monitor to capture all keyDown events.
    /// This is more reliable than overriding keyDown() because:
    /// - It captures events before menu key equivalents consume them
    /// - It works regardless of first responder state
    /// - It follows macOS NSEvent monitoring conventions
    private func installKeyMonitor() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Only process when our window is key window
            guard self.window?.isKeyWindow == true else { return event }

            self.handleKeyEvent(event)

            // Return nil to consume the event (prevent system beep),
            // or return event to let it propagate to menu key equivalents.
            // We consume all key events to prevent beep on unhandled keys.
            return nil
        }
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    // MARK: - Key Event Handling

    override func keyDown(with event: NSEvent) {
        // Events are handled by the local monitor.
        // Override to prevent the default beep on unhandled keys.
    }

    override func flagsChanged(with event: NSEvent) {
        // Ignore modifier-only key events
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let kc = event.keyCode

        // Ignore modifier-only keys
        guard !modifierKeyCodes.contains(kc) else { return }

        // Clean modifier flags (remove device-independent flags)
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        let desc = keyDescription(keyCode: kc, modifiers: mods)

        if isOptionOnly(modifiers: mods) {
            // Option-only combination: show hint with calculation
            let baseCode = Int(kc)
            let optCode = baseCode + ModifierOffset.optionAlone
            keyCodeLabel.stringValue = L("keycode.optionDetected", desc, baseCode, optCode)
            keyCodeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium)
            keyDescLabel.stringValue = desc
        } else if let code = pcKeyCode(keyCode: kc, modifiers: mods) {
            keyCodeLabel.stringValue = L("keycode.result", code)
            keyCodeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .medium)
            keyDescLabel.stringValue = desc
        }
    }
}
