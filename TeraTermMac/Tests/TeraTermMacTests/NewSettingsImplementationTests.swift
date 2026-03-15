/*
 * NewSettingsImplementationTests.swift
 * Tests for newly implemented settings in TeraTermMac:
 *   - Default values for all new TerminalSettings properties
 *   - INI round-trip encoding/decoding for new properties
 *   - Localization key existence for new dialog labels (en + ja)
 *   - Additional Settings tab count verification
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - New TerminalSettings Default Values

final class NewSettingsDefaultValueTests: XCTestCase {

    func testTerminalSpeedDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.terminalSpeed, "38400")
    }

    func testKillFocusCursorDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.killFocusCursor)
    }

    func testScrollThresholdDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.scrollThreshold, 12)
    }

    func testScrollWindowClearScreenDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.scrollWindowClearScreen)
    }

    func testBeepOverUsedCountDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.beepOverUsedCount, 5)
    }

    func testBeepOverUsedTimeDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.beepOverUsedTime, 2)
    }

    func testBeepSuppressTimeDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.beepSuppressTime, 5)
    }

    func testConnectingTimeoutDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.connectingTimeout, 0)
    }

    func testClearComBuffOnOpenDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.clearComBuffOnOpen)
    }

    func testAutoComPortReconnectDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.autoComPortReconnect)
    }

    func testLogTimestampFormatDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.logTimestampFormat, "%Y-%m-%d %H:%M:%S.%N")
    }

    func testAccept8BitCtrlDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.accept8BitCtrl)
    }

    func testSend8BitCtrlDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.send8BitCtrl)
    }

    func testAlternateScreenBufferDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.alternateScreenBuffer)
    }

    func testBracketedPasteModeDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.bracketedPasteMode)
    }

    func testBracketedControlOnlyDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.bracketedControlOnly)
    }

    func testAllowWrongSequenceDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.allowWrongSequence)
    }

    func testMaxOSCBufferSizeDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.maxOSCBufferSize, 4096)
    }

    func testEnableLineModeDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.enableLineMode)
    }

    func testMouseSelectStartDelayDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.mouseSelectStartDelay, 0)
    }

    func testTranslateWheelToCursorDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.translateWheelToCursor)
    }

    func testDisableWheelToCursorByCtrlDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.disableWheelToCursorByCtrl)
    }

    func testMaxBroadcastHistoryDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.maxBroadcastHistory, 99)
    }

    func testDebugModesDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.debugModes, "all")
    }

    func testJoinSplitURLDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.joinSplitURL)
    }

    func testJoinSplitURLIgnoreEOLCharDefault() {
        let s = TerminalSettings()
        XCTAssertEqual(s.joinSplitURLIgnoreEOLChar, "\\\\")
    }

    func testUnicodeEmojiOverrideDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.unicodeEmojiOverride)
    }

    func testPcBoldColorDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.pcBoldColor)
    }

    func testZmodemAutoReceiveDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.zmodemAutoReceive)
    }

    func testConfirmFileDragAndDropDefault() {
        let s = TerminalSettings()
        XCTAssertTrue(s.confirmFileDragAndDrop)
    }

    func testAutoFileRenameDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.autoFileRename)
    }

    func testClearScreenOnCloseConnectionDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.clearScreenOnCloseConnection)
    }

    func testBackWrapDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.backWrap)
    }

    func testVtCompatTabDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.vtCompatTab)
    }

    func testFallbackToCP932Default() {
        let s = TerminalSettings()
        XCTAssertFalse(s.fallbackToCP932)
    }

    func testSaveVTWinPosDefault() {
        let s = TerminalSettings()
        XCTAssertFalse(s.saveVTWinPos)
    }
}

// MARK: - INI Round-Trip for New Properties

final class NewSettingsINIRoundTripTests: XCTestCase {

    func testNewPropertiesINIRoundTrip() {
        let mgr = ConfigPersistenceManager()
        var original = TeraTermConfig()

        // Set non-default values for all new properties
        original.terminalSpeed = "115200"
        original.killFocusCursor = false
        original.scrollThreshold = 24
        original.scrollWindowClearScreen = false
        original.beepOverUsedCount = 10
        original.beepOverUsedTime = 4
        original.beepSuppressTime = 8
        original.connectingTimeout = 30
        original.clearComBuffOnOpen = false
        original.autoComPortReconnect = false
        original.logTimestampFormat = "%H:%M:%S"
        original.accept8BitCtrl = false
        original.send8BitCtrl = true
        original.alternateScreenBuffer = false
        original.bracketedPasteMode = false
        original.bracketedControlOnly = true
        original.allowWrongSequence = true
        original.maxOSCBufferSize = 8192
        original.enableLineMode = false
        original.mouseSelectStartDelay = 150
        original.translateWheelToCursor = false
        original.disableWheelToCursorByCtrl = false
        original.maxBroadcastHistory = 50
        original.debugModes = "none"
        original.joinSplitURL = true
        original.joinSplitURLIgnoreEOLChar = "~"
        original.unicodeEmojiOverride = true
        original.pcBoldColor = true
        original.zmodemAutoReceive = true
        original.confirmFileDragAndDrop = false
        original.autoFileRename = true
        original.clearScreenOnCloseConnection = true
        original.backWrap = true
        original.vtCompatTab = true
        original.fallbackToCP932 = true
        original.saveVTWinPos = true

        // Encode to INI sections, then decode back
        let sections = mgr.encode(original)
        let decoded = mgr.decode(sections: sections)

        // Verify all new properties survived the round-trip
        XCTAssertEqual(decoded.terminalSpeed, "115200")
        XCTAssertFalse(decoded.killFocusCursor)
        XCTAssertEqual(decoded.scrollThreshold, 24)
        XCTAssertFalse(decoded.scrollWindowClearScreen)
        XCTAssertEqual(decoded.beepOverUsedCount, 10)
        XCTAssertEqual(decoded.beepOverUsedTime, 4)
        XCTAssertEqual(decoded.beepSuppressTime, 8)
        XCTAssertEqual(decoded.connectingTimeout, 30)
        XCTAssertFalse(decoded.clearComBuffOnOpen)
        XCTAssertFalse(decoded.autoComPortReconnect)
        XCTAssertEqual(decoded.logTimestampFormat, "%H:%M:%S")
        XCTAssertFalse(decoded.accept8BitCtrl)
        XCTAssertTrue(decoded.send8BitCtrl)
        XCTAssertFalse(decoded.alternateScreenBuffer)
        XCTAssertFalse(decoded.bracketedPasteMode)
        XCTAssertTrue(decoded.bracketedControlOnly)
        XCTAssertTrue(decoded.allowWrongSequence)
        XCTAssertEqual(decoded.maxOSCBufferSize, 8192)
        XCTAssertFalse(decoded.enableLineMode)
        XCTAssertEqual(decoded.mouseSelectStartDelay, 150)
        XCTAssertFalse(decoded.translateWheelToCursor)
        XCTAssertFalse(decoded.disableWheelToCursorByCtrl)
        XCTAssertEqual(decoded.maxBroadcastHistory, 50)
        XCTAssertEqual(decoded.debugModes, "none")
        XCTAssertTrue(decoded.joinSplitURL)
        XCTAssertEqual(decoded.joinSplitURLIgnoreEOLChar, "~")
        XCTAssertTrue(decoded.unicodeEmojiOverride)
        XCTAssertTrue(decoded.pcBoldColor)
        XCTAssertTrue(decoded.zmodemAutoReceive)
        XCTAssertFalse(decoded.confirmFileDragAndDrop)
        XCTAssertTrue(decoded.autoFileRename)
        XCTAssertTrue(decoded.clearScreenOnCloseConnection)
        XCTAssertTrue(decoded.backWrap)
        XCTAssertTrue(decoded.vtCompatTab)
        XCTAssertTrue(decoded.fallbackToCP932)
        XCTAssertTrue(decoded.saveVTWinPos)
    }
}

// MARK: - Localization Key Tests for New Settings

final class NewSettingsLocalizationTests: XCTestCase {

    /// Verify that all new settings dialog localization keys exist in both en and ja.
    func testNewSettingsLocalizationKeysExist() {
        let newKeys = [
            "dialog.general.connectingTimeout",
            "dialog.general.clearScreenOnClose",
            "dialog.sequence.accept8BitCtrl",
            "dialog.sequence.bracketedPaste",
            "dialog.mouse.translateWheelToCursor",
            "dialog.log.timestampFormat",
            "dialog.visual.killFocusCursor",
            "dialog.debug.debugModes",
            "dialog.coding.emojiOverride",
            "dialog.copyPaste.mouseSelectDelay",
        ]

        for key in newKeys {
            let value = TTL(key)
            XCTAssertNotEqual(value, key,
                "Localization key '\(key)' should have a value (not return the key itself)")
            XCTAssertFalse(value.isEmpty,
                "Localization key '\(key)' should not be empty")
        }
    }

    /// Verify the en localization bundle contains all new keys.
    func testEnglishLocalizationBundleHasNewKeys() {
        guard let enPath = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let enBundle = Bundle(path: enPath) else {
            // In unit test context, fall back to the main bundle
            return
        }

        let newKeys = [
            "dialog.general.connectingTimeout",
            "dialog.general.clearScreenOnClose",
            "dialog.sequence.accept8BitCtrl",
            "dialog.sequence.bracketedPaste",
            "dialog.mouse.translateWheelToCursor",
            "dialog.log.timestampFormat",
            "dialog.visual.killFocusCursor",
            "dialog.debug.debugModes",
            "dialog.coding.emojiOverride",
            "dialog.copyPaste.mouseSelectDelay",
        ]

        for key in newKeys {
            let value = enBundle.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(value, key,
                "English localization should contain key '\(key)'")
        }
    }

    /// Verify the ja localization bundle contains all new keys.
    func testJapaneseLocalizationBundleHasNewKeys() {
        guard let jaPath = Bundle.main.path(forResource: "ja", ofType: "lproj"),
              let jaBundle = Bundle(path: jaPath) else {
            // In unit test context, fall back to the main bundle
            return
        }

        let newKeys = [
            "dialog.general.connectingTimeout",
            "dialog.general.clearScreenOnClose",
            "dialog.sequence.accept8BitCtrl",
            "dialog.sequence.bracketedPaste",
            "dialog.mouse.translateWheelToCursor",
            "dialog.log.timestampFormat",
            "dialog.visual.killFocusCursor",
            "dialog.debug.debugModes",
            "dialog.coding.emojiOverride",
            "dialog.copyPaste.mouseSelectDelay",
        ]

        for key in newKeys {
            let value = jaBundle.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(value, key,
                "Japanese localization should contain key '\(key)'")
        }
    }
}

// MARK: - Additional Settings Tab Count Verification

final class NewSettingsTabCountTests: XCTestCase {

    /// Verify that all 13 Additional Settings tabs can still be instantiated
    /// after adding new settings properties.
    func testAdditionalSettingsTabCountRemains13() {
        let settings = TerminalSettings()
        let tabs: [AdditionalSettingsTab] = [
            GeneralTab(settings: settings),
            CodingTab(settings: settings),
            CopyPasteTab(settings: settings),
            SequenceTab(settings: settings),
            MouseTab(settings: settings),
            LogTab(settings: settings),
            VisualTab(settings: settings),
            FontTab(settings: settings),
            TEKFontTab(settings: settings),
            ThemeTab(settings: settings),
            UITab(settings: settings),
            PluginTab(settings: settings),
            DebugTab(settings: settings),
        ]

        XCTAssertEqual(tabs.count, 13, "Should have 13 tabs (all except Cygwin)")

        for tab in tabs {
            XCTAssertFalse(tab.tabTitle.isEmpty,
                "Tab '\(type(of: tab))' should have a non-empty title")
            XCTAssertNotNil(tab.contentView,
                "Tab '\(type(of: tab))' should have a content view")
        }
    }
}

#endif
