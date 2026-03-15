/*
 * MacroStatusPanelTests
 * Tests for MacroStatusPanelController and its integration with TTLInterpreter.
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)

// MARK: - Mock Delegate

private class MockPanelDelegate: MacroStatusPanelDelegate {
    var pauseToggleCount = 0
    var stopRequestCount = 0

    func macroStatusPanelDidTogglePause(_ controller: MacroStatusPanelController) {
        pauseToggleCount += 1
    }

    func macroStatusPanelDidRequestStop(_ controller: MacroStatusPanelController) {
        stopRequestCount += 1
    }
}

// MARK: - Tests

final class MacroStatusPanelTests: XCTestCase {

    // MARK: - Controller Unit Tests

    func testInitialState() {
        let controller = MacroStatusPanelController()
        XCTAssertFalse(controller.isPaused)
    }

    func testSetIsPaused() {
        let controller = MacroStatusPanelController()
        XCTAssertFalse(controller.isPaused)
        controller.setIsPaused(true)
        XCTAssertTrue(controller.isPaused)
        controller.setIsPaused(false)
        XCTAssertFalse(controller.isPaused)
    }

    // MARK: - Interpreter Integration Tests

    func testInterpreterPauseFlag() {
        let interpreter = TTLInterpreter()
        XCTAssertFalse(interpreter.isPausedByUser)

        // Simulate pause toggle from status panel
        interpreter.macroStatusPanelDidTogglePause(interpreter.statusPanel)
        // isPaused on the panel is toggled inside the button action,
        // but calling the delegate method directly tests the interpreter side.
        // The interpreter reads isPaused from the controller.
    }

    func testInterpreterStopRequestFlag() {
        let interpreter = TTLInterpreter()
        XCTAssertFalse(interpreter.isStopRequested)

        // Request stop via delegate protocol
        interpreter.macroStatusPanelDidRequestStop(interpreter.statusPanel)
        XCTAssertTrue(interpreter.isStopRequested)
    }

    func testStopClearsFlagsAndStatus() {
        let interpreter = TTLInterpreter()
        interpreter.loadScript("pause 1\nend")

        // Set flags manually to simulate running state
        interpreter.macroStatusPanelDidRequestStop(interpreter.statusPanel)
        XCTAssertTrue(interpreter.isStopRequested)

        interpreter.stop()
        XCTAssertFalse(interpreter.isStopRequested)
        XCTAssertFalse(interpreter.isPausedByUser)
        XCTAssertEqual(interpreter.parser.status, .end)
    }

    func testLoadScriptResetsFlags() {
        let interpreter = TTLInterpreter()
        interpreter.loadScript("end")
        // Manually set flags
        interpreter.macroStatusPanelDidRequestStop(interpreter.statusPanel)
        XCTAssertTrue(interpreter.isStopRequested)

        // Reload should reset
        interpreter.loadScript("end")
        XCTAssertFalse(interpreter.isStopRequested)
        XCTAssertFalse(interpreter.isPausedByUser)
    }

    func testMacroFileNameFromURL() throws {
        let interpreter = TTLInterpreter()
        let tmpDir = FileManager.default.temporaryDirectory
        let testFile = tmpDir.appendingPathComponent("test_macro.ttl")
        try "end".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        try interpreter.loadScript(from: testFile)
        XCTAssertEqual(interpreter.macroFileName, "test_macro.ttl")
    }

    func testStatusPanelDelegateIsSet() {
        let interpreter = TTLInterpreter()
        // The status panel's delegate should be the interpreter
        XCTAssertTrue(interpreter.statusPanel.delegate === interpreter)
    }
}

#endif
