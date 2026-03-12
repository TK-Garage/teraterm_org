/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * Common constants and helpers for setup dialogs.
 * Layout values are chosen to reproduce the control spacing from
 * Tera Term 5.6 while respecting macOS HIG.
 */

#if canImport(AppKit)
import AppKit

// MARK: - Dialog Layout Constants

enum DialogLayout {
    // Standard macOS dialog margins
    static let margin: CGFloat = 20
    static let innerMargin: CGFloat = 12

    // Standard control sizes
    static let buttonWidth: CGFloat = 80
    static let buttonHeight: CGFloat = 24
    static let buttonSpacing: CGFloat = 8
    static let textFieldHeight: CGFloat = 22
    static let popupHeight: CGFloat = 24
    static let checkboxHeight: CGFloat = 18
    static let radioHeight: CGFloat = 18
    static let labelHeight: CGFloat = 17
    static let colorWellSize: CGFloat = 28
    static let sliderHeight: CGFloat = 22

    // Group box
    static let groupBoxPadding: CGFloat = 14
    static let groupBoxTopPadding: CGFloat = 20

    // Row spacing
    static let rowSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 16

    // Label-to-control spacing (>= 10pt for macOS HIG)
    static let labelTrailing: CGFloat = 10

    // Standard input width
    static let popupWidth: CGFloat = 160
    static let narrowFieldWidth: CGFloat = 60
    static let wideFieldWidth: CGFloat = 200
}

// MARK: - Localization Helper

func TTL(_ key: String) -> String {
    #if SWIFT_PACKAGE
    return NSLocalizedString(key, bundle: Bundle.module, comment: "")
    #else
    return NSLocalizedString(key, bundle: Bundle.main, comment: "")
    #endif
}

func TTL(_ key: String, _ args: CVarArg...) -> String {
    let fmt = TTL(key)
    return String(format: fmt, arguments: args)
}

// MARK: - NSView Auto Layout Helpers

extension NSView {
    /// Create a standard label (NSTextField as static text).
    static func makeLabel(_ text: String, alignment: NSTextAlignment = .right) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = alignment
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return label
    }

    /// Create a standard editable text field.
    static func makeTextField(value: String = "", placeholder: String = "", width: CGFloat? = nil) -> NSTextField {
        let field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.stringValue = value
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        if let w = width {
            field.widthAnchor.constraint(equalToConstant: w).isActive = true
        }
        return field
    }

    /// Create a secure (password) text field.
    static func makeSecureTextField(placeholder: String = "", width: CGFloat? = nil) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        if let w = width {
            field.widthAnchor.constraint(equalToConstant: w).isActive = true
        }
        return field
    }

    /// Create a number-only text field.
    static func makeNumberField(value: Int, width: CGFloat = DialogLayout.narrowFieldWidth) -> NSTextField {
        let field = makeTextField(value: "\(value)", width: width)
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        field.formatter = formatter
        return field
    }

    /// Create an NSPopUpButton.
    static func makePopUpButton(items: [String], selected: String? = nil, width: CGFloat? = nil) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.font = NSFont.systemFont(ofSize: 13)
        for item in items {
            popup.addItem(withTitle: item)
        }
        if let sel = selected {
            popup.selectItem(withTitle: sel)
        }
        if let w = width {
            popup.widthAnchor.constraint(equalToConstant: w).isActive = true
        }
        return popup
    }

    /// Create a checkbox NSButton.
    static func makeCheckbox(_ title: String, checked: Bool = false) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.font = NSFont.systemFont(ofSize: 13)
        button.state = checked ? .on : .off
        return button
    }

    /// Create a radio NSButton.
    static func makeRadioButton(_ title: String, tag: Int = 0) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.font = NSFont.systemFont(ofSize: 13)
        button.tag = tag
        return button
    }

    /// Create a standard push button (OK, Cancel, Help).
    static func makePushButton(_ title: String, keyEquivalent: String = "") -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 13)
        button.keyEquivalent = keyEquivalent
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: DialogLayout.buttonWidth).isActive = true
        return button
    }

    /// Create a titled NSBox (group box).
    static func makeGroupBox(title: String) -> NSBox {
        let box = NSBox()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.boxType = .primary
        box.titlePosition = .atTop
        box.title = title
        box.titleFont = NSFont.systemFont(ofSize: 13)
        return box
    }

    /// Create an NSColorWell.
    static func makeColorWell(color: NSColor) -> NSColorWell {
        let well = NSColorWell()
        well.translatesAutoresizingMaskIntoConstraints = false
        well.color = color
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: DialogLayout.colorWellSize),
            well.heightAnchor.constraint(equalToConstant: DialogLayout.colorWellSize),
        ])
        return well
    }

    /// Create an NSSlider.
    static func makeSlider(min: Double, max: Double, value: Double) -> NSSlider {
        let slider = NSSlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = value
        slider.isContinuous = true
        return slider
    }
}

// MARK: - Form Layout Helpers

extension NSView {

    /// Create a horizontal form row: right-aligned label + control.
    ///
    /// The label's compression resistance is raised so it never truncates,
    /// while the control is allowed to stretch.  Both views are aligned
    /// on `.firstBaseline` so text lines up even when font sizes differ
    /// slightly (e.g. label vs popup button).
    ///
    /// - Parameters:
    ///   - label: The label text (will be localized with `TTL()`).
    ///   - control: Any NSView to place next to the label.
    /// - Returns: A horizontal `NSStackView` containing the pair.
    static func createFormRow(label text: String, control: NSView) -> NSStackView {
        let label = NSView.makeLabel(TTL(text), alignment: .right)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [label, control])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = DialogLayout.labelTrailing
        row.alignment = .firstBaseline
        row.distribution = .fill
        return row
    }

    /// Create a horizontal form row from a pre-made label + control.
    static func createFormRow(labelView: NSTextField, control: NSView) -> NSStackView {
        labelView.setContentCompressionResistancePriority(.required, for: .horizontal)
        labelView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [labelView, control])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = DialogLayout.labelTrailing
        row.alignment = .firstBaseline
        row.distribution = .fill
        return row
    }

    /// Create a vertical stack view with standard row spacing,
    /// suitable for stacking multiple form rows.
    static func createVerticalStack(
        spacing: CGFloat = DialogLayout.rowSpacing,
        alignment: NSLayoutConstraint.Attribute = .leading
    ) -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = alignment
        stack.spacing = spacing
        stack.distribution = .fill
        return stack
    }

    /// Create a 2-column NSGridView from label-control pairs.
    ///
    /// Labels are right-aligned, controls left-aligned, with consistent
    /// spacing.  Use this when multiple rows need vertically aligned
    /// columns (e.g. settings forms where labels line up).
    ///
    /// - Parameter rows: Array of `(labelKey, control)` pairs.
    /// - Returns: A configured `NSGridView`.
    static func createFormGrid(rows: [(String, NSView)]) -> NSGridView {
        let gridRows: [[NSView]] = rows.map { (labelKey, control) in
            let label = NSView.makeLabel(TTL(labelKey), alignment: .right)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            control.translatesAutoresizingMaskIntoConstraints = false
            return [label, control]
        }
        let grid = NSGridView(views: gridRows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = DialogLayout.rowSpacing
        grid.columnSpacing = DialogLayout.labelTrailing
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        for i in 0..<grid.numberOfRows {
            grid.row(at: i).rowAlignment = .firstBaseline
        }
        return grid
    }
}

// MARK: - Base Dialog ViewController

class BaseSetupDialogController: NSViewController {
    var okHandler: (() -> Void)?
    var cancelHandler: (() -> Void)?

    // Standard footer buttons
    private(set) var okButton: NSButton!
    private(set) var cancelButton: NSButton!
    private(set) var helpButton: NSButton!

    /// The content area above the buttons. Subclasses add controls here.
    let contentArea = NSView()

    /// Vertical stack view that fills the content area.
    /// Subclasses can call `addRow(label:view:)` or add views directly.
    private(set) var contentStackView: NSStackView!

    /// Minimum width for the dialog content area (auto-expands if labels
    /// are longer in another language).
    var minimumContentWidth: CGFloat = 400
    private var contentWidthConstraint: NSLayoutConstraint?

    // MARK: - Convenience: Add Form Row

    /// Add a labelled form row to the content stack.
    ///
    /// The label is right-aligned with max compression resistance so it
    /// never truncates.  The control stretches to fill remaining width.
    /// This is the primary API for subclasses building form-style dialogs.
    ///
    /// - Parameters:
    ///   - labelKey: Localization key (passed through `TTL()`).
    ///   - view: The control placed next to the label.
    func addRow(label labelKey: String, view control: NSView) {
        let row = NSView.createFormRow(label: labelKey, control: control)
        row.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
        contentStackView.addArrangedSubview(row)
    }

    /// Add a pre-built view (e.g. a checkbox, group box, separator) that
    /// spans the full width of the content area.
    func addFullWidthView(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStackView.widthAnchor).isActive = true
    }

    /// Add a vertical section gap.
    func addSectionSpacing() {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: DialogLayout.sectionSpacing - DialogLayout.rowSpacing).isActive = true
        contentStackView.addArrangedSubview(spacer)
    }

    /// Add a 2-column grid form from label-control pairs (for aligned columns).
    func addFormGrid(rows: [(String, NSView)]) {
        let grid = NSView.createFormGrid(rows: rows)
        contentStackView.addArrangedSubview(grid)
    }

    // MARK: - View Lifecycle

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        contentArea.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentArea)

        // Build the content stack view inside the content area
        contentStackView = NSView.createVerticalStack(
            spacing: DialogLayout.rowSpacing,
            alignment: .leading
        )
        contentArea.addSubview(contentStackView)
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: contentArea.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])

        // Minimum width — expands automatically if labels are wider
        let wc = contentArea.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumContentWidth)
        wc.priority = .defaultHigh
        wc.isActive = true
        contentWidthConstraint = wc

        // Footer buttons: [Help] ---- [Cancel] [OK]
        okButton = NSView.makePushButton(TTL("OK"), keyEquivalent: "\r")
        okButton.target = self
        okButton.action = #selector(okAction(_:))

        cancelButton = NSView.makePushButton(TTL("Cancel"), keyEquivalent: "\u{1b}")
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction(_:))

        helpButton = NSView.makePushButton(TTL("Help"))
        helpButton.target = self
        helpButton.action = #selector(helpAction(_:))

        container.addSubview(okButton)
        container.addSubview(cancelButton)
        container.addSubview(helpButton)

        // Separator line
        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        container.addSubview(separator)

        let m = DialogLayout.margin
        let bs = DialogLayout.buttonSpacing

        NSLayoutConstraint.activate([
            // Content area
            contentArea.topAnchor.constraint(equalTo: container.topAnchor, constant: m),
            contentArea.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
            contentArea.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),

            // Separator
            separator.topAnchor.constraint(equalTo: contentArea.bottomAnchor, constant: m),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Buttons row
            okButton.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: m * 0.75),
            okButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),
            okButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m * 0.75),

            cancelButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: okButton.leadingAnchor, constant: -bs),

            helpButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),
            helpButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
        ])

        self.view = container
    }

    /// Present this dialog as a modal sheet on the given window.
    /// Returns the dialog window for tracking purposes.
    @discardableResult
    func presentAsSheet(on parentWindow: NSWindow) -> NSWindow {
        let dialogWindow = NSWindow(contentViewController: self)
        dialogWindow.styleMask = [.titled, .closable]
        dialogWindow.title = self.title ?? ""
        dialogWindow.isReleasedWhenClosed = false
        // Fixed size — not resizable
        dialogWindow.styleMask.remove(.resizable)

        parentWindow.beginSheet(dialogWindow) { [weak self] response in
            if response == .OK {
                self?.okHandler?()
            } else {
                self?.cancelHandler?()
            }
        }
        return dialogWindow
    }

    /// Present as application-modal dialog (when no parent window).
    func presentModal() -> NSApplication.ModalResponse {
        let dialogWindow = NSWindow(contentViewController: self)
        dialogWindow.styleMask = [.titled, .closable]
        dialogWindow.title = self.title ?? ""
        dialogWindow.isReleasedWhenClosed = false
        dialogWindow.styleMask.remove(.resizable)
        dialogWindow.center()
        return NSApplication.shared.runModal(for: dialogWindow)
    }

    @objc private func okAction(_ sender: Any?) {
        applySettings()
        if let sheet = view.window, let parent = sheet.sheetParent {
            parent.endSheet(sheet, returnCode: .OK)
        } else if let window = view.window {
            NSApplication.shared.stopModal(withCode: .OK)
            window.close()
        }
    }

    @objc private func cancelAction(_ sender: Any?) {
        if let sheet = view.window, let parent = sheet.sheetParent {
            parent.endSheet(sheet, returnCode: .cancel)
        } else if let window = view.window {
            NSApplication.shared.stopModal(withCode: .cancel)
            window.close()
        }
    }

    @objc func helpAction(_ sender: Any?) {
        if let url = URL(string: "https://teratermproject.github.io/") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Override in subclass to apply UI values to settings.
    func applySettings() {}
}
#endif
