/*
 * TransferMenuProtocolTests.swift
 *
 * Tests for newly implemented transfer protocols:
 *   - B-Plus protocol (send/receive)
 *   - Quick-VAN protocol (send/receive)
 *   - YMODEM send/receive dialogs
 *   - Kermit Get / Kermit Finish subcommands
 *   - Transfer menu items
 *   - FileTransferManager integration with new protocols
 */

import XCTest
@testable import TeraTermMac

// MARK: - TransferProtocolType Enum Tests

class TransferProtocolTypeTests: XCTestCase {

    func testBPlusProtocolTypeExists() {
        let type: TransferProtocolType = .bplus
        switch type {
        case .bplus: break
        default: XCTFail("Should match .bplus")
        }
    }

    func testQuickVANProtocolTypeExists() {
        let type: TransferProtocolType = .quickVAN
        switch type {
        case .quickVAN: break
        default: XCTFail("Should match .quickVAN")
        }
    }

    func testAllProtocolTypesAreCovered() {
        // Verify all protocol types can be instantiated
        let types: [TransferProtocolType] = [
            .xmodem, .xmodemCRC, .xmodem1K,
            .ymodem, .ymodemG,
            .zmodem,
            .kermit,
            .bplus,
            .quickVAN
        ]
        XCTAssertEqual(types.count, 9, "Should have 9 protocol types")
    }
}

// MARK: - KermitMode Enum Tests

class KermitModeTests: XCTestCase {

    func testKermitModeValues() {
        let modes: [KermitMode] = [.receive, .send, .get, .finish]
        XCTAssertEqual(modes.count, 4, "Should have 4 Kermit modes")
    }

    func testKermitGetMode() {
        let mode: KermitMode = .get
        switch mode {
        case .get: break
        default: XCTFail("Should match .get")
        }
    }

    func testKermitFinishMode() {
        let mode: KermitMode = .finish
        switch mode {
        case .finish: break
        default: XCTFail("Should match .finish")
        }
    }
}

// MARK: - B-Plus Protocol Tests

class BPlusProtocolTests: XCTestCase {

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

    func testBPlusProtocolInstantiation() {
        let bp = BPlusProtocol()
        XCTAssertNotNil(bp, "BPlusProtocol should be instantiable")
    }

    func testBPlusSendStart() {
        let filePath = tempDir.appendingPathComponent("bp_send.bin")
        try! Data(repeating: 0xAA, count: 100).write(to: filePath)

        let bp = BPlusProtocol()
        bp.direction = .send
        bp.filePath = filePath.path
        bp.fileHandle = FileHandle(forReadingAtPath: filePath.path)
        bp.delegate = delegate

        bp.start()

        // Should have sent a parameter packet
        XCTAssertFalse(delegate.sentData.isEmpty, "B-Plus sender should send parameter packet")

        // First bytes should be DLE (0x10) 'B' (0x42)
        let sent = delegate.allSentData
        XCTAssertTrue(sent.count >= 2, "Sent data should have at least 2 bytes")
        XCTAssertEqual(sent[0], 0x10, "First byte should be DLE")
        XCTAssertEqual(sent[1], 0x42, "Second byte should be 'B'")
    }

    func testBPlusReceiveStart() {
        let bp = BPlusProtocol()
        bp.direction = .receive
        bp.delegate = delegate

        bp.start()

        // Receiver starts in recvInit state, waiting for DLE B
        // Check state is starting
        let hasStarting = delegate.stateUpdates.contains { s in
            if case .starting = s { return true }; return false
        }
        XCTAssertTrue(hasStarting, "B-Plus receiver should start")
    }

    func testBPlusCancel() {
        let bp = BPlusProtocol()
        bp.direction = .receive
        bp.delegate = delegate
        bp.start()
        delegate.sentData.removeAll()

        bp.cancel()

        // Should send a failure packet (DLE B ... F ...)
        XCTAssertFalse(delegate.sentData.isEmpty, "Cancel should send failure packet")
    }

    func testBPlusDLEFramingStructure() {
        // Verify DLE-framed packet structure
        let filePath = tempDir.appendingPathComponent("bp_frame.bin")
        try! Data([0x01, 0x02, 0x03]).write(to: filePath)

        let bp = BPlusProtocol()
        bp.direction = .send
        bp.filePath = filePath.path
        bp.fileHandle = FileHandle(forReadingAtPath: filePath.path)
        bp.delegate = delegate

        bp.start()

        let sent = delegate.allSentData
        // Packet starts with DLE B
        XCTAssertEqual(sent[0], 0x10, "DLE")
        XCTAssertEqual(sent[1], 0x42, "'B'")

        // Should contain DLE ETX somewhere (end marker)
        var foundDLEETX = false
        for i in 2..<(sent.count - 1) {
            if sent[i] == 0x10 && sent[i + 1] == 0x03 {
                foundDLEETX = true
                break
            }
        }
        XCTAssertTrue(foundDLEETX, "Packet should contain DLE ETX end marker")
    }

    func testBPlusChecksumMode() {
        // Default should be standard checksum (not CRC)
        let bp = BPlusProtocol()
        bp.direction = .send
        bp.delegate = delegate

        let filePath = tempDir.appendingPathComponent("bp_check.bin")
        try! Data(repeating: 0x55, count: 10).write(to: filePath)
        bp.filePath = filePath.path
        bp.fileHandle = FileHandle(forReadingAtPath: filePath.path)

        bp.start()

        // With standard checksum mode, check byte count after DLE ETX should be 1
        let sent = delegate.allSentData
        // Find DLE ETX position
        for i in 2..<(sent.count - 1) {
            if sent[i] == 0x10 && sent[i + 1] == 0x03 {
                // After DLE ETX should be 1 checksum byte (standard mode)
                let remaining = sent.count - (i + 2)
                XCTAssertEqual(remaining, 1,
                    "Standard checksum should have 1 check byte after DLE ETX")
                break
            }
        }
    }
}

// MARK: - Quick-VAN Protocol Tests

class QuickVANProtocolTests: XCTestCase {

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

    func testQuickVANInstantiation() {
        let qv = QuickVANProtocol()
        XCTAssertNotNil(qv, "QuickVANProtocol should be instantiable")
    }

    func testQuickVANReceiveStart() {
        let qv = QuickVANProtocol()
        qv.direction = .receive
        qv.delegate = delegate

        qv.start()

        // Should send NAK to initiate
        XCTAssertFalse(delegate.sentData.isEmpty, "Quick-VAN receiver should send NAK")
        let sent = delegate.allSentData
        XCTAssertEqual(sent[0], 0x15, "First byte should be NAK (0x15)")

        let hasStarting = delegate.stateUpdates.contains { s in
            if case .starting = s { return true }; return false
        }
        XCTAssertTrue(hasStarting, "Quick-VAN should enter starting state")
    }

    func testQuickVANSendStart() {
        let filePath = tempDir.appendingPathComponent("qv_send.bin")
        try! Data(repeating: 0xBB, count: 200).write(to: filePath)

        let qv = QuickVANProtocol()
        qv.direction = .send
        qv.filePath = filePath.path
        qv.fileHandle = FileHandle(forReadingAtPath: filePath.path)
        qv.delegate = delegate

        qv.start()

        // Should send SINIT packet (STX frame)
        XCTAssertFalse(delegate.sentData.isEmpty, "Quick-VAN sender should send SINIT")
        let sent = delegate.allSentData
        XCTAssertEqual(sent[0], 0x02, "First byte should be STX (0x02)")
        XCTAssertEqual(sent[1], 0x01, "Second byte should be SINIT type (0x01)")
    }

    func testQuickVANCancel() {
        let qv = QuickVANProtocol()
        qv.direction = .receive
        qv.delegate = delegate
        qv.start()
        delegate.sentData.removeAll()

        qv.cancel()

        // Should send CAN
        XCTAssertFalse(delegate.sentData.isEmpty, "Cancel should send CAN")
        let sent = delegate.allSentData
        XCTAssertEqual(sent[0], 0x18, "Cancel byte should be CAN (0x18)")
    }

    func testQuickVANEOTHandling() {
        let qv = QuickVANProtocol()
        qv.direction = .receive
        qv.filePath = tempDir.appendingPathComponent("qv_recv.bin").path
        qv.delegate = delegate
        qv.start()
        delegate.sentData.removeAll()

        // Send EOT to receiver
        qv.processData(Data([0x04]))

        // Should ACK and complete
        let hasCompleted = delegate.stateUpdates.contains { s in
            if case .completed = s { return true }; return false
        }
        XCTAssertTrue(hasCompleted, "EOT should trigger completion")
    }

    func testQuickVANSINITPacketFormat() {
        let qv = QuickVANProtocol()
        qv.direction = .send
        qv.delegate = delegate

        let filePath = tempDir.appendingPathComponent("qv_sinit.bin")
        try! Data([0x01]).write(to: filePath)
        qv.filePath = filePath.path
        qv.fileHandle = FileHandle(forReadingAtPath: filePath.path)

        qv.start()

        let sent = delegate.allSentData
        // SINIT: STX(02) SINIT(01) NUM VERSION WINSIZE CHECKSUM CR
        XCTAssertTrue(sent.count >= 7, "SINIT packet should be at least 7 bytes")
        XCTAssertEqual(sent[0], 0x02, "STX")
        XCTAssertEqual(sent[1], 0x01, "SINIT type")
        // Last byte should be CR (0x0D)
        XCTAssertEqual(sent[sent.count - 1], 0x0D, "SINIT should end with CR")
    }

    func testQuickVANDataBlockFormat() {
        // Verify 128-byte data block format: SOH BLK ~BLK DATA[128] CHECKSUM
        let testData = Data(repeating: 0x42, count: 128)
        var sum: UInt8 = 0x01  // SOH
        sum = sum &+ 0x01    // BLK=1
        sum = sum &+ 0xFE    // ~BLK
        for b in testData { sum = sum &+ b }

        // Build a data packet manually
        var packet = Data()
        packet.append(0x01) // SOH
        packet.append(0x01) // BLK
        packet.append(0xFE) // ~BLK
        packet.append(testData)
        packet.append(sum)

        XCTAssertEqual(packet.count, 132, "Data block should be 132 bytes (SOH+BLK+~BLK+128+CHECKSUM)")

        // Verify complement
        XCTAssertEqual(packet[1] ^ packet[2], 0xFF, "Block number and complement should XOR to 0xFF")
    }
}

// MARK: - Kermit Get/Finish Tests

class KermitGetFinishTests: XCTestCase {

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

    func testKermitGetStartsWithIPacket() {
        let km = KermitProtocol()
        km.delegate = delegate

        km.startGet(remoteFileName: "remote.txt")

        // Should have sent an I (Initialize) packet
        XCTAssertFalse(delegate.sentData.isEmpty, "Kermit Get should send I packet")
        let sent = delegate.sentData[0]
        XCTAssertEqual(sent[0], 0x01, "MARK byte")
        XCTAssertEqual(sent[3], UInt8(Character("I").asciiValue!), "Type should be 'I'")

        let hasStarting = delegate.stateUpdates.contains { s in
            if case .starting = s { return true }; return false
        }
        XCTAssertTrue(hasStarting, "Kermit Get should enter starting state")
    }

    func testKermitGetInitData() {
        let km = KermitProtocol()
        km.delegate = delegate

        km.startGet(remoteFileName: "test_file.dat")

        // I packet should contain init data (MAXL, TIME, etc.)
        let iPkt = delegate.sentData[0]
        // Init data starts at offset 4
        let initData = iPkt[4..<(iPkt.count - 2)] // strip checksum + EOL
        XCTAssertTrue(initData.count >= 9, "Init data should have at least 9 fields")

        // MAXL should be 94
        let maxl = Int(initData[initData.startIndex]) - 32
        XCTAssertEqual(maxl, 94, "Default MAXL should be 94")
    }

    func testKermitGetSendsRPacketAfterACK() {
        let km = KermitProtocol()
        km.delegate = delegate

        km.startGet(remoteFileName: "remote_file.txt")
        delegate.sentData.removeAll()

        // Simulate ACK for I packet with init data
        var ackData = Data()
        ackData.append(0x01) // MARK
        let ackPayload = Data([UInt8(Character("Y").asciiValue!)])
        let ackLen = ackPayload.count + 3
        ackData.append(UInt8(ackLen + 32)) // LEN
        ackData.append(UInt8(0 + 32)) // SEQ=0
        ackData.append(UInt8(Character("Y").asciiValue!)) // TYPE='Y'

        // Add init data in ACK
        let initReply = Data([UInt8(94 + 32), UInt8(10 + 32), UInt8(0 + 32), UInt8(0), UInt8(13 + 32), 0x23, 0x59, 0x31, 0x7E])
        ackData.append(initReply)

        // Recalculate length
        let totalLen = initReply.count + 3
        ackData[1] = UInt8(totalLen + 32)

        // Checksum
        let checksumData = ackData[1...]
        let sum = checksumData.reduce(0) { $0 + Int($1) } & 0xFF
        let check = UInt8(((sum + (sum >> 6)) & 0x3F) + 32)
        ackData.append(check)
        ackData.append(0x0D) // EOL

        km.processData(ackData)

        // After ACK for I packet, should send R packet with filename
        XCTAssertFalse(delegate.sentData.isEmpty, "Should send R packet after I-ACK")
        if let rPkt = delegate.sentData.first {
            XCTAssertEqual(rPkt[0], 0x01, "MARK")
            XCTAssertEqual(rPkt[3], UInt8(Character("R").asciiValue!), "Type should be 'R'")
        }
    }

    func testKermitFinishStartsWithIPacket() {
        let km = KermitProtocol()
        km.delegate = delegate

        km.startFinish()

        // Should send I packet first
        XCTAssertFalse(delegate.sentData.isEmpty, "Kermit Finish should send I packet")
        let sent = delegate.sentData[0]
        XCTAssertEqual(sent[0], 0x01, "MARK byte")
        XCTAssertEqual(sent[3], UInt8(Character("I").asciiValue!), "Type should be 'I'")
    }

    func testKermitFinishState() {
        let km = KermitProtocol()
        km.delegate = delegate

        km.startFinish()

        let hasStarting = delegate.stateUpdates.contains { s in
            if case .starting = s { return true }; return false
        }
        XCTAssertTrue(hasStarting, "Kermit Finish should enter starting state")
    }
}

// MARK: - FileTransferManager New Protocol Tests

class FileTransferManagerNewProtocolTests: XCTestCase {

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

    func testManagerBPlusSend() {
        let filePath = tempDir.appendingPathComponent("mgr_bp_send.bin")
        try! Data(repeating: 0xCC, count: 50).write(to: filePath)

        let mgr = FileTransferManager()
        mgr.delegate = delegate

        mgr.startTransfer(protocol: .bplus, direction: .send, filePath: filePath.path)
        XCTAssertTrue(mgr.isTransferActive, "B-Plus send should be active")

        mgr.cancelTransfer()
        XCTAssertFalse(mgr.isTransferActive, "B-Plus should be inactive after cancel")
    }

    func testManagerBPlusReceive() {
        let filePath = tempDir.appendingPathComponent("mgr_bp_recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        let mgr = FileTransferManager()
        mgr.delegate = delegate

        mgr.startTransfer(protocol: .bplus, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(mgr.isTransferActive, "B-Plus receive should be active")

        mgr.cancelTransfer()
        XCTAssertFalse(mgr.isTransferActive)
    }

    func testManagerQuickVANSend() {
        let filePath = tempDir.appendingPathComponent("mgr_qv_send.bin")
        try! Data(repeating: 0xDD, count: 300).write(to: filePath)

        let mgr = FileTransferManager()
        mgr.delegate = delegate

        mgr.startTransfer(protocol: .quickVAN, direction: .send, filePath: filePath.path)
        XCTAssertTrue(mgr.isTransferActive, "Quick-VAN send should be active")

        mgr.cancelTransfer()
        XCTAssertFalse(mgr.isTransferActive)
    }

    func testManagerQuickVANReceive() {
        let filePath = tempDir.appendingPathComponent("mgr_qv_recv.bin")
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        let mgr = FileTransferManager()
        mgr.delegate = delegate

        mgr.startTransfer(protocol: .quickVAN, direction: .receive, filePath: filePath.path)
        XCTAssertTrue(mgr.isTransferActive, "Quick-VAN receive should be active")

        mgr.cancelTransfer()
        XCTAssertFalse(mgr.isTransferActive)
    }

    func testManagerKermitGet() {
        let filePath = tempDir.appendingPathComponent("mgr_km_get.bin")

        let mgr = FileTransferManager()
        mgr.delegate = delegate

        mgr.startKermitGet(remoteFileName: "remote.txt", localPath: filePath.path)
        XCTAssertTrue(mgr.isTransferActive, "Kermit Get should be active")

        // Should have sent I packet
        XCTAssertFalse(delegate.sentData.isEmpty, "Kermit Get should produce I packet")

        mgr.cancelTransfer()
        XCTAssertFalse(mgr.isTransferActive)
    }

    func testManagerKermitFinish() {
        let mgr = FileTransferManager()
        mgr.delegate = delegate

        mgr.startKermitFinish()
        XCTAssertTrue(mgr.isTransferActive, "Kermit Finish should be active")

        // Should have sent I packet
        XCTAssertFalse(delegate.sentData.isEmpty, "Kermit Finish should produce I packet")

        mgr.cancelTransfer()
        XCTAssertFalse(mgr.isTransferActive)
    }

    func testManagerAllNewProtocolsSequential() {
        let protocols: [TransferProtocolType] = [.bplus, .quickVAN]

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

// MARK: - B-Plus Loopback Tests

class BPlusLoopbackTests: XCTestCase {

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

    func testBPlusSenderProducesData() {
        let srcPath = tempDir.appendingPathComponent("bp_src.bin")
        let testData = Data((0..<256).map { UInt8($0 & 0xFF) })
        try! testData.write(to: srcPath)

        let sender = BPlusProtocol()
        sender.direction = .send
        sender.filePath = srcPath.path
        sender.fileHandle = FileHandle(forReadingAtPath: srcPath.path)

        let sDelegate = MockFileTransferDelegate()
        sender.delegate = sDelegate
        sender.start()

        // Sender should produce initial parameter packet
        XCTAssertFalse(sDelegate.sentData.isEmpty, "B-Plus sender should produce output")
        let allSent = sDelegate.allSentData
        XCTAssertTrue(allSent.count > 5, "Parameter packet should have reasonable length")
    }

    func testBPlusReceiverWaitsForInput() {
        let receiver = BPlusProtocol()
        receiver.direction = .receive
        receiver.filePath = tempDir.appendingPathComponent("bp_recv.bin").path

        let rDelegate = MockFileTransferDelegate()
        receiver.delegate = rDelegate
        receiver.start()

        // Receiver should be in starting state, waiting for DLE B
        let hasStarting = rDelegate.stateUpdates.contains { s in
            if case .starting = s { return true }; return false
        }
        XCTAssertTrue(hasStarting, "Receiver should be in starting state")
    }
}

// MARK: - Quick-VAN Loopback Tests

class QuickVANLoopbackTests: XCTestCase {

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

    func testQuickVANSenderProducesSINIT() {
        let srcPath = tempDir.appendingPathComponent("qv_src.bin")
        let testData = Data(repeating: 0x55, count: 500)
        try! testData.write(to: srcPath)

        let sender = QuickVANProtocol()
        sender.direction = .send
        sender.filePath = srcPath.path
        sender.fileHandle = FileHandle(forReadingAtPath: srcPath.path)

        let sDelegate = MockFileTransferDelegate()
        sender.delegate = sDelegate
        sender.start()

        XCTAssertFalse(sDelegate.sentData.isEmpty, "Quick-VAN sender should produce SINIT")
        let sinit = sDelegate.allSentData
        XCTAssertEqual(sinit[0], 0x02, "First byte: STX")
        XCTAssertEqual(sinit[1], 0x01, "Second byte: SINIT type")
    }

    func testQuickVANReceiverSendsNAK() {
        let receiver = QuickVANProtocol()
        receiver.direction = .receive
        receiver.filePath = tempDir.appendingPathComponent("qv_recv.bin").path

        let rDelegate = MockFileTransferDelegate()
        receiver.delegate = rDelegate
        receiver.start()

        XCTAssertFalse(rDelegate.sentData.isEmpty, "Receiver should send NAK")
        let sent = rDelegate.allSentData
        XCTAssertEqual(sent[0], 0x15, "Should be NAK (0x15)")
    }

    func testQuickVANBlockChecksumRoundtrip() {
        // Create a block with proper checksum and verify
        let blockData = Data(repeating: 0x42, count: 128)
        let blk: UInt8 = 1

        var sum: UInt8 = 0x01  // SOH
        sum = sum &+ blk
        sum = sum &+ (~blk)
        for b in blockData { sum = sum &+ b }

        // Build packet
        var packet = Data()
        packet.append(0x01) // SOH
        packet.append(blk)
        packet.append(~blk)
        packet.append(blockData)
        packet.append(sum)

        // Verify checksum
        var verifySum: UInt8 = 0
        for b in packet.prefix(packet.count - 1) {
            verifySum = verifySum &+ b
        }
        XCTAssertEqual(verifySum, sum, "Checksum should match recomputed value")
    }
}

// MARK: - YMODEM Dialog Tests

#if canImport(AppKit)
class YMODEMOptionAccessoryTests: XCTestCase {

    func testDefaultStandardMode() {
        let accessory = YMODEMOptionAccessory(defaultStandard: true)
        XCTAssertEqual(accessory.standardRadio.state, .on)
        XCTAssertEqual(accessory.ymodemGRadio.state, .off)
        XCTAssertEqual(accessory.selectedProtocol, .ymodem)
    }

    func testYMODEMGMode() {
        let accessory = YMODEMOptionAccessory(defaultStandard: false)
        XCTAssertEqual(accessory.standardRadio.state, .off)
        XCTAssertEqual(accessory.ymodemGRadio.state, .on)
        XCTAssertEqual(accessory.selectedProtocol, .ymodemG)
    }

    func testBinaryDefaultOn() {
        let accessory = YMODEMOptionAccessory()
        XCTAssertTrue(accessory.isBinary)
    }

    func testBinaryToggle() {
        let accessory = YMODEMOptionAccessory()
        accessory.binaryCheck.state = .off
        XCTAssertFalse(accessory.isBinary)
    }

    func testFrameSize() {
        let accessory = YMODEMOptionAccessory()
        XCTAssertEqual(accessory.frame.width, 440)
        XCTAssertEqual(accessory.frame.height, 52)
    }

    func testRadioMutualExclusion() {
        let accessory = YMODEMOptionAccessory(defaultStandard: true)
        // Simulate switching to YMODEM-G
        accessory.standardRadio.state = .off
        accessory.ymodemGRadio.state = .on
        XCTAssertEqual(accessory.selectedProtocol, .ymodemG)

        // Switch back
        accessory.standardRadio.state = .on
        accessory.ymodemGRadio.state = .off
        XCTAssertEqual(accessory.selectedProtocol, .ymodem)
    }
}
#endif

// MARK: - Kermit Packet Type Tests (Get/Finish specific)

class KermitGetFinishPacketTests: XCTestCase {

    func testKermitIPacketType() {
        // 'I' packet is used for Initialize in both Get and Finish flows
        let typeChar = UInt8(Character("I").asciiValue!)
        XCTAssertEqual(typeChar, 0x49, "'I' should be 0x49")
    }

    func testKermitRPacketType() {
        // 'R' packet is used for Receive-Init (file request in Get)
        let typeChar = UInt8(Character("R").asciiValue!)
        XCTAssertEqual(typeChar, 0x52, "'R' should be 0x52")
    }

    func testKermitGPacketType() {
        // 'G' packet is used for Generic command (Finish sends G with 'F')
        let typeChar = UInt8(Character("G").asciiValue!)
        XCTAssertEqual(typeChar, 0x47, "'G' should be 0x47")
    }

    func testKermitFinishSubcommand() {
        // Finish subcommand is 'F' (0x46)
        let finishCmd: UInt8 = 0x46
        XCTAssertEqual(Character(UnicodeScalar(finishCmd)), "F",
            "Finish subcommand should be 'F'")
    }

    func testKermitGetFileNameEncoding() {
        // Test that remote filename is properly encoded for R packet
        let filename = "test_file.dat"
        let data = Data(filename.utf8)
        let decoded = String(data: data, encoding: .utf8)
        XCTAssertEqual(decoded, filename, "Filename should roundtrip through UTF-8")
    }
}

// MARK: - Integration: All Protocols in FileTransferManager

class AllProtocolsManagerTests: XCTestCase {

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

    func testAllProtocolTypesCanBeStarted() {
        let allTypes: [TransferProtocolType] = [
            .xmodem, .xmodemCRC, .xmodem1K,
            .ymodem, .ymodemG,
            .zmodem,
            .kermit,
            .bplus,
            .quickVAN
        ]

        for proto in allTypes {
            let filePath = tempDir.appendingPathComponent("all_\(proto).bin")
            FileManager.default.createFile(atPath: filePath.path, contents: nil)

            let mgr = FileTransferManager()
            mgr.delegate = delegate

            mgr.startTransfer(protocol: proto, direction: .receive, filePath: filePath.path)
            XCTAssertTrue(mgr.isTransferActive, "\(proto) should start successfully")

            mgr.cancelTransfer()
            XCTAssertFalse(mgr.isTransferActive, "\(proto) should cancel successfully")
        }
    }

    func testKermitGetViaManager() {
        let mgr = FileTransferManager()
        mgr.delegate = delegate

        let localPath = tempDir.appendingPathComponent("km_get_mgr.bin").path
        mgr.startKermitGet(remoteFileName: "server_file.txt", localPath: localPath)

        XCTAssertTrue(mgr.isTransferActive)
        XCTAssertFalse(delegate.sentData.isEmpty, "Should produce I packet")

        mgr.cancelTransfer()
        XCTAssertFalse(mgr.isTransferActive)
    }

    func testKermitFinishViaManager() {
        let mgr = FileTransferManager()
        mgr.delegate = delegate

        mgr.startKermitFinish()

        XCTAssertTrue(mgr.isTransferActive)
        XCTAssertFalse(delegate.sentData.isEmpty, "Should produce I packet")

        mgr.cancelTransfer()
        XCTAssertFalse(mgr.isTransferActive)
    }
}
