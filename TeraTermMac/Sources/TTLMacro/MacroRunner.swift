/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Macro execution engine for TTLMacro.app.
 * Wraps TTLParser to execute .ttl scripts.
 * This is the integration point for the MacroParser / TTLInterpreter.
 */

import Foundation
import TTLMacroShared

// MARK: - MacroRunner

/// Executes TTL macro scripts. This class encapsulates the macro parser
/// and provides a simplified interface for the TTLMacro app.
///
/// Integration note: When migrating TTLInterpreter to this app,
/// replace the stub implementation with actual TTLInterpreter usage.
/// The TTLInterpreter needs to be refactored to work with XPC callbacks
/// instead of direct TTLInterpreterDelegate calls.
class MacroRunner {

    // MARK: - Callbacks

    /// Called when a line is executed. Parameters: (lineNumber, lineText)
    var onLineExecuted: ((Int, String) -> Void)?

    /// Called when macro execution completes. Parameter: exitCode
    var onComplete: ((Int) -> Void)?

    /// Called when macro execution fails. Parameters: (errorMessage, lineNumber)
    var onError: ((String, Int) -> Void)?

    // MARK: - State

    private(set) var isRunning: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var currentLineNumber: Int = 0
    private(set) var currentScriptPath: String?

    /// The XPC client proxy for communicating with TeraTermMac.app
    var clientProxy: MacroClientProtocol?

    // MARK: - Script Lines (stub parser)

    private var scriptLines: [String] = []
    private var execTimer: Timer?

    // MARK: - Execution

    func run(scriptPath: String) {
        guard !isRunning else { return }

        currentScriptPath = scriptPath

        // Load and parse the script file
        guard let content = try? String(contentsOfFile: scriptPath, encoding: .utf8) else {
            onError?(L("macro.error.noFile"), 0)
            return
        }

        scriptLines = content.components(separatedBy: .newlines)
        currentLineNumber = 0
        isRunning = true
        isPaused = false

        // Start execution loop
        scheduleNextLine()
    }

    func stop() {
        isRunning = false
        isPaused = false
        cancelExecTimer()

        let exitCode = 0
        onComplete?(exitCode)

        // Notify via XPC if connected
        clientProxy?.macroDidFinish(exitCode: exitCode, reply: {})
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        cancelExecTimer()
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        scheduleNextLine()
    }

    var status: MacroExecutionStatus {
        if !isRunning { return .idle }
        if isPaused { return .paused }
        return .running
    }

    // MARK: - Internal Execution (Stub)

    /// Schedule the next line for execution.
    /// In the real implementation, this delegates to TTLInterpreter.execStep().
    private func scheduleNextLine() {
        cancelExecTimer()
        guard isRunning, !isPaused else { return }

        execTimer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { [weak self] _ in
            self?.executeNextLine()
        }
    }

    private func executeNextLine() {
        guard isRunning, !isPaused else { return }

        if currentLineNumber >= scriptLines.count {
            // Script complete
            isRunning = false
            let exitCode = 0
            onComplete?(exitCode)
            clientProxy?.macroDidFinish(exitCode: exitCode, reply: {})
            return
        }

        let line = scriptLines[currentLineNumber]
        currentLineNumber += 1

        // Notify line execution
        onLineExecuted?(currentLineNumber, line)
        clientProxy?.didExecuteLine(lineNumber: currentLineNumber, lineText: line, reply: {})

        // Process the line (stub: just skip comments and empty lines)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("//") {
            // Comment or empty line - continue immediately
            scheduleNextLine()
            return
        }

        // For stub: handle basic commands
        if trimmed.lowercased().hasPrefix("end") || trimmed.lowercased().hasPrefix("exit") {
            isRunning = false
            onComplete?(0)
            clientProxy?.macroDidFinish(exitCode: 0, reply: {})
            return
        }

        if trimmed.lowercased().hasPrefix("closett") {
            // Close TeraTermMac.app via XPC
            clientProxy?.terminateApp(reply: { [weak self] in
                self?.scheduleNextLine()
            })
            return
        }

        if trimmed.lowercased().hasPrefix("getttver") {
            // Get version via XPC
            clientProxy?.getAppVersion(reply: { [weak self] _ in
                self?.scheduleNextLine()
            })
            return
        }

        if trimmed.lowercased().hasPrefix("pause") {
            // Simple pause command
            let parts = trimmed.split(separator: " ")
            let seconds = parts.count > 1 ? Double(parts[1]) ?? 1.0 : 1.0
            execTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                self?.scheduleNextLine()
            }
            return
        }

        // Default: continue to next line
        scheduleNextLine()
    }

    private func cancelExecTimer() {
        execTimer?.invalidate()
        execTimer = nil
    }

    deinit {
        cancelExecTimer()
    }
}
