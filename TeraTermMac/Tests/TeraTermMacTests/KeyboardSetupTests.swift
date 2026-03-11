/*
 * KeyboardSetupTests.swift
 * Tests for keyboard setup features:
 *   - Keyboard type (Terminal ID) selection
 *   - Disable application keypad mode
 *   - Disable application cursor key mode
 *   - Settings persistence (encode/decode)
 *   - KeyboardHandler behavior with disable flags
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - Keyboard Settings Property Tests

final class KeyboardSettingsPropertyTests: XCTestCase {

    func testDefaultDisableAppKeypadIsFalse() {
        let s = TerminalSettings()
        XCTAssertFalse(s.disableAppKeypad,
            "disableAppKeypad should default to false")
    }

    func testDefaultDisableAppCursorIsFalse() {
        let s = TerminalSettings()
        XCTAssertFalse(s.disableAppCursor,
            "disableAppCursor should default to false")
    }

    func testDefaultTerminalIDIsVT220() {
        let s = TerminalSettings()
        XCTAssertEqual(s.terminalID, .vt220,
            "terminalID should default to VT220")
    }

    func testDisableAppKeypadCanBeSet() {
        let s = TerminalSettings()
        s.disableAppKeypad = true
        XCTAssertTrue(s.disableAppKeypad)
        s.disableAppKeypad = false
        XCTAssertFalse(s.disableAppKeypad)
    }

    func testDisableAppCursorCanBeSet() {
        let s = TerminalSettings()
        s.disableAppCursor = true
        XCTAssertTrue(s.disableAppCursor)
        s.disableAppCursor = false
        XCTAssertFalse(s.disableAppCursor)
    }

    func testTerminalIDAllCases() {
        let allIDs = TerminalID.allCases
        XCTAssertEqual(allIDs.count, 14, "Should have 14 terminal ID types")
        XCTAssertTrue(allIDs.contains(.vt100))
        XCTAssertTrue(allIDs.contains(.vt220))
        XCTAssertTrue(allIDs.contains(.vt320))
        XCTAssertTrue(allIDs.contains(.vt420))
        XCTAssertTrue(allIDs.contains(.vt520))
        XCTAssertTrue(allIDs.contains(.dumb))
    }

    func testTerminalIDDisplayNames() {
        XCTAssertEqual(TerminalID.vt100.displayName, "VT100")
        XCTAssertEqual(TerminalID.vt220.displayName, "VT220")
        XCTAssertEqual(TerminalID.vt320.displayName, "VT320")
        XCTAssertEqual(TerminalID.vt420.displayName, "VT420")
        XCTAssertEqual(TerminalID.dumb.displayName, "DUMB")
    }
}

// MARK: - Keyboard Settings Persistence Tests

final class KeyboardSettingsPersistenceTests: XCTestCase {

    func testDisableAppKeypadEncodeDecode() throws {
        let original = TerminalSettings()
        original.disableAppKeypad = true

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalSettings.self, from: data)

        XCTAssertTrue(decoded.disableAppKeypad,
            "disableAppKeypad should survive encode/decode")
    }

    func testDisableAppCursorEncodeDecode() throws {
        let original = TerminalSettings()
        original.disableAppCursor = true

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalSettings.self, from: data)

        XCTAssertTrue(decoded.disableAppCursor,
            "disableAppCursor should survive encode/decode")
    }

    func testTerminalIDEncodeDecode() throws {
        let original = TerminalSettings()
        original.terminalID = .vt100

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalSettings.self, from: data)

        XCTAssertEqual(decoded.terminalID, .vt100,
            "terminalID should survive encode/decode")
    }

    func testAllKeyboardSettingsEncodeDecode() throws {
        let original = TerminalSettings()
        original.terminalID = .vt320
        original.bsKey = 127
        original.deleteKey = 8
        original.metaKey = 1
        original.disableAppKeypad = true
        original.disableAppCursor = true
        original.answerback = "test-answerback"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TerminalSettings.self, from: data)

        XCTAssertEqual(decoded.terminalID, .vt320)
        XCTAssertEqual(decoded.bsKey, 127)
        XCTAssertEqual(decoded.deleteKey, 8)
        XCTAssertEqual(decoded.metaKey, 1)
        XCTAssertTrue(decoded.disableAppKeypad)
        XCTAssertTrue(decoded.disableAppCursor)
        XCTAssertEqual(decoded.answerback, "test-answerback")
    }
}

// MARK: - KeyboardHandler Application Keypad Tests

final class KeyboardHandlerKeypadTests: XCTestCase {

    private func makeHandler(disableAppKeypad: Bool = false, disableAppCursor: Bool = false) -> KeyboardHandler {
        let settings = TerminalSettings()
        settings.disableAppKeypad = disableAppKeypad
        settings.disableAppCursor = disableAppCursor
        let handler = KeyboardHandler(settings: settings)
        return handler
    }

    private func makeKeyEvent(keyCode: UInt16, characters: String = "", modifiers: TerminalKeyEvent.KeyModifiers = []) -> TerminalKeyEvent {
        return TerminalKeyEvent(keyCode: keyCode, characters: characters, modifiers: modifiers, isKeyDown: true)
    }

    // MARK: - Application Keypad Mode

    func testKeypadNormalModeWhenAppKeypadDisabled() {
        let handler = makeHandler(disableAppKeypad: true)
        handler.modes.applicationKeypad = true  // Host enables app keypad

        // KP 0 (keyCode 0x52) should send "0" not ESC O p
        let event = makeKeyEvent(keyCode: 0x52)
        let result = handler.processKeyEvent(event)

        XCTAssertEqual(result, Data("0".utf8),
            "Keypad 0 should send '0' when app keypad is disabled")
    }

    func testKeypadApplicationModeWhenNotDisabled() {
        let handler = makeHandler(disableAppKeypad: false)
        handler.modes.applicationKeypad = true

        // KP 0 should send ESC O p in application mode
        let event = makeKeyEvent(keyCode: 0x52)
        let result = handler.processKeyEvent(event)

        XCTAssertEqual(result, Data("\u{1B}Op".utf8),
            "Keypad 0 should send ESC O p when app keypad is enabled")
    }

    func testKeypadNumericModeByDefault() {
        let handler = makeHandler()
        handler.modes.applicationKeypad = false

        let event = makeKeyEvent(keyCode: 0x52)
        let result = handler.processKeyEvent(event)

        XCTAssertEqual(result, Data("0".utf8),
            "Keypad 0 should send '0' in numeric mode")
    }

    func testKeypadEnterDisabledAppKeypad() {
        let handler = makeHandler(disableAppKeypad: true)
        handler.modes.applicationKeypad = true

        // KP Enter (0x4C) should send CR, not ESC O M
        let event = makeKeyEvent(keyCode: 0x4C)
        let result = handler.processKeyEvent(event)

        XCTAssertEqual(result, Data([0x0D]),
            "KP Enter should send CR when app keypad is disabled")
    }

    func testKeypadEnterApplicationMode() {
        let handler = makeHandler(disableAppKeypad: false)
        handler.modes.applicationKeypad = true

        let event = makeKeyEvent(keyCode: 0x4C)
        let result = handler.processKeyEvent(event)

        XCTAssertEqual(result, Data("\u{1B}OM".utf8),
            "KP Enter should send ESC O M in application mode")
    }

    func testMultipleKeypadKeysDisabled() {
        let handler = makeHandler(disableAppKeypad: true)
        handler.modes.applicationKeypad = true

        let testCases: [(UInt16, String)] = [
            (0x53, "1"),  // KP 1
            (0x54, "2"),  // KP 2
            (0x55, "3"),  // KP 3
            (0x56, "4"),  // KP 4
            (0x57, "5"),  // KP 5
            (0x58, "6"),  // KP 6
            (0x59, "7"),  // KP 7
            (0x5B, "8"),  // KP 8
            (0x5C, "9"),  // KP 9
            (0x41, "."),  // KP Decimal
        ]

        for (keyCode, expected) in testCases {
            let event = makeKeyEvent(keyCode: keyCode)
            let result = handler.processKeyEvent(event)
            XCTAssertEqual(result, Data(expected.utf8),
                "KP key 0x\(String(keyCode, radix: 16)) should send '\(expected)' when disabled")
        }
    }

    // MARK: - Application Cursor Mode

    func testCursorNormalModeWhenAppCursorDisabled() {
        let handler = makeHandler(disableAppCursor: true)
        handler.modes.cursorKeyMode = true  // Host enables app cursor

        // Up arrow (0x7E) should send CSI A, not ESC O A
        let event = makeKeyEvent(keyCode: 0x7E)
        let result = handler.processKeyEvent(event)

        XCTAssertEqual(result, Data("\u{1B}[A".utf8),
            "Up arrow should send CSI A when app cursor is disabled")
    }

    func testCursorApplicationModeWhenNotDisabled() {
        let handler = makeHandler(disableAppCursor: false)
        handler.modes.cursorKeyMode = true

        let event = makeKeyEvent(keyCode: 0x7E)
        let result = handler.processKeyEvent(event)

        XCTAssertEqual(result, Data("\u{1B}OA".utf8),
            "Up arrow should send ESC O A when app cursor is enabled")
    }

    func testCursorNormalModeByDefault() {
        let handler = makeHandler()
        handler.modes.cursorKeyMode = false

        let event = makeKeyEvent(keyCode: 0x7E)
        let result = handler.processKeyEvent(event)

        XCTAssertEqual(result, Data("\u{1B}[A".utf8),
            "Up arrow should send CSI A in normal cursor mode")
    }

    func testAllCursorKeysDisabled() {
        let handler = makeHandler(disableAppCursor: true)
        handler.modes.cursorKeyMode = true

        let testCases: [(UInt16, String)] = [
            (0x7E, "\u{1B}[A"),  // Up
            (0x7D, "\u{1B}[B"),  // Down
            (0x7C, "\u{1B}[C"),  // Right
            (0x7B, "\u{1B}[D"),  // Left
            (0x73, "\u{1B}[H"),  // Home
            (0x77, "\u{1B}[F"),  // End
        ]

        for (keyCode, expected) in testCases {
            let event = makeKeyEvent(keyCode: keyCode)
            let result = handler.processKeyEvent(event)
            XCTAssertEqual(result, Data(expected.utf8),
                "Cursor key 0x\(String(keyCode, radix: 16)) should send normal sequence when disabled")
        }
    }

    func testAllCursorKeysApplicationMode() {
        let handler = makeHandler(disableAppCursor: false)
        handler.modes.cursorKeyMode = true

        let testCases: [(UInt16, String)] = [
            (0x7E, "\u{1B}OA"),  // Up
            (0x7D, "\u{1B}OB"),  // Down
            (0x7C, "\u{1B}OC"),  // Right
            (0x7B, "\u{1B}OD"),  // Left
            (0x73, "\u{1B}OH"),  // Home
            (0x77, "\u{1B}OF"),  // End
        ]

        for (keyCode, expected) in testCases {
            let event = makeKeyEvent(keyCode: keyCode)
            let result = handler.processKeyEvent(event)
            XCTAssertEqual(result, Data(expected.utf8),
                "Cursor key 0x\(String(keyCode, radix: 16)) should send app sequence when enabled")
        }
    }

    // MARK: - Combined Disable Flags

    func testBothDisableFlagsSet() {
        let handler = makeHandler(disableAppKeypad: true, disableAppCursor: true)
        handler.modes.applicationKeypad = true
        handler.modes.cursorKeyMode = true

        // Keypad should be numeric
        let kpEvent = makeKeyEvent(keyCode: 0x52)
        XCTAssertEqual(handler.processKeyEvent(kpEvent), Data("0".utf8))

        // Cursor should be normal
        let cursorEvent = makeKeyEvent(keyCode: 0x7E)
        XCTAssertEqual(handler.processKeyEvent(cursorEvent), Data("\u{1B}[A".utf8))
    }

    func testDisableFlagsDoNotAffectModifiedKeys() {
        let handler = makeHandler(disableAppCursor: true)
        handler.modes.cursorKeyMode = true

        // Shift+Up should send CSI 1;2 A regardless
        let event = makeKeyEvent(keyCode: 0x7E, modifiers: .shift)
        let result = handler.processKeyEvent(event)
        XCTAssertEqual(result, Data("\u{1B}[1;2A".utf8),
            "Modified cursor keys should work normally even with disable flag")
    }
}

// MARK: - Settings Propagation Tests

final class KeyboardSettingsPropagationTests: XCTestCase {

    func testApplySettingsPropagatesDisableAppKeypad() {
        let settings = TerminalSettings()
        let wc = TerminalWindowController(settings: settings)
        _ = wc.window

        settings.disableAppKeypad = true
        wc.applySettings()
        XCTAssertTrue(wc.keyboardHandler.settings.disableAppKeypad,
            "disableAppKeypad should propagate to KeyboardHandler")

        wc.window?.close()
    }

    func testApplySettingsPropagatesDisableAppCursor() {
        let settings = TerminalSettings()
        let wc = TerminalWindowController(settings: settings)
        _ = wc.window

        settings.disableAppCursor = true
        wc.applySettings()
        XCTAssertTrue(wc.keyboardHandler.settings.disableAppCursor,
            "disableAppCursor should propagate to KeyboardHandler")

        wc.window?.close()
    }

    func testApplySettingsPropagatesTerminalID() {
        let settings = TerminalSettings()
        let wc = TerminalWindowController(settings: settings)
        _ = wc.window

        settings.terminalID = .vt100
        wc.applySettings()
        XCTAssertEqual(wc.terminalEmulator.settings.terminalID, .vt100,
            "terminalID should propagate to TerminalEmulator")

        wc.window?.close()
    }
}

// MARK: - Terminal Emulator Integration Tests

final class KeyboardTerminalEmulatorTests: XCTestCase {

    func testEmulatorTerminalIDMatchesSettings() {
        let settings = TerminalSettings()
        settings.terminalID = .vt320
        let emulator = TerminalEmulator(settings: settings)
        XCTAssertEqual(emulator.terminalID, .vt320)
    }

    func testEmulatorDECKPAMSetsApplicationKeypad() {
        let settings = TerminalSettings()
        let emulator = TerminalEmulator(settings: settings)

        // ESC = (DECKPAM) sets application keypad mode
        emulator.processData(Data("\u{1B}=".utf8))
        XCTAssertTrue(emulator.modes.applicationKeypad,
            "DECKPAM should enable application keypad")
    }

    func testEmulatorDECKPNMClearsApplicationKeypad() {
        let settings = TerminalSettings()
        let emulator = TerminalEmulator(settings: settings)

        emulator.processData(Data("\u{1B}=".utf8))  // Enable
        emulator.processData(Data("\u{1B}>".utf8))  // Disable
        XCTAssertFalse(emulator.modes.applicationKeypad,
            "DECKPNM should disable application keypad")
    }

    func testEmulatorDECCKMSetsCursorKeyMode() {
        let settings = TerminalSettings()
        let emulator = TerminalEmulator(settings: settings)

        // CSI ? 1 h (DECSET DECCKM)
        emulator.processData(Data("\u{1B}[?1h".utf8))
        XCTAssertTrue(emulator.modes.cursorKeyMode,
            "DECCKM set should enable cursor key mode")
    }

    func testEmulatorDECCKMResetClearsCursorKeyMode() {
        let settings = TerminalSettings()
        let emulator = TerminalEmulator(settings: settings)

        emulator.processData(Data("\u{1B}[?1h".utf8))  // Enable
        emulator.processData(Data("\u{1B}[?1l".utf8))  // Disable
        XCTAssertFalse(emulator.modes.cursorKeyMode,
            "DECCKM reset should disable cursor key mode")
    }

    func testKeyboardHandlerRespectsDisableEvenWhenEmulatorSetsMode() {
        let settings = TerminalSettings()
        settings.disableAppKeypad = true
        settings.disableAppCursor = true

        let emulator = TerminalEmulator(settings: settings)
        let handler = KeyboardHandler(settings: settings)

        // Host enables both modes via escape sequences
        emulator.processData(Data("\u{1B}=".utf8))      // DECKPAM
        emulator.processData(Data("\u{1B}[?1h".utf8))   // DECCKM

        // Sync modes from emulator to handler
        handler.modes = emulator.modes

        // Even though modes are set, handler should ignore them
        let kpEvent = TerminalKeyEvent(keyCode: 0x52, characters: "", modifiers: [], isKeyDown: true)
        XCTAssertEqual(handler.processKeyEvent(kpEvent), Data("0".utf8),
            "Keypad should stay numeric despite host DECKPAM")

        let curEvent = TerminalKeyEvent(keyCode: 0x7E, characters: "", modifiers: [], isKeyDown: true)
        XCTAssertEqual(handler.processKeyEvent(curEvent), Data("\u{1B}[A".utf8),
            "Cursor should stay normal despite host DECCKM")
    }
}

#endif
