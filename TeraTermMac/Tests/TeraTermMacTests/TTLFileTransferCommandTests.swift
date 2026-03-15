/*
 * TTLFileTransferCommandTests.swift
 * Tests for newly implemented TTL macro commands:
 *   - File transfer: xmodemrecv/send, ymodemrecv/send, zmodemrecv/send,
 *     bplusrecv/send, kmtrecv/send/get/finish, quickvanrecv/send, scprecv/send
 *   - recvfile, restoresetup, callmenu
 *   - setserialdelaychar, setserialdelayline
 *
 * Port of ttl.cpp file transfer and utility command handling to Swift.
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)

// MARK: - File Transfer Command Tests

final class TTLFileTransferCommandTests: XCTestCase {

    var interpreter: TTLInterpreter!
    var delegate: MockTTLDelegate!

    override func setUp() {
        super.setUp()
        interpreter = TTLInterpreter()
        delegate = MockTTLDelegate()
        delegate.isConnected = true
        interpreter.delegate = delegate
    }

    /// Synchronously execute a single TTL command line (non-async path only).
    /// For async commands that set status to .sleep, we just verify dispatch happened.
    private func execLine(_ line: String) throws {
        interpreter.loadScript(line)
        interpreter.prescanLabels()
        guard interpreter.parser.getNewLine() else {
            XCTFail("Failed to get line")
            return
        }
        interpreter.scanLabel()
        try interpreter.execCmnd()
    }

    // MARK: - XMODEM Tests

    func testXmodemRecvDispatchesTransfer() throws {
        try execLine("xmodemrecv '/tmp/recv.dat' 1 2")
        XCTAssertEqual(delegate.lastTransferProtocol, .xmodemCRC)
        XCTAssertEqual(delegate.lastTransferDirection, .receive)
        XCTAssertEqual(delegate.lastTransferFilePath, "/tmp/recv.dat")
    }

    func testXmodemRecvChecksumMode() throws {
        try execLine("xmodemrecv '/tmp/recv.dat' 1 1")
        XCTAssertEqual(delegate.lastTransferProtocol, .xmodem,
            "Option 1 should select checksum mode")
    }

    func testXmodemSendDispatchesTransfer() throws {
        try execLine("xmodemsend '/tmp/send.dat' 3")
        XCTAssertEqual(delegate.lastTransferProtocol, .xmodem1K)
        XCTAssertEqual(delegate.lastTransferDirection, .send)
        XCTAssertEqual(delegate.lastTransferFilePath, "/tmp/send.dat")
    }

    func testXmodemSendDefaultCRC() throws {
        try execLine("xmodemsend '/tmp/send.dat' 2")
        XCTAssertEqual(delegate.lastTransferProtocol, .xmodemCRC)
    }

    // MARK: - YMODEM Tests

    func testYmodemRecvDispatchesTransfer() throws {
        try execLine("ymodemrecv")
        XCTAssertEqual(delegate.lastTransferProtocol, .ymodem)
        XCTAssertEqual(delegate.lastTransferDirection, .receive)
    }

    func testYmodemSendDispatchesTransfer() throws {
        try execLine("ymodemsend '/tmp/file.bin'")
        XCTAssertEqual(delegate.lastTransferProtocol, .ymodem)
        XCTAssertEqual(delegate.lastTransferDirection, .send)
        XCTAssertEqual(delegate.lastTransferFilePath, "/tmp/file.bin")
    }

    // MARK: - ZMODEM Tests

    func testZmodemRecvDispatchesTransfer() throws {
        try execLine("zmodemrecv")
        XCTAssertEqual(delegate.lastTransferProtocol, .zmodem)
        XCTAssertEqual(delegate.lastTransferDirection, .receive)
    }

    func testZmodemSendDispatchesTransfer() throws {
        try execLine("zmodemsend '/tmp/file.bin' 1")
        XCTAssertEqual(delegate.lastTransferProtocol, .zmodem)
        XCTAssertEqual(delegate.lastTransferDirection, .send)
        XCTAssertEqual(delegate.lastTransferFilePath, "/tmp/file.bin")
    }

    // MARK: - B-Plus Tests

    func testBplusRecvDispatchesTransfer() throws {
        try execLine("bplusrecv")
        XCTAssertEqual(delegate.lastTransferProtocol, .bplus)
        XCTAssertEqual(delegate.lastTransferDirection, .receive)
    }

    func testBplusSendDispatchesTransfer() throws {
        try execLine("bplussend '/tmp/file.bin'")
        XCTAssertEqual(delegate.lastTransferProtocol, .bplus)
        XCTAssertEqual(delegate.lastTransferDirection, .send)
    }

    // MARK: - Kermit Tests

    func testKmtRecvDispatchesTransfer() throws {
        try execLine("kmtrecv")
        XCTAssertEqual(delegate.lastTransferProtocol, .kermit)
        XCTAssertEqual(delegate.lastTransferDirection, .receive)
    }

    func testKmtSendDispatchesTransfer() throws {
        try execLine("kmtsend '/tmp/file.bin'")
        XCTAssertEqual(delegate.lastTransferProtocol, .kermit)
        XCTAssertEqual(delegate.lastTransferDirection, .send)
    }

    func testKmtGetDispatchesTransfer() throws {
        try execLine("kmtget 'remote_file.txt'")
        XCTAssertEqual(delegate.lastTransferProtocol, .kermit)
        XCTAssertEqual(delegate.lastTransferFilePath, "remote_file.txt")
    }

    func testKmtFinishDispatchesTransfer() throws {
        try execLine("kmtfinish")
        XCTAssertEqual(delegate.lastTransferProtocol, .kermit)
    }

    // MARK: - Quick-VAN Tests

    func testQuickVANRecvDispatchesTransfer() throws {
        try execLine("quickvanrecv")
        XCTAssertEqual(delegate.lastTransferProtocol, .quickVAN)
        XCTAssertEqual(delegate.lastTransferDirection, .receive)
    }

    func testQuickVANSendDispatchesTransfer() throws {
        try execLine("quickvansend '/tmp/file.bin'")
        XCTAssertEqual(delegate.lastTransferProtocol, .quickVAN)
        XCTAssertEqual(delegate.lastTransferDirection, .send)
    }

    // MARK: - SCP Tests

    func testScpSendDispatchesSCP() throws {
        try execLine("scpsend '/tmp/local.txt' 'remote/path.txt'")
        XCTAssertEqual(delegate.lastScpLocalPath, "/tmp/local.txt")
        XCTAssertEqual(delegate.lastScpRemotePath, "remote/path.txt")
    }

    func testScpSendWithoutRemotePath() throws {
        try execLine("scpsend '/tmp/local.txt'")
        XCTAssertEqual(delegate.lastScpLocalPath, "/tmp/local.txt")
        // Remote path defaults to filename
        XCTAssertEqual(delegate.lastScpRemotePath, "local.txt")
    }

    func testScpRecvDispatchesSCP() throws {
        try execLine("scprecv 'remote/file.txt' '/tmp/local.txt'")
        XCTAssertEqual(delegate.lastScpRemotePath, "remote/file.txt")
        XCTAssertEqual(delegate.lastScpLocalPath, "/tmp/local.txt")
    }

    func testScpRecvWithoutLocalPath() throws {
        try execLine("scprecv 'remote/file.txt'")
        XCTAssertEqual(delegate.lastScpRemotePath, "remote/file.txt")
        // Local path defaults to current directory + filename
        XCTAssertTrue(delegate.lastScpLocalPath?.hasSuffix("/file.txt") == true,
            "Local path should end with /file.txt, got: \(delegate.lastScpLocalPath ?? "nil")")
    }

    // MARK: - RecvFile Tests

    func testRecvFileDispatchesReceive() throws {
        try execLine("recvfile '/tmp/received.dat' 1 5")
        XCTAssertEqual(delegate.lastRecvFilePath, "/tmp/received.dat")
    }

    // MARK: - Requires Connection Tests

    func testFileTransferRequiresConnection() {
        delegate.isConnected = false

        XCTAssertThrowsError(try execLine("xmodemrecv '/tmp/f.dat' 1 2")) { error in
            XCTAssertTrue((error as? TTLError) == .linkFirst,
                "Should throw linkFirst when not connected")
        }
        XCTAssertThrowsError(try execLine("zmodemrecv")) { error in
            XCTAssertTrue((error as? TTLError) == .linkFirst)
        }
        XCTAssertThrowsError(try execLine("kmtfinish")) { error in
            XCTAssertTrue((error as? TTLError) == .linkFirst)
        }
    }
}

// MARK: - Setup / Menu / Serial Delay Command Tests

final class TTLSetupMenuDelayCommandTests: XCTestCase {

    var interpreter: TTLInterpreter!
    var delegate: MockTTLDelegate!

    override func setUp() {
        super.setUp()
        interpreter = TTLInterpreter()
        delegate = MockTTLDelegate()
        delegate.isConnected = true
        interpreter.delegate = delegate
    }

    private func execLine(_ line: String) throws {
        interpreter.loadScript(line)
        interpreter.prescanLabels()
        guard interpreter.parser.getNewLine() else {
            XCTFail("Failed to get line")
            return
        }
        interpreter.scanLabel()
        try interpreter.execCmnd()
    }

    // MARK: - restoresetup

    func testRestoreSetup() throws {
        try execLine("restoresetup '/tmp/settings.json'")
        XCTAssertEqual(delegate.lastRestoreSetupPath, "/tmp/settings.json")
    }

    func testRestoreSetupEmptyFilename() {
        XCTAssertThrowsError(try execLine("restoresetup ''")) { error in
            XCTAssertTrue((error as? TTLError) == .syntax,
                "Empty filename should throw syntax error")
        }
    }

    // MARK: - loadkeymap

    func testLoadKeyMap() throws {
        try execLine("loadkeymap 'keyboard.cnf'")
        XCTAssertEqual(delegate.lastLoadKeyMapPath, "keyboard.cnf")
    }

    func testLoadKeyMapWithFullPath() throws {
        try execLine("loadkeymap '/path/to/IBMKEYB.CNF'")
        XCTAssertEqual(delegate.lastLoadKeyMapPath, "/path/to/IBMKEYB.CNF")
    }

    func testLoadKeyMapEmptyFilename() {
        XCTAssertThrowsError(try execLine("loadkeymap ''")) { error in
            XCTAssertTrue((error as? TTLError) == .syntax,
                "Empty filename should throw syntax error")
        }
    }

    // MARK: - callmenu

    func testCallMenu() throws {
        try execLine("callmenu 50110")
        XCTAssertEqual(delegate.lastCallMenuId, 50110)
    }

    func testCallMenuRequiresConnection() {
        delegate.isConnected = false
        XCTAssertThrowsError(try execLine("callmenu 50110")) { error in
            XCTAssertTrue((error as? TTLError) == .linkFirst)
        }
    }

    // MARK: - setserialdelaychar

    func testSetSerialDelayChar() throws {
        try execLine("setserialdelaychar 100")
        XCTAssertEqual(delegate.lastSerialDelayChar, 100)
    }

    func testSetSerialDelayCharRequiresConnection() {
        delegate.isConnected = false
        XCTAssertThrowsError(try execLine("setserialdelaychar 100")) { error in
            XCTAssertTrue((error as? TTLError) == .linkFirst)
        }
    }

    // MARK: - setserialdelayline

    func testSetSerialDelayLine() throws {
        try execLine("setserialdelayline 200")
        XCTAssertEqual(delegate.lastSerialDelayLine, 200)
    }

    func testSetSerialDelayLineRequiresConnection() {
        delegate.isConnected = false
        XCTAssertThrowsError(try execLine("setserialdelayline 200")) { error in
            XCTAssertTrue((error as? TTLError) == .linkFirst)
        }
    }

    // MARK: - TerminalSettings Serial Delay Properties

    func testSerialDelayProperties() {
        let settings = TerminalSettings()
        XCTAssertEqual(settings.serialDelayPerChar, 0, "Default delay per char should be 0")
        XCTAssertEqual(settings.serialDelayPerLine, 0, "Default delay per line should be 0")

        settings.serialDelayPerChar = 50
        settings.serialDelayPerLine = 100
        XCTAssertEqual(settings.serialDelayPerChar, 50)
        XCTAssertEqual(settings.serialDelayPerLine, 100)
    }
}

// MARK: - Transfer Protocol Type Coverage Tests

final class TTLTransferProtocolCoverageTests: XCTestCase {

    func testAllTransferProtocolTypesExist() {
        // Verify all protocol types needed by TTL commands are available
        let types: [TransferProtocolType] = [
            .xmodem, .xmodemCRC, .xmodem1K,
            .ymodem, .ymodemG,
            .zmodem,
            .kermit,
            .bplus,
            .quickVAN
        ]
        XCTAssertEqual(types.count, 9, "Should have 9 transfer protocol types")
    }

    func testTransferDirectionCases() {
        let directions: [TransferDirection] = [.send, .receive]
        XCTAssertEqual(directions.count, 2)
    }

    func testKermitModeCases() {
        let modes: [KermitMode] = [.receive, .send, .get, .finish]
        XCTAssertEqual(modes.count, 4, "Kermit should have 4 modes")
    }
}

// MARK: - Command Dispatch Registration Tests

final class TTLCommandDispatchTests: XCTestCase {

    func testFileTransferCommandsAreRegistered() {
        // Verify that all file transfer command names resolve to valid TTLCommand cases
        let parser = TTLParser()

        let commands = [
            "bplusrecv", "bplussend",
            "xmodemrecv", "xmodemsend",
            "ymodemrecv", "ymodemsend",
            "zmodemrecv", "zmodemsend",
            "kmtrecv", "kmtsend", "kmtget", "kmtfinish",
            "quickvanrecv", "quickvansend",
            "scprecv", "scpsend",
            "recvfile",
            "restoresetup", "loadkeymap", "callmenu",
            "setserialdelaychar", "setserialdelayline",
        ]

        for cmdName in commands {
            parser.loadScript(cmdName)
            guard parser.getNewLine() else {
                XCTFail("Failed to load: \(cmdName)")
                continue
            }
            parser.linePtr = 0
            let word = parser.getReservedWord()
            XCTAssertNotNil(word,
                "Command '\(cmdName)' should be recognized as a reserved word")
        }
    }

    func testFileTransferCommandsCaseInsensitive() {
        let parser = TTLParser()

        // TTL commands are case-insensitive
        let cases = ["XmodemRecv", "XMODEMSEND", "ZmodemRecv", "KMTFINISH", "ScpSend"]
        for cmdName in cases {
            parser.loadScript(cmdName)
            guard parser.getNewLine() else {
                XCTFail("Failed to load: \(cmdName)")
                continue
            }
            parser.linePtr = 0
            let word = parser.getReservedWord()
            XCTAssertNotNil(word,
                "Command '\(cmdName)' should be case-insensitive")
        }
    }
}

#endif
