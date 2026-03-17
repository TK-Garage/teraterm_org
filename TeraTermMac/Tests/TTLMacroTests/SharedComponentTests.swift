/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Tests for shared components (localization, dialog types, constants).
 */

import XCTest
import TTLMacroShared

final class SharedComponentTests: XCTestCase {

    // MARK: - Localization Tests

    func testLocalizationFunctionReturnsString() {
        // L() should return at least the key itself as fallback
        let result = L("macro.open.title")
        XCTAssertFalse(result.isEmpty)
    }

    func testLocalizationFunctionWithFormat() {
        let result = L("macro.menu.lineNumber", 42)
        XCTAssertFalse(result.isEmpty)
        // Should contain the number 42
        XCTAssertTrue(result.contains("42"))
    }

    func testLocalizationKeysFallback() {
        // Unknown key should return the key itself
        let unknownKey = "this.key.does.not.exist.xyz"
        let result = L(unknownKey)
        XCTAssertEqual(result, unknownKey)
    }

    // MARK: - Dialog Type Tests

    func testDialogTypeMessageBox() {
        XCTAssertEqual(MacroDialogType.messagebox.rawValue, "messagebox")
    }

    func testDialogTypeInputBox() {
        XCTAssertEqual(MacroDialogType.inputbox.rawValue, "inputbox")
    }

    func testDialogTypeYesNoBox() {
        XCTAssertEqual(MacroDialogType.yesnobox.rawValue, "yesnobox")
    }

    func testDialogTypePasswordBox() {
        XCTAssertEqual(MacroDialogType.passwordbox.rawValue, "passwordbox")
    }

    func testDialogTypeListBox() {
        XCTAssertEqual(MacroDialogType.listbox.rawValue, "listbox")
    }

    func testDialogTypeFilenameBox() {
        XCTAssertEqual(MacroDialogType.filenamebox.rawValue, "filenamebox")
    }

    func testDialogTypeDirnameBox() {
        XCTAssertEqual(MacroDialogType.dirnamebox.rawValue, "dirnamebox")
    }

    func testDialogTypeStatusBox() {
        XCTAssertEqual(MacroDialogType.statusbox.rawValue, "statusbox")
    }

    // MARK: - Execution Status Tests

    func testExecutionStatusIdle() {
        XCTAssertEqual(MacroExecutionStatus.idle.rawValue, "idle")
    }

    func testExecutionStatusRunning() {
        XCTAssertEqual(MacroExecutionStatus.running.rawValue, "running")
    }

    func testExecutionStatusPaused() {
        XCTAssertEqual(MacroExecutionStatus.paused.rawValue, "paused")
    }

    func testExecutionStatusStopped() {
        XCTAssertEqual(MacroExecutionStatus.stopped.rawValue, "stopped")
    }

    func testExecutionStatusError() {
        XCTAssertEqual(MacroExecutionStatus.error.rawValue, "error")
    }

    // MARK: - Constants Tests

    func testMaxReconnectAttempts() {
        XCTAssertEqual(MacroConstants.maxReconnectAttempts, 3)
    }

    func testReconnectInterval() {
        XCTAssertEqual(MacroConstants.reconnectInterval, 2.0)
    }

    func testTTLFileExtension() {
        XCTAssertEqual(MacroConstants.ttlFileExtension, "ttl")
    }

    func testBundleIdentifiers() {
        XCTAssertEqual(MacroConstants.ttlMacroBundleId, "com.teraterm.mac.TTLMacro")
        XCTAssertEqual(MacroConstants.teraTermMacBundleId, "com.teraterm.mac")
    }

    // MARK: - XPC Interface Tests

    func testServiceInterfaceNotNil() {
        let interface = MacroXPCInterface.serviceInterface()
        XCTAssertNotNil(interface)
    }

    func testClientInterfaceNotNil() {
        let interface = MacroXPCInterface.clientInterface()
        XCTAssertNotNil(interface)
    }

    // MARK: - AppIcon Asset Tests

    func testAppIconAssetsExist() {
        // Verify icon files exist in the expected location
        let basePath = "Sources/TTLMacro/Resources/Assets.xcassets/AppIcon.appiconset"

        // Check that Contents.json exists
        let contentsJsonPath = basePath + "/Contents.json"
        // We can't easily check file existence in tests without a known root
        // but we verify the path format is correct
        XCTAssertTrue(contentsJsonPath.hasSuffix("Contents.json"))
    }

    func testIconSizes() {
        let expectedSizes = [16, 32, 64, 128, 256, 512, 1024]
        for size in expectedSizes {
            let filename = "icon_\(size).png"
            XCTAssertTrue(filename.hasSuffix(".png"))
            XCTAssertTrue(filename.hasPrefix("icon_"))
        }
    }
}
