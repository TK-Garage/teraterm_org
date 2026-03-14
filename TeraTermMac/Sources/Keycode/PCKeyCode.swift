/*
 * PCKeyCode.swift
 * PC key code conversion table and calculation for Keycode.app
 *
 * Port of KEYCODE.EXE key code calculation to macOS.
 * Uses macOS NSEvent keyCode as the base value with modifier offsets.
 *
 * Original TeraTerm (Windows):
 *   Scan = HIWORD(lParam) & 0x1ff   (hardware scan code, 9 bits)
 *   Shift → +0x200, Ctrl → +0x400, Alt → +0x800
 *
 * macOS port:
 *   Base = NSEvent.keyCode (0-127)
 *   Shift → +256, Ctrl → +512, Option → +1024 (combined only)
 *   Option alone → +2048 (manual calculation, shown as UI hint)
 */

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Modifier Offsets

/// Modifier key offset values for PC key code calculation.
enum ModifierOffset {
    static let none: Int             = 0
    static let shift: Int            = 256   // bit 8
    static let control: Int          = 512   // bit 9
    static let option: Int           = 1024  // bit 10
    static let shiftControl: Int     = 768   // 256 + 512
    static let shiftOption: Int      = 1280  // 256 + 1024
    static let controlOption: Int    = 1536  // 512 + 1024
    static let shiftControlOption: Int = 1792 // 256 + 512 + 1024
    static let optionAlone: Int      = 2048  // Meta key (manual calculation)
}

// MARK: - Key Name Table

/// Human-readable name for each macOS keyCode.
/// Used for the key description label in the UI.
let keyNames: [UInt16: String] = [
    // Letters
    0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
    0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
    0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
    0x10: "Y", 0x11: "T", 0x20: "U", 0x22: "I", 0x1F: "O",
    0x23: "P", 0x25: "L", 0x26: "J", 0x28: "K", 0x2D: "N",
    0x2E: "M",

    // Numbers
    0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6",
    0x17: "5", 0x19: "9", 0x1A: "7", 0x1C: "8", 0x1D: "0",

    // Symbols
    0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[",
    0x27: "'", 0x29: ";", 0x2A: "\\", 0x2B: ",",
    0x2C: "/", 0x2F: ".", 0x32: "`",

    // Special keys
    0x24: "Return", 0x30: "Tab", 0x31: "Space",
    0x33: "BackSpace", 0x35: "Escape", 0x39: "CapsLock",

    // Function keys
    0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
    0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
    0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16",
    0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",

    // Cursor keys
    0x7E: "↑", 0x7D: "↓", 0x7B: "←", 0x7C: "→",

    // Editing keys
    0x75: "Delete", 0x73: "Home", 0x77: "End",
    0x74: "PageUp", 0x79: "PageDown", 0x72: "Insert",

    // Keypad
    0x52: "Keypad 0", 0x53: "Keypad 1", 0x54: "Keypad 2",
    0x55: "Keypad 3", 0x56: "Keypad 4", 0x57: "Keypad 5",
    0x58: "Keypad 6", 0x59: "Keypad 7", 0x5B: "Keypad 8",
    0x5C: "Keypad 9", 0x41: "Keypad .", 0x43: "Keypad *",
    0x45: "Keypad +", 0x4B: "Keypad /", 0x4E: "Keypad -",
    0x51: "Keypad =", 0x4C: "Keypad Enter", 0x47: "Keypad Clear",
]

/// Set of all recognized macOS keyCodes for which we produce a PC key code.
let recognizedKeyCodes: Set<UInt16> = Set(keyNames.keys)

// MARK: - Modifier-only key codes (should be ignored)

/// macOS keyCodes for modifier keys themselves.
let modifierKeyCodes: Set<UInt16> = [
    0x38, // Left Shift
    0x3C, // Right Shift
    0x3B, // Left Control
    0x3E, // Right Control
    0x3A, // Left Option
    0x3D, // Right Option
    0x37, // Left Command
    0x36, // Right Command
    0x3F, // Function (fn)
]

// MARK: - PC Key Code Calculation

#if canImport(AppKit)

/// Calculate the modifier offset from NSEvent.ModifierFlags.
/// Option-only combinations return nil (displayed as manual hint).
func modifierOffset(from flags: NSEvent.ModifierFlags) -> Int? {
    let shift = flags.contains(.shift)
    let ctrl = flags.contains(.control)
    let opt = flags.contains(.option)

    // Option alone → manual calculation (return nil to signal hint display)
    if opt && !shift && !ctrl {
        return nil
    }

    var offset = 0
    if shift { offset += ModifierOffset.shift }
    if ctrl  { offset += ModifierOffset.control }
    if opt   { offset += ModifierOffset.option }
    return offset
}

/// Calculate the PC key code from a macOS key event.
///
/// - Parameters:
///   - keyCode: The macOS NSEvent keyCode (hardware key identifier).
///   - modifiers: The modifier flags from the NSEvent.
/// - Returns: The PC key code, or nil if the key is a modifier-only key
///            or Option-only combination.
func pcKeyCode(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Int? {
    // Ignore modifier-only keys
    guard !modifierKeyCodes.contains(keyCode) else { return nil }

    guard let offset = modifierOffset(from: modifiers) else {
        // Option-only: signal to UI to show hint
        return nil
    }

    return Int(keyCode) + offset
}

/// Build the human-readable key description string.
/// e.g., "Shift + Ctrl + A", "F5", "Keypad 0"
func keyDescription(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
    var parts: [String] = []

    if modifiers.contains(.shift)   { parts.append("Shift") }
    if modifiers.contains(.control) { parts.append("Ctrl") }
    if modifiers.contains(.option)  { parts.append("Option") }
    if modifiers.contains(.command) { parts.append("Cmd") }

    let name = keyNames[keyCode] ?? "0x\(String(keyCode, radix: 16, uppercase: true))"
    parts.append(name)

    return parts.joined(separator: " + ")
}

/// Check if the event represents an Option-only key combination.
func isOptionOnly(modifiers: NSEvent.ModifierFlags) -> Bool {
    let shift = modifiers.contains(.shift)
    let ctrl = modifiers.contains(.control)
    let opt = modifiers.contains(.option)
    return opt && !shift && !ctrl
}

#endif

// MARK: - Pure calculation (for testing without AppKit event flags)

/// Calculate PC key code from raw values (testable without NSEvent).
///
/// - Parameters:
///   - keyCode: macOS keyCode value.
///   - shift: Shift modifier active.
///   - control: Control modifier active.
///   - option: Option modifier active (in combination with other modifiers).
/// - Returns: The PC key code.
func pcKeyCodeRaw(keyCode: UInt16, shift: Bool = false, control: Bool = false, option: Bool = false) -> Int {
    var offset = 0
    if shift   { offset += ModifierOffset.shift }
    if control { offset += ModifierOffset.control }
    if option  { offset += ModifierOffset.option }
    return Int(keyCode) + offset
}
