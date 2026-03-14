/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Macro command execution tests using test .ttl files.
 */

import XCTest
import TTLMacroShared
@testable import TTLMacro

final class MacroCommandTests: XCTestCase {

    var runner: MacroRunner!
    var mockClient: MockMacroClient!

    override func setUp() {
        super.setUp()
        runner = MacroRunner()
        mockClient = MockMacroClient()
        runner.clientProxy = mockClient
    }

    override func tearDown() {
        runner = nil
        mockClient = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func createTempScript(_ content: String) -> String {
        let path = NSTemporaryDirectory() + "test_cmd_\(UUID().uuidString).ttl"
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func runAndWait(_ path: String, timeout: TimeInterval = 5.0) {
        let expectation = XCTestExpectation(description: "macro complete")
        runner.onComplete = { _ in expectation.fulfill() }
        runner.onError = { _, _ in expectation.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [expectation], timeout: timeout)
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Comment and Empty Lines

    func testCommentLines() {
        let path = createTempScript("; This is a comment\n// Another comment\n\nend\n")
        runAndWait(path)
        XCTAssertFalse(runner.isRunning)
    }

    // MARK: - End Command

    func testEndCommand() {
        let path = createTempScript("end\n")
        let expectation = XCTestExpectation(description: "end command")

        runner.onComplete = { exitCode in
            XCTAssertEqual(exitCode, 0)
            expectation.fulfill()
        }

        runner.run(scriptPath: path)
        wait(for: [expectation], timeout: 5.0)
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Exit Command

    func testExitCommand() {
        let path = createTempScript("exit\n")
        let expectation = XCTestExpectation(description: "exit command")

        runner.onComplete = { exitCode in
            XCTAssertEqual(exitCode, 0)
            expectation.fulfill()
        }

        runner.run(scriptPath: path)
        wait(for: [expectation], timeout: 5.0)
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Pause Command

    func testPauseCommand() {
        let path = createTempScript("pause 1\nend\n")
        let start = Date()
        let expectation = XCTestExpectation(description: "pause command")

        runner.onComplete = { _ in
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertGreaterThanOrEqual(elapsed, 0.8) // Allow some tolerance
            expectation.fulfill()
        }

        runner.run(scriptPath: path)
        wait(for: [expectation], timeout: 5.0)
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - CloseTT Command

    func testCloseTTCommand() {
        let path = createTempScript("closett\nend\n")
        let expectation = XCTestExpectation(description: "closett command")

        runner.onComplete = { _ in
            expectation.fulfill()
        }

        runner.run(scriptPath: path)
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mockClient.terminateAppCalled)
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - GetTTVer Command

    func testGetTTVerCommand() {
        let path = createTempScript("getttver\nend\n")
        mockClient.appVersion = "5.6.0"
        let expectation = XCTestExpectation(description: "getttver command")

        runner.onComplete = { _ in
            expectation.fulfill()
        }

        runner.run(scriptPath: path)
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(mockClient.getAppVersionCalled)
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Line Execution Tracking

    func testLineNumberTracking() {
        let path = createTempScript("; line 1\n; line 2\n; line 3\nend\n")
        var lineNumbers: [Int] = []

        runner.onLineExecuted = { lineNumber, _ in
            lineNumbers.append(lineNumber)
        }

        runAndWait(path)

        // Should have tracked all executed lines
        XCTAssertFalse(lineNumbers.isEmpty)
        // Lines should be in order
        for i in 1..<lineNumbers.count {
            XCTAssertGreaterThanOrEqual(lineNumbers[i], lineNumbers[i-1])
        }
    }

    func testDidExecuteLineXPCCallback() {
        let path = createTempScript("; line\nend\n")
        runAndWait(path)
        XCTAssertTrue(mockClient.didExecuteLineCalled)
        XCTAssertFalse(mockClient.executedLineNumbers.isEmpty)
    }

    // MARK: - MacroDidFinish via XPC

    func testMacroDidFinishCallsXPC() {
        let path = createTempScript("end\n")
        runAndWait(path)
        XCTAssertTrue(mockClient.macroDidFinishCalled)
        XCTAssertEqual(mockClient.lastExitCode, 0)
    }

    // MARK: - Multiple Script Execution

    func testCannotRunWhileAlreadyRunning() {
        let path1 = createTempScript("pause 2\nend\n")
        let path2 = createTempScript("end\n")

        runner.run(scriptPath: path1)
        XCTAssertTrue(runner.isRunning)

        // Second run should be ignored
        runner.run(scriptPath: path2)
        XCTAssertEqual(runner.currentScriptPath, path1)

        runner.stop()
        try? FileManager.default.removeItem(atPath: path1)
        try? FileManager.default.removeItem(atPath: path2)
    }

    // MARK: - Stop During Execution

    func testStopDuringExecution() {
        let path = createTempScript("pause 10\nend\n")
        let expectation = XCTestExpectation(description: "stop during execution")

        runner.onComplete = { _ in
            expectation.fulfill()
        }

        runner.run(scriptPath: path)
        XCTAssertTrue(runner.isRunning)

        // Stop after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.runner.stop()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertFalse(runner.isRunning)
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Pause and Resume

    func testPauseAndResume() {
        let path = createTempScript("pause 5\nend\n")

        runner.run(scriptPath: path)
        XCTAssertTrue(runner.isRunning)
        XCTAssertEqual(runner.status, MacroExecutionStatus.running)

        runner.pause()
        XCTAssertTrue(runner.isPaused)
        XCTAssertEqual(runner.status, MacroExecutionStatus.paused)

        runner.resume()
        XCTAssertFalse(runner.isPaused)
        XCTAssertEqual(runner.status, MacroExecutionStatus.running)

        runner.stop()
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Empty Script

    func testEmptyScript() {
        let path = createTempScript("")
        let expectation = XCTestExpectation(description: "empty script")

        runner.onComplete = { _ in
            expectation.fulfill()
        }

        runner.run(scriptPath: path)
        wait(for: [expectation], timeout: 5.0)
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Script With Only Comments

    func testScriptWithOnlyComments() {
        let path = createTempScript("; comment 1\n; comment 2\n; comment 3\n")
        let expectation = XCTestExpectation(description: "comments only")

        runner.onComplete = { _ in
            expectation.fulfill()
        }

        runner.run(scriptPath: path)
        wait(for: [expectation], timeout: 5.0)
        try? FileManager.default.removeItem(atPath: path)
    }
}
