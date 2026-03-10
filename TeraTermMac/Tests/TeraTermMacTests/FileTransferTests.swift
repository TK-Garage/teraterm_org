/*
 * FileTransferTests.swift
 * Comprehensive tests for XMODEM, YMODEM, ZMODEM, Kermit file transfer protocols.
 */

import XCTest
@testable import TeraTermMac

// MARK: - Mock File Transfer Delegate

class MockFileTransferDelegate: FileTransferDelegate {
    var stateUpdates: [TransferState] = []
    var sentData: [Data] = []
    var completedFiles: [(String, Int64)] = []
    var errors: [String] = []

    func transferDidUpdateState(_ state: TransferState) {
        stateUpdates.append(state)
    }

    func transferDidRequestSend(_ data: Data) {
        sentData.append(data)
    }

    func transferDidComplete(fileName: String, bytes: Int64) {
        completedFiles.append((fileName, bytes))
    }

    func transferDidFail(error: String) {
        errors.append(error)
    }

    /// All sent data concatenated
    var allSentData: Data {
        sentData.reduce(Data()) { $0 + $1 }
    }

    /// The last state update
    var lastState: TransferState? {
        stateUpdates.last
    }

    func reset() {
        stateUpdates.removeAll()
        sentData.removeAll()
        completedFiles.removeAll()
        errors.removeAll()
    }
}

// MARK: - CRC Utility Tests

class CRCTests: XCTestCase {

    func testCRC16Empty() {
        let result = crc16(Data())
        XCTAssertEqual(result, 0, "CRC-16 of empty data should be 0")
    }

    func testCRC16KnownValues() {
        // CRC-16-CCITT of "123456789" should be 0x29B1
        let data = Data("123456789".utf8)
        let result = crc16(data)
        XCTAssertEqual(result, 0x29B1, "CRC-16 of '123456789' should be 0x29B1")
    }

    func testCRC16SingleByte() {
        let data = Data([0x00])
        let result = crc16(data)
        XCTAssertNotEqual(result, 0, "CRC-16 of single zero byte should not be 0")
    }

    func testCRC16Deterministic() {
        let data = Data([0x41, 0x42, 0x43])
        let a = crc16(data)
        let b = crc16(data)
        XCTAssertEqual(a, b, "CRC-16 should be deterministic")
    }

    func testCRC32Empty() {
        let result = crc32(Data())
        XCTAssertEqual(result, 0, "CRC-32 of empty data should be 0")
    }

    func testCRC32KnownValues() {
        // CRC-32 of "123456789" should be 0xCBF43926
        let data = Data("123456789".utf8)
        let result = crc32(data)
        XCTAssertEqual(result, 0xCBF43926, "CRC-32 of '123456789' should be 0xCBF43926")
    }

    func testCRC32Deterministic() {
        let data = Data(repeating: 0xFF, count: 256)
        let a = crc32(data)
        let b = crc32(data)
        XCTAssertEqual(a, b)
    }
}

// MARK: - Transfer Enums Tests

class TransferEnumTests: XCTestCase {

    func testTransferProtocolTypes() {
        // Verify all protocol types exist
        let types: [TransferProtocolType] = [
            .xmodem, .xmodemCRC, .xmodem1K,
            .ymodem, .ymodemG,
            .zmodem, .kermit
        ]
        XCTAssertEqual(types.count, 7)
    }

    func testTransferDirections() {
        let dirs: [TransferDirection] = [.send, .receive]
        XCTAssertEqual(dirs.count, 2)
    }

    func testTransferStates() {
        // Verify each state variant can be constructed
        let states: [TransferState] = [
            .idle,
            .starting,
            .inProgress(bytesTransferred: 100, totalBytes: 1000, fileName: "test.bin"),
            .inProgress(bytesTransferred: 100, totalBytes: nil, fileName: "test.bin"),
            .completing,
            .completed(fileName: "test.bin", bytes: 1000),
            .failed(error: "test error"),
            .cancelled,
        ]
        XCTAssertEqual(states.count, 8)
    }
}

// MARK: - XMODEM Tests

class XMODEMTests: XCTestCase {

    var delegate: MockFileTransferDelegate!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        delegate = MockFileTransferDelegate()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Receive Tests

    func testXMODEMReceiveStartSendsCForCRCMode() {
        let xm = XMODEMProtocol()
        xm.mode = .crc
        xm.direction = .receive
        xm.delegate = delegate

        xm.start()

        XCTAssertEqual(delegate.sentData.count, 1)
        XCTAssertEqual(delegate.sentData[0], Data([0x43])) // 'C'
    }

    func testXMODEMReceiveStartSendsNAKForChecksumMode() {
        let xm = XMODEMProtocol()
        xm.mode = .checksum
        xm.direction = .receive
        xm.delegate = delegate

        xm.start()

        XCTAssertEqual(delegate.sentData.count, 1)
        XCTAssertEqual(delegate.sentData[0], Data([0x15])) // NAK
    }

    func testXMODEMReceiveValidChecksumBlock() {
        let xm = XMODEMProtocol()
        xm.mode = .checksum
        xm.direction = .receive
        xm.filePath = tempDir.appendingPathComponent("recv.bin").path
        xm.delegate = delegate

        xm.start()
        delegate.reset()

        // Build a valid XMODEM checksum block: SOH + blk(1) + ~blk(0xFE) + 128 bytes + checksum
        var block = Data()
        block.append(0x01) // SOH
        block.append(0x01) // block number 1
        block.append(0xFE) // complement of block number
        let payload = Data(repeating: 0x41, count: 128) // 'A' * 128
        block.append(payload)
        let checksum = payload.reduce(UInt8(0)) { $0 &+ $1 }
        block.append(checksum)

        xm.processData(block)

        // Should have sent ACK
        XCTAssertTrue(delegate.sentData.contains(Data([0x06])), "Should send ACK after valid block")

        // Should have state update with progress
        let hasProgress = delegate.stateUpdates.contains { state in
            if case .inProgress(let bytes, _, _) = state { return bytes == 128 }
            return false
        }
        XCTAssertTrue(hasProgress, "Should report 128 bytes progress")
    }

    func testXMODEMReceiveInvalidChecksumSendsNAK() {
        let xm = XMODEMProtocol()
        xm.mode = .checksum
        xm.direction = .receive
        xm.delegate = delegate

        xm.start()
        delegate.reset()

        var block = Data()
        block.append(0x01) // SOH
        block.append(0x01) // block number
        block.append(0xFE)
        let payload = Data(repeating: 0x41, count: 128)
        block.append(payload)
        block.append(0x00) // Wrong checksum

        xm.processData(block)

        XCTAssertTrue(delegate.sentData.contains(Data([0x15])), "Should send NAK for bad checksum")
    }

    func testXMODEMReceiveValidCRCBlock() {
        let xm = XMODEMProtocol()
        xm.mode = .crc
        xm.direction = .receive
        xm.filePath = tempDir.appendingPathComponent("recv_crc.bin").path
        xm.delegate = delegate

        xm.start()
        delegate.reset()

        let payload = Data(repeating: 0x42, count: 128) // 'B' * 128
        let crcVal = crc16(payload)

        var block = Data()
        block.append(0x01) // SOH
        block.append(0x01) // block 1
        block.append(0xFE)
        block.append(payload)
        block.append(UInt8(crcVal >> 8))
        block.append(UInt8(crcVal & 0xFF))

        xm.processData(block)

        XCTAssertTrue(delegate.sentData.contains(Data([0x06])), "Should ACK valid CRC block")
    }

    func testXMODEMReceiveEOT() {
        let xm = XMODEMProtocol()
        xm.mode = .checksum
        xm.direction = .receive
        xm.filePath = tempDir.appendingPathComponent("recv_eot.bin").path
        xm.delegate = delegate

        xm.start()
        delegate.reset()

        // Send EOT
        xm.processData(Data([0x04]))

        // Should ACK the EOT
        XCTAssertTrue(delegate.sentData.contains(Data([0x06])))

        // Should complete
        let hasCompleted = delegate.stateUpdates.contains { state in
            if case .completed = state { return true }
            return false
        }
        XCTAssertTrue(hasCompleted, "Should complete transfer on EOT")
    }

    func testXMODEMReceiveCAN() {
        let xm = XMODEMProtocol()
        xm.mode = .crc
        xm.direction = .receive
        xm.delegate = delegate

        xm.start()
        delegate.reset()

        xm.processData(Data([0x18])) // CAN

        let hasCancelled = delegate.stateUpdates.contains { state in
            if case .cancelled = state { return true }
            return false
        }
        XCTAssertTrue(hasCancelled, "Should cancel on CAN")
    }

    func testXMODEMReceiveWrongBlockNumberSendsNAK() {
        let xm = XMODEMProtocol()
        xm.mode = .checksum
        xm.direction = .receive
        xm.delegate = delegate

        xm.start()
        delegate.reset()

        let payload = Data(repeating: 0x41, count: 128)
        let checksum = payload.reduce(UInt8(0)) { $0 &+ $1 }

        var block = Data()
        block.append(0x01) // SOH
        block.append(0x02) // block 2 (expected 1!)
        block.append(0xFD) // complement
        block.append(payload)
        block.append(checksum)

        xm.processData(block)

        XCTAssertTrue(delegate.sentData.contains(Data([0x15])), "Should NAK wrong block number")
    }

    func testXMODEMReceiveMultipleBlocks() {
        let xm = XMODEMProtocol()
        xm.mode = .checksum
        xm.direction = .receive
        xm.filePath = tempDir.appendingPathComponent("multi.bin").path
        xm.delegate = delegate

        xm.start()
        delegate.reset()

        // Send 3 blocks then EOT
        for blockNum in 1...3 {
            let payload = Data(repeating: UInt8(blockNum), count: 128)
            let checksum = payload.reduce(UInt8(0)) { $0 &+ $1 }

            var block = Data()
            block.append(0x01)
            block.append(UInt8(blockNum))
            block.append(~UInt8(blockNum))
            block.append(payload)
            block.append(checksum)
            xm.processData(block)
        }

        xm.processData(Data([0x04])) // EOT

        XCTAssertEqual(delegate.completedFiles.count, 1)
        XCTAssertEqual(delegate.completedFiles[0].1, 384) // 3 * 128
    }

    func testXMODEMReceive1KBlock() {
        let xm = XMODEMProtocol()
        xm.mode = .oneK
        xm.direction = .receive
        xm.filePath = tempDir.appendingPathComponent("1k.bin").path
        xm.delegate = delegate

        xm.start()
        delegate.reset()

        let payload = Data(repeating: 0x55, count: 1024)
        let crcVal = crc16(payload)

        var block = Data()
        block.append(0x02) // STX for 1K
        block.append(0x01)
        block.append(0xFE)
        block.append(payload)
        block.append(UInt8(crcVal >> 8))
        block.append(UInt8(crcVal & 0xFF))

        xm.processData(block)
        xm.processData(Data([0x04])) // EOT

        XCTAssertEqual(delegate.completedFiles.count, 1)
        XCTAssertEqual(delegate.completedFiles[0].1, 1024)
    }

    // MARK: - Send Tests

    func testXMODEMSendNoFileFails() {
        let xm = XMODEMProtocol()
        xm.mode = .crc
        xm.direction = .send
        xm.delegate = delegate

        xm.start()

        let hasFailed = delegate.stateUpdates.contains { state in
            if case .failed = state { return true }
            return false
        }
        XCTAssertTrue(hasFailed, "Should fail without file path")
    }

    func testXMODEMSendFile() {
        let filePath = tempDir.appendingPathComponent("send.bin")
        let testData = Data(repeating: 0xAA, count: 256) // 2 blocks
        try! testData.write(to: filePath)

        let xm = XMODEMProtocol()
        xm.mode = .crc
        xm.direction = .send
        xm.filePath = filePath.path
        xm.delegate = delegate

        xm.start()

        // Simulate receiver sending 'C' to start
        xm.processData(Data([0x43]))

        // Should have sent first block
        XCTAssertFalse(delegate.sentData.isEmpty, "Should send first block after 'C'")
        let firstPacket = delegate.sentData.last!
        XCTAssertEqual(firstPacket[0], 0x01, "Should start with SOH")
        XCTAssertEqual(firstPacket[1], 0x01, "Block number should be 1")
        XCTAssertEqual(firstPacket[2], 0xFE, "Block complement should be 0xFE")
        XCTAssertEqual(firstPacket.count, 1 + 2 + 128 + 2, "CRC mode packet size")

        // ACK → next block
        delegate.reset()
        xm.processData(Data([0x06])) // ACK
        XCTAssertFalse(delegate.sentData.isEmpty, "Should send second block after ACK")

        // ACK → should send EOT
        delegate.reset()
        xm.processData(Data([0x06])) // ACK
        XCTAssertTrue(delegate.sentData.contains(Data([0x04])), "Should send EOT after all data")
    }

    func testXMODEMSendPadding() {
        // File shorter than 128 bytes → padded with SUB (0x1A)
        let filePath = tempDir.appendingPathComponent("short.bin")
        let testData = Data([0x41, 0x42, 0x43]) // 3 bytes
        try! testData.write(to: filePath)

        let xm = XMODEMProtocol()
        xm.mode = .checksum
        xm.direction = .send
        xm.filePath = filePath.path
        xm.delegate = delegate

        xm.start()
        xm.processData(Data([0x15])) // NAK to start

        let packet = delegate.sentData.last!
        // Data payload starts at offset 3 and is 128 bytes
        let payload = Data(packet[3..<131])
        XCTAssertEqual(payload[0], 0x41)
        XCTAssertEqual(payload[1], 0x42)
        XCTAssertEqual(payload[2], 0x43)
        // Rest should be SUB padding
        for i in 3..<128 {
            XCTAssertEqual(payload[i], 0x1A, "Byte \(i) should be SUB padding")
        }
    }

    func testXMODEMCancel() {
        let xm = XMODEMProtocol()
        xm.mode = .crc
        xm.direction = .receive
        xm.delegate = delegate

        xm.start()
        delegate.reset()
        xm.cancel()

        XCTAssertTrue(delegate.sentData.contains(Data([0x18, 0x18, 0x18])), "Should send 3x CAN")
    }

    // MARK: - Retry Tests

    func testXMODEMReceiveMaxRetriesExceeded() {
        let xm = XMODEMProtocol()
        xm.mode = .checksum
        xm.direction = .receive
        xm.delegate = delegate

        xm.start()
        delegate.reset()

        // Send 11 blocks with wrong block number to exceed max retries (10)
        let payload = Data(repeating: 0x41, count: 128)
        let checksum = payload.reduce(UInt8(0)) { $0 &+ $1 }

        for _ in 0...10 {
            var block = Data()
            block.append(0x01)
            block.append(0xFF) // Wrong block number
            block.append(0x00) // Wrong complement
            block.append(payload)
            block.append(checksum)
            xm.processData(block)
        }

        let hasFailed = delegate.stateUpdates.contains { state in
            if case .failed(let err) = state { return err.contains("retries") }
            return false
        }
        XCTAssertTrue(hasFailed, "Should fail after too many retries")
    }
}

// MARK: - YMODEM Tests

class YMODEMTests: XCTestCase {

    var delegate: MockFileTransferDelegate!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        delegate = MockFileTransferDelegate()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testYMODEMReceiveStartSendsC() {
        let ym = YMODEMProtocol()
        ym.direction = .receive
        ym.delegate = delegate

        ym.start()

        XCTAssertEqual(delegate.sentData.count, 1)
        XCTAssertEqual(delegate.sentData[0], Data([0x43])) // 'C'
    }

    func testYMODEMReceiveBlock0ParsesFileInfo() {
        let ym = YMODEMProtocol()
        ym.direction = .receive
        ym.filePath = tempDir.appendingPathComponent("recv").path
        ym.delegate = delegate

        ym.start()
        delegate.reset()

        // Build block 0: filename\0size mtime mode\0...padding
        var payload = Data()
        payload.append(Data("testfile.bin".utf8))
        payload.append(0) // NUL
        payload.append(Data("12345 14157745474 100644".utf8))
        payload.append(0) // NUL

        while payload.count < 128 { payload.append(0) }

        let crcVal = crc16(payload)
        var block = Data()
        block.append(0x01) // SOH
        block.append(0x00) // block 0
        block.append(0xFF) // complement
        block.append(payload)
        block.append(UInt8(crcVal >> 8))
        block.append(UInt8(crcVal & 0xFF))

        ym.processData(block)

        // Should send ACK then 'C'
        XCTAssertTrue(delegate.sentData.contains(Data([0x06])), "Should ACK block 0")
        XCTAssertTrue(delegate.sentData.contains(Data([0x43])), "Should send 'C' after ACK")

        // Should report starting progress
        let hasProgress = delegate.stateUpdates.contains { state in
            if case .inProgress(_, _, let name) = state { return name == "testfile.bin" }
            return false
        }
        XCTAssertTrue(hasProgress, "Should report file name from block 0")
    }

    func testYMODEMReceiveEmptyBlock0EndsBatch() {
        let ym = YMODEMProtocol()
        ym.direction = .receive
        ym.filePath = tempDir.appendingPathComponent("recv").path
        ym.delegate = delegate

        ym.start()
        delegate.reset()

        // Empty block 0 (all zeros) signals end of batch
        let payload = Data(repeating: 0, count: 128)
        let crcVal = crc16(payload)

        var block = Data()
        block.append(0x01) // SOH
        block.append(0x00) // block 0
        block.append(0xFF)
        block.append(payload)
        block.append(UInt8(crcVal >> 8))
        block.append(UInt8(crcVal & 0xFF))

        ym.processData(block)

        let hasCompleted = delegate.stateUpdates.contains { state in
            if case .completed = state { return true }
            return false
        }
        XCTAssertTrue(hasCompleted, "Empty block 0 should complete batch")
    }

    func testYMODEMReceiveDataBlockWithFileSizeTrim() {
        let ym = YMODEMProtocol()
        ym.direction = .receive
        ym.filePath = tempDir.appendingPathComponent("trimtest.bin").path
        ym.delegate = delegate

        ym.start()
        delegate.reset()

        // Block 0 with file size = 100 bytes
        var payload0 = Data()
        payload0.append(Data("test.bin".utf8))
        payload0.append(0)
        payload0.append(Data("100".utf8))
        payload0.append(0)
        while payload0.count < 128 { payload0.append(0) }

        let crc0 = crc16(payload0)
        var block0 = Data()
        block0.append(0x01)
        block0.append(0x00)
        block0.append(0xFF)
        block0.append(payload0)
        block0.append(UInt8(crc0 >> 8))
        block0.append(UInt8(crc0 & 0xFF))

        ym.processData(block0)
        delegate.reset()

        // Data block with 128 bytes (but file is only 100 bytes)
        let payload1 = Data(repeating: 0x42, count: 128)
        let crc1 = crc16(payload1)
        var block1 = Data()
        block1.append(0x01) // SOH
        block1.append(0x01) // block 1
        block1.append(0xFE)
        block1.append(payload1)
        block1.append(UInt8(crc1 >> 8))
        block1.append(UInt8(crc1 & 0xFF))

        ym.processData(block1)

        // Should trim to 100 bytes
        let hasProgress = delegate.stateUpdates.contains { state in
            if case .inProgress(let bytes, _, _) = state { return bytes == 100 }
            return false
        }
        XCTAssertTrue(hasProgress, "Should trim data to file size (100 bytes)")
    }

    func testYMODEMSendStartWaitsForC() {
        let filePath = tempDir.appendingPathComponent("send.bin")
        try! Data(repeating: 0xAA, count: 200).write(to: filePath)

        let ym = YMODEMProtocol()
        ym.direction = .send
        ym.filePath = filePath.path
        ym.delegate = delegate

        ym.start()

        // Should be in starting state, no data sent yet
        let hasStarting = delegate.stateUpdates.contains { state in
            if case .starting = state { return true }
            return false
        }
        XCTAssertTrue(hasStarting)
        // No block sent until receiver sends 'C'
        XCTAssertTrue(delegate.sentData.isEmpty, "Should not send until 'C' received")
    }

    func testYMODEMSendBlock0OnC() {
        let filePath = tempDir.appendingPathComponent("send.bin")
        try! Data(repeating: 0xAA, count: 200).write(to: filePath)

        let ym = YMODEMProtocol()
        ym.direction = .send
        ym.filePath = filePath.path
        ym.delegate = delegate

        ym.start()

        // Send 'C' to trigger block 0
        ym.processData(Data([0x43]))

        XCTAssertFalse(delegate.sentData.isEmpty, "Should send block 0 after 'C'")
        let block0 = delegate.sentData[0]
        XCTAssertEqual(block0[0], 0x01, "Block 0 should use SOH")
        XCTAssertEqual(block0[1], 0x00, "Block number should be 0")
        XCTAssertEqual(block0[2], 0xFF, "Complement should be 0xFF")

        // Payload should contain filename
        let payloadStart = 3
        let payload = Data(block0[payloadStart..<(payloadStart + 128)])
        XCTAssertTrue(payload.starts(with: Data("send.bin".utf8)), "Block 0 should contain filename")

        // After filename NUL, should contain file size
        if let nulIdx = payload.firstIndex(of: 0) {
            let afterNul = payload.index(after: nulIdx)
            if afterNul < payload.endIndex {
                let metaStr = String(data: Data(payload[afterNul...]).prefix(while: { $0 != 0 }), encoding: .ascii) ?? ""
                XCTAssertTrue(metaStr.starts(with: "200"), "Block 0 should contain file size")
            }
        }
    }

    func testYMODEMCancelSends5CAN5BS() {
        let ym = YMODEMProtocol()
        ym.direction = .receive
        ym.delegate = delegate

        ym.start()
        delegate.reset()
        ym.cancel()

        let cancelData = delegate.allSentData
        XCTAssertEqual(cancelData.count, 10, "Cancel should be 5 CAN + 5 BS")
        for i in 0..<5 {
            XCTAssertEqual(cancelData[i], 0x18, "First 5 bytes should be CAN")
        }
        for i in 5..<10 {
            XCTAssertEqual(cancelData[i], 0x08, "Last 5 bytes should be BS")
        }
    }

    func testYMODEMEOTHandshake() {
        let ym = YMODEMProtocol()
        ym.direction = .receive
        ym.filePath = tempDir.appendingPathComponent("eot.bin").path
        ym.delegate = delegate

        ym.start()

        // Send block 0
        var payload0 = Data("test.bin".utf8)
        payload0.append(0)
        payload0.append(Data("128".utf8))
        payload0.append(0)
        while payload0.count < 128 { payload0.append(0) }
        let crc0 = crc16(payload0)
        var block0 = Data()
        block0.append(0x01); block0.append(0x00); block0.append(0xFF)
        block0.append(payload0)
        block0.append(UInt8(crc0 >> 8)); block0.append(UInt8(crc0 & 0xFF))
        ym.processData(block0)

        // Send data block
        let payload1 = Data(repeating: 0x42, count: 128)
        let crc1 = crc16(payload1)
        var block1 = Data()
        block1.append(0x01); block1.append(0x01); block1.append(0xFE)
        block1.append(payload1)
        block1.append(UInt8(crc1 >> 8)); block1.append(UInt8(crc1 & 0xFF))
        ym.processData(block1)
        delegate.reset()

        // First EOT → should NAK
        ym.processData(Data([0x04]))
        XCTAssertTrue(delegate.sentData.contains(Data([0x15])), "Should NAK first EOT")
        delegate.reset()

        // Second EOT → should ACK
        ym.processData(Data([0x04]))
        XCTAssertTrue(delegate.sentData.contains(Data([0x06])), "Should ACK second EOT")
    }
}

// MARK: - ZMODEM Tests

class ZMODEMTests: XCTestCase {

    var delegate: MockFileTransferDelegate!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        delegate = MockFileTransferDelegate()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testZMODEMReceiveStart() {
        let zm = ZMODEMProtocol()
        zm.direction = .receive
        zm.delegate = delegate

        zm.start()

        // Should send ZRINIT header
        XCTAssertFalse(delegate.sentData.isEmpty, "Should send ZRINIT on receive start")

        let header = delegate.allSentData
        // ZRINIT header starts with ZPAD ZPAD ZDLE ZHEX
        XCTAssertTrue(header.contains(0x2A), "Header should contain ZPAD (0x2A)")

        let hasStarting = delegate.stateUpdates.contains { state in
            if case .starting = state { return true }
            return false
        }
        XCTAssertTrue(hasStarting, "Should enter starting state")
    }

    func testZMODEMSendStartNoFile() {
        let zm = ZMODEMProtocol()
        zm.direction = .send
        zm.delegate = delegate

        zm.start()

        let hasFailed = delegate.stateUpdates.contains { state in
            if case .failed = state { return true }
            return false
        }
        XCTAssertTrue(hasFailed, "Should fail without file path")
    }

    func testZMODEMSendStartValidFile() {
        let filePath = tempDir.appendingPathComponent("test.bin")
        try! Data(repeating: 0x55, count: 100).write(to: filePath)

        let zm = ZMODEMProtocol()
        zm.direction = .send
        zm.filePath = filePath.path
        zm.delegate = delegate

        zm.start()

        // Should send ZRQINIT header
        XCTAssertFalse(delegate.sentData.isEmpty, "Should send ZRQINIT")

        let hasStarting = delegate.stateUpdates.contains { state in
            if case .starting = state { return true }
            return false
        }
        XCTAssertTrue(hasStarting)
    }

    func testZMODEMSendNonExistentFile() {
        let zm = ZMODEMProtocol()
        zm.direction = .send
        zm.filePath = "/nonexistent/file.bin"
        zm.delegate = delegate

        zm.start()

        let hasFailed = delegate.stateUpdates.contains { state in
            if case .failed(let err) = state { return err.contains("not found") }
            return false
        }
        XCTAssertTrue(hasFailed)
    }

    func testZMODEMHexHeaderFormat() {
        let zm = ZMODEMProtocol()
        zm.direction = .receive
        zm.delegate = delegate

        zm.start()

        let header = delegate.allSentData
        // Check ZPAD ZPAD ZDLE ZHEX sequence
        XCTAssertTrue(header.count >= 4, "Header should have at least 4 bytes")
        XCTAssertEqual(header[0], 0x2A) // ZPAD
        XCTAssertEqual(header[1], 0x2A) // ZPAD
        XCTAssertEqual(header[2], 0x18) // ZDLE
        XCTAssertEqual(header[3], 0x42) // ZHEX
    }

    func testZMODEMAutoDetect() {
        // Test the ZMODEM auto-detection sequence
        let data1 = Data([0x2A, 0x2A, 0x18, 0x42, 0x30, 0x30])
        XCTAssertTrue(ZMODEMProtocol.detectZMODEM(in: data1), "Should detect ZMODEM in data")

        let data2 = Data([0x41, 0x42, 0x43])
        XCTAssertFalse(ZMODEMProtocol.detectZMODEM(in: data2), "Should not detect ZMODEM in random data")

        let data3 = Data([0x2A, 0x2A])
        XCTAssertFalse(ZMODEMProtocol.detectZMODEM(in: data3), "Should not detect incomplete sequence")
    }

    func testZMODEMCancel() {
        let zm = ZMODEMProtocol()
        zm.direction = .receive
        zm.delegate = delegate

        zm.start()
        delegate.reset()
        zm.cancel()

        let cancelData = delegate.allSentData
        // Should send 8x ZDLE (0x18) + 10x BS (0x08)
        XCTAssertEqual(cancelData.count, 18, "Cancel should be 8 ZDLE + 10 BS")
        for i in 0..<8 {
            XCTAssertEqual(cancelData[i], 0x18, "First 8 bytes should be ZDLE/CAN")
        }
        for i in 8..<18 {
            XCTAssertEqual(cancelData[i], 0x08, "Last 10 bytes should be BS")
        }
    }

    func testZMODEMAutoDetectInManager() {
        let manager = FileTransferManager()
        manager.delegate = delegate

        let savePath = tempDir.appendingPathComponent("auto_recv.bin").path

        // Should not auto-detect random data
        let random = Data([0x41, 0x42, 0x43])
        XCTAssertFalse(manager.checkAutoDetect(random, savePath: savePath))
        XCTAssertFalse(manager.isTransferActive)

        // Should auto-detect ZMODEM initiation
        let zmodemInit = Data([0x2A, 0x2A, 0x18, 0x42, 0x30, 0x31, 0x30, 0x30])
        XCTAssertTrue(manager.checkAutoDetect(zmodemInit, savePath: savePath))
        XCTAssertTrue(manager.isTransferActive)

        manager.cancelTransfer()
    }
}

// MARK: - Kermit Tests

class KermitTests: XCTestCase {

    var delegate: MockFileTransferDelegate!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        delegate = MockFileTransferDelegate()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testKermitSendStart() {
        let km = KermitProtocol()
        km.direction = .send
        km.filePath = tempDir.appendingPathComponent("test.txt").path
        km.delegate = delegate

        km.start()

        // Should send Send-Init (S) packet
        XCTAssertFalse(delegate.sentData.isEmpty, "Should send init packet")
        let packet = delegate.sentData[0]
        XCTAssertEqual(packet[0], 0x01, "Should start with MARK/SOH")
        XCTAssertEqual(packet[3], UInt8(Character("S").asciiValue!), "Type should be 'S'")
    }

    func testKermitReceiveStart() {
        let km = KermitProtocol()
        km.direction = .receive
        km.delegate = delegate

        km.start()

        let hasStarting = delegate.stateUpdates.contains { state in
            if case .starting = state { return true }
            return false
        }
        XCTAssertTrue(hasStarting, "Should enter starting state")
    }

    func testKermitHandleSendInit() {
        let km = KermitProtocol()
        km.direction = .receive
        km.delegate = delegate

        km.start()
        delegate.reset()

        // Build a Send-Init (S) packet
        let initData = buildKermitInitData()
        let packet = buildKermitPacket(seq: 0, type: "S", data: initData)

        km.processData(packet)

        // Should respond with ACK (Y) packet
        XCTAssertFalse(delegate.sentData.isEmpty, "Should send ACK to Send-Init")
        let ackPacket = delegate.sentData[0]
        XCTAssertEqual(ackPacket[3], UInt8(Character("Y").asciiValue!), "Should send 'Y' (ACK)")
    }

    func testKermitHandleFileHeader() {
        let km = KermitProtocol()
        km.direction = .receive
        km.filePath = tempDir.appendingPathComponent("recv.txt").path
        km.fileHandle = FileHandle(forWritingAtPath: km.filePath!)
        km.delegate = delegate

        km.start()

        // First: Send-Init
        let initPacket = buildKermitPacket(seq: 0, type: "S", data: buildKermitInitData())
        km.processData(initPacket)

        delegate.reset()

        // Then: File-Header with filename "hello.txt"
        let filePacket = buildKermitPacket(seq: 1, type: "F", data: Data("hello.txt".utf8))
        km.processData(filePacket)

        // Should ACK the file header
        XCTAssertFalse(delegate.sentData.isEmpty)
    }

    func testKermitHandleDataPacket() {
        let km = KermitProtocol()
        km.direction = .receive
        let recvPath = tempDir.appendingPathComponent("data.bin")
        FileManager.default.createFile(atPath: recvPath.path, contents: nil)
        km.filePath = recvPath.path
        km.fileHandle = FileHandle(forWritingAtPath: recvPath.path)
        km.delegate = delegate

        km.start()

        // Send-Init
        km.processData(buildKermitPacket(seq: 0, type: "S", data: buildKermitInitData()))
        // File-Header
        km.processData(buildKermitPacket(seq: 1, type: "F", data: Data("test.bin".utf8)))

        delegate.reset()

        // Data packet
        let fileContent = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"
        km.processData(buildKermitPacket(seq: 2, type: "D", data: fileContent))

        // Should report progress
        let hasProgress = delegate.stateUpdates.contains { state in
            if case .inProgress(let bytes, _, _) = state { return bytes > 0 }
            return false
        }
        XCTAssertTrue(hasProgress, "Should report progress after data packet")
    }

    func testKermitHandleBreak() {
        let km = KermitProtocol()
        km.direction = .receive
        km.delegate = delegate

        km.start()

        // Send-Init → File → EOF → Break
        km.processData(buildKermitPacket(seq: 0, type: "S", data: buildKermitInitData()))
        km.processData(buildKermitPacket(seq: 1, type: "F", data: Data("test.bin".utf8)))
        km.processData(buildKermitPacket(seq: 2, type: "Z", data: Data()))
        delegate.reset()
        km.processData(buildKermitPacket(seq: 3, type: "B", data: Data()))

        let hasCompleted = delegate.stateUpdates.contains { state in
            if case .completed = state { return true }
            return false
        }
        XCTAssertTrue(hasCompleted, "Should complete on Break packet")
        XCTAssertEqual(delegate.completedFiles.count, 1)
    }

    func testKermitHandleError() {
        let km = KermitProtocol()
        km.direction = .receive
        km.delegate = delegate

        km.start()
        delegate.reset()

        let errorMsg = Data("Remote error".utf8)
        km.processData(buildKermitPacket(seq: 0, type: "E", data: errorMsg))

        let hasFailed = delegate.stateUpdates.contains { state in
            if case .failed = state { return true }
            return false
        }
        XCTAssertTrue(hasFailed, "Should fail on Error packet")
    }

    func testKermitDecodeControlCharEscaping() {
        let km = KermitProtocol()
        km.direction = .receive
        let recvPath = tempDir.appendingPathComponent("escaped.bin")
        FileManager.default.createFile(atPath: recvPath.path, contents: nil)
        km.filePath = recvPath.path
        km.fileHandle = FileHandle(forWritingAtPath: recvPath.path)
        km.delegate = delegate

        km.start()
        km.processData(buildKermitPacket(seq: 0, type: "S", data: buildKermitInitData()))
        km.processData(buildKermitPacket(seq: 1, type: "F", data: Data("esc.bin".utf8)))

        delegate.reset()

        // Data with control char escaping: #M → 0x0D (CR), #J → 0x0A (LF)
        let escapedData = Data([0x23, 0x4D, 0x23, 0x4A, 0x41]) // #M #J A
        km.processData(buildKermitPacket(seq: 2, type: "D", data: escapedData))

        let hasProgress = delegate.stateUpdates.contains { state in
            if case .inProgress(let bytes, _, _) = state { return bytes == 3 } // CR + LF + A
            return false
        }
        XCTAssertTrue(hasProgress, "Decoded data should be 3 bytes (CR, LF, A)")
    }

    func testKermitCancel() {
        let km = KermitProtocol()
        km.direction = .receive
        km.delegate = delegate

        km.start()
        delegate.reset()
        km.cancel()

        // Should send Error (E) packet
        let packet = delegate.sentData.last!
        XCTAssertEqual(packet[3], UInt8(Character("E").asciiValue!), "Cancel should send Error packet")
    }

    // MARK: - Helper Methods

    private func buildKermitInitData() -> Data {
        var data = Data()
        data.append(UInt8(94 + 32))   // MAXL
        data.append(UInt8(5 + 32))    // TIME
        data.append(UInt8(0 + 32))    // NPAD
        data.append(0)                // PADC
        data.append(UInt8(13 + 32))   // EOL
        data.append(UInt8(Character("#").asciiValue!))  // QCTL
        data.append(UInt8(Character("N").asciiValue!))  // QBIN
        data.append(UInt8(Character("1").asciiValue!))  // CHKT
        data.append(UInt8(Character(" ").asciiValue!))  // REPT
        return data
    }

    private func buildKermitPacket(seq: Int, type: String, data: Data) -> Data {
        var packet = Data()
        packet.append(0x01) // MARK/SOH
        packet.append(UInt8(data.count + 3 + 32)) // LEN
        packet.append(UInt8(seq + 32))              // SEQ
        packet.append(UInt8(Character(type).asciiValue!)) // TYPE
        packet.append(data)
        // Checksum (type 1: single-byte)
        let checksum = packet[1...].reduce(0) { ($0 + Int($1)) } % 256
        packet.append(UInt8((checksum + (checksum >> 6)) & 0x3F + 32))
        packet.append(0x0D) // EOL
        return packet
    }
}

// MARK: - FileTransferManager Tests

class FileTransferManagerTests: XCTestCase {

    var delegate: MockFileTransferDelegate!
    var manager: FileTransferManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        delegate = MockFileTransferDelegate()
        manager = FileTransferManager()
        manager.delegate = delegate
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testIsTransferActiveInitially() {
        XCTAssertFalse(manager.isTransferActive)
    }

    func testStartXMODEMTransfer() {
        let filePath = tempDir.appendingPathComponent("recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        manager.startTransfer(protocol: .xmodemCRC, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(manager.isTransferActive)
    }

    func testStartXMODEMChecksumTransfer() {
        let filePath = tempDir.appendingPathComponent("recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        manager.startTransfer(protocol: .xmodem, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(manager.isTransferActive)
    }

    func testStartXMODEM1KTransfer() {
        let filePath = tempDir.appendingPathComponent("recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        manager.startTransfer(protocol: .xmodem1K, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(manager.isTransferActive)
    }

    func testStartZMODEMTransfer() {
        let filePath = tempDir.appendingPathComponent("recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        manager.startTransfer(protocol: .zmodem, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(manager.isTransferActive)
    }

    func testStartKermitTransfer() {
        let filePath = tempDir.appendingPathComponent("recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        manager.startTransfer(protocol: .kermit, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(manager.isTransferActive)
    }

    func testStartYMODEMTransfer() {
        let filePath = tempDir.appendingPathComponent("recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        manager.startTransfer(protocol: .ymodem, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(manager.isTransferActive)
    }

    func testStartYMODEMGTransfer() {
        let filePath = tempDir.appendingPathComponent("recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        manager.startTransfer(protocol: .ymodemG, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(manager.isTransferActive)
    }

    func testCancelTransfer() {
        let filePath = tempDir.appendingPathComponent("recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        manager.startTransfer(protocol: .xmodemCRC, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(manager.isTransferActive)

        manager.cancelTransfer()
        XCTAssertFalse(manager.isTransferActive)
    }

    func testProcessIncomingData() {
        let filePath = tempDir.appendingPathComponent("recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        manager.startTransfer(protocol: .xmodemCRC, direction: .receive, filePath: filePath.path)

        // Feed EOT
        manager.processIncomingData(Data([0x04]))

        // Should have completed
        let hasCompleted = delegate.stateUpdates.contains { state in
            if case .completed = state { return true }
            return false
        }
        XCTAssertTrue(hasCompleted)
    }

    func testSendTransferCreatesFileHandle() {
        let filePath = tempDir.appendingPathComponent("send.bin")
        try! Data(repeating: 0xBB, count: 64).write(to: filePath)

        manager.startTransfer(protocol: .xmodemCRC, direction: .send, filePath: filePath.path)
        XCTAssertTrue(manager.isTransferActive)
    }

    func testAllProtocolTypesCreateTransfer() {
        let types: [TransferProtocolType] = [
            .xmodem, .xmodemCRC, .xmodem1K,
            .ymodem, .ymodemG,
            .zmodem, .kermit
        ]

        for protocolType in types {
            let filePath = tempDir.appendingPathComponent("test_\(protocolType).bin")
            FileManager.default.createFile(atPath: filePath.path, contents: nil)

            let mgr = FileTransferManager()
            mgr.delegate = delegate
            mgr.startTransfer(protocol: protocolType, direction: .receive, filePath: filePath.path)
            XCTAssertTrue(mgr.isTransferActive, "Transfer should be active for \(protocolType)")
            mgr.cancelTransfer()
        }
    }

    func testYMODEMBatchSend() {
        let files = (1...3).map { i -> String in
            let path = tempDir.appendingPathComponent("file\(i).bin")
            try! Data(repeating: UInt8(i), count: 100).write(to: path)
            return path.path
        }

        manager.startYMODEMBatchSend(filePaths: files)
        XCTAssertTrue(manager.isTransferActive, "Batch send should be active")
        manager.cancelTransfer()
    }
}

// MARK: - XMODEM Integration: Send → Receive Loopback

class XMODEMLoopbackTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Simulate a full XMODEM transfer by wiring sender ↔ receiver
    func testXMODEMFullLoopbackChecksum() {
        let srcPath = tempDir.appendingPathComponent("src.bin")
        let dstPath = tempDir.appendingPathComponent("dst.bin")
        let testData = Data((0..<256).map { UInt8($0 % 256) }) // 256 bytes = 2 blocks
        try! testData.write(to: srcPath)

        let sender = XMODEMProtocol()
        sender.mode = .checksum
        sender.direction = .send
        sender.filePath = srcPath.path
        sender.fileHandle = FileHandle(forReadingAtPath: srcPath.path)

        let receiver = XMODEMProtocol()
        receiver.mode = .checksum
        receiver.direction = .receive
        receiver.filePath = dstPath.path

        let senderDelegate = MockFileTransferDelegate()
        let receiverDelegate = MockFileTransferDelegate()
        sender.delegate = senderDelegate
        receiver.delegate = receiverDelegate

        // Start receiver → sends NAK
        receiver.start()

        // Feed receiver's output to sender
        for data in receiverDelegate.sentData {
            sender.processData(data)
        }
        receiverDelegate.reset()

        // Loop: sender sends block → receiver processes → sends ACK → sender processes
        for _ in 0..<10 {
            // Forward sender output to receiver
            let senderOutput = senderDelegate.sentData
            senderDelegate.reset()
            for data in senderOutput {
                receiver.processData(data)
            }

            // Forward receiver output to sender
            let receiverOutput = receiverDelegate.sentData
            receiverDelegate.reset()
            for data in receiverOutput {
                sender.processData(data)
            }

            // Check if completed
            let senderCompleted = senderDelegate.stateUpdates.contains { s in
                if case .completing = s { return true }
                if case .completed = s { return true }
                return false
            }
            let receiverCompleted = receiverDelegate.stateUpdates.contains { s in
                if case .completed = s { return true }
                return false
            }
            if senderCompleted && receiverCompleted { break }
        }

        // Verify the received file matches (first 256 bytes, ignoring padding)
        if let receivedData = try? Data(contentsOf: dstPath) {
            XCTAssertTrue(receivedData.count >= 256, "Received file should have at least 256 bytes")
            XCTAssertEqual(Data(receivedData.prefix(256)), testData, "Received data should match sent data")
        } else {
            XCTFail("Received file should exist")
        }
    }

    func testXMODEMFullLoopbackCRC() {
        let srcPath = tempDir.appendingPathComponent("src_crc.bin")
        let dstPath = tempDir.appendingPathComponent("dst_crc.bin")
        let testData = Data(repeating: 0x42, count: 128) // Exactly 1 block
        try! testData.write(to: srcPath)

        let sender = XMODEMProtocol()
        sender.mode = .crc
        sender.direction = .send
        sender.filePath = srcPath.path
        sender.fileHandle = FileHandle(forReadingAtPath: srcPath.path)

        let receiver = XMODEMProtocol()
        receiver.mode = .crc
        receiver.direction = .receive
        receiver.filePath = dstPath.path

        let senderDelegate = MockFileTransferDelegate()
        let receiverDelegate = MockFileTransferDelegate()
        sender.delegate = senderDelegate
        receiver.delegate = receiverDelegate

        receiver.start()

        for data in receiverDelegate.sentData {
            sender.processData(data)
        }
        receiverDelegate.reset()

        for _ in 0..<10 {
            let sOut = senderDelegate.sentData
            senderDelegate.reset()
            for d in sOut { receiver.processData(d) }

            let rOut = receiverDelegate.sentData
            receiverDelegate.reset()
            for d in rOut { sender.processData(d) }

            let done = receiverDelegate.stateUpdates.contains { s in
                if case .completed = s { return true }
                return false
            }
            if done { break }
        }

        if let receivedData = try? Data(contentsOf: dstPath) {
            XCTAssertEqual(Data(receivedData.prefix(128)), testData)
        } else {
            XCTFail("Received file should exist")
        }
    }
}
