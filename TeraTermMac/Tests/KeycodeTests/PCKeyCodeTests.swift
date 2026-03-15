/*
 * PCKeyCodeTests.swift
 * Tests for PC key code calculation in Keycode.app
 *
 * Covers:
 *   - Alphanumeric standalone keys
 *   - All modifier combinations (Shift, Ctrl, Shift+Ctrl, etc.)
 *   - Function keys F1-F12
 *   - Keypad keys (0-9, Enter, +, -, *, /, .)
 *   - Special keys (Tab, Return, Escape, Space, BackSpace, Delete)
 *   - Navigation keys (Home, End, PageUp, PageDown, arrows)
 *   - Option+key hint value verification
 *   - Key name table completeness
 */

import XCTest
@testable import Keycode

// MARK: - Alphanumeric Standalone Key Tests

final class PCKeyCodeAlphanumericTests: XCTestCase {

    // MARK: - Letters

    func testKeyA() {
        // A = macOS keyCode 0x00 = 0
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x00), 0)
    }

    func testKeyZ() {
        // Z = macOS keyCode 0x06 = 6
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x06), 6)
    }

    func testKeyQ() {
        // Q = macOS keyCode 0x0C = 12
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x0C), 12)
    }

    func testKeyM() {
        // M = macOS keyCode 0x2E = 46
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x2E), 46)
    }

    // MARK: - Number Keys

    func testKey0() {
        // 0 = macOS keyCode 0x1D = 29
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x1D), 29)
    }

    func testKey1() {
        // 1 = macOS keyCode 0x12 = 18
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x12), 18)
    }

    func testKey9() {
        // 9 = macOS keyCode 0x19 = 25
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x19), 25)
    }
}

// MARK: - Modifier Combination Tests

final class PCKeyCodeModifierTests: XCTestCase {

    // MARK: - Shift+key

    func testShiftA() {
        // Shift+A = 0 + 256 = 256
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x00, shift: true), 256)
    }

    func testShiftZ() {
        // Shift+Z = 6 + 256 = 262
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x06, shift: true), 262)
    }

    // MARK: - Ctrl+key

    func testCtrlA() {
        // Ctrl+A = 0 + 512 = 512
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x00, control: true), 512)
    }

    func testCtrlZ() {
        // Ctrl+Z = 6 + 512 = 518
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x06, control: true), 518)
    }

    // MARK: - Shift+Ctrl+key

    func testShiftCtrlA() {
        // Shift+Ctrl+A = 0 + 256 + 512 = 768
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x00, shift: true, control: true), 768)
    }

    func testShiftCtrlZ() {
        // Shift+Ctrl+Z = 6 + 768 = 774
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x06, shift: true, control: true), 774)
    }

    // MARK: - Shift+Option+key

    func testShiftOptionA() {
        // Shift+Option+A = 0 + 256 + 1024 = 1280
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x00, shift: true, option: true), 1280)
    }

    // MARK: - Ctrl+Option+key

    func testCtrlOptionA() {
        // Ctrl+Option+A = 0 + 512 + 1024 = 1536
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x00, control: true, option: true), 1536)
    }

    // MARK: - Shift+Ctrl+Option+key

    func testShiftCtrlOptionA() {
        // Shift+Ctrl+Option+A = 0 + 256 + 512 + 1024 = 1792
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x00, shift: true, control: true, option: true), 1792)
    }

    // MARK: - Modifier offset constants

    func testModifierOffsetValues() {
        XCTAssertEqual(ModifierOffset.none, 0)
        XCTAssertEqual(ModifierOffset.shift, 256)
        XCTAssertEqual(ModifierOffset.control, 512)
        XCTAssertEqual(ModifierOffset.option, 1024)
        XCTAssertEqual(ModifierOffset.shiftControl, 768)
        XCTAssertEqual(ModifierOffset.shiftOption, 1280)
        XCTAssertEqual(ModifierOffset.controlOption, 1536)
        XCTAssertEqual(ModifierOffset.shiftControlOption, 1792)
        XCTAssertEqual(ModifierOffset.optionAlone, 2048)
    }

    func testModifierOffsetsAreComposable() {
        XCTAssertEqual(ModifierOffset.shiftControl, ModifierOffset.shift + ModifierOffset.control)
        XCTAssertEqual(ModifierOffset.shiftOption, ModifierOffset.shift + ModifierOffset.option)
        XCTAssertEqual(ModifierOffset.controlOption, ModifierOffset.control + ModifierOffset.option)
        XCTAssertEqual(ModifierOffset.shiftControlOption, ModifierOffset.shift + ModifierOffset.control + ModifierOffset.option)
    }
}

// MARK: - Function Key Tests

final class PCKeyCodeFunctionKeyTests: XCTestCase {

    func testF1() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x7A), 122)
    }

    func testF2() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x78), 120)
    }

    func testF3() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x63), 99)
    }

    func testF4() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x76), 118)
    }

    func testF5() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x60), 96)
    }

    func testF6() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x61), 97)
    }

    func testF7() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x62), 98)
    }

    func testF8() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x64), 100)
    }

    func testF9() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x65), 101)
    }

    func testF10() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x6D), 109)
    }

    func testF11() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x67), 103)
    }

    func testF12() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x6F), 111)
    }

    func testShiftF1() {
        // Shift+F1 = 122 + 256 = 378
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x7A, shift: true), 378)
    }

    func testCtrlF5() {
        // Ctrl+F5 = 96 + 512 = 608
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x60, control: true), 608)
    }
}

// MARK: - Keypad Key Tests

final class PCKeyCodeKeypadTests: XCTestCase {

    func testKeypad0() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x52), 82)
    }

    func testKeypad1() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x53), 83)
    }

    func testKeypad2() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x54), 84)
    }

    func testKeypad3() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x55), 85)
    }

    func testKeypad4() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x56), 86)
    }

    func testKeypad5() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x57), 87)
    }

    func testKeypad6() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x58), 88)
    }

    func testKeypad7() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x59), 89)
    }

    func testKeypad8() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x5B), 91)
    }

    func testKeypad9() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x5C), 92)
    }

    func testKeypadEnter() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x4C), 76)
    }

    func testKeypadPlus() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x45), 69)
    }

    func testKeypadMinus() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x4E), 78)
    }

    func testKeypadMultiply() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x43), 67)
    }

    func testKeypadDivide() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x4B), 75)
    }

    func testKeypadDecimal() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x41), 65)
    }

    func testKeypadEquals() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x51), 81)
    }

    func testKeypadClear() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x47), 71)
    }
}

// MARK: - Special Key Tests

final class PCKeyCodeSpecialKeyTests: XCTestCase {

    func testTab() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x30), 48)
    }

    func testReturn() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x24), 36)
    }

    func testEscape() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x35), 53)
    }

    func testSpace() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x31), 49)
    }

    func testBackSpace() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x33), 51)
    }

    func testForwardDelete() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x75), 117)
    }

    func testCapsLock() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x39), 57)
    }
}

// MARK: - Navigation Key Tests

final class PCKeyCodeNavigationTests: XCTestCase {

    func testHome() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x73), 115)
    }

    func testEnd() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x77), 119)
    }

    func testPageUp() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x74), 116)
    }

    func testPageDown() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x79), 121)
    }

    func testUpArrow() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x7E), 126)
    }

    func testDownArrow() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x7D), 125)
    }

    func testLeftArrow() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x7B), 123)
    }

    func testRightArrow() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x7C), 124)
    }

    func testInsert() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x72), 114)
    }

    func testShiftUpArrow() {
        // Shift + Up = 126 + 256 = 382
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x7E, shift: true), 382)
    }

    func testCtrlLeftArrow() {
        // Ctrl + Left = 123 + 512 = 635
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x7B, control: true), 635)
    }
}

// MARK: - Option+key Hint Value Tests

final class PCKeyCodeOptionTests: XCTestCase {

    func testOptionAManualCalculation() {
        // Option+A: base code is 0 (keyCode for A)
        // Manual calculation: 0 + 2048 = 2048
        let baseCode = pcKeyCodeRaw(keyCode: 0x00)
        let optionCode = baseCode + ModifierOffset.optionAlone
        XCTAssertEqual(optionCode, 2048)
    }

    func testOptionZManualCalculation() {
        // Option+Z: base code is 6
        // Manual calculation: 6 + 2048 = 2054
        let baseCode = pcKeyCodeRaw(keyCode: 0x06)
        let optionCode = baseCode + ModifierOffset.optionAlone
        XCTAssertEqual(optionCode, 2054)
    }

    func testOptionF1ManualCalculation() {
        // Option+F1: base code is 122
        // Manual calculation: 122 + 2048 = 2170
        let baseCode = pcKeyCodeRaw(keyCode: 0x7A)
        let optionCode = baseCode + ModifierOffset.optionAlone
        XCTAssertEqual(optionCode, 2170)
    }

    func testOptionSpaceManualCalculation() {
        // Option+Space: base code is 49
        // Manual calculation: 49 + 2048 = 2097
        let baseCode = pcKeyCodeRaw(keyCode: 0x31)
        let optionCode = baseCode + ModifierOffset.optionAlone
        XCTAssertEqual(optionCode, 2097)
    }
}

// MARK: - Key Name Table Tests

final class PCKeyCodeKeyNameTests: XCTestCase {

    func testAllLetterKeysHaveNames() {
        let letterKeyCodes: [UInt16] = [
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            0x08, 0x09, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
            0x10, 0x11, 0x1F, 0x20, 0x22, 0x23, 0x25, 0x26,
            0x28, 0x2D, 0x2E,
        ]
        for kc in letterKeyCodes {
            XCTAssertNotNil(keyNames[kc], "Key 0x\(String(kc, radix: 16)) should have a name")
        }
    }

    func testAllFunctionKeysHaveNames() {
        let fKeyKeyCodes: [UInt16] = [
            0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64,
            0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A,
            0x40, 0x4F, 0x50, 0x5A,
        ]
        for kc in fKeyKeyCodes {
            XCTAssertNotNil(keyNames[kc], "Function key 0x\(String(kc, radix: 16)) should have a name")
        }
    }

    func testKeyNameTableCount() {
        // Total keys: 26 letters + 10 numbers + 11 symbols + 6 special + 20 function +
        //             4 cursor + 6 editing + 18 keypad = 101
        XCTAssertGreaterThanOrEqual(keyNames.count, 95, "Should have at least 95 key names")
    }

    func testModifierKeyCodesAreSeparate() {
        // Modifier keys should NOT be in the keyNames table
        for kc in modifierKeyCodes {
            XCTAssertNil(keyNames[kc], "Modifier key 0x\(String(kc, radix: 16)) should not be in keyNames")
        }
    }
}

// MARK: - Edge Cases

final class PCKeyCodeEdgeCaseTests: XCTestCase {

    func testMaxBaseKeyCode() {
        // Highest macOS keyCode in our table: 0x7E (126) for Up arrow
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x7E), 126)
    }

    func testMaxKeyCodeWithAllModifiers() {
        // 126 + 256 + 512 + 1024 = 1918
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x7E, shift: true, control: true, option: true), 1918)
    }

    func testNoModifiers() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x00), 0)
    }

    func testSymbolKeys() {
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x18), 24)  // =
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x1B), 27)  // -
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x1E), 30)  // ]
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x21), 33)  // [
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x27), 39)  // '
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x29), 41)  // ;
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x2A), 42)  // backslash
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x2B), 43)  // ,
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x2C), 44)  // /
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x2F), 47)  // .
        XCTAssertEqual(pcKeyCodeRaw(keyCode: 0x32), 50)  // `
    }
}
