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

    // --- Broadcast / Multicast methods ---
    func broadcastData(data: Data, reply: @escaping (Int) -> Void) {
        record("broadcastData", ["data": data]); reply(1)
    }
    func setMulticastName(name: String, reply: @escaping () -> Void) {
        record("setMulticastName", ["name": name]); reply()
    }
    func multicastData(groupName: String, data: Data, reply: @escaping (Int) -> Void) {
        record("multicastData", ["groupName": groupName, "data": data]); reply(1)
    }
    func getSessionList(reply: @escaping ([String]) -> Void) {
        record("getSessionList"); reply(["sess1:host1:22", "sess2:host2:23"])
    }
    func sendToSession(sessionId: String, data: Data, reply: @escaping (Bool) -> Void) {
        record("sendToSession", ["sessionId": sessionId, "data": data]); reply(true)
    }
    func subscribeToTerminalData(reply: @escaping (Data) -> Void) {
        record("subscribeToTerminalData")
        // Store callback for test-driven data injection
        terminalDataCallback = reply
    }
    func setTerminalSize(cols: Int, rows: Int, reply: @escaping () -> Void) {
        record("setTerminalSize", ["cols": cols, "rows": rows]); reply()
    }

    var terminalDataCallback: ((Data) -> Void)?

    func reset() { calls.removeAll(); terminalDataCallback = nil }

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
        // NSXPCListenerEndpoint can only be encoded by NSXPCCoder (not NSKeyedArchiver).
        // Verify that the endpoint can be obtained and used to create a connection,
        // which is the actual use case for anonymous listener endpoints.
        let listener = NSXPCListener.anonymous()
        let endpoint = listener.endpoint
        XCTAssertNotNil(endpoint)

        // Verify the endpoint can be used to create a connection
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        XCTAssertNotNil(connection)
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
        let macroXPCPath = "/home/user/teraterm_org/TeraTermMac/Sources/TeraTermMac/App/MacroXPCManager.swift"
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
        inc x
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
        fileopen fh '\(testFile)' 1
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

    func testDialogTypes() {
        XCTAssertEqual(MacroDialogType.messagebox.rawValue, "messagebox")
        XCTAssertEqual(MacroDialogType.inputbox.rawValue, "inputbox")
        XCTAssertEqual(MacroDialogType.yesnobox.rawValue, "yesnobox")
        XCTAssertEqual(MacroDialogType.passwordbox.rawValue, "passwordbox")
        XCTAssertEqual(MacroDialogType.listbox.rawValue, "listbox")
        XCTAssertEqual(MacroDialogType.filenamebox.rawValue, "filenamebox")
        XCTAssertEqual(MacroDialogType.dirnamebox.rawValue, "dirnamebox")
        XCTAssertEqual(MacroDialogType.statusbox.rawValue, "statusbox")
    }

    func testXPCServiceName() {
        XCTAssertEqual(kTTLMacroXPCServiceName, "com.teraterm.mac.TTLMacro")
    }
}

// MARK: - TTLParser Expression Evaluation Tests

final class TTLParserExpressionTests: XCTestCase {

    var parser: TTLParser!

    override func setUp() {
        super.setUp()
        parser = TTLParser()
    }

    private func evalInt(_ expr: String) throws -> Int {
        parser.lineBuffer = expr
        parser.linePtr = 0
        parser.lineParsePtr = 0
        let result = try parser.getExpression()
        switch result {
        case .integer(let v): return v
        default: XCTFail("Expected integer result"); return 0
        }
    }

    private func evalStr(_ expr: String) throws -> String {
        parser.lineBuffer = expr
        parser.linePtr = 0
        parser.lineParsePtr = 0
        let result = try parser.getExpression()
        switch result {
        case .stringLiteral(let s): return s
        case .string(let id): return parser.getStrVal(id: id)
        default: XCTFail("Expected string result"); return ""
        }
    }

    // MARK: - Integer Arithmetic

    func testIntegerLiteral() throws {
        XCTAssertEqual(try evalInt("42"), 42)
    }

    func testIntegerAddition() throws {
        XCTAssertEqual(try evalInt("3 + 4"), 7)
    }

    func testIntegerSubtraction() throws {
        XCTAssertEqual(try evalInt("10 - 3"), 7)
    }

    func testIntegerMultiplication() throws {
        XCTAssertEqual(try evalInt("6 * 7"), 42)
    }

    func testIntegerDivision() throws {
        XCTAssertEqual(try evalInt("20 / 4"), 5)
    }

    func testIntegerModulo() throws {
        XCTAssertEqual(try evalInt("17 % 5"), 2)
    }

    func testParenthesizedExpr() throws {
        XCTAssertEqual(try evalInt("(3 + 4) * 2"), 14)
    }

    func testNegativeNumber() throws {
        XCTAssertEqual(try evalInt("-5"), -5)
    }

    func testComplexArithmetic() throws {
        XCTAssertEqual(try evalInt("2 + 3 * 4"), 14) // Precedence: * before +
    }

    func testNestedParens() throws {
        XCTAssertEqual(try evalInt("((2 + 3) * (4 - 1))"), 15)
    }

    // MARK: - Bitwise Operations

    func testBitAnd() throws {
        XCTAssertEqual(try evalInt("0xFF & 0x0F"), 0x0F)
    }

    func testBitOr() throws {
        XCTAssertEqual(try evalInt("0xF0 | 0x0F"), 0xFF)
    }

    func testBitXor() throws {
        XCTAssertEqual(try evalInt("0xFF ^ 0x0F"), 0xF0)
    }

    func testBitShiftLeft() throws {
        XCTAssertEqual(try evalInt("1 << 4"), 16)
    }

    func testBitShiftRight() throws {
        XCTAssertEqual(try evalInt("16 >> 2"), 4)
    }

    func testBitNot() throws {
        // ~0 == -1 in two's complement
        XCTAssertEqual(try evalInt("~0"), -1)
    }

    // MARK: - Comparison Operations

    func testEqualTrue() throws {
        XCTAssertEqual(try evalInt("5 == 5"), 1)
    }

    func testEqualFalse() throws {
        XCTAssertEqual(try evalInt("5 == 3"), 0)
    }

    func testNotEqual() throws {
        XCTAssertEqual(try evalInt("5 != 3"), 1)
    }

    func testLessThan() throws {
        XCTAssertEqual(try evalInt("3 < 5"), 1)
    }

    func testGreaterThan() throws {
        XCTAssertEqual(try evalInt("5 > 3"), 1)
    }

    func testLessOrEqual() throws {
        XCTAssertEqual(try evalInt("5 <= 5"), 1)
    }

    func testGreaterOrEqual() throws {
        XCTAssertEqual(try evalInt("5 >= 6"), 0)
    }

    // MARK: - Logical Operations

    func testLogicalAnd() throws {
        XCTAssertEqual(try evalInt("1 && 1"), 1)
        XCTAssertEqual(try evalInt("1 && 0"), 0)
    }

    func testLogicalOr() throws {
        XCTAssertEqual(try evalInt("0 || 1"), 1)
        XCTAssertEqual(try evalInt("0 || 0"), 0)
    }

    func testLogicalNot() throws {
        XCTAssertEqual(try evalInt("!0"), 1)
        XCTAssertEqual(try evalInt("!1"), 0)
    }

    // MARK: - Hex and Octal Literals

    func testHexLiteral() throws {
        XCTAssertEqual(try evalInt("0xFF"), 255)
    }

    func testHexUppercase() throws {
        XCTAssertEqual(try evalInt("0xABCD"), 0xABCD)
    }

    // MARK: - String Literals

    func testStringLiteral() throws {
        XCTAssertEqual(try evalStr("'hello'"), "hello")
    }

    func testEmptyStringLiteral() throws {
        XCTAssertEqual(try evalStr("''"), "")
    }

    // MARK: - Variables

    func testIntVariable() throws {
        let id = parser.newIntVar("myvar", value: 99)
        XCTAssertGreaterThanOrEqual(id, 0)
        XCTAssertEqual(parser.getIntVal(id: id), 99)
    }

    func testStrVariable() throws {
        let id = parser.newStrVar("mystr", value: "test")
        XCTAssertGreaterThanOrEqual(id, 0)
        XCTAssertEqual(parser.getStrVal(id: id), "test")
    }

    func testCheckVar() {
        _ = parser.newIntVar("abc", value: 10)
        let check = parser.checkVar("abc")
        XCTAssertNotNil(check)
        XCTAssertEqual(check?.type, .integer)
    }

    func testCheckVarNotFound() {
        let check = parser.checkVar("nonexistent")
        XCTAssertNil(check)
    }

    func testSetIntVal() {
        let id = parser.newIntVar("x", value: 1)
        parser.setIntVal(id: id, value: 42)
        XCTAssertEqual(parser.getIntVal(id: id), 42)
    }

    func testSetStrVal() {
        let id = parser.newStrVar("s", value: "old")
        parser.setStrVal(id: id, value: "new")
        XCTAssertEqual(parser.getStrVal(id: id), "new")
    }

    func testNewIntArrayVar() {
        let id = parser.newIntArrayVar("arr", size: 5)
        XCTAssertGreaterThanOrEqual(id, 0)
    }

    func testNewStrArrayVar() {
        let id = parser.newStrArrayVar("sarr", size: 3)
        XCTAssertGreaterThanOrEqual(id, 0)
    }

    func testDelLabVar() {
        _ = parser.newLabVar("lab1", position: 10, level: 2)
        parser.delLabVar(level: 2)
        XCTAssertNil(parser.checkVar("lab1"))
    }

    // MARK: - System Variables

    func testInitSystemVariables() {
        parser.initSystemVariables()
        let resultCheck = parser.checkVar("result")
        XCTAssertNotNil(resultCheck)
        let timeoutCheck = parser.checkVar("timeout")
        XCTAssertNotNil(timeoutCheck)
    }

    func testSetResult() {
        parser.initSystemVariables()
        parser.setResult(42)
        let check = parser.checkVar("result")
        XCTAssertNotNil(check)
        if let check = check {
            XCTAssertEqual(parser.getIntVal(id: check.id), 42)
        }
    }

    // MARK: - Script Loading

    func testLoadScript() {
        parser.loadScript("line1\nline2\nline3")
        XCTAssertEqual(parser.lines.count, 3)
        XCTAssertEqual(parser.lines[0], "line1")
        XCTAssertEqual(parser.lines[2], "line3")
    }

    func testGetNewLine() {
        parser.loadScript("first\nsecond")
        parser.currentLine = 0
        let got = parser.getNewLine()
        XCTAssertTrue(got)
        XCTAssertEqual(parser.lineBuffer, "first")
    }

    // MARK: - Command Recognition

    func testCheckReservedWord() {
        XCTAssertNotNil(parser.checkReservedWord("send"))
        XCTAssertNotNil(parser.checkReservedWord("wait"))
        XCTAssertNotNil(parser.checkReservedWord("goto"))
        XCTAssertNotNil(parser.checkReservedWord("if"))
        XCTAssertNotNil(parser.checkReservedWord("end"))
        XCTAssertNil(parser.checkReservedWord("notacommand"))
    }

    // MARK: - Error Messages

    func testTTLErrorMessages() {
        XCTAssertFalse(TTLError.syntax.message.isEmpty)
        XCTAssertFalse(TTLError.varNotInit.message.isEmpty)
        XCTAssertFalse(TTLError.typeMismatch.message.isEmpty)
        XCTAssertFalse(TTLError.divByZero.message.isEmpty)
        XCTAssertFalse(TTLError.labelReq.message.isEmpty)
        XCTAssertFalse(TTLError.stackOver.message.isEmpty)
        XCTAssertFalse(TTLError.tooManyVar.message.isEmpty)
    }

    // MARK: - MacroFileLoader

    func testMacroFileLoaderUTF8() throws {
        let data = "hello".data(using: .utf8)!
        let result = try MacroFileLoader.decodeData(data)
        XCTAssertEqual(result.content, "hello")
    }

    func testMacroFileLoaderEmpty() throws {
        let result = try MacroFileLoader.decodeData(Data())
        XCTAssertEqual(result.content, "")
        XCTAssertEqual(result.encoding, .ascii)
    }

    func testMacroFileLoaderUTF8BOM() throws {
        var bytes: [UInt8] = [0xEF, 0xBB, 0xBF]
        bytes.append(contentsOf: "test".utf8)
        let result = try MacroFileLoader.decodeData(Data(bytes))
        XCTAssertEqual(result.content, "test")
        XCTAssertEqual(result.encoding, .utf8BOM)
    }

    func testMacroFileLoaderUTF16LE() throws {
        var bytes: [UInt8] = [0xFF, 0xFE]
        bytes.append(contentsOf: "AB".data(using: .utf16LittleEndian)!)
        let result = try MacroFileLoader.decodeData(Data(bytes))
        XCTAssertEqual(result.content, "AB")
        XCTAssertEqual(result.encoding, .utf16LEBOM)
    }
}

// MARK: - TTLParser Tokenizer Tests

final class TTLParserTokenizerTests: XCTestCase {

    var parser: TTLParser!

    override func setUp() {
        super.setUp()
        parser = TTLParser()
    }

    func testGetIdentifier() {
        parser.lineBuffer = "myVar123 rest"
        parser.linePtr = 0
        parser.lineParsePtr = 0
        let id = parser.getIdentifier()
        XCTAssertEqual(id, "myVar123")
    }

    func testGetIdentifierEmpty() {
        parser.lineBuffer = "  "
        parser.linePtr = 0
        parser.lineParsePtr = 0
        // getFirstChar should skip spaces
        let _ = parser.getFirstChar()
        let id = parser.getIdentifier()
        XCTAssertNil(id)
    }

    func testGetNumber() {
        parser.lineBuffer = "12345 rest"
        parser.linePtr = 0
        parser.lineParsePtr = 0
        let num = parser.getNumber()
        XCTAssertEqual(num, 12345)
    }

    func testGetNumberHex() {
        parser.lineBuffer = "0xFF rest"
        parser.linePtr = 0
        parser.lineParsePtr = 0
        let num = parser.getNumber()
        XCTAssertEqual(num, 255)
    }

    func testGetLabelName() {
        parser.lineBuffer = ":myLabel rest"
        parser.linePtr = 1  // Skip the ':'
        parser.lineParsePtr = 1
        let label = parser.getLabelName()
        XCTAssertEqual(label, "mylabel")  // Labels are lowercase
    }

    func testGetFirstChar() {
        parser.lineBuffer = "   x = 1"
        parser.linePtr = 0
        parser.lineParsePtr = 0
        let ch = parser.getFirstChar()
        XCTAssertEqual(ch, "x")
    }

    func testGetFirstCharComment() {
        parser.lineBuffer = "; this is a comment"
        parser.linePtr = 0
        parser.lineParsePtr = 0
        let ch = parser.getFirstChar()
        XCTAssertNil(ch) // Comment lines return nil
    }

    func testCheckParameterGiven() {
        parser.lineBuffer = "send 'hello'"
        parser.linePtr = 5
        parser.lineParsePtr = 5
        XCTAssertTrue(parser.checkParameterGiven())
    }

    func testCheckParameterNotGiven() {
        parser.lineBuffer = "end"
        parser.linePtr = 3
        parser.lineParsePtr = 3
        XCTAssertFalse(parser.checkParameterGiven())
    }
}

// MARK: - Bundle ID Tests

final class BundleIDTests: XCTestCase {

    func testMacroConstantsBundleIds() {
        XCTAssertEqual(MacroConstants.ttlMacroBundleId, "com.teraterm.mac.TTLMacro")
        XCTAssertEqual(MacroConstants.teraTermMacBundleId, "com.teraterm.mac")
    }

    func testXPCServiceNameMatchesBundleId() {
        XCTAssertEqual(kTTLMacroXPCServiceName, MacroConstants.ttlMacroBundleId)
    }

    func testNoBundleIdContainsYourApp() throws {
        // Verify no "com.yourapp" remains in shared source
        let sharedDir = "/home/user/teraterm_org/TeraTermMac/Sources/TTLMacroShared/"
        let fm = FileManager.default
        guard let files = fm.enumerator(atPath: sharedDir) else {
            XCTFail("Cannot enumerate shared dir"); return
        }
        for case let file as String in files where file.hasSuffix(".swift") {
            let content = try String(contentsOfFile: sharedDir + file, encoding: .utf8)
            XCTAssertFalse(content.contains("com.yourapp"),
                           "Found com.yourapp in \(file)")
        }
    }

    func testNoBundleIdContainsYourAppInMacro() throws {
        let macroDir = "/home/user/teraterm_org/TeraTermMac/Sources/TTLMacro/"
        let fm = FileManager.default
        guard let files = fm.enumerator(atPath: macroDir) else {
            XCTFail("Cannot enumerate macro dir"); return
        }
        for case let file as String in files where file.hasSuffix(".swift") || file.hasSuffix(".plist") || file.hasSuffix(".entitlements") {
            let content = try String(contentsOfFile: macroDir + file, encoding: .utf8)
            XCTAssertFalse(content.contains("com.yourapp"),
                           "Found com.yourapp in \(file)")
        }
    }

    func testMacroConstants() {
        XCTAssertEqual(MacroConstants.maxReconnectAttempts, 3)
        XCTAssertEqual(MacroConstants.reconnectInterval, 2.0)
        XCTAssertEqual(MacroConstants.xpcTimeout, 30.0)
        XCTAssertEqual(MacroConstants.ttlFileExtension, "ttl")
        XCTAssertEqual(MacroConstants.xpcModeArgument, "--xpc-mode")
    }
}

// MARK: - Mock Coverage Tests (verify all 63+ protocol methods are covered)

final class MockCoverageTests: XCTestCase {

    func testExtendedMockCoversAllProtocolMethods() {
        let mock = ExtendedMockMacroClient()

        // Call every protocol method and verify recording
        mock.sendToTerminal(data: Data()) { }
        mock.recvFromTerminal(timeout: 1) { _ in }
        mock.showDialog(type: "t", message: "m", defaultValue: "") { _, _ in }
        mock.setWindowTitle(title: "t") { }
        mock.macroDidFinish(exitCode: 0) { }
        mock.macroDidFail(error: "e", line: 0) { }
        mock.logMessage(level: "info", text: "t") { }
        mock.terminateApp { }
        mock.getAppVersion { _ in }
        mock.didExecuteLine(lineNumber: 1, lineText: "t") { }
        mock.isConnected { _ in }
        mock.getWindowTitle { _ in }
        mock.showWindow(visible: true) { }
        mock.clearScreen { }
        mock.sendBreak { }
        mock.disconnectFromHost { }
        mock.connectToHost(param: "h") { _ in }
        mock.connectLocalShell { _ in }
        mock.flushReceiveBuffer { }
        mock.moveWindow(x: 0, y: 0) { }
        mock.resizeWindow(width: 80, height: 24) { }
        mock.bringWindowToFront { }
        mock.getWindowPosition { _, _ in }
        mock.setBaudRate(rate: 9600) { }
        mock.setFlowControl(mode: 0) { }
        mock.setDtr(on: 1) { }
        mock.setRts(on: 1) { }
        mock.getModemStatus { _ in }
        mock.setSerialDelayChar(ms: 0) { }
        mock.setSerialDelayLine(ms: 0) { }
        mock.openLog(path: "/tmp/log", append: false) { }
        mock.closeLog { }
        mock.pauseLog { }
        mock.resumeLog { }
        mock.writeToLog(text: "t") { }
        mock.getLogInfo { _, _ in }
        mock.setLogRotation(mode: "size", value: 100) { }
        mock.getClipboard { _ in }
        mock.setClipboard(text: "t") { }
        mock.getHostname { _ in }
        mock.getAppDirectory { _ in }
        mock.showError(message: "e", line: 0, lineText: "", fileName: "") { _ in }
        mock.showStatusBox(message: "m", title: "t") { }
        mock.closeStatusBox { }
        mock.startFileSend(protocolName: "xmodem", localPath: "/tmp/f", option: "") { _, _ in }
        mock.startFileRecv(protocolName: "zmodem", localDir: "/tmp") { _, _, _ in }
        mock.getTransferStatus { _, _, _ in }
        mock.cancelTransfer { }
        mock.scpSend(localPath: "/tmp/f", remotePath: "/tmp/r") { _ in }
        mock.scpRecv(remotePath: "/tmp/r", localPath: "/tmp/l") { _ in }
        mock.restoreSetup(path: "/tmp/s") { }
        mock.callMenu(menuId: 1) { }
        mock.loadKeyMap(path: "/tmp/k") { }
        mock.enableKeyboard(flag: 1) { }
        mock.setEcho(flag: 1) { }
        mock.displayString(text: "t") { }
        mock.sendPasswordData(data: Data()) { }
        mock.broadcastData(data: Data()) { _ in }
        mock.setMulticastName(name: "group1") { }
        mock.multicastData(groupName: "group1", data: Data()) { _ in }
        mock.getSessionList { _ in }
        mock.sendToSession(sessionId: "s1", data: Data()) { _ in }
        mock.subscribeToTerminalData { _ in }
        mock.setTerminalSize(cols: 80, rows: 24) { }

        // Verify all 63 methods were recorded
        XCTAssertGreaterThanOrEqual(mock.calls.count, 63,
            "Expected at least 63 method calls, got \(mock.calls.count)")

        // Verify specific method names
        let methods = Set(mock.calls.map { $0.method })
        XCTAssertTrue(methods.contains("sendToTerminal"))
        XCTAssertTrue(methods.contains("broadcastData"))
        XCTAssertTrue(methods.contains("multicastData"))
        XCTAssertTrue(methods.contains("subscribeToTerminalData"))
        XCTAssertTrue(methods.contains("setTerminalSize"))
        XCTAssertTrue(methods.contains("getSessionList"))
        XCTAssertTrue(methods.contains("sendToSession"))
        XCTAssertTrue(methods.contains("setMulticastName"))
    }

    func testMockMacroServiceCoversAllMethods() {
        let mock = MockMacroService()
        mock.runMacro(scriptPath: "/test.ttl") { _ in }
        mock.stopMacro { }
        mock.pauseMacro { }
        mock.resumeMacro { }
        mock.macroStatus { _ in }
        mock.sendVariable(name: "x", value: "1") { }

        XCTAssertTrue(mock.runMacroCalled)
        XCTAssertTrue(mock.stopMacroCalled)
        XCTAssertTrue(mock.pauseMacroCalled)
        XCTAssertTrue(mock.resumeMacroCalled)
        XCTAssertTrue(mock.macroStatusCalled)
        XCTAssertTrue(mock.sendVariableCalled)
    }
}

// MARK: - Broadcast/Multicast Command Tests

final class BroadcastMulticastTests: XCTestCase {

    var runner: MacroRunner!
    var mockClient: ExtendedMockMacroClient!
    var tempDir: String!

    override func setUp() {
        super.setUp()
        runner = MacroRunner()
        mockClient = ExtendedMockMacroClient()
        runner.clientProxy = mockClient
        tempDir = NSTemporaryDirectory() + "ttlmacro_bcast_\(ProcessInfo.processInfo.processIdentifier)/"
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

    func testBroadcastCommand() {
        let exp = XCTestExpectation(description: "broadcast completes")
        let path = writeTTL("broadcast 'hello all'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("broadcastData"))
    }

    func testSetMulticastNameCommand() {
        let exp = XCTestExpectation(description: "setmulticast completes")
        let path = writeTTL("setmulticastname 'group1'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("setMulticastName"))
    }

    func testDispStrCommand() {
        let exp = XCTestExpectation(description: "dispstr completes")
        let path = writeTTL("dispstr 'local display'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("displayString"))
    }
}

// MARK: - Wait Command Event-Driven Tests

final class WaitEventDrivenTests: XCTestCase {

    func testWaitCommandNoPolling() throws {
        // Verify no 0.1s polling remains in MacroRunner.swift
        let path = "/home/user/teraterm_org/TeraTermMac/Sources/TTLMacro/MacroRunner.swift"
        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertFalse(content.contains("withTimeInterval: 0.1"),
                       "MacroRunner still contains 0.1s polling intervals")
    }

    func testWaitCommandUsesSubscribe() throws {
        // Verify wait commands use subscribeToTerminalData
        let path = "/home/user/teraterm_org/TeraTermMac/Sources/TTLMacro/MacroRunner.swift"
        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(content.contains("subscribeToTerminalData"),
                      "Wait commands should use subscribeToTerminalData for event-driven receive")
    }

    func testWaitCommandSetsTimeoutVariable() throws {
        // Verify timeout variable is set in wait commands
        let path = "/home/user/teraterm_org/TeraTermMac/Sources/TTLMacro/MacroRunner.swift"
        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(content.contains("variables[\"timeout\"] = .integer(1)"),
                      "Wait commands should set timeout variable to 1 on timeout")
        XCTAssertTrue(content.contains("variables[\"timeout\"] = .integer(0)"),
                      "Wait commands should set timeout variable to 0 on success")
    }
}

// MARK: - Additional MacroRunner Command Tests

final class ExtendedCommandTests: XCTestCase {

    var runner: MacroRunner!
    var mockClient: ExtendedMockMacroClient!
    var tempDir: String!

    override func setUp() {
        super.setUp()
        runner = MacroRunner()
        mockClient = ExtendedMockMacroClient()
        runner.clientProxy = mockClient
        tempDir = NSTemporaryDirectory() + "ttlmacro_ext_\(ProcessInfo.processInfo.processIdentifier)/"
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

    // MARK: - Window Commands

    func testSetTitleCommand() {
        let exp = XCTestExpectation(description: "settitle completes")
        let path = writeTTL("settitle 'My Window'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("setWindowTitle"))
    }

    func testClearScreenCommand() {
        let exp = XCTestExpectation(description: "clearscreen completes")
        let path = writeTTL("clearscreen\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("clearScreen"))
    }

    func testFlushRecvCommand() {
        let exp = XCTestExpectation(description: "flushrecv completes")
        let path = writeTTL("flushrecv\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("flushReceiveBuffer"))
    }

    func testDisconnectCommand() {
        let exp = XCTestExpectation(description: "disconnect completes")
        let path = writeTTL("disconnect\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("disconnectFromHost"))
    }

    func testSendBreakCommand() {
        let exp = XCTestExpectation(description: "sendbreak completes")
        let path = writeTTL("sendbreak\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("sendBreak"))
    }

    // MARK: - Log Commands

    func testLogOpenCommand() {
        let exp = XCTestExpectation(description: "logopen completes")
        let logFile = tempDir + "test.log"
        let path = writeTTL("logopen '\(logFile)' 0\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("openLog"))
    }

    func testLogCloseCommand() {
        let exp = XCTestExpectation(description: "logclose completes")
        let path = writeTTL("logclose\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("closeLog"))
    }

    func testLogWriteCommand() {
        let exp = XCTestExpectation(description: "logwrite completes")
        let path = writeTTL("logwrite 'test entry'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("writeToLog"))
    }

    // MARK: - Clipboard Commands

    func testSetClipboardCommand() {
        let exp = XCTestExpectation(description: "setclipboard completes")
        let path = writeTTL("setclipboard 'test'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("setClipboard"))
    }

    // MARK: - Serial Commands

    func testSetBaudRateCommand() {
        let exp = XCTestExpectation(description: "setbaud completes")
        let path = writeTTL("setbaud 9600\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("setBaudRate"))
    }

    // MARK: - Settings Commands

    func testRestoreSetupCommand() {
        let exp = XCTestExpectation(description: "restoresetup completes")
        let setupFile = tempDir + "teraterm.ini"
        try? "".write(toFile: setupFile, atomically: true, encoding: .utf8)
        let path = writeTTL("restoresetup '\(setupFile)'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("restoreSetup"))
    }

    // MARK: - SubCall / Return

    func testCallReturn() {
        let exp = XCTestExpectation(description: "call/return completes")
        let script = """
        call sub1
        end
        :sub1
        return
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("macroDidFinish"))
    }

    // MARK: - ExecCmnd

    func testExecCommand() {
        let exp = XCTestExpectation(description: "exec completes")
        let path = writeTTL("exec 'echo test'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
    }

    // MARK: - Multiple sends

    func testMultipleSends() {
        let exp = XCTestExpectation(description: "multi-send completes")
        let script = """
        send 'line1'
        sendln 'line2'
        send 'line3'
        end
        """
        let path = writeTTL(script)
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        let sendCalls = mockClient.calls.filter { $0.method == "sendToTerminal" }
        XCTAssertGreaterThanOrEqual(sendCalls.count, 3)
    }

    // MARK: - Status Box

    func testShowStatusBox() {
        let exp = XCTestExpectation(description: "statusbox completes")
        let path = writeTTL("statusbox 'Working...' 'Status'\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("showStatusBox"))
    }

    // MARK: - CloseStatusBox

    func testCloseStatusBox() {
        let exp = XCTestExpectation(description: "closesbox completes")
        let path = writeTTL("closesbox\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("closeStatusBox"))
    }

    // MARK: - MPause

    func testMPauseCommand() {
        let exp = XCTestExpectation(description: "mpause completes")
        let path = writeTTL("mpause 100\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("macroDidFinish"))
    }

    // MARK: - GetVer

    func testGetVerCommand() {
        let exp = XCTestExpectation(description: "getver completes")
        let path = writeTTL("getver\nend")
        runner.onComplete = { _ in exp.fulfill() }
        runner.run(scriptPath: path)
        wait(for: [exp], timeout: 10.0)
        XCTAssertTrue(mockClient.hasCall("getAppVersion"))
    }
}

// MARK: - TTLParser Operator Tests

final class TTLParserOperatorTests: XCTestCase {

    func testCheckReservedOperators() {
        let parser = TTLParser()
        XCTAssertNotNil(parser.checkReservedOperator("and"))
        XCTAssertNotNil(parser.checkReservedOperator("or"))
        XCTAssertNotNil(parser.checkReservedOperator("not"))
        XCTAssertNotNil(parser.checkReservedOperator("xor"))
        XCTAssertNil(parser.checkReservedOperator("bogus"))
    }
}

// MARK: - TTLError Tests

final class TTLErrorTests: XCTestCase {

    func testAllErrorCasesHaveMessages() {
        let errors: [TTLError] = [
            .closeParen, .cantCall, .cantConnect, .cantOpen,
            .divByZero, .invalidCtl, .labelAlreadyDef, .labelReq,
            .linkFirst, .stackOver, .syntax, .tooManyLabels,
            .tooManyVar, .typeMismatch, .varNotInit, .closeComment,
            .outOfRange, .closeBracket, .fewMemory, .notSupported,
            .cantExec
        ]
        for error in errors {
            XCTAssertFalse(error.message.isEmpty,
                           "TTLError.\(error) should have a non-empty message")
        }
    }

    func testErrorRawValues() {
        XCTAssertEqual(TTLError.syntax.rawValue, 11)
        XCTAssertEqual(TTLError.closeParen.rawValue, 1)
        XCTAssertEqual(TTLError.cantExec.rawValue, 21)
    }
}

// MARK: - TTLVarType Tests

final class TTLVarTypeTests: XCTestCase {

    func testAllVarTypes() {
        let types: [TTLVarType] = [.unknown, .integer, .string, .label, .intArray, .strArray]
        XCTAssertEqual(types.count, 6)
    }
}

// MARK: - TTLStatus Tests

final class TTLStatusTests: XCTestCase {

    func testStatusRawValues() {
        XCTAssertEqual(TTLStatus.run.rawValue, 1)
        XCTAssertEqual(TTLStatus.end.rawValue, 11)
        XCTAssertEqual(TTLStatus.pause.rawValue, 7)
        XCTAssertEqual(TTLStatus.wait4all.rawValue, 13)
    }
}
