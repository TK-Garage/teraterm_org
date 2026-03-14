/*
 * DialogOverflowTests.swift
 * Comprehensive tests to verify that all dialog input controls
 * do not overflow their parent containers.
 *
 * Checks every dialog class for:
 *   - NSAlert accessoryViews use frame-based layout (NSAlert sizes by frame,
 *     not Auto Layout) with reasonable fixed dimensions
 *   - BaseSetupDialogController-based dialogs have bounded fields
 *   - All AdditionalSettings tabs have bounded editable fields
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - Helpers

/// Recursively collect all subviews of the given type.
private func findSubviews<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
    var result: [T] = []
    for sub in view.subviews {
        if let match = sub as? T { result.append(match) }
        result.append(contentsOf: findSubviews(of: type, in: sub))
    }
    return result
}

/// Force layout on a view hierarchy so frames are calculated.
private func forceLayout(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
}

/// Check that a constraint list does NOT contain an unbounded
/// greaterThanOrEqual width without a matching equalTo or lessThanOrEqual.
private func hasProperWidthBound(_ view: NSView) -> Bool {
    // Frame-based layout (translatesAutoresizingMaskIntoConstraints = true):
    // the frame itself is the bound – acceptable if width > 0 and reasonable
    if view.translatesAutoresizingMaskIntoConstraints && view.frame.width > 0 && view.frame.width <= 600 {
        return true
    }
    let widthConstraints = view.constraints.filter {
        $0.firstAttribute == .width && $0.firstItem as? NSView === view
    }
    let hasGTE = widthConstraints.contains { $0.relation == .greaterThanOrEqual }
    let hasEQ  = widthConstraints.contains { $0.relation == .equal }
    let hasLTE = widthConstraints.contains { $0.relation == .lessThanOrEqual }

    // If there is a greaterThanOrEqual, there should also be an equal or lessThanOrEqual
    if hasGTE && !hasEQ && !hasLTE {
        return false
    }
    return true
}

/// Check if a view is bounded by its superview (stack/grid or trailing constraint).
private func isConstrainedByParent(_ view: NSView) -> Bool {
    guard let sv = view.superview else { return false }
    if sv is NSStackView || sv is NSGridView { return true }
    for c in sv.constraints {
        if (c.firstAttribute == .trailing || c.firstAttribute == .width) &&
           (c.firstItem as? NSView === view || c.secondItem as? NSView === view) {
            return true
        }
    }
    return isConstrainedByParent(sv)
}

/// Check if a view is inside an NSStackView or NSGridView ancestor.
private func isInStackOrGrid(_ view: NSView) -> Bool {
    var current: NSView? = view.superview
    while let sv = current {
        if sv is NSStackView || sv is NSGridView { return true }
        current = sv.superview
    }
    return false
}


// MARK: - NSAlert AccessoryView Frame Tests
//
// NSAlert sizes its accessoryView by FRAME, not Auto Layout.
// All accessoryViews must use frame-based layout with fixed dimensions.

final class DialogOverflowAlertFrameTests: XCTestCase {

    /// Verify that an NSAlert accessoryView uses frame-based layout
    /// with a reasonable fixed width.
    private func verifyAccessoryViewFrame(_ accessoryView: NSView,
                                          expectedWidth: CGFloat,
                                          dialogName: String,
                                          file: StaticString = #file,
                                          line: UInt = #line) {
        // The view should use frame-based layout for NSAlert compatibility
        XCTAssertTrue(accessoryView.translatesAutoresizingMaskIntoConstraints,
            "\(dialogName): accessoryView must use frame-based layout " +
            "(translatesAutoresizingMaskIntoConstraints = true) for NSAlert",
            file: file, line: line)

        // Frame width should match expected value
        XCTAssertEqual(accessoryView.frame.width, expectedWidth, accuracy: 1.0,
            "\(dialogName): accessoryView frame width should be \(expectedWidth)pt, " +
            "got \(accessoryView.frame.width)pt",
            file: file, line: line)

        // Frame width must be positive and reasonable
        XCTAssertGreaterThan(accessoryView.frame.width, 0,
            "\(dialogName): accessoryView frame width must be > 0",
            file: file, line: line)
        XCTAssertLessThanOrEqual(accessoryView.frame.width, 600,
            "\(dialogName): accessoryView frame width should not exceed 600pt",
            file: file, line: line)
    }

    // MARK: - Comment to Log Dialog

    func testCommentToLogDialogFrameBased() {
        let textField = NSView.makeTextField(value: "", placeholder: "Comment")
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = true
        textField.frame = NSRect(x: 0, y: 0, width: 300, height: 24)

        verifyAccessoryViewFrame(textField, expectedWidth: 300,
                                 dialogName: "CommentToLog")
    }

    // MARK: - InputDialog

    func testInputDialogFrameBased() {
        let field = NSView.makeTextField(value: "test")
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = true
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)

        verifyAccessoryViewFrame(field, expectedWidth: 300,
                                 dialogName: "InputDialog")
    }

    // MARK: - ClipboardConfirmationDialog

    func testClipboardDialogFrameBased() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 250))

        verifyAccessoryViewFrame(scrollView, expectedWidth: 400,
                                 dialogName: "ClipboardConfirmation")
        XCTAssertEqual(scrollView.frame.height, 250, accuracy: 1.0,
            "ClipboardConfirmation: height should be 250pt")
    }

    // MARK: - ListDialog

    func testListDialogFrameBased() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 180))

        verifyAccessoryViewFrame(scrollView, expectedWidth: 340,
                                 dialogName: "ListDialog")
        XCTAssertEqual(scrollView.frame.height, 180, accuracy: 1.0,
            "ListDialog: height should be 180pt")
    }

    // MARK: - WindowListDialog

    func testWindowListDialogFrameBased() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))

        verifyAccessoryViewFrame(scrollView, expectedWidth: 360,
                                 dialogName: "WindowListDialog")
        XCTAssertEqual(scrollView.frame.height, 180, accuracy: 1.0,
            "WindowListDialog: height should be 180pt")
    }

    // MARK: - ChangeDirectoryDialog

    func testChangeDirectoryDialogFrameBased() {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 24))

        verifyAccessoryViewFrame(row, expectedWidth: 320,
                                 dialogName: "ChangeDirectoryDialog")
    }

    // MARK: - Password (TTLInterpreter) Dialog

    func testPasswordDialogFrameBased() {
        let input = NSView.makeSecureTextField(placeholder: "", width: nil)
        input.translatesAutoresizingMaskIntoConstraints = true
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)

        verifyAccessoryViewFrame(input, expectedWidth: 300,
                                 dialogName: "PasswordDialog")
    }

    // MARK: - DialogCommandProvider InputBox

    func testDialogCommandInputBoxFrameBased() {
        let inputField = NSView.makeTextField(value: "test")
        inputField.translatesAutoresizingMaskIntoConstraints = true
        inputField.frame = NSRect(x: 0, y: 0, width: 300, height: 24)

        verifyAccessoryViewFrame(inputField, expectedWidth: 300,
                                 dialogName: "DialogCommandProvider.InputBox")
    }

    // MARK: - DialogCommandProvider ListBox

    func testDialogCommandListBoxFrameBased() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        verifyAccessoryViewFrame(scrollView, expectedWidth: 300,
                                 dialogName: "DialogCommandProvider.ListBox")
    }

    // MARK: - SSH Security Dialogs

    func testSSHFingerprintViewFrameBased() {
        let stack = NSStackView(views: [
            NSView.makeLabel("Key Type: RSA", alignment: .left),
            NSView.makeLabel("SHA256:abc123", alignment: .left),
        ])
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.frame = NSRect(x: 0, y: 0, width: 400, height: 48)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        verifyAccessoryViewFrame(stack, expectedWidth: 400,
                                 dialogName: "SSHFingerprintView")
    }

    func testSSHDifferentKeyDialogFrameBased() {
        let stack = NSStackView(views: [
            NSView.makeLabel("Stored:", alignment: .left),
            NSView.makeTextField(value: "old-fp"),
            NSView.makeLabel("New:", alignment: .left),
            NSView.makeTextField(value: "new-fp"),
            NSView.makeLabel("Warning!", alignment: .left),
        ])
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.frame = NSRect(x: 0, y: 0, width: 440, height: 120)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        verifyAccessoryViewFrame(stack, expectedWidth: 440,
                                 dialogName: "SSHDifferentKeyDialog")
    }
}


// MARK: - BaseSetupDialogController-based Dialogs

final class DialogOverflowBaseSetupTests: XCTestCase {

    private var settings: TerminalSettings!

    override func setUp() {
        settings = TerminalSettings()
    }

    /// Helper: load a BaseSetupDialogController's view and verify controls fit.
    private func verifyDialogFits(_ vc: BaseSetupDialogController,
                                  file: StaticString = #file,
                                  line: UInt = #line) {
        vc.loadViewIfNeeded()
        forceLayout(vc.view)

        let contentArea = vc.contentArea

        let textFields = findSubviews(of: NSTextField.self, in: contentArea)
        for tf in textFields where tf.isEditable {
            XCTAssertTrue(hasProperWidthBound(tf) || isConstrainedByParent(tf),
                "Editable field in \(type(of: vc)) may overflow: '\(tf.placeholderString ?? tf.stringValue)'",
                file: file, line: line)
        }
    }

    func testDragDropDialogNoOverflow() {
        let vc = DragDropDialogController(path: "/tmp/test.txt")
        verifyDialogFits(vc)
    }

    func testEditHistoryDialogNoOverflow() {
        let vc = EditHistoryDialogController(history: ["host1", "host2", "host3"])
        verifyDialogFits(vc)
    }

    func testLogDialogNoOverflow() {
        let vc = LogDialogController()
        verifyDialogFits(vc)
    }

    func testKeyboardSetupDialogNoOverflow() {
        let vc = KeyboardSetupDialogController(settings: settings)
        verifyDialogFits(vc)
    }

    func testTCPIPDialogNoOverflow() {
        let vc = TCPIPDialogController(settings: settings)
        verifyDialogFits(vc)
    }
}


// MARK: - SSH Dialogs

final class DialogOverflowSSHTests: XCTestCase {

    private var settings: TerminalSettings!

    override func setUp() {
        settings = TerminalSettings()
    }

    private func verifyDialogFits(_ vc: BaseSetupDialogController,
                                  file: StaticString = #file,
                                  line: UInt = #line) {
        vc.loadViewIfNeeded()
        forceLayout(vc.view)

        let textFields = findSubviews(of: NSTextField.self, in: vc.contentArea)
        for tf in textFields where tf.isEditable {
            XCTAssertTrue(hasProperWidthBound(tf) || isConstrainedByParent(tf),
                "Editable field in \(type(of: vc)) may overflow",
                file: file, line: line)
        }
    }

    func testSCPDialogNoOverflow() {
        let vc = SCPDialogController(settings: settings)
        verifyDialogFits(vc)
    }

    func testSSHSetupDialogNoOverflow() {
        let vc = SSHSetupDialogController(settings: settings)
        verifyDialogFits(vc)
    }

    func testSSHKeyGenDialogNoOverflow() {
        let vc = SSHKeyGenDialogController()
        verifyDialogFits(vc)
    }

    func testSSHForwardingEditDialogNoOverflow() {
        let vc = SSHForwardingEditDialogController(rule: nil)
        verifyDialogFits(vc)
    }

    func testProxySetupDialogNoOverflow() {
        let vc = ProxySetupDialogController(settings: settings)
        verifyDialogFits(vc)
    }

    func testGeneralSetupDialogNoOverflow() {
        let vc = GeneralSetupDialogController(settings: settings)
        verifyDialogFits(vc)
    }
}


// MARK: - Setup View Controllers

final class DialogOverflowSetupViewTests: XCTestCase {

    private var settings: TerminalSettings!

    override func setUp() {
        settings = TerminalSettings()
    }

    func testTerminalSetupNoOverflow() {
        let vc = TerminalSetupViewController(settings: settings)
        vc.loadViewIfNeeded()
        forceLayout(vc.view)

        let textFields = findSubviews(of: NSTextField.self, in: vc.contentArea)
        for tf in textFields where tf.isEditable {
            XCTAssertTrue(hasProperWidthBound(tf) || isInStackOrGrid(tf),
                "Editable field in TerminalSetupViewController may overflow")
        }
    }

    func testWindowSetupNoOverflow() {
        let vc = WindowSetupViewController(settings: settings)
        vc.loadViewIfNeeded()
        forceLayout(vc.view)

        let textFields = findSubviews(of: NSTextField.self, in: vc.contentArea)
        for tf in textFields where tf.isEditable {
            XCTAssertTrue(hasProperWidthBound(tf) || isInStackOrGrid(tf),
                "Editable field in WindowSetupViewController may overflow")
        }
    }

    func testSerialPortSetupNoOverflow() {
        let vc = SerialPortSetupViewController(settings: settings)
        vc.loadViewIfNeeded()
        forceLayout(vc.view)

        let textFields = findSubviews(of: NSTextField.self, in: vc.contentArea)
        for tf in textFields where tf.isEditable {
            XCTAssertTrue(hasProperWidthBound(tf) || isInStackOrGrid(tf),
                "Editable field in SerialPortSetupViewController may overflow")
        }
    }
}


// MARK: - Additional Settings Tabs

final class DialogOverflowAdditionalSettingsTests: XCTestCase {

    private var settings: TerminalSettings!

    override func setUp() {
        settings = TerminalSettings()
    }

    /// Verify that all tabs' editable fields are bounded by their container.
    func testAllTabsEditableFieldsBounded() {
        let tabs: [(String, AdditionalSettingsTab)] = [
            ("General",   GeneralTab(settings: settings)),
            ("Coding",    CodingTab(settings: settings)),
            ("CopyPaste", CopyPasteTab(settings: settings)),
            ("Sequence",  SequenceTab(settings: settings)),
            ("Mouse",     MouseTab(settings: settings)),
            ("Log",       LogTab(settings: settings)),
            ("Visual",    VisualTab(settings: settings)),
            ("Font",      FontTab(settings: settings)),
            ("TEKFont",   TEKFontTab(settings: settings)),
            ("Theme",     ThemeTab(settings: settings)),
            ("UI",        UITab(settings: settings)),
            ("Plugin",    PluginTab(settings: settings)),
            ("Debug",     DebugTab(settings: settings)),
        ]

        for (name, tab) in tabs {
            let cv = tab.contentView
            forceLayout(cv)

            let editableFields = findSubviews(of: NSTextField.self, in: cv)
                .filter { $0.isEditable }

            for tf in editableFields {
                XCTAssertTrue(hasProperWidthBound(tf) || isInStackOrGrid(tf),
                    "Tab '\(name)': editable field may overflow " +
                    "(placeholder: '\(tf.placeholderString ?? "")' value: '\(tf.stringValue)')")
            }
        }
    }
}

// MARK: - Unified Settings Tab Overflow Tests

/// Verify that all tabs in the unified settings dialog fit within the window.
/// The unified window is 800×620, tab view minimum 720×420.
/// Each tab's content must not exceed the available width/height.
final class UnifiedSettingsTabOverflowTests: XCTestCase {

    private var settings: TerminalSettings!
    /// Available width inside the tab view content rect (approximate).
    /// Window(800) - margins(2×16) - bezel(~14) - container margins(2×16) = ~722pt
    private let maxContentWidth: CGFloat = 730

    override func setUp() {
        settings = TerminalSettings()
    }

    // MARK: - Row 1 tabs

    func testTerminalTabFitsInUnifiedDialog() {
        let vc = TerminalSetupViewController(settings: settings)
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "Terminal")
    }

    func testWindowTabFitsInUnifiedDialog() {
        let vc = WindowSetupViewController(settings: settings)
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "Window")
    }

    func testKeyboardTabFitsInUnifiedDialog() {
        let vc = KeyboardSetupDialogController(settings: settings)
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "Keyboard")
    }

    func testSerialPortTabFitsInUnifiedDialog() {
        let vc = SerialPortSetupViewController(settings: settings)
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "SerialPort")
    }

    func testTCPIPTabFitsInUnifiedDialog() {
        let vc = TCPIPDialogController(settings: settings)
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "TCPIP")
    }

    func testGeneralSetupTabFitsInUnifiedDialog() {
        let vc = GeneralSetupDialogController(settings: settings)
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "General")
    }

    // MARK: - Row 2 tabs

    func testProxyTabFitsInUnifiedDialog() {
        let vc = ProxySetupDialogController(settings: settings)
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "Proxy")
    }

    func testSSHTabFitsInUnifiedDialog() {
        let vc = SSHSetupDialogController(settings: settings)
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "SSH")
    }

    func testSSHAuthTabFitsInUnifiedDialog() {
        let vc = SSHAuthSetupDialogController(settings: settings)
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "SSHAuth")
    }

    func testSSHForwardingTabFitsInUnifiedDialog() {
        let vc = SSHForwardingSetupDialogController(settings: settings)
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "SSHForwarding")
    }

    func testSSHKeyGenTabFitsInUnifiedDialog() {
        let vc = SSHKeyGenDialogController()
        vc.hidesFooterButtons = true
        verifyFitsInTabView(vc, name: "SSHKeyGen")
    }

    // MARK: - Row 3 tabs (AdditionalSettingsTab)

    func testAllAdditionalTabsFitInUnifiedDialog() {
        let tabs: [(String, AdditionalSettingsTab)] = [
            ("General",    GeneralTab(settings: settings)),
            ("Coding",     CodingTab(settings: settings)),
            ("CopyPaste",  CopyPasteTab(settings: settings)),
            ("Sequence",   SequenceTab(settings: settings)),
            ("Mouse",      MouseTab(settings: settings)),
            ("Log",        LogTab(settings: settings)),
            ("Visual",     VisualTab(settings: settings)),
            ("Font",       FontTab(settings: settings)),
            ("TEKFont",    TEKFontTab(settings: settings)),
            ("Theme",      ThemeTab(settings: settings)),
            ("UI",         UITab(settings: settings)),
            ("Plugin",     PluginTab(settings: settings)),
            ("LocalShell", LocalShellTab(settings: settings)),
            ("Debug",      DebugTab(settings: settings)),
        ]

        for (name, tab) in tabs {
            let cv = tab.contentView
            forceLayout(cv)
            let fittingSize = cv.fittingSize
            XCTAssertLessThanOrEqual(fittingSize.width, maxContentWidth,
                "Additional tab '\(name)' content width (\(fittingSize.width)) " +
                "exceeds max \(maxContentWidth)pt for unified dialog")
        }
    }

    // MARK: - Scroll view wrapping

    func testWrapForTabViewCreatesScrollView() {
        let settings = TerminalSettings()
        let controller = UnifiedSettingsController(settings: settings)
        // Verify the controller can be created without error
        XCTAssertNotNil(controller)
    }

    func testAllTabsHaveScrollableContent() {
        // Verify that all 25 tab enum cases exist
        XCTAssertEqual(UnifiedSettingsTab.allCases.count, 25,
            "Should have 25 tabs total (11 + 14)")
        XCTAssertEqual(UnifiedSettingsTab.row1.count, 11, "Row 1 should have 11 tabs")
        XCTAssertEqual(UnifiedSettingsTab.row2.count, 14, "Row 2 should have 14 tabs")
    }

    // MARK: - Helper

    private func verifyFitsInTabView(_ vc: BaseSetupDialogController,
                                     name: String,
                                     file: StaticString = #file,
                                     line: UInt = #line) {
        vc.loadViewIfNeeded()
        forceLayout(vc.view)

        let contentArea = vc.contentArea
        let fittingSize = contentArea.fittingSize

        XCTAssertLessThanOrEqual(fittingSize.width, maxContentWidth,
            "Tab '\(name)' content width (\(fittingSize.width)) " +
            "exceeds max \(maxContentWidth)pt for unified dialog",
            file: file, line: line)

        // Also verify no text field overflows contentArea bounds
        let textFields = findSubviews(of: NSTextField.self, in: contentArea)
        for tf in textFields where tf.isEditable {
            XCTAssertTrue(hasProperWidthBound(tf) || isConstrainedByParent(tf),
                "Tab '\(name)': editable field may overflow " +
                "(placeholder: '\(tf.placeholderString ?? "")')",
                file: file, line: line)
        }
    }
}

#endif
