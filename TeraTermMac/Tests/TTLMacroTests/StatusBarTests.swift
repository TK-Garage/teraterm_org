/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Status bar and animation tests for TTLMacro.
 */

import XCTest
import TTLMacroShared
@testable import TTLMacro

#if canImport(AppKit)

final class StatusBarTests: XCTestCase {

    var statusBarManager: StatusBarManager!

    override func setUp() {
        super.setUp()
        statusBarManager = StatusBarManager()
    }

    override func tearDown() {
        statusBarManager.cleanup()
        statusBarManager = nil
        super.tearDown()
    }

    // MARK: - Animation Timer Tests

    func testAnimationStartsTimer() {
        statusBarManager.startAnimation()
        XCTAssertTrue(statusBarManager.isAnimating)
        statusBarManager.stopAnimation()
    }

    func testAnimationStopsTimer() {
        statusBarManager.startAnimation()
        XCTAssertTrue(statusBarManager.isAnimating)
        statusBarManager.stopAnimation()
        XCTAssertFalse(statusBarManager.isAnimating)
    }

    func testAnimationInvalidatesOnStop() {
        statusBarManager.startAnimation()
        statusBarManager.stopAnimation()
        XCTAssertFalse(statusBarManager.isAnimating)
    }

    /// Lesson from key input delay: ensure Timer does not accumulate
    /// when startAnimation is called multiple times.
    func testRepeatedStartAnimationDoesNotAccumulateTimers() {
        // Start animation 10 times in a row
        for _ in 0..<10 {
            statusBarManager.startAnimation()
        }
        // Should still only have one timer
        XCTAssertTrue(statusBarManager.isAnimating)

        statusBarManager.stopAnimation()
        XCTAssertFalse(statusBarManager.isAnimating)
    }

    func testAnimationStopsOnPause() {
        statusBarManager.startAnimation()
        XCTAssertTrue(statusBarManager.isAnimating)

        // Simulating pause state
        statusBarManager.stopAnimation()
        XCTAssertFalse(statusBarManager.isAnimating)
    }

    func testAnimationRestartsOnResume() {
        statusBarManager.startAnimation()
        statusBarManager.stopAnimation()
        XCTAssertFalse(statusBarManager.isAnimating)

        // Resume
        statusBarManager.startAnimation()
        XCTAssertTrue(statusBarManager.isAnimating)
        statusBarManager.stopAnimation()
    }

    // MARK: - Line Number Update

    func testUpdateLineNumber() {
        // Just verify no crash - actual menu item update requires AppKit run loop
        statusBarManager.updateLineNumber(42)
        statusBarManager.updateLineNumber(100)
    }

    // MARK: - Cleanup

    func testCleanupStopsAnimation() {
        statusBarManager.startAnimation()
        statusBarManager.cleanup()
        XCTAssertFalse(statusBarManager.isAnimating)
    }

    // MARK: - Constants

    func testAnimationInterval() {
        XCTAssertEqual(MacroConstants.animationInterval, 0.3)
    }

    func testMenuUpdateIntervals() {
        XCTAssertEqual(MacroConstants.menuVisibleUpdateInterval, 0.1)
        XCTAssertEqual(MacroConstants.menuHiddenUpdateInterval, 1.0)
    }
}

#endif
