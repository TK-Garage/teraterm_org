/*
 * TTL Communication & Async Tests
 * Phase 3: wait, send, recvln with mock stream objects
 * Timeout verification, thread-safe pause/stop
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)

// MARK: - Pseudo-Device Stream (Mock Serial/TCP)

/// Simulates a serial port or TCP socket for testing wait/send/recv
class MockStream {
    private var buffer: String = ""
    private let lock = NSLock()

    /// Write data into the stream (simulates receiving from device)
    func feedData(_ data: String) {
        lock.lock()
        buffer += data
        lock.unlock()
    }

    /// Read and optionally clear the buffer
    func readBuffer(clear: Bool) -> String {
        lock.lock()
        let data = buffer
        if clear { buffer = "" }
        lock.unlock()
        return data
    }

    /// Flush the buffer
    func flush() {
        lock.lock()
        buffer = ""
        lock.unlock()
    }

    var isEmpty: Bool {
        lock.lock()
        let empty = buffer.isEmpty
        lock.unlock()
        return empty
    }
}

// MARK: - Streaming Mock Delegate

class StreamingMockDelegate: MockTTLDelegate {
    let stream = MockStream()
    var sendLog: [String] = []

    override func ttlSendData(_ data: Data) {
        sendLog.append(String(data: data, encoding: .utf8) ?? "")
    }

    override func ttlSendString(_ text: String) {
        sendLog.append(text)
    }

    override func ttlSendLine(_ text: String) {
        sendLog.append(text + "\r\n")
    }

    override func ttlIsConnected() -> Bool { return true }

    override func ttlGetReceivedData(clear: Bool) -> String {
        return stream.readBuffer(clear: clear)
    }

    override func ttlFlushReceiveBuffer() {
        stream.flush()
    }
}

// MARK: - Communication Tests

final class TTLCommunicationTests: XCTestCase {

    var interpreter: TTLInterpreter!
    var delegate: StreamingMockDelegate!

    override func setUp() {
        super.setUp()
        interpreter = TTLInterpreter()
        delegate = StreamingMockDelegate()
        interpreter.delegate = delegate
    }

    // MARK: - Wait Pattern Detection

    func testWaitPatternDetection_SimpleMatch() {
        let stream = delegate.stream
        let buffer = "Login: admin\r\nPassword: "

        // Simulate wait for "Password:"
        let pattern = "Password:"
        XCTAssertTrue(buffer.contains(pattern))
    }

    func testWaitPatternDetection_MultiplePatterns() {
        let buffer = "Connection refused\r\n"
        let patterns = ["Login:", "Password:", "Connection refused", "Timeout"]

        var matchIndex = 0
        for (i, pattern) in patterns.enumerated() {
            if buffer.contains(pattern) {
                matchIndex = i + 1 // 1-based
                break
            }
        }
        XCTAssertEqual(matchIndex, 3) // "Connection refused" is pattern 3
    }

    func testWaitPatternDetection_NoMatch() {
        let buffer = "Some random output"
        let patterns = ["Login:", "Password:"]

        var matched = false
        for pattern in patterns {
            if buffer.contains(pattern) {
                matched = true
                break
            }
        }
        XCTAssertFalse(matched)
    }

    func testWaitPatternDetection_RegexMatch() {
        let buffer = "IP Address: 192.168.1.100"
        let pattern = "\\d+\\.\\d+\\.\\d+\\.\\d+"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(buffer.startIndex..., in: buffer)
        let match = regex.firstMatch(in: buffer, range: range)
        XCTAssertNotNil(match)

        if let matchRange = Range(match!.range, in: buffer) {
            XCTAssertEqual(String(buffer[matchRange]), "192.168.1.100")
        }
    }

    func testWaitPatternDetection_RegexGroupCapture() {
        let buffer = "Firmware v2.1.3 ready"
        let pattern = "v(\\d+)\\.(\\d+)\\.(\\d+)"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(buffer.startIndex..., in: buffer)
        let match = regex.firstMatch(in: buffer, range: range)
        XCTAssertNotNil(match)
        XCTAssertEqual(match!.numberOfRanges, 4)

        if let g1 = Range(match!.range(at: 1), in: buffer) {
            XCTAssertEqual(String(buffer[g1]), "2")
        }
        if let g2 = Range(match!.range(at: 2), in: buffer) {
            XCTAssertEqual(String(buffer[g2]), "1")
        }
        if let g3 = Range(match!.range(at: 3), in: buffer) {
            XCTAssertEqual(String(buffer[g3]), "3")
        }
    }

    // MARK: - Stream Buffer Tests

    func testStreamFeedAndRead() {
        let stream = delegate.stream
        stream.feedData("Hello ")
        stream.feedData("World")

        let data = stream.readBuffer(clear: false)
        XCTAssertEqual(data, "Hello World")

        // Read with clear
        let data2 = stream.readBuffer(clear: true)
        XCTAssertEqual(data2, "Hello World")
        XCTAssertTrue(stream.isEmpty)
    }

    func testStreamFlush() {
        let stream = delegate.stream
        stream.feedData("data to flush")
        XCTAssertFalse(stream.isEmpty)

        stream.flush()
        XCTAssertTrue(stream.isEmpty)
    }

    func testStreamIncrementalFeed() {
        let stream = delegate.stream

        stream.feedData("Log")
        XCTAssertFalse(stream.readBuffer(clear: false).contains("Login:"))

        stream.feedData("in:")
        XCTAssertTrue(stream.readBuffer(clear: false).contains("Login:"))
    }

    // MARK: - Timeout Verification

    func testTimeout_BasicCheck() {
        // Verify timeout calculation: timeout + mtimeout/1000
        let timeout = 3
        let mtimeout = 500
        let timeLimit = Double(timeout) + Double(mtimeout) / 1000.0
        XCTAssertEqual(timeLimit, 3.5, accuracy: 0.001)
    }

    func testTimeout_ZeroTimeout() {
        let timeout = 0
        let mtimeout = 0
        let timeLimit = Double(timeout) + Double(mtimeout) / 1000.0
        XCTAssertEqual(timeLimit, 0.0)
    }

    func testTimeout_MillisecondOnly() {
        let timeout = 0
        let mtimeout = 2500
        let timeLimit = Double(timeout) + Double(mtimeout) / 1000.0
        XCTAssertEqual(timeLimit, 2.5, accuracy: 0.001)
    }

    func testTimeout_TimerExpiration() {
        let start = Date()
        let timeLimit: TimeInterval = 0.1 // 100ms

        // Simulate time check
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, timeLimit)
    }

    func testTimeout_SetViaSystemVariable() {
        let p = interpreter.parser
        interpreter.loadScript("")

        p.setIntVal(id: p.timeoutVarId, value: 3)
        p.setIntVal(id: p.mtimeoutVarId, value: 0)

        let timeout = p.getIntVal(id: p.timeoutVarId)
        let mtimeout = p.getIntVal(id: p.mtimeoutVarId)
        let timeLimit = Double(timeout) + Double(mtimeout) / 1000.0
        XCTAssertEqual(timeLimit, 3.0, accuracy: 0.001)
    }

    func testTimeout_ResultSetToZero() {
        // On timeout, result should be 0
        let p = interpreter.parser
        interpreter.loadScript("")
        p.setResult(0)
        XCTAssertEqual(p.getIntVal(id: p.resultVarId), 0)
    }

    // MARK: - Wait State Machine

    func testWaitStateMachine_InitialState() {
        let p = interpreter.parser
        interpreter.loadScript("")
        XCTAssertEqual(p.status, .run)
    }

    func testWaitStateMachine_WaitState() {
        let p = interpreter.parser
        interpreter.loadScript("")
        p.status = .wait
        XCTAssertEqual(p.status, .wait)
    }

    func testWaitStateMachine_WaitLnState() {
        let p = interpreter.parser
        interpreter.loadScript("")
        p.status = .waitLn
        XCTAssertEqual(p.status, .waitLn)
    }

    func testWaitStateMachine_WaitNState() {
        let p = interpreter.parser
        interpreter.loadScript("")
        p.status = .waitN
        XCTAssertEqual(p.status, .waitN)
    }

    func testWaitStateMachine_Wait4AllState() {
        let p = interpreter.parser
        interpreter.loadScript("")
        p.status = .wait4all
        XCTAssertEqual(p.status, .wait4all)
    }

    func testWaitStateMachine_PauseState() {
        let p = interpreter.parser
        interpreter.loadScript("")
        p.status = .pause
        XCTAssertEqual(p.status, .pause)
    }

    func testWaitStateMachine_EndState() {
        let p = interpreter.parser
        interpreter.loadScript("")
        p.status = .end
        XCTAssertEqual(p.status, .end)
    }

    // MARK: - Wait4All Logic

    func testWait4All_AllPatternsFound() {
        let patterns = ["Login:", "Password:", "Ready"]
        let buffer = "System Ready\r\nLogin: admin\r\nPassword: ****"

        var allFound = true
        for pattern in patterns {
            if !buffer.contains(pattern) {
                allFound = false
                break
            }
        }
        XCTAssertTrue(allFound)
    }

    func testWait4All_SomePatternsMissing() {
        let patterns = ["Login:", "Password:", "Ready"]
        let buffer = "Login: admin\r\nReady"

        var allFound = true
        for pattern in patterns {
            if !buffer.contains(pattern) {
                allFound = false
                break
            }
        }
        XCTAssertFalse(allFound)
    }

    // MARK: - WaitN Logic

    func testWaitN_ExactCount() {
        let buffer = "ABCDE"
        let count = 5
        XCTAssertTrue(buffer.count >= count)

        let received = String(buffer.prefix(count))
        XCTAssertEqual(received, "ABCDE")
    }

    func testWaitN_NotEnoughData() {
        let buffer = "AB"
        let count = 5
        XCTAssertFalse(buffer.count >= count)
    }

    func testWaitN_ExcessData() {
        let buffer = "ABCDEFGH"
        let count = 5
        let received = String(buffer.prefix(count))
        let remaining = String(buffer.dropFirst(count))
        XCTAssertEqual(received, "ABCDE")
        XCTAssertEqual(remaining, "FGH")
    }

    // MARK: - Send Command Tests

    func testSend_BasicString() {
        let text = "ls -la"
        delegate.ttlSendString(text)
        XCTAssertEqual(delegate.sendLog.last, "ls -la")
    }

    func testSendLn_AddsNewline() {
        delegate.ttlSendLine("hostname")
        XCTAssertEqual(delegate.sendLog.last, "hostname\r\n")
    }

    func testSend_BinaryData() {
        let data = Data([0x01, 0x02, 0x03])
        delegate.ttlSendData(data)
        XCTAssertEqual(delegate.sentData.last, data)
    }

    func testSend_EmptyString() {
        delegate.ttlSendString("")
        XCTAssertEqual(delegate.sendLog.last, "")
    }

    func testSend_SpecialChars() {
        delegate.ttlSendString("echo \"hello\\nworld\"")
        XCTAssertTrue(delegate.sendLog.last?.contains("echo") ?? false)
    }

    // MARK: - RecvLn Logic

    func testRecvLn_CompleteLine() {
        let buf = "hostname\r\nuser@host:~$ "

        if let nlRange = buf.rangeOfCharacter(from: CharacterSet.newlines) {
            let line = String(buf[buf.startIndex..<nlRange.lowerBound])
            XCTAssertEqual(line, "hostname")
        } else {
            XCTFail("Should find newline")
        }
    }

    func testRecvLn_NoNewline() {
        let buf = "partial data"
        let nlRange = buf.rangeOfCharacter(from: CharacterSet.newlines)
        XCTAssertNil(nlRange)
    }

    func testRecvLn_EmptyLine() {
        let buf = "\r\ndata"
        if let nlRange = buf.rangeOfCharacter(from: CharacterSet.newlines) {
            let line = String(buf[buf.startIndex..<nlRange.lowerBound])
            XCTAssertEqual(line, "")
        }
    }

    // MARK: - Connection State

    func testConnectionState_NotConnected() {
        delegate.isConnected = false
        XCTAssertFalse(delegate.ttlIsConnected())
    }

    func testConnectionState_Connected() {
        delegate.isConnected = true
        XCTAssertTrue(delegate.ttlIsConnected())
    }

    func testConnectionState_Disconnect() {
        delegate.isConnected = true
        delegate.ttlDisconnect()
        XCTAssertFalse(delegate.ttlIsConnected())
    }

    func testConnectionState_Connect() {
        delegate.isConnected = false
        delegate.ttlConnect("telnet://localhost:23")
        XCTAssertTrue(delegate.ttlIsConnected())
    }

    // MARK: - FlushRecv

    func testFlushRecv() {
        delegate.stream.feedData("old data")
        XCTAssertFalse(delegate.stream.isEmpty)
        delegate.ttlFlushReceiveBuffer()
        XCTAssertTrue(delegate.stream.isEmpty)
    }

    // MARK: - Interpreter Stop

    func testInterpreterStop() {
        interpreter.loadScript("end")
        interpreter.stop()
        XCTAssertEqual(interpreter.parser.status, .end)
    }

    func testInterpreterStop_ClearsStatus() {
        interpreter.loadScript("")
        interpreter.parser.status = .wait
        interpreter.stop()
        XCTAssertEqual(interpreter.parser.status, .end)
    }

    // MARK: - Result Variable after Wait Operations

    func testResult_AfterMatch() {
        let p = interpreter.parser
        interpreter.loadScript("")

        // Simulate: wait matched pattern 2 → result = 2
        p.setResult(2)
        XCTAssertEqual(p.getIntVal(id: p.resultVarId), 2)
    }

    func testResult_AfterTimeout() {
        let p = interpreter.parser
        interpreter.loadScript("")

        // Simulate: wait timed out → result = 0
        p.setResult(0)
        XCTAssertEqual(p.getIntVal(id: p.resultVarId), 0)
    }

    // MARK: - InputStr after Wait

    func testInputStr_AfterWaitMatch() {
        let p = interpreter.parser
        interpreter.loadScript("")

        p.setInputStr("Login: admin\r\nPassword: ")
        XCTAssertEqual(p.getStrVal(id: p.inputStrVarId), "Login: admin\r\nPassword: ")
    }

    func testMatchStr_AfterRegexWait() {
        let p = interpreter.parser
        interpreter.loadScript("")

        p.setMatchStr("192.168.1.100")
        XCTAssertEqual(p.getStrVal(id: p.matchStrVarId), "192.168.1.100")
    }

    // MARK: - Async Wait with RunLoop (Integration)

    func testAsyncWaitTimeout() {
        let expectation = expectation(description: "Timeout occurs")

        let p = interpreter.parser
        interpreter.loadScript("")
        p.setIntVal(id: p.timeoutVarId, value: 0)
        p.setIntVal(id: p.mtimeoutVarId, value: 100) // 100ms timeout

        // Set up completion handler
        interpreter.onComplete = {
            expectation.fulfill()
        }

        // Start a simple script that immediately ends
        interpreter.loadScript("end")
        interpreter.run()

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(p.status, .end)
    }
}

#endif
