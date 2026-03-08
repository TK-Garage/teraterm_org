/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of vtterm.c CSI/ESC command handling to Swift/macOS
 * Terminal emulator - connects parser to buffer
 */

import Foundation

// MARK: - Terminal Emulator Delegate

protocol TerminalEmulatorDelegate: AnyObject {
    func terminalDidUpdateDisplay()
    func terminalDidChangeCursorPosition(x: Int, y: Int)
    func terminalDidChangeTitle(_ title: String)
    func terminalDidChangeIconTitle(_ title: String)
    func terminalDidRing()
    func terminalDidRequestResize(width: Int, height: Int)
    func terminalDidRequestResponse(_ data: Data)
    func terminalDidChangeMode(_ modes: TerminalModes)
    func terminalDidRequestPaste()
    func terminalDidRequestCopy(_ text: String)
    func terminalDidChangeColors()
}

// MARK: - Terminal Emulator (port of vtterm.c)

class TerminalEmulator {
    weak var delegate: TerminalEmulatorDelegate?

    let buffer: TerminalBuffer
    let parser: VTParser
    var settings: TerminalSettings
    var modes = TerminalModes()
    var charSet = CharSetState()

    // Terminal identification
    var terminalID: TerminalID = .vt220

    // Conformance level
    var conformanceLevel: Int = 2  // VT100=1, VT200+=2

    // Title
    var windowTitle: String = "Tera Term"
    var iconTitle: String = "Tera Term"

    // Protected mode
    var protectedMode: Bool = false

    // Charset reporting
    var sendCharSet: CharSetState = CharSetState()

    // CR/LF receive state for AUTO mode (port of vtterm.c PrevCharacter/PrevCRorLFGeneratedCRLF)
    private var prevControlChar: UInt8 = 0
    private var prevCRorLFGeneratedCRLF: Bool = false

    // Macro receive buffer: accumulates received text for TTL wait commands
    var macroReceiveBuffer: String = ""

    init(settings: TerminalSettings) {
        self.settings = settings
        self.terminalID = settings.terminalID
        self.buffer = TerminalBuffer(
            width: settings.terminalWidth,
            height: settings.terminalHeight,
            scrollBufferSize: settings.scrollBufferSize
        )
        self.parser = VTParser()
        self.parser.delegate = self
    }

    // MARK: - Data Processing

    func processData(_ data: Data) {
        parser.parse(data)
        // Feed macro receive buffer for TTL wait commands
        if let text = String(data: data, encoding: .utf8) {
            macroReceiveBuffer += text
        }
        delegate?.terminalDidUpdateDisplay()
    }

    func processString(_ string: String) {
        parser.parse(string)
        delegate?.terminalDidUpdateDisplay()
    }

    // MARK: - Resize

    func resize(width: Int, height: Int) {
        buffer.resize(newWidth: width, newHeight: height)
        settings.terminalWidth = width
        settings.terminalHeight = height
    }

    // MARK: - Reset

    func softReset() {
        // DECSTR - Soft Terminal Reset
        modes.insertMode = false
        modes.originMode = false
        buffer.originMode = false
        modes.autoWrapMode = true
        modes.cursorKeyMode = false
        modes.applicationKeypad = false
        modes.showCursor = true
        modes.reverseVideo = false

        buffer.currentAttributes = []
        buffer.currentColor = .default

        buffer.setScrollRegion(top: 0, bottom: buffer.height - 1)
        buffer.scrollLeft = 0
        buffer.scrollRight = buffer.width - 1
        buffer.useLeftRightMargin = false
        modes.leftRightMarginMode = false

        charSet.reset()
        buffer.saveCursor()

        delegate?.terminalDidChangeMode(modes)
    }

    func hardReset() {
        // RIS - Full Reset
        softReset()
        buffer.reset()
        buffer.tabStops.reset(width: buffer.width)
        parser.reset()
        charSet.reset()
        modes = TerminalModes()

        delegate?.terminalDidUpdateDisplay()
        delegate?.terminalDidChangeMode(modes)
    }

    // MARK: - Send Response

    private func sendResponse(_ string: String) {
        delegate?.terminalDidRequestResponse(Data(string.utf8))
    }

    // MARK: - SGR (Select Graphic Rendition) Processing

    private func processSGR(_ params: CSIParams) {
        if params.count == 0 {
            buffer.currentAttributes = []
            buffer.currentColor = .default
            return
        }

        var i = 0
        while i < params.count {
            let p = params.params[i]
            switch p {
            case 0: // Reset
                buffer.currentAttributes = []
                buffer.currentColor = .default
            case 1: buffer.currentAttributes.insert(.bold)
            case 2: buffer.currentAttributes.insert(.dim)
            case 3: buffer.currentAttributes.insert(.italic)
            case 4: buffer.currentAttributes.insert(.underline)
            case 5: buffer.currentAttributes.insert(.blink)
            case 7: buffer.currentAttributes.insert(.reverse)
            case 8: buffer.currentAttributes.insert(.invisible)
            case 9: buffer.currentAttributes.insert(.strikethrough)
            case 21: buffer.currentAttributes.insert(.doubleUnderline)
            case 22:
                buffer.currentAttributes.remove(.bold)
                buffer.currentAttributes.remove(.dim)
            case 23: buffer.currentAttributes.remove(.italic)
            case 24:
                buffer.currentAttributes.remove(.underline)
                buffer.currentAttributes.remove(.doubleUnderline)
                buffer.currentAttributes.remove(.curlyUnderline)
                buffer.currentAttributes.remove(.dottedUnderline)
                buffer.currentAttributes.remove(.dashedUnderline)
            case 25: buffer.currentAttributes.remove(.blink)
            case 27: buffer.currentAttributes.remove(.reverse)
            case 28: buffer.currentAttributes.remove(.invisible)
            case 29: buffer.currentAttributes.remove(.strikethrough)

            // Foreground colors (standard)
            case 30...37:
                buffer.currentColor.foreground = UInt8(p - 30)
                buffer.currentColor.isFgDefault = false
                buffer.currentColor.isFg256 = false
                buffer.currentColor.isFgRGB = false
            case 38: // Extended foreground
                i = processExtendedColor(params, index: i, isForeground: true)
            case 39: // Default foreground
                buffer.currentColor.isFgDefault = true
                buffer.currentColor.isFg256 = false
                buffer.currentColor.isFgRGB = false

            // Background colors (standard)
            case 40...47:
                buffer.currentColor.background = UInt8(p - 40)
                buffer.currentColor.isBgDefault = false
                buffer.currentColor.isBg256 = false
                buffer.currentColor.isBgRGB = false
            case 48: // Extended background
                i = processExtendedColor(params, index: i, isForeground: false)
            case 49: // Default background
                buffer.currentColor.isBgDefault = true
                buffer.currentColor.isBg256 = false
                buffer.currentColor.isBgRGB = false

            case 53: buffer.currentAttributes.insert(.overline)
            case 55: buffer.currentAttributes.remove(.overline)

            // Bright foreground colors
            case 90...97:
                buffer.currentColor.foreground = UInt8(p - 90 + 8)
                buffer.currentColor.isFgDefault = false
                buffer.currentColor.isFg256 = false
                buffer.currentColor.isFgRGB = false

            // Bright background colors
            case 100...107:
                buffer.currentColor.background = UInt8(p - 100 + 8)
                buffer.currentColor.isBgDefault = false
                buffer.currentColor.isBg256 = false
                buffer.currentColor.isBgRGB = false

            default:
                break
            }
            i += 1
        }
    }

    private func processExtendedColor(_ params: CSIParams, index: Int, isForeground: Bool) -> Int {
        guard index + 1 < params.count else { return index }

        let mode = params.params[index + 1]
        switch mode {
        case 5: // 256-color
            guard index + 2 < params.count else { return index + 1 }
            let colorIndex = UInt8(clamping: params.params[index + 2])
            if isForeground {
                buffer.currentColor.foreground = colorIndex
                buffer.currentColor.isFgDefault = false
                buffer.currentColor.isFg256 = true
                buffer.currentColor.isFgRGB = false
            } else {
                buffer.currentColor.background = colorIndex
                buffer.currentColor.isBgDefault = false
                buffer.currentColor.isBg256 = true
                buffer.currentColor.isBgRGB = false
            }
            return index + 2

        case 2: // True color (RGB)
            guard index + 4 < params.count else { return index + 1 }
            let r = UInt8(clamping: params.params[index + 2])
            let g = UInt8(clamping: params.params[index + 3])
            let b = UInt8(clamping: params.params[index + 4])
            if isForeground {
                buffer.currentColor.fgR = r
                buffer.currentColor.fgG = g
                buffer.currentColor.fgB = b
                buffer.currentColor.isFgDefault = false
                buffer.currentColor.isFg256 = false
                buffer.currentColor.isFgRGB = true
            } else {
                buffer.currentColor.bgR = r
                buffer.currentColor.bgG = g
                buffer.currentColor.bgB = b
                buffer.currentColor.isBgDefault = false
                buffer.currentColor.isBg256 = false
                buffer.currentColor.isBgRGB = true
            }
            return index + 4

        default:
            return index + 1
        }
    }

    // MARK: - DEC Private Mode Set/Reset

    private func setDecPrivateMode(_ mode: Int, enabled: Bool) {
        switch mode {
        case 1: // DECCKM - Cursor Key Mode
            modes.cursorKeyMode = enabled
        case 2: // DECANM - ANSI/VT52 Mode
            modes.ansiMode = enabled
        case 3: // DECCOLM - 132/80 Column Mode
            if modes.allow132Mode {
                modes.columnMode132 = enabled
                let newWidth = enabled ? 132 : 80
                delegate?.terminalDidRequestResize(width: newWidth, height: buffer.height)
                buffer.eraseInDisplay(2)
                buffer.moveCursorTo(x: 0, y: 0)
            }
        case 4: // DECSCLM - Smooth Scroll
            modes.smoothScroll = enabled
        case 5: // DECSCNM - Screen Mode (Reverse Video)
            if modes.reverseVideo != enabled {
                modes.reverseVideo = enabled
                delegate?.terminalDidChangeColors()
            }
        case 6: // DECOM - Origin Mode
            modes.originMode = enabled
            buffer.originMode = enabled
            if enabled {
                buffer.moveCursorTo(x: 0, y: 0) // Home within margins
            } else {
                buffer.moveCursorTo(x: 0, y: 0)
            }
        case 7: // DECAWM - Auto Wrap Mode
            modes.autoWrapMode = enabled
        case 8: // DECARM - Auto Repeat
            modes.autoRepeatMode = enabled
        case 9: // X10 Mouse tracking
            modes.mouseTrackingX10 = enabled
        case 12: // Cursor blinking (AT&T)
            // Toggle cursor blink
            break
        case 25: // DECTCEM - Cursor visible
            modes.showCursor = enabled
        case 40: // Allow 132 mode
            modes.allow132Mode = enabled
        case 45: // Reverse wrap around
            modes.reverseWrapAround = enabled
        case 47: // Alternate screen buffer
            if enabled {
                buffer.switchToAlternateBuffer()
            } else {
                buffer.switchToNormalBuffer()
            }
            modes.alternateScreenBuffer = enabled
        case 69: // DECLRMM - Left Right Margin Mode
            modes.leftRightMarginMode = enabled
            if !enabled {
                buffer.scrollLeft = 0
                buffer.scrollRight = buffer.width - 1
                buffer.useLeftRightMargin = false
            }
        case 1000: // Normal mouse tracking
            modes.mouseTrackingNormal = enabled
        case 1001: // Highlight mouse tracking
            modes.mouseTrackingHighlight = enabled
        case 1002: // Button event mouse tracking
            modes.mouseTrackingButton = enabled
        case 1003: // Any event mouse tracking
            modes.mouseTrackingAny = enabled
        case 1004: // Focus event
            modes.mouseFocusEvent = enabled
        case 1005: // UTF-8 mouse encoding
            modes.mouseExtendedUTF8 = enabled
        case 1006: // SGR mouse encoding
            modes.mouseExtendedSGR = enabled
        case 1015: // URXVT mouse encoding
            modes.mouseExtendedURXVT = enabled
        case 1016: // SGR-Pixels mouse encoding
            modes.mouseExtendedSGRPixels = enabled
        case 1047: // Alt screen buffer
            if enabled {
                buffer.switchToAlternateBuffer()
            } else {
                buffer.switchToNormalBuffer()
            }
            modes.altScreenBuffer = enabled
        case 1048: // Save/restore cursor
            if enabled {
                buffer.saveCursor()
            } else {
                buffer.restoreCursor()
            }
            modes.saveCursorAltBuffer = enabled
        case 1049: // Alt screen buffer + save cursor + clear
            if enabled {
                buffer.saveCursor()
                buffer.switchToAlternateBuffer()
                buffer.eraseInDisplay(2)
                buffer.moveCursorTo(x: 0, y: 0)
            } else {
                buffer.switchToNormalBuffer()
                buffer.restoreCursor()
            }
            modes.altScreenBufferClear = enabled
        case 2004: // Bracketed paste mode
            modes.bracketedPaste = enabled
        default:
            break
        }
        delegate?.terminalDidChangeMode(modes)
    }

    // MARK: - Standard Mode Set/Reset

    private func setStandardMode(_ mode: Int, enabled: Bool) {
        switch mode {
        case 4: // IRM - Insert/Replace Mode
            modes.insertMode = enabled
        case 12: // SRM - Send/Receive Mode
            modes.sendReceiveMode = enabled
        case 20: // LNM - Line Feed/New Line Mode
            modes.newLineMode = enabled
        default:
            break
        }
    }

    // MARK: - Device Attributes

    private func sendPrimaryDA() {
        // VT220 response
        switch terminalID {
        case .vt100, .vt100j:
            sendResponse("\u{1B}[?1;2c")
        case .vt101:
            sendResponse("\u{1B}[?1;0c")
        case .vt102, .vt102j:
            sendResponse("\u{1B}[?6c")
        case .vt220, .vt220j:
            sendResponse("\u{1B}[?62;1;2;6;7;8;9c")
        case .vt320, .vt382:
            sendResponse("\u{1B}[?63;1;2;6;7;8;9c")
        case .vt420:
            sendResponse("\u{1B}[?64;1;2;6;7;8;9;15;18;21c")
        case .vt520, .vt525:
            sendResponse("\u{1B}[?65;1;2;6;7;8;9;15;18;21c")
        default:
            sendResponse("\u{1B}[?62;1;2;6;7;8;9c")
        }
    }

    private func sendSecondaryDA() {
        // xterm-compatible response: VT220, firmware version, 0
        sendResponse("\u{1B}[>1;5700;0c")
    }

    private func sendTertiaryDA() {
        sendResponse("\u{1B}P!|00000000\u{1B}\\")
    }

    // MARK: - Device Status Reports

    private func processDeviceStatusReport(_ params: CSIParams) {
        let n = params.param(0)

        if params.privateMarker == 0x3F { // ?
            // DEC-specific DSR
            switch n {
            case 6: // DECXCPR - Extended Cursor Position
                sendResponse("\u{1B}[?\(buffer.cursorY + 1);\(buffer.cursorX + 1)R")
            case 15: // Printer status
                sendResponse("\u{1B}[?13n") // No printer
            case 25: // UDK status
                sendResponse("\u{1B}[?20n") // UDKs unlocked
            case 26: // Keyboard status
                sendResponse("\u{1B}[?27;1;0;0n") // North American
            case 53, 55: // Locator status
                sendResponse("\u{1B}[?53n") // No locator
            case 62: // Macro space report
                sendResponse("\u{1B}[0*{")
            case 63: // Memory checksum
                sendResponse("\u{1B}P0!~0000\u{1B}\\")
            case 75: // Data integrity
                sendResponse("\u{1B}[?70n") // Ready, no errors
            case 85: // Multi-session status
                sendResponse("\u{1B}[?83n") // Not ready
            default:
                break
            }
        } else {
            // Standard DSR
            switch n {
            case 5: // Operating status
                sendResponse("\u{1B}[0n") // OK
            case 6: // CPR - Cursor Position Report
                sendResponse("\u{1B}[\(buffer.cursorY + 1);\(buffer.cursorX + 1)R")
            default:
                break
            }
        }
    }
}

// MARK: - VTParserDelegate Implementation

extension TerminalEmulator: VTParserDelegate {

    func parserDidReceivePrintable(_ text: String) {
        for char in text {
            if modes.insertMode {
                buffer.insertCharacters(1)
            }
            let scalar = char.unicodeScalars.first ?? UnicodeScalar(0x20)
            buffer.putChar(char, scalar: scalar)
        }
    }

    func parserDidReceiveControl(_ char: UInt8) {
        // Handled by individual control handlers
    }

    func parserDidRequestBell() {
        delegate?.terminalDidRing()
    }

    func parserDidRequestBackspace() {
        buffer.backspace()
    }

    func parserDidRequestTab() {
        buffer.tab()
    }

    // Port of vtterm.c ProcessLF()
    func parserDidRequestLineFeed() {
        switch settings.crReceive {
        case .lf:
            // CRReceive=LF: LF received → treat as CR+LF
            buffer.carriageReturn()
            buffer.lineFeed()
        case .auto_:
            // AUTO mode: CR or LF generates CR+LF; consecutive CR+LF pair is deduplicated
            if prevControlChar != 0x0D || !prevCRorLFGeneratedCRLF {
                buffer.carriageReturn()
                buffer.lineFeed()
                prevCRorLFGeneratedCRLF = true
            } else {
                prevCRorLFGeneratedCRLF = false
            }
        default:
            // CRReceive=CR or CRLF: standard VT100 behavior
            buffer.lineFeed()
            if modes.newLineMode {
                buffer.carriageReturn()
            }
        }
        prevControlChar = 0x0A
    }

    // Port of vtterm.c ProcessCR()
    func parserDidRequestCarriageReturn() {
        switch settings.crReceive {
        case .auto_:
            // AUTO mode: CR or LF generates CR+LF; consecutive CR+LF pair is deduplicated
            if prevControlChar != 0x0A || !prevCRorLFGeneratedCRLF {
                buffer.carriageReturn()
                buffer.lineFeed()
                prevCRorLFGeneratedCRLF = true
            } else {
                prevCRorLFGeneratedCRLF = false
            }
        default:
            buffer.carriageReturn()
            if settings.crReceive == .crlf {
                // CRReceive=CRLF: CR received → add LF
                buffer.lineFeed()
            }
        }
        prevControlChar = 0x0D
    }

    func parserDidRequestShiftOut() {
        charSet.gl = 1  // Switch to G1
    }

    func parserDidRequestShiftIn() {
        charSet.gl = 0  // Switch to G0
    }

    // MARK: - ESC Sequence Handler

    func parserDidReceiveESC(intermediates: [UInt8], final: UInt8) {
        if intermediates.isEmpty {
            switch final {
            case 0x37: // ESC 7 - DECSC (Save Cursor)
                buffer.saveCursor()
            case 0x38: // ESC 8 - DECRC (Restore Cursor)
                buffer.restoreCursor()
            case 0x44: // ESC D - IND (Index/Line Feed)
                buffer.lineFeed()
            case 0x45: // ESC E - NEL (Next Line)
                buffer.carriageReturn()
                buffer.lineFeed()
            case 0x48: // ESC H - HTS (Horizontal Tab Set)
                buffer.tabStops.set(at: buffer.cursorX)
            case 0x4D: // ESC M - RI (Reverse Index)
                buffer.reverseLineFeed()
            case 0x4E: // ESC N - SS2 (Single Shift 2)
                charSet.singleShift = 2
            case 0x4F: // ESC O - SS3 (Single Shift 3)
                charSet.singleShift = 3
            case 0x5A: // ESC Z - DECID (Identify)
                sendPrimaryDA()
            case 0x63: // ESC c - RIS (Reset)
                hardReset()
            case 0x3D: // ESC = - DECKPAM (Keypad Application Mode)
                modes.applicationKeypad = true
                delegate?.terminalDidChangeMode(modes)
            case 0x3E: // ESC > - DECKPNM (Keypad Numeric Mode)
                modes.applicationKeypad = false
                delegate?.terminalDidChangeMode(modes)
            case 0x6E: // ESC n - LS2 (Locking Shift 2)
                charSet.gl = 2
            case 0x6F: // ESC o - LS3 (Locking Shift 3)
                charSet.gl = 3
            case 0x7C: // ESC | - LS3R (Locking Shift 3 Right)
                charSet.gr = 3
            case 0x7D: // ESC } - LS2R (Locking Shift 2 Right)
                charSet.gr = 2
            case 0x7E: // ESC ~ - LS1R (Locking Shift 1 Right)
                charSet.gr = 1
            default:
                break
            }
        } else if intermediates.count == 1 {
            let inter = intermediates[0]
            switch inter {
            case 0x20: // SP
                if final == 0x46 { // ESC SP F - S7C1T (7-bit C1)
                    conformanceLevel = 2
                } else if final == 0x47 { // ESC SP G - S8C1T (8-bit C1)
                    conformanceLevel = 2
                }
            case 0x23: // #
                switch final {
                case 0x33: break // DECDHL - Double Height Line (top)
                case 0x34: break // DECDHL - Double Height Line (bottom)
                case 0x35: break // DECSWL - Single Width Line
                case 0x36: break // DECDWL - Double Width Line
                case 0x38: // DECALN - Screen Alignment Pattern
                    for y in 0..<buffer.height {
                        for x in 0..<buffer.width {
                            buffer.moveCursorTo(x: x, y: y)
                            buffer.putChar("E")
                        }
                    }
                    buffer.moveCursorTo(x: 0, y: 0)
                default: break
                }
            case 0x28: // ( - G0 designator
                charSet.g[0] = decodeCharSet(final)
            case 0x29: // ) - G1 designator
                charSet.g[1] = decodeCharSet(final)
            case 0x2A: // * - G2 designator
                charSet.g[2] = decodeCharSet(final)
            case 0x2B: // + - G3 designator
                charSet.g[3] = decodeCharSet(final)
            default:
                break
            }
        }
    }

    private func decodeCharSet(_ final: UInt8) -> CharSetState.CharSet {
        switch final {
        case 0x30: return .decSpecialGraphics  // 0
        case 0x41: return .ukNational          // A
        case 0x42: return .ascii               // B
        case 0x3E: return .decTechnical        // >
        default: return .ascii
        }
    }

    // MARK: - CSI Sequence Handler

    func parserDidReceiveCSI(params: CSIParams, final: UInt8) {
        if let marker = params.privateMarker {
            handlePrivateCSI(marker: marker, params: params, final: final)
            return
        }

        if !params.intermediates.isEmpty {
            handleCSIWithIntermediate(params: params, final: final)
            return
        }

        switch final {
        case 0x40: // @ - ICH (Insert Characters)
            buffer.insertCharacters(params.param(0, default: 1))

        case 0x41: // A - CUU (Cursor Up)
            buffer.moveCursorUp(params.param(0, default: 1))

        case 0x42: // B - CUD (Cursor Down)
            buffer.moveCursorDown(params.param(0, default: 1))

        case 0x43: // C - CUF (Cursor Forward)
            buffer.moveCursorForward(params.param(0, default: 1))

        case 0x44: // D - CUB (Cursor Backward)
            buffer.moveCursorBackward(params.param(0, default: 1))

        case 0x45: // E - CNL (Cursor Next Line)
            buffer.moveCursorDown(params.param(0, default: 1))
            buffer.carriageReturn()

        case 0x46: // F - CPL (Cursor Previous Line)
            buffer.moveCursorUp(params.param(0, default: 1))
            buffer.carriageReturn()

        case 0x47: // G - CHA (Cursor Horizontal Absolute)
            buffer.moveCursorTo(x: params.param(0, default: 1) - 1, y: buffer.cursorY)

        case 0x48: // H - CUP (Cursor Position)
            let row = params.param(0, default: 1) - 1
            let col = params.param(1, default: 1) - 1
            buffer.moveCursorTo(x: col, y: row)

        case 0x49: // I - CHT (Cursor Horizontal Tab)
            let n = params.param(0, default: 1)
            for _ in 0..<n { buffer.tab() }

        case 0x4A: // J - ED (Erase in Display)
            buffer.eraseInDisplay(params.param(0))

        case 0x4B: // K - EL (Erase in Line)
            buffer.eraseInLine(params.param(0))

        case 0x4C: // L - IL (Insert Lines)
            buffer.insertLines(params.param(0, default: 1))

        case 0x4D: // M - DL (Delete Lines)
            buffer.deleteLines(params.param(0, default: 1))

        case 0x50: // P - DCH (Delete Characters)
            buffer.deleteCharacters(params.param(0, default: 1))

        case 0x53: // S - SU (Scroll Up)
            buffer.scrollUp(params.param(0, default: 1))

        case 0x54: // T - SD (Scroll Down)
            buffer.scrollDown(params.param(0, default: 1))

        case 0x58: // X - ECH (Erase Characters)
            buffer.eraseCharacters(params.param(0, default: 1))

        case 0x5A: // Z - CBT (Cursor Backward Tabulation)
            let n = params.param(0, default: 1)
            for _ in 0..<n { buffer.backTab() }

        case 0x60: // ` - HPA (Horizontal Position Absolute)
            buffer.moveCursorTo(x: params.param(0, default: 1) - 1, y: buffer.cursorY)

        case 0x61: // a - HPR (Horizontal Position Relative)
            buffer.moveCursorForward(params.param(0, default: 1))

        case 0x62: // b - REP (Repeat)
            // Repeat last character
            break

        case 0x63: // c - DA (Device Attributes)
            if params.param(0) == 0 {
                sendPrimaryDA()
            }

        case 0x64: // d - VPA (Vertical Position Absolute)
            buffer.moveCursorTo(x: buffer.cursorX, y: params.param(0, default: 1) - 1)

        case 0x65: // e - VPR (Vertical Position Relative)
            buffer.moveCursorDown(params.param(0, default: 1))

        case 0x66: // f - HVP (Horizontal Vertical Position)
            let row = params.param(0, default: 1) - 1
            let col = params.param(1, default: 1) - 1
            buffer.moveCursorTo(x: col, y: row)

        case 0x67: // g - TBC (Tab Clear)
            let n = params.param(0)
            if n == 0 {
                buffer.tabStops.clear(at: buffer.cursorX)
            } else if n == 3 {
                buffer.tabStops.clearAll()
            }

        case 0x68: // h - SM (Set Mode)
            for p in params.params {
                setStandardMode(p, enabled: true)
            }
            if params.params.isEmpty {
                setStandardMode(params.param(0), enabled: true)
            }

        case 0x6C: // l - RM (Reset Mode)
            for p in params.params {
                setStandardMode(p, enabled: false)
            }
            if params.params.isEmpty {
                setStandardMode(params.param(0), enabled: false)
            }

        case 0x6D: // m - SGR (Select Graphic Rendition)
            processSGR(params)

        case 0x6E: // n - DSR (Device Status Report)
            processDeviceStatusReport(params)

        case 0x70: // p - various
            break

        case 0x71: // q - DECSCA (Select Character Protection Attribute)
            // or DECLL (Load LEDs)
            break

        case 0x72: // r - DECSTBM (Set Top and Bottom Margins)
            let top = params.param(0, default: 1) - 1
            let bottom = params.param(1, default: buffer.height) - 1
            buffer.setScrollRegion(top: top, bottom: bottom)

        case 0x73: // s - DECSLRM or SCOSC
            if modes.leftRightMarginMode && params.count >= 2 {
                // DECSLRM - Set Left and Right Margins
                let left = params.param(0, default: 1) - 1
                let right = params.param(1, default: buffer.width) - 1
                buffer.setLeftRightMargin(left: left, right: right)
            } else {
                // SCOSC - Save Cursor Position
                buffer.saveCursor()
            }

        case 0x74: // t - Window operations (xterm)
            processWindowOps(params)

        case 0x75: // u - SCORC (Restore Cursor Position)
            buffer.restoreCursor()

        case 0x78: // x - DECREQTPARM
            let n = params.param(0)
            if n == 0 || n == 1 {
                sendResponse("\u{1B}[\(n + 2);1;1;120;120;1;0x")
            }

        default:
            break
        }
    }

    // MARK: - Private CSI (? prefix)

    private func handlePrivateCSI(marker: UInt8, params: CSIParams, final: UInt8) {
        switch marker {
        case 0x3F: // ?
            switch final {
            case 0x68: // h - DECSET
                for p in params.params {
                    setDecPrivateMode(p, enabled: true)
                }
                if params.params.isEmpty {
                    setDecPrivateMode(params.param(0), enabled: true)
                }

            case 0x6C: // l - DECRST
                for p in params.params {
                    setDecPrivateMode(p, enabled: false)
                }
                if params.params.isEmpty {
                    setDecPrivateMode(params.param(0), enabled: false)
                }

            case 0x6E: // n - DECDSR
                processDeviceStatusReport(params)

            case 0x73: // s - Save DEC Private Mode
                break

            case 0x72: // r - Restore DEC Private Mode
                break

            case 0x63: // c - DA (Secondary/Tertiary)
                if params.param(0) == 0 {
                    sendPrimaryDA()
                }

            default:
                break
            }

        case 0x3E: // >
            switch final {
            case 0x63: // c - Secondary DA
                sendSecondaryDA()
            case 0x6D: // m - xterm modifyOtherKeys
                break
            default:
                break
            }

        case 0x3D: // =
            switch final {
            case 0x63: // c - Tertiary DA
                sendTertiaryDA()
            default:
                break
            }

        case 0x21: // !
            if final == 0x70 { // CSI ! p - DECSTR (Soft Reset)
                softReset()
            }

        default:
            break
        }
    }

    // MARK: - CSI with Intermediate Bytes

    private func handleCSIWithIntermediate(params: CSIParams, final: UInt8) {
        guard let inter = params.intermediates.first else { return }

        switch inter {
        case 0x20: // SP
            switch final {
            case 0x71: // q - DECSCUSR (Set Cursor Style)
                let style = params.param(0, default: 1)
                switch style {
                case 0, 1: settings.cursorShape = .block; settings.cursorBlink = true
                case 2: settings.cursorShape = .block; settings.cursorBlink = false
                case 3: settings.cursorShape = .horizontal; settings.cursorBlink = true
                case 4: settings.cursorShape = .horizontal; settings.cursorBlink = false
                case 5: settings.cursorShape = .vertical; settings.cursorBlink = true
                case 6: settings.cursorShape = .vertical; settings.cursorBlink = false
                default: break
                }
            default: break
            }
        case 0x22: // "
            switch final {
            case 0x70: // p - DECSCL (Set Conformance Level)
                break
            case 0x71: // q - DECSCA
                protectedMode = params.param(0) == 1
            default: break
            }
        case 0x27: // '
            switch final {
            case 0x7D: // } - DECIC (Insert Columns)
                buffer.scrollRight(params.param(0, default: 1))
            case 0x7E: // ~ - DECDC (Delete Columns)
                buffer.scrollLeft(params.param(0, default: 1))
            default: break
            }
        case 0x2A: // *
            break
        case 0x24: // $
            break
        default:
            break
        }
    }

    // MARK: - Window Operations (CSI t)

    private func processWindowOps(_ params: CSIParams) {
        let op = params.param(0)
        switch op {
        case 8: // Resize text area
            let rows = params.param(1)
            let cols = params.param(2)
            if rows > 0 && cols > 0 {
                delegate?.terminalDidRequestResize(width: cols, height: rows)
            }
        case 11: // Report window state
            sendResponse("\u{1B}[1t") // Not iconified
        case 13: // Report window position
            sendResponse("\u{1B}[3;0;0t")
        case 14: // Report text area size in pixels
            sendResponse("\u{1B}[4;0;0t")
        case 18: // Report text area size in chars
            sendResponse("\u{1B}[8;\(buffer.height);\(buffer.width)t")
        case 19: // Report screen size in chars
            sendResponse("\u{1B}[9;\(buffer.height);\(buffer.width)t")
        case 20: // Report icon title
            sendResponse("\u{1B}]L\(iconTitle)\u{1B}\\")
        case 21: // Report window title
            sendResponse("\u{1B}]l\(windowTitle)\u{1B}\\")
        case 22: // Push title
            break
        case 23: // Pop title
            break
        default:
            break
        }
    }

    // MARK: - OSC Sequence Handler

    func parserDidReceiveOSC(command: Int, data: String) {
        switch command {
        case 0: // Change icon name and window title
            windowTitle = data
            iconTitle = data
            delegate?.terminalDidChangeTitle(data)
            delegate?.terminalDidChangeIconTitle(data)
        case 1: // Change icon name
            iconTitle = data
            delegate?.terminalDidChangeIconTitle(data)
        case 2: // Change window title
            windowTitle = data
            delegate?.terminalDidChangeTitle(data)
        case 4: // Change/query color
            processOSCColor(data)
        case 7: // Set working directory (iTerm2/macOS Terminal)
            break
        case 8: // Hyperlinks
            break
        case 10: // Change foreground color
            processOSCDefaultColor(10, data: data)
        case 11: // Change background color
            processOSCDefaultColor(11, data: data)
        case 12: // Change cursor color
            processOSCDefaultColor(12, data: data)
        case 52: // Clipboard operations
            processOSCClipboard(data)
        case 104: // Reset color
            break
        case 110: // Reset foreground color
            break
        case 111: // Reset background color
            break
        case 112: // Reset cursor color
            break
        case 133: // Shell integration (FinalTerm/iTerm2)
            break
        default:
            break
        }
    }

    private func processOSCColor(_ data: String) {
        // OSC 4 ; <index> ; <color> ST
        // Parse and apply palette color changes
    }

    private func processOSCDefaultColor(_ type: Int, data: String) {
        if data == "?" {
            // Query color
            switch type {
            case 10:
                let c = settings.colorTheme.foreground
                sendResponse("\u{1B}]10;rgb:\(hexColor(c))\u{07}")
            case 11:
                let c = settings.colorTheme.background
                sendResponse("\u{1B}]11;rgb:\(hexColor(c))\u{07}")
            case 12:
                let c = settings.colorTheme.cursorColor
                sendResponse("\u{1B}]12;rgb:\(hexColor(c))\u{07}")
            default:
                break
            }
        }
    }

    private func hexColor(_ c: TerminalColor) -> String {
        return String(format: "%02x%02x/%02x%02x/%02x%02x", c.r, c.r, c.g, c.g, c.b, c.b)
    }

    private func processOSCClipboard(_ data: String) {
        let parts = data.split(separator: ";", maxSplits: 1)
        guard parts.count >= 1 else { return }
        if parts.count == 1 || parts[1] == "?" {
            // Query clipboard - send content
            delegate?.terminalDidRequestCopy("")
        } else {
            // Set clipboard from base64
            let base64 = String(parts[1])
            if let decoded = Data(base64Encoded: base64),
               let text = String(data: decoded, encoding: .utf8) {
                delegate?.terminalDidRequestCopy(text)
            }
        }
    }

    // MARK: - DCS Sequence Handler

    func parserDidReceiveDCS(params: CSIParams, intermediates: [UInt8], data: String) {
        // Handle Device Control String sequences
        // DECRQSS, DECUDK, etc.
        if let inter = intermediates.first {
            switch inter {
            case 0x24: // $
                // DECRQSS - Request Selection or Setting
                processStatusStringRequest(data)
            default:
                break
            }
        }
    }

    private func processStatusStringRequest(_ data: String) {
        // DECRQSS responses
        switch data {
        case "r": // DECSTBM
            sendResponse("\u{1B}P1$r\(buffer.scrollTop + 1);\(buffer.scrollBottom + 1)r\u{1B}\\")
        case "m": // SGR
            sendResponse("\u{1B}P1$r0m\u{1B}\\")
        case " q": // DECSCUSR
            let style: Int
            switch settings.cursorShape {
            case .block: style = settings.cursorBlink ? 1 : 2
            case .horizontal: style = settings.cursorBlink ? 3 : 4
            case .vertical: style = settings.cursorBlink ? 5 : 6
            }
            sendResponse("\u{1B}P1$r\(style) q\u{1B}\\")
        default:
            sendResponse("\u{1B}P0$r\u{1B}\\") // Invalid request
        }
    }
}
