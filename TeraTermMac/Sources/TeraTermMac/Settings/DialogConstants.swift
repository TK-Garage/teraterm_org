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
    static let buttonWidth: CGFloat = 72
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

/// ローカライズ用バンドルを main.swift と同一ロジックで決定する。
///
/// 問題: Bundle.preferredLocalizations は実行時に UserDefaults へ書き込んだ
/// AppleLanguages を反映しない（次回起動まで効かない）。そのため初回起動時に
/// システム言語（英語等）が選ばれ、日本語表示されないケースがあった。
///
/// 修正: TeraTermUILanguage 設定値を直接読み、対応する .lproj バンドルを
/// 明示的にロードする。"Auto" 時のみシステム言語に従う。
private let _localizedBundle: Bundle = {
    #if SWIFT_PACKAGE
    let module = Bundle.module
    #else
    let module = Bundle.main
    #endif

    // main.swift と同一ロジックで言語コードを決定
    let savedLanguage = UserDefaults.standard.string(forKey: "TeraTermUILanguage") ?? "Japanese"
    let langCode: String
    switch savedLanguage {
    case "Auto":
        // システム言語に従う
        let preferredLangs = Bundle.preferredLocalizations(from: module.localizations)
        langCode = preferredLangs.first ?? "ja"
    case "English":
        langCode = "en"
    default:
        // "Japanese" およびその他 → 日本語
        langCode = "ja"
    }

    if let path = module.path(forResource: langCode, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle
    }

    // フォールバック: 日本語バンドルを直接試行
    if let path = module.path(forResource: "ja", ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle
    }

    return module
}()

func TTL(_ key: String) -> String {
    return NSLocalizedString(key, bundle: _localizedBundle, comment: "")
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

// MARK: - Standard macOS Help Button

extension NSView {
    /// Create a standard macOS help button (circled "?" icon).
    /// Uses `.helpButton` bezel style per macOS HIG.
    static func makeHelpButton() -> NSButton {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .helpButton
        button.title = ""
        return button
    }
}

// MARK: - HIG-Compliant Dialog Button Bar

/// Creates an NSStackView-based button bar following macOS HIG:
///   [Destructive] --- spacer --- [Help(?)] [Cancel] [OK/Connect/Apply]
///
/// - Cancel is placed to the left of the primary action
/// - OK/Connect/Apply is rightmost
/// - Help button uses standard macOS circled "?" style
/// - Destructive buttons are isolated on the left
/// - Button spacing: 8pt within groups, 12pt between groups
enum DialogButtonBar {

    struct Configuration {
        var okTitle: String = "OK"
        var cancelTitle: String = "Cancel"
        var showHelp: Bool = true
        var destructiveTitle: String? = nil
        /// Minimum 72pt per macOS HIG; auto-expands for localized text.
        var minButtonWidth: CGFloat = DialogLayout.buttonWidth
    }

    /// Build a horizontal button bar.
    ///
    /// - Parameters:
    ///   - config: Button titles and visibility options.
    ///   - okTarget: Target for the OK button action.
    ///   - okAction: Selector for the OK button.
    ///   - cancelTarget: Target for the Cancel button action.
    ///   - cancelAction: Selector for the Cancel button.
    ///   - helpTarget: Target for the Help button action.
    ///   - helpAction: Selector for the Help button.
    ///   - destructiveTarget: Target for the destructive button action.
    ///   - destructiveAction: Selector for the destructive button.
    /// - Returns: A tuple of (barView, okButton, cancelButton, helpButton, destructiveButton).
    static func build(
        config: Configuration = Configuration(),
        okTarget: AnyObject? = nil, okAction: Selector? = nil,
        cancelTarget: AnyObject? = nil, cancelAction: Selector? = nil,
        helpTarget: AnyObject? = nil, helpAction: Selector? = nil,
        destructiveTarget: AnyObject? = nil, destructiveAction: Selector? = nil
    ) -> (bar: NSStackView, ok: NSButton, cancel: NSButton, help: NSButton?, destructive: NSButton?) {

        // Primary action button (rightmost) — default button (Enter key)
        let okButton = NSView.makePushButton(TTL(config.okTitle), keyEquivalent: "\r")
        okButton.target = okTarget
        okButton.action = okAction
        okButton.setAccessibilityLabel(TTL(config.okTitle))

        // Cancel button — Escape key
        let cancelButton = NSView.makePushButton(TTL(config.cancelTitle), keyEquivalent: "\u{1b}")
        cancelButton.target = cancelTarget
        cancelButton.action = cancelAction
        cancelButton.setAccessibilityLabel(TTL(config.cancelTitle))

        // Right group: [Cancel] [OK]  (8pt spacing)
        let rightGroup = NSStackView(views: [cancelButton, okButton])
        rightGroup.translatesAutoresizingMaskIntoConstraints = false
        rightGroup.orientation = .horizontal
        rightGroup.spacing = DialogLayout.buttonSpacing
        rightGroup.distribution = .fill

        // Help button — standard macOS "?" circle
        var helpButton: NSButton? = nil
        if config.showHelp {
            let hb = NSView.makeHelpButton()
            hb.target = helpTarget
            hb.action = helpAction
            hb.setAccessibilityLabel(TTL("Help"))
            helpButton = hb
            rightGroup.insertArrangedSubview(hb, at: 0)
        }

        // Destructive button (left-isolated)
        var destructiveButton: NSButton? = nil
        var leftViews: [NSView] = []
        if let destructiveTitle = config.destructiveTitle {
            let db = NSView.makePushButton(TTL(destructiveTitle))
            db.target = destructiveTarget
            db.action = destructiveAction
            db.setAccessibilityLabel(TTL(destructiveTitle))
            destructiveButton = db
            leftViews.append(db)
        }

        // Spacer between left and right groups
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)

        // Full bar: [Destructive?] --- spacer --- [Help(?)] [Cancel] [OK]
        let allViews: [NSView] = leftViews + [spacer, rightGroup]
        let bar = NSStackView(views: allViews)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.orientation = .horizontal
        bar.spacing = DialogLayout.buttonSpacing
        bar.distribution = .fill
        bar.alignment = .centerY

        return (bar, okButton, cancelButton, helpButton, destructiveButton)
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

        // Footer button bar — HIG: [Help(?)] --- [Cancel] [OK]
        let buttonBar = DialogButtonBar.build(
            okTarget: self, okAction: #selector(okAction(_:)),
            cancelTarget: self, cancelAction: #selector(cancelAction(_:)),
            helpTarget: self, helpAction: #selector(helpAction(_:))
        )
        okButton = buttonBar.ok
        cancelButton = buttonBar.cancel
        helpButton = buttonBar.help ?? NSView.makeHelpButton()

        let footerBar = buttonBar.bar
        container.addSubview(footerBar)

        // Separator line
        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        container.addSubview(separator)

        let m = DialogLayout.margin

        NSLayoutConstraint.activate([
            // Content area
            contentArea.topAnchor.constraint(equalTo: container.topAnchor, constant: m),
            contentArea.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
            contentArea.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),

            // Separator
            separator.topAnchor.constraint(equalTo: contentArea.bottomAnchor, constant: m),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Button bar
            footerBar.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: m * 0.75),
            footerBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
            footerBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),
            footerBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m * 0.75),
        ])

        self.view = container
    }

    /// Present this dialog as a modal window with a visible title bar.
    /// The window is centered over the parent window and blocks until
    /// the user clicks OK or Cancel.
    /// Returns the dialog window for tracking purposes.
    @discardableResult
    func presentAsModal(on parentWindow: NSWindow) -> NSWindow {
        // NSWindow(contentViewController:) は内部で fullSizeContentView 相当の
        // 設定を行い、コンテンツがタイトルバー背後に描画されてしまう。
        // 明示的に contentRect + styleMask でウィンドウを作成し、
        // contentViewController を後から設定することで回避する。
        let dialogWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        dialogWindow.contentViewController = self
        dialogWindow.isReleasedWhenClosed = false
        dialogWindow.title = self.title ?? ""

        // 親ウィンドウの中央に配置
        dialogWindow.layoutIfNeeded()
        let parentFrame = parentWindow.frame
        let dialogSize = dialogWindow.frame.size
        let x = parentFrame.midX - dialogSize.width / 2
        let y = parentFrame.midY - dialogSize.height / 2
        dialogWindow.setFrameOrigin(NSPoint(x: x, y: y))

        // スクリーン内に収める
        if let screen = parentWindow.screen ?? NSScreen.main {
            var frame = dialogWindow.frame
            let visible = screen.visibleFrame
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
            dialogWindow.setFrame(frame, display: true)
        }

        let response = NSApplication.shared.runModal(for: dialogWindow)
        if response == .OK {
            okHandler?()
        } else {
            cancelHandler?()
        }
        return dialogWindow
    }

    /// Present as application-modal dialog (when no parent window).
    func presentModal() -> NSApplication.ModalResponse {
        let dialogWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        dialogWindow.contentViewController = self
        dialogWindow.isReleasedWhenClosed = false
        dialogWindow.title = self.title ?? ""
        dialogWindow.center()

        // スクリーン内に収める
        if let screen = NSScreen.main {
            var frame = dialogWindow.frame
            let visible = screen.visibleFrame
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
            dialogWindow.setFrame(frame, display: true)
        }

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
