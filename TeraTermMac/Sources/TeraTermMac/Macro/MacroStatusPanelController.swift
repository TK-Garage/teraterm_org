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
        let update: () -> Void = { [weak self] in
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
        let update: () -> Void = { [weak self] in
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
        // --- Build content view with Auto Layout ---
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // --- Visual Effect Background ---
        let effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        container.addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // --- Macro Name Label (header) ---
        let nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = NSFont.boldSystemFont(ofSize: 13)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.macroNameLabel = nameLabel

        // --- Line Number Label (center, monospace) ---
        let lineLbl = NSTextField(labelWithString: TTL("macroStatus.linePrefix", 0))
        lineLbl.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
        lineLbl.textColor = .secondaryLabelColor
        lineLbl.alignment = .center
        lineLbl.translatesAutoresizingMaskIntoConstraints = false
        self.lineLabel = lineLbl

        // --- Buttons ---
        let pauseBtn = NSView.makePushButton(NSLocalizedString("macroStatus.pause", comment: ""))
        pauseBtn.target = self
        pauseBtn.action = #selector(pauseResumeClicked(_:))
        self.pauseResumeButton = pauseBtn

        let stopBtn = NSView.makePushButton(NSLocalizedString("macroStatus.stop", comment: ""))
        stopBtn.target = self
        stopBtn.action = #selector(stopClicked(_:))
        stopBtn.contentTintColor = .systemRed
        self.stopButton = stopBtn

        let buttonStack = NSStackView(views: [pauseBtn, stopBtn])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        // --- Vertical Layout Stack ---
        let mainStack = NSStackView(views: [nameLabel, lineLbl, buttonStack])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 8
        effectView.addSubview(mainStack)

        let pad: CGFloat = 16
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 12),
            mainStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: pad),
            mainStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -pad),
            mainStack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -12),

            // Minimum width — expands if localized text is longer
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),

            // Name label spans full width
            nameLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            // Button stack spans full width
            buttonStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])

        // --- Panel (content-driven sizing) ---
        let vc = NSViewController()
        vc.view = container
        let p = NSPanel(contentViewController: vc)
        p.styleMask = [.titled, .closable, .utilityWindow]
        p.title = NSLocalizedString("macroStatus.title", comment: "")
        p.isFloatingPanel = true
        p.level = .floating
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
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
