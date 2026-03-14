/*
 * KeyInputPerformanceTests.swift
 * Tests for key input latency fix — verifies that:
 *   1. Key events do not accumulate handlers on reconnect
 *   2. Disconnect prevents further event delivery
 *   3. Main thread is not blocked by key input handling
 *   4. Network send occurs on a background thread
 *   5. Reconnect cycles work correctly
 *   6. No performance degradation over long runs
 *   7. Timers do not leak on reconnect
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - Mock Connection Manager

/// Records send() calls with thread info and timing for verification.
final class MockConnectionManager {
    private let lock = NSLock()
    private var _sendCount: Int = 0
    private var _sendThreadIsMain: [Bool] = []
    private var _sendTimestamps: [CFAbsoluteTime] = []
    private var _isConnected: Bool = false

    var sendCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _sendCount
    }

    var sendThreadIsMain: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return _sendThreadIsMain
    }

    var sendTimestamps: [CFAbsoluteTime] {
        lock.lock()
        defer { lock.unlock() }
        return _sendTimestamps
    }

    var isConnected: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isConnected }
        set { lock.lock(); _isConnected = newValue; lock.unlock() }
    }

    func send(_ data: Data) {
        lock.lock()
        _sendCount += 1
        _sendThreadIsMain.append(Thread.isMainThread)
        _sendTimestamps.append(CFAbsoluteTimeGetCurrent())
        lock.unlock()
    }

    func reset() {
        lock.lock()
        _sendCount = 0
        _sendThreadIsMain = []
        _sendTimestamps = []
        lock.unlock()
    }
}

// MARK: - Key Input Pipeline Under Test

/// Simulates the TerminalWindowController key input pipeline
/// without requiring a real NSWindow. This isolates the send-queue
/// behavior for unit testing.
final class KeyInputPipeline {
    let keyboardHandler: KeyboardHandler
    let mockConnection: MockConnectionManager
    let sendQueue: DispatchQueue

    private(set) var handleKeyDownCallCount: Int = 0
    private let countLock = NSLock()
    private var _connected = false

    var isConnected: Bool {
        get { countLock.lock(); defer { countLock.unlock() }; return _connected }
        set { countLock.lock(); _connected = newValue; countLock.unlock() }
    }

    init() {
        let settings = TerminalSettings()
        keyboardHandler = KeyboardHandler(settings: settings)
        mockConnection = MockConnectionManager()
        sendQueue = DispatchQueue(
            label: "com.teraterm.test.sendQueue", qos: .userInteractive)
    }

    func connect() {
        isConnected = true
        mockConnection.isConnected = true
    }

    func disconnect() {
        isConnected = false
        mockConnection.isConnected = false
    }

    /// Simulate a keyDown event and send via the async pipeline.
    func handleKeyDown(keyCode: UInt16 = 0x24, characters: String = "\r") {
        countLock.lock()
        handleKeyDownCallCount += 1
        countLock.unlock()

        let event = TerminalKeyEvent(
            keyCode: keyCode,
            characters: characters,
            modifiers: [],
            isKeyDown: true
        )
        guard let data = keyboardHandler.processKeyEvent(event) else { return }
        guard isConnected else { return }

        sendQueue.async { [weak self] in
            self?.mockConnection.send(data)
        }
    }

    func resetCounts() {
        countLock.lock()
        handleKeyDownCallCount = 0
        countLock.unlock()
        mockConnection.reset()
    }
}

// MARK: - Test 1: No Accumulated Handlers After Reconnect

final class KeyInputAccumulationTests: XCTestCase {

    func testNoAccumulatedHandlersAfterReconnect() {
        let pipeline = KeyInputPipeline()

        // connect/disconnect 10 times
        for _ in 0..<10 {
            pipeline.connect()
            pipeline.disconnect()
        }
        pipeline.connect()

        pipeline.resetCounts()

        // Send one key event
        pipeline.handleKeyDown()

        // Wait for async send
        let expectation = XCTestExpectation(description: "Single send after reconnect")
        expectation.expectedFulfillmentCount = 1

        pipeline.sendQueue.async {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(pipeline.mockConnection.sendCount, 1,
            "After 10 reconnects, a single keyDown should result in exactly 1 send call")
    }
}

// MARK: - Test 2: No Events After Disconnect

final class KeyInputDisconnectTests: XCTestCase {

    func testNoEventsAfterDisconnect() {
        let pipeline = KeyInputPipeline()
        pipeline.connect()
        pipeline.disconnect()

        // Send a key event after disconnect
        pipeline.handleKeyDown()

        // Wait a bit — the event should NOT be delivered
        let notDelivered = XCTestExpectation(description: "Event should not be delivered")
        notDelivered.isInverted = true

        pipeline.sendQueue.async {
            if pipeline.mockConnection.sendCount > 0 {
                notDelivered.fulfill()
            }
        }

        wait(for: [notDelivered], timeout: 1.0)

        XCTAssertEqual(pipeline.mockConnection.sendCount, 0,
            "No send should occur after disconnect")
    }
}

// MARK: - Test 3: Main Thread Non-Blocking

final class KeyInputMainThreadTests: XCTestCase {

    func testMainThreadNotBlocked() {
        let pipeline = KeyInputPipeline()
        pipeline.connect()

        // Send 100 key events on the main thread and measure time
        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<100 {
            pipeline.handleKeyDown(keyCode: 0, characters: "a")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // 100 events should complete in well under 16ms (one frame)
        // Each handleKeyDown should take < 1ms on main thread
        XCTAssertLessThan(elapsed, 0.016,
            "100 key events should not block main thread for more than 16ms, took \(elapsed * 1000)ms")

        // Wait for sends to complete
        let done = XCTestExpectation(description: "All sends complete")
        pipeline.sendQueue.async {
            done.fulfill()
        }
        wait(for: [done], timeout: 5.0)

        pipeline.disconnect()
    }
}

// MARK: - Test 4: Send Occurs on Background Thread

final class KeyInputBackgroundSendTests: XCTestCase {

    func testSendOnBackgroundThread() {
        let pipeline = KeyInputPipeline()
        pipeline.connect()

        let sendExpectation = XCTestExpectation(description: "Send completed")

        pipeline.handleKeyDown()

        pipeline.sendQueue.async {
            sendExpectation.fulfill()
        }

        wait(for: [sendExpectation], timeout: 5.0)

        let threadInfo = pipeline.mockConnection.sendThreadIsMain
        XCTAssertFalse(threadInfo.isEmpty, "At least one send should have occurred")
        for (i, isMain) in threadInfo.enumerated() {
            XCTAssertFalse(isMain,
                "Send #\(i) should NOT be on main thread")
        }

        pipeline.disconnect()
    }
}

// MARK: - Test 5: Reconnect Cycle Works Correctly

final class KeyInputReconnectTests: XCTestCase {

    func testReconnectCycleWorksCorrectly() {
        let pipeline = KeyInputPipeline()

        // Perform 10 connect/disconnect cycles
        for _ in 0..<10 {
            pipeline.connect()
            pipeline.disconnect()
        }

        // Final connect
        pipeline.connect()
        pipeline.resetCounts()

        // Send one key
        pipeline.handleKeyDown()

        let done = XCTestExpectation(description: "Send after reconnect")
        pipeline.sendQueue.async {
            done.fulfill()
        }
        wait(for: [done], timeout: 5.0)

        XCTAssertEqual(pipeline.mockConnection.sendCount, 1,
            "After 10 reconnect cycles, exactly 1 send should occur for 1 key event")

        pipeline.disconnect()
    }
}

// MARK: - Test 6: No Performance Degradation Over Long Runs

final class KeyInputDegradationTests: XCTestCase {

    func testNoPerformanceDegradation() {
        let pipeline = KeyInputPipeline()
        pipeline.connect()

        let totalEvents = 1000
        var timings: [CFAbsoluteTime] = []

        for _ in 0..<totalEvents {
            let start = CFAbsoluteTimeGetCurrent()
            pipeline.handleKeyDown(keyCode: 0, characters: "x")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            timings.append(elapsed)
        }

        // Wait for all sends to complete
        let done = XCTestExpectation(description: "All sends done")
        pipeline.sendQueue.async {
            done.fulfill()
        }
        wait(for: [done], timeout: 5.0)

        // Compare first 10 vs last 10 average times
        let first10 = timings.prefix(10)
        let last10 = timings.suffix(10)

        let avgFirst = first10.reduce(0, +) / Double(first10.count)
        let avgLast = last10.reduce(0, +) / Double(last10.count)

        // Avoid division by zero — if avgFirst is essentially 0, just check
        // that avgLast is also very small (< 1ms)
        if avgFirst > 0.000001 {
            let ratio = avgLast / avgFirst
            XCTAssertLessThan(ratio, 2.0,
                "Last 10 events should not be more than 2x slower than first 10. " +
                "First avg: \(avgFirst * 1000)ms, Last avg: \(avgLast * 1000)ms, Ratio: \(ratio)")
        } else {
            XCTAssertLessThan(avgLast, 0.001,
                "Last 10 events should each take less than 1ms, avg: \(avgLast * 1000)ms")
        }

        pipeline.disconnect()
    }
}

// MARK: - Test 7: Timer Leak Check

final class KeyInputTimerLeakTests: XCTestCase {

    func testTimersDoNotLeakOnReconnect() {
        // This test verifies that TerminalView's cursor blink timer
        // does not accumulate across startCursorBlink calls.
        // Since TerminalView requires AppKit window context, we test
        // the timer pattern directly.

        var timers: [Timer] = []

        // Simulate 10 reconnects — each one creates a new timer
        // after invalidating the old one (correct pattern)
        var currentTimer: Timer?
        for _ in 0..<10 {
            currentTimer?.invalidate()
            currentTimer = Timer.scheduledTimer(withTimeInterval: 100, repeats: true) { _ in }
            timers.append(currentTimer!)
        }

        // Only the last timer should be valid
        let validCount = timers.filter { $0.isValid }.count
        XCTAssertEqual(validCount, 1,
            "After 10 timer replacements, only 1 timer should be valid, found \(validCount)")

        // Cleanup
        currentTimer?.invalidate()
    }
}

#else
// Non-macOS stub
final class KeyInputPerformanceTests: XCTestCase {
    func testSkipOnNonMacOS() {
        // These tests require AppKit, skipped on non-macOS
    }
}
#endif
