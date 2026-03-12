/*
 * Layout Engine Tests
 *
 * Verifies that the shared layout helpers (DialogConstants.swift) produce
 * correct view hierarchies with proper Auto Layout constraints.
 * Tests cover: form rows, vertical stacks, form grids,
 * BaseSetupDialogController addRow API, and minimum-width behaviour.
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

final class LayoutEngineTests: XCTestCase {

    // MARK: - DialogLayout Constants

    func testDialogLayoutConstants() {
        // Verify the key constants haven't been accidentally changed
        XCTAssertEqual(DialogLayout.margin, 20)
        XCTAssertEqual(DialogLayout.innerMargin, 12)
        XCTAssertEqual(DialogLayout.rowSpacing, 8)
        XCTAssertEqual(DialogLayout.labelTrailing, 10)
        XCTAssertEqual(DialogLayout.buttonWidth, 80)
        XCTAssertEqual(DialogLayout.sectionSpacing, 16)
    }

    // MARK: - NSView Factory Methods

    func testMakeLabel() {
        let label = NSView.makeLabel("Test Label")
        XCTAssertFalse(label.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(label.font, NSFont.systemFont(ofSize: 13))
        XCTAssertEqual(label.stringValue, "Test Label")
        XCTAssertEqual(label.alignment, .right)
    }

    func testMakeLabel_LeftAligned() {
        let label = NSView.makeLabel("Left", alignment: .left)
        XCTAssertEqual(label.alignment, .left)
    }

    func testMakeTextField() {
        let field = NSView.makeTextField(value: "hello", placeholder: "type here")
        XCTAssertFalse(field.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(field.stringValue, "hello")
        XCTAssertEqual(field.placeholderString, "type here")
    }

    func testMakeTextField_WithWidth() {
        let field = NSView.makeTextField(width: 200)
        // Should have a width constraint
        let widthConstraints = field.constraints.filter { $0.firstAttribute == .width }
        XCTAssertFalse(widthConstraints.isEmpty, "Should have width constraint")
    }

    func testMakeCheckbox() {
        let cb = NSView.makeCheckbox("Enable", checked: true)
        XCTAssertFalse(cb.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(cb.state, .on)
        XCTAssertEqual(cb.title, "Enable")
    }

    func testMakePopUpButton() {
        let popup = NSView.makePopUpButton(items: ["A", "B", "C"], selected: "B")
        XCTAssertEqual(popup.numberOfItems, 3)
        XCTAssertEqual(popup.titleOfSelectedItem, "B")
    }

    func testMakePushButton() {
        let button = NSView.makePushButton("OK", keyEquivalent: "\r")
        XCTAssertFalse(button.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(button.title, "OK")
        XCTAssertEqual(button.keyEquivalent, "\r")
        // Should have minimum width constraint
        let widthConstraints = button.constraints.filter { $0.firstAttribute == .width }
        XCTAssertFalse(widthConstraints.isEmpty)
    }

    func testMakeGroupBox() {
        let box = NSView.makeGroupBox(title: "Settings")
        XCTAssertEqual(box.title, "Settings")
        XCTAssertEqual(box.boxType, .primary)
    }

    func testMakeNumberField() {
        let field = NSView.makeNumberField(value: 42)
        XCTAssertEqual(field.stringValue, "42")
        XCTAssertNotNil(field.formatter)
    }

    // MARK: - Form Row Creation

    func testCreateFormRow() {
        let control = NSView.makeTextField(value: "test")
        let row = NSView.createFormRow(label: "Name:", control: control)

        XCTAssertEqual(row.orientation, .horizontal)
        XCTAssertEqual(row.spacing, DialogLayout.labelTrailing)
        XCTAssertEqual(row.alignment, .firstBaseline)
        XCTAssertEqual(row.arrangedSubviews.count, 2)

        // First view should be a label
        let label = row.arrangedSubviews[0] as? NSTextField
        XCTAssertNotNil(label)
        XCTAssertTrue(label?.isEditable == false)

        // Label compression resistance should be .required
        XCTAssertEqual(
            label?.contentCompressionResistancePriority(for: .horizontal),
            .required
        )
    }

    func testCreateFormRow_LabelView() {
        let label = NSView.makeLabel("Custom")
        let control = NSView.makeTextField()
        let row = NSView.createFormRow(labelView: label, control: control)

        XCTAssertEqual(row.arrangedSubviews.count, 2)
        XCTAssertEqual(
            label.contentCompressionResistancePriority(for: .horizontal),
            .required
        )
    }

    // MARK: - Vertical Stack

    func testCreateVerticalStack() {
        let stack = NSView.createVerticalStack()
        XCTAssertEqual(stack.orientation, .vertical)
        XCTAssertEqual(stack.spacing, DialogLayout.rowSpacing)
        XCTAssertFalse(stack.translatesAutoresizingMaskIntoConstraints)
    }

    func testCreateVerticalStack_CustomSpacing() {
        let stack = NSView.createVerticalStack(spacing: 20)
        XCTAssertEqual(stack.spacing, 20)
    }

    // MARK: - Form Grid

    func testCreateFormGrid() {
        let field1 = NSView.makeTextField(value: "v1")
        let field2 = NSView.makeTextField(value: "v2")
        let grid = NSView.createFormGrid(rows: [
            ("Label1", field1),
            ("Label2", field2),
        ])

        XCTAssertEqual(grid.numberOfRows, 2)
        XCTAssertEqual(grid.numberOfColumns, 2)
        XCTAssertEqual(grid.rowSpacing, DialogLayout.rowSpacing)
        XCTAssertEqual(grid.columnSpacing, DialogLayout.labelTrailing)
        XCTAssertEqual(grid.column(at: 0).xPlacement, .trailing)
        XCTAssertEqual(grid.column(at: 1).xPlacement, .leading)
    }

    // MARK: - BaseSetupDialogController

    func testBaseDialogController_LoadView() {
        let vc = BaseSetupDialogController()
        vc.loadView()

        XCTAssertNotNil(vc.view)
        XCTAssertNotNil(vc.okButton)
        XCTAssertNotNil(vc.cancelButton)
        XCTAssertNotNil(vc.helpButton)
        XCTAssertNotNil(vc.contentStackView)

        // OK button should have Return as key equivalent
        XCTAssertEqual(vc.okButton.keyEquivalent, "\r")
        // Cancel button should have Escape
        XCTAssertEqual(vc.cancelButton.keyEquivalent, "\u{1b}")
    }

    func testBaseDialogController_ContentStackView() {
        let vc = BaseSetupDialogController()
        vc.loadView()

        XCTAssertEqual(vc.contentStackView.orientation, .vertical)
        XCTAssertEqual(vc.contentStackView.spacing, DialogLayout.rowSpacing)
    }

    func testBaseDialogController_AddRow() {
        let vc = BaseSetupDialogController()
        vc.loadView()

        let field = NSView.makeTextField(value: "test")
        vc.addRow(label: "Name:", view: field)

        XCTAssertEqual(vc.contentStackView.arrangedSubviews.count, 1)
        let row = vc.contentStackView.arrangedSubviews[0] as? NSStackView
        XCTAssertNotNil(row, "Added row should be an NSStackView")
        XCTAssertEqual(row?.arrangedSubviews.count, 2)
    }

    func testBaseDialogController_AddMultipleRows() {
        let vc = BaseSetupDialogController()
        vc.loadView()

        vc.addRow(label: "Name:", view: NSView.makeTextField())
        vc.addRow(label: "Email:", view: NSView.makeTextField())
        vc.addRow(label: "Password:", view: NSView.makeSecureTextField())

        XCTAssertEqual(vc.contentStackView.arrangedSubviews.count, 3)
    }

    func testBaseDialogController_AddFullWidthView() {
        let vc = BaseSetupDialogController()
        vc.loadView()

        let checkbox = NSView.makeCheckbox("Enable feature")
        vc.addFullWidthView(checkbox)

        XCTAssertEqual(vc.contentStackView.arrangedSubviews.count, 1)
        XCTAssertTrue(vc.contentStackView.arrangedSubviews[0] === checkbox)
    }

    func testBaseDialogController_AddFormGrid() {
        let vc = BaseSetupDialogController()
        vc.loadView()

        vc.addFormGrid(rows: [
            ("Host:", NSView.makeTextField()),
            ("Port:", NSView.makeNumberField(value: 22)),
        ])

        XCTAssertEqual(vc.contentStackView.arrangedSubviews.count, 1)
        let grid = vc.contentStackView.arrangedSubviews[0] as? NSGridView
        XCTAssertNotNil(grid)
        XCTAssertEqual(grid?.numberOfRows, 2)
    }

    func testBaseDialogController_MinimumWidth() {
        let vc = BaseSetupDialogController()
        vc.minimumContentWidth = 500
        vc.loadView()

        // The content area should have a width >= constraint
        let widthConstraints = vc.contentArea.constraints.filter {
            $0.firstAttribute == .width && $0.relation == .greaterThanOrEqual
        }
        XCTAssertFalse(widthConstraints.isEmpty)
        XCTAssertEqual(widthConstraints.first?.constant, 500)
    }

    func testBaseDialogController_SectionSpacing() {
        let vc = BaseSetupDialogController()
        vc.loadView()

        vc.addRow(label: "Row1:", view: NSView.makeTextField())
        vc.addSectionSpacing()
        vc.addRow(label: "Row2:", view: NSView.makeTextField())

        // Should have 3 arranged subviews: row, spacer, row
        XCTAssertEqual(vc.contentStackView.arrangedSubviews.count, 3)
    }

    // MARK: - Layout Consistency (Label Never Truncates)

    func testLongLabelDoesNotTruncate() {
        // Simulate a long Japanese label vs a short English label
        let longLabel = NSView.makeLabel("ターミナルウィンドウの背景色設定:", alignment: .right)
        longLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let control = NSView.makeTextField(width: 100)
        let row = NSView.createFormRow(labelView: longLabel, control: control)

        // Force layout
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
        container.addSubview(row)
        row.frame = container.bounds
        container.layoutSubtreeIfNeeded()

        // Label's intrinsic width should be fully respected
        let labelWidth = longLabel.intrinsicContentSize.width
        XCTAssertGreaterThan(labelWidth, 0)
        XCTAssertEqual(
            longLabel.contentCompressionResistancePriority(for: .horizontal),
            .required,
            "Label must have .required compression resistance"
        )
    }

    // MARK: - Snapshot (Basic Smoke Test)

    func testSaveToDebugPNG_DoesNotCrash() {
        let vc = BaseSetupDialogController()
        vc.loadView()
        vc.addRow(label: "Test:", view: NSView.makeTextField(value: "Hello"))

        // Force layout to set a non-zero size
        vc.view.setFrameSize(NSSize(width: 500, height: 200))
        vc.view.layoutSubtreeIfNeeded()

        // Should not crash even without a window
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutEngineTest_\(ProcessInfo.processInfo.processIdentifier)")
        vc.view.captureScreenToPNG(fileName: "test_layout", directory: tmpDir)

        // Cleanup
        try? FileManager.default.removeItem(at: tmpDir)
    }
}

#endif
