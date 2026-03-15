/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * TTLMacro application delegate.
 * Handles launch patterns A (direct) and B (XPC mode).
 */

#if canImport(AppKit)
import AppKit
import TTLMacroShared
import UniformTypeIdentifiers

// MARK: - App Delegate

class TTLMacroAppDelegate: NSObject, NSApplicationDelegate {

    private(set) var statusBarManager: StatusBarManager?
    private(set) var macroRunner: MacroRunner?
    private var xpcServiceHandler: XPCServiceHandler?
    private(set) var variableWatchPanel: VariableWatchPanel?

    /// Whether launched in XPC mode (pattern B)
    var isXPCMode: Bool {
        return CommandLine.arguments.contains(MacroConstants.xpcModeArgument)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement = YES: app does not appear in Dock
        NSApp.setActivationPolicy(.accessory)

        macroRunner = MacroRunner()
        statusBarManager = StatusBarManager()
        statusBarManager?.delegate = self
        variableWatchPanel = VariableWatchPanel()

        if isXPCMode {
            // Pattern B: XPC mode - start listener and wait for commands
            xpcServiceHandler = XPCServiceHandler(macroRunner: macroRunner!)
            xpcServiceHandler?.startListener()
            statusBarManager?.showIdleMenu()
        } else {
            // Pattern A: Direct launch - show file selection dialog
            showOpenPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        macroRunner?.stop()
        statusBarManager?.cleanup()
        xpcServiceHandler?.stopListener()
    }

    // MARK: - Pattern A: File Selection

    private func showOpenPanel() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = L("macro.open.title")
        panel.prompt = L("macro.open.prompt")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if #available(macOS 11.0, *) {
            if let ttlType = UTType(filenameExtension: MacroConstants.ttlFileExtension) {
                panel.allowedContentTypes = [ttlType]
            }
        } else {
            panel.allowedFileTypes = [MacroConstants.ttlFileExtension]
        }

        let response = panel.runModal()

        if response == .OK, let url = panel.url {
            startMacro(at: url.path)
        } else {
            // Cancel or close → terminate
            NSApp.terminate(nil)
        }
    }

    // MARK: - Macro Execution

    func startMacro(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            statusBarManager?.cleanup()
            NSApp.terminate(nil)
            return
        }

        statusBarManager?.showRunningMenu(macroPath: path)

        macroRunner?.onLineExecuted = { [weak self] lineNumber, lineText in
            self?.statusBarManager?.updateLineNumber(lineNumber)
        }

        macroRunner?.onTransferProgress = { [weak self] status, bytes, total in
            self?.statusBarManager?.updateTransferProgress(status: status, bytes: bytes, total: total)
        }

        macroRunner?.onTransferError = { detail in
            TransferErrorDialog.show(detail)
        }

        macroRunner?.onDebugPause = { [weak self] lineNumber, lineText in
            DispatchQueue.main.async {
                self?.statusBarManager?.showPausedMenu()
                // Refresh variable watch panel if visible
                if let vars = self?.macroRunner?.getVariables() {
                    self?.variableWatchPanel?.updateVariables(vars)
                }
            }
        }

        macroRunner?.onComplete = { [weak self] exitCode in
            DispatchQueue.main.async {
                self?.statusBarManager?.cleanup()
                if !self!.isXPCMode {
                    NSApp.terminate(nil)
                } else {
                    self?.statusBarManager?.showIdleMenu()
                }
            }
        }

        macroRunner?.onError = { [weak self] error, line in
            DispatchQueue.main.async {
                self?.statusBarManager?.cleanup()
                if !self!.isXPCMode {
                    NSApp.terminate(nil)
                } else {
                    self?.statusBarManager?.showIdleMenu()
                }
            }
        }

        macroRunner?.run(scriptPath: path)
    }
}

// MARK: - StatusBarManagerDelegate

extension TTLMacroAppDelegate: StatusBarManagerDelegate {
    func statusBarDidRequestOpen() {
        showOpenPanel()
    }

    func statusBarDidRequestPause() {
        macroRunner?.pause()
        statusBarManager?.showPausedMenu()
    }

    func statusBarDidRequestResume() {
        macroRunner?.resume()
        statusBarManager?.showRunningMenu(macroPath: macroRunner?.currentScriptPath ?? "")
    }

    func statusBarDidRequestStop() {
        DispatchQueue.main.async {
            if MacroDialogHelper.showStopConfirmation() {
                self.macroRunner?.stop()
            }
        }
    }

    func statusBarDidRequestStepLine() {
        macroRunner?.stepLine()
    }

    func statusBarDidRequestStepOver() {
        macroRunner?.stepOver()
    }

    func statusBarDidRequestStepOut() {
        macroRunner?.stepOut()
    }

    func statusBarDidRequestQuit() {
        NSApp.terminate(nil)
    }

    func statusBarDidRequestShowVariables() {
        variableWatchPanel?.show()
        if let vars = macroRunner?.getVariables() {
            variableWatchPanel?.updateVariables(vars)
        }
    }
}

#endif
