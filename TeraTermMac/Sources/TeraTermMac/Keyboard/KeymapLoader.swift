/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of ttset_keyboard.c to Swift/macOS
 * Reads .cnf keyboard mapping files (same format as original Tera Term).
 * Supports automatic character encoding and line ending detection.
 */

import Foundation

// MARK: - Key IDs (port of tttypes_key.h)

/// Internal key identifiers matching original Tera Term key codes.
enum KeyID: Int, CaseIterable {
    // VT editor keypad
    case up = 1, down, right, left
    // VT numeric keypad
    case num0 = 5, num1, num2, num3, num4, num5, num6, num7, num8, num9
    case numMinus = 15, numComma, numPeriod, numSlash, numAsterisk, numPlus, numEnter
    case pf1 = 22, pf2, pf3, pf4
    // VT editor keypad continued
    case find = 26, insert, remove, select, prev, next
    // VT function keys
    case f6 = 32, f7, f8, f9, f10, f11, f12, f13, f14
    case help = 41, `do`
    case f17 = 43, f18, f19, f20
    // Xterm function keys
    case xf1 = 47, xf2, xf3, xf4, xf5
    // UDK
    case udk6 = 52, udk7, udk8, udk9, udk10, udk11, udk12
    case udk13 = 59, udk14, udk15, udk16, udk17, udk18, udk19, udk20
    // Special
    case hold = 67, print, `break`
    case xBackTab = 70
    // Shortcut keys (Tera Term commands)
    case cmdEditCopy = 71, cmdEditPaste, cmdEditPasteCR
    case cmdEditCLS = 74, cmdEditCLB
    case cmdCtrlOpenTEK = 76, cmdCtrlCloseTEK
    case cmdLineUp = 78, cmdLineDown
    case cmdPageUp = 80, cmdPageDown
    case cmdBuffTop = 82, cmdBuffBottom
    case cmdNextWin = 84, cmdPrevWin
    case cmdNextSWin = 86, cmdPrevSWin
    case cmdLocalEcho = 88, cmdScrollLock
    // User keys start at 90
    case user1 = 90

    static let keyMax = 188  // IdUser1 + NumOfUserKey - 1
    static let numOfUserKey = 99
}

// MARK: - User Key Entry

/// A user-defined key entry from the [User keys] section.
struct UserKeyEntry: Equatable {
    let userIndex: Int       // 1-99
    let pcKeyCode: Int       // PC key code
    let controlFlag: Int     // 0=string, 1=newline conversion, 2=macro, 3=menu command
    let value: String        // Character string / macro file / command ID
}

// MARK: - KeyMap

/// Parsed keyboard mapping data from a .cnf file.
struct KeyMap: Equatable {
    /// Maps key ID (1-based index) to PC key code.  0xFFFF means unassigned.
    var map: [UInt16]

    /// User-defined key entries.
    var userKeys: [UserKeyEntry]

    /// Duplicate key code warnings found during loading.
    var warnings: [String]

    init() {
        map = Array(repeating: 0xFFFF, count: KeyID.keyMax)
        userKeys = []
        warnings = []
    }
}

// MARK: - KeymapLoader

/// Loads Tera Term .cnf keyboard mapping files.
/// Compatible with original Tera Term format with automatic encoding/line-ending detection.
struct KeymapLoader {

    // MARK: - Section/Key Definitions (port of ttset_keyboard.c static arrays)

    private static let vtEditorKeys: [(KeyID, String)] = [
        (.up, "Up"), (.down, "Down"), (.right, "Right"), (.left, "Left"),
        (.find, "Find"), (.insert, "Insert"), (.remove, "Remove"),
        (.select, "Select"), (.prev, "Prev"), (.next, "Next"),
    ]

    private static let vtNumericKeys: [(KeyID, String)] = [
        (.num0, "Num0"), (.num1, "Num1"), (.num2, "Num2"), (.num3, "Num3"),
        (.num4, "Num4"), (.num5, "Num5"), (.num6, "Num6"), (.num7, "Num7"),
        (.num8, "Num8"), (.num9, "Num9"),
        (.numMinus, "NumMinus"), (.numComma, "NumComma"),
        (.numPeriod, "NumPeriod"), (.numEnter, "NumEnter"),
        (.numSlash, "NumSlash"), (.numAsterisk, "NumAsterisk"),
        (.numPlus, "NumPlus"),
        (.pf1, "PF1"), (.pf2, "PF2"), (.pf3, "PF3"), (.pf4, "PF4"),
    ]

    private static let vtFunctionKeys: [(KeyID, String)] = [
        (.hold, "Hold"), (.print, "Print"), (.break, "Break"),
        (.f6, "F6"), (.f7, "F7"), (.f8, "F8"), (.f9, "F9"), (.f10, "F10"),
        (.f11, "F11"), (.f12, "F12"), (.f13, "F13"), (.f14, "F14"),
        (.help, "Help"), (.do, "Do"),
        (.f17, "F17"), (.f18, "F18"), (.f19, "F19"), (.f20, "F20"),
        (.udk6, "UDK6"), (.udk7, "UDK7"), (.udk8, "UDK8"), (.udk9, "UDK9"),
        (.udk10, "UDK10"), (.udk11, "UDK11"), (.udk12, "UDK12"),
        (.udk13, "UDK13"), (.udk14, "UDK14"), (.udk15, "UDK15"),
        (.udk16, "UDK16"), (.udk17, "UDK17"), (.udk18, "UDK18"),
        (.udk19, "UDK19"), (.udk20, "UDK20"),
    ]

    private static let xtermKeys: [(KeyID, String)] = [
        (.xf1, "XF1"), (.xf2, "XF2"), (.xf3, "XF3"), (.xf4, "XF4"),
        (.xf5, "XF5"), (.xBackTab, "XBackTab"),
    ]

    private static let shortcutKeys: [(KeyID, String)] = [
        (.cmdEditCopy, "EditCopy"), (.cmdEditPaste, "EditPaste"),
        (.cmdEditPasteCR, "EditPasteCR"),
        (.cmdEditCLS, "EditCLS"), (.cmdEditCLB, "EditCLB"),
        (.cmdCtrlOpenTEK, "ControlOpenTEK"), (.cmdCtrlCloseTEK, "ControlCloseTEK"),
        (.cmdLineUp, "LineUp"), (.cmdLineDown, "LineDown"),
        (.cmdPageUp, "PageUp"), (.cmdPageDown, "PageDown"),
        (.cmdBuffTop, "BuffTop"), (.cmdBuffBottom, "BuffBottom"),
        (.cmdNextWin, "NextWin"), (.cmdPrevWin, "PrevWin"),
        (.cmdNextSWin, "NextShownWin"), (.cmdPrevSWin, "PrevShownWin"),
        (.cmdLocalEcho, "LocalEcho"), (.cmdScrollLock, "ScrollLock"),
    ]

    // MARK: - Public API

    enum LoadError: Error, LocalizedError {
        case fileNotFound(String)
        case encodingDetectionFailed
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return TTL("error.keymap.fileNotFound", path)
            case .encodingDetectionFailed:
                return TTL("error.keymap.encodingFailed")
            case .parseError(let msg):
                return TTL("error.keymap.parseError", msg)
            }
        }
    }

    /// Load a .cnf keymap file from the given URL.
    /// Auto-detects character encoding (UTF-8, Shift_JIS, EUC-JP, Latin-1)
    /// and line endings (CRLF, LF, CR).
    static func load(from url: URL) throws -> KeyMap {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.fileNotFound(url.path)
        }

        let data = try Data(contentsOf: url)
        let text = try decodeText(data)
        return parse(text)
    }

    /// Load a .cnf keymap file from a string (for testing).
    static func parse(_ text: String) -> KeyMap {
        let sections = parseINI(text)
        var keyMap = KeyMap()

        readSection(sections, name: "VT editor keypad", keys: vtEditorKeys, into: &keyMap)
        readSection(sections, name: "VT numeric keypad", keys: vtNumericKeys, into: &keyMap)
        readSection(sections, name: "VT function keys", keys: vtFunctionKeys, into: &keyMap)
        readSection(sections, name: "X function keys", keys: xtermKeys, into: &keyMap)
        readSection(sections, name: "Shortcut keys", keys: shortcutKeys, into: &keyMap)
        readUserKeys(sections, into: &keyMap)
        checkDuplicates(&keyMap)

        return keyMap
    }

    // MARK: - Encoding Detection

    /// Detect encoding and decode Data to String.
    static func decodeText(_ data: Data) throws -> String {
        // Check for BOM
        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            // UTF-8 BOM
            if let str = String(data: data.dropFirst(3), encoding: .utf8) {
                return str
            }
        }
        if data.count >= 2 {
            if data[0] == 0xFF && data[1] == 0xFE {
                if let str = String(data: data, encoding: .utf16LittleEndian) {
                    return str
                }
            }
            if data[0] == 0xFE && data[1] == 0xFF {
                if let str = String(data: data, encoding: .utf16BigEndian) {
                    return str
                }
            }
        }

        // Try UTF-8 first
        if let str = String(data: data, encoding: .utf8) {
            // Validate it's actually valid UTF-8 (not just ASCII being decoded)
            if isValidUTF8(data) {
                return str
            }
        }

        // Try Shift_JIS (common for Japanese Tera Term configs)
        if let str = String(data: data, encoding: .shiftJIS) {
            return str
        }

        // Try EUC-JP
        if let str = String(data: data, encoding: .japaneseEUC) {
            return str
        }

        // Try ISO Latin-1 as fallback
        if let str = String(data: data, encoding: .isoLatin1) {
            return str
        }

        throw LoadError.encodingDetectionFailed
    }

    /// Validate that data is valid UTF-8 (catches mis-detected Shift_JIS, etc.)
    private static func isValidUTF8(_ data: Data) -> Bool {
        var i = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            let seqLen: Int
            if byte < 0x80 {
                seqLen = 1
            } else if byte & 0xE0 == 0xC0 {
                seqLen = 2
                // Overlong check: must be >= 0xC2
                if byte < 0xC2 { return false }
            } else if byte & 0xF0 == 0xE0 {
                seqLen = 3
            } else if byte & 0xF8 == 0xF0 {
                seqLen = 4
                // Must be <= 0xF4
                if byte > 0xF4 { return false }
            } else {
                return false
            }
            if i + seqLen > data.endIndex { return false }
            for j in 1..<seqLen {
                if data[i + j] & 0xC0 != 0x80 { return false }
            }
            i += seqLen
        }
        return true
    }

    // MARK: - INI Parsing

    private struct INISection {
        var name: String
        var pairs: [(key: String, value: String)]
    }

    private static func parseINI(_ text: String) -> [INISection] {
        var sections: [INISection] = []
        var current = INISection(name: "", pairs: [])

        // Split by any line ending (CRLF, LF, CR)
        let lines = text.components(separatedBy: .newlines)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {
                continue
            }

            // Section header
            if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                sections.append(current)
                let name = String(line[line.index(after: line.startIndex)..<close])
                current = INISection(name: name, pairs: [])
                continue
            }

            // Key=Value
            if let eqIdx = line.firstIndex(of: "=") {
                let key = String(line[line.startIndex..<eqIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                current.pairs.append((key: key, value: value))
            }
        }
        sections.append(current)

        // Remove leading empty section
        if let first = sections.first, first.name.isEmpty && first.pairs.isEmpty {
            sections.removeFirst()
        }

        return sections
    }

    // MARK: - Section Reading

    private static func readSection(
        _ sections: [INISection],
        name: String,
        keys: [(KeyID, String)],
        into keyMap: inout KeyMap
    ) {
        guard let section = sections.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else { return }

        for (keyId, keyName) in keys {
            guard let pair = section.pairs.first(where: {
                $0.key.caseInsensitiveCompare(keyName) == .orderedSame
            }) else { continue }

            let value = pair.value
            if value.isEmpty || value.caseInsensitiveCompare("off") == .orderedSame {
                keyMap.map[keyId.rawValue - 1] = 0xFFFF
            } else if let num = UInt16(value) {
                keyMap.map[keyId.rawValue - 1] = num
            } else {
                keyMap.map[keyId.rawValue - 1] = 0xFFFF
            }
        }
    }

    // MARK: - User Keys Reading

    private static func readUserKeys(_ sections: [INISection], into keyMap: inout KeyMap) {
        guard let section = sections.first(where: {
            $0.name.caseInsensitiveCompare("User keys") == .orderedSame
        }) else { return }

        for i in 1...KeyID.numOfUserKey {
            let entryName = "User\(i)"
            guard let pair = section.pairs.first(where: {
                $0.key.caseInsensitiveCompare(entryName) == .orderedSame
            }) else { continue }

            let value = pair.value
            if value.isEmpty { continue }

            if value.caseInsensitiveCompare("off") == .orderedSame ||
               value.lowercased().hasPrefix("off") {
                let ttKeyCode = KeyID.user1.rawValue + i - 1
                if ttKeyCode - 1 < keyMap.map.count {
                    keyMap.map[ttKeyCode - 1] = 0xFFFF
                }
                continue
            }

            // Parse: keycode,type,string
            let components = value.split(separator: ",", maxSplits: 2)
            guard components.count == 3,
                  let keyCode = Int(components[0].trimmingCharacters(in: .whitespaces)),
                  let controlFlag = Int(components[1].trimmingCharacters(in: .whitespaces))
            else { continue }

            let str = String(components[2])

            let entry = UserKeyEntry(
                userIndex: i,
                pcKeyCode: keyCode,
                controlFlag: controlFlag,
                value: str
            )
            keyMap.userKeys.append(entry)

            let ttKeyCode = KeyID.user1.rawValue + i - 1
            if ttKeyCode - 1 < keyMap.map.count {
                keyMap.map[ttKeyCode - 1] = UInt16(keyCode)
            }
        }
    }

    // MARK: - Duplicate Check

    private static func checkDuplicates(_ keyMap: inout KeyMap) {
        for j in 1..<KeyID.keyMax {
            guard keyMap.map[j] != 0xFFFF else { continue }
            for i in 0..<j {
                if keyMap.map[i] == keyMap.map[j] {
                    keyMap.warnings.append(
                        "Keycode \(keyMap.map[j]) is used more than once"
                    )
                    keyMap.map[i] = 0xFFFF
                }
            }
        }
    }

    // MARK: - User Key String Decoder

    /// Decode a user key value string, expanding $HH hex escapes to bytes.
    /// e.g., "telnet$20host$0D" → "telnet host\r"
    static func decodeUserKeyValue(_ value: String) -> Data {
        var result = Data()
        var i = value.startIndex
        while i < value.endIndex {
            if value[i] == "$" {
                let hexStart = value.index(after: i)
                if hexStart < value.endIndex {
                    let hexEnd = value.index(hexStart, offsetBy: 2, limitedBy: value.endIndex) ?? value.endIndex
                    let hexStr = String(value[hexStart..<hexEnd])
                    if hexStr.count == 2, let byte = UInt8(hexStr, radix: 16) {
                        result.append(byte)
                        i = hexEnd
                        continue
                    }
                }
            }
            result.append(contentsOf: value[i].utf8)
            i = value.index(after: i)
        }
        return result
    }
}
