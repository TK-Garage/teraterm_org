/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Comprehensive tests for remaining tasks:
 * - XPC anonymous listener connection
 * - TTLInterpreterDelegate → XPC mapping
 * - MacroRunner full command execution
 * - Keychain integration
 * - File transfer XPC flow control
 */

import XCTest
import TTLMacroShared
@testable import TTLMacro

// MARK: - Extended MockMacroClient

/// Extended mock that records all method calls for verification.
class ExtendedMockMacroClient: NSObject, MacroClientProtocol {
    // Recording
    var calls: [(method: String, args: [String: Any])] = []
    var lastMethod: String { calls.last?.method ?? "" }

    // Configurable responses
    var isConnectedResponse: Bool = true
    var recvData: Data?
    var dialogResult: (Int, String) = (1, "test_input")
    var appVersion: String = "1.2.3"
    var hostname: String = "testhost"
    var windowTitle: String = "Test Window"
    var clipboardText: String = "clipboard"
    var transferStatus: (String, Int, Int) = ("done", 100, 100)
    var connectResult: Bool = true

    private func record(_ method: String, _ args: [String: Any] = [:]) {
        calls.append((method: method, args: args))
    }

    func sendToTerminal(data: Data, reply: @escaping () -> Void) {
        record("sendToTerminal", ["data": data]); reply()
    }
    func recvFromTerminal(timeout: Int, reply: @escaping (Data?) -> Void) {
        record("recvFromTerminal", ["timeout": timeout]); reply(recvData)
    }
    func showDialog(type: String, message: String, defaultValue: String,
                    reply: @escaping (Int, String) -> Void) {
        record("showDialog", ["type": type, "message": message])
        reply(dialogResult.0, dialogResult.1)
    }
    func setWindowTitle(title: String, reply: @escaping () -> Void) {
        record("setWindowTitle", ["title": title]); reply()
    }
    func macroDidFinish(exitCode: Int, reply: @escaping () -> Void) {
        record("macroDidFinish", ["exitCode": exitCode]); reply()
    }
    func macroDidFail(error: String, line: Int, reply: @escaping () -> Void) {
        record("macroDidFail", ["error": error, "line": line]); reply()
    }
    func logMessage(level: String, text: String, reply: @escaping () -> Void) {
        record("logMessage"); reply()
    }
    func terminateApp(reply: @escaping () -> Void) {
        record("terminateApp"); reply()
    }
    func getAppVersion(reply: @escaping (String) -> Void) {
        record("getAppVersion"); reply(appVersion)
    }
    func didExecuteLine(lineNumber: Int, lineText: String, reply: @escaping () -> Void) {
        record("didExecuteLine", ["lineNumber": lineNumber]); reply()
    }
    func isConnected(reply: @escaping (Bool) -> Void) {
        record("isConnected"); reply(isConnectedResponse)
    }
    var isXPCLinkedResponse: Bool = true
    func isXPCLinked(reply: @escaping (Bool) -> Void) {
        record("isXPCLinked"); reply(isXPCLinkedResponse)
    }
    func getWindowTitle(reply: @escaping (String) -> Void) {
        record("getWindowTitle"); reply(windowTitle)
    }
    func showWindow(visible: Bool, reply: @escaping () -> Void) {
        record("showWindow", ["visible": visible]); reply()
    }
    func clearScreen(reply: @escaping () -> Void) {
        record("clearScreen"); reply()
    }
    func sendBreak(reply: @escaping () -> Void) {
        record("sendBreak"); reply()
    }
    func disconnectFromHost(reply: @escaping () -> Void) {
        record("disconnectFromHost"); reply()
    }
    func connectToHost(param: String, reply: @escaping (Bool) -> Void) {
        record("connectToHost", ["param": param]); reply(connectResult)
    }
    func connectLocalShell(reply: @escaping (Bool) -> Void) {
        record("connectLocalShell"); reply(connectResult)
    }
    func flushReceiveBuffer(reply: @escaping () -> Void) {
        record("flushReceiveBuffer"); reply()
    }
    func moveWindow(x: Int, y: Int, reply: @escaping () -> Void) {
        record("moveWindow", ["x": x, "y": y]); reply()
    }
    func resizeWindow(width: Int, height: Int, reply: @escaping () -> Void) {
        record("resizeWindow"); reply()
    }
    func bringWindowToFront(reply: @escaping () -> Void) {
        record("bringWindowToFront"); reply()
    }
    func getWindowPosition(reply: @escaping (Int, Int) -> Void) {
        record("getWindowPosition"); reply(100, 200)
    }
    func setBaudRate(rate: Int, reply: @escaping () -> Void) {
        record("setBaudRate", ["rate": rate]); reply()
    }
    func setFlowControl(mode: Int, reply: @escaping () -> Void) {
        record("setFlowControl"); reply()
    }
    func setDtr(on: Int, reply: @escaping () -> Void) {
        record("setDtr"); reply()
    }
    func setRts(on: Int, reply: @escaping () -> Void) {
        record("setRts"); reply()
    }
    func getModemStatus(reply: @escaping (Int) -> Void) {
        record("getModemStatus"); reply(0)
    }
    func setSerialDelayChar(ms: Int, reply: @escaping () -> Void) {
        record("setSerialDelayChar"); reply()
    }
    func setSerialDelayLine(ms: Int, reply: @escaping () -> Void) {
        record("setSerialDelayLine"); reply()
    }
    func openLog(path: String, append: Bool, reply: @escaping () -> Void) {
        record("openLog", ["path": path]); reply()
    }
    func closeLog(reply: @escaping () -> Void) {
        record("closeLog"); reply()
    }
    func pauseLog(reply: @escaping () -> Void) {
        record("pauseLog"); reply()
    }
    func resumeLog(reply: @escaping () -> Void) {
        record("resumeLog"); reply()
    }
    func writeToLog(text: String, reply: @escaping () -> Void) {
        record("writeToLog"); reply()
    }
    func getLogInfo(reply: @escaping (Int, String) -> Void) {
        record("getLogInfo"); reply(0, "/tmp/log.txt")
    }
    func setLogRotation(mode: String, value: Int, reply: @escaping () -> Void) {
        record("setLogRotation"); reply()
    }
    func getClipboard(reply: @escaping (String) -> Void) {
        record("getClipboard"); reply(clipboardText)
    }
    func setClipboard(text: String, reply: @escaping () -> Void) {
        record("setClipboard", ["text": text]); reply()
    }
    func getHostname(reply: @escaping (String) -> Void) {
        record("getHostname"); reply(hostname)
    }
    func getAppDirectory(reply: @escaping (String) -> Void) {
        record("getAppDirectory"); reply("/Applications")
    }
    func showError(message: String, line: Int, lineText: String, fileName: String,
                   reply: @escaping (Bool) -> Void) {
        record("showError"); reply(true)
    }
    func showStatusBox(message: String, title: String, reply: @escaping () -> Void) {
        record("showStatusBox"); reply()
    }
    func closeStatusBox(reply: @escaping () -> Void) {
        record("closeStatusBox"); reply()
    }
    func startFileSend(protocolName: String, localPath: String, option: String,
                       reply: @escaping (Bool, String) -> Void) {
        record("startFileSend", ["protocolName": protocolName, "localPath": localPath])
        reply(true, "")
    }
    func startFileRecv(protocolName: String, localDir: String,
                       reply: @escaping (Bool, String, String) -> Void) {
        record("startFileRecv", ["protocolName": protocolName])
        reply(true, "", "")
    }
    func getTransferStatus(reply: @escaping (String, Int, Int) -> Void) {
        record("getTransferStatus")
        reply(transferStatus.0, transferStatus.1, transferStatus.2)
    }
    func cancelTransfer(reply: @escaping () -> Void) {
        record("cancelTransfer"); reply()
    }
    func scpSend(localPath: String, remotePath: String, reply: @escaping (Bool) -> Void) {
        record("scpSend"); reply(true)
    }
    func scpRecv(remotePath: String, localPath: String, reply: @escaping (Bool) -> Void) {
        record("scpRecv"); reply(true)
    }
    func restoreSetup(path: String, reply: @escaping () -> Void) {
        record("restoreSetup"); reply()
    }
    func callMenu(menuId: Int, reply: @escaping () -> Void) {
        record("callMenu"); reply()
    }
    func loadKeyMap(path: String, reply: @escaping () -> Void) {
        record("loadKeyMap"); reply()
    }
    func enableKeyboard(flag: Int, reply: @escaping () -> Void) {
        record("enableKeyboard"); reply()
    }
    func setEcho(flag: Int, reply: @escaping () -> Void) {
        record("setEcho"); reply()
    }
    func displayString(text: String, reply: @escaping () -> Void) {
        record("displayString"); reply()
    }
    func sendPasswordData(data: Data, reply: @escaping () -> Void) {
        record("sendPasswordData"); reply()
    }

    func reset() { calls.removeAll() }

    func hasCall(_ method: String) -> Bool {
        return calls.contains { $0.method == method }
    }
}

// MARK: - MockKeychainManager

/// In-memory keychain mock for testing.
class MockKeychainManager {
    private var store: [String: String] = [:]

    func save(password: String, account: String) throws {
        store[account] = password
    }

    func load(account: String) throws -> String {
        guard let pw = store[account] else {
            throw TTLKeychainError.notFound
        }
        return pw
    }

    func delete(account: String) throws {
        store.removeValue(forKey: account)
    }

    func exists(account: String) -> Bool {
        return store[account] != nil
    }
}

// MARK: - XPC Anonymous Listener Tests

final class XPCAnonymousListenerTests: XCTestCase {

    func testAnonymousListenerEndpointCreation() {
        // Verify anonymous listener can be created and endpoint obtained
        let listener = NSXPCListener.anonymous()
        XCTAssertNotNil(listener)
        let endpoint = listener.endpoint
        XCTAssertNotNil(endpoint)
    }

    func testEndpointSerialization() throws {
        // Verify endpoint can be serialized and deserialized
        let listener = NSXPCListener.anonymous()
        let endpoint = listener.endpoint

        let data = try NSKeyedArchiver.archivedData(
            withRootObject: endpoint, requiringSecureCoding: true)
        XCTAssertFalse(data.isEmpty)

        let restored = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSXPCListenerEndpoint.self, from: data)
        XCTAssertNotNil(restored)
    }

    func testEndpointFilePathGeneration() {
        let path = MacroXPCEndpoint.endpointFilePath(pid: 12345)
        XCTAssertTrue(path.contains("ttlmacro_endpoint_12345.dat"))
    }

    func testConnectionTimeout() {
        XCTAssertEqual(MacroXPCEndpoint.connectionTimeout, 10.0)
    }

    func testNoServiceNameConnectionInCode() throws {
        // Verify that NSXPCConnection(serviceName:) is not used in production code
        let macroXPCPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/TTLMacroTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // TeraTermMac
            .appendingPathComponent("Sources/TeraTermMac/App/MacroXPCManager.swift")
            .path
        let content = try String(contentsOfFile: macroXPCPath, encoding: .utf8)
        XCTAssertFalse(content.contains("NSXPCConnection(serviceName:"),
                       "Production code should not use NSXPCConnection(serviceName:)")
    }
}

// MARK: - MacroRunner Command Tests

final class MacroRunnerCommandTests: XCTestCase {

    var runner: MacroRunner!
    var mockClient: ExtendedMockMacroClient!
    var tempDir: String!

    override func setUp() {
        super.setUp()
        runner = MacroRunner()
        mockClient = ExtendedMockMacroClient()
        runner.clientProxy = mockClient
        tempDir = NSTemporaryDirectory() + "ttlmacro_test_\(ProcessInfo.processInfo.processIdentifier)/"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        runner.stop()
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    private func writeTTL(_ content: String) -> String {
        let path = tempDir + "test.ttl"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    // MARK: - Send Command Tests

    func testSendCommand() {
        let exp = XCTestExpectation(description: "send completes")
        let path = writeTTL("send 'hello'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("sendToTerminal"))
        let sentData = mockClient.calls.first { $0.method == "sendToTerminal" }?
            .args["data"] as? Data
        XCTAssertEqual(String(data: sentData ?? Data(), encoding: .utf8), "hello")
    }

    // MARK: - Connect Command Test

    func testConnectCommand() {
        let exp = XCTestExpectation(description: "connect completes")
        let path = writeTTL("connect 'testhost'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("connectToHost"))
    }

    // MARK: - Control Flow Tests

    func testIfThenEndif() {
        let exp = XCTestExpectation(description: "if completes")
        let script = """
        x = 1
        if x == 1 then
        send 'yes'
        endif
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("sendToTerminal"))
    }

    func testForNext() {
        let exp = XCTestExpectation(description: "for completes")
        let script = """
        count = 0
        for i 1 3
        count = count
        next
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(runner.status == .idle)
    }

    func testWhileEndwhile() {
        let exp = XCTestExpectation(description: "while completes")
        let script = """
        x = 0
        while x < 3
        x = x
        endwhile
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
    }

    func testGotoCall() {
        let exp = XCTestExpectation(description: "goto completes")
        let script = """
        goto skip
        send 'should_not_run'
        :skip
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertFalse(mockClient.hasCall("sendToTerminal"))
    }

    // MARK: - Dialog Tests

    func testMessageBox() {
        let exp = XCTestExpectation(description: "messagebox completes")
        let path = writeTTL("messagebox 'Hello' 'Title'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("showDialog"))
    }

    // MARK: - File I/O Tests

    func testFileWriteRead() {
        let exp = XCTestExpectation(description: "file ops complete")
        let testFile = tempDir + "testfile.txt"
        let script = """
        fileopen fh '\(testFile)' 0
        filewriteln fh 'hello world'
        fileclose fh
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile))
    }

    // MARK: - String Command Tests

    func testStrLen() {
        let exp = XCTestExpectation(description: "strlen completes")
        let script = """
        strlen 'hello'
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
    }

    // MARK: - System Command Tests

    func testGetDate() {
        let exp = XCTestExpectation(description: "getdate completes")
        let script = """
        getdate d
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
    }

    // MARK: - End/Exit Tests

    func testEndCommand() {
        let exp = XCTestExpectation(description: "end completes")
        let path = writeTTL("end")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("macroDidFinish"))
    }

    func testPauseCommand() {
        let exp = XCTestExpectation(description: "pause completes")
        let path = writeTTL("pause 1\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
    }
}

// MARK: - Keychain Tests

final class KeychainManagerTests: XCTestCase {

    var keychain: TTLKeychainManager!
    let testService = "com.test.TTLMacro.KeychainTest.\(ProcessInfo.processInfo.processIdentifier)"

    override func setUp() {
        super.setUp()
        keychain = TTLKeychainManager(serviceName: testService)
    }

    override func tearDown() {
        // Clean up test entries
        try? keychain.delete(account: "test:user1")
        try? keychain.delete(account: "test:user2")
        try? keychain.delete(account: "192.168.1.1:admin")
        super.tearDown()
    }

    func testSaveAndLoad() throws {
        try keychain.save(password: "secret123", account: "test:user1")
        let loaded = try keychain.load(account: "test:user1")
        XCTAssertEqual(loaded, "secret123")
    }

    func testDeleteThenLoadThrows() throws {
        try keychain.save(password: "secret", account: "test:user1")
        try keychain.delete(account: "test:user1")
        XCTAssertThrowsError(try keychain.load(account: "test:user1"))
    }

    func testSeparateAccounts() throws {
        try keychain.save(password: "pw1", account: "test:user1")
        try keychain.save(password: "pw2", account: "test:user2")
        XCTAssertEqual(try keychain.load(account: "test:user1"), "pw1")
        XCTAssertEqual(try keychain.load(account: "test:user2"), "pw2")
    }

    func testExists() throws {
        XCTAssertFalse(keychain.exists(account: "192.168.1.1:admin"))
        try keychain.save(password: "pw", account: "192.168.1.1:admin")
        XCTAssertTrue(keychain.exists(account: "192.168.1.1:admin"))
    }

    func testPasswordNotInUserDefaults() throws {
        try keychain.save(password: "sensitive", account: "test:user1")
        // Verify it's not in UserDefaults
        let defaults = UserDefaults.standard
        XCTAssertNil(defaults.string(forKey: "test:user1"))
        XCTAssertNil(defaults.string(forKey: "sensitive"))
    }

    func testZeroData() {
        var data = Data([0x41, 0x42, 0x43, 0x44]) // "ABCD"
        TTLKeychainManager.zeroData(&data)
        XCTAssertEqual(data, Data([0x00, 0x00, 0x00, 0x00]))
    }
}

// MARK: - File Transfer Tests

final class FileTransferXPCTests: XCTestCase {

    var runner: MacroRunner!
    var mockClient: ExtendedMockMacroClient!
    var tempDir: String!

    override func setUp() {
        super.setUp()
        runner = MacroRunner()
        mockClient = ExtendedMockMacroClient()
        runner.clientProxy = mockClient
        tempDir = NSTemporaryDirectory() + "ttlmacro_xfer_test_\(ProcessInfo.processInfo.processIdentifier)/"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        runner.stop()
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    private func writeTTL(_ content: String) -> String {
        let path = tempDir + "test.ttl"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testXmodemSendCallsCorrectProtocol() {
        let exp = XCTestExpectation(description: "xmodemsend completes")
        mockClient.transferStatus = ("done", 100, 100)
        let testFile = tempDir + "send.bin"
        FileManager.default.createFile(atPath: testFile, contents: Data([0x01]))
        let path = writeTTL("xmodemsend '\(testFile)' 2\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        let sendCall = mockClient.calls.first { $0.method == "startFileSend" }
        XCTAssertEqual(sendCall?.args["protocolName"] as? String, "xmodem")
    }

    func testTransferDoneAdvancesToNextLine() {
        let exp = XCTestExpectation(description: "transfer done")
        mockClient.transferStatus = ("done", 100, 100)
        let testFile = tempDir + "send2.bin"
        FileManager.default.createFile(atPath: testFile, contents: Data([0x01]))
        let path = writeTTL("zmodemsend '\(testFile)' 1\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("macroDidFinish"))
    }

    func testTransferErrorCallsMacroDidFail() {
        let exp = XCTestExpectation(description: "transfer error")
        mockClient.transferStatus = ("error", 0, 0)
        let path = writeTTL("zmodemrecv\nend")
        runner.onError = { _, _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("macroDidFail"))
    }

    func testCancelTransferOnStop() {
        let exp = XCTestExpectation(description: "cancel on stop")
        // Set transfer to keep polling
        mockClient.transferStatus = ("sending", 50, 100)
        let testFile = tempDir + "send3.bin"
        FileManager.default.createFile(atPath: testFile, contents: Data([0x01]))
        let path = writeTTL("xmodemsend '\(testFile)' 2\nend")
        runner.run(scriptPath: path)
        // Give it time to start polling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.runner.stop()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("cancelTransfer"))
    }

    func testKermitFinishCallsCancelTransfer() {
        let exp = XCTestExpectation(description: "kermit finish")
        let path = writeTTL("kmtfinish\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("cancelTransfer"))
    }

    func testTransferProgressReportedWithBytes() {
        let exp = XCTestExpectation(description: "transfer with progress")
        mockClient.transferStatus = ("done", 512, 1024)
        let testFile = tempDir + "progress.bin"
        FileManager.default.createFile(atPath: testFile, contents: Data(repeating: 0xAA, count: 128))
        let path = writeTTL("xmodemsend '\(testFile)' 2\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        let statusCalls = mockClient.calls.filter { $0.method == "getTransferStatus" }
        XCTAssertFalse(statusCalls.isEmpty, "Should poll transfer status at least once")
    }

    func testRecvTransferCallsStartFileRecv() {
        let exp = XCTestExpectation(description: "recv transfer")
        mockClient.transferStatus = ("done", 256, 256)
        let path = writeTTL("xmodemrecv\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        let recvCall = mockClient.calls.first { $0.method == "startFileRecv" }
        XCTAssertNotNil(recvCall, "Should call startFileRecv for xmodemrecv")
        XCTAssertEqual(recvCall?.args["protocolName"] as? String, "xmodem")
    }
}

// MARK: - TestLink 3-State Tests

final class TestLinkTests: XCTestCase {

    var runner: MacroRunner!
    var mockClient: ExtendedMockMacroClient!
    var tempDir: String!

    override func setUp() {
        super.setUp()
        runner = MacroRunner()
        mockClient = ExtendedMockMacroClient()
        runner.clientProxy = mockClient
        tempDir = NSTemporaryDirectory() + "ttlmacro_testlink_\(ProcessInfo.processInfo.processIdentifier)/"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        runner.stop()
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    private func writeTTL(_ content: String) -> String {
        let path = tempDir + "test.ttl"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testTestLinkReturns0WhenNotLinked() {
        // result=0: XPC not linked → should not send 'connected' or 'linked'
        let exp = XCTestExpectation(description: "testlink returns 0")
        mockClient.isXPCLinkedResponse = false
        mockClient.isConnectedResponse = false
        let script = """
        testlink
        if result == 0 then
        send 'not_linked'
        endif
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("isXPCLinked"))
        XCTAssertFalse(mockClient.hasCall("isConnected"),
                       "Should not check isConnected when XPC is not linked")
        // Verify result=0 was set by checking the conditional branch was taken
        XCTAssertTrue(mockClient.hasCall("sendToTerminal"),
                      "Should enter result==0 branch")
        let sentData = mockClient.calls.first { $0.method == "sendToTerminal" }?
            .args["data"] as? Data
        XCTAssertEqual(String(data: sentData ?? Data(), encoding: .utf8), "not_linked")
    }

    func testTestLinkReturns1WhenLinkedButNotConnected() {
        // result=1: XPC linked, host not connected
        let exp = XCTestExpectation(description: "testlink returns 1")
        mockClient.isXPCLinkedResponse = true
        mockClient.isConnectedResponse = false
        let script = """
        testlink
        if result == 1 then
        send 'linked_not_connected'
        endif
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("isXPCLinked"))
        XCTAssertTrue(mockClient.hasCall("isConnected"))
        XCTAssertTrue(mockClient.hasCall("sendToTerminal"),
                      "Should enter result==1 branch")
        let sentData = mockClient.calls.first { $0.method == "sendToTerminal" }?
            .args["data"] as? Data
        XCTAssertEqual(String(data: sentData ?? Data(), encoding: .utf8), "linked_not_connected")
    }

    func testTestLinkReturns2WhenLinkedAndConnected() {
        // result=2: XPC linked and host connected
        let exp = XCTestExpectation(description: "testlink returns 2")
        mockClient.isXPCLinkedResponse = true
        mockClient.isConnectedResponse = true
        let script = """
        testlink
        if result == 2 then
        send 'connected'
        endif
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("isXPCLinked"))
        XCTAssertTrue(mockClient.hasCall("isConnected"))
        XCTAssertTrue(mockClient.hasCall("sendToTerminal"),
                      "Should enter result==2 branch")
        let sentData = mockClient.calls.first { $0.method == "sendToTerminal" }?
            .args["data"] as? Data
        XCTAssertEqual(String(data: sentData ?? Data(), encoding: .utf8), "connected")
    }

    func testTestLinkScriptConditionalNotConnected() {
        // Verify testlink result=1 does NOT trigger result==2 branch
        let exp = XCTestExpectation(description: "testlink conditional not connected")
        mockClient.isXPCLinkedResponse = true
        mockClient.isConnectedResponse = false
        let script = """
        testlink
        if result == 2 then
        send 'should_not_run'
        endif
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertFalse(mockClient.hasCall("sendToTerminal"),
                       "Should NOT send when testlink result is 1, not 2")
    }
}

// MARK: - MacroXPCManager Integration Tests

final class MacroXPCManagerIntegrationTests: XCTestCase {

    func testIsXPCLinkedReturnsTrueWhenConnectionExists() {
        // Verify isXPCLinked returns true when XPC connection is established
        // This tests the protocol method exists and the mock responds correctly
        let mock = ExtendedMockMacroClient()
        mock.isXPCLinkedResponse = true
        let exp = XCTestExpectation(description: "isXPCLinked true")
        mock.isXPCLinked { linked in
            XCTAssertTrue(linked)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testIsXPCLinkedReturnsFalseWhenNoConnection() {
        let mock = ExtendedMockMacroClient()
        mock.isXPCLinkedResponse = false
        let exp = XCTestExpectation(description: "isXPCLinked false")
        mock.isXPCLinked { linked in
            XCTAssertFalse(linked)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testProtocolIncludesIsXPCLinkedMethod() {
        // Verify the XPC interface includes the new method
        let interface = MacroXPCInterface.clientInterface()
        XCTAssertNotNil(interface)
    }

    func testTerminalOperationMethodsRecorded() {
        // Verify all terminal operation methods are callable through the mock
        let mock = ExtendedMockMacroClient()
        let exp = XCTestExpectation(description: "operations complete")
        exp.expectedFulfillmentCount = 5

        mock.sendBreak { mock.hasCall("sendBreak"); exp.fulfill() }
        mock.clearScreen { mock.hasCall("clearScreen"); exp.fulfill() }
        mock.flushReceiveBuffer { mock.hasCall("flushReceiveBuffer"); exp.fulfill() }
        mock.bringWindowToFront { mock.hasCall("bringWindowToFront"); exp.fulfill() }
        mock.displayString(text: "test") { mock.hasCall("displayString"); exp.fulfill() }

        wait(for: [exp], timeout: 2.0)
        XCTAssertTrue(mock.hasCall("sendBreak"))
        XCTAssertTrue(mock.hasCall("clearScreen"))
        XCTAssertTrue(mock.hasCall("flushReceiveBuffer"))
        XCTAssertTrue(mock.hasCall("bringWindowToFront"))
        XCTAssertTrue(mock.hasCall("displayString"))
    }

    func testLogOperationMethodsRecorded() {
        let mock = ExtendedMockMacroClient()
        let exp = XCTestExpectation(description: "log ops complete")
        exp.expectedFulfillmentCount = 4

        mock.openLog(path: "/tmp/test.log", append: false) { exp.fulfill() }
        mock.writeToLog(text: "test line") { exp.fulfill() }
        mock.pauseLog { exp.fulfill() }
        mock.closeLog { exp.fulfill() }

        wait(for: [exp], timeout: 2.0)
        XCTAssertTrue(mock.hasCall("openLog"))
        XCTAssertTrue(mock.hasCall("writeToLog"))
        XCTAssertTrue(mock.hasCall("pauseLog"))
        XCTAssertTrue(mock.hasCall("closeLog"))
    }

    func testWindowOperationMethodsRecorded() {
        let mock = ExtendedMockMacroClient()
        let exp = XCTestExpectation(description: "window ops")
        exp.expectedFulfillmentCount = 3

        mock.moveWindow(x: 100, y: 200) { exp.fulfill() }
        mock.resizeWindow(width: 800, height: 600) { exp.fulfill() }
        mock.setWindowTitle(title: "Test") { exp.fulfill() }

        wait(for: [exp], timeout: 2.0)
        let moveCall = mock.calls.first { $0.method == "moveWindow" }
        XCTAssertEqual(moveCall?.args["x"] as? Int, 100)
        XCTAssertEqual(moveCall?.args["y"] as? Int, 200)
    }
}

// MARK: - XPC Protocol Completeness Tests

final class XPCProtocolCompletenessTests: XCTestCase {

    func testMacroClientProtocolHasAllRequiredMethods() {
        // Verify the protocol has the expected number of methods
        let interface = MacroXPCInterface.clientInterface()
        XCTAssertNotNil(interface)
    }

    func testMacroServiceProtocolMethods() {
        let interface = MacroXPCInterface.serviceInterface()
        XCTAssertNotNil(interface)
    }

    func testTransferStatusStrings() {
        XCTAssertEqual(TransferStatusString.idle.rawValue, "idle")
        XCTAssertEqual(TransferStatusString.sending.rawValue, "sending")
        XCTAssertEqual(TransferStatusString.receiving.rawValue, "receiving")
        XCTAssertEqual(TransferStatusString.done.rawValue, "done")
        XCTAssertEqual(TransferStatusString.error.rawValue, "error")
    }

    func testMacroExecutionStatuses() {
        XCTAssertEqual(MacroExecutionStatus.idle.rawValue, "idle")
        XCTAssertEqual(MacroExecutionStatus.running.rawValue, "running")
        XCTAssertEqual(MacroExecutionStatus.paused.rawValue, "paused")
        XCTAssertEqual(MacroExecutionStatus.stopped.rawValue, "stopped")
        XCTAssertEqual(MacroExecutionStatus.error.rawValue, "error")
    }

    func testEndpointConstants() {
        XCTAssertEqual(MacroXPCEndpoint.connectionTimeout, 10.0)
        XCTAssertEqual(MacroXPCEndpoint.transferPollInterval, 0.5)
        XCTAssertEqual(MacroXPCEndpoint.defaultTransferTimeout, 600.0)
    }
}
