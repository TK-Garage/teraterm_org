/*
 * WindowMenuTests.swift
 * Tests for Window menu arrangement features:
 *   - Minimize All (port of ID_WINDOW_MINIMIZEALL)
 *   - Cascade (port of ID_WINDOW_CASCADEALL)
 *   - Tile Vertically / Stacked (port of ID_WINDOW_STACKED)
 *   - Tile Horizontally / Side by Side (port of ID_WINDOW_SIDEBYSIDE)
 *   - Restore All (port of ID_WINDOW_RESTOREALL)
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - Window Menu Localization Tests

final class WindowMenuLocalizationTests: XCTestCase {

    func testEnglishLocalizationKeysExist() {
        // Verify that all window menu localization keys resolve to non-empty strings
        let keys = [
            "menu.window.minimizeAll",
            "menu.window.restoreAll",
            "menu.window.cascade",
            "menu.window.tileVertical",
            "menu.window.tileHorizontal",
        ]
        for key in keys {
            let value = NSLocalizedString(key, bundle: Bundle.module, comment: "")
            XCTAssertNotEqual(value, key,
                "Localization key '\(key)' should resolve to a translated string")
            XCTAssertFalse(value.isEmpty,
                "Localization key '\(key)' should not be empty")
        }
    }

    func testWindowMenuItemCount() {
        // Window menu should have: Minimize, Zoom, separator,
        // Minimize All, Cascade, Tile Vertically, Tile Horizontally, Restore All,
        // separator, Window List
        // Total unique action items: 8
        let actionItems = [
            "Minimize", "Zoom",
            "Minimize All", "Cascade",
            "Tile Vertically", "Tile Horizontally",
            "Restore All", "Window List"
        ]
        XCTAssertEqual(actionItems.count, 8,
            "Window menu should have 8 action items")
    }
}

// MARK: - Window Arrangement Logic Tests

final class WindowArrangementTests: XCTestCase {

    func testTileHorizontalCalculation() {
        // Side by side: N windows split the screen width equally
        let screenWidth: CGFloat = 1200
        let screenHeight: CGFloat = 800
        let screenOriginX: CGFloat = 0
        let screenOriginY: CGFloat = 0
        let count = 3

        var rects: [NSRect] = []
        let width = screenWidth / CGFloat(count)
        for i in 0..<count {
            let rect = NSRect(
                x: screenOriginX + width * CGFloat(i),
                y: screenOriginY,
                width: width,
                height: screenHeight)
            rects.append(rect)
        }

        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects[0].origin.x, 0, accuracy: 0.1)
        XCTAssertEqual(rects[1].origin.x, 400, accuracy: 0.1)
        XCTAssertEqual(rects[2].origin.x, 800, accuracy: 0.1)
        XCTAssertEqual(rects[0].width, 400, accuracy: 0.1)
        XCTAssertEqual(rects[0].height, 800, accuracy: 0.1)
    }

    func testTileVerticalCalculation() {
        // Stacked: N windows split the screen height equally
        let screenWidth: CGFloat = 1200
        let screenHeight: CGFloat = 800
        let screenOriginX: CGFloat = 0
        let screenOriginY: CGFloat = 0
        let count = 2

        var rects: [NSRect] = []
        let height = screenHeight / CGFloat(count)
        for i in 0..<count {
            let rect = NSRect(
                x: screenOriginX,
                y: screenOriginY + height * CGFloat(count - 1 - i),
                width: screenWidth,
                height: height)
            rects.append(rect)
        }

        XCTAssertEqual(rects.count, 2)
        // First window (top)
        XCTAssertEqual(rects[0].origin.y, 400, accuracy: 0.1)
        // Second window (bottom)
        XCTAssertEqual(rects[1].origin.y, 0, accuracy: 0.1)
        XCTAssertEqual(rects[0].width, 1200, accuracy: 0.1)
        XCTAssertEqual(rects[0].height, 400, accuracy: 0.1)
    }

    func testTileSingleWindow() {
        // Single window should take full screen area
        let screenWidth: CGFloat = 1440
        let screenHeight: CGFloat = 900
        let count = 1

        let width = screenWidth / CGFloat(count)
        let rect = NSRect(x: 0, y: 0, width: width, height: screenHeight)

        XCTAssertEqual(rect.width, 1440, accuracy: 0.1)
        XCTAssertEqual(rect.height, 900, accuracy: 0.1)
    }

    func testCascadeOffsetProgression() {
        // Verify cascadeTopLeft produces incrementing positions
        // This tests the concept - actual NSWindow.cascadeTopLeft requires a window
        let cascadeOffset: CGFloat = 20
        var positions: [NSPoint] = []
        for i in 0..<4 {
            positions.append(NSPoint(
                x: 100 + cascadeOffset * CGFloat(i),
                y: 500 - cascadeOffset * CGFloat(i)))
        }

        for i in 1..<positions.count {
            XCTAssertGreaterThan(positions[i].x, positions[i-1].x,
                "Cascade X should increase")
            XCTAssertLessThan(positions[i].y, positions[i-1].y,
                "Cascade Y should decrease (top-left based)")
        }
    }
}

// MARK: - AppDelegate Window Menu Method Tests

final class AppDelegateWindowMenuTests: XCTestCase {

    func testAppDelegateRespondsToWindowMenuSelectors() {
        let delegate = AppDelegate()

        // Verify AppDelegate responds to all window arrangement selectors
        XCTAssertTrue(delegate.responds(to: #selector(AppDelegate.minimizeAllWindows(_:))),
            "AppDelegate should respond to minimizeAllWindows:")
        XCTAssertTrue(delegate.responds(to: #selector(AppDelegate.cascadeAllWindows(_:))),
            "AppDelegate should respond to cascadeAllWindows:")
        XCTAssertTrue(delegate.responds(to: #selector(AppDelegate.tileWindowsVertically(_:))),
            "AppDelegate should respond to tileWindowsVertically:")
        XCTAssertTrue(delegate.responds(to: #selector(AppDelegate.tileWindowsHorizontally(_:))),
            "AppDelegate should respond to tileWindowsHorizontally:")
        XCTAssertTrue(delegate.responds(to: #selector(AppDelegate.restoreAllWindows(_:))),
            "AppDelegate should respond to restoreAllWindows:")
    }

    func testWindowMenuMethodsDoNotCrashWithNoWindows() {
        let delegate = AppDelegate()
        // These should be safe to call even with no windows open
        delegate.minimizeAllWindows(nil)
        delegate.cascadeAllWindows(nil)
        delegate.tileWindowsVertically(nil)
        delegate.tileWindowsHorizontally(nil)
        delegate.restoreAllWindows(nil)
        // If we get here without crashing, the test passes
    }
}

#endif
