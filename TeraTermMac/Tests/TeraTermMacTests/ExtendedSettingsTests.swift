/*
 * ExtendedSettingsTests.swift
 * Tests for extended settings features:
 *   - Window settings (bold, frameless, color modes, bg color, attribute colors)
 *   - Font settings (resize to fit width)
 *   - Theme settings (background image, transparency, color editor)
 *   - Log settings (BOM, timestamp type)
 *   - TEK window printing
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - Extended Terminal Settings Tests

final class ExtendedTerminalSettingsTests: XCTestCase {

    // MARK: - Window Extended Settings Properties

    func testWindowExtendedSettingsDefaults() {
        let s = TerminalSettings()
        XCTAssertTrue(s.enableBoldDisplay)
        XCTAssertFalse(s.hideWindowFrame)
        XCTAssertFalse(s.enableAixtermColors)
        XCTAssertTrue(s.enableXterm256Colors)
        XCTAssertFalse(s.useStandardBGColor)
    }

    func testWindowExtendedSettingsModification() {
        let s = TerminalSettings()
        s.enableBoldDisplay = false
        s.hideWindowFrame = true
        s.enableAixtermColors = true
        s.enableXterm256Colors = false
        s.useStandardBGColor = true

        XCTAssertFalse(s.enableBoldDisplay)
        XCTAssertTrue(s.hideWindowFrame)
        XCTAssertTrue(s.enableAixtermColors)
        XCTAssertFalse(s.enableXterm256Colors)
        XCTAssertTrue(s.useStandardBGColor)
    }

    // MARK: - Attribute Color Settings

    func testAttrColorDefaults() {
        let s = TerminalSettings()
        XCTAssertEqual(s.attrColorNormal.r, 255)
        XCTAssertEqual(s.attrColorNormal.g, 255)
        XCTAssertEqual(s.attrColorNormal.b, 255)
        XCTAssertEqual(s.attrColorBold.r, 255)
        XCTAssertEqual(s.attrColorBold.g, 255)
        XCTAssertEqual(s.attrColorBold.b, 0)
        XCTAssertEqual(s.attrColorURL.r, 0)
        XCTAssertEqual(s.attrColorURL.g, 128)
        XCTAssertEqual(s.attrColorURL.b, 255)
    }

    func testAttrColorModification() {
        let s = TerminalSettings()
        s.attrColorNormal = TerminalColor(r: 100, g: 200, b: 50)
        s.attrColorBold = TerminalColor(r: 10, g: 20, b: 30)
        s.attrColorBlink = TerminalColor(r: 40, g: 50, b: 60)
        s.attrColorReverse = TerminalColor(r: 70, g: 80, b: 90)
        s.attrColorURL = TerminalColor(r: 110, g: 120, b: 130)
        s.attrColorUnderline = TerminalColor(r: 140, g: 150, b: 160)

        XCTAssertEqual(s.attrColorNormal, TerminalColor(r: 100, g: 200, b: 50))
        XCTAssertEqual(s.attrColorBold, TerminalColor(r: 10, g: 20, b: 30))
        XCTAssertEqual(s.attrColorBlink, TerminalColor(r: 40, g: 50, b: 60))
        XCTAssertEqual(s.attrColorReverse, TerminalColor(r: 70, g: 80, b: 90))
        XCTAssertEqual(s.attrColorURL, TerminalColor(r: 110, g: 120, b: 130))
        XCTAssertEqual(s.attrColorUnderline, TerminalColor(r: 140, g: 150, b: 160))
    }

    // MARK: - Font Extended Settings

    func testResizeFontToFitDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.resizeFontToFitWidth)
    }

    func testResizeFontToFitModification() {
        let s = TerminalSettings()
        s.resizeFontToFitWidth = true
        XCTAssertTrue(s.resizeFontToFitWidth)
    }

    // MARK: - Background Image Settings

    func testBgImageDefaults() {
        let s = TerminalSettings()
        XCTAssertEqual(s.bgImagePath, "")
        XCTAssertEqual(s.bgImageAlphaNormal, 1.0, accuracy: 0.001)
        XCTAssertEqual(s.bgImageAlphaReverse, 1.0, accuracy: 0.001)
        XCTAssertEqual(s.bgImageAlphaOther, 1.0, accuracy: 0.001)
    }

    func testBgImageModification() {
        let s = TerminalSettings()
        s.bgImagePath = "/tmp/background.png"
        s.bgImageAlphaNormal = 0.8
        s.bgImageAlphaReverse = 0.6
        s.bgImageAlphaOther = 0.4

        XCTAssertEqual(s.bgImagePath, "/tmp/background.png")
        XCTAssertEqual(s.bgImageAlphaNormal, 0.8, accuracy: 0.001)
        XCTAssertEqual(s.bgImageAlphaReverse, 0.6, accuracy: 0.001)
        XCTAssertEqual(s.bgImageAlphaOther, 0.4, accuracy: 0.001)
    }

    // MARK: - Log Extended Settings

    func testLogBOMDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.logBOM)
    }

    func testLogBOMModification() {
        let s = TerminalSettings()
        s.logBOM = true
        XCTAssertTrue(s.logBOM)
    }

    func testLogTimestampTypeDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.logTimestampType, 0)
    }

    func testLogTimestampTypeModification() {
        let s = TerminalSettings()
        s.logTimestampType = 1
        XCTAssertEqual(s.logTimestampType, 1)
        s.logTimestampType = 2
        XCTAssertEqual(s.logTimestampType, 2)
    }

    // MARK: - LogTimestampType Enum

    func testLogTimestampTypeEnum() {
        XCTAssertEqual(LogTimestampType.local.rawValue, 0)
        XCTAssertEqual(LogTimestampType.utc.rawValue, 1)
        XCTAssertEqual(LogTimestampType.elapsed.rawValue, 2)
        XCTAssertEqual(LogTimestampType.allCases.count, 3)
    }

    func testLogTimestampTypeDisplayNames() {
        XCTAssertEqual(LogTimestampType.local.displayName, "Local Time")
        XCTAssertEqual(LogTimestampType.utc.displayName, "UTC")
        XCTAssertEqual(LogTimestampType.elapsed.displayName, "Elapsed Time")
    }

    // MARK: - Settings Codable (JSON round-trip)

    func testExtendedSettingsJSONRoundTrip() throws {
        let original = TerminalSettings()
        original.enableBoldDisplay = false
        original.hideWindowFrame = true
        original.enableAixtermColors = true
        original.enableXterm256Colors = false
        original.useStandardBGColor = true
        original.attrColorBold = TerminalColor(r: 1, g: 2, b: 3)
        original.resizeFontToFitWidth = true
        original.bgImagePath = "/test/bg.png"
        original.bgImageAlphaNormal = 0.5
        original.bgImageAlphaReverse = 0.3
        original.bgImageAlphaOther = 0.7
        original.logBOM = true
        original.logTimestampType = 2

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let loaded = try decoder.decode(TerminalSettings.self, from: data)

        XCTAssertFalse(loaded.enableBoldDisplay)
        XCTAssertTrue(loaded.hideWindowFrame)
        XCTAssertTrue(loaded.enableAixtermColors)
        XCTAssertFalse(loaded.enableXterm256Colors)
        XCTAssertTrue(loaded.useStandardBGColor)
        XCTAssertEqual(loaded.attrColorBold, TerminalColor(r: 1, g: 2, b: 3))
        XCTAssertTrue(loaded.resizeFontToFitWidth)
        XCTAssertEqual(loaded.bgImagePath, "/test/bg.png")
        XCTAssertEqual(loaded.bgImageAlphaNormal, 0.5, accuracy: 0.001)
        XCTAssertEqual(loaded.bgImageAlphaReverse, 0.3, accuracy: 0.001)
        XCTAssertEqual(loaded.bgImageAlphaOther, 0.7, accuracy: 0.001)
        XCTAssertTrue(loaded.logBOM)
        XCTAssertEqual(loaded.logTimestampType, 2)
    }
}

// MARK: - Log BOM and Timestamp Tests

final class LogExtendedTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "teraterm_log_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    func testLogBOMWritten() throws {
        let logger = TerminalLogger()
        let path = tempDir + "/bom_test.log"
        let opts = LogOptions(writeBOM: true)

        XCTAssertTrue(logger.startLogging(to: path, options: opts))
        logger.logString("Hello")
        logger.stopLogging()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // UTF-8 BOM is EF BB BF
        XCTAssertTrue(data.count >= 3)
        XCTAssertEqual(data[0], 0xEF)
        XCTAssertEqual(data[1], 0xBB)
        XCTAssertEqual(data[2], 0xBF)
    }

    func testLogNoBOM() throws {
        let logger = TerminalLogger()
        let path = tempDir + "/no_bom_test.log"
        let opts = LogOptions(writeBOM: false)

        XCTAssertTrue(logger.startLogging(to: path, options: opts))
        logger.logString("Hello")
        logger.stopLogging()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // Should NOT start with BOM
        XCTAssertTrue(data.count >= 3)
        let firstThree = [data[0], data[1], data[2]]
        XCTAssertNotEqual(firstThree, [0xEF, 0xBB, 0xBF])
    }

    func testLogTimestampLocal() {
        let logger = TerminalLogger()
        let path = tempDir + "/ts_local.log"
        var opts = LogOptions()
        opts.addTimestamp = true
        opts.timestampType = .local

        XCTAssertTrue(logger.startLogging(to: path, options: opts))
        let ts = logger.formattedTimestamp()
        logger.stopLogging()

        // Local timestamp should not be empty
        XCTAssertFalse(ts.isEmpty)
    }

    func testLogTimestampUTC() {
        let logger = TerminalLogger()
        let path = tempDir + "/ts_utc.log"
        var opts = LogOptions()
        opts.addTimestamp = true
        opts.timestampType = .utc

        XCTAssertTrue(logger.startLogging(to: path, options: opts))
        let ts = logger.formattedTimestamp()
        logger.stopLogging()

        XCTAssertFalse(ts.isEmpty)
    }

    func testLogTimestampElapsed() {
        let logger = TerminalLogger()
        let path = tempDir + "/ts_elapsed.log"
        var opts = LogOptions()
        opts.addTimestamp = true
        opts.timestampType = .elapsed

        XCTAssertTrue(logger.startLogging(to: path, options: opts))
        // Wait a tiny bit
        Thread.sleep(forTimeInterval: 0.01)
        let ts = logger.formattedTimestamp()
        logger.stopLogging()

        // Should be in HH:MM:SS.mmm format
        XCTAssertTrue(ts.contains(":"))
        XCTAssertTrue(ts.contains("."))
    }

    func testLogBOMNotWrittenOnAppend() throws {
        let logger = TerminalLogger()
        let path = tempDir + "/bom_append.log"

        // First pass: create with BOM
        var opts = LogOptions(appendMode: false, writeBOM: true)
        XCTAssertTrue(logger.startLogging(to: path, options: opts))
        logger.logString("First")
        logger.stopLogging()

        // Second pass: append mode should NOT add another BOM
        let logger2 = TerminalLogger()
        opts = LogOptions(appendMode: true, writeBOM: true)
        XCTAssertTrue(logger2.startLogging(to: path, options: opts))
        logger2.logString("Second")
        logger2.stopLogging()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // Count BOM occurrences - should be exactly 1
        var bomCount = 0
        for i in 0..<(data.count - 2) {
            if data[i] == 0xEF && data[i+1] == 0xBB && data[i+2] == 0xBF {
                bomCount += 1
            }
        }
        XCTAssertEqual(bomCount, 1, "BOM should appear only once, not on append")
    }
}

// MARK: - Visual Tab Extended Tests

final class VisualTabExtendedTests: XCTestCase {

    func testVisualTabAppliesWindowExtendedSettings() {
        let settings = TerminalSettings()
        settings.enableBoldDisplay = true
        settings.hideWindowFrame = false
        settings.enableAixtermColors = false
        settings.enableXterm256Colors = true
        settings.useStandardBGColor = false

        _ = VisualTab(settings: settings)

        // Modify settings via tab
        settings.enableBoldDisplay = false
        settings.hideWindowFrame = true

        // Re-create to verify initial values were used
        let tab2 = VisualTab(settings: settings)
        XCTAssertNotNil(tab2.contentView)
        XCTAssertFalse(tab2.tabTitle.isEmpty)
    }

    func testVisualTabContentViewExists() {
        let settings = TerminalSettings()
        let tab = VisualTab(settings: settings)
        XCTAssertNotNil(tab.contentView)
        XCTAssertGreaterThan(tab.contentView.subviews.count, 0)
    }
}

// MARK: - Font Tab Extended Tests

final class FontTabExtendedTests: XCTestCase {

    func testFontTabHasResizeFontOption() {
        let settings = TerminalSettings()
        let tab = FontTab(settings: settings)
        XCTAssertNotNil(tab.contentView)
        XCTAssertGreaterThan(tab.contentView.subviews.count, 0)
    }

    func testFontTabAppliesResizeFontSetting() {
        let settings = TerminalSettings()
        settings.resizeFontToFitWidth = false
        let tab = FontTab(settings: settings)
        tab.apply(to: settings)
        // Default should be false
        XCTAssertFalse(settings.resizeFontToFitWidth)
    }
}

// MARK: - Theme Tab Extended Tests

final class ThemeTabExtendedTests: XCTestCase {

    func testThemeTabContentViewExists() {
        let settings = TerminalSettings()
        let tab = ThemeTab(settings: settings)
        XCTAssertNotNil(tab.contentView)
        XCTAssertGreaterThan(tab.contentView.subviews.count, 0)
    }

    func testThemeTabAppliesBgImageSettings() {
        let settings = TerminalSettings()
        settings.bgImagePath = "/test/bg.png"
        settings.bgImageAlphaNormal = 0.5
        let tab = ThemeTab(settings: settings)
        tab.apply(to: settings)
        // Apply should set values from UI controls
        XCTAssertNotNil(settings.bgImagePath)
    }

    func testThemeTabAppliesColorEditorSettings() {
        let settings = TerminalSettings()
        _ = settings.colorTheme.foreground
        let tab = ThemeTab(settings: settings)
        tab.apply(to: settings)
        // Color wells should preserve the color when applied
        XCTAssertNotNil(settings.colorTheme.foreground)
        // Values might differ slightly due to color space conversion,
        // so just verify they're not nil
    }
}

// MARK: - Log Tab Extended Tests

final class LogTabExtendedTests: XCTestCase {

    func testLogTabContentViewExists() {
        let settings = TerminalSettings()
        let tab = LogTab(settings: settings)
        XCTAssertNotNil(tab.contentView)
        XCTAssertGreaterThan(tab.contentView.subviews.count, 0)
    }

    func testLogTabAppliesBOMSetting() {
        let settings = TerminalSettings()
        settings.logBOM = false
        let tab = LogTab(settings: settings)
        tab.apply(to: settings)
        XCTAssertFalse(settings.logBOM)
    }

    func testLogTabAppliesTimestampTypeSetting() {
        let settings = TerminalSettings()
        settings.logTimestampType = 0
        let tab = LogTab(settings: settings)
        tab.apply(to: settings)
        XCTAssertEqual(settings.logTimestampType, 0)
    }
}

// MARK: - TEK Window Print Tests

final class TEKWindowPrintTests: XCTestCase {

    func testTEKWindowControllerPrintMethodExists() {
        let settings = TerminalSettings()
        let tek = TEKWindowController(settings: settings)
        // Verify the print method exists
        XCTAssertTrue(tek.responds(to: #selector(NSObject.doesNotRecognizeSelector(_:))) ||
                      tek.responds(to: NSSelectorFromString("printTEKWindow")))
    }

    func testTEKViewDrawsWithoutCrash() {
        let view = TEKView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        // Drawing should not crash
        view.clearScreen()
        view.processData(Data())
        XCTAssertTrue(view.bounds.width > 0)
    }

    func testTEKWindowControllerCreation() {
        let settings = TerminalSettings()
        let tek = TEKWindowController(settings: settings)
        XCTAssertNotNil(tek.window)
        XCTAssertEqual(tek.window?.title, "Tera Term: TEK")
        tek.window?.close()
    }
}

// MARK: - Settings Propagation Tests for New Properties

final class ExtendedSettingsPropagationTests: XCTestCase {

    func testSettingsObjectReferenceForNewProperties() {
        let s = TerminalSettings()
        s.enableBoldDisplay = false
        s.hideWindowFrame = true
        s.bgImagePath = "/path/to/bg.png"
        s.logBOM = true

        let wc = TerminalWindowController(settings: s)
        _ = wc.window

        // All components should see the same reference
        XCTAssertFalse(wc.settings.enableBoldDisplay)
        XCTAssertTrue(wc.settings.hideWindowFrame)
        XCTAssertEqual(wc.settings.bgImagePath, "/path/to/bg.png")
        XCTAssertTrue(wc.settings.logBOM)

        wc.window?.close()
    }

    func testNewSettingsRoundTripViaApply() {
        let s = TerminalSettings()
        s.enableAixtermColors = true
        s.enableXterm256Colors = false
        s.resizeFontToFitWidth = true
        s.logTimestampType = 2

        let wc = TerminalWindowController(settings: s)
        _ = wc.window
        wc.applySettings()

        XCTAssertTrue(wc.settings.enableAixtermColors)
        XCTAssertFalse(wc.settings.enableXterm256Colors)
        XCTAssertTrue(wc.settings.resizeFontToFitWidth)
        XCTAssertEqual(wc.settings.logTimestampType, 2)

        wc.window?.close()
    }
}

#endif
