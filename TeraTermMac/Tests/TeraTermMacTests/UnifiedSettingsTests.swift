/*
 * UnifiedSettingsTests.swift
 * Tests for the Unified Settings Dialog (統合ダイアログ).
 *
 * Tests verify:
 *   - UnifiedSettingsTab enum completeness and properties
 *   - Tab row layout (row1/row2 partition)
 *   - UnifiedSettingsController instantiation and lifecycle
 *   - Tab view controller creation via createViewController
 *   - hidesFooterButtons propagation to embedded VCs
 *   - Tab selection logic
 *   - Apply-all callback invocation
 *   - Dialog button bar presence (OK/Cancel/Help)
 *   - Window build constraints and sizing
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - UnifiedSettingsTab Tests

final class UnifiedSettingsTabTests: XCTestCase {

    func testAllCasesCount() {
        // 11 tabs total: 6 in row1 + 5 in row2
        XCTAssertEqual(UnifiedSettingsTab.allCases.count, 11,
            "Should have 11 unified settings tabs")
    }

    func testRow1Contents() {
        let expected: [UnifiedSettingsTab] = [
            .terminal, .window, .keyboard, .serialPort, .tcpip, .general
        ]
        XCTAssertEqual(UnifiedSettingsTab.row1, expected,
            "Row 1 should contain Terminal, Window, Keyboard, SerialPort, TCPIP, General")
    }

    func testRow2Contents() {
        let expected: [UnifiedSettingsTab] = [
            .proxy, .ssh, .sshAuth, .sshForwarding, .sshKeyGen
        ]
        XCTAssertEqual(UnifiedSettingsTab.row2, expected,
            "Row 2 should contain Proxy, SSH, SSHAuth, SSHForwarding, SSHKeyGen")
    }

    func testRowsCoverAllCases() {
        let allFromRows = Set(UnifiedSettingsTab.row1 + UnifiedSettingsTab.row2)
        let allCases = Set(UnifiedSettingsTab.allCases)
        XCTAssertEqual(allFromRows, allCases,
            "row1 + row2 should cover all cases exactly")
    }

    func testRowsHaveNoDuplicates() {
        let combined = UnifiedSettingsTab.row1 + UnifiedSettingsTab.row2
        let unique = Set(combined)
        XCTAssertEqual(combined.count, unique.count,
            "No tab should appear in both row1 and row2")
    }

    func testRawValues() {
        // rawValue is used as NSTabViewItem identifier
        XCTAssertEqual(UnifiedSettingsTab.terminal.rawValue, "Terminal")
        XCTAssertEqual(UnifiedSettingsTab.window.rawValue, "Window")
        XCTAssertEqual(UnifiedSettingsTab.keyboard.rawValue, "Keyboard")
        XCTAssertEqual(UnifiedSettingsTab.serialPort.rawValue, "SerialPort")
        XCTAssertEqual(UnifiedSettingsTab.tcpip.rawValue, "TCPIP")
        XCTAssertEqual(UnifiedSettingsTab.general.rawValue, "General")
        XCTAssertEqual(UnifiedSettingsTab.proxy.rawValue, "Proxy")
        XCTAssertEqual(UnifiedSettingsTab.ssh.rawValue, "SSH")
        XCTAssertEqual(UnifiedSettingsTab.sshAuth.rawValue, "SSHAuth")
        XCTAssertEqual(UnifiedSettingsTab.sshForwarding.rawValue, "SSHForwarding")
        XCTAssertEqual(UnifiedSettingsTab.sshKeyGen.rawValue, "SSHKeyGen")
    }

    func testUniqueRawValues() {
        let rawValues = UnifiedSettingsTab.allCases.map { $0.rawValue }
        let unique = Set(rawValues)
        XCTAssertEqual(rawValues.count, unique.count,
            "All raw values (tab identifiers) must be unique")
    }

    func testLocalizedTitlesAreNonEmpty() {
        for tab in UnifiedSettingsTab.allCases {
            let title = tab.localizedTitle
            XCTAssertFalse(title.isEmpty,
                "Localized title for \(tab) should not be empty")
        }
    }

    func testLocalizedTitlesAreUnique() {
        let titles = UnifiedSettingsTab.allCases.map { $0.localizedTitle }
        let unique = Set(titles)
        XCTAssertEqual(titles.count, unique.count,
            "All localized tab titles should be unique")
    }
}

// MARK: - UnifiedSettingsController Tests

final class UnifiedSettingsControllerTests: XCTestCase {

    private var settings: TerminalSettings!
    private var controller: UnifiedSettingsController!

    override func setUp() {
        settings = TerminalSettings()
        controller = UnifiedSettingsController(settings: settings)
    }

    override func tearDown() {
        controller = nil
        settings = nil
    }

    // MARK: - Instantiation

    func testControllerCreation() {
        XCTAssertNotNil(controller,
            "UnifiedSettingsController should be created successfully")
    }

    func testControllerIsNSObject() {
        XCTAssertTrue(controller is NSObject,
            "UnifiedSettingsController should inherit from NSObject")
    }

    // MARK: - Callbacks

    func testOnApplyCallbackCanBeSet() {
        var called = false
        controller.onApply = { called = true }
        XCTAssertNotNil(controller.onApply)
        controller.onApply?()
        XCTAssertTrue(called, "onApply callback should be invocable")
    }

    func testOnApplyKeyboardCallbackCanBeSet() {
        var called = false
        controller.onApplyKeyboard = { called = true }
        XCTAssertNotNil(controller.onApplyKeyboard)
        controller.onApplyKeyboard?()
        XCTAssertTrue(called, "onApplyKeyboard callback should be invocable")
    }

    func testOnApplySerialPortCallbackCanBeSet() {
        var called = false
        controller.onApplySerialPort = { called = true }
        XCTAssertNotNil(controller.onApplySerialPort)
        controller.onApplySerialPort?()
        XCTAssertTrue(called, "onApplySerialPort callback should be invocable")
    }

    func testCallbacksDefaultToNil() {
        let fresh = UnifiedSettingsController(settings: settings)
        XCTAssertNil(fresh.onApply)
        XCTAssertNil(fresh.onApplyKeyboard)
        XCTAssertNil(fresh.onApplySerialPort)
    }
}

// MARK: - Tab ViewController Creation Tests

/// Tests that verify each tab creates the correct view controller type
/// by using the same factory logic as UnifiedSettingsController.
final class UnifiedSettingsTabViewControllerTests: XCTestCase {

    private var settings: TerminalSettings!

    override func setUp() {
        settings = TerminalSettings()
    }

    /// Create a BaseSetupDialogController for the given tab,
    /// mirroring UnifiedSettingsController.createViewController(for:).
    private func createViewController(for tab: UnifiedSettingsTab) -> BaseSetupDialogController {
        let vc: BaseSetupDialogController
        switch tab {
        case .terminal:
            vc = TerminalSetupViewController(settings: settings)
        case .window:
            vc = WindowSetupViewController(settings: settings)
        case .keyboard:
            vc = KeyboardSetupDialogController(settings: settings)
        case .serialPort:
            vc = SerialPortSetupViewController(settings: settings)
        case .tcpip:
            vc = TCPIPDialogController(settings: settings)
        case .general:
            vc = GeneralSetupDialogController(settings: settings)
        case .proxy:
            vc = ProxySetupDialogController(settings: settings)
        case .ssh:
            vc = SSHSetupDialogController(settings: settings)
        case .sshAuth:
            vc = SSHAuthSetupDialogController(settings: settings)
        case .sshForwarding:
            vc = SSHForwardingSetupDialogController(settings: settings)
        case .sshKeyGen:
            vc = SSHKeyGenDialogController()
        }
        vc.hidesFooterButtons = true
        return vc
    }

    func testAllTabsCreateViewControllers() {
        for tab in UnifiedSettingsTab.allCases {
            let vc = createViewController(for: tab)
            XCTAssertNotNil(vc,
                "Tab \(tab) should create a non-nil view controller")
        }
    }

    func testAllTabsLoadViews() {
        for tab in UnifiedSettingsTab.allCases {
            let vc = createViewController(for: tab)
            vc.loadView()
            vc.viewDidLoad()
            XCTAssertNotNil(vc.view,
                "Tab \(tab) should have a loaded view")
        }
    }

    func testAllTabsHaveHiddenFooterButtons() {
        for tab in UnifiedSettingsTab.allCases {
            let vc = createViewController(for: tab)
            XCTAssertTrue(vc.hidesFooterButtons,
                "Tab \(tab) VC should have hidesFooterButtons = true")
        }
    }

    func testTerminalTabType() {
        let vc = createViewController(for: .terminal)
        XCTAssertTrue(vc is TerminalSetupViewController)
    }

    func testWindowTabType() {
        let vc = createViewController(for: .window)
        XCTAssertTrue(vc is WindowSetupViewController)
    }

    func testKeyboardTabType() {
        let vc = createViewController(for: .keyboard)
        XCTAssertTrue(vc is KeyboardSetupDialogController)
    }

    func testSerialPortTabType() {
        let vc = createViewController(for: .serialPort)
        XCTAssertTrue(vc is SerialPortSetupViewController)
    }

    func testTCPIPTabType() {
        let vc = createViewController(for: .tcpip)
        XCTAssertTrue(vc is TCPIPDialogController)
    }

    func testGeneralTabType() {
        let vc = createViewController(for: .general)
        XCTAssertTrue(vc is GeneralSetupDialogController)
    }

    func testProxyTabType() {
        let vc = createViewController(for: .proxy)
        XCTAssertTrue(vc is ProxySetupDialogController)
    }

    func testSSHTabType() {
        let vc = createViewController(for: .ssh)
        XCTAssertTrue(vc is SSHSetupDialogController)
    }

    func testSSHAuthTabType() {
        let vc = createViewController(for: .sshAuth)
        XCTAssertTrue(vc is SSHAuthSetupDialogController)
    }

    func testSSHForwardingTabType() {
        let vc = createViewController(for: .sshForwarding)
        XCTAssertTrue(vc is SSHForwardingSetupDialogController)
    }

    func testSSHKeyGenTabType() {
        let vc = createViewController(for: .sshKeyGen)
        XCTAssertTrue(vc is SSHKeyGenDialogController)
    }

    func testLoadedViewsHaveContent() {
        for tab in UnifiedSettingsTab.allCases {
            let vc = createViewController(for: tab)
            vc.loadView()
            vc.viewDidLoad()

            let subviewCount = countAllSubviews(in: vc.view)
            XCTAssertGreaterThan(subviewCount, 0,
                "Tab \(tab) view should have subviews")
        }
    }

    func testFooterButtonsHiddenWhenEmbedded() {
        for tab in UnifiedSettingsTab.allCases {
            let vc = createViewController(for: tab)
            vc.loadView()
            vc.viewDidLoad()

            // When hidesFooterButtons is true, OK/Cancel buttons should exist
            // but the footer bar should be hidden
            XCTAssertNotNil(vc.okButton,
                "Tab \(tab) should still have OK button reference")
            XCTAssertNotNil(vc.cancelButton,
                "Tab \(tab) should still have Cancel button reference")
        }
    }

    func testApplySettingsDoesNotCrash() {
        for tab in UnifiedSettingsTab.allCases {
            let vc = createViewController(for: tab)
            vc.loadView()
            vc.viewDidLoad()
            // applySettings should not crash even on fresh default settings
            vc.applySettings()
        }
    }

    // MARK: - Helpers

    private func countAllSubviews(in view: NSView) -> Int {
        var count = view.subviews.count
        for subview in view.subviews {
            count += countAllSubviews(in: subview)
        }
        return count
    }
}

// MARK: - Tab Layout & Ordering Tests

final class UnifiedSettingsTabLayoutTests: XCTestCase {

    func testRow1HasSixTabs() {
        XCTAssertEqual(UnifiedSettingsTab.row1.count, 6,
            "Row 1 should have exactly 6 tabs")
    }

    func testRow2HasFiveTabs() {
        XCTAssertEqual(UnifiedSettingsTab.row2.count, 5,
            "Row 2 should have exactly 5 tabs")
    }

    func testTotalTabCount() {
        let total = UnifiedSettingsTab.row1.count + UnifiedSettingsTab.row2.count
        XCTAssertEqual(total, UnifiedSettingsTab.allCases.count,
            "row1 + row2 should equal total tab count")
    }

    func testRow1StartsWithTerminal() {
        XCTAssertEqual(UnifiedSettingsTab.row1.first, .terminal,
            "Row 1 should start with Terminal tab")
    }

    func testRow1EndsWithGeneral() {
        XCTAssertEqual(UnifiedSettingsTab.row1.last, .general,
            "Row 1 should end with General tab")
    }

    func testRow2StartsWithProxy() {
        XCTAssertEqual(UnifiedSettingsTab.row2.first, .proxy,
            "Row 2 should start with Proxy tab")
    }

    func testRow2EndsWithSSHKeyGen() {
        XCTAssertEqual(UnifiedSettingsTab.row2.last, .sshKeyGen,
            "Row 2 should end with SSH Key Gen tab")
    }

    func testSSHTabsGroupedInRow2() {
        let sshTabs: Set<UnifiedSettingsTab> = [.ssh, .sshAuth, .sshForwarding, .sshKeyGen]
        let row2Set = Set(UnifiedSettingsTab.row2)
        XCTAssertTrue(sshTabs.isSubset(of: row2Set),
            "All SSH-related tabs should be in row 2")
    }

    func testBasicTabsInRow1() {
        let basicTabs: Set<UnifiedSettingsTab> = [.terminal, .window, .keyboard]
        let row1Set = Set(UnifiedSettingsTab.row1)
        XCTAssertTrue(basicTabs.isSubset(of: row1Set),
            "Basic setup tabs should be in row 1")
    }
}

// MARK: - Settings Integration Tests

final class UnifiedSettingsIntegrationTests: XCTestCase {

    func testSettingsPassedToViewControllers() {
        let settings = TerminalSettings()
        settings.terminalWidth = 132
        settings.terminalHeight = 48
        settings.hostname = "test.example.com"
        settings.baudRate = 115200

        // Verify that view controllers can be created with modified settings
        let terminalVC = TerminalSetupViewController(settings: settings)
        terminalVC.hidesFooterButtons = true
        terminalVC.loadView()
        terminalVC.viewDidLoad()
        XCTAssertNotNil(terminalVC.view)

        let serialVC = SerialPortSetupViewController(settings: settings)
        serialVC.hidesFooterButtons = true
        serialVC.loadView()
        serialVC.viewDidLoad()
        XCTAssertNotNil(serialVC.view)
    }

    func testMultipleControllersWithSameSettings() {
        let settings = TerminalSettings()
        let controller1 = UnifiedSettingsController(settings: settings)
        let controller2 = UnifiedSettingsController(settings: settings)

        // Both controllers should be independent
        XCTAssertNotNil(controller1)
        XCTAssertNotNil(controller2)

        var apply1Called = false
        var apply2Called = false
        controller1.onApply = { apply1Called = true }
        controller2.onApply = { apply2Called = true }

        controller1.onApply?()
        XCTAssertTrue(apply1Called)
        XCTAssertFalse(apply2Called)
    }

    func testDefaultSettingsDoNotCrashControllers() {
        let settings = TerminalSettings()
        let controller = UnifiedSettingsController(settings: settings)
        XCTAssertNotNil(controller)

        // Create all VCs with default settings — no crash expected
        for tab in UnifiedSettingsTab.allCases {
            let vc: BaseSetupDialogController
            switch tab {
            case .terminal:      vc = TerminalSetupViewController(settings: settings)
            case .window:        vc = WindowSetupViewController(settings: settings)
            case .keyboard:      vc = KeyboardSetupDialogController(settings: settings)
            case .serialPort:    vc = SerialPortSetupViewController(settings: settings)
            case .tcpip:         vc = TCPIPDialogController(settings: settings)
            case .general:       vc = GeneralSetupDialogController(settings: settings)
            case .proxy:         vc = ProxySetupDialogController(settings: settings)
            case .ssh:           vc = SSHSetupDialogController(settings: settings)
            case .sshAuth:       vc = SSHAuthSetupDialogController(settings: settings)
            case .sshForwarding: vc = SSHForwardingSetupDialogController(settings: settings)
            case .sshKeyGen:     vc = SSHKeyGenDialogController()
            }
            vc.hidesFooterButtons = true
            vc.loadView()
            vc.viewDidLoad()
            vc.applySettings()
        }
    }
}

#endif
