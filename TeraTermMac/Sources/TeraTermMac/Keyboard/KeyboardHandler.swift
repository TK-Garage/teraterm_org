/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of keyboard.c to Swift/macOS
 * Keyboard input handling and key mapping
 */

import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Key Event

struct TerminalKeyEvent {
    let keyCode: UInt16
    let characters: String
    let modifiers: KeyModifiers
    let isKeyDown: Bool

    struct KeyModifiers: OptionSet {
        let rawValue: UInt
        static let shift   = KeyModifiers(rawValue: 1 << 0)
        static let control = KeyModifiers(rawValue: 1 << 1)
        static let alt     = KeyModifiers(rawValue: 1 << 2)  // Option on macOS
        static let meta    = KeyModifiers(rawValue: 1 << 3)  // Command on macOS
    }
}

// MARK: - Keyboard Handler (port of keyboard.c)

class KeyboardHandler {
    var modes: TerminalModes = TerminalModes()
    var settings: TerminalSettings

    /// Controls whether keyboard input is forwarded to the terminal.
    /// Set to false by macro enablekeyboard command to suppress user input during automation.
    var isEnabled: Bool = true

    // User-defined keys
    private var userDefinedKeys: [String: String] = [:]

    // Keyboard input enabled flag (used by macro enablekeyb command)
    private(set) var inputEnabled: Bool = true

    func setInputEnabled(_ enabled: Bool) {
        inputEnabled = enabled
    }

    // Macro key bindings
    private var macroBindings: [String: String] = [:]

    init(settings: TerminalSettings) {
        self.settings = settings
    }

    // MARK: - Process Key Event

    func processKeyEvent(_ event: TerminalKeyEvent) -> Data? {
        guard event.isKeyDown else { return nil }
        guard inputEnabled else { return nil }

        // Check for user-defined key first
        if let udk = processUserDefinedKey(event) {
            return Data(udk.utf8)
        }

        // Handle special keys
        if let special = processSpecialKey(event) {
            return special
        }

        // Handle modifier combinations
        if let modified = processModifiedKey(event) {
            return modified
        }

        // Regular character input
        if !event.characters.isEmpty {
            return processRegularKey(event)
        }

        return nil
    }

    // MARK: - Special Keys (Function keys, arrows, etc.)

    private func processSpecialKey(_ event: TerminalKeyEvent) -> Data? {
        let keyCode = event.keyCode
        let mods = event.modifiers

        // macOS key codes
        switch keyCode {
        case 0x7E: // Up arrow
            return cursorKeySequence("A", mods: mods)
        case 0x7D: // Down arrow
            return cursorKeySequence("B", mods: mods)
        case 0x7C: // Right arrow
            return cursorKeySequence("C", mods: mods)
        case 0x7B: // Left arrow
            return cursorKeySequence("D", mods: mods)

        case 0x73: // Home
            return cursorKeySequence("H", mods: mods)
        case 0x77: // End
            return cursorKeySequence("F", mods: mods)

        case 0x74: // Page Up
            return modifiedSequence("5~", mods: mods)
        case 0x79: // Page Down
            return modifiedSequence("6~", mods: mods)

        case 0x72: // Insert (Help on Mac)
            return modifiedSequence("2~", mods: mods)
        case 0x75: // Forward Delete
            return modifiedSequence("3~", mods: mods)

        case 0x33: // Backspace
            return processBackspace(mods: mods)
        case 0x24: // Return
            return processReturn(mods: mods)
        case 0x30: // Tab
            return processTab(mods: mods)
        case 0x35: // Escape
            return Data([0x1B])

        // Function keys F1-F12
        case 0x7A: return functionKeySequence(1, mods: mods)
        case 0x78: return functionKeySequence(2, mods: mods)
        case 0x63: return functionKeySequence(3, mods: mods)
        case 0x76: return functionKeySequence(4, mods: mods)
        case 0x60: return functionKeySequence(5, mods: mods)
        case 0x61: return functionKeySequence(6, mods: mods)
        case 0x62: return functionKeySequence(7, mods: mods)
        case 0x64: return functionKeySequence(8, mods: mods)
        case 0x65: return functionKeySequence(9, mods: mods)
        case 0x6D: return functionKeySequence(10, mods: mods)
        case 0x67: return functionKeySequence(11, mods: mods)
        case 0x6F: return functionKeySequence(12, mods: mods)
        case 0x69: return functionKeySequence(13, mods: mods)
        case 0x6B: return functionKeySequence(14, mods: mods)
        case 0x71: return functionKeySequence(15, mods: mods)

        // Keypad keys
        case 0x52: return keypadKey("0", mods: mods)  // KP 0
        case 0x53: return keypadKey("1", mods: mods)  // KP 1
        case 0x54: return keypadKey("2", mods: mods)  // KP 2
        case 0x55: return keypadKey("3", mods: mods)  // KP 3
        case 0x56: return keypadKey("4", mods: mods)  // KP 4
        case 0x57: return keypadKey("5", mods: mods)  // KP 5
        case 0x58: return keypadKey("6", mods: mods)  // KP 6
        case 0x59: return keypadKey("7", mods: mods)  // KP 7
        case 0x5B: return keypadKey("8", mods: mods)  // KP 8
        case 0x5C: return keypadKey("9", mods: mods)  // KP 9
        case 0x41: return keypadKey(".", mods: mods)  // KP Decimal
        case 0x43: return keypadKey("*", mods: mods)  // KP Multiply
        case 0x45: return keypadKey("+", mods: mods)  // KP Plus
        case 0x4B: return keypadKey("/", mods: mods)  // KP Divide
        case 0x4E: return keypadKey("-", mods: mods)  // KP Minus
        case 0x4C: return keypadKey("M", mods: mods)  // KP Enter

        default:
            return nil
        }
    }

    // MARK: - Cursor Key Sequences

    private func cursorKeySequence(_ key: String, mods: TerminalKeyEvent.KeyModifiers) -> Data {
        let modifier = xTermModifier(mods)

        if modes.cursorKeyMode && !settings.disableAppCursor && mods.isEmpty {
            // Application cursor mode: ESC O <key>
            return Data("\u{1B}O\(key)".utf8)
        }

        if modifier > 1 {
            // Modified cursor key: CSI 1 ; <mod> <key>
            return Data("\u{1B}[1;\(modifier)\(key)".utf8)
        }

        // Normal cursor mode: CSI <key>
        return Data("\u{1B}[\(key)".utf8)
    }

    // MARK: - Function Key Sequences

    private func functionKeySequence(_ num: Int, mods: TerminalKeyEvent.KeyModifiers) -> Data {
        let modifier = xTermModifier(mods)
        let code: String

        switch num {
        case 1: code = "11"
        case 2: code = "12"
        case 3: code = "13"
        case 4: code = "14"
        case 5: code = "15"
        case 6: code = "17"
        case 7: code = "18"
        case 8: code = "19"
        case 9: code = "20"
        case 10: code = "21"
        case 11: code = "23"
        case 12: code = "24"
        case 13: code = "25"
        case 14: code = "26"
        case 15: code = "28"
        default: code = "11"
        }

        if modifier > 1 {
            return Data("\u{1B}[\(code);\(modifier)~".utf8)
        }
        return Data("\u{1B}[\(code)~".utf8)
    }

    // MARK: - Modified Sequence

    private func modifiedSequence(_ base: String, mods: TerminalKeyEvent.KeyModifiers) -> Data {
        let modifier = xTermModifier(mods)
        if modifier > 1 {
            // Insert modifier before ~
            let code = base.replacingOccurrences(of: "~", with: ";\(modifier)~")
            return Data("\u{1B}[\(code)".utf8)
        }
        return Data("\u{1B}[\(base)".utf8)
    }

    // MARK: - Keypad Keys

    private func keypadKey(_ key: String, mods: TerminalKeyEvent.KeyModifiers) -> Data {
        if modes.applicationKeypad && !settings.disableAppKeypad && mods.isEmpty {
            // Application keypad mode: ESC O <char>
            let kpChar: String
            switch key {
            case "0": kpChar = "p"
            case "1": kpChar = "q"
            case "2": kpChar = "r"
            case "3": kpChar = "s"
            case "4": kpChar = "t"
            case "5": kpChar = "u"
            case "6": kpChar = "v"
            case "7": kpChar = "w"
            case "8": kpChar = "x"
            case "9": kpChar = "y"
            case ".": kpChar = "n"
            case "-": kpChar = "m"
            case "+": kpChar = "k"  // Not standard but commonly used
            case "*": kpChar = "j"
            case "/": kpChar = "o"
            case "M": kpChar = "M"  // Enter
            default: kpChar = key
            }
            return Data("\u{1B}O\(kpChar)".utf8)
        }

        // Numeric mode - send number
        if key == "M" {
            return processReturn(mods: mods)
        }
        return Data(key.utf8)
    }

    // MARK: - Special Key Processing

    private func processBackspace(mods: TerminalKeyEvent.KeyModifiers) -> Data {
        if mods.contains(.alt) {
            // Alt+Backspace: ESC + BS/DEL
            return Data([0x1B, UInt8(settings.bsKey)])
        }
        if mods.contains(.control) {
            return Data([0x08]) // Always BS with Ctrl
        }
        return Data([UInt8(settings.bsKey)])
    }

    private func processReturn(mods: TerminalKeyEvent.KeyModifiers) -> Data {
        if mods.contains(.alt) {
            return Data([0x1B, 0x0D])
        }

        switch settings.crSend {
        case .cr:
            return Data([0x0D])
        case .crlf:
            return Data([0x0D, 0x0A])
        case .lf:
            return Data([0x0A])
        case .auto_:
            return Data([0x0D])
        }
    }

    private func processTab(mods: TerminalKeyEvent.KeyModifiers) -> Data {
        if mods.contains(.shift) {
            return Data("\u{1B}[Z".utf8) // Back tab (CSI Z)
        }
        return Data([0x09])
    }

    // MARK: - Modified Key Processing

    private func processModifiedKey(_ event: TerminalKeyEvent) -> Data? {
        let mods = event.modifiers

        if mods.contains(.control) {
            // Ctrl+key combinations
            if let char = event.characters.first {
                let value = char.asciiValue ?? 0
                switch value {
                case 0x40...0x5F: // @, A-Z, [\]^_
                    return Data([value - 0x40])
                case 0x61...0x7A: // a-z
                    return Data([value - 0x60])
                case 0x20: // Ctrl+Space = NUL
                    return Data([0x00])
                case 0x2F: // Ctrl+/ = 0x1F
                    return Data([0x1F])
                default:
                    break
                }
            }
        }

        if mods.contains(.alt) && !event.characters.isEmpty {
            // Alt/Option key: send ESC prefix
            if settings.metaKey > 0 {
                var data = Data([0x1B])
                data.append(Data(event.characters.utf8))
                return data
            }
        }

        return nil
    }

    // MARK: - Regular Key

    private func processRegularKey(_ event: TerminalKeyEvent) -> Data? {
        return Data(event.characters.utf8)
    }

    // MARK: - User Defined Keys

    private func processUserDefinedKey(_ event: TerminalKeyEvent) -> String? {
        let keyId = "\(event.keyCode)_\(event.modifiers.rawValue)"
        return userDefinedKeys[keyId]
    }

    func setUserDefinedKey(keyCode: UInt16, modifiers: TerminalKeyEvent.KeyModifiers, value: String) {
        let keyId = "\(keyCode)_\(modifiers.rawValue)"
        userDefinedKeys[keyId] = value
    }

    // MARK: - xterm Modifier Encoding

    private func xTermModifier(_ mods: TerminalKeyEvent.KeyModifiers) -> Int {
        var modifier = 1
        if mods.contains(.shift)   { modifier += 1 }
        if mods.contains(.alt)     { modifier += 2 }
        if mods.contains(.control) { modifier += 4 }
        if mods.contains(.meta)    { modifier += 8 }
        return modifier
    }

    // MARK: - Bracketed Paste

    func bracketedPasteStart() -> Data {
        if modes.bracketedPaste {
            return Data("\u{1B}[200~".utf8)
        }
        return Data()
    }

    func bracketedPasteEnd() -> Data {
        if modes.bracketedPaste {
            return Data("\u{1B}[201~".utf8)
        }
        return Data()
    }

    // MARK: - Focus Events

    func focusIn() -> Data? {
        if modes.mouseFocusEvent {
            return Data("\u{1B}[I".utf8)
        }
        return nil
    }

    func focusOut() -> Data? {
        if modes.mouseFocusEvent {
            return Data("\u{1B}[O".utf8)
        }
        return nil
    }

    // MARK: - Mouse Events

    func mouseEvent(button: Int, x: Int, y: Int, isRelease: Bool, modifiers: TerminalKeyEvent.KeyModifiers) -> Data? {
        guard modes.isMouseTrackingActive else { return nil }

        if modes.mouseExtendedSGR {
            return sgrMouseEvent(button: button, x: x, y: y, isRelease: isRelease, modifiers: modifiers)
        }

        // Normal mouse encoding
        var cb = button
        if modifiers.contains(.shift)   { cb |= 4 }
        if modifiers.contains(.alt)     { cb |= 8 }
        if modifiers.contains(.control) { cb |= 16 }

        if isRelease { cb = 3 }

        let cx = min(x + 33, 255)
        let cy = min(y + 33, 255)

        return Data([0x1B, 0x5B, 0x4D, UInt8(cb + 32), UInt8(cx), UInt8(cy)])
    }

    private func sgrMouseEvent(button: Int, x: Int, y: Int, isRelease: Bool, modifiers: TerminalKeyEvent.KeyModifiers) -> Data {
        var cb = button
        if modifiers.contains(.shift)   { cb |= 4 }
        if modifiers.contains(.alt)     { cb |= 8 }
        if modifiers.contains(.control) { cb |= 16 }

        let suffix = isRelease ? "m" : "M"
        return Data("\u{1B}[<\(cb);\(x + 1);\(y + 1)\(suffix)".utf8)
    }

    // MARK: - Scroll Events

    func scrollEvent(direction: Int, x: Int, y: Int, modifiers: TerminalKeyEvent.KeyModifiers) -> Data? {
        guard modes.isMouseTrackingActive else { return nil }

        let button = direction > 0 ? 64 : 65  // Scroll up = 64, scroll down = 65

        if modes.mouseExtendedSGR {
            return sgrMouseEvent(button: button, x: x, y: y, isRelease: false, modifiers: modifiers)
        }

        var cb = button
        if modifiers.contains(.shift)   { cb |= 4 }
        if modifiers.contains(.alt)     { cb |= 8 }
        if modifiers.contains(.control) { cb |= 16 }

        let cx = min(x + 33, 255)
        let cy = min(y + 33, 255)

        return Data([0x1B, 0x5B, 0x4D, UInt8(cb + 32), UInt8(cx), UInt8(cy)])
    }
}
