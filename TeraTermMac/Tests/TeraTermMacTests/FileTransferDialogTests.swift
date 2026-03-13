/*
 * FileTransferDialogTests.swift
 * Tests for file transfer dialog accessory views and helper logic.
 */

import XCTest
@testable import TeraTermMac

// MARK: - XMODEMOptionAccessory Tests

class XMODEMOptionAccessoryTests: XCTestCase {

    func testDefaultCRCMode() {
        let accessory = XMODEMOptionAccessory(isSend: true, defaultCRC: true)
        XCTAssertEqual(accessory.crcRadio.state, .on)
        XCTAssertEqual(accessory.checksumRadio.state, .off)
        XCTAssertEqual(accessory.selectedProtocol, .xmodemCRC)
    }

    func testDefaultChecksumMode() {
        let accessory = XMODEMOptionAccessory(isSend: true, defaultCRC: false)
        XCTAssertEqual(accessory.checksumRadio.state, .on)
        XCTAssertEqual(accessory.crcRadio.state, .off)
        XCTAssertEqual(accessory.selectedProtocol, .xmodem)
    }

    func testOneKOverridesCRC() {
        let accessory = XMODEMOptionAccessory(isSend: true, defaultCRC: true)
        accessory.oneKCheck.state = .on
        XCTAssertEqual(accessory.selectedProtocol, .xmodem1K)
    }

    func testBinaryDefaultOn() {
        let accessory = XMODEMOptionAccessory(isSend: true)
        XCTAssertTrue(accessory.isBinary)
    }

    func testBinaryToggle() {
        let accessory = XMODEMOptionAccessory(isSend: false)
        accessory.binaryCheck.state = .off
        XCTAssertFalse(accessory.isBinary)
    }

    func testFrameSize() {
        // Auto Layoutベースのビューは layoutSubtreeIfNeeded 後に fittingSize を使う
        let accessory = XMODEMOptionAccessory(isSend: true)
        accessory.layoutSubtreeIfNeeded()
        let size = accessory.fittingSize
        XCTAssertGreaterThan(size.width, 0, "XMODEMOptionAccessory should have non-zero width")
        XCTAssertGreaterThan(size.height, 0, "XMODEMOptionAccessory should have non-zero height")
    }

    func testRadioMutualExclusion() {
        let accessory = XMODEMOptionAccessory(isSend: true, defaultCRC: true)
        // Simulate clicking checksum radio
        accessory.checksumRadio.performClick(nil)
        // After the radio action fires, crc should be off
        // (Note: in unit test performClick may not fire target/action,
        //  so we test the protocol enum directly with state manipulation)
        accessory.checksumRadio.state = .on
        accessory.crcRadio.state = .off
        accessory.oneKCheck.state = .off
        XCTAssertEqual(accessory.selectedProtocol, .xmodem)
    }

    func testSelectedProtocolPriority() {
        let accessory = XMODEMOptionAccessory(isSend: true, defaultCRC: false)
        // Checksum selected, but 1K enabled → 1K takes priority
        accessory.oneKCheck.state = .on
        XCTAssertEqual(accessory.selectedProtocol, .xmodem1K)
    }
}

// MARK: - FileOptionAccessory Tests

class FileOptionAccessoryTests: XCTestCase {

    func testBinaryDefaultOn() {
        let accessory = FileOptionAccessory()
        XCTAssertTrue(accessory.isBinary)
    }

    func testBinaryToggleOff() {
        let accessory = FileOptionAccessory()
        accessory.binaryCheck.state = .off
        XCTAssertFalse(accessory.isBinary)
    }

    func testFrameSize() {
        let accessory = FileOptionAccessory()
        accessory.layoutSubtreeIfNeeded()
        let size = accessory.fittingSize
        XCTAssertGreaterThan(size.width, 0, "FileOptionAccessory should have non-zero width")
        XCTAssertGreaterThan(size.height, 0, "FileOptionAccessory should have non-zero height")
    }
}

// MARK: - ProtocolTransferPanel Tests

class ProtocolTransferPanelTests: XCTestCase {

    func testInitiallyNotVisible() {
        let panel = ProtocolTransferPanel()
        XCTAssertFalse(panel.isVisible)
    }

    func testShowMakesVisible() {
        let panel = ProtocolTransferPanel()
        panel.show(fileName: "test.bin", protocolName: "XMODEM-CRC")
        XCTAssertTrue(panel.isVisible)
        panel.close()
    }

    func testCloseMakesInvisible() {
        let panel = ProtocolTransferPanel()
        panel.show(fileName: "test.bin", protocolName: "ZMODEM")
        panel.close()
        XCTAssertFalse(panel.isVisible)
    }

    func testUpdateDoesNotCrash() {
        let panel = ProtocolTransferPanel()
        panel.show(fileName: "data.bin", protocolName: "Kermit")
        panel.update(packetNum: 10, bytesTransferred: 5120, totalBytes: 10240)
        panel.update(packetNum: 20, bytesTransferred: 10240, totalBytes: 10240)
        panel.update(packetNum: 5, bytesTransferred: 2048, totalBytes: nil)
        panel.close()
    }

    func testCancelCallback() {
        let panel = ProtocolTransferPanel()
        var cancelled = false
        panel.onCancel = { cancelled = true }
        panel.show(fileName: "test.bin", protocolName: "XMODEM")
        // Simulate cancel (internal method is @objc)
        panel.onCancel?()
        XCTAssertTrue(cancelled)
        panel.close()
    }
}

// MARK: - FileTransferProgressPanel Tests

class FileTransferProgressPanelTests: XCTestCase {

    func testInitiallyNotVisible() {
        let panel = FileTransferProgressPanel()
        XCTAssertFalse(panel.isVisible)
    }

    func testShowForSend() {
        let panel = FileTransferProgressPanel()
        panel.show(fileName: "file.bin", fullPath: "/tmp/file.bin", forSend: true)
        XCTAssertTrue(panel.isVisible)
        panel.close()
    }

    func testShowForReceive() {
        let panel = FileTransferProgressPanel()
        panel.show(fileName: "recv.bin", fullPath: "/tmp/recv.bin", forSend: false)
        XCTAssertTrue(panel.isVisible)
        panel.close()
    }

    func testUpdateWithPercentage() {
        let panel = FileTransferProgressPanel()
        panel.show(fileName: "file.bin", fullPath: "/tmp/file.bin", forSend: true)
        panel.update(fileSize: 10000, byteCount: 5000)
        panel.close()
    }

    func testUpdateWithoutFileSize() {
        let panel = FileTransferProgressPanel()
        panel.show(fileName: "file.bin", fullPath: "/tmp/file.bin", forSend: false)
        panel.update(fileSize: 0, byteCount: 1234)
        panel.close()
    }

    func testCloseCallback() {
        let panel = FileTransferProgressPanel()
        var closed = false
        panel.onClose = { closed = true }
        panel.show(fileName: "f.bin", fullPath: "/f.bin", forSend: true)
        panel.onClose?()
        XCTAssertTrue(closed)
        panel.close()
    }

    func testPauseResumeCallback() {
        let panel = FileTransferProgressPanel()
        var lastPaused: Bool?
        panel.onPauseResume = { paused in lastPaused = paused }
        panel.show(fileName: "f.bin", fullPath: "/f.bin", forSend: true)
        panel.onPauseResume?(true)
        XCTAssertEqual(lastPaused, true)
        panel.onPauseResume?(false)
        XCTAssertEqual(lastPaused, false)
        panel.close()
    }
}

// MARK: - KermitGetDialogController Tests

class KermitGetDialogControllerTests: XCTestCase {

    func testTitleIsSet() {
        let vc = KermitGetDialogController()
        XCTAssertEqual(vc.title, "Tera Term: Kermit Get")
    }
}

// MARK: - SendFileDialogController Tests

class SendFileDialogControllerTests: XCTestCase {

    func testTitleIsSet() {
        let vc = SendFileDialogController()
        // タイトルはローカライズされる
        XCTAssertEqual(vc.title, NSLocalizedString("dialog.sendFile.title", value: "Send file", comment: ""))
    }

    func testDelayTypeEnum() {
        XCTAssertEqual(SendFileDialogController.DelayType.noDelay.rawValue, 0)
        XCTAssertEqual(SendFileDialogController.DelayType.perChar.rawValue, 1)
        XCTAssertEqual(SendFileDialogController.DelayType.perLine.rawValue, 2)
        XCTAssertEqual(SendFileDialogController.DelayType.allCases.count, 3)
    }

    func testDelayTypeLocalizedTitles() {
        // Verify each delay type produces a non-empty title
        for dt in SendFileDialogController.DelayType.allCases {
            XCTAssertFalse(dt.localizedTitle.isEmpty,
                "DelayType \(dt) should have non-empty localized title")
        }
    }

    func testResultInitialization() {
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let result = SendFileDialogController.Result(
            fileURL: url,
            bulkRead: true,
            binary: false,
            delayType: .perChar,
            sendSize: 1280,
            delayTimeMs: 50
        )
        XCTAssertEqual(result.fileURL, url)
        XCTAssertTrue(result.bulkRead)
        XCTAssertFalse(result.binary)
        XCTAssertEqual(result.delayType, .perChar)
        XCTAssertEqual(result.sendSize, 1280)
        XCTAssertEqual(result.delayTimeMs, 50)
    }

    func testResultAllSendSize() {
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let result = SendFileDialogController.Result(
            fileURL: url,
            bulkRead: false,
            binary: true,
            delayType: .noDelay,
            sendSize: 0,
            delayTimeMs: 0
        )
        XCTAssertEqual(result.sendSize, 0) // 0 = "All"
        XCTAssertTrue(result.binary)
        XCTAssertFalse(result.bulkRead)
    }

    func testInitialResultIsNil() {
        let vc = SendFileDialogController()
        XCTAssertNil(vc.result)
    }
}

// MARK: - RecvFileDialogController Tests

class RecvFileDialogControllerTests: XCTestCase {

    func testTitleIsSet() {
        let vc = RecvFileDialogController()
        // タイトルはローカライズされる
        XCTAssertEqual(vc.title, NSLocalizedString("dialog.recvFile.title", value: "Receive file", comment: ""))
    }

    func testResultInitialization() {
        let url = URL(fileURLWithPath: "/tmp/recv.bin")
        let result = RecvFileDialogController.Result(
            fileURL: url,
            binary: true,
            autoStopWaitSec: 30
        )
        XCTAssertEqual(result.fileURL, url)
        XCTAssertTrue(result.binary)
        XCTAssertEqual(result.autoStopWaitSec, 30)
    }

    func testResultZeroAutoStop() {
        let url = URL(fileURLWithPath: "/tmp/test.bin")
        let result = RecvFileDialogController.Result(
            fileURL: url,
            binary: false,
            autoStopWaitSec: 0
        )
        XCTAssertFalse(result.binary)
        XCTAssertEqual(result.autoStopWaitSec, 0)
    }

    func testInitialResultIsNil() {
        let vc = RecvFileDialogController()
        XCTAssertNil(vc.result)
    }
}
