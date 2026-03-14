/*
 * KeycodeView.swift
 * Key input view for Keycode.app
 *
 * Captures keyboard events and displays the corresponding PC key code.
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

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
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

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    // MARK: - Key Event Handling

    override func keyDown(with event: NSEvent) {
        handleKeyEvent(event)
    }

    override func flagsChanged(with event: NSEvent) {
        // Ignore modifier-only key events
        // Only process if a non-modifier key is also pressed
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
