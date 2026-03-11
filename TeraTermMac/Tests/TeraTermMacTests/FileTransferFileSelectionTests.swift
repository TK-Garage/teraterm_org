/*
 * FileTransferFileSelectionTests.swift
 *
 * Tests for file transfer file selection enhancements:
 *   - All file types selectable (no content-type filtering)
 *   - Read permission validation with error display
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - configureOpenPanelForAllFileTypes Tests

class FileTransferOpenPanelConfigTests: XCTestCase {

    func testConfigureSetsEmptyAllowedContentTypes() {
        let panel = NSOpenPanel()
        // Pre-set a content type to verify it gets cleared
        panel.allowedContentTypes = [.plainText]
        FileTransferDialogHelper.configureOpenPanelForAllFileTypes(panel)
        XCTAssertTrue(panel.allowedContentTypes.isEmpty,
            "allowedContentTypes should be empty to allow all file types")
    }

    func testConfigureSetsAllowsOtherFileTypes() {
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = false
        FileTransferDialogHelper.configureOpenPanelForAllFileTypes(panel)
        XCTAssertTrue(panel.allowsOtherFileTypes,
            "allowsOtherFileTypes should be true to allow any file")
    }

    func testConfigureSetsTreeatsFilePackagesAsDirectories() {
        let panel = NSOpenPanel()
        panel.treatsFilePackagesAsDirectories = false
        FileTransferDialogHelper.configureOpenPanelForAllFileTypes(panel)
        XCTAssertTrue(panel.treatsFilePackagesAsDirectories,
            "treatsFilePackagesAsDirectories should be true so users can browse inside packages")
    }

    func testConfigureDoesNotAlterCanChooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        FileTransferDialogHelper.configureOpenPanelForAllFileTypes(panel)
        XCTAssertTrue(panel.canChooseFiles,
            "canChooseFiles should remain unchanged")
    }

    func testConfigureDoesNotAlterCanChooseDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        FileTransferDialogHelper.configureOpenPanelForAllFileTypes(panel)
        XCTAssertFalse(panel.canChooseDirectories,
            "canChooseDirectories should remain unchanged")
    }
}

// MARK: - validateReadPermission Tests

class FileTransferReadPermissionTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TeraTermMacTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testReadableFileReturnsTrue() throws {
        let fileURL = tempDir.appendingPathComponent("readable.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: fileURL, on: nil)
        XCTAssertTrue(result, "A readable file should pass validation")
    }

    func testUnreadableFileReturnsFalse() throws {
        let fileURL = tempDir.appendingPathComponent("unreadable.bin")
        try Data([0x00, 0x01, 0x02]).write(to: fileURL)

        // Remove read permission
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: fileURL.path)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: fileURL, on: nil)
        XCTAssertFalse(result, "A file without read permission should fail validation")

        // Restore permissions for cleanup
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
    }

    func testNonExistentFileReturnsFalse() {
        let fileURL = tempDir.appendingPathComponent("does_not_exist.dat")
        let result = FileTransferDialogHelper.validateReadPermission(
            for: fileURL, on: nil)
        XCTAssertFalse(result, "A non-existent file should fail validation")
    }

    func testBinaryFileIsReadable() throws {
        let fileURL = tempDir.appendingPathComponent("data.bin")
        let binaryData = Data(repeating: 0xFF, count: 1024)
        try binaryData.write(to: fileURL)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: fileURL, on: nil)
        XCTAssertTrue(result, "A binary file with read permission should pass")
    }

    func testHiddenFileIsReadable() throws {
        let fileURL = tempDir.appendingPathComponent(".hidden_config")
        try "secret".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: fileURL, on: nil)
        XCTAssertTrue(result, "A hidden file with read permission should pass")
    }

    func testSymlinkToReadableFile() throws {
        let targetURL = tempDir.appendingPathComponent("target.txt")
        try "target content".write(to: targetURL, atomically: true, encoding: .utf8)

        let linkURL = tempDir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: linkURL, on: nil)
        XCTAssertTrue(result, "A symlink to a readable file should pass")
    }

    func testSymlinkToUnreadableFile() throws {
        let targetURL = tempDir.appendingPathComponent("target_noperm.txt")
        try "data".write(to: targetURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: targetURL.path)

        let linkURL = tempDir.appendingPathComponent("link_noperm.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: linkURL, on: nil)
        XCTAssertFalse(result, "A symlink to an unreadable file should fail")

        // Restore for cleanup
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: targetURL.path)
    }

    func testFileWithExecuteOnlyPermission() throws {
        let fileURL = tempDir.appendingPathComponent("exec_only.sh")
        try "#!/bin/sh\necho hello".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o111], ofItemAtPath: fileURL.path)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: fileURL, on: nil)
        XCTAssertFalse(result, "Execute-only file should fail read validation")

        // Restore for cleanup
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
    }

    func testLargeFileIsReadable() throws {
        let fileURL = tempDir.appendingPathComponent("large.dat")
        // Create a 1MB file
        let data = Data(repeating: 0xAB, count: 1024 * 1024)
        try data.write(to: fileURL)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: fileURL, on: nil)
        XCTAssertTrue(result, "A large file with read permission should pass")
    }

    func testFileWithSpecialCharactersInName() throws {
        let fileURL = tempDir.appendingPathComponent("file with spaces & (special).txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: fileURL, on: nil)
        XCTAssertTrue(result, "File with special characters in name should be validated correctly")
    }

    func testFileWithJapaneseNameIsReadable() throws {
        let fileURL = tempDir.appendingPathComponent("テスト転送ファイル.dat")
        try "テストデータ".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: fileURL, on: nil)
        XCTAssertTrue(result, "File with Japanese name should be validated correctly")
    }

    func testEmptyFileIsReadable() throws {
        let fileURL = tempDir.appendingPathComponent("empty.txt")
        try Data().write(to: fileURL)

        let result = FileTransferDialogHelper.validateReadPermission(
            for: fileURL, on: nil)
        XCTAssertTrue(result, "An empty file with read permission should pass")
    }
}

#endif
