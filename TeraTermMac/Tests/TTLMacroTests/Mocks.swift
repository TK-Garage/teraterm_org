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

    // New terminal operation methods (required by MacroClientProtocol)
    var isConnectedResponse: Bool = false
    var isXPCLinkedResponse: Bool = true

    func isConnected(reply: @escaping (Bool) -> Void) { reply(isConnectedResponse) }
    func isXPCLinked(reply: @escaping (Bool) -> Void) { reply(isXPCLinkedResponse) }
    func getWindowTitle(reply: @escaping (String) -> Void) { reply("") }
    func showWindow(visible: Bool, reply: @escaping () -> Void) { reply() }
    func clearScreen(reply: @escaping () -> Void) { reply() }
    func sendBreak(reply: @escaping () -> Void) { reply() }
    func disconnectFromHost(reply: @escaping () -> Void) { reply() }
    func connectToHost(param: String, reply: @escaping (Bool) -> Void) { reply(true) }
    func connectLocalShell(reply: @escaping (Bool) -> Void) { reply(true) }
    func flushReceiveBuffer(reply: @escaping () -> Void) { reply() }
    func moveWindow(x: Int, y: Int, reply: @escaping () -> Void) { reply() }
    func resizeWindow(width: Int, height: Int, reply: @escaping () -> Void) { reply() }
    func bringWindowToFront(reply: @escaping () -> Void) { reply() }
    func getWindowPosition(reply: @escaping (Int, Int) -> Void) { reply(0, 0) }
    func setBaudRate(rate: Int, reply: @escaping () -> Void) { reply() }
    func setFlowControl(mode: Int, reply: @escaping () -> Void) { reply() }
    func setDtr(on: Int, reply: @escaping () -> Void) { reply() }
    func setRts(on: Int, reply: @escaping () -> Void) { reply() }
    func getModemStatus(reply: @escaping (Int) -> Void) { reply(0) }
    func setSerialDelayChar(ms: Int, reply: @escaping () -> Void) { reply() }
    func setSerialDelayLine(ms: Int, reply: @escaping () -> Void) { reply() }
    func openLog(path: String, append: Bool, reply: @escaping () -> Void) { reply() }
    func closeLog(reply: @escaping () -> Void) { reply() }
    func pauseLog(reply: @escaping () -> Void) { reply() }
    func resumeLog(reply: @escaping () -> Void) { reply() }
    func writeToLog(text: String, reply: @escaping () -> Void) { reply() }
    func getLogInfo(reply: @escaping (Int, String) -> Void) { reply(0, "") }
    func setLogRotation(mode: String, value: Int, reply: @escaping () -> Void) { reply() }
    func getClipboard(reply: @escaping (String) -> Void) { reply("") }
    func setClipboard(text: String, reply: @escaping () -> Void) { reply() }
    func getHostname(reply: @escaping (String) -> Void) { reply("localhost") }
    func getAppDirectory(reply: @escaping (String) -> Void) { reply("/tmp") }
    func showError(message: String, line: Int, lineText: String, fileName: String,
                   reply: @escaping (Bool) -> Void) { reply(true) }
    func showStatusBox(message: String, title: String, reply: @escaping () -> Void) { reply() }
    func closeStatusBox(reply: @escaping () -> Void) { reply() }
    func startFileSend(protocolName: String, localPath: String, option: String,
                       reply: @escaping (Bool, String) -> Void) { reply(true, "") }
    func startFileRecv(protocolName: String, localDir: String,
                       reply: @escaping (Bool, String, String) -> Void) { reply(true, "", "") }
    func getTransferStatus(reply: @escaping (String, Int, Int) -> Void) { reply("done", 0, 0) }
    func cancelTransfer(reply: @escaping () -> Void) { reply() }
    func scpSend(localPath: String, remotePath: String, reply: @escaping (Bool) -> Void) { reply(true) }
    func scpRecv(remotePath: String, localPath: String, reply: @escaping (Bool) -> Void) { reply(true) }
    func restoreSetup(path: String, reply: @escaping () -> Void) { reply() }
    func callMenu(menuId: Int, reply: @escaping () -> Void) { reply() }
    func loadKeyMap(path: String, reply: @escaping () -> Void) { reply() }
    func enableKeyboard(flag: Int, reply: @escaping () -> Void) { reply() }
    func setEcho(flag: Int, reply: @escaping () -> Void) { reply() }
    func displayString(text: String, reply: @escaping () -> Void) { reply() }
    func sendPasswordData(data: Data, reply: @escaping () -> Void) { reply() }

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
