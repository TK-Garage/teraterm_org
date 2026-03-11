/*
 * KeymapLoaderTests.swift
 * Tests for KeymapLoader - .cnf keyboard mapping file parser.
 *
 * Tests cover:
 *   - Parsing all 6 sections (VT editor, numeric, function, X, shortcut, user keys)
 *   - Character encoding auto-detection (UTF-8, Shift_JIS, Latin-1)
 *   - Line ending auto-detection (CRLF, LF, CR)
 *   - Comment and blank line handling
 *   - "off" value handling
 *   - Duplicate key code detection
 *   - User key $HH hex escape decoding
 *   - File I/O error handling
 */

import XCTest
@testable import TeraTermMac

// MARK: - Basic Parsing Tests

final class KeymapLoaderParsingTests: XCTestCase {

    // MARK: - VT Editor Keypad

    func testParseVTEditorKeypad() {
        let cnf = """
        [VT editor keypad]
        Up=328
        Down=336
        Right=333
        Left=331
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 336)
        XCTAssertEqual(keyMap.map[KeyID.right.rawValue - 1], 333)
        XCTAssertEqual(keyMap.map[KeyID.left.rawValue - 1], 331)
    }

    func testParseVTEditorKeypadAllKeys() {
        let cnf = """
        [VT editor keypad]
        Up=328
        Down=336
        Right=333
        Left=331
        Find=327
        Insert=338
        Remove=339
        Select=335
        Prev=329
        Next=337
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.find.rawValue - 1], 327)
        XCTAssertEqual(keyMap.map[KeyID.insert.rawValue - 1], 338)
        XCTAssertEqual(keyMap.map[KeyID.remove.rawValue - 1], 339)
        XCTAssertEqual(keyMap.map[KeyID.select.rawValue - 1], 335)
        XCTAssertEqual(keyMap.map[KeyID.prev.rawValue - 1], 329)
        XCTAssertEqual(keyMap.map[KeyID.next.rawValue - 1], 337)
    }

    // MARK: - VT Numeric Keypad

    func testParseVTNumericKeypad() {
        let cnf = """
        [VT numeric keypad]
        Num0=82
        Num5=76
        NumEnter=284
        NumSlash=309
        PF1=59
        PF4=62
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.num0.rawValue - 1], 82)
        XCTAssertEqual(keyMap.map[KeyID.num5.rawValue - 1], 76)
        XCTAssertEqual(keyMap.map[KeyID.numEnter.rawValue - 1], 284)
        XCTAssertEqual(keyMap.map[KeyID.numSlash.rawValue - 1], 309)
        XCTAssertEqual(keyMap.map[KeyID.pf1.rawValue - 1], 59)
        XCTAssertEqual(keyMap.map[KeyID.pf4.rawValue - 1], 62)
    }

    // MARK: - VT Function Keys

    func testParseVTFunctionKeys() {
        let cnf = """
        [VT function keys]
        Hold=off
        Print=off
        Break=off
        F6=64
        F11=87
        F12=88
        F13=573
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.hold.rawValue - 1], 0xFFFF, "Hold=off should be 0xFFFF")
        XCTAssertEqual(keyMap.map[KeyID.print.rawValue - 1], 0xFFFF, "Print=off should be 0xFFFF")
        XCTAssertEqual(keyMap.map[KeyID.f6.rawValue - 1], 64)
        XCTAssertEqual(keyMap.map[KeyID.f11.rawValue - 1], 87)
        XCTAssertEqual(keyMap.map[KeyID.f12.rawValue - 1], 88)
        XCTAssertEqual(keyMap.map[KeyID.f13.rawValue - 1], 573)
    }

    func testParseUDKKeys() {
        let cnf = """
        [VT function keys]
        UDK6=1088
        UDK7=1089
        UDK20=1604
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.udk6.rawValue - 1], 1088)
        XCTAssertEqual(keyMap.map[KeyID.udk7.rawValue - 1], 1089)
        XCTAssertEqual(keyMap.map[KeyID.udk20.rawValue - 1], 1604)
    }

    // MARK: - X Function Keys

    func testParseXFunctionKeys() {
        let cnf = """
        [X function keys]
        XF1=off
        XF5=63
        XBackTab=527
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.xf1.rawValue - 1], 0xFFFF, "XF1=off should be 0xFFFF")
        XCTAssertEqual(keyMap.map[KeyID.xf5.rawValue - 1], 63)
        XCTAssertEqual(keyMap.map[KeyID.xBackTab.rawValue - 1], 527)
    }

    // MARK: - Shortcut Keys

    func testParseShortcutKeys() {
        let cnf = """
        [Shortcut keys]
        EditCopy=1362
        EditPaste=850
        EditPasteCR=off
        LineUp=1352
        LineDown=1360
        ScrollLock=70
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.cmdEditCopy.rawValue - 1], 1362)
        XCTAssertEqual(keyMap.map[KeyID.cmdEditPaste.rawValue - 1], 850)
        XCTAssertEqual(keyMap.map[KeyID.cmdEditPasteCR.rawValue - 1], 0xFFFF)
        XCTAssertEqual(keyMap.map[KeyID.cmdLineUp.rawValue - 1], 1352)
        XCTAssertEqual(keyMap.map[KeyID.cmdLineDown.rawValue - 1], 1360)
        XCTAssertEqual(keyMap.map[KeyID.cmdScrollLock.rawValue - 1], 70)
    }

    // MARK: - User Keys

    func testParseUserKeys() {
        let cnf = """
        [User keys]
        User1=1083,0,telnet myhost
        User2=1084,0,$0D$0A
        User3=1085,1,$0D
        User4=1086,2,test.ttl
        User5=1087,3,50110
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.userKeys.count, 5)

        XCTAssertEqual(keyMap.userKeys[0].userIndex, 1)
        XCTAssertEqual(keyMap.userKeys[0].pcKeyCode, 1083)
        XCTAssertEqual(keyMap.userKeys[0].controlFlag, 0)
        XCTAssertEqual(keyMap.userKeys[0].value, "telnet myhost")

        XCTAssertEqual(keyMap.userKeys[1].controlFlag, 0)
        XCTAssertEqual(keyMap.userKeys[1].value, "$0D$0A")

        XCTAssertEqual(keyMap.userKeys[2].controlFlag, 1)

        XCTAssertEqual(keyMap.userKeys[3].controlFlag, 2)
        XCTAssertEqual(keyMap.userKeys[3].value, "test.ttl")

        XCTAssertEqual(keyMap.userKeys[4].controlFlag, 3)
        XCTAssertEqual(keyMap.userKeys[4].value, "50110")
    }

    func testParseUserKeyOff() {
        let cnf = """
        [User keys]
        User1=off
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.userKeys.count, 0, "off user key should not be added")
        let ttKeyCode = KeyID.user1.rawValue
        XCTAssertEqual(keyMap.map[ttKeyCode - 1], 0xFFFF)
    }

    func testUserKeyMapEntry() {
        let cnf = """
        [User keys]
        User1=1083,0,test
        """
        let keyMap = KeymapLoader.parse(cnf)

        let ttKeyCode = KeyID.user1.rawValue
        XCTAssertEqual(keyMap.map[ttKeyCode - 1], 1083,
            "User key PC key code should be stored in map")
    }
}

// MARK: - Comment and Formatting Tests

final class KeymapLoaderFormattingTests: XCTestCase {

    func testCommentsAreIgnored() {
        let cnf = """
        ; This is a comment
        [VT editor keypad]
        ; Up arrow key
        Up=328
        ; Down arrow key
        Down=336
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 336)
    }

    func testEmptyLinesAreIgnored() {
        let cnf = """
        [VT editor keypad]

        Up=328

        Down=336

        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 336)
    }

    func testCaseInsensitiveKeys() {
        let cnf = """
        [VT editor keypad]
        up=328
        DOWN=336
        Right=333
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 336)
        XCTAssertEqual(keyMap.map[KeyID.right.rawValue - 1], 333)
    }

    func testOffValueCaseInsensitive() {
        let cnf = """
        [VT function keys]
        Hold=OFF
        Print=Off
        Break=off
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.hold.rawValue - 1], 0xFFFF)
        XCTAssertEqual(keyMap.map[KeyID.print.rawValue - 1], 0xFFFF)
        XCTAssertEqual(keyMap.map[KeyID.break.rawValue - 1], 0xFFFF)
    }

    func testEmptyValueIsOff() {
        let cnf = """
        [VT editor keypad]
        Up=
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 0xFFFF,
            "Empty value should be treated as off")
    }

    func testInvalidValueIsOff() {
        let cnf = """
        [VT editor keypad]
        Up=abc
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 0xFFFF,
            "Non-numeric value should be treated as off")
    }

    func testUnknownSectionIsIgnored() {
        let cnf = """
        [Unknown section]
        Foo=123

        [VT editor keypad]
        Up=328
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
    }

    func testUnknownKeyIsIgnored() {
        let cnf = """
        [VT editor keypad]
        Up=328
        UnknownKey=999
        Down=336
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 336)
    }
}

// MARK: - Line Ending Tests

final class KeymapLoaderLineEndingTests: XCTestCase {

    func testCRLFLineEndings() {
        let cnf = "[VT editor keypad]\r\nUp=328\r\nDown=336\r\n"
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 336)
    }

    func testLFLineEndings() {
        let cnf = "[VT editor keypad]\nUp=328\nDown=336\n"
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 336)
    }

    func testCRLineEndings() {
        let cnf = "[VT editor keypad]\rUp=328\rDown=336\r"
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 336)
    }
}

// MARK: - Encoding Detection Tests

final class KeymapLoaderEncodingTests: XCTestCase {

    func testDecodeUTF8() throws {
        let text = "; UTF-8 テスト\n[VT editor keypad]\nUp=328\n"
        let data = text.data(using: .utf8)!
        let decoded = try KeymapLoader.decodeText(data)
        XCTAssertTrue(decoded.contains("テスト"))
        XCTAssertTrue(decoded.contains("Up=328"))
    }

    func testDecodeUTF8WithBOM() throws {
        let bom = Data([0xEF, 0xBB, 0xBF])
        let text = "; BOM test\n[VT editor keypad]\nUp=328\n"
        let data = bom + text.data(using: .utf8)!
        let decoded = try KeymapLoader.decodeText(data)
        XCTAssertTrue(decoded.contains("Up=328"))
    }

    func testDecodeShiftJIS() throws {
        // "テスト" in Shift_JIS: 0x83 0x65 0x83 0x58 0x83 0x67
        let sjisComment = Data([0x3B, 0x20, 0x83, 0x65, 0x83, 0x58, 0x83, 0x67, 0x0D, 0x0A])
        let asciiPart = "[VT editor keypad]\r\nUp=328\r\n".data(using: .ascii)!
        let data = sjisComment + asciiPart
        let decoded = try KeymapLoader.decodeText(data)
        XCTAssertTrue(decoded.contains("Up=328"))
    }

    func testDecodeASCII() throws {
        let text = "[VT editor keypad]\nUp=328\n"
        let data = text.data(using: .ascii)!
        let decoded = try KeymapLoader.decodeText(data)
        XCTAssertEqual(decoded, text)
    }

    func testDecodeLatin1() throws {
        // Latin-1 with special chars (e.g., ü = 0xFC)
        var data = Data([0x3B, 0x20, 0xFC, 0x0A])  // "; ü\n"
        data.append("[VT editor keypad]\nUp=328\n".data(using: .ascii)!)
        let decoded = try KeymapLoader.decodeText(data)
        XCTAssertTrue(decoded.contains("Up=328"))
    }
}

// MARK: - Duplicate Detection Tests

final class KeymapLoaderDuplicateTests: XCTestCase {

    func testDuplicateKeyCodeWarning() {
        let cnf = """
        [VT editor keypad]
        Up=328
        Down=328
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertFalse(keyMap.warnings.isEmpty, "Should have duplicate warning")
        XCTAssertTrue(keyMap.warnings[0].contains("328"))

        // First occurrence should be invalidated
        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 0xFFFF,
            "First duplicate should be invalidated")
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 328,
            "Second duplicate should keep its value")
    }

    func testNoDuplicateWarningForOff() {
        let cnf = """
        [VT function keys]
        Hold=off
        Print=off
        """
        let keyMap = KeymapLoader.parse(cnf)

        XCTAssertTrue(keyMap.warnings.isEmpty,
            "off values should not trigger duplicate warnings")
    }
}

// MARK: - User Key Value Decoder Tests

final class KeymapLoaderUserKeyDecoderTests: XCTestCase {

    func testDecodeSimpleString() {
        let result = KeymapLoader.decodeUserKeyValue("telnet myhost")
        XCTAssertEqual(result, Data("telnet myhost".utf8))
    }

    func testDecodeHexEscapes() {
        let result = KeymapLoader.decodeUserKeyValue("$0D$0A")
        XCTAssertEqual(result, Data([0x0D, 0x0A]))
    }

    func testDecodeMixedContent() {
        let result = KeymapLoader.decodeUserKeyValue("hello$0Dworld")
        var expected = Data("hello".utf8)
        expected.append(0x0D)
        expected.append(contentsOf: "world".utf8)
        XCTAssertEqual(result, expected)
    }

    func testDecodeEmptyString() {
        let result = KeymapLoader.decodeUserKeyValue("")
        XCTAssertEqual(result, Data())
    }

    func testDecodeOnlyHex() {
        let result = KeymapLoader.decodeUserKeyValue("$1B$5B$41")
        XCTAssertEqual(result, Data([0x1B, 0x5B, 0x41]))
    }
}

// MARK: - Full IBMKEYB.CNF Format Test

final class KeymapLoaderFullFormatTests: XCTestCase {

    func testParseIBMKeybFormat() {
        let cnf = """
        ; Sample of KEYBOARD.CNF for the IBM-PC/AT 101-key keyboard.
        ;
        [VT editor keypad]
        ;Up arrow key
        Up=328
        ;Down arrow key
        Down=336
        ;Right arrow key
        Right=333
        ;Left arrow key
        Left=331
        ;Insert key
        Insert=338
        ;Home key
        Find=327
        ;PageUp key
        Prev=329
        ;Delete key
        Remove=339
        ;End key
        Select=335
        ;PageDown key
        Next=337

        [VT numeric keypad]
        Num0=82
        Num1=79
        Num2=80
        Num3=81
        Num4=75
        Num5=76
        Num6=77
        Num7=71
        Num8=72
        Num9=73
        NumComma=1102
        NumPlus=78
        NumPeriod=83
        NumEnter=284
        NumSlash=309
        NumAsterisk=55
        NumMinus=74
        PF1=59
        PF2=60
        PF3=61
        PF4=62

        [VT function keys]
        Hold=off
        Print=off
        Break=off
        F6=64
        F7=65
        F8=66
        F9=67
        F10=68
        F11=87
        F12=88
        F13=573
        F14=574
        Help=575
        Do=576
        F17=577
        F18=578
        F19=579
        F20=580
        UDK6=1088
        UDK7=1089
        UDK8=1090
        UDK9=1091
        UDK10=1092
        UDK11=1111
        UDK12=1112
        UDK13=1597
        UDK14=1598
        UDK15=1599
        UDK16=1600
        UDK17=1601
        UDK18=1602
        UDK19=1603
        UDK20=1604

        [X function keys]
        XF1=off
        XF2=off
        XF3=off
        XF4=off
        XF5=63
        XBackTab=527

        [Shortcut keys]
        EditCopy=1362
        EditPaste=850
        EditPasteCR=off
        EditCLS=off
        EditCLB=off
        ControlOpenTEK=off
        ControlCloseTEK=off
        LineUp=1352
        LineDown=1360
        PageUp=1353
        PageDown=1361
        BuffTop=1351
        BuffBottom=1359
        NextWin=1039
        NextShownWin=off
        PrevWin=1551
        PrevShownWin=off
        LocalEcho=off
        ScrollLock=70

        [User keys]
        ;User1=1083,0,telnet myhost
        """
        let keyMap = KeymapLoader.parse(cnf)

        // Verify key counts: many assigned, no warnings expected for this standard config
        let assignedCount = keyMap.map.filter { $0 != 0xFFFF }.count
        XCTAssertGreaterThan(assignedCount, 50, "Should have many assigned keys")

        // Spot checks
        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.f12.rawValue - 1], 88)
        XCTAssertEqual(keyMap.map[KeyID.cmdEditCopy.rawValue - 1], 1362)
        XCTAssertEqual(keyMap.map[KeyID.xf5.rawValue - 1], 63)
        XCTAssertEqual(keyMap.map[KeyID.udk20.rawValue - 1], 1604)

        // User keys section has all lines commented out
        XCTAssertEqual(keyMap.userKeys.count, 0)

        // No duplicate warnings in well-formed file
        XCTAssertTrue(keyMap.warnings.isEmpty,
            "Standard IBMKEYB.CNF should have no warnings, got: \(keyMap.warnings)")
    }

    func testEmptyFileProducesDefaultKeyMap() {
        let keyMap = KeymapLoader.parse("")

        // All keys should be unassigned
        for i in 0..<KeyID.keyMax {
            XCTAssertEqual(keyMap.map[i], 0xFFFF,
                "Key at index \(i) should be 0xFFFF for empty file")
        }
        XCTAssertEqual(keyMap.userKeys.count, 0)
        XCTAssertTrue(keyMap.warnings.isEmpty)
    }
}

// MARK: - File I/O Tests

final class KeymapLoaderFileIOTests: XCTestCase {

    func testLoadFromNonExistentFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_keymap_test.cnf")
        XCTAssertThrowsError(try KeymapLoader.load(from: url)) { error in
            guard case KeymapLoader.LoadError.fileNotFound = error else {
                XCTFail("Expected fileNotFound error, got \(error)")
                return
            }
        }
    }

    func testLoadFromTempFile() throws {
        let cnf = "[VT editor keypad]\nUp=328\nDown=336\n"
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_keymap_\(UUID().uuidString).cnf")
        try cnf.write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let keyMap = try KeymapLoader.load(from: tmpURL)
        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 336)
    }

    func testLoadCRLFFile() throws {
        let cnf = "[VT editor keypad]\r\nUp=328\r\nDown=336\r\n"
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_keymap_crlf_\(UUID().uuidString).cnf")
        try cnf.data(using: .utf8)!.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let keyMap = try KeymapLoader.load(from: tmpURL)
        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
        XCTAssertEqual(keyMap.map[KeyID.down.rawValue - 1], 336)
    }

    func testLoadShiftJISFile() throws {
        // Create a Shift_JIS encoded file with Japanese comments
        var data = Data()
        // "; テスト\r\n" in Shift_JIS
        data.append(contentsOf: [0x3B, 0x20, 0x83, 0x65, 0x83, 0x58, 0x83, 0x67, 0x0D, 0x0A])
        data.append("[VT editor keypad]\r\nUp=328\r\n".data(using: .ascii)!)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_keymap_sjis_\(UUID().uuidString).cnf")
        try data.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let keyMap = try KeymapLoader.load(from: tmpURL)
        XCTAssertEqual(keyMap.map[KeyID.up.rawValue - 1], 328)
    }
}

// MARK: - KeyMap Struct Tests

final class KeyMapStructTests: XCTestCase {

    func testKeyMapInitialization() {
        let keyMap = KeyMap()

        XCTAssertEqual(keyMap.map.count, KeyID.keyMax)
        XCTAssertTrue(keyMap.map.allSatisfy { $0 == 0xFFFF })
        XCTAssertEqual(keyMap.userKeys.count, 0)
        XCTAssertEqual(keyMap.warnings.count, 0)
    }

    func testKeyIDConstants() {
        XCTAssertEqual(KeyID.up.rawValue, 1)
        XCTAssertEqual(KeyID.user1.rawValue, 90)
        XCTAssertEqual(KeyID.keyMax, 188)
        XCTAssertEqual(KeyID.numOfUserKey, 99)
    }

    func testUserKeyEntryEquatable() {
        let a = UserKeyEntry(userIndex: 1, pcKeyCode: 1083, controlFlag: 0, value: "test")
        let b = UserKeyEntry(userIndex: 1, pcKeyCode: 1083, controlFlag: 0, value: "test")
        let c = UserKeyEntry(userIndex: 2, pcKeyCode: 1084, controlFlag: 1, value: "other")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
