/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of vtterm.c to Swift/macOS
 * VT100/VT220/VT320/VT420/xterm terminal emulation parser
 */

import Foundation

// MARK: - Parser State Machine (port of vtterm.c state machine)

enum ParserState {
    case ground
    case escape
    case escapeIntermediate
    case csiEntry
    case csiParam
    case csiIntermediate
    case csiIgnore
    case dcsEntry
    case dcsParam
    case dcsIntermediate
    case dcsPassthrough
    case dcsIgnore
    case oscString
    case sosPmApcString
    case utf8
}

// MARK: - CSI Parameter

struct CSIParams {
    var params: [Int] = []
    var subParams: [[Int]] = []
    var intermediates: [UInt8] = []
    var privateMarker: UInt8? = nil  // ? > = !

    var count: Int { params.count }

    func param(_ index: Int, default defaultValue: Int = 0) -> Int {
        guard index < params.count else { return defaultValue }
        let val = params[index]
        return val == 0 ? defaultValue : val
    }

    mutating func reset() {
        params = []
        subParams = []
        intermediates = []
        privateMarker = nil
    }
}

// MARK: - Terminal Modes

struct TerminalModes {
    // DEC Private Modes (DECSET/DECRST)
    var cursorKeyMode: Bool = false           // DECCKM (1)
    var ansiMode: Bool = true                 // DECANM (2)
    var columnMode132: Bool = false            // DECCOLM (3)
    var smoothScroll: Bool = false             // DECSCLM (4)
    var reverseVideo: Bool = false             // DECSCNM (5)
    var originMode: Bool = false               // DECOM (6)
    var autoWrapMode: Bool = true              // DECAWM (7)
    var autoRepeatMode: Bool = true            // DECARM (8)
    var showCursor: Bool = true                // DECTCEM (25)
    var allow132Mode: Bool = false             // (40)
    var reverseWrapAround: Bool = false        // (45)
    var alternateScreenBuffer: Bool = false    // (47)
    var bracketedPaste: Bool = false           // (2004)
    var applicationKeypad: Bool = false        // DECKPAM/DECKPNM

    // Mouse modes
    var mouseTrackingX10: Bool = false         // (9)
    var mouseTrackingNormal: Bool = false      // (1000)
    var mouseTrackingHighlight: Bool = false   // (1001)
    var mouseTrackingButton: Bool = false      // (1002)
    var mouseTrackingAny: Bool = false         // (1003)
    var mouseFocusEvent: Bool = false          // (1004)
    var mouseExtendedUTF8: Bool = false        // (1005)
    var mouseExtendedSGR: Bool = false         // (1006)
    var mouseExtendedURXVT: Bool = false       // (1015)
    var mouseExtendedSGRPixels: Bool = false   // (1016)

    // xterm private modes
    var altScreenBuffer: Bool = false          // (1047)
    var saveCursorAltBuffer: Bool = false      // (1048)
    var altScreenBufferClear: Bool = false     // (1049)

    // Standard Modes (SM/RM)
    var insertMode: Bool = false               // IRM (4)
    var sendReceiveMode: Bool = true           // SRM (12)
    var newLineMode: Bool = false              // LNM (20)

    // Left/Right margin mode
    var leftRightMarginMode: Bool = false      // DECLRMM (69)

    var isMouseTrackingActive: Bool {
        return mouseTrackingX10 || mouseTrackingNormal ||
               mouseTrackingButton || mouseTrackingAny
    }
}

// MARK: - Character Set State (port of charset.cpp)

struct CharSetState {
    enum CharSet: UInt8 {
        case ascii = 0
        case decSpecialGraphics = 1
        case ukNational = 2
        case decTechnical = 3
    }

    var gl: Int = 0   // G0-G3 index for GL
    var gr: Int = 2   // G0-G3 index for GR
    var g: [CharSet] = [.ascii, .ascii, .ascii, .ascii]  // G0-G3
    var singleShift: Int? = nil  // SS2=2, SS3=3

    mutating func reset() {
        gl = 0
        gr = 2
        g = [.ascii, .ascii, .ascii, .ascii]
        singleShift = nil
    }
}

// MARK: - VT Parser Delegate

protocol VTParserDelegate: AnyObject {
    func parserDidReceivePrintable(_ text: String)
    func parserDidReceiveControl(_ char: UInt8)
    func parserDidReceiveCSI(params: CSIParams, final: UInt8)
    func parserDidReceiveESC(intermediates: [UInt8], final: UInt8)
    func parserDidReceiveOSC(command: Int, data: String)
    func parserDidReceiveDCS(params: CSIParams, intermediates: [UInt8], data: String)
    func parserDidRequestBell()
    func parserDidRequestBackspace()
    func parserDidRequestTab()
    func parserDidRequestLineFeed()
    func parserDidRequestCarriageReturn()
    func parserDidRequestShiftOut()
    func parserDidRequestShiftIn()
}

// MARK: - VT Terminal Parser (port of vtterm.c)

class VTParser {
    weak var delegate: VTParserDelegate?

    private var state: ParserState = .ground
    private var csiParams = CSIParams()
    private var oscString = ""
    private var oscCommand: Int = -1
    private var dcsString = ""
    private var dcsParams = CSIParams()
    private var dcsIntermediates: [UInt8] = []
    private var escIntermediates: [UInt8] = []
    private var printBuffer = ""

    // UTF-8 decoding state
    private var utf8Remaining: Int = 0
    private var utf8Value: UInt32 = 0

    // Parameter accumulator
    private var currentParam: Int = 0
    private var paramStarted: Bool = false

    init() {}

    // MARK: - Main Parse Entry Point

    func parse(_ data: Data) {
        for byte in data {
            processByte(byte)
        }
        flushPrintBuffer()
    }

    func parse(_ bytes: [UInt8]) {
        for byte in bytes {
            processByte(byte)
        }
        flushPrintBuffer()
    }

    func parse(_ string: String) {
        parse(Array(string.utf8))
    }

    // MARK: - Byte Processing State Machine

    private func processByte(_ byte: UInt8) {
        // C0 controls take effect in most states
        if byte < 0x20 && state != .oscString && state != .dcsPassthrough && state != .sosPmApcString {
            if handleC0Control(byte) {
                return
            }
        }

        // C1 controls (0x80-0x9F) when received as single bytes
        if byte >= 0x80 && byte <= 0x9F && state == .ground {
            handleC1Control(byte)
            return
        }

        switch state {
        case .ground:
            handleGround(byte)

        case .escape:
            handleEscape(byte)

        case .escapeIntermediate:
            handleEscapeIntermediate(byte)

        case .csiEntry:
            handleCSIEntry(byte)

        case .csiParam:
            handleCSIParam(byte)

        case .csiIntermediate:
            handleCSIIntermediate(byte)

        case .csiIgnore:
            handleCSIIgnore(byte)

        case .dcsEntry:
            handleDCSEntry(byte)

        case .dcsParam:
            handleDCSParam(byte)

        case .dcsIntermediate:
            handleDCSIntermediate(byte)

        case .dcsPassthrough:
            handleDCSPassthrough(byte)

        case .dcsIgnore:
            handleDCSIgnore(byte)

        case .oscString:
            handleOSCString(byte)

        case .sosPmApcString:
            handleSOSPMAPC(byte)

        case .utf8:
            handleUTF8(byte)
        }
    }

    // MARK: - C0 Control Characters

    private func handleC0Control(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x00: // NUL - ignore
            return true
        case 0x07: // BEL
            flushPrintBuffer()
            if state == .oscString {
                dispatchOSC()
                state = .ground
                return true
            }
            delegate?.parserDidRequestBell()
            return true
        case 0x08: // BS
            flushPrintBuffer()
            delegate?.parserDidRequestBackspace()
            return true
        case 0x09: // HT
            flushPrintBuffer()
            delegate?.parserDidRequestTab()
            return true
        case 0x0A, 0x0B, 0x0C: // LF, VT, FF
            flushPrintBuffer()
            delegate?.parserDidRequestLineFeed()
            return true
        case 0x0D: // CR
            flushPrintBuffer()
            delegate?.parserDidRequestCarriageReturn()
            return true
        case 0x0E: // SO (Shift Out)
            flushPrintBuffer()
            delegate?.parserDidRequestShiftOut()
            return true
        case 0x0F: // SI (Shift In)
            flushPrintBuffer()
            delegate?.parserDidRequestShiftIn()
            return true
        case 0x1B: // ESC
            flushPrintBuffer()
            state = .escape
            escIntermediates = []
            return true
        case 0x18, 0x1A: // CAN, SUB - cancel current sequence
            state = .ground
            return true
        default:
            return false
        }
    }

    // MARK: - C1 Control Characters (8-bit)

    private func handleC1Control(_ byte: UInt8) {
        flushPrintBuffer()
        switch byte {
        case 0x84: // IND (Index)
            delegate?.parserDidRequestLineFeed()
        case 0x85: // NEL (Next Line)
            delegate?.parserDidRequestCarriageReturn()
            delegate?.parserDidRequestLineFeed()
        case 0x88: // HTS (Horizontal Tab Set)
            delegate?.parserDidReceiveESC(intermediates: [], final: 0x48) // ESC H
        case 0x8D: // RI (Reverse Index)
            delegate?.parserDidReceiveESC(intermediates: [], final: 0x4D) // ESC M
        case 0x8E: // SS2
            delegate?.parserDidReceiveESC(intermediates: [], final: 0x4E)
        case 0x8F: // SS3
            delegate?.parserDidReceiveESC(intermediates: [], final: 0x4F)
        case 0x90: // DCS
            state = .dcsEntry
            dcsParams.reset()
            dcsIntermediates = []
            dcsString = ""
        case 0x9B: // CSI
            state = .csiEntry
            csiParams.reset()
            currentParam = 0
            paramStarted = false
        case 0x9C: // ST
            break // String terminator
        case 0x9D: // OSC
            state = .oscString
            oscString = ""
            oscCommand = -1
        case 0x9E: // PM
            state = .sosPmApcString
        case 0x9F: // APC
            state = .sosPmApcString
        default:
            break
        }
    }

    // MARK: - Ground State

    private func handleGround(_ byte: UInt8) {
        if byte >= 0x80 {
            // Multi-byte UTF-8
            if byte >= 0xC0 && byte <= 0xDF {
                utf8Remaining = 1
                utf8Value = UInt32(byte & 0x1F)
                state = .utf8
            } else if byte >= 0xE0 && byte <= 0xEF {
                utf8Remaining = 2
                utf8Value = UInt32(byte & 0x0F)
                state = .utf8
            } else if byte >= 0xF0 && byte <= 0xF7 {
                utf8Remaining = 3
                utf8Value = UInt32(byte & 0x07)
                state = .utf8
            } else if byte >= 0xA0 {
                // Latin-1 supplement
                if let scalar = UnicodeScalar(UInt32(byte)) {
                    printBuffer.append(Character(scalar))
                }
            }
        } else if byte >= 0x20 {
            // Printable ASCII
            printBuffer.append(Character(UnicodeScalar(byte)))
        }
    }

    // MARK: - UTF-8 Continuation

    private func handleUTF8(_ byte: UInt8) {
        if byte & 0xC0 == 0x80 {
            utf8Value = (utf8Value << 6) | UInt32(byte & 0x3F)
            utf8Remaining -= 1
            if utf8Remaining == 0 {
                if let scalar = UnicodeScalar(utf8Value) {
                    printBuffer.append(Character(scalar))
                }
                state = .ground
            }
        } else {
            // Invalid continuation byte
            state = .ground
            processByte(byte)
        }
    }

    // MARK: - Escape Sequence

    private func handleEscape(_ byte: UInt8) {
        switch byte {
        case 0x20...0x2F: // Intermediate bytes
            escIntermediates.append(byte)
            state = .escapeIntermediate

        case 0x30...0x4F, 0x51...0x57, 0x59, 0x5A, 0x5C, 0x60...0x7E:
            // Final byte - dispatch
            delegate?.parserDidReceiveESC(intermediates: escIntermediates, final: byte)
            state = .ground

        case 0x5B: // [ -> CSI
            state = .csiEntry
            csiParams.reset()
            currentParam = 0
            paramStarted = false

        case 0x5D: // ] -> OSC
            state = .oscString
            oscString = ""
            oscCommand = -1

        case 0x50: // P -> DCS
            state = .dcsEntry
            dcsParams.reset()
            dcsIntermediates = []
            dcsString = ""

        case 0x58: // X -> SOS
            state = .sosPmApcString

        case 0x5E: // ^ -> PM
            state = .sosPmApcString

        case 0x5F: // _ -> APC
            state = .sosPmApcString

        default:
            state = .ground
        }
    }

    private func handleEscapeIntermediate(_ byte: UInt8) {
        if byte >= 0x20 && byte <= 0x2F {
            escIntermediates.append(byte)
        } else if byte >= 0x30 && byte <= 0x7E {
            delegate?.parserDidReceiveESC(intermediates: escIntermediates, final: byte)
            state = .ground
        } else {
            state = .ground
        }
    }

    // MARK: - CSI Sequence

    private func handleCSIEntry(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39: // 0-9
            currentParam = Int(byte - 0x30)
            paramStarted = true
            state = .csiParam

        case 0x3B: // ;
            csiParams.params.append(0)
            state = .csiParam

        case 0x3C...0x3F: // < = > ?
            csiParams.privateMarker = byte
            state = .csiParam

        case 0x20...0x2F: // Intermediate
            csiParams.intermediates.append(byte)
            state = .csiIntermediate

        case 0x40...0x7E: // Final byte
            dispatchCSI(byte)
            state = .ground

        default:
            state = .ground
        }
    }

    private func handleCSIParam(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39: // 0-9
            currentParam = currentParam * 10 + Int(byte - 0x30)
            paramStarted = true

        case 0x3A: // : (sub-parameter separator)
            if paramStarted {
                csiParams.params.append(currentParam)
                currentParam = 0
                paramStarted = false
            }

        case 0x3B: // ;
            csiParams.params.append(paramStarted ? currentParam : 0)
            currentParam = 0
            paramStarted = false

        case 0x3C...0x3F: // < = > ? (can appear in params for some sequences)
            if csiParams.params.isEmpty && !paramStarted {
                csiParams.privateMarker = byte
            }

        case 0x20...0x2F: // Intermediate
            if paramStarted {
                csiParams.params.append(currentParam)
                currentParam = 0
                paramStarted = false
            }
            csiParams.intermediates.append(byte)
            state = .csiIntermediate

        case 0x40...0x7E: // Final byte
            if paramStarted {
                csiParams.params.append(currentParam)
                currentParam = 0
                paramStarted = false
            }
            dispatchCSI(byte)
            state = .ground

        default:
            state = .csiIgnore
        }
    }

    private func handleCSIIntermediate(_ byte: UInt8) {
        if byte >= 0x20 && byte <= 0x2F {
            csiParams.intermediates.append(byte)
        } else if byte >= 0x40 && byte <= 0x7E {
            dispatchCSI(byte)
            state = .ground
        } else {
            state = .csiIgnore
        }
    }

    private func handleCSIIgnore(_ byte: UInt8) {
        if byte >= 0x40 && byte <= 0x7E {
            state = .ground
        }
    }

    private func dispatchCSI(_ final: UInt8) {
        delegate?.parserDidReceiveCSI(params: csiParams, final: final)
    }

    // MARK: - DCS Sequence

    private func handleDCSEntry(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39:
            currentParam = Int(byte - 0x30)
            paramStarted = true
            state = .dcsParam
        case 0x3B:
            dcsParams.params.append(0)
            state = .dcsParam
        case 0x3C...0x3F:
            dcsParams.privateMarker = byte
            state = .dcsParam
        case 0x20...0x2F:
            dcsIntermediates.append(byte)
            state = .dcsIntermediate
        case 0x40...0x7E:
            state = .dcsPassthrough
        default:
            state = .dcsIgnore
        }
    }

    private func handleDCSParam(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39:
            currentParam = currentParam * 10 + Int(byte - 0x30)
            paramStarted = true
        case 0x3B:
            dcsParams.params.append(paramStarted ? currentParam : 0)
            currentParam = 0
            paramStarted = false
        case 0x20...0x2F:
            if paramStarted {
                dcsParams.params.append(currentParam)
                currentParam = 0
                paramStarted = false
            }
            dcsIntermediates.append(byte)
            state = .dcsIntermediate
        case 0x40...0x7E:
            if paramStarted {
                dcsParams.params.append(currentParam)
                currentParam = 0
                paramStarted = false
            }
            state = .dcsPassthrough
        default:
            state = .dcsIgnore
        }
    }

    private func handleDCSIntermediate(_ byte: UInt8) {
        if byte >= 0x20 && byte <= 0x2F {
            dcsIntermediates.append(byte)
        } else if byte >= 0x40 && byte <= 0x7E {
            state = .dcsPassthrough
        } else {
            state = .dcsIgnore
        }
    }

    private func handleDCSPassthrough(_ byte: UInt8) {
        if byte == 0x9C || byte == 0x1B { // ST or ESC
            if byte == 0x1B {
                // Need to check for ESC \ (ST)
                // For simplicity, end DCS on ESC
            }
            delegate?.parserDidReceiveDCS(params: dcsParams, intermediates: dcsIntermediates, data: dcsString)
            state = .ground
        } else {
            dcsString.append(Character(UnicodeScalar(byte)))
        }
    }

    private func handleDCSIgnore(_ byte: UInt8) {
        if byte == 0x9C { // ST
            state = .ground
        }
    }

    // MARK: - OSC String

    private func handleOSCString(_ byte: UInt8) {
        switch byte {
        case 0x07: // BEL - terminates OSC
            dispatchOSC()
            state = .ground
        case 0x1B: // ESC - might be ESC \ (ST)
            // We'll handle this as termination
            dispatchOSC()
            state = .escape
        case 0x9C: // ST
            dispatchOSC()
            state = .ground
        case 0x3B: // ; separator between command and data
            if oscCommand == -1 {
                oscCommand = Int(oscString) ?? -1
                oscString = ""
            } else {
                oscString.append(";")
            }
        default:
            if byte >= 0x20 {
                oscString.append(Character(UnicodeScalar(byte)))
            }
        }
    }

    private func dispatchOSC() {
        if oscCommand == -1 {
            oscCommand = Int(oscString) ?? 0
            oscString = ""
        }
        delegate?.parserDidReceiveOSC(command: oscCommand, data: oscString)
    }

    // MARK: - SOS/PM/APC

    private func handleSOSPMAPC(_ byte: UInt8) {
        if byte == 0x9C || byte == 0x07 { // ST or BEL
            state = .ground
        }
        // Otherwise just consume bytes
    }

    // MARK: - Print Buffer

    private func flushPrintBuffer() {
        if !printBuffer.isEmpty {
            delegate?.parserDidReceivePrintable(printBuffer)
            printBuffer = ""
        }
    }

    // MARK: - Reset

    func reset() {
        state = .ground
        csiParams.reset()
        oscString = ""
        oscCommand = -1
        dcsString = ""
        dcsParams.reset()
        dcsIntermediates = []
        escIntermediates = []
        printBuffer = ""
        utf8Remaining = 0
        utf8Value = 0
        currentParam = 0
        paramStarted = false
    }
}
