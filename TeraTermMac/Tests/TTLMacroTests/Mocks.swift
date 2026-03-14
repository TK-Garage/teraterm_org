/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Mock implementations for TTLMacro tests.
 */

import Foundation
import TTLMacroShared

// MARK: - MockMacroService

/// Mock implementation of MacroServiceProtocol for testing the client side.
class MockMacroService: NSObject, MacroServiceProtocol {

    var runMacroCalled = false
    var lastScriptPath: String?
    var stopMacroCalled = false
    var pauseMacroCalled = false
    var resumeMacroCalled = false
    var macroStatusCalled = false
    var sendVariableCalled = false
    var lastVariableName: String?
    var lastVariableValue: String?
    var currentStatus: String = MacroExecutionStatus.idle.rawValue

    func runMacro(scriptPath: String, reply: @escaping (NSError?) -> Void) {
        runMacroCalled = true
        lastScriptPath = scriptPath
        reply(nil)
    }

    func stopMacro(reply: @escaping () -> Void) {
        stopMacroCalled = true
        currentStatus = MacroExecutionStatus.stopped.rawValue
        reply()
    }

    func pauseMacro(reply: @escaping () -> Void) {
        pauseMacroCalled = true
        currentStatus = MacroExecutionStatus.paused.rawValue
        reply()
    }

    func resumeMacro(reply: @escaping () -> Void) {
        resumeMacroCalled = true
        currentStatus = MacroExecutionStatus.running.rawValue
        reply()
    }

    func macroStatus(reply: @escaping (String) -> Void) {
        macroStatusCalled = true
        reply(currentStatus)
    }

    func sendVariable(name: String, value: String, reply: @escaping () -> Void) {
        sendVariableCalled = true
        lastVariableName = name
        lastVariableValue = value
        reply()
    }

    func reset() {
        runMacroCalled = false
        lastScriptPath = nil
        stopMacroCalled = false
        pauseMacroCalled = false
        resumeMacroCalled = false
        macroStatusCalled = false
        sendVariableCalled = false
        lastVariableName = nil
        lastVariableValue = nil
        currentStatus = MacroExecutionStatus.idle.rawValue
    }
}

// MARK: - MockMacroClient

/// Mock implementation of MacroClientProtocol for testing the service side.
class MockMacroClient: NSObject, MacroClientProtocol {

    var sendToTerminalCalled = false
    var lastSentData: Data?
    var recvFromTerminalCalled = false
    var showDialogCalled = false
    var lastDialogType: String?
    var lastDialogMessage: String?
    var setWindowTitleCalled = false
    var lastWindowTitle: String?
    var macroDidFinishCalled = false
    var lastExitCode: Int = -1
    var macroDidFailCalled = false
    var lastError: String?
    var lastErrorLine: Int = -1
    var logMessageCalled = false
    var terminateAppCalled = false
    var getAppVersionCalled = false
    var didExecuteLineCalled = false
    var lastExecutedLineNumber: Int = -1
    var lastExecutedLineText: String?
    var executedLineNumbers: [Int] = []

    // Configurable responses
    var recvData: Data?
    var dialogResult: (Int, String) = (1, "")
    var appVersion: String = "1.0.0"

    func sendToTerminal(data: Data, reply: @escaping () -> Void) {
        sendToTerminalCalled = true
        lastSentData = data
        reply()
    }

    func recvFromTerminal(timeout: Int, reply: @escaping (Data?) -> Void) {
        recvFromTerminalCalled = true
        reply(recvData)
    }

    func showDialog(type: String, message: String, defaultValue: String,
                    reply: @escaping (Int, String) -> Void) {
        showDialogCalled = true
        lastDialogType = type
        lastDialogMessage = message
        reply(dialogResult.0, dialogResult.1)
    }

    func setWindowTitle(title: String, reply: @escaping () -> Void) {
        setWindowTitleCalled = true
        lastWindowTitle = title
        reply()
    }

    func macroDidFinish(exitCode: Int, reply: @escaping () -> Void) {
        macroDidFinishCalled = true
        lastExitCode = exitCode
        reply()
    }

    func macroDidFail(error: String, line: Int, reply: @escaping () -> Void) {
        macroDidFailCalled = true
        lastError = error
        lastErrorLine = line
        reply()
    }

    func logMessage(level: String, text: String, reply: @escaping () -> Void) {
        logMessageCalled = true
        reply()
    }

    func terminateApp(reply: @escaping () -> Void) {
        terminateAppCalled = true
        reply()
    }

    func getAppVersion(reply: @escaping (String) -> Void) {
        getAppVersionCalled = true
        reply(appVersion)
    }

    func didExecuteLine(lineNumber: Int, lineText: String, reply: @escaping () -> Void) {
        didExecuteLineCalled = true
        lastExecutedLineNumber = lineNumber
        lastExecutedLineText = lineText
        executedLineNumbers.append(lineNumber)
        reply()
    }

    func reset() {
        sendToTerminalCalled = false
        lastSentData = nil
        recvFromTerminalCalled = false
        showDialogCalled = false
        lastDialogType = nil
        lastDialogMessage = nil
        setWindowTitleCalled = false
        lastWindowTitle = nil
        macroDidFinishCalled = false
        lastExitCode = -1
        macroDidFailCalled = false
        lastError = nil
        lastErrorLine = -1
        logMessageCalled = false
        terminateAppCalled = false
        getAppVersionCalled = false
        didExecuteLineCalled = false
        lastExecutedLineNumber = -1
        lastExecutedLineText = nil
        executedLineNumbers = []
    }
}
