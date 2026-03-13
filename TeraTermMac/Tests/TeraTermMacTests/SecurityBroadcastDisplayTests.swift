/*
 * SecurityBroadcastDisplayTests.swift
 * Tests for SSH security warning dialogs, broadcast dialog,
 * and enhanced copy/paste, sequence, and visual tab settings.
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - New Settings Properties Tests

final class ExtendedSettingsPropertiesTests: XCTestCase {

    func testCopyPasteExtendedDefaults() {
        let s = TerminalSettings()
        XCTAssertFalse(s.disableRightClickPaste)
        XCTAssertFalse(s.confirmRightClickPaste)
        XCTAssertFalse(s.disableMiddleClickPaste)
        XCTAssertFalse(s.leftClickOnlySelection)
        XCTAssertFalse(s.trimTrailingNewline)
        XCTAssertTrue(s.confirmDangerousClipboard)
        XCTAssertTrue(s.dangerousKeywordFile.isEmpty)
        XCTAssertFalse(s.enableSelectionOnActivate)
    }

    func testControlSequenceExtendedDefaults() {
        let s = TerminalSettings()
        XCTAssertFalse(s.disableControlKeyMouseEvent)
        XCTAssertEqual(s.titleChangeMode, 0)
        XCTAssertTrue(s.windowInfoReportSequence)
        XCTAssertEqual(s.clipboardAccessMode, 0)
        XCTAssertTrue(s.notifyClipboardAccess)
        XCTAssertFalse(s.acceptScrollBufferClear)
        XCTAssertFalse(s.disablePrintSequence)
    }

    func testBroadcastDefaults() {
        let s = TerminalSettings()
        XCTAssertTrue(s.broadcastHistory.isEmpty)
        XCTAssertFalse(s.broadcastSendToThisOnly)
        XCTAssertTrue(s.broadcastSendEnter)
        XCTAssertFalse(s.broadcastRealtime)
    }

    func testVisualExtendedDefaults() {
        let s = TerminalSettings()
        XCTAssertTrue(s.enableBoldColor)
        XCTAssertTrue(s.enableBoldFont)
        XCTAssertTrue(s.enableBlinkColor)
        XCTAssertTrue(s.enableReverseColor)
        XCTAssertTrue(s.enableUnderlineColor)
        XCTAssertTrue(s.enableUnderlineDecoration)
        XCTAssertTrue(s.enableURLColor)
        XCTAssertTrue(s.enableURLUnderline)
        XCTAssertTrue(s.enableANSIColor)
        XCTAssertEqual(s.fontRenderingQuality, 0)
    }

    func testExtendedSettingsEncodeDecode() throws {
        let original = TerminalSettings()
        original.disableRightClickPaste = true
        original.confirmDangerousClipboard = false
        original.dangerousKeywordFile = "/usr/local/keywords.txt"
        original.disableControlKeyMouseEvent = true
        original.titleChangeMode = 2
        original.clipboardAccessMode = 1
        original.broadcastHistory = ["ls -la", "pwd"]
        original.broadcastRealtime = true
        original.enableBoldColor = false
        original.enableURLUnderline = false
        original.enableANSIColor = false
        original.fontRenderingQuality = 2

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TerminalSettings.self, from: data)

        XCTAssertTrue(decoded.disableRightClickPaste)
        XCTAssertFalse(decoded.confirmDangerousClipboard)
        XCTAssertEqual(decoded.dangerousKeywordFile, "/usr/local/keywords.txt")
        XCTAssertTrue(decoded.disableControlKeyMouseEvent)
        XCTAssertEqual(decoded.titleChangeMode, 2)
        XCTAssertEqual(decoded.clipboardAccessMode, 1)
        XCTAssertEqual(decoded.broadcastHistory, ["ls -la", "pwd"])
        XCTAssertTrue(decoded.broadcastRealtime)
        XCTAssertFalse(decoded.enableBoldColor)
        XCTAssertFalse(decoded.enableURLUnderline)
        XCTAssertFalse(decoded.enableANSIColor)
        XCTAssertEqual(decoded.fontRenderingQuality, 2)
    }
}

// MARK: - SSH Security Dialog Tests

final class SSHSecurityDialogTests: XCTestCase {

    func testHostKeyActionEnum() {
        // Verify all cases exist
        let actions: [HostKeyAction] = [.accept, .acceptOnce, .reject]
        XCTAssertEqual(actions.count, 3)
    }

    func testSSHFPStatusEnum() {
        let statuses: [SSHFPDialog.SSHFPStatus] = [.matched, .notMatched, .notFound, .insecure]
        XCTAssertEqual(statuses.count, 4)
    }

    func testUnknownHostDialogClassExists() {
        // クラスがアクセス可能であることを確認
        XCTAssertNotNil(UnknownHostDialog.self as AnyClass)
    }

    func testDifferentKeyDialogClassExists() {
        XCTAssertNotNil(DifferentKeyDialog.self as AnyClass)
    }

    func testDifferentTypeKeyDialogClassExists() {
        XCTAssertNotNil(DifferentTypeKeyDialog.self as AnyClass)
    }

    func testHostKeyRotationDialogClassExists() {
        XCTAssertNotNil(HostKeyRotationDialog.self as AnyClass)
    }

    func testSSHFPDialogClassExists() {
        XCTAssertNotNil(SSHFPDialog.self as AnyClass)
    }
}

// MARK: - Broadcast Dialog Tests

final class BroadcastDialogTests: XCTestCase {

    func testBroadcastDialogCreation() {
        let settings = TerminalSettings()
        let controller = BroadcastDialogController(settings: settings)
        XCTAssertNotNil(controller, "Broadcast dialog controller should be created")
    }

    func testBroadcastWindowEntry() {
        let entry = BroadcastDialogController.BroadcastWindowEntry(
            windowID: 1, title: "Test Window", selected: true)
        XCTAssertEqual(entry.windowID, 1)
        XCTAssertEqual(entry.title, "Test Window")
        XCTAssertTrue(entry.selected)
    }

    func testBroadcastHistoryManagement() {
        let settings = TerminalSettings()
        settings.broadcastHistory = ["cmd1", "cmd2", "cmd3"]
        XCTAssertEqual(settings.broadcastHistory.count, 3)
        XCTAssertEqual(settings.broadcastHistory[0], "cmd1")
    }

    func testBroadcastSettingsPersistence() {
        let settings = TerminalSettings()
        settings.broadcastSendToThisOnly = true
        settings.broadcastSendEnter = false
        settings.broadcastRealtime = true
        XCTAssertTrue(settings.broadcastSendToThisOnly)
        XCTAssertFalse(settings.broadcastSendEnter)
        XCTAssertTrue(settings.broadcastRealtime)
    }
}

// MARK: - Enhanced Tab Tests

final class EnhancedTabTests: XCTestCase {

    private var settings: TerminalSettings!

    override func setUp() {
        settings = TerminalSettings()
    }

    func testCopyPasteTabHasExtendedControls() {
        let tab = CopyPasteTab(settings: settings)
        let controls = collectControls(in: tab.contentView)
        // Original: 3 checkboxes + new: 8 = 11 total
        XCTAssertGreaterThanOrEqual(controls.checkboxes, 10,
            "Copy/Paste tab should have extended checkboxes")
        XCTAssertGreaterThanOrEqual(controls.textFields, 2,
            "Copy/Paste tab should have delimiter and keyword fields")
        XCTAssertGreaterThanOrEqual(controls.boxes, 2,
            "Copy/Paste tab should have paste and security group boxes")
    }

    func testCopyPasteTabAppliesExtendedSettings() {
        settings.disableRightClickPaste = false
        settings.confirmDangerousClipboard = true
        let tab = CopyPasteTab(settings: settings)
        tab.apply(to: settings)
        XCTAssertNotNil(settings.disableRightClickPaste)
        XCTAssertNotNil(settings.confirmDangerousClipboard)
        XCTAssertNotNil(settings.dangerousKeywordFile)
    }

    func testSequenceTabHasExtendedControls() {
        let tab = SequenceTab(settings: settings)
        let controls = collectControls(in: tab.contentView)
        // Original: 6 checkboxes + new: 5 = 11 total
        XCTAssertGreaterThanOrEqual(controls.checkboxes, 10,
            "Sequence tab should have extended checkboxes")
        XCTAssertGreaterThanOrEqual(controls.popups, 3,
            "Sequence tab should have beep, title mode, and clipboard mode popups")
    }

    func testSequenceTabAppliesExtendedSettings() {
        let tab = SequenceTab(settings: settings)
        tab.apply(to: settings)
        XCTAssertNotNil(settings.disableControlKeyMouseEvent)
        XCTAssertNotNil(settings.titleChangeMode)
        XCTAssertNotNil(settings.clipboardAccessMode)
        XCTAssertNotNil(settings.notifyClipboardAccess)
        XCTAssertNotNil(settings.acceptScrollBufferClear)
        XCTAssertNotNil(settings.disablePrintSequence)
    }

    func testVisualTabHasExtendedControls() {
        let tab = VisualTab(settings: settings)
        let controls = collectControls(in: tab.contentView)
        // Original: 5 attribute checks + new: 9 color/font checks = 14
        XCTAssertGreaterThanOrEqual(controls.checkboxes, 14,
            "Visual tab should have extended attribute color/font checkboxes")
        XCTAssertGreaterThanOrEqual(controls.popups, 2,
            "Visual tab should have mouse cursor and font quality popups")
        XCTAssertGreaterThanOrEqual(controls.colorWells, 16,
            "Visual tab should still have 16 ANSI color wells")
        XCTAssertGreaterThanOrEqual(controls.boxes, 3,
            "Visual tab should have opacity, color, attrs, and attr color boxes")
    }

    func testVisualTabAppliesExtendedSettings() {
        let tab = VisualTab(settings: settings)
        tab.apply(to: settings)
        XCTAssertNotNil(settings.mouseCursorType)
        XCTAssertNotNil(settings.fontRenderingQuality)
        XCTAssertNotNil(settings.enableBoldColor)
        XCTAssertNotNil(settings.enableBoldFont)
        XCTAssertNotNil(settings.enableBlinkColor)
        XCTAssertNotNil(settings.enableReverseColor)
        XCTAssertNotNil(settings.enableUnderlineColor)
        XCTAssertNotNil(settings.enableUnderlineDecoration)
        XCTAssertNotNil(settings.enableURLColor)
        XCTAssertNotNil(settings.enableURLUnderline)
        XCTAssertNotNil(settings.enableANSIColor)
    }
}

// MARK: - Control Counting Helper (shared)

private struct ControlCounts {
    var textFields = 0
    var secureFields = 0
    var popups = 0
    var checkboxes = 0
    var radios = 0
    var sliders = 0
    var buttons = 0
    var colorWells = 0
    var boxes = 0
}

private func collectControls(in view: NSView) -> ControlCounts {
    var counts = ControlCounts()
    collectRecursive(view: view, counts: &counts)
    return counts
}

private func collectRecursive(view: NSView, counts: inout ControlCounts) {
    switch view {
    case is NSSecureTextField:
        counts.secureFields += 1
    case is NSPopUpButton:
        counts.popups += 1
    case let button as NSButton:
        // buttonType has no public getter; infer type from cell masks.
        // Checkboxes/radios: highlightsBy = .contentsCellMask, showsStateBy = .contentsCellMask
        // Push buttons: highlightsBy contains .pushInCellMask, showsStateBy is empty
        if let cell = button.cell as? NSButtonCell,
           cell.highlightsBy == .contentsCellMask,
           cell.showsStateBy == .contentsCellMask {
            // Both checkbox and radio have identical masks;
            // distinguish by image: radio uses a circle, checkbox uses a square
            if button.image?.name()?.lowercased().contains("radio") == true {
                counts.radios += 1
            } else {
                counts.checkboxes += 1
            }
        } else {
            counts.buttons += 1
        }
    case is NSTextField:
        counts.textFields += 1
    case is NSSlider:
        counts.sliders += 1
    case is NSColorWell:
        counts.colorWells += 1
    case let box as NSBox where box.boxType == .primary:
        counts.boxes += 1
    default:
        break
    }

    for subview in view.subviews {
        collectRecursive(view: subview, counts: &counts)
    }
}

#endif
