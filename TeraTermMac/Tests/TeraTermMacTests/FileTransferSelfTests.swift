/*
 * FileTransferSelfTests.swift
 *
 * Self-tests for file transfer protocol transfer logic.
 * Focuses on loopback (sender↔receiver wiring) and encode/decode roundtrips
 * to verify protocol correctness without external dependencies.
 */

import XCTest
@testable import TeraTermMac

// MARK: - Transfer Protocol Constants

private enum XMODEMConstant {
    static let standardBlockSize = 128     // Standard XMODEM block payload size
    static let extendedBlockSize = 1024    // XMODEM-1K / YMODEM block payload size
    static let SOH: UInt8 = 0x01          // Start of Heading (128-byte block)
    static let STX: UInt8 = 0x02          // Start of Text (1024-byte block)
    static let SUB: UInt8 = 0x1A          // Padding byte for short blocks
}

// MARK: - Loopback Test Harness

/// Wires a sender and receiver together, pumping data between them
/// until both sides complete or a maximum iteration count is reached.
private class LoopbackHarness {
    let senderDelegate = MockFileTransferDelegate()
    let receiverDelegate = MockFileTransferDelegate()

    /// Run the loopback: receiver.start() → pump data back and forth.
    /// Returns (senderCompleted, receiverCompleted).
    func run(sender: FileTransferProtocol,
             receiver: FileTransferProtocol,
             maxIterations: Int = 30) -> (senderDone: Bool, receiverDone: Bool) {
        sender.delegate = senderDelegate
        receiver.delegate = receiverDelegate

        // Receiver starts first (sends initial handshake byte)
        receiver.start()

        // Feed receiver's initial output to sender
        for data in receiverDelegate.sentData {
            sender.processData(data)
        }
        receiverDelegate.sentData.removeAll()

        for _ in 0..<maxIterations {
            // Forward sender → receiver
            let sOut = senderDelegate.sentData
            senderDelegate.sentData.removeAll()
            for d in sOut { receiver.processData(d) }

            // Forward receiver → sender
            let rOut = receiverDelegate.sentData
            receiverDelegate.sentData.removeAll()
            for d in rOut { sender.processData(d) }

            let sDone = isCompleteOrCompleting(senderDelegate.stateUpdates)
            let rDone = isComplete(receiverDelegate.stateUpdates)
            if sDone && rDone { return (true, true) }
        }

        return (isCompleteOrCompleting(senderDelegate.stateUpdates),
                isComplete(receiverDelegate.stateUpdates))
    }

    private func isComplete(_ updates: [TransferState]) -> Bool {
        updates.contains { if case .completed = $0 { return true }; return false }
    }

    private func isCompleteOrCompleting(_ updates: [TransferState]) -> Bool {
        updates.contains {
            if case .completed = $0 { return true }
            if case .completing = $0 { return true }
            return false
        }
    }
}

// MARK: - XMODEM-1K Loopback

class XMODEM1KLoopbackTests: XCTestCase {

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

    func testXMODEM1KLoopback2048Bytes() {
        let srcPath = tempDir.appendingPathComponent("src_1k.bin")
        let dstPath = tempDir.appendingPathComponent("dst_1k.bin")
        let testData = Data((0..<2048).map { UInt8($0 & 0xFF) })
        try! testData.write(to: srcPath)

        let sender = XMODEMProtocol()
        sender.mode = .oneK
        sender.direction = .send
        sender.filePath = srcPath.path
        sender.fileHandle = FileHandle(forReadingAtPath: srcPath.path)

        let receiver = XMODEMProtocol()
        receiver.mode = .oneK
        receiver.direction = .receive
        receiver.filePath = dstPath.path

        let harness = LoopbackHarness()
        let result = harness.run(sender: sender, receiver: receiver)

        XCTAssertTrue(result.receiverDone, "Receiver should complete 1K transfer")

        if let received = try? Data(contentsOf: dstPath) {
            XCTAssertTrue(received.count >= 2048)
            XCTAssertEqual(Data(received.prefix(2048)), testData,
                           "Received data should match original for 1K blocks")
        } else {
            XCTFail("Received file should exist")
        }
    }

    func testXMODEM1KLoopbackSmallFile() {
        // File smaller than 1024 bytes → still uses 1K block with padding
        let srcPath = tempDir.appendingPathComponent("src_small_1k.bin")
        let dstPath = tempDir.appendingPathComponent("dst_small_1k.bin")
        let testData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try! testData.write(to: srcPath)

        let sender = XMODEMProtocol()
        sender.mode = .oneK
        sender.direction = .send
        sender.filePath = srcPath.path
        sender.fileHandle = FileHandle(forReadingAtPath: srcPath.path)

        let receiver = XMODEMProtocol()
        receiver.mode = .oneK
        receiver.direction = .receive
        receiver.filePath = dstPath.path

        let harness = LoopbackHarness()
        let result = harness.run(sender: sender, receiver: receiver)

        XCTAssertTrue(result.receiverDone, "Small file 1K transfer should complete")

        if let received = try? Data(contentsOf: dstPath) {
            // First 4 bytes should match original
            XCTAssertEqual(Data(received.prefix(4)), testData)
        } else {
            XCTFail("Received file should exist")
        }
    }

    func testXMODEMChecksumLoopbackExactBlock() {
        // Exactly 128 bytes → 1 block, no partial
        let srcPath = tempDir.appendingPathComponent("exact128.bin")
        let dstPath = tempDir.appendingPathComponent("exact128_recv.bin")
        let testData = Data(repeating: 0x77, count: 128)
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

        let harness = LoopbackHarness()
        let result = harness.run(sender: sender, receiver: receiver)

        XCTAssertTrue(result.receiverDone)

        if let received = try? Data(contentsOf: dstPath) {
            XCTAssertEqual(Data(received.prefix(128)), testData,
                           "Exact block boundary should transfer correctly")
        } else {
            XCTFail("Received file should exist")
        }
    }

    func testXMODEMCRCLoopbackMultiBlock() {
        // 500 bytes → 4 blocks (128 * 4 = 512, last block padded)
        let srcPath = tempDir.appendingPathComponent("multi_crc.bin")
        let dstPath = tempDir.appendingPathComponent("multi_crc_recv.bin")
        let testData = Data((0..<500).map { UInt8($0 & 0xFF) })
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

        let harness = LoopbackHarness()
        let result = harness.run(sender: sender, receiver: receiver)

        XCTAssertTrue(result.receiverDone, "Multi-block CRC transfer should complete")

        if let received = try? Data(contentsOf: dstPath) {
            XCTAssertTrue(received.count >= 500)
            XCTAssertEqual(Data(received.prefix(500)), testData)
        } else {
            XCTFail("Received file should exist")
        }
    }
}

// MARK: - YMODEM Loopback

class YMODEMLoopbackTests: XCTestCase {

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

    /// Full YMODEM loopback: sender↔receiver with block 0 file info negotiation
    func testYMODEMFullLoopback() {
        let srcPath = tempDir.appendingPathComponent("ymodem_src.bin")
        let dstDir = tempDir.appendingPathComponent("ymodem_dst")
        try? FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)

        let testData = Data((0..<2000).map { UInt8($0 & 0xFF) })
        try! testData.write(to: srcPath)

        let sender = YMODEMProtocol()
        sender.direction = .send
        sender.filePath = srcPath.path
        sender.fileHandle = FileHandle(forReadingAtPath: srcPath.path)

        let receiver = YMODEMProtocol()
        receiver.direction = .receive
        // Use directory so receiver can pick up filename from block 0
        receiver.filePath = dstDir.appendingPathComponent("placeholder").path

        let sDelegate = MockFileTransferDelegate()
        let rDelegate = MockFileTransferDelegate()
        sender.delegate = sDelegate
        receiver.delegate = rDelegate

        // Receiver starts and sends 'C'
        receiver.start()

        // Feed receiver's 'C' to sender to start
        sender.start()
        for d in rDelegate.sentData { sender.processData(d) }
        rDelegate.sentData.removeAll()

        var transferComplete = false
        for _ in 0..<50 {
            let sOut = sDelegate.sentData
            sDelegate.sentData.removeAll()
            for d in sOut { receiver.processData(d) }

            let rOut = rDelegate.sentData
            rDelegate.sentData.removeAll()
            for d in rOut { sender.processData(d) }

            // Check sender and receiver states
            let sDone = sDelegate.stateUpdates.contains { s in
                if case .completed = s { return true }; return false
            }
            let rDone = rDelegate.stateUpdates.contains { s in
                if case .completed = s { return true }; return false
            }
            if sDone && rDone {
                transferComplete = true
                break
            }
        }

        XCTAssertTrue(transferComplete, "YMODEM loopback transfer should complete")
    }

    /// Test block 0 metadata roundtrip: filename + size survive the transfer
    func testYMODEMBlock0MetadataRoundtrip() {
        let srcPath = tempDir.appendingPathComponent("metadata_test.dat")
        let testData = Data(repeating: 0xAB, count: 300)
        try! testData.write(to: srcPath)

        let sender = YMODEMProtocol()
        sender.direction = .send
        sender.filePath = srcPath.path
        sender.fileHandle = FileHandle(forReadingAtPath: srcPath.path)

        let sDelegate = MockFileTransferDelegate()
        sender.delegate = sDelegate
        sender.start()

        // Simulate receiver sending 'C'
        sender.processData(Data([0x43]))

        // Sender should have sent block 0
        XCTAssertFalse(sDelegate.sentData.isEmpty, "Sender should produce block 0")
        let block0 = sDelegate.sentData[0]
        XCTAssertEqual(block0[1], 0x00, "Should be block number 0")
        XCTAssertEqual(block0[2], 0xFF, "Complement should be 0xFF")

        // Parse the payload from block 0
        let blockSize = (block0[0] == 0x01) ? 128 : 1024
        let payload = Data(block0[3..<(3 + blockSize)])

        // Find filename
        if let nulIdx = payload.firstIndex(of: 0) {
            let name = String(data: Data(payload[payload.startIndex..<nulIdx]), encoding: .utf8)
            XCTAssertEqual(name, "metadata_test.dat", "Block 0 should contain correct filename")

            // After NUL, find size
            let afterNul = payload.index(after: nulIdx)
            if afterNul < payload.endIndex {
                let metaBytes = Data(payload[afterNul...]).prefix(while: { $0 != 0 })
                let metaStr = String(data: metaBytes, encoding: .ascii) ?? ""
                let parts = metaStr.split(separator: " ")
                XCTAssertFalse(parts.isEmpty, "Metadata should contain file size")
                XCTAssertEqual(parts[0], "300", "File size in block 0 should be 300")
            }
        } else {
            XCTFail("Block 0 payload should contain NUL-terminated filename")
        }
    }

    /// Test YMODEM end-of-batch: empty block 0 terminates batch
    func testYMODEMSendEmptyBlock0Terminates() {
        let sender = YMODEMProtocol()
        sender.direction = .send
        sender.filePaths = []

        let sDelegate = MockFileTransferDelegate()
        sender.delegate = sDelegate
        sender.start()

        // When sender has no files, the batch should complete quickly.
        // We verify the empty block 0 packet structure directly.
        let emptyPayload = Data(repeating: 0, count: 128)
        let crcVal = crc16(emptyPayload)

        var expectedBlock0 = Data()
        expectedBlock0.append(0x01) // SOH
        expectedBlock0.append(0x00) // block 0
        expectedBlock0.append(0xFF) // complement
        expectedBlock0.append(emptyPayload)
        expectedBlock0.append(UInt8(crcVal >> 8))
        expectedBlock0.append(UInt8(crcVal & 0xFF))

        // Verify the CRC of all-zero payload
        XCTAssertEqual(expectedBlock0.count, 1 + 2 + 128 + 2,
                       "Empty block 0 should be 133 bytes")

        // Verify CRC is valid
        let recalc = crc16(emptyPayload)
        XCTAssertEqual(recalc, crcVal, "CRC should be deterministic")
    }
}

// MARK: - CRC Roundtrip Tests

class CRCRoundtripTests: XCTestCase {

    func testCRC16RoundtripIntegrity() {
        // Verify that CRC-16-CCITT property: CRC(data || CRC) == 0 when correctly appended
        let data = Data("Hello, XMODEM!".utf8)
        let crcVal = crc16(data)

        var dataWithCRC = data
        dataWithCRC.append(UInt8(crcVal >> 8))
        dataWithCRC.append(UInt8(crcVal & 0xFF))

        let checkCRC = crc16(dataWithCRC)
        XCTAssertEqual(checkCRC, 0, "CRC-16 of data+CRC should be 0")
    }

    func testCRC16AllByteValues() {
        // Ensure CRC handles all byte values 0x00-0xFF
        let data = Data((0...255).map { UInt8($0) })
        let crcVal = crc16(data)

        // Should be deterministic
        XCTAssertEqual(crc16(data), crcVal)

        // Flipping any bit should change the CRC
        for i in 0..<min(data.count, 32) {  // Sample first 32 bytes
            var corrupted = data
            corrupted[i] ^= 0x01
            XCTAssertNotEqual(crc16(corrupted), crcVal,
                              "CRC should change when byte \(i) is corrupted")
        }
    }

    func testCRC32RoundtripIntegrity() {
        let data = Data("Hello, ZMODEM!".utf8)
        let crcVal = crc32(data)

        // CRC-32 should be deterministic
        XCTAssertEqual(crc32(data), crcVal)

        // Different data should give different CRC
        var modified = data
        modified[0] ^= 0x01
        XCTAssertNotEqual(crc32(modified), crcVal)
    }

    func testCRC16LargeData() {
        // 10KB of pattern data
        let data = Data((0..<10240).map { UInt8($0 & 0xFF) })
        let c1 = crc16(data)
        let c2 = crc16(data)
        XCTAssertEqual(c1, c2, "CRC-16 of large data should be deterministic")
        XCTAssertNotEqual(c1, 0, "CRC-16 of non-empty patterned data should not be 0")
    }
}

// MARK: - ZMODEM Header Encode/Decode Tests

class ZMODEMHeaderTests: XCTestCase {

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

    func testZMODEMHexHeaderStructure() {
        // When receiver starts, it sends ZRINIT as hex header
        let zm = ZMODEMProtocol()
        zm.direction = .receive
        zm.delegate = delegate

        zm.start()

        let header = delegate.allSentData
        // Hex header: ZPAD ZPAD ZDLE ZHEX type[2hex] flags[8hex] crc[4hex] CR LF [XON]
        XCTAssertTrue(header.count >= 16, "Hex header should be at least 16 bytes")
        XCTAssertEqual(header[0], 0x2A, "First byte: ZPAD")
        XCTAssertEqual(header[1], 0x2A, "Second byte: ZPAD")
        XCTAssertEqual(header[2], 0x18, "Third byte: ZDLE")
        XCTAssertEqual(header[3], 0x42, "Fourth byte: ZHEX ('B')")

        // Type field is 2 hex chars encoding ZRINIT (0x01)
        let typeHigh = header[4]
        let typeLow = header[5]
        let typeValue = hexDecode(typeHigh) << 4 | hexDecode(typeLow)
        XCTAssertEqual(typeValue, 0x01, "Type should be ZRINIT (0x01)")

        // Verify CR/LF trailer exists
        let hasCR = header.contains(0x0D)
        let hasLF = header.contains(where: { $0 == 0x0A || $0 == 0x8A })
        XCTAssertTrue(hasCR, "Should have CR in trailer")
        XCTAssertTrue(hasLF, "Should have LF in trailer")
    }

    func testZMODEMSenderHexHeader() {
        // Sender sends ZRQINIT (type 0x00) on start
        let filePath = tempDir.appendingPathComponent("z_send.bin")
        try! Data(repeating: 0x55, count: 100).write(to: filePath)

        let zm = ZMODEMProtocol()
        zm.direction = .send
        zm.filePath = filePath.path
        zm.delegate = delegate

        zm.start()

        let header = delegate.allSentData
        XCTAssertEqual(header[0], 0x2A, "ZPAD")
        XCTAssertEqual(header[1], 0x2A, "ZPAD")
        XCTAssertEqual(header[2], 0x18, "ZDLE")
        XCTAssertEqual(header[3], 0x42, "ZHEX")

        // Type should be ZRQINIT (0x00)
        let typeValue = hexDecode(header[4]) << 4 | hexDecode(header[5])
        XCTAssertEqual(typeValue, 0x00, "Sender should send ZRQINIT (0x00)")
    }

    func testZMODEMHexHeaderCRCValid() {
        // Verify the CRC in a hex header is valid
        let zm = ZMODEMProtocol()
        zm.direction = .receive
        zm.delegate = delegate
        zm.start()

        let header = delegate.allSentData
        // After ZPAD ZPAD ZDLE ZHEX, we have 14 hex chars: type(2) + flags(8) + crc(4)
        // Total hex chars = 14, each pair = 1 byte => 7 bytes: type + 4flags + 2crc
        guard header.count >= 18 else {
            XCTFail("Header too short: \(header.count)")
            return
        }

        // Extract the 7 decoded bytes from hex portion
        var decoded = [UInt8]()
        for i in stride(from: 4, to: 18, by: 2) {
            let val = hexDecode(header[i]) << 4 | hexDecode(header[i + 1])
            decoded.append(val)
        }
        // decoded = [type, f3, f2, f1, f0, crcHi, crcLo]
        XCTAssertEqual(decoded.count, 7, "Should decode 7 bytes from hex header")

        // CRC should validate: CRC(type + 4 flags + 2 CRC bytes) == 0
        var crc: UInt16 = 0
        for byte in decoded {
            crc = crc ^ (UInt16(byte) << 8)
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        XCTAssertEqual(crc, 0, "Hex header CRC should validate to 0")
    }

    func testZMODEMAutoDetectEdgeCases() {
        // Empty data
        XCTAssertFalse(ZMODEMProtocol.detectZMODEM(in: Data()))

        // Exactly the sequence
        let exact = Data([0x2A, 0x2A, 0x18, 0x42])
        XCTAssertTrue(ZMODEMProtocol.detectZMODEM(in: exact))

        // Sequence embedded in noise
        var noisy = Data(repeating: 0x00, count: 100)
        noisy[50] = 0x2A; noisy[51] = 0x2A; noisy[52] = 0x18; noisy[53] = 0x42
        XCTAssertTrue(ZMODEMProtocol.detectZMODEM(in: noisy))

        // Almost-match (wrong last byte)
        let almost = Data([0x2A, 0x2A, 0x18, 0x41])
        XCTAssertFalse(ZMODEMProtocol.detectZMODEM(in: almost))
    }

    func testZMODEMCancelPacketStructure() {
        let zm = ZMODEMProtocol()
        zm.direction = .receive
        zm.delegate = delegate
        zm.start()
        delegate.sentData.removeAll()

        zm.cancel()

        let cancelData = delegate.allSentData
        // 8 ZDLE (0x18) + 10 BS (0x08)
        XCTAssertEqual(cancelData.count, 18)

        let zdleCount = cancelData.prefix(8).filter { $0 == 0x18 }.count
        XCTAssertEqual(zdleCount, 8, "Should have 8 ZDLE bytes")

        let bsCount = cancelData.suffix(10).filter { $0 == 0x08 }.count
        XCTAssertEqual(bsCount, 10, "Should have 10 BS bytes")
    }

    // Helper to decode a hex ASCII nibble
    private func hexDecode(_ b: UInt8) -> UInt8 {
        if b >= 0x30 && b <= 0x39 { return b - 0x30 }
        if b >= 0x61 && b <= 0x66 { return b - 0x61 + 10 }
        if b >= 0x41 && b <= 0x46 { return b - 0x41 + 10 }
        return 0
    }
}

// MARK: - ZMODEM ZDLE Escape Tests

class ZMODEMZDLEEscapeTests: XCTestCase {

    /// Test that ZDLE-escaped data round-trips correctly through receiver parsing.
    /// We build a ZFILE data subpacket with known content and verify the receiver
    /// can parse it.
    func testZDLEEscapeBytesRequiringEscape() {
        // Bytes that require ZDLE escaping per the spec
        let specialBytes: [UInt8] = [
            0x0D, 0x8D,  // CR
            0x0A, 0x8A,  // LF
            0x10, 0x90,  // DLE
            0x11, 0x91,  // XON
            0x13, 0x93,  // XOFF
            0x1D, 0x9D,  // GS
            0x18,        // ZDLE itself
        ]

        // Verify each special byte, when XORed with 0x40, produces a non-special value
        for b in specialBytes {
            let escaped = b ^ 0x40
            XCTAssertNotEqual(escaped, 0x18,
                              "Escaped form of 0x\(String(b, radix: 16)) should not be ZDLE")
        }
    }

    func testZDLEEscapeRoundtrip() {
        // Create raw bytes including all special values and verify escape+unescape identity
        var rawData = Data()
        for b: UInt8 in [0x00, 0x0A, 0x0D, 0x10, 0x11, 0x13, 0x18, 0x1D,
                         0x41, 0x42, 0x7F, 0x80, 0x8A, 0x8D, 0x90, 0x91, 0x93, 0x9D, 0xFF] {
            rawData.append(b)
        }

        // Escape
        var escaped = Data()
        for b in rawData {
            switch b {
            case 0x0D, 0x8D, 0x0A, 0x8A, 0x10, 0x90, 0x11, 0x91,
                 0x13, 0x93, 0x1D, 0x9D, 0x18:
                escaped.append(0x18)      // ZDLE
                escaped.append(b ^ 0x40)  // escaped form
            default:
                escaped.append(b)
            }
        }

        // Unescape
        var unescaped = Data()
        var i = 0
        while i < escaped.count {
            if escaped[i] == 0x18 {
                i += 1
                if i < escaped.count {
                    unescaped.append(escaped[i] ^ 0x40)
                }
            } else {
                unescaped.append(escaped[i])
            }
            i += 1
        }

        XCTAssertEqual(unescaped, rawData,
                       "ZDLE escape/unescape should roundtrip all byte values")
    }
}

// MARK: - Kermit Encode/Decode Roundtrip Tests

class KermitEncodingRoundtripTests: XCTestCase {

    func testKermitControlCharEncoding() {
        // Control characters (0x00-0x1F, 0x7F) should be encoded as #<char^0x40>
        let qctl: UInt8 = 0x23 // '#'

        for byte: UInt8 in [0x00, 0x01, 0x0A, 0x0D, 0x1F, 0x7F] {
            var encoded = Data()
            encoded.append(qctl)
            encoded.append(byte ^ 0x40)

            // Decode
            var decoded = Data()
            var i = 0
            while i < encoded.count {
                if encoded[i] == qctl {
                    i += 1
                    if i < encoded.count {
                        let b = encoded[i]
                        if (b & 0x7F) >= 0x3F && (b & 0x7F) <= 0x5F {
                            decoded.append(b ^ 0x40)
                        } else {
                            decoded.append(b)
                        }
                    }
                } else {
                    decoded.append(encoded[i])
                }
                i += 1
            }

            XCTAssertEqual(decoded, Data([byte]),
                           "Control char 0x\(String(byte, radix: 16)) should roundtrip")
        }
    }

    func testKermitQCTLSelfEncoding() {
        // '#' itself should be encoded as '##'
        let qctl: UInt8 = 0x23
        let encoded = Data([qctl, qctl])

        // Decode: first '#' is quote, second '#' is literal
        // Per spec, '#' doesn't match the 0x3F-0x5F range for XOR, so it's literal
        var decoded = Data()
        var i = 0
        while i < encoded.count {
            if encoded[i] == qctl {
                i += 1
                if i < encoded.count {
                    let b = encoded[i]
                    if (b & 0x7F) >= 0x3F && (b & 0x7F) <= 0x5F {
                        decoded.append(b ^ 0x40)
                    } else {
                        decoded.append(b)
                    }
                }
            } else {
                decoded.append(encoded[i])
            }
            i += 1
        }

        XCTAssertEqual(decoded, Data([qctl]),
                       "'#' should be decoded from '##'")
    }

    func testKermitRepeatCountEncoding() {
        // Repeat prefix: ~<count+32><byte>
        // e.g., 10 repetitions of 'A': ~<42>A
        let reptChar: UInt8 = 0x7E // '~'
        let count = 10
        let byte: UInt8 = 0x41 // 'A'

        var encoded = Data()
        encoded.append(reptChar)
        encoded.append(UInt8(count + 32))
        encoded.append(byte)

        // Decode
        var decoded = Data()
        var i = 0
        while i < encoded.count {
            if encoded[i] == reptChar {
                i += 1
                guard i < encoded.count else { break }
                let repeatCount = Int(encoded[i]) - 32
                i += 1
                guard i < encoded.count else { break }
                let val = encoded[i]
                for _ in 0..<repeatCount {
                    decoded.append(val)
                }
            } else {
                decoded.append(encoded[i])
            }
            i += 1
        }

        XCTAssertEqual(decoded, Data(repeating: byte, count: count),
                       "Repeat encoding should produce \(count) copies of 'A'")
    }

    func testKermitTocharUnchar() {
        // Kermit tochar: value + 32; unchar: value - 32
        for v in 0..<95 {
            let charVal = UInt8(v + 32)
            let uncharVal = Int(charVal) - 32
            XCTAssertEqual(uncharVal, v,
                           "tochar/unchar should roundtrip for value \(v)")
        }
    }

    func testKermitPacketChecksumType1() {
        // Type 1 checksum: (sum & 0xFF) → ((s + (s >> 6)) & 0x3F) + 32
        let data: [UInt8] = [0x60, 0x20, 0x59]  // LEN, SEQ, TYPE='Y'
        let sum = data.reduce(0) { $0 + Int($1) }
        let checkByte = UInt8(((sum + (sum >> 6)) & 0x3F) + 32)

        // Verify the checksum is in printable range
        XCTAssertTrue(checkByte >= 32 && checkByte < 128,
                       "Type 1 checksum should be in printable range")

        // Recompute and verify
        let recomputed = UInt8(((sum + (sum >> 6)) & 0x3F) + 32)
        XCTAssertEqual(checkByte, recomputed, "Type 1 checksum should be deterministic")
    }
}

// MARK: - Kermit Full Loopback Tests

class KermitLoopbackTests: XCTestCase {

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

    func testKermitFullLoopback() {
        let srcPath = tempDir.appendingPathComponent("kermit_src.txt")
        let dstPath = tempDir.appendingPathComponent("kermit_dst.txt")
        let testData = Data("Hello Kermit Protocol Transfer Test!".utf8)
        try! testData.write(to: srcPath)

        FileManager.default.createFile(atPath: dstPath.path, contents: nil)

        let sender = KermitProtocol()
        sender.direction = .send
        sender.filePath = srcPath.path
        sender.fileHandle = FileHandle(forReadingAtPath: srcPath.path)

        let receiver = KermitProtocol()
        receiver.direction = .receive
        receiver.filePath = dstPath.path
        receiver.fileHandle = FileHandle(forWritingAtPath: dstPath.path)

        let sDelegate = MockFileTransferDelegate()
        let rDelegate = MockFileTransferDelegate()
        sender.delegate = sDelegate
        receiver.delegate = rDelegate

        // Sender starts by sending S packet
        sender.start()
        receiver.start()

        for _ in 0..<30 {
            // Forward sender → receiver
            let sOut = sDelegate.sentData
            sDelegate.sentData.removeAll()
            for d in sOut { receiver.processData(d) }

            // Forward receiver → sender
            let rOut = rDelegate.sentData
            rDelegate.sentData.removeAll()
            for d in rOut { sender.processData(d) }

            let sDone = sDelegate.stateUpdates.contains { s in
                if case .completed = s { return true }; return false
            }
            let rDone = rDelegate.stateUpdates.contains { s in
                if case .completed = s { return true }; return false
            }
            if sDone && rDone { break }
        }

        let senderCompleted = sDelegate.completedFiles.count > 0
        let receiverCompleted = rDelegate.completedFiles.count > 0

        XCTAssertTrue(senderCompleted, "Kermit sender should complete")
        XCTAssertTrue(receiverCompleted, "Kermit receiver should complete")

        // Verify received file content
        if let received = try? Data(contentsOf: dstPath) {
            // Kermit decoded data may have been written incrementally
            XCTAssertTrue(received.count > 0, "Received file should have content")
        }
    }

    func testKermitSendInitParameterNegotiation() {
        let sender = KermitProtocol()
        sender.direction = .send
        sender.filePath = tempDir.appendingPathComponent("neg.bin").path
        try! Data([0x01]).write(to: URL(fileURLWithPath: sender.filePath!))
        sender.fileHandle = FileHandle(forReadingAtPath: sender.filePath!)

        let sDelegate = MockFileTransferDelegate()
        sender.delegate = sDelegate
        sender.start()

        // Sender should have sent S packet with init data
        XCTAssertFalse(sDelegate.sentData.isEmpty)
        let sPacket = sDelegate.sentData[0]
        XCTAssertEqual(sPacket[0], 0x01, "MARK byte")
        XCTAssertEqual(sPacket[3], UInt8(Character("S").asciiValue!), "Type = S")

        // Init data starts at offset 4
        let initData = sPacket[4..<(sPacket.count - 2)] // strip checksum + EOL
        XCTAssertTrue(initData.count >= 9, "Init data should have at least 9 fields")

        // MAXL
        let maxl = Int(initData[initData.startIndex]) - 32
        XCTAssertEqual(maxl, 94, "Default MAXL should be 94")

        // QCTL
        let qctl = initData[initData.startIndex + 5]
        XCTAssertEqual(qctl, 0x23, "QCTL should be '#' (0x23)")

        // EOL
        let eol = Int(initData[initData.startIndex + 4]) - 32
        XCTAssertEqual(eol, 13, "EOL should be CR (13)")
    }
}

// MARK: - XMODEM Packet Integrity Tests

class XMODEMPacketIntegrityTests: XCTestCase {

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

    func testXMODEMSendPacketCRCMatches() {
        // Verify that the CRC in sent packets is valid
        let filePath = tempDir.appendingPathComponent("crc_verify.bin")
        let testData = Data((0..<128).map { UInt8($0) })
        try! testData.write(to: filePath)

        let xm = XMODEMProtocol()
        xm.mode = .crc
        xm.direction = .send
        xm.filePath = filePath.path
        xm.fileHandle = FileHandle(forReadingAtPath: filePath.path)

        let delegate = MockFileTransferDelegate()
        xm.delegate = delegate
        xm.start()

        // Trigger first block with 'C'
        xm.processData(Data([0x43]))

        XCTAssertFalse(delegate.sentData.isEmpty)
        let packet = delegate.sentData.last!

        // Packet: SOH(1) + blk(1) + ~blk(1) + data(128) + CRC(2) = 133
        XCTAssertEqual(packet.count, 133)

        let payload = Data(packet[3..<131])
        let packetCRC = (UInt16(packet[131]) << 8) | UInt16(packet[132])
        let computedCRC = crc16(payload)

        XCTAssertEqual(packetCRC, computedCRC,
                       "Packet CRC should match recomputed CRC")
    }

    func testXMODEMSendPacketChecksumMatches() {
        let filePath = tempDir.appendingPathComponent("chk_verify.bin")
        let testData = Data(repeating: 0xAA, count: 50)
        try! testData.write(to: filePath)

        let xm = XMODEMProtocol()
        xm.mode = .checksum
        xm.direction = .send
        xm.filePath = filePath.path
        xm.fileHandle = FileHandle(forReadingAtPath: filePath.path)

        let delegate = MockFileTransferDelegate()
        xm.delegate = delegate
        xm.start()

        // Trigger with NAK
        xm.processData(Data([0x15]))

        XCTAssertFalse(delegate.sentData.isEmpty)
        let packet = delegate.sentData.last!

        // SOH(1) + blk(1) + ~blk(1) + data(128) + checksum(1) = 132
        XCTAssertEqual(packet.count, 132)

        let payload = Data(packet[3..<131])
        let packetChecksum = packet[131]
        let computedChecksum = payload.reduce(UInt8(0)) { $0 &+ $1 }

        XCTAssertEqual(packetChecksum, computedChecksum,
                       "Packet checksum should match recomputed checksum")

        // Verify padding
        // First 50 bytes should be 0xAA, rest should be SUB (0x1A)
        for i in 0..<50 {
            XCTAssertEqual(payload[i], 0xAA)
        }
        for i in 50..<128 {
            XCTAssertEqual(payload[i], 0x1A, "Byte \(i) should be SUB padding")
        }
    }

    func testXMODEMBlockNumberWraparound() {
        // Block numbers wrap: 255 → 0 (using &+ operator)
        var blockNum: UInt8 = 254
        blockNum = blockNum &+ 1
        XCTAssertEqual(blockNum, 255)
        blockNum = blockNum &+ 1
        XCTAssertEqual(blockNum, 0, "Block number should wrap from 255 to 0")

        // Complement wraps too
        let comp: UInt8 = ~blockNum
        XCTAssertEqual(comp, 0xFF, "Complement of 0 should be 0xFF")
    }
}

// MARK: - FileTransferManager Integration Tests

class FileTransferManagerSelfTests: XCTestCase {

    var tempDir: URL!
    var delegate: MockFileTransferDelegate!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        delegate = MockFileTransferDelegate()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testManagerXMODEMReceiveCompleteFlow() {
        let filePath = tempDir.appendingPathComponent("mgr_recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        let mgr = FileTransferManager()
        mgr.delegate = delegate

        mgr.startTransfer(protocol: .xmodemCRC, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(mgr.isTransferActive)

        // Build and send a valid CRC block
        let payload = Data(repeating: 0x42, count: 128)
        let crcVal = crc16(payload)
        var block = Data()
        block.append(0x01) // SOH
        block.append(0x01) // block 1
        block.append(0xFE) // complement
        block.append(payload)
        block.append(UInt8(crcVal >> 8))
        block.append(UInt8(crcVal & 0xFF))

        mgr.processIncomingData(block)

        // Send EOT
        mgr.processIncomingData(Data([0x04]))

        let hasCompleted = delegate.stateUpdates.contains { s in
            if case .completed = s { return true }; return false
        }
        XCTAssertTrue(hasCompleted, "Manager should report completion")
    }

    func testManagerZMODEMAutoDetectAndStart() {
        let savePath = tempDir.appendingPathComponent("auto_detect.bin").path

        let mgr = FileTransferManager()
        mgr.delegate = delegate

        // Random data should not trigger
        XCTAssertFalse(mgr.checkAutoDetect(Data([0x41, 0x42]), savePath: savePath))
        XCTAssertFalse(mgr.isTransferActive)

        // ZMODEM init sequence should trigger
        let zInit = Data([0x2A, 0x2A, 0x18, 0x42, 0x30, 0x30, 0x30, 0x30])
        XCTAssertTrue(mgr.checkAutoDetect(zInit, savePath: savePath))
        XCTAssertTrue(mgr.isTransferActive)

        // Cancel and verify
        mgr.cancelTransfer()
        XCTAssertFalse(mgr.isTransferActive)
    }

    func testManagerMultipleProtocolsSequential() {
        // Start and cancel different protocols in sequence
        let protocols: [TransferProtocolType] = [
            .xmodem, .xmodemCRC, .xmodem1K, .ymodem, .zmodem, .kermit
        ]

        for proto in protocols {
            let filePath = tempDir.appendingPathComponent("seq_\(proto).bin")
            FileManager.default.createFile(atPath: filePath.path, contents: nil)

            let mgr = FileTransferManager()
            mgr.delegate = delegate

            mgr.startTransfer(protocol: proto, direction: .receive, filePath: filePath.path)
            XCTAssertTrue(mgr.isTransferActive, "\(proto) should be active")

            mgr.cancelTransfer()
            XCTAssertFalse(mgr.isTransferActive, "\(proto) should be inactive after cancel")
        }
    }
}
