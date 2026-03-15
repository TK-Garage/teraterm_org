/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Launch flow tests for TTLMacro.
 */

import XCTest
import TTLMacroShared
@testable import TTLMacro

final class LaunchFlowTests: XCTestCase {

    // MARK: - XPC Mode Detection

    func testXPCModeDetectionWithArgument() {
        // The isXPCMode property checks CommandLine.arguments
        // We test the constant used for detection
        XCTAssertEqual(MacroConstants.xpcModeArgument, "--xpc-mode")
    }

    func testXPCModeArgumentConstant() {
        let args = ["TTLMacro", "--xpc-mode"]
        XCTAssertTrue(args.contains(MacroConstants.xpcModeArgument))
    }

    func testDirectLaunchDetection() {
        let args = ["TTLMacro"]
        XCTAssertFalse(args.contains(MacroConstants.xpcModeArgument))
    }

    // MARK: - MacroRunner Basic Tests

    func testMacroRunnerInitialState() {
        let runner = MacroRunner()
        XCTAssertFalse(runner.isRunning)
        XCTAssertFalse(runner.isPaused)
        XCTAssertEqual(runner.currentLineNumber, 0)
        XCTAssertNil(runner.currentScriptPath)
        XCTAssertEqual(runner.status, MacroExecutionStatus.idle)
    }

    func testMacroRunnerRunNonexistentFile() {
        let runner = MacroRunner()
        var errorReceived = false

        runner.onError = { _, _ in
            errorReceived = true
        }

        runner.run(scriptPath: "/nonexistent/path/test.ttl")

        // Should get error callback for missing file
        XCTAssertTrue(errorReceived)
        XCTAssertFalse(runner.isRunning)
    }

    func testMacroRunnerRunValidFile() {
        let runner = MacroRunner()

        // Create a temporary test file
        let tempPath = NSTemporaryDirectory() + "test_launch_\(UUID().uuidString).ttl"
        try? "end\n".write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let expectation = XCTestExpectation(description: "macro complete")

        runner.onComplete = { exitCode in
            XCTAssertEqual(exitCode, 0)
            expectation.fulfill()
        }

        runner.run(scriptPath: tempPath)
        XCTAssertEqual(runner.currentScriptPath, tempPath)

        wait(for: [expectation], timeout: 5.0)
    }

    func testMacroRunnerWithXPCClient() {
        let runner = MacroRunner()
        let mockClient = MockMacroClient()
        runner.clientProxy = mockClient

        let tempPath = NSTemporaryDirectory() + "test_xpc_\(UUID().uuidString).ttl"
        try? "; comment\nend\n".write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let expectation = XCTestExpectation(description: "macro complete with XPC")

        runner.onComplete = { _ in
            expectation.fulfill()
        }

        runner.run(scriptPath: tempPath)

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mockClient.macroDidFinishCalled)
    }

    // MARK: - Pattern B: XPC Service Handler

    func testXPCServiceHandlerCreation() {
        let runner = MacroRunner()
        let handler = XPCServiceHandler(macroRunner: runner)
        XCTAssertNotNil(handler)
    }

    func testXPCServiceRunMacroWithMissingFile() {
        let runner = MacroRunner()
        let handler = XPCServiceHandler(macroRunner: runner)
        let expectation = XCTestExpectation(description: "error reply")

        handler.runMacro(scriptPath: "/nonexistent.ttl") { error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testXPCServiceRunMacroWithValidFile() {
        let runner = MacroRunner()
        let handler = XPCServiceHandler(macroRunner: runner)

        let tempPath = NSTemporaryDirectory() + "test_svc_\(UUID().uuidString).ttl"
        try? "end\n".write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let expectation = XCTestExpectation(description: "success reply")

        handler.runMacro(scriptPath: tempPath) { error in
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testXPCServiceStopMacro() {
        let runner = MacroRunner()
        let handler = XPCServiceHandler(macroRunner: runner)
        let expectation = XCTestExpectation(description: "stop reply")

        handler.stopMacro {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testXPCServicePauseResumeMacro() {
        let runner = MacroRunner()
        let handler = XPCServiceHandler(macroRunner: runner)

        let pauseExpectation = XCTestExpectation(description: "pause reply")
        handler.pauseMacro {
            pauseExpectation.fulfill()
        }
        wait(for: [pauseExpectation], timeout: 5.0)

        let resumeExpectation = XCTestExpectation(description: "resume reply")
        handler.resumeMacro {
            resumeExpectation.fulfill()
        }
        wait(for: [resumeExpectation], timeout: 5.0)
    }

    func testXPCServiceMacroStatus() {
        let runner = MacroRunner()
        let handler = XPCServiceHandler(macroRunner: runner)
        let expectation = XCTestExpectation(description: "status reply")

        handler.macroStatus { status in
            XCTAssertEqual(status, MacroExecutionStatus.idle.rawValue)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Line Execution Callback

    func testLineExecutionCallback() {
        let runner = MacroRunner()
        var executedLines: [Int] = []

        let tempPath = NSTemporaryDirectory() + "test_lines_\(UUID().uuidString).ttl"
        try? "; line 1\n; line 2\n; line 3\nend\n".write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let expectation = XCTestExpectation(description: "lines executed")

        runner.onLineExecuted = { lineNumber, _ in
            executedLines.append(lineNumber)
        }

        runner.onComplete = { _ in
            expectation.fulfill()
        }

        runner.run(scriptPath: tempPath)

        wait(for: [expectation], timeout: 5.0)
        XCTAssertFalse(executedLines.isEmpty)
    }
}
