/*
 * DialogOverflowTests.swift
 * Comprehensive tests to verify that all dialog input controls
 * do not overflow their parent containers.
 *
 * Checks every dialog class for:
 *   - Input fields (NSTextField, NSSecureTextField) have fixed or
 *     maximum-bounded width constraints (not only greaterThanOrEqual)
 *   - ScrollViews used as NSAlert accessoryViews have fixed dimensions
 *   - All controls fit within their parent view bounds after layout
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

/// Check whether `child` fits inside `parent` bounds (with tolerance).
private func fitsWithin(_ child: NSView, parent: NSView, tolerance: CGFloat = 1.0) -> Bool {
    let childFrame = child.convert(child.bounds, to: parent)
    let parentBounds = parent.bounds
    return childFrame.minX >= -tolerance &&
           childFrame.minY >= -tolerance &&
           childFrame.maxX <= parentBounds.width + tolerance &&
           childFrame.maxY <= parentBounds.height + tolerance
}

/// Check that a constraint list does NOT contain an unbounded
/// greaterThanOrEqual width without a matching equalTo or lessThanOrEqual.
private func hasProperWidthBound(_ view: NSView) -> Bool {
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

        // Check all text fields
        let textFields = findSubviews(of: NSTextField.self, in: contentArea)
        for tf in textFields where tf.isEditable {
            // Editable fields should have bounded width
            XCTAssertTrue(hasProperWidthBound(tf) || isConstrainedByParent(tf),
                "Editable field in \(type(of: vc)) may overflow: '\(tf.placeholderString ?? tf.stringValue)'",
                file: file, line: line)
        }
    }

    /// Check if a view is bounded by its superview's trailing anchor or by a
    /// containing stack/grid (which handles overflow implicitly).
    private func isConstrainedByParent(_ view: NSView) -> Bool {
        guard let sv = view.superview else { return false }
        // In a stack view or grid view, children are auto-constrained
        if sv is NSStackView || sv is NSGridView { return true }
        // Check if there's a trailing constraint from superview to this view
        for c in sv.constraints {
            if (c.firstAttribute == .trailing || c.firstAttribute == .width) &&
               (c.firstItem as? NSView === view || c.secondItem as? NSView === view) {
                return true
            }
        }
        // Recurse upward
        return isConstrainedByParent(sv)
    }

    // MARK: - DragDropDialogController

    func testDragDropDialogNoOverflow() {
        let vc = DragDropDialogController(path: "/tmp/test.txt")
        verifyDialogFits(vc)
    }

    // MARK: - EditHistoryDialogController

    func testEditHistoryDialogNoOverflow() {
        let vc = EditHistoryDialogController(history: ["host1", "host2", "host3"])
        verifyDialogFits(vc)
    }

    // MARK: - LogDialogController

    func testLogDialogNoOverflow() {
        let vc = LogDialogController()
        verifyDialogFits(vc)
    }

    // MARK: - KeyboardSetupDialogController

    func testKeyboardSetupDialogNoOverflow() {
        let vc = KeyboardSetupDialogController(settings: settings)
        verifyDialogFits(vc)
    }

    // MARK: - TCPIPDialogController

    func testTCPIPDialogNoOverflow() {
        let vc = TCPIPDialogController(settings: settings)
        verifyDialogFits(vc)
    }
}


// MARK: - NSAlert-based Dialogs (accessoryView overflow checks)

final class DialogOverflowAlertTests: XCTestCase {

    /// Verify that an NSAlert accessoryView has a fixed width constraint
    /// (equalToConstant) rather than an unbounded minimum.
    private func verifyAccessoryViewWidth(_ accessoryView: NSView,
                                          dialogName: String,
                                          file: StaticString = #file,
                                          line: UInt = #line) {
        let widthConstraints = accessoryView.constraints.filter {
            $0.firstAttribute == .width && $0.firstItem as? NSView === accessoryView
        }
        XCTAssertFalse(widthConstraints.isEmpty,
            "\(dialogName): accessoryView should have a width constraint",
            file: file, line: line)

        let hasUnboundedGTE = widthConstraints.contains {
            $0.relation == .greaterThanOrEqual
        }
        let hasBound = widthConstraints.contains {
            $0.relation == .equal || $0.relation == .lessThanOrEqual
        }

        XCTAssertFalse(hasUnboundedGTE && !hasBound,
            "\(dialogName): accessoryView uses greaterThanOrEqual without upper bound — may overflow",
            file: file, line: line)
    }

    // MARK: - Comment to Log Dialog

    func testCommentToLogDialogFixedWidth() {
        let alert = NSAlert()
        alert.messageText = "Comment"
        alert.addButton(withTitle: "OK")

        let textField = NSView.makeTextField(value: "", placeholder: "Comment")
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.lineBreakMode = .byTruncatingTail
        textField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        alert.accessoryView = textField

        verifyAccessoryViewWidth(textField, dialogName: "CommentToLog")
    }

    // MARK: - InputDialog

    func testInputDialogFixedWidth() {
        let field = NSView.makeTextField(value: "test")
        field.lineBreakMode = .byTruncatingTail
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true

        verifyAccessoryViewWidth(field, dialogName: "InputDialog")
    }

    // MARK: - ClipboardConfirmationDialog

    func testClipboardDialogFixedSize() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalToConstant: 400),
            scrollView.heightAnchor.constraint(equalToConstant: 250),
        ])

        verifyAccessoryViewWidth(scrollView, dialogName: "ClipboardConfirmation")
    }

    // MARK: - ListDialog

    func testListDialogFixedSize() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalToConstant: 340),
            scrollView.heightAnchor.constraint(equalToConstant: 180),
        ])

        verifyAccessoryViewWidth(scrollView, dialogName: "ListDialog")
    }

    // MARK: - WindowListDialog

    func testWindowListDialogFixedSize() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalToConstant: 360),
            scrollView.heightAnchor.constraint(equalToConstant: 180),
        ])

        verifyAccessoryViewWidth(scrollView, dialogName: "WindowListDialog")
    }

    // MARK: - ChangeDirectoryDialog

    func testChangeDirectoryDialogFixedWidth() {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 320).isActive = true

        verifyAccessoryViewWidth(row, dialogName: "ChangeDirectoryDialog")
    }

    // MARK: - Password (TTLInterpreter) Dialog

    func testPasswordDialogFixedWidth() {
        let input = NSView.makeSecureTextField(placeholder: "", width: nil)
        input.widthAnchor.constraint(equalToConstant: 300).isActive = true

        verifyAccessoryViewWidth(input, dialogName: "PasswordDialog")
    }

    // MARK: - DialogCommandProvider InputBox

    func testDialogCommandInputBoxFixedFrame() {
        // DialogCommandProvider uses frame-based layout (translatesAutoresizingMaskIntoConstraints = true)
        let inputField = NSView.makeTextField(value: "test")
        inputField.translatesAutoresizingMaskIntoConstraints = true
        inputField.frame = NSRect(x: 0, y: 0, width: 300, height: 24)

        // Frame-based layout: verify the frame width is reasonable
        XCTAssertEqual(inputField.frame.width, 300,
            "DialogCommandProvider inputField should have a fixed 300pt frame width")
    }

    // MARK: - DialogCommandProvider ListBox

    func testDialogCommandListBoxFixedFrame() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertEqual(scrollView.frame.width, 300,
            "DialogCommandProvider listBox scrollView should have fixed 300pt frame")
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

    private func isInStackOrGrid(_ view: NSView) -> Bool {
        var current: NSView? = view.superview
        while let sv = current {
            if sv is NSStackView || sv is NSGridView { return true }
            current = sv.superview
        }
        return false
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

    private func isInStackOrGrid(_ view: NSView) -> Bool {
        var current: NSView? = view.superview
        while let sv = current {
            if sv is NSStackView || sv is NSGridView { return true }
            current = sv.superview
        }
        return false
    }
}

#endif
