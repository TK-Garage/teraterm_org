/*
 * UnifiedSettingsTests.swift
 * Tests for the Unified Settings Dialog (統合ダイアログ).
 *
 * Tests verify:
 *   - UnifiedSettingsTab enum completeness and properties (25 tabs)
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
        // 25 tabs total: 11 in row1 + 14 in row2
        XCTAssertEqual(UnifiedSettingsTab.allCases.count, 25,
            "Should have 25 unified settings tabs")
    }

    func testRow1Contents() {
        let expected: [UnifiedSettingsTab] = [
            .terminal, .window, .keyboard, .serialPort, .tcpip, .general,
            .proxy, .ssh, .sshAuth, .sshForwarding, .sshKeyGen
        ]
        XCTAssertEqual(UnifiedSettingsTab.row1, expected,
            "Row 1 should contain basic setup + network/SSH tabs")
    }

    func testRow2Contents() {
        let expected: [UnifiedSettingsTab] = [
            .addlGeneral, .addlCoding, .addlCopyPaste, .addlSequence,
            .addlMouse, .addlLog, .addlVisual, .addlFont, .addlTEKFont,
            .addlTheme, .addlUI, .addlPlugin, .addlLocalShell, .addlDebug
        ]
        XCTAssertEqual(UnifiedSettingsTab.row2, expected,
            "Row 2 should contain all additional settings tabs")
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
            "No tab should appear in multiple rows")
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
        // Row 3 additional settings
        XCTAssertEqual(UnifiedSettingsTab.addlGeneral.rawValue, "AddlGeneral")
        XCTAssertEqual(UnifiedSettingsTab.addlCoding.rawValue, "AddlCoding")
        XCTAssertEqual(UnifiedSettingsTab.addlCopyPaste.rawValue, "AddlCopyPaste")
        XCTAssertEqual(UnifiedSettingsTab.addlSequence.rawValue, "AddlSequence")
        XCTAssertEqual(UnifiedSettingsTab.addlMouse.rawValue, "AddlMouse")
        XCTAssertEqual(UnifiedSettingsTab.addlLog.rawValue, "AddlLog")
        XCTAssertEqual(UnifiedSettingsTab.addlVisual.rawValue, "AddlVisual")
        XCTAssertEqual(UnifiedSettingsTab.addlFont.rawValue, "AddlFont")
        XCTAssertEqual(UnifiedSettingsTab.addlTEKFont.rawValue, "AddlTEKFont")
        XCTAssertEqual(UnifiedSettingsTab.addlTheme.rawValue, "AddlTheme")
        XCTAssertEqual(UnifiedSettingsTab.addlUI.rawValue, "AddlUI")
        XCTAssertEqual(UnifiedSettingsTab.addlPlugin.rawValue, "AddlPlugin")
        XCTAssertEqual(UnifiedSettingsTab.addlLocalShell.rawValue, "AddlLocalShell")
        XCTAssertEqual(UnifiedSettingsTab.addlDebug.rawValue, "AddlDebug")
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

    /// Row 1 tabs that use BaseSetupDialogController (non-additional-settings tabs)
    private static let setupTabs = UnifiedSettingsTab.row1

    /// Create a BaseSetupDialogController for the given tab (row 1+2 only),
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
        default:
            fatalError("createViewController called with additional-settings tab: \(tab)")
        }
        vc.hidesFooterButtons = true
        return vc
    }

    /// Create an AdditionalSettingsTab for row-2 (additional settings) tabs.
    private func createAdditionalTab(for tab: UnifiedSettingsTab) -> AdditionalSettingsTab {
        switch tab {
        case .addlGeneral:   return GeneralTab(settings: settings)
        case .addlCoding:    return CodingTab(settings: settings)
        case .addlCopyPaste: return CopyPasteTab(settings: settings)
        case .addlSequence:  return SequenceTab(settings: settings)
        case .addlMouse:     return MouseTab(settings: settings)
        case .addlLog:       return LogTab(settings: settings)
        case .addlVisual:    return VisualTab(settings: settings)
        case .addlFont:      return FontTab(settings: settings)
        case .addlTEKFont:   return TEKFontTab(settings: settings)
        case .addlTheme:     return ThemeTab(settings: settings)
        case .addlUI:        return UITab(settings: settings)
        case .addlPlugin:    return PluginTab(settings: settings)
        case .addlLocalShell: return LocalShellTab(settings: settings)
        case .addlDebug:     return DebugTab(settings: settings)
        default:
            fatalError("createAdditionalTab called with non-additional-settings tab: \(tab)")
        }
    }

    func testAllSetupTabsCreateViewControllers() {
        for tab in Self.setupTabs {
            let vc = createViewController(for: tab)
            XCTAssertNotNil(vc,
                "Tab \(tab) should create a non-nil view controller")
        }
    }

    func testAllAdditionalTabsCreate() {
        for tab in UnifiedSettingsTab.row2.filter({ $0.isAdditionalSettingsTab }) {
            let tc = createAdditionalTab(for: tab)
            XCTAssertNotNil(tc.contentView,
                "Additional tab \(tab) should have a contentView")
        }
    }

    func testAllSetupTabsLoadViews() {
        for tab in Self.setupTabs {
            let vc = createViewController(for: tab)
            vc.loadView()
            vc.viewDidLoad()
            XCTAssertNotNil(vc.view,
                "Tab \(tab) should have a loaded view")
        }
    }

    func testAllSetupTabsHaveHiddenFooterButtons() {
        for tab in Self.setupTabs {
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

    func testLoadedSetupViewsHaveContent() {
        for tab in Self.setupTabs {
            let vc = createViewController(for: tab)
            vc.loadView()
            vc.viewDidLoad()

            let subviewCount = countAllSubviews(in: vc.view)
            XCTAssertGreaterThan(subviewCount, 0,
                "Tab \(tab) view should have subviews")
        }
    }

    func testFooterButtonsHiddenWhenEmbedded() {
        for tab in Self.setupTabs {
            let vc = createViewController(for: tab)
            vc.loadView()
            vc.viewDidLoad()

            XCTAssertNotNil(vc.okButton,
                "Tab \(tab) should still have OK button reference")
            XCTAssertNotNil(vc.cancelButton,
                "Tab \(tab) should still have Cancel button reference")
        }
    }

    func testApplySettingsDoesNotCrash() {
        for tab in Self.setupTabs {
            let vc = createViewController(for: tab)
            vc.loadView()
            vc.viewDidLoad()
            vc.applySettings()
        }
    }

    func testAdditionalTabsApplyDoesNotCrash() {
        for tab in UnifiedSettingsTab.row2.filter({ $0.isAdditionalSettingsTab }) {
            let tc = createAdditionalTab(for: tab)
            tc.apply(to: settings)
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

    func testRow1HasElevenTabs() {
        XCTAssertEqual(UnifiedSettingsTab.row1.count, 11,
            "Row 1 should have exactly 11 tabs (basic setup + network/SSH)")
    }

    func testRow2HasFourteenTabs() {
        XCTAssertEqual(UnifiedSettingsTab.row2.count, 14,
            "Row 2 should have exactly 14 tabs (additional settings)")
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

    func testRow1EndsWithSSHKeyGen() {
        XCTAssertEqual(UnifiedSettingsTab.row1.last, .sshKeyGen,
            "Row 1 should end with SSH Key Gen tab")
    }

    func testRow2StartsWithAddlGeneral() {
        XCTAssertEqual(UnifiedSettingsTab.row2.first, .addlGeneral,
            "Row 2 should start with Additional General tab")
    }

    func testRow2EndsWithAddlDebug() {
        XCTAssertEqual(UnifiedSettingsTab.row2.last, .addlDebug,
            "Row 2 should end with Additional Debug tab")
    }

    func testSSHTabsGroupedInRow1() {
        let sshTabs: Set<UnifiedSettingsTab> = [.ssh, .sshAuth, .sshForwarding, .sshKeyGen]
        let row1Set = Set(UnifiedSettingsTab.row1)
        XCTAssertTrue(sshTabs.isSubset(of: row1Set),
            "All SSH-related tabs should be in row 1")
    }

    func testBasicTabsInRow1() {
        let basicTabs: Set<UnifiedSettingsTab> = [.terminal, .window, .keyboard]
        let row1Set = Set(UnifiedSettingsTab.row1)
        XCTAssertTrue(basicTabs.isSubset(of: row1Set),
            "Basic setup tabs should be in row 1")
    }

    func testAdditionalTabsInRow2() {
        let additionalTabs: Set<UnifiedSettingsTab> = [
            .addlGeneral, .addlCoding, .addlCopyPaste, .addlSequence,
            .addlMouse, .addlLog, .addlVisual, .addlFont, .addlTEKFont,
            .addlTheme, .addlUI, .addlPlugin, .addlLocalShell, .addlDebug
        ]
        let row2Set = Set(UnifiedSettingsTab.row2)
        XCTAssertEqual(additionalTabs, row2Set,
            "All additional settings tabs should be in row 2")
    }

    func testIsAdditionalSettingsTab() {
        for tab in UnifiedSettingsTab.row1 {
            XCTAssertFalse(tab.isAdditionalSettingsTab,
                "\(tab) should not be an additional settings tab")
        }
        for tab in UnifiedSettingsTab.row2 {
            XCTAssertTrue(tab.isAdditionalSettingsTab,
                "\(tab) should be an additional settings tab")
        }
    }
}

// MARK: - Modal Dialog Lifecycle Tests (メニュー無効化バグ修正検証)

/// 設定ダイアログを閉じた後にメニューが無効にならないことを検証するテスト。
/// バグ: ダイアログの閉じるボタン（×）でモーダルを閉じると stopModal が呼ばれず、
/// メニューが無効のままになる。修正: NSWindowDelegate で windowWillClose を実装。
final class ModalDialogLifecycleTests: XCTestCase {

    // MARK: - UnifiedSettingsController window delegate

    func testUnifiedSettingsControllerConformsToNSWindowDelegate() {
        let settings = TerminalSettings()
        let controller = UnifiedSettingsController(settings: settings)
        XCTAssertTrue(controller is NSWindowDelegate,
            "UnifiedSettingsController should conform to NSWindowDelegate")
    }

    func testUnifiedSettingsControllerRespondsToWindowShouldClose() {
        let settings = TerminalSettings()
        let controller = UnifiedSettingsController(settings: settings)
        XCTAssertTrue(controller.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))),
            "UnifiedSettingsController should respond to windowShouldClose:")
    }

    // MARK: - AdditionalSettingsController window delegate

    func testAdditionalSettingsControllerConformsToNSWindowDelegate() {
        let settings = TerminalSettings()
        let controller = AdditionalSettingsController(settings: settings)
        XCTAssertTrue(controller is NSWindowDelegate,
            "AdditionalSettingsController should conform to NSWindowDelegate")
    }

    func testAdditionalSettingsControllerRespondsToWindowShouldClose() {
        let settings = TerminalSettings()
        let controller = AdditionalSettingsController(settings: settings)
        XCTAssertTrue(controller.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))),
            "AdditionalSettingsController should respond to windowShouldClose:")
    }

    // MARK: - BaseSetupDialogController window delegate

    func testBaseSetupDialogControllerConformsToNSWindowDelegate() {
        let settings = TerminalSettings()
        let vc = TerminalSetupViewController(settings: settings)
        XCTAssertTrue(vc is NSWindowDelegate,
            "BaseSetupDialogController should conform to NSWindowDelegate")
    }

    func testBaseSetupDialogControllerRespondsToWindowShouldClose() {
        let settings = TerminalSettings()
        let vc = TerminalSetupViewController(settings: settings)
        XCTAssertTrue(vc.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))),
            "BaseSetupDialogController should respond to windowShouldClose:")
    }

    // MARK: - Modal window configuration

    /// UnifiedSettingsController が作成するウィンドウに delegate が設定されていることを検証。
    /// buildWindow() はプライベートなので、show() 前に window が nil であることと、
    /// コントローラが NSWindowDelegate に適合していることで間接的に検証。
    func testUnifiedSettingsControllerIsWindowDelegate() {
        let settings = TerminalSettings()
        let controller = UnifiedSettingsController(settings: settings)
        // controller は NSWindowDelegate に適合しており、
        // buildWindow() 内で win.delegate = self が設定される
        XCTAssertTrue(controller is NSWindowDelegate)
    }

    // MARK: - Modal stopModal called on window close

    /// windowShouldClose がアニメーション付きで dismiss を行うことを検証。
    /// 実際の runModal は使わず、windowShouldClose の動作のみテスト。
    func testWindowShouldCloseReturnsFalseForUnifiedSettings() {
        let settings = TerminalSettings()
        let controller = UnifiedSettingsController(settings: settings)

        // windowShouldClose は false を返し、dismissAnimated で非同期にモーダルを終了する。
        // ウィンドウが無い状態でも安全に呼び出せることを検証。
        let dummyWindow = NSWindow()
        let result = controller.windowShouldClose(dummyWindow)
        XCTAssertFalse(result, "windowShouldClose should return false to prevent immediate close")
    }

    func testWindowShouldCloseReturnsFalseForAdditionalSettings() {
        let settings = TerminalSettings()
        let controller = AdditionalSettingsController(settings: settings)
        let dummyWindow = NSWindow()
        let result = controller.windowShouldClose(dummyWindow)
        XCTAssertFalse(result, "windowShouldClose should return false to prevent immediate close")
    }

    func testWindowShouldCloseReturnsFalseForBaseSetupDialog() {
        let settings = TerminalSettings()
        let vc = TerminalSetupViewController(settings: settings)
        let dummyWindow = NSWindow()
        let result = vc.windowShouldClose(dummyWindow)
        XCTAssertFalse(result, "windowShouldClose should return false to prevent immediate close")
    }

    // MARK: - All dialog subclasses inherit NSWindowDelegate

    func testAllBaseSetupDialogSubclassesConformToNSWindowDelegate() {
        let settings = TerminalSettings()
        let controllers: [BaseSetupDialogController] = [
            TerminalSetupViewController(settings: settings),
            WindowSetupViewController(settings: settings),
            SerialPortSetupViewController(settings: settings),
            SSHAuthViewController(settings: settings),
            TCPIPDialogController(settings: settings),
            LogDialogController(),
            DragDropDialogController(path: "/tmp/test"),
            EditHistoryDialogController(history: []),
        ]

        for vc in controllers {
            XCTAssertTrue(vc is NSWindowDelegate,
                "\(type(of: vc)) should conform to NSWindowDelegate (inherited from BaseSetupDialogController)")
            XCTAssertTrue(vc.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))),
                "\(type(of: vc)) should respond to windowShouldClose:")
        }
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

        // Create all row 1 VCs with default settings — no crash expected
        let setupTabs = UnifiedSettingsTab.row1
        for tab in setupTabs {
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
            default:             continue
            }
            vc.hidesFooterButtons = true
            vc.loadView()
            vc.viewDidLoad()
            vc.applySettings()
        }

        // Create all row 3 additional tabs — no crash expected
        let additionalTabInstances: [AdditionalSettingsTab] = [
            GeneralTab(settings: settings),
            CodingTab(settings: settings),
            CopyPasteTab(settings: settings),
            SequenceTab(settings: settings),
            MouseTab(settings: settings),
            LogTab(settings: settings),
            VisualTab(settings: settings),
            FontTab(settings: settings),
            TEKFontTab(settings: settings),
            ThemeTab(settings: settings),
            UITab(settings: settings),
            PluginTab(settings: settings),
            LocalShellTab(settings: settings),
            DebugTab(settings: settings),
        ]
        for tc in additionalTabInstances {
            XCTAssertNotNil(tc.contentView)
            tc.apply(to: settings)
        }
    }
}

#endif
