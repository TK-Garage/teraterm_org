/*
 * Tests for VT Parser
 */

import XCTest
@testable import TeraTermMac

final class VTParserTests: XCTestCase {

    var parser: VTParser!
    var delegate: TestParserDelegate!

    override func setUp() {
        super.setUp()
        parser = VTParser()
        delegate = TestParserDelegate()
        parser.delegate = delegate
    }

    // MARK: - Printable Characters

    func testPrintableASCII() {
        parser.parse("Hello")
        XCTAssertEqual(delegate.printedText, "Hello")
    }

    func testPrintableUTF8() {
        parser.parse("日本語")
        XCTAssertEqual(delegate.printedText, "日本語")
    }

    // MARK: - Control Characters

    func testBell() {
        parser.parse([0x07])
        XCTAssertTrue(delegate.bellReceived)
    }

    func testBackspace() {
        parser.parse([0x08])
        XCTAssertTrue(delegate.backspaceReceived)
    }

    func testTab() {
        parser.parse([0x09])
        XCTAssertTrue(delegate.tabReceived)
    }

    func testLineFeed() {
        parser.parse([0x0A])
        XCTAssertTrue(delegate.lineFeedReceived)
    }

    func testCarriageReturn() {
        parser.parse([0x0D])
        XCTAssertTrue(delegate.crReceived)
    }

    // MARK: - ESC Sequences

    func testESCSaveCursor() {
        parser.parse("\u{1B}7")
        XCTAssertEqual(delegate.lastESCFinal, 0x37) // '7'
    }

    func testESCRestoreCursor() {
        parser.parse("\u{1B}8")
        XCTAssertEqual(delegate.lastESCFinal, 0x38) // '8'
    }

    func testESCIndex() {
        parser.parse("\u{1B}D")
        XCTAssertEqual(delegate.lastESCFinal, 0x44) // 'D'
    }

    func testESCReverseIndex() {
        parser.parse("\u{1B}M")
        XCTAssertEqual(delegate.lastESCFinal, 0x4D) // 'M'
    }

    // MARK: - CSI Sequences

    func testCSICursorUp() {
        parser.parse("\u{1B}[5A")
        XCTAssertEqual(delegate.lastCSIFinal, 0x41) // 'A'
        XCTAssertEqual(delegate.lastCSIParams?.params, [5])
    }

    func testCSICursorPosition() {
        parser.parse("\u{1B}[10;20H")
        XCTAssertEqual(delegate.lastCSIFinal, 0x48) // 'H'
        XCTAssertEqual(delegate.lastCSIParams?.params, [10, 20])
    }

    func testCSIEraseDisplay() {
        parser.parse("\u{1B}[2J")
        XCTAssertEqual(delegate.lastCSIFinal, 0x4A) // 'J'
        XCTAssertEqual(delegate.lastCSIParams?.params, [2])
    }

    func testCSISGR() {
        parser.parse("\u{1B}[1;31;42m")
        XCTAssertEqual(delegate.lastCSIFinal, 0x6D) // 'm'
        XCTAssertEqual(delegate.lastCSIParams?.params, [1, 31, 42])
    }

    func testCSIPrivateMode() {
        parser.parse("\u{1B}[?25h")
        XCTAssertEqual(delegate.lastCSIFinal, 0x68) // 'h'
        XCTAssertEqual(delegate.lastCSIParams?.privateMarker, 0x3F) // '?'
        XCTAssertEqual(delegate.lastCSIParams?.params, [25])
    }

    func testCSIDefaultParams() {
        parser.parse("\u{1B}[H") // Default params for CUP
        XCTAssertEqual(delegate.lastCSIFinal, 0x48) // 'H'
        XCTAssertTrue(delegate.lastCSIParams?.params.isEmpty ?? true)
    }

    // MARK: - OSC Sequences

    func testOSCSetTitle() {
        parser.parse("\u{1B}]0;My Title\u{07}")
        XCTAssertEqual(delegate.lastOSCCommand, 0)
        XCTAssertEqual(delegate.lastOSCData, "My Title")
    }

    func testOSCSetTitleST() {
        parser.parse("\u{1B}]2;Window Title\u{1B}\\")
        XCTAssertEqual(delegate.lastOSCCommand, 2)
        XCTAssertEqual(delegate.lastOSCData, "Window Title")
    }

    // MARK: - Mixed Sequences

    func testMixedContent() {
        parser.parse("Hello\u{1B}[31mWorld\u{1B}[0m!")
        // Should receive: "Hello", CSI 31m, "World", CSI 0m, "!"
        XCTAssertTrue(delegate.printedText.contains("Hello"))
        XCTAssertTrue(delegate.printedText.contains("World"))
        XCTAssertTrue(delegate.printedText.contains("!"))
    }

    // MARK: - Reset

    func testParserReset() {
        parser.parse("\u{1B}[") // Start CSI sequence
        parser.reset()
        parser.parse("A") // Should be treated as printable after reset
        XCTAssertTrue(delegate.printedText.contains("A"))
    }
}

// MARK: - Test Delegate

class TestParserDelegate: VTParserDelegate {
    var printedText = ""
    var bellReceived = false
    var backspaceReceived = false
    var tabReceived = false
    var lineFeedReceived = false
    var crReceived = false
    var lastESCFinal: UInt8?
    var lastESCIntermediates: [UInt8]?
    var lastCSIFinal: UInt8?
    var lastCSIParams: CSIParams?
    var lastOSCCommand: Int?
    var lastOSCData: String?

    func parserDidReceivePrintable(_ text: String) {
        printedText += text
    }

    func parserDidReceiveControl(_ char: UInt8) {}

    func parserDidReceiveCSI(params: CSIParams, final: UInt8) {
        lastCSIParams = params
        lastCSIFinal = final
    }

    func parserDidReceiveESC(intermediates: [UInt8], final: UInt8) {
        lastESCIntermediates = intermediates
        lastESCFinal = final
    }

    func parserDidReceiveOSC(command: Int, data: String) {
        lastOSCCommand = command
        lastOSCData = data
    }

    func parserDidReceiveDCS(params: CSIParams, intermediates: [UInt8], data: String) {}
    func parserDidRequestBell() { bellReceived = true }
    func parserDidRequestBackspace() { backspaceReceived = true }
    func parserDidRequestTab() { tabReceived = true }
    func parserDidRequestLineFeed() { lineFeedReceived = true }
    func parserDidRequestCarriageReturn() { crReceived = true }
    func parserDidRequestShiftOut() {}
    func parserDidRequestShiftIn() {}
}

// MARK: - Terminal Buffer Tests

final class TerminalBufferTests: XCTestCase {

    var buffer: TerminalBuffer!

    override func setUp() {
        super.setUp()
        buffer = TerminalBuffer(width: 80, height: 24)
    }

    func testInitialState() {
        XCTAssertEqual(buffer.width, 80)
        XCTAssertEqual(buffer.height, 24)
        XCTAssertEqual(buffer.cursorX, 0)
        XCTAssertEqual(buffer.cursorY, 0)
    }

    func testPutChar() {
        buffer.putChar("A")
        XCTAssertEqual(buffer.cursorX, 1)
        let ch = buffer.character(at: 0, y: 0)
        XCTAssertEqual(ch.character, "A")
    }

    func testCursorMovement() {
        buffer.moveCursorTo(x: 10, y: 5)
        XCTAssertEqual(buffer.cursorX, 10)
        XCTAssertEqual(buffer.cursorY, 5)

        buffer.moveCursorUp(2)
        XCTAssertEqual(buffer.cursorY, 3)

        buffer.moveCursorDown(1)
        XCTAssertEqual(buffer.cursorY, 4)

        buffer.moveCursorForward(5)
        XCTAssertEqual(buffer.cursorX, 15)

        buffer.moveCursorBackward(3)
        XCTAssertEqual(buffer.cursorX, 12)
    }

    func testLineFeed() {
        buffer.moveCursorTo(x: 0, y: 0)
        buffer.lineFeed()
        XCTAssertEqual(buffer.cursorY, 1)
    }

    func testCarriageReturn() {
        buffer.moveCursorTo(x: 10, y: 5)
        buffer.carriageReturn()
        XCTAssertEqual(buffer.cursorX, 0)
        XCTAssertEqual(buffer.cursorY, 5)
    }

    func testEraseInDisplay() {
        buffer.putChar("X")
        buffer.eraseInDisplay(2)
        let ch = buffer.character(at: 0, y: 0)
        XCTAssertEqual(ch.character, " ")
    }

    func testEraseInLine() {
        for c in "Hello, World!" {
            buffer.putChar(c)
        }
        buffer.moveCursorTo(x: 5, y: 0)
        buffer.eraseInLine(0) // Erase from cursor to end
        let ch5 = buffer.character(at: 5, y: 0)
        XCTAssertEqual(ch5.character, " ")
        let ch4 = buffer.character(at: 4, y: 0)
        XCTAssertEqual(ch4.character, "o")
    }

    func testScrollRegion() {
        buffer.setScrollRegion(top: 5, bottom: 20)
        XCTAssertEqual(buffer.scrollTop, 5)
        XCTAssertEqual(buffer.scrollBottom, 20)
    }

    func testSaveCursor() {
        buffer.moveCursorTo(x: 10, y: 5)
        buffer.saveCursor()
        buffer.moveCursorTo(x: 0, y: 0)
        buffer.restoreCursor()
        XCTAssertEqual(buffer.cursorX, 10)
        XCTAssertEqual(buffer.cursorY, 5)
    }

    func testResize() {
        buffer.resize(newWidth: 132, newHeight: 43)
        XCTAssertEqual(buffer.width, 132)
        XCTAssertEqual(buffer.height, 43)
    }

    func testAlternateBuffer() {
        buffer.putChar("X")
        buffer.switchToAlternateBuffer()
        XCTAssertTrue(buffer.isAlternateBuffer)
        let ch = buffer.character(at: 0, y: 0)
        XCTAssertEqual(ch.character, " ") // Alt buffer should be clean

        buffer.switchToNormalBuffer()
        XCTAssertFalse(buffer.isAlternateBuffer)
    }

    func testInsertDelete() {
        for c in "ABCD" {
            buffer.putChar(c)
        }
        buffer.moveCursorTo(x: 1, y: 0)
        buffer.insertCharacters(1)
        let ch = buffer.character(at: 1, y: 0)
        XCTAssertEqual(ch.character, " ")
        let chB = buffer.character(at: 2, y: 0)
        XCTAssertEqual(chB.character, "B")
    }
}

// MARK: - Terminal Emulator Tests

final class TerminalEmulatorTests: XCTestCase {

    var emulator: TerminalEmulator!
    var delegate: TestEmulatorDelegate!

    override func setUp() {
        super.setUp()
        let settings = TerminalSettings()
        settings.terminalWidth = 80
        settings.terminalHeight = 24
        emulator = TerminalEmulator(settings: settings)
        delegate = TestEmulatorDelegate()
        emulator.delegate = delegate
    }

    func testProcessText() {
        emulator.processString("Hello")
        XCTAssertEqual(emulator.buffer.cursorX, 5)
    }

    func testCursorPositioning() {
        emulator.processString("\u{1B}[10;20H")
        XCTAssertEqual(emulator.buffer.cursorY, 9)  // 1-based to 0-based
        XCTAssertEqual(emulator.buffer.cursorX, 19)
    }

    func testSGRBold() {
        emulator.processString("\u{1B}[1m")
        XCTAssertTrue(emulator.buffer.currentAttributes.contains(.bold))
    }

    func testSGRReset() {
        emulator.processString("\u{1B}[1;4m")
        emulator.processString("\u{1B}[0m")
        XCTAssertTrue(emulator.buffer.currentAttributes.isEmpty)
    }

    func testDECSET_DECRST() {
        // Show cursor
        emulator.processString("\u{1B}[?25h")
        XCTAssertTrue(emulator.modes.showCursor)

        // Hide cursor
        emulator.processString("\u{1B}[?25l")
        XCTAssertFalse(emulator.modes.showCursor)
    }

    func testAlternateScreenBuffer() {
        emulator.processString("Normal")
        emulator.processString("\u{1B}[?1049h") // Switch to alt
        XCTAssertTrue(emulator.buffer.isAlternateBuffer)

        emulator.processString("\u{1B}[?1049l") // Switch back
        XCTAssertFalse(emulator.buffer.isAlternateBuffer)
    }

    func testBracketedPasteMode() {
        emulator.processString("\u{1B}[?2004h")
        XCTAssertTrue(emulator.modes.bracketedPaste)

        emulator.processString("\u{1B}[?2004l")
        XCTAssertFalse(emulator.modes.bracketedPaste)
    }

    func testOSCTitle() {
        emulator.processString("\u{1B}]0;Test Title\u{07}")
        XCTAssertEqual(delegate.lastTitle, "Test Title")
    }

    func testSoftReset() {
        emulator.processString("\u{1B}[1m") // Bold
        emulator.processString("\u{1B}[!p")  // Soft reset
        XCTAssertTrue(emulator.buffer.currentAttributes.isEmpty)
    }

    func testHardReset() {
        emulator.processString("Some text\u{1B}[1m")
        emulator.processString("\u{1B}c") // Hard reset
        XCTAssertEqual(emulator.buffer.cursorX, 0)
        XCTAssertEqual(emulator.buffer.cursorY, 0)
    }
}

class TestEmulatorDelegate: TerminalEmulatorDelegate {
    var lastTitle: String?
    var lastIconTitle: String?
    var displayUpdated = false
    var lastResponse: Data?

    func terminalDidUpdateDisplay() { displayUpdated = true }
    func terminalDidChangeCursorPosition(x: Int, y: Int) {}
    func terminalDidChangeTitle(_ title: String) { lastTitle = title }
    func terminalDidChangeIconTitle(_ title: String) { lastIconTitle = title }
    func terminalDidRing() {}
    func terminalDidRequestResize(width: Int, height: Int) {}
    func terminalDidRequestResponse(_ data: Data) { lastResponse = data }
    func terminalDidChangeMode(_ modes: TerminalModes) {}
    func terminalDidRequestPaste() {}
    func terminalDidRequestCopy(_ text: String) {}
    func terminalDidChangeColors() {}
}

// MARK: - Encoding Converter Tests

final class EncodingConverterTests: XCTestCase {

    func testUnicodeWidth() {
        XCTAssertEqual(EncodingConverter.unicodeWidth(UnicodeScalar(0x41)!), 1) // 'A'
        XCTAssertEqual(EncodingConverter.unicodeWidth(UnicodeScalar(0x4E00)!), 2) // CJK
        XCTAssertEqual(EncodingConverter.unicodeWidth(UnicodeScalar(0x0300)!), 0) // Combining
    }

    func testDECSpecialGraphics() {
        XCTAssertEqual(EncodingConverter.decSpecialGraphics("j"), "\u{2518}") // Lower right corner
        XCTAssertEqual(EncodingConverter.decSpecialGraphics("k"), "\u{2510}") // Upper right corner
        XCTAssertEqual(EncodingConverter.decSpecialGraphics("l"), "\u{250C}") // Upper left corner
        XCTAssertEqual(EncodingConverter.decSpecialGraphics("q"), "\u{2500}") // Horizontal line
        XCTAssertEqual(EncodingConverter.decSpecialGraphics("x"), "\u{2502}") // Vertical line
    }

    func testIsCombining() {
        XCTAssertTrue(EncodingConverter.isCombining(UnicodeScalar(0x0301)!))   // Combining acute
        XCTAssertFalse(EncodingConverter.isCombining(UnicodeScalar(0x41)!))     // 'A'
    }
}

// MARK: - Telnet Protocol Tests

final class TelnetProtocolTests: XCTestCase {

    var telnet: TelnetProtocol!

    override func setUp() {
        super.setUp()
        telnet = TelnetProtocol()
    }

    func testPassthroughData() {
        let input = Data("Hello".utf8)
        let output = telnet.processIncoming(input)
        XCTAssertEqual(output, input)
    }

    func testEscapedIAC() {
        let input = Data([0xFF, 0xFF]) // IAC IAC = literal 0xFF
        let output = telnet.processIncoming(input)
        XCTAssertEqual(output, Data([0xFF]))
    }

    func testNOP() {
        let input = Data([0xFF, 0xF1]) // IAC NOP
        let output = telnet.processIncoming(input)
        XCTAssertTrue(output.isEmpty)
    }

    func testMixedDataAndCommands() {
        let input = Data([0x48, 0x69, 0xFF, 0xF1, 0x21]) // "Hi" + IAC NOP + "!"
        let output = telnet.processIncoming(input)
        XCTAssertEqual(output, Data([0x48, 0x69, 0x21])) // "Hi!"
    }
}
