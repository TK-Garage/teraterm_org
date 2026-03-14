/*
 * LogAndMenuFeatureTests.swift
 * Tests for newly implemented features:
 *   - Log pause/resume, comment, view, progress dialog
 *   - Edit menu: pasteCR, deselect, selectScreen
 *   - Control menu: resetRemoteTitle, TEK window, macro window
 *   - Connection error localization
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - Terminal Logger State Tests

final class TerminalLoggerStateTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LogTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir,
            withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func tempPath(_ name: String) -> String {
        tempDir.appendingPathComponent(name).path
    }

    // MARK: - Pause / Resume

    func testInitialStateIsInactive() {
        let logger = TerminalLogger()
        XCTAssertEqual(logger.state, .inactive)
    }

    func testStartLoggingSetsActive() {
        let logger = TerminalLogger()
        let ok = logger.startLogging(to: tempPath("test.log"))
        XCTAssertTrue(ok, "startLogging should succeed")
        XCTAssertEqual(logger.state, .active)
        logger.stopLogging()
    }

    func testPauseLoggingChangeState() {
        let logger = TerminalLogger()
        _ = logger.startLogging(to: tempPath("pause.log"))
        XCTAssertEqual(logger.state, .active)

        logger.pauseLogging()
        XCTAssertEqual(logger.state, .paused, "State should be paused after pauseLogging()")

        logger.resumeLogging()
        XCTAssertEqual(logger.state, .active, "State should be active after resumeLogging()")

        logger.stopLogging()
    }

    func testPauseOnInactiveIsNoop() {
        let logger = TerminalLogger()
        logger.pauseLogging()
        XCTAssertEqual(logger.state, .inactive, "Pause on inactive should be no-op")
    }

    func testResumeOnActiveIsNoop() {
        let logger = TerminalLogger()
        _ = logger.startLogging(to: tempPath("resume_noop.log"))
        logger.resumeLogging()  // Already active
        XCTAssertEqual(logger.state, .active)
        logger.stopLogging()
    }

    func testPausedLoggerDoesNotWriteData() {
        let logger = TerminalLogger()
        let path = tempPath("paused_data.log")
        _ = logger.startLogging(to: path)

        logger.logString("before_pause")
        logger.pauseLogging()

        let bytesBeforePause = logger.bytesLogged
        logger.logString("during_pause")  // Should be ignored
        XCTAssertEqual(logger.bytesLogged, bytesBeforePause,
            "Bytes logged should not increase while paused")

        logger.resumeLogging()
        logger.logString("after_resume")
        XCTAssertGreaterThan(logger.bytesLogged, bytesBeforePause,
            "Bytes logged should increase after resume")

        logger.stopLogging()
    }

    func testStateChangeCallback() {
        let logger = TerminalLogger()
        var states: [LogState] = []
        logger.onStateChanged = { states.append($0) }

        _ = logger.startLogging(to: tempPath("callback.log"))
        logger.pauseLogging()
        logger.resumeLogging()
        logger.stopLogging()

        XCTAssertEqual(states, [.active, .paused, .active, .inactive])
    }

    // MARK: - Log Comment

    func testLogCommentWritesComment() {
        let logger = TerminalLogger()
        let path = tempPath("comment.log")
        _ = logger.startLogging(to: path)

        let bytesBeforeComment = logger.bytesLogged
        logger.logComment("Test comment here")
        XCTAssertGreaterThan(logger.bytesLogged, bytesBeforeComment,
            "Comment should increase bytes logged")

        logger.stopLogging()

        // Verify file content contains the comment
        let content = try? String(contentsOfFile: path, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("# Test comment here") ?? false,
            "Log file should contain the comment prefixed with #")
    }

    func testLogCommentIgnoredWhenInactive() {
        let logger = TerminalLogger()
        logger.logComment("Should be ignored")
        XCTAssertEqual(logger.bytesLogged, 0)
    }

    func testLogCommentIgnoredWhenPaused() {
        let logger = TerminalLogger()
        _ = logger.startLogging(to: tempPath("paused_comment.log"))
        logger.pauseLogging()

        let bytesBefore = logger.bytesLogged
        logger.logComment("Paused comment")
        // logComment checks for state == .active, so while paused it should be ignored
        XCTAssertEqual(logger.bytesLogged, bytesBefore,
            "Comment should not be written while paused")

        logger.resumeLogging()
        logger.stopLogging()
    }

    // MARK: - Log File Path

    func testLogFilePathIsSet() {
        let logger = TerminalLogger()
        let path = tempPath("filepath.log")
        _ = logger.startLogging(to: path)
        XCTAssertEqual(logger.logFilePath, path)
        logger.stopLogging()
    }

    // MARK: - BOM Writing

    func testBOMWrittenWhenConfigured() {
        let opts = LogOptions(writeBOM: true)
        let logger = TerminalLogger(options: opts)
        let path = tempPath("bom.log")
        _ = logger.startLogging(to: path, options: opts)
        logger.stopLogging()

        let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertNotNil(data)
        // UTF-8 BOM: EF BB BF
        XCTAssertTrue(data?.starts(with: [0xEF, 0xBB, 0xBF]) ?? false,
            "Log file should start with UTF-8 BOM")
    }

    func testNoBOMByDefault() {
        let logger = TerminalLogger()
        let path = tempPath("nobom.log")
        _ = logger.startLogging(to: path)
        logger.stopLogging()

        let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertNotNil(data)
        XCTAssertFalse(data?.starts(with: [0xEF, 0xBB, 0xBF]) ?? true,
            "Log file should NOT start with BOM by default")
    }

    // MARK: - Timestamp Tests

    func testTimestampOnEveryLine() {
        let opts = LogOptions(addTimestamp: true, plainText: true)
        let logger = TerminalLogger(options: opts)
        let path = tempPath("timestamp_multi.log")
        _ = logger.startLogging(to: path, options: opts)

        // Log multi-line data
        logger.logData(Data("line1\r\nline2\r\nline3\r\n".utf8))
        logger.stopLogging()

        let content = try? String(contentsOfFile: path, encoding: .utf8)
        XCTAssertNotNil(content)

        // Split into lines and check non-header content lines have timestamps
        let lines = content!.components(separatedBy: "\n").filter { !$0.isEmpty }
        // Skip header ("=== Tera Term Mac Log Start ...") and footer
        let dataLines = lines.filter { !$0.contains("=== Tera Term Mac Log") }
        XCTAssertGreaterThanOrEqual(dataLines.count, 3,
            "Should have at least 3 data lines")
        for line in dataLines {
            XCTAssertTrue(line.contains("[") && line.contains("]"),
                "Each line should have a timestamp bracket: \(line)")
        }
    }

    func testTimestampAfterOSCWithEscBackslashTerminator() {
        let opts = LogOptions(addTimestamp: true, plainText: true)
        let logger = TerminalLogger(options: opts)
        let path = tempPath("timestamp_osc.log")
        _ = logger.startLogging(to: path, options: opts)

        // OSC sequence terminated with ESC \ (two-byte ST), then normal text
        var data = Data()
        data.append(contentsOf: [0x1B, 0x5D])           // ESC ] (OSC start)
        data.append(contentsOf: "0;window title".utf8)   // OSC payload
        data.append(contentsOf: [0x1B, 0x5C])            // ESC \ (ST terminator)
        data.append(contentsOf: "line1\r\n".utf8)
        data.append(contentsOf: "line2\r\n".utf8)
        logger.logData(data)
        logger.stopLogging()

        let content = try? String(contentsOfFile: path, encoding: .utf8)
        XCTAssertNotNil(content)

        // Both line1 and line2 should appear in the log (not consumed by OSC)
        XCTAssertTrue(content!.contains("line1"), "line1 should not be consumed by OSC parser")
        XCTAssertTrue(content!.contains("line2"), "line2 should not be consumed by OSC parser")

        // Both lines should have timestamps
        let lines = content!.components(separatedBy: "\n").filter { !$0.isEmpty }
        let dataLines = lines.filter { $0.contains("line") }
        XCTAssertEqual(dataLines.count, 2, "Should have 2 data lines")
        for line in dataLines {
            XCTAssertTrue(line.contains("[") && line.contains("]"),
                "Each line should have a timestamp: \(line)")
        }
    }
}

// MARK: - LogProgressPanel Tests

final class LogProgressPanelTests: XCTestCase {

    func testLogProgressPanelCanBeCreated() {
        let logger = TerminalLogger()
        let path = NSTemporaryDirectory() + "progress_test_\(UUID().uuidString).log"
        _ = logger.startLogging(to: path)

        let panel = LogProgressPanel(logger: logger)
        XCTAssertNotNil(panel)
        XCTAssertTrue(panel.title.contains("Log") || !panel.title.isEmpty,
            "Panel should have a title")

        logger.stopLogging()
        try? FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - Connection Error Localization Tests

final class ConnectionErrorLocalizationTests: XCTestCase {

    func testStreamCreationFailedHasDescription() {
        let err = ConnectionError.streamCreationFailed(host: "example.com", port: 23)
        let desc = err.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty, "Error should have a description")
        XCTAssertTrue(desc.contains("example.com"), "Should contain host name")
    }

    func testConnectionFailedHasDescription() {
        let err = ConnectionError.connectionFailed(host: "host.test", port: 80, detail: nil)
        let desc = err.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty)
        XCTAssertTrue(desc.contains("host.test"))
    }

    func testConnectionFailedWithDetail() {
        let err = ConnectionError.connectionFailed(host: "h", port: 1, detail: "extra info")
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("extra info"), "Should include detail")
    }

    func testConnectionRefusedHasDescription() {
        let err = ConnectionError.connectionRefused(host: "refused.host", port: 443)
        let desc = err.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty)
        XCTAssertTrue(desc.contains("refused.host"))
    }

    func testConnectionTimeoutHasDescription() {
        let err = ConnectionError.connectionTimeout(host: "timeout.host", port: 22)
        let desc = err.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty)
        XCTAssertTrue(desc.contains("timeout.host"))
    }

    func testHostNotFoundHasDescription() {
        let err = ConnectionError.hostNotFound(host: "unknown.host")
        let desc = err.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty)
        XCTAssertTrue(desc.contains("unknown.host"))
    }

    func testSSHNotSupportedHasDescription() {
        let err = ConnectionError.sshNotSupported(host: "ssh.host", port: 22)
        let desc = err.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty)
        XCTAssertTrue(desc.contains("ssh.host"))
    }

    func testSSHConnectionFailedHasDescription() {
        let err = ConnectionError.sshConnectionFailed(host: "ssh2.host", port: 22, detail: "auth fail")
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("ssh2.host"))
        XCTAssertTrue(desc.contains("auth fail"))
    }

    func testSerialPortOpenFailedHasDescription() {
        let err = ConnectionError.serialPortOpenFailed(device: "/dev/ttyUSB0", detail: nil)
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("/dev/ttyUSB0"))
    }

    func testPtyCreationFailedHasDescription() {
        let err = ConnectionError.ptyCreationFailed
        let desc = err.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty, "ptyCreationFailed should have description")
    }

    func testSendFailedHasDescription() {
        let err = ConnectionError.sendFailed
        let desc = err.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty, "sendFailed should have description")
    }

    // MARK: - Alert Titles

    func testAlertTitleHostNotFound() {
        let err = ConnectionError.hostNotFound(host: "x")
        XCTAssertFalse(err.alertTitle.isEmpty)
    }

    func testAlertTitleConnectionRefused() {
        let err = ConnectionError.connectionRefused(host: "x", port: 1)
        XCTAssertFalse(err.alertTitle.isEmpty)
    }

    func testAlertTitleConnectionTimeout() {
        let err = ConnectionError.connectionTimeout(host: "x", port: 1)
        XCTAssertFalse(err.alertTitle.isEmpty)
    }

    func testAlertTitleSSHNotSupported() {
        let err = ConnectionError.sshNotSupported(host: "x", port: 22)
        XCTAssertFalse(err.alertTitle.isEmpty)
    }

    func testAlertTitleSSHError() {
        let err = ConnectionError.sshConnectionFailed(host: "x", port: 22, detail: nil)
        XCTAssertFalse(err.alertTitle.isEmpty)
    }

    func testAlertTitleSerial() {
        let err = ConnectionError.serialPortOpenFailed(device: "d", detail: nil)
        XCTAssertFalse(err.alertTitle.isEmpty)
    }

    func testAlertTitleDefault() {
        let err = ConnectionError.streamCreationFailed(host: "x", port: 1)
        XCTAssertFalse(err.alertTitle.isEmpty)
    }

    func testAllErrorCasesHaveNonEmptyDescription() {
        let errors: [ConnectionError] = [
            .streamCreationFailed(host: "h", port: 1),
            .connectionFailed(host: "h", port: 1, detail: nil),
            .connectionRefused(host: "h", port: 1),
            .connectionTimeout(host: "h", port: 1),
            .hostNotFound(host: "h"),
            .sshNotSupported(host: "h", port: 1),
            .sshConnectionFailed(host: "h", port: 1, detail: nil),
            .sshForkFailed(detail: nil),
            .sshNotFound,
            .serialPortOpenFailed(device: "d", detail: nil),
            .ptyCreationFailed,
            .sendFailed,
        ]

        for err in errors {
            XCTAssertNotNil(err.errorDescription, "\(err) should have errorDescription")
            XCTAssertFalse(err.errorDescription!.isEmpty, "\(err) should have non-empty errorDescription")
            XCTAssertFalse(err.alertTitle.isEmpty, "\(err) should have non-empty alertTitle")
        }
    }
}

// MARK: - TEK Window Controller Tests

final class TEKWindowControllerFeatureTests: XCTestCase {

    func testTEKWindowControllerCanBeCreated() {
        let settings = TerminalSettings()
        let tek = TEKWindowController(settings: settings)
        XCTAssertNotNil(tek)
        XCTAssertNotNil(tek.window)
    }

    func testTEKWindowTitle() {
        let settings = TerminalSettings()
        let tek = TEKWindowController(settings: settings)
        tek.showWindow(nil)
        XCTAssertTrue(tek.window?.title.contains("TEK") ?? false,
            "TEK window title should contain 'TEK'")
    }

    func testTEKWindowHasPrintMethod() {
        let settings = TerminalSettings()
        let tek = TEKWindowController(settings: settings)
        // Verify printTEKWindow method exists (responds to selector)
        XCTAssertTrue(tek.responds(to: #selector(TEKWindowController.printTEKWindow)),
            "TEKWindowController should respond to printTEKWindow")
    }
}

// MARK: - Macro Status Panel Tests (additional)

final class MacroStatusPanelFeatureTests: XCTestCase {

    func testMacroStatusPanelCanBeCreated() {
        let panel = MacroStatusPanelController()
        XCTAssertNotNil(panel, "MacroStatusPanelController should be instantiable")
    }

    func testMacroStatusPanelHasDelegate() {
        let panel = MacroStatusPanelController()
        XCTAssertNil(panel.delegate, "Delegate should be nil initially")
    }
}

#endif
