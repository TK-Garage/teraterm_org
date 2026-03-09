/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * MacroStatusPanelController.swift
 * Floating utility panel that displays TTL macro execution status
 * (current file name, line number) and provides pause/resume/stop controls.
 * Follows macOS HIG with NSVisualEffectView behind-window material.
 */

#if canImport(AppKit)
import AppKit

// MARK: - Delegate Protocol

/// Delegate that receives user actions from the macro status panel.
protocol MacroStatusPanelDelegate: AnyObject {
    /// Called when the user toggles pause/resume.
    func macroStatusPanelDidTogglePause(_ controller: MacroStatusPanelController)
    /// Called when the user requests macro stop.
    func macroStatusPanelDidRequestStop(_ controller: MacroStatusPanelController)
}

// MARK: - MacroStatusPanelController

/// A floating utility panel showing macro execution status with pause/stop controls.
final class MacroStatusPanelController {

    // MARK: - Public Properties

    weak var delegate: MacroStatusPanelDelegate?

    /// Whether the macro is currently paused (drives button title).
    private(set) var isPaused: Bool = false

    // MARK: - UI Elements

    private var panel: NSPanel?
    private var macroNameLabel: NSTextField?
    private var lineLabel: NSTextField?
    private var pauseResumeButton: NSButton?
    private var stopButton: NSButton?

    // MARK: - Panel Lifecycle

    /// Show the panel with the given macro file name.
    func show(macroName: String) {
        if panel == nil {
            buildPanel()
        }
        isPaused = false
        macroNameLabel?.stringValue = macroName
        lineLabel?.stringValue = "Line: 0"
        updatePauseButtonTitle()
        panel?.orderFront(nil)
    }

    /// Hide and release the panel.
    func close() {
        panel?.orderOut(nil)
        panel = nil
        macroNameLabel = nil
        lineLabel = nil
        pauseResumeButton = nil
        stopButton = nil
    }

    /// Update the displayed line number. Safe to call from any thread.
    func updateLineNumber(_ line: Int) {
        let update = { [weak self] in
            self?.lineLabel?.stringValue = "Line: \(line)"
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    /// Update the displayed macro name.
    func updateMacroName(_ name: String) {
        let update = { [weak self] in
            self?.macroNameLabel?.stringValue = name
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    /// Reflect external pause state (e.g. when the interpreter pauses for other reasons).
    func setIsPaused(_ paused: Bool) {
        isPaused = paused
        updatePauseButtonTitle()
    }

    // MARK: - Panel Construction

    private func buildPanel() {
        // --- Panel ---
        let panelRect = NSRect(x: 0, y: 0, width: 280, height: 120)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .utilityWindow]
        let p = NSPanel(
            contentRect: panelRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        p.title = NSLocalizedString("macroStatus.title", comment: "")
        p.isFloatingPanel = true
        p.level = .floating
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false

        // --- Visual Effect Background ---
        let effectView = NSVisualEffectView(frame: panelRect)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        p.contentView = effectView

        // --- Macro Name Label (header) ---
        let nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = NSFont.boldSystemFont(ofSize: 13)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(nameLabel)
        self.macroNameLabel = nameLabel

        // --- Line Number Label (center, monospace) ---
        let lineLbl = NSTextField(labelWithString: "Line: 0")
        lineLbl.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
        lineLbl.textColor = .secondaryLabelColor
        lineLbl.alignment = .center
        lineLbl.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(lineLbl)
        self.lineLabel = lineLbl

        // --- Buttons ---
        let pauseBtn = NSButton(
            title: NSLocalizedString("macroStatus.pause", comment: ""),
            target: self,
            action: #selector(pauseResumeClicked(_:))
        )
        pauseBtn.bezelStyle = .rounded
        pauseBtn.translatesAutoresizingMaskIntoConstraints = false
        self.pauseResumeButton = pauseBtn

        let stopBtn = NSButton(
            title: NSLocalizedString("macroStatus.stop", comment: ""),
            target: self,
            action: #selector(stopClicked(_:))
        )
        stopBtn.bezelStyle = .rounded
        stopBtn.contentTintColor = .systemRed
        stopBtn.translatesAutoresizingMaskIntoConstraints = false
        self.stopButton = stopBtn

        let stack = NSStackView(views: [pauseBtn, stopBtn])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stack)

        // --- Auto Layout ---
        NSLayoutConstraint.activate([
            // Name label – top
            nameLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),

            // Line label – center
            lineLbl.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            lineLbl.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            lineLbl.leadingAnchor.constraint(greaterThanOrEqualTo: effectView.leadingAnchor, constant: 16),

            // Button stack – bottom
            stack.topAnchor.constraint(equalTo: lineLbl.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -12),
        ])

        p.center()
        self.panel = p
    }

    // MARK: - Actions

    @objc private func pauseResumeClicked(_ sender: NSButton) {
        isPaused.toggle()
        updatePauseButtonTitle()
        delegate?.macroStatusPanelDidTogglePause(self)
    }

    @objc private func stopClicked(_ sender: NSButton) {
        delegate?.macroStatusPanelDidRequestStop(self)
    }

    // MARK: - Helpers

    private func updatePauseButtonTitle() {
        let key = isPaused ? "macroStatus.resume" : "macroStatus.pause"
        pauseResumeButton?.title = NSLocalizedString(key, comment: "")
    }
}

#endif
