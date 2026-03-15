/*
 * SSHMockConnection.swift
 * Phase 2 & 3: Mock SSH connection for integration testing.
 *
 * Provides MockSSHConnection (conforming to the Connection protocol)
 * that simulates SSH authentication and session lifecycle WITHOUT
 * requiring a real SSH server or libssh2.
 *
 * NOTE – Security-Scoped Bookmarks:
 *   In a sandboxed app, if the user selects a private key via
 *   NSOpenPanel, the system grants a temporary security scope.
 *   To persist access across app launches, create a Security-Scoped
 *   Bookmark with:
 *     let bookmark = try url.bookmarkData(
 *         options: .withSecurityScope,
 *         includingResourceValuesForKeys: nil,
 *         relativeTo: nil)
 *   Then resolve it on next launch with:
 *     var isStale = false
 *     let url = try URL(resolvingBookmarkData: bookmark,
 *         options: .withSecurityScope,
 *         relativeTo: nil,
 *         bookmarkDataIsStale: &isStale)
 *     guard url.startAccessingSecurityScopedResource() else { ... }
 *   The mock below does NOT use bookmarks since temp files are used.
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)

// MARK: - SSH Authentication Result

enum SSHAuthResult {
    case success
    case invalidCredentials
    case keyMismatch
    case unsupportedAlgorithm(String)
    case timeout
    case serverRefused(String)
}

// MARK: - Mock SSH Connection

/// Simulates an SSH connection lifecycle for testing purposes.
/// Conforms to the `Connection` protocol so it can be plugged into
/// `ConnectionManager` in place of a real TCP connection.
class MockSSHConnection: Connection {

    weak var delegate: ConnectionDelegate?
    private(set) var state: ConnectionState = .disconnected

    var isConnected: Bool { state == .connected }

    // Simulation configuration
    var simulatedAuthResult: SSHAuthResult = .success
    var simulatedBanner: String? = "SSH-2.0-OpenSSH_9.6\r\n"
    var simulatedShellPrompt: String = "$ "
    var simulatedLatency: TimeInterval = 0   // Set > 0 to test async

    // Authentication parameters captured during connect
    private(set) var lastUsername: String?
    private(set) var lastAuthMethod: SSHAuthMethod?
    private(set) var lastKeyFile: String?

    // Track calls for verification
    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var sentData: [Data] = []

    /// Configure and initiate the mock connection.
    func connectSSH(host: String, port: Int, username: String,
                    authMethod: SSHAuthMethod, passphrase: String,
                    keyFile: String?) {
        lastUsername = username
        lastAuthMethod = authMethod
        lastKeyFile = keyFile
        connect()
    }

    // MARK: - Connection Protocol

    func connect() {
        connectCallCount += 1
        setState(.connecting)

        let doAuth = { [weak self] in
            guard let self = self else { return }

            switch self.simulatedAuthResult {
            case .success:
                self.setState(.connected)
                self.delegate?.connectionDidConnect()
                // Send banner and shell prompt
                if let banner = self.simulatedBanner {
                    let bannerData = Data(banner.utf8)
                    self.delegate?.connectionDidReceiveData(bannerData)
                }
                let promptData = Data(self.simulatedShellPrompt.utf8)
                self.delegate?.connectionDidReceiveData(promptData)

            case .invalidCredentials:
                let err = ConnectionError.connectionFailed(
                    host: "mock", port: 22,
                    detail: "Authentication failed: invalid credentials")
                self.setState(.error("Authentication failed"))
                self.delegate?.connectionDidFail(error: err)

            case .keyMismatch:
                let err = ConnectionError.connectionFailed(
                    host: "mock", port: 22,
                    detail: "Public key authentication failed: key mismatch")
                self.setState(.error("Key mismatch"))
                self.delegate?.connectionDidFail(error: err)

            case .unsupportedAlgorithm(let algo):
                let err = ConnectionError.connectionFailed(
                    host: "mock", port: 22,
                    detail: "No matching host key algorithm: \(algo)")
                self.setState(.error("Unsupported algorithm"))
                self.delegate?.connectionDidFail(error: err)

            case .timeout:
                let err = ConnectionError.connectionTimeout(host: "mock", port: 22)
                self.setState(.error("Connection timeout"))
                self.delegate?.connectionDidFail(error: err)

            case .serverRefused(let reason):
                let err = ConnectionError.connectionRefused(host: "mock", port: 22)
                self.setState(.error("Refused: \(reason)"))
                self.delegate?.connectionDidFail(error: err)
            }
        }

        if simulatedLatency > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + simulatedLatency, execute: doAuth)
        } else {
            doAuth()
        }
    }

    func disconnect() {
        disconnectCallCount += 1
        setState(.disconnecting)
        setState(.disconnected)
        delegate?.connectionDidDisconnect()
    }

    func send(_ data: Data) {
        sentData.append(data)
        // Echo back if connected (simulate remote shell)
        if isConnected {
            delegate?.connectionDidReceiveData(data)
        }
    }

    func send(_ string: String) {
        send(Data(string.utf8))
    }

    private func setState(_ newState: ConnectionState) {
        state = newState
        delegate?.connectionStateChanged(newState)
    }
}

// MARK: - Mock Connection Delegate (captures events)

class MockConnectionDelegate: ConnectionDelegate {
    var didConnectCount = 0
    var didDisconnectCount = 0
    var receivedData: [Data] = []
    var errors: [Error] = []
    var stateHistory: [ConnectionState] = []

    func connectionDidConnect() {
        didConnectCount += 1
    }

    func connectionDidDisconnect() {
        didDisconnectCount += 1
    }

    func connectionDidReceiveData(_ data: Data) {
        receivedData.append(data)
    }

    func connectionDidFail(error: Error) {
        errors.append(error)
    }

    func connectionStateChanged(_ state: ConnectionState) {
        stateHistory.append(state)
    }

    /// Concatenated received text.
    var receivedText: String {
        receivedData.compactMap { String(data: $0, encoding: .utf8) }.joined()
    }
}

// MARK: - Phase 2: Mock SSH Connection Tests

final class SSHMockConnectionTests: XCTestCase {

    // MARK: - Successful Authentication

    func testSuccessfulEd25519Auth() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .success

        conn.connectSSH(
            host: "192.168.1.10", port: 22,
            username: "admin",
            authMethod: .publicKey,
            passphrase: "testpass",
            keyFile: "/Users/admin/.ssh/id_ed25519"
        )

        XCTAssertTrue(conn.isConnected)
        XCTAssertEqual(delegate.didConnectCount, 1)
        XCTAssertEqual(conn.lastUsername, "admin")
        XCTAssertEqual(conn.lastAuthMethod, .publicKey)

        // Should receive banner + prompt
        XCTAssertTrue(delegate.receivedText.contains("SSH-2.0-OpenSSH"))
        XCTAssertTrue(delegate.receivedText.contains("$ "))

        // State transitions: connecting → connected
        XCTAssertEqual(delegate.stateHistory, [.connecting, .connected])
    }

    func testSuccessfulPasswordAuth() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .success

        conn.connectSSH(
            host: "server.example.com", port: 22,
            username: "root",
            authMethod: .password,
            passphrase: "password123",
            keyFile: nil
        )

        XCTAssertTrue(conn.isConnected)
        XCTAssertEqual(conn.lastAuthMethod, .password)
    }

    // MARK: - Authentication Failures

    func testInvalidCredentials() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .invalidCredentials

        conn.connectSSH(
            host: "host", port: 22,
            username: "user",
            authMethod: .password,
            passphrase: "wrong",
            keyFile: nil
        )

        XCTAssertFalse(conn.isConnected)
        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertEqual(delegate.didConnectCount, 0)
    }

    func testKeyMismatch() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .keyMismatch

        conn.connectSSH(
            host: "host", port: 22,
            username: "user",
            authMethod: .publicKey,
            passphrase: "",
            keyFile: "/path/to/wrong_key"
        )

        XCTAssertFalse(conn.isConnected)
        XCTAssertEqual(delegate.errors.count, 1)
        // State should end in error
        if case .error(let msg) = conn.state {
            XCTAssertTrue(msg.contains("mismatch"))
        } else {
            XCTFail("Expected error state")
        }
    }

    func testUnsupportedAlgorithm() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .unsupportedAlgorithm("ssh-dss")

        conn.connectSSH(
            host: "host", port: 22,
            username: "user",
            authMethod: .publicKey,
            passphrase: "",
            keyFile: "/path/to/id_dsa"
        )

        XCTAssertFalse(conn.isConnected)
        XCTAssertEqual(delegate.errors.count, 1)
    }

    func testConnectionTimeout() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .timeout

        conn.connectSSH(
            host: "unreachable.example.com", port: 22,
            username: "user",
            authMethod: .password,
            passphrase: "pass",
            keyFile: nil
        )

        XCTAssertFalse(conn.isConnected)
        XCTAssertEqual(delegate.errors.count, 1)
    }

    func testServerRefused() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .serverRefused("Too many auth attempts")

        conn.connectSSH(
            host: "host", port: 22,
            username: "user",
            authMethod: .password,
            passphrase: "pass",
            keyFile: nil
        )

        XCTAssertFalse(conn.isConnected)
        XCTAssertEqual(delegate.errors.count, 1)
    }

    // MARK: - Disconnect & Cleanup

    func testDisconnectAfterConnect() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .success

        conn.connect()
        XCTAssertTrue(conn.isConnected)

        conn.disconnect()
        XCTAssertFalse(conn.isConnected)
        XCTAssertEqual(delegate.didDisconnectCount, 1)
        XCTAssertEqual(conn.state, .disconnected)
    }

    func testMultipleDisconnectsAreSafe() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .success

        conn.connect()
        conn.disconnect()
        conn.disconnect()  // Should not crash

        XCTAssertEqual(delegate.didDisconnectCount, 2)
    }

    // MARK: - Data Send/Receive

    func testSendDataWhenConnected() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .success

        conn.connect()
        conn.send("ls -la\n")

        // Mock echoes back sent data
        XCTAssertTrue(delegate.receivedText.contains("ls -la"))
        XCTAssertEqual(conn.sentData.count, 1)
    }

    // MARK: - State Transition Verification

    func testStateTransitionsOnSuccess() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .success

        conn.connect()

        XCTAssertEqual(delegate.stateHistory, [
            .connecting,
            .connected,
        ])
    }

    func testStateTransitionsOnFailure() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .invalidCredentials

        conn.connect()

        XCTAssertEqual(delegate.stateHistory.count, 2)
        XCTAssertEqual(delegate.stateHistory[0], .connecting)
        if case .error(_) = delegate.stateHistory[1] {
            // Expected
        } else {
            XCTFail("Expected error state")
        }
    }

    func testStateTransitionsOnDisconnect() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .success

        conn.connect()
        conn.disconnect()

        XCTAssertEqual(delegate.stateHistory, [
            .connecting,
            .connected,
            .disconnecting,
            .disconnected,
        ])
    }

    // MARK: - Reconnection

    func testReconnectAfterDisconnect() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .success

        conn.connect()
        XCTAssertTrue(conn.isConnected)
        conn.disconnect()
        XCTAssertFalse(conn.isConnected)

        // Reconnect
        conn.connect()
        XCTAssertTrue(conn.isConnected)
        XCTAssertEqual(conn.connectCallCount, 2)
    }

    func testReconnectAfterFailure() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate

        // First attempt fails
        conn.simulatedAuthResult = .invalidCredentials
        conn.connect()
        XCTAssertFalse(conn.isConnected)

        // Second attempt succeeds (e.g. user corrected credentials)
        conn.simulatedAuthResult = .success
        conn.connect()
        XCTAssertTrue(conn.isConnected)
        XCTAssertEqual(conn.connectCallCount, 2)
    }

    // MARK: - Async Latency Simulation

    func testAsyncConnectionWithLatency() {
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .success
        conn.simulatedLatency = 0.1

        let expectation = XCTestExpectation(description: "Connection completes")

        conn.connect()
        // Should be in connecting state immediately
        XCTAssertEqual(conn.state, .connecting)
        XCTAssertFalse(conn.isConnected)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertTrue(conn.isConnected)
            XCTAssertEqual(delegate.didConnectCount, 1)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }
}

// MARK: - Phase 3: UI State Reflection Tests

final class SSHUIStateTests: XCTestCase {

    /// Verify that ConnectionState can encode connection progress for UI display.
    func testConnectionStateDescriptions() {
        XCTAssertEqual(ConnectionState.disconnected, .disconnected)
        XCTAssertEqual(ConnectionState.connecting, .connecting)
        XCTAssertEqual(ConnectionState.connected, .connected)
        XCTAssertEqual(ConnectionState.disconnecting, .disconnecting)
        XCTAssertEqual(ConnectionState.error("test"), .error("test"))
        XCTAssertNotEqual(ConnectionState.error("a"), .error("b"))
    }

    /// Simulate that title bar should update based on connection state.
    func testTitleBarStateMapping() {
        // Map connection states to expected title bar text
        let titleForState: (ConnectionState) -> String = { state in
            switch state {
            case .disconnected:    return "Disconnected"
            case .connecting:      return "Connecting..."
            case .connected:       return "Connected"
            case .disconnecting:   return "Disconnecting..."
            case .error(let msg):  return "Error: \(msg)"
            }
        }

        XCTAssertEqual(titleForState(.connecting), "Connecting...")
        XCTAssertEqual(titleForState(.connected), "Connected")
        XCTAssertEqual(titleForState(.error("Auth failed")), "Error: Auth failed")
    }

    /// Verify that reconnection with saved settings restores connection parameters.
    func testReconnectWithSavedSettings() {
        // Simulate loading settings from INI
        let mgr = ConfigPersistenceManager()
        var config = TeraTermConfig()
        config.hostName = "ssh.example.com"
        config.tcpPort = 2222

        // Encode → decode round-trip
        let sections = mgr.encode(config)
        let loaded = mgr.decode(sections: sections)

        // Create mock connection with loaded settings
        let conn = MockSSHConnection()
        let delegate = MockConnectionDelegate()
        conn.delegate = delegate
        conn.simulatedAuthResult = .success

        conn.connectSSH(
            host: loaded.hostName,
            port: loaded.tcpPort,
            username: "user",
            authMethod: .publicKey,
            passphrase: "",
            keyFile: nil
        )

        XCTAssertTrue(conn.isConnected)
        XCTAssertEqual(conn.lastUsername, "user")
    }
}

#endif
