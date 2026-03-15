/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * XPC connection tests for TTLMacro.
 */

import XCTest
import TTLMacroShared

final class XPCConnectionTests: XCTestCase {

    // MARK: - Protocol Interface Tests

    func testServiceInterfaceCreation() {
        let interface = MacroXPCInterface.serviceInterface()
        XCTAssertNotNil(interface)
    }

    func testClientInterfaceCreation() {
        let interface = MacroXPCInterface.clientInterface()
        XCTAssertNotNil(interface)
    }

    // MARK: - Mock Service Tests

    func testMockServiceRunMacro() {
        let mock = MockMacroService()
        let expectation = XCTestExpectation(description: "runMacro reply")

        mock.runMacro(scriptPath: "/tmp/test.ttl") { error in
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.runMacroCalled)
        XCTAssertEqual(mock.lastScriptPath, "/tmp/test.ttl")
    }

    func testMockServiceStopMacro() {
        let mock = MockMacroService()
        let expectation = XCTestExpectation(description: "stopMacro reply")

        mock.stopMacro {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.stopMacroCalled)
        XCTAssertEqual(mock.currentStatus, MacroExecutionStatus.stopped.rawValue)
    }

    func testMockServicePauseMacro() {
        let mock = MockMacroService()
        let expectation = XCTestExpectation(description: "pauseMacro reply")

        mock.pauseMacro {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.pauseMacroCalled)
        XCTAssertEqual(mock.currentStatus, MacroExecutionStatus.paused.rawValue)
    }

    func testMockServiceResumeMacro() {
        let mock = MockMacroService()
        let expectation = XCTestExpectation(description: "resumeMacro reply")

        mock.resumeMacro {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.resumeMacroCalled)
        XCTAssertEqual(mock.currentStatus, MacroExecutionStatus.running.rawValue)
    }

    func testMockServiceMacroStatus() {
        let mock = MockMacroService()
        mock.currentStatus = MacroExecutionStatus.running.rawValue
        let expectation = XCTestExpectation(description: "macroStatus reply")

        mock.macroStatus { status in
            XCTAssertEqual(status, MacroExecutionStatus.running.rawValue)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.macroStatusCalled)
    }

    func testMockServiceSendVariable() {
        let mock = MockMacroService()
        let expectation = XCTestExpectation(description: "sendVariable reply")

        mock.sendVariable(name: "testVar", value: "testValue") {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.sendVariableCalled)
        XCTAssertEqual(mock.lastVariableName, "testVar")
        XCTAssertEqual(mock.lastVariableValue, "testValue")
    }

    // MARK: - Mock Client Tests

    func testMockClientTerminateApp() {
        let mock = MockMacroClient()
        let expectation = XCTestExpectation(description: "terminateApp reply")

        mock.terminateApp {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.terminateAppCalled)
    }

    func testMockClientGetAppVersion() {
        let mock = MockMacroClient()
        mock.appVersion = "2.5.1"
        let expectation = XCTestExpectation(description: "getAppVersion reply")

        mock.getAppVersion { version in
            XCTAssertEqual(version, "2.5.1")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.getAppVersionCalled)
    }

    func testMockClientDidExecuteLine() {
        let mock = MockMacroClient()
        let expectation = XCTestExpectation(description: "didExecuteLine reply")

        mock.didExecuteLine(lineNumber: 42, lineText: "send 'hello'") {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.didExecuteLineCalled)
        XCTAssertEqual(mock.lastExecutedLineNumber, 42)
        XCTAssertEqual(mock.lastExecutedLineText, "send 'hello'")
    }

    func testMockClientSendToTerminal() {
        let mock = MockMacroClient()
        let testData = "Hello".data(using: .utf8)!
        let expectation = XCTestExpectation(description: "sendToTerminal reply")

        mock.sendToTerminal(data: testData) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.sendToTerminalCalled)
        XCTAssertEqual(mock.lastSentData, testData)
    }

    func testMockClientShowDialog() {
        let mock = MockMacroClient()
        mock.dialogResult = (1, "user input")
        let expectation = XCTestExpectation(description: "showDialog reply")

        mock.showDialog(type: "inputbox", message: "Enter:", defaultValue: "") { result, text in
            XCTAssertEqual(result, 1)
            XCTAssertEqual(text, "user input")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.showDialogCalled)
        XCTAssertEqual(mock.lastDialogType, "inputbox")
    }

    func testMockClientMacroDidFinish() {
        let mock = MockMacroClient()
        let expectation = XCTestExpectation(description: "macroDidFinish reply")

        mock.macroDidFinish(exitCode: 0) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.macroDidFinishCalled)
        XCTAssertEqual(mock.lastExitCode, 0)
    }

    func testMockClientMacroDidFail() {
        let mock = MockMacroClient()
        let expectation = XCTestExpectation(description: "macroDidFail reply")

        mock.macroDidFail(error: "Syntax error", line: 10) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mock.macroDidFailCalled)
        XCTAssertEqual(mock.lastError, "Syntax error")
        XCTAssertEqual(mock.lastErrorLine, 10)
    }

    // MARK: - XPC Mode Detection Tests

    func testXPCModeArgument() {
        XCTAssertEqual(MacroConstants.xpcModeArgument, "--xpc-mode")
    }

    func testXPCServiceName() {
        XCTAssertEqual(kTTLMacroXPCServiceName, "com.yourapp.TeraTermMac.TTLMacro")
    }

    // MARK: - Reset Tests

    func testMockServiceReset() {
        let mock = MockMacroService()
        mock.runMacroCalled = true
        mock.lastScriptPath = "/test"
        mock.reset()
        XCTAssertFalse(mock.runMacroCalled)
        XCTAssertNil(mock.lastScriptPath)
    }

    func testMockClientReset() {
        let mock = MockMacroClient()
        mock.terminateAppCalled = true
        mock.lastExitCode = 42
        mock.executedLineNumbers = [1, 2, 3]
        mock.reset()
        XCTAssertFalse(mock.terminateAppCalled)
        XCTAssertEqual(mock.lastExitCode, -1)
        XCTAssertTrue(mock.executedLineNumbers.isEmpty)
    }
}
