/*
 * Tests for TerminalView color resolution logic
 * Verifies the port of GetDrawAttr() from vtdisp.c
 */

#if canImport(AppKit)
import XCTest
@testable import TeraTermMac

final class ColorResolutionTests: XCTestCase {

    var view: TerminalView!

    override func setUp() {
        super.setUp()
        view = TerminalView()
    }

    override func tearDown() {
        view = nil
        super.tearDown()
    }

    // MARK: - Helper

    /// Compare two NSColors by their RGB components (ignoring alpha unless specified).
    private func assertColorEqual(_ a: NSColor, _ b: NSColor, alpha: Bool = false,
                                  file: StaticString = #file, line: UInt = #line) {
        guard let ac = a.usingColorSpace(.sRGB), let bc = b.usingColorSpace(.sRGB) else {
            XCTFail("Cannot convert colors to sRGB", file: file, line: line)
            return
        }
        XCTAssertEqual(ac.redComponent,   bc.redComponent,   accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(ac.greenComponent, bc.greenComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(ac.blueComponent,  bc.blueComponent,  accuracy: 0.01, file: file, line: line)
        if alpha {
            XCTAssertEqual(ac.alphaComponent, bc.alphaComponent, accuracy: 0.01, file: file, line: line)
        }
    }

    private func makeCell(attrs: CharAttributes = [],
                          fgIndex: UInt8? = nil,
                          bgIndex: UInt8? = nil,
                          fgRGB: (UInt8, UInt8, UInt8)? = nil,
                          bgRGB: (UInt8, UInt8, UInt8)? = nil) -> BufferCharacter {
        var cell = BufferCharacter()
        cell.attributes = attrs
        if let fg = fgIndex {
            cell.color.foreground = fg
            cell.color.isFgDefault = false
        }
        if let bg = bgIndex {
            cell.color.background = bg
            cell.color.isBgDefault = false
        }
        if let (r, g, b) = fgRGB {
            cell.color.isFgRGB = true
            cell.color.isFgDefault = false
            cell.color.fgR = r; cell.color.fgG = g; cell.color.fgB = b
        }
        if let (r, g, b) = bgRGB {
            cell.color.isBgRGB = true
            cell.color.isBgDefault = false
            cell.color.bgR = r; cell.color.bgG = g; cell.color.bgB = b
        }
        return cell
    }

    private func tc(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> NSColor {
        view.nsColor(from: TerminalColor(r: r, g: g, b: b))
    }

    // MARK: - Normal Text (no attributes, default colors)

    func testNormalText_DefaultColors() {
        let cell = makeCell()
        let (fg, bg) = view.resolveColors(cell, inSelection: false)
        let expectedFG = tc(view.settings.colorTheme.foreground.r,
                            view.settings.colorTheme.foreground.g,
                            view.settings.colorTheme.foreground.b)
        let expectedBG = tc(view.settings.colorTheme.background.r,
                            view.settings.colorTheme.background.g,
                            view.settings.colorTheme.background.b)
        assertColorEqual(fg, expectedFG)
        assertColorEqual(bg, expectedBG)
    }

    // MARK: - enableANSIColor = true

    func testANSIColor_Enabled_ForegroundIndex() {
        view.settings.enableANSIColor = true
        let cell = makeCell(fgIndex: 1) // ANSI red
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        // Should use palette color index 1
        let expectedFG = tc(view.settings.colorTheme.ansiColors[1].r,
                            view.settings.colorTheme.ansiColors[1].g,
                            view.settings.colorTheme.ansiColors[1].b)
        assertColorEqual(fg, expectedFG)
    }

    // MARK: - enableANSIColor = false

    func testANSIColor_Disabled_FallsBackToTheme() {
        view.settings.enableANSIColor = false
        let cell = makeCell(fgIndex: 1) // ANSI red — should be ignored
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        // Should fall back to theme foreground (not ANSI red)
        let expectedFG = tc(view.settings.colorTheme.foreground.r,
                            view.settings.colorTheme.foreground.g,
                            view.settings.colorTheme.foreground.b)
        assertColorEqual(fg, expectedFG)
    }

    func testANSIColor_Disabled_BGFallsBackToTheme() {
        view.settings.enableANSIColor = false
        let cell = makeCell(bgIndex: 4) // ANSI blue BG — should be ignored
        let (_, bg) = view.resolveColors(cell, inSelection: false)
        let expectedBG = tc(view.settings.colorTheme.background.r,
                            view.settings.colorTheme.background.g,
                            view.settings.colorTheme.background.b)
        assertColorEqual(bg, expectedBG)
    }

    // MARK: - Attribute Colors

    func testBoldAttribute_UsesAttrColorBold() {
        view.settings.enableBoldColor = true
        view.settings.enableANSIColor = false
        let cell = makeCell(attrs: .bold)
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        assertColorEqual(fg, tc(view.settings.attrColorBold.r,
                                view.settings.attrColorBold.g,
                                view.settings.attrColorBold.b))
    }

    func testBoldAttribute_Disabled_UsesNormalColor() {
        view.settings.enableBoldColor = false
        view.settings.enableANSIColor = false
        let cell = makeCell(attrs: .bold)
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        assertColorEqual(fg, tc(view.settings.colorTheme.foreground.r,
                                view.settings.colorTheme.foreground.g,
                                view.settings.colorTheme.foreground.b))
    }

    func testBlinkAttribute_UsesAttrColorBlink() {
        view.settings.enableBlinkColor = true
        view.settings.enableANSIColor = false
        let cell = makeCell(attrs: .blink)
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        assertColorEqual(fg, tc(view.settings.attrColorBlink.r,
                                view.settings.attrColorBlink.g,
                                view.settings.attrColorBlink.b))
    }

    func testUnderlineAttribute_UsesAttrColorUnderline() {
        view.settings.enableUnderlineColor = true
        view.settings.enableANSIColor = false
        let cell = makeCell(attrs: .underline)
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        assertColorEqual(fg, tc(view.settings.attrColorUnderline.r,
                                view.settings.attrColorUnderline.g,
                                view.settings.attrColorUnderline.b))
    }

    // MARK: - Attribute Color Priority

    func testPriority_BoldOverBlink() {
        view.settings.enableBoldColor = true
        view.settings.enableBlinkColor = true
        view.settings.enableANSIColor = false
        let cell = makeCell(attrs: [.bold, .blink])
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        // Bold has higher priority than Blink
        assertColorEqual(fg, tc(view.settings.attrColorBold.r,
                                view.settings.attrColorBold.g,
                                view.settings.attrColorBold.b))
    }

    func testPriority_UnderlineOverBold() {
        view.settings.enableUnderlineColor = true
        view.settings.enableBoldColor = true
        view.settings.enableANSIColor = false
        let cell = makeCell(attrs: [.underline, .bold])
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        assertColorEqual(fg, tc(view.settings.attrColorUnderline.r,
                                view.settings.attrColorUnderline.g,
                                view.settings.attrColorUnderline.b))
    }

    // MARK: - ANSI Color Overrides Attribute Color

    func testANSIColor_OverridesAttrBold() {
        view.settings.enableBoldColor = true
        view.settings.enableANSIColor = true
        let cell = makeCell(attrs: .bold, fgIndex: 2) // Bold attr + ANSI green fg
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        // ANSI color should override the bold attribute color
        let ansiGreen = view.settings.colorTheme.ansiColors[2]
        assertColorEqual(fg, tc(ansiGreen.r, ansiGreen.g, ansiGreen.b))
    }

    // MARK: - Reverse Attribute

    func testReverse_SwapsColors() {
        view.settings.enableReverseColor = false
        view.settings.enableANSIColor = false
        view.modes.reverseVideo = false
        let cell = makeCell(attrs: .reverse)
        let (fg, bg) = view.resolveColors(cell, inSelection: false)
        // Reversed: fg gets background color, bg gets foreground color
        assertColorEqual(fg, tc(view.settings.colorTheme.background.r,
                                view.settings.colorTheme.background.g,
                                view.settings.colorTheme.background.b))
        assertColorEqual(bg, tc(view.settings.colorTheme.foreground.r,
                                view.settings.colorTheme.foreground.g,
                                view.settings.colorTheme.foreground.b))
    }

    func testReverse_WithReverseColor_UsesAttrColorReverse() {
        view.settings.enableReverseColor = true
        view.settings.enableANSIColor = false
        view.modes.reverseVideo = false
        let cell = makeCell(attrs: .reverse)
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        assertColorEqual(fg, tc(view.settings.attrColorReverse.r,
                                view.settings.attrColorReverse.g,
                                view.settings.attrColorReverse.b))
    }

    func testReverse_XOR_WithDECSCNM() {
        // reverse attr + reverseVideo mode → cancel out → normal display
        view.settings.enableANSIColor = false
        view.modes.reverseVideo = true
        let cell = makeCell(attrs: .reverse)
        let (fg, bg) = view.resolveColors(cell, inSelection: false)
        // XOR: .reverse != true → false → NOT reversed
        assertColorEqual(fg, tc(view.settings.colorTheme.foreground.r,
                                view.settings.colorTheme.foreground.g,
                                view.settings.colorTheme.foreground.b))
        assertColorEqual(bg, tc(view.settings.colorTheme.background.r,
                                view.settings.colorTheme.background.g,
                                view.settings.colorTheme.background.b))
    }

    func testReverse_ANSIColor_SwapsCorrectly() {
        view.settings.enableReverseColor = false
        view.settings.enableANSIColor = true
        view.modes.reverseVideo = false
        // Cell has ANSI red fg + reverse
        let cell = makeCell(attrs: .reverse, fgIndex: 1)
        let (_, bg) = view.resolveColors(cell, inSelection: false)
        // ANSI fg goes to bg when reversed
        let ansiRed = view.settings.colorTheme.ansiColors[1]
        assertColorEqual(bg, tc(ansiRed.r, ansiRed.g, ansiRed.b))
    }

    // MARK: - Selection Override

    func testSelection_OverridesEverything() {
        view.settings.enableANSIColor = true
        let cell = makeCell(attrs: [.bold, .reverse], fgIndex: 1)
        let (fg, bg) = view.resolveColors(cell, inSelection: true)
        assertColorEqual(fg, tc(view.settings.colorTheme.selectionForeground.r,
                                view.settings.colorTheme.selectionForeground.g,
                                view.settings.colorTheme.selectionForeground.b))
        assertColorEqual(bg, tc(view.settings.colorTheme.selectionBackground.r,
                                view.settings.colorTheme.selectionBackground.g,
                                view.settings.colorTheme.selectionBackground.b))
    }

    // MARK: - Dim Attribute

    func testDim_ReducesAlpha() {
        view.settings.enableANSIColor = false
        let cell = makeCell(attrs: .dim)
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        if let c = fg.usingColorSpace(.sRGB) {
            XCTAssertEqual(c.alphaComponent, 0.5, accuracy: 0.01)
        }
    }

    // MARK: - RGB True Color

    func testRGB_ForegroundOverridesWithANSIEnabled() {
        view.settings.enableANSIColor = true
        let cell = makeCell(fgRGB: (128, 64, 32))
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        assertColorEqual(fg, view.nsColor(r: 128, g: 64, b: 32))
    }

    func testRGB_IgnoredWhenANSIDisabled() {
        view.settings.enableANSIColor = false
        let cell = makeCell(fgRGB: (128, 64, 32))
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        // Should fall back to theme foreground
        assertColorEqual(fg, tc(view.settings.colorTheme.foreground.r,
                                view.settings.colorTheme.foreground.g,
                                view.settings.colorTheme.foreground.b))
    }

    // MARK: - PC Bold Color

    func testPCBoldColor_BrightensIndex() {
        view.settings.enableANSIColor = true
        view.settings.pcBoldColor = true
        // Bold + ANSI red (index 1) → should become bright red (index 9)
        let cell = makeCell(attrs: .bold, fgIndex: 1)
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        let brightRed = view.settings.colorTheme.ansiColors[9]
        assertColorEqual(fg, tc(brightRed.r, brightRed.g, brightRed.b))
    }

    func testPCBoldColor_Disabled_NoShift() {
        view.settings.enableANSIColor = true
        view.settings.pcBoldColor = false
        let cell = makeCell(attrs: .bold, fgIndex: 1)
        let (fg, _) = view.resolveColors(cell, inSelection: false)
        let normalRed = view.settings.colorTheme.ansiColors[1]
        assertColorEqual(fg, tc(normalRed.r, normalRed.g, normalRed.b))
    }
}
#endif
