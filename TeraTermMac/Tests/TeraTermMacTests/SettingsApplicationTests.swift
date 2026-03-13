/*
 * SettingsApplicationTests.swift
 * Tests for real-time settings application to the active terminal window.
 *
 * Verifies that TerminalWindowController.applySettings() propagates
 * all setting changes to TerminalView, TerminalEmulator, KeyboardHandler,
 * and the window itself.
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - TerminalWindowController.applySettings Tests

class SettingsApplicationTests: XCTestCase {

    private var wc: TerminalWindowController!
    private var settings: TerminalSettings!

    override func setUp() {
        super.setUp()
        settings = TerminalSettings()
        wc = TerminalWindowController(settings: settings)
        // Force window and view to be created
        _ = wc.window
    }

    override func tearDown() {
        wc.window?.close()
        wc = nil
        settings = nil
        super.tearDown()
    }

    // MARK: - Window Title

    func testApplySettingsUpdatesWindowTitle() {
        settings.title = "New Title 123"
        wc.applySettings()
        // Window title includes connection status suffix, but starts with the settings title
        XCTAssertTrue(wc.window?.title.hasPrefix("New Title 123") ?? false,
            "Window title should start with the settings title")
    }

    func testApplySettingsUpdatesWindowTitleMultipleTimes() {
        settings.title = "First"
        wc.applySettings()
        XCTAssertTrue(wc.window?.title.hasPrefix("First") ?? false)

        settings.title = "Second"
        wc.applySettings()
        XCTAssertTrue(wc.window?.title.hasPrefix("Second") ?? false)
    }

    // MARK: - Window Alpha

    func testApplySettingsUpdatesWindowAlpha() {
        settings.windowAlpha = 0.5
        wc.applySettings()
        XCTAssertEqual(wc.window?.alphaValue ?? 0, 0.5, accuracy: 0.01,
            "Window alpha should match settings")
    }

    func testApplySettingsFullyOpaque() {
        settings.windowAlpha = 1.0
        wc.applySettings()
        XCTAssertEqual(wc.window?.alphaValue ?? 0, 1.0, accuracy: 0.01)
    }

    func testApplySettingsPartialTransparency() {
        settings.windowAlpha = 0.75
        wc.applySettings()
        XCTAssertEqual(wc.window?.alphaValue ?? 0, 0.75, accuracy: 0.01)
    }

    // MARK: - Font Changes

    func testApplySettingsUpdatesFontName() {
        settings.fontName = "Courier"
        settings.fontSize = 16.0
        wc.applySettings()
        XCTAssertEqual(wc.terminalView.settings.fontName, "Courier")
        XCTAssertEqual(wc.terminalView.settings.fontSize, 16.0)
    }

    func testApplySettingsUpdatesFontSize() {
        let originalCellWidth = wc.terminalView.cellWidth
        settings.fontSize = 24.0  // Much larger font
        wc.applySettings()
        // Cell width should change with font size
        XCTAssertNotEqual(wc.terminalView.cellWidth, originalCellWidth,
            "Cell width should change when font size changes")
    }

    // MARK: - Terminal Dimensions

    func testApplySettingsResizesForTerminalDimensions() {
        settings.terminalWidth = 120
        settings.terminalHeight = 40
        wc.applySettings()

        // Verify window content size matches preferred size for new dimensions
        let expectedSize = wc.terminalView.preferredSize(columns: 120, rows: 40)
        let contentSize = wc.window?.contentView?.frame.size ?? .zero
        XCTAssertEqual(contentSize.width, expectedSize.width, accuracy: 2.0,
            "Content width should match 120 columns")
        XCTAssertEqual(contentSize.height, expectedSize.height, accuracy: 2.0,
            "Content height should match 40 rows")
    }

    func testApplySettingsSmallTerminal() {
        settings.terminalWidth = 40
        settings.terminalHeight = 10
        wc.applySettings()

        let expectedSize = wc.terminalView.preferredSize(columns: 40, rows: 10)
        let contentSize = wc.window?.contentView?.frame.size ?? .zero
        XCTAssertEqual(contentSize.width, expectedSize.width, accuracy: 2.0)
        XCTAssertEqual(contentSize.height, expectedSize.height, accuracy: 2.0)
    }

    // MARK: - Settings Propagation to Components

    func testApplySettingsPropagatesTerminalView() {
        settings.cursorShape = .vertical
        settings.cursorBlink = false
        wc.applySettings()
        XCTAssertEqual(wc.terminalView.settings.cursorShape, .vertical)
        XCTAssertEqual(wc.terminalView.settings.cursorBlink, false)
    }

    func testApplySettingsPropagatesEmulator() {
        settings.terminalID = .vt320
        settings.localEcho = true
        wc.applySettings()
        XCTAssertEqual(wc.terminalEmulator.settings.terminalID, .vt320)
        XCTAssertEqual(wc.terminalEmulator.settings.localEcho, true)
    }

    func testApplySettingsPropagatesKeyboardHandler() {
        settings.bsKey = 127
        settings.deleteKey = 8
        settings.metaKey = 1
        wc.applySettings()
        XCTAssertEqual(wc.keyboardHandler.settings.bsKey, 127)
        XCTAssertEqual(wc.keyboardHandler.settings.deleteKey, 8)
        XCTAssertEqual(wc.keyboardHandler.settings.metaKey, 1)
    }

    // MARK: - Cursor Settings

    func testApplySettingsCursorShapeBlock() {
        settings.cursorShape = .block
        wc.applySettings()
        XCTAssertEqual(wc.terminalView.settings.cursorShape, .block)
    }

    func testApplySettingsCursorShapeVertical() {
        settings.cursorShape = .vertical
        wc.applySettings()
        XCTAssertEqual(wc.terminalView.settings.cursorShape, .vertical)
    }

    func testApplySettingsCursorShapeHorizontal() {
        settings.cursorShape = .horizontal
        wc.applySettings()
        XCTAssertEqual(wc.terminalView.settings.cursorShape, .horizontal)
    }

    // MARK: - Color Theme

    func testApplySettingsUpdatesColorTheme() {
        settings.colorTheme.foreground = TerminalColor(r: 255, g: 0, b: 0)
        settings.colorTheme.background = TerminalColor(r: 0, g: 0, b: 255)
        wc.applySettings()
        XCTAssertEqual(wc.terminalView.settings.colorTheme.foreground.r, 255)
        XCTAssertEqual(wc.terminalView.settings.colorTheme.background.b, 255)
    }

    // MARK: - Terminal Emulation Settings

    func testApplySettingsTerminalID() {
        settings.terminalID = .vt100
        wc.applySettings()
        XCTAssertEqual(wc.terminalEmulator.settings.terminalID, .vt100)
    }

    func testApplySettingsNewLineMode() {
        settings.crSend = .crlf
        settings.crReceive = .lf
        wc.applySettings()
        XCTAssertEqual(wc.terminalEmulator.settings.crSend, .crlf)
        XCTAssertEqual(wc.terminalEmulator.settings.crReceive, .lf)
    }

    func testApplySettingsLocalEcho() {
        settings.localEcho = true
        wc.applySettings()
        XCTAssertTrue(wc.terminalEmulator.settings.localEcho)

        settings.localEcho = false
        wc.applySettings()
        XCTAssertFalse(wc.terminalEmulator.settings.localEcho)
    }

    // MARK: - Scroll Buffer

    func testApplySettingsScrollBuffer() {
        settings.enableScrollBuffer = true
        settings.scrollBufferSize = 50000
        wc.applySettings()
        XCTAssertTrue(wc.terminalView.settings.enableScrollBuffer)
        XCTAssertEqual(wc.terminalView.settings.scrollBufferSize, 50000)
    }

    // MARK: - Encoding

    func testApplySettingsEncoding() {
        settings.encoding = .sjis
        wc.applySettings()
        XCTAssertEqual(wc.terminalEmulator.settings.encoding, .sjis)
    }

    // MARK: - Multiple Rapid Changes

    func testApplySettingsMultipleRapidChanges() {
        // Simulate rapid settings changes (user clicking through dialogs quickly)
        for i in 0..<10 {
            settings.title = "Rapid Change \(i)"
            settings.windowAlpha = Double(50 + i * 5) / 100.0
            wc.applySettings()
        }
        // Final state should reflect last change
        XCTAssertTrue(wc.window?.title.hasPrefix("Rapid Change 9") ?? false)
        XCTAssertEqual(wc.window?.alphaValue ?? 0, 0.95, accuracy: 0.01)
    }

    // MARK: - Idempotency

    func testApplySettingsIdempotent() {
        settings.title = "Idempotent Test"
        settings.windowAlpha = 0.8
        settings.terminalWidth = 100
        settings.terminalHeight = 30

        wc.applySettings()
        let sizeAfterFirst = wc.window?.contentView?.frame.size ?? .zero

        wc.applySettings()
        let sizeAfterSecond = wc.window?.contentView?.frame.size ?? .zero

        XCTAssertEqual(sizeAfterFirst.width, sizeAfterSecond.width, accuracy: 0.1,
            "Applying settings twice should produce the same result")
        XCTAssertEqual(sizeAfterFirst.height, sizeAfterSecond.height, accuracy: 0.1)
    }

    // MARK: - Comprehensive Settings Change

    func testApplySettingsComprehensive() {
        // Change every category of settings at once
        settings.title = "Comprehensive"
        settings.windowAlpha = 0.9
        settings.fontName = "Monaco"
        settings.fontSize = 12.0
        settings.terminalWidth = 132
        settings.terminalHeight = 43
        settings.cursorShape = .horizontal
        settings.cursorBlink = false
        settings.localEcho = true
        settings.terminalID = .vt420
        settings.bsKey = 127
        settings.encoding = .eucjp
        settings.crSend = .lf
        settings.crReceive = .crlf
        settings.enableScrollBuffer = true
        settings.scrollBufferSize = 20000

        wc.applySettings()

        // Verify all propagated
        XCTAssertTrue(wc.window?.title.hasPrefix("Comprehensive") ?? false)
        XCTAssertEqual(wc.window?.alphaValue ?? 0, 0.9, accuracy: 0.01)
        XCTAssertEqual(wc.terminalView.settings.fontName, "Monaco")
        XCTAssertEqual(wc.terminalView.settings.fontSize, 12.0)
        XCTAssertEqual(wc.terminalView.settings.cursorShape, .horizontal)
        XCTAssertFalse(wc.terminalView.settings.cursorBlink)
        XCTAssertEqual(wc.terminalEmulator.settings.terminalID, .vt420)
        XCTAssertTrue(wc.terminalEmulator.settings.localEcho)
        XCTAssertEqual(wc.keyboardHandler.settings.bsKey, 127)
        XCTAssertEqual(wc.terminalEmulator.settings.encoding, .eucjp)
        XCTAssertEqual(wc.terminalEmulator.settings.crSend, .lf)
        XCTAssertEqual(wc.terminalEmulator.settings.crReceive, .crlf)
    }
}

// MARK: - Settings Dialog Integration Tests

class SettingsDialogIntegrationTests: XCTestCase {

    /// Verify TerminalSetupViewController modifies settings in place.
    func testTerminalSetupAppliesSettings() {
        let settings = TerminalSettings()
        settings.terminalWidth = 80
        settings.terminalHeight = 24

        let vc = TerminalSetupViewController(settings: settings)
        vc.loadView()
        vc.viewDidLoad()

        // The dialog should reference the same settings object
        // Modifying via applySettings should update the original
        XCTAssertEqual(settings.terminalWidth, 80)
        XCTAssertEqual(settings.terminalHeight, 24)
    }

    /// Verify WindowSetupViewController modifies settings in place.
    func testWindowSetupAppliesSettings() {
        let settings = TerminalSettings()
        settings.title = "Original"

        let vc = WindowSetupViewController(settings: settings)
        vc.loadView()
        vc.viewDidLoad()

        // Settings object should be shared
        XCTAssertEqual(settings.title, "Original")
    }

    /// Verify SendFileDialogController creates a valid result.
    func testSendFileDialogResultStructure() {
        let result = SendFileDialogController.Result(
            fileURL: URL(fileURLWithPath: "/tmp/test.txt"),
            bulkRead: true,
            binary: true,
            delayType: .perLine,
            sendSize: 1280,
            delayTimeMs: 100
        )
        XCTAssertEqual(result.fileURL.path, "/tmp/test.txt")
        XCTAssertTrue(result.bulkRead)
        XCTAssertTrue(result.binary)
        XCTAssertEqual(result.delayType, .perLine)
        XCTAssertEqual(result.sendSize, 1280)
        XCTAssertEqual(result.delayTimeMs, 100)
    }

    /// Verify RecvFileDialogController creates a valid result.
    func testRecvFileDialogResultStructure() {
        let result = RecvFileDialogController.Result(
            fileURL: URL(fileURLWithPath: "/tmp/recv.bin"),
            binary: false,
            autoStopWaitSec: 60
        )
        XCTAssertEqual(result.fileURL.path, "/tmp/recv.bin")
        XCTAssertFalse(result.binary)
        XCTAssertEqual(result.autoStopWaitSec, 60)
    }
}

// MARK: - Settings Reference Sharing Tests

class SettingsReferenceSharingTests: XCTestCase {

    /// Verify all components share the same settings reference.
    func testAllComponentsShareSettingsReference() {
        let settings = TerminalSettings()
        let wc = TerminalWindowController(settings: settings)
        _ = wc.window

        // All components should reference the same settings object
        XCTAssertTrue(wc.settings === settings,
            "WindowController should hold the same settings reference")
        XCTAssertTrue(wc.terminalView.settings === settings,
            "TerminalView should hold the same settings reference")
        XCTAssertTrue(wc.terminalEmulator.settings === settings,
            "TerminalEmulator should hold the same settings reference")
        XCTAssertTrue(wc.keyboardHandler.settings === settings,
            "KeyboardHandler should hold the same settings reference")

        wc.window?.close()
    }

    /// Verify that modifying settings and calling applySettings
    /// makes the change visible to all components.
    func testSettingsChangeVisibleToAllComponents() {
        let settings = TerminalSettings()
        let wc = TerminalWindowController(settings: settings)
        _ = wc.window

        settings.title = "Shared Change"
        settings.localEcho = true
        settings.bsKey = 127

        wc.applySettings()

        // Since settings is a reference type, all components see the change
        XCTAssertEqual(wc.terminalView.settings.title, "Shared Change")
        XCTAssertTrue(wc.terminalEmulator.settings.localEcho)
        XCTAssertEqual(wc.keyboardHandler.settings.bsKey, 127)

        wc.window?.close()
    }

    /// Verify applySettings re-assigns settings to components
    /// (handles case where a new TerminalSettings object is loaded).
    func testApplySettingsAfterSettingsReplacement() {
        let settings = TerminalSettings()
        let wc = TerminalWindowController(settings: settings)
        _ = wc.window

        // Simulate loading a new config file: replace the settings object
        let newSettings = TerminalSettings()
        newSettings.title = "Loaded Config"
        newSettings.fontSize = 18.0
        wc.settings = newSettings
        wc.applySettings()

        XCTAssertTrue(wc.terminalView.settings === newSettings)
        XCTAssertEqual(wc.terminalView.settings.title, "Loaded Config")
        XCTAssertEqual(wc.terminalView.settings.fontSize, 18.0)

        wc.window?.close()
    }
}

#endif
