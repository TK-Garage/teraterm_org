/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * Miscellaneous dialogs — faithful reproduction of Tera Term 5.6 dialogs
 * not covered by other controllers.
 *
 * Dialogs ported:
 *   IDD_CLIPBOARD_DIALOG, IDD_DAD_DIALOG, IDD_DIRDLG, IDD_EDITHISTORYDLG,
 *   IDD_ERRDLG, IDD_INPDLG, IDD_LISTDLG, IDD_LOGDLG, IDD_MSGDLG,
 *   IDD_PRNABORTDLG, IDD_STATDLG, IDD_TCPIPDLG, IDD_WINLISTDLG
 */

#if canImport(AppKit)
import AppKit

// MARK: - Clipboard Confirmation Dialog (IDD_CLIPBOARD_DIALOG)

/// Displays clipboard content for confirmation before pasting.
final class ClipboardConfirmationDialog {

    /// Show clipboard text for confirmation. Returns true if user confirmed.
    static func confirm(text: String, on window: NSWindow,
                        completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = TTL("dialog.clipboard.title")
        alert.informativeText = ""
        alert.addButton(withTitle: TTL("OK"))
        alert.addButton(withTitle: TTL("Cancel"))

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalToConstant: 400),
            scrollView.heightAnchor.constraint(equalToConstant: 250),
        ])
        alert.accessoryView = scrollView

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                completion(true)
            } else {
                completion(false)
            }
        }
    }
}

// MARK: - File Drag and Drop Dialog (IDD_DAD_DIALOG)

/// Dialog shown when files are dragged and dropped onto the terminal.
final class DragDropDialogController: BaseSetupDialogController {

    enum Action: Int {
        case sendSCP = 0
        case sendFile = 1
        case pastePath = 2
    }

    struct Result {
        let filePath: String
        let action: Action
        let binary: Bool
        let escapeSpaces: Bool
    }

    private var pathField: NSTextField!
    private var scpRadio: NSButton!
    private var sendFileRadio: NSButton!
    private var pasteRadio: NSButton!
    private var binaryCheck: NSButton!
    private var escapeCheck: NSButton!

    private(set) var result: Result?
    private let droppedPath: String

    init(path: String) {
        self.droppedPath = path
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.dragDrop.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        contentArea.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let pathLabel = NSView.makeLabel(TTL("dialog.dragDrop.filePath"), alignment: .left)
        pathField = NSView.makeTextField(value: droppedPath)
        pathField.isEditable = false

        scpRadio = NSView.makeRadioButton(TTL("dialog.dragDrop.scp"), tag: 0)
        sendFileRadio = NSView.makeRadioButton(TTL("dialog.dragDrop.sendFile"), tag: 1)
        pasteRadio = NSView.makeRadioButton(TTL("dialog.dragDrop.pastePath"), tag: 2)
        pasteRadio.state = .on

        for r in [scpRadio!, sendFileRadio!, pasteRadio!] {
            r.target = self
            r.action = #selector(actionChanged(_:))
        }

        binaryCheck = NSView.makeCheckbox(TTL("dialog.dragDrop.binary"))
        escapeCheck = NSView.makeCheckbox(TTL("dialog.dragDrop.escape"), checked: true)

        let radioStack = NSStackView(views: [scpRadio, sendFileRadio, pasteRadio])
        radioStack.translatesAutoresizingMaskIntoConstraints = false
        radioStack.orientation = .vertical
        radioStack.alignment = .leading
        radioStack.spacing = 4

        let stack = NSStackView(views: [pathLabel, pathField, radioStack, binaryCheck, escapeCheck])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentArea.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])
    }

    @objc private func actionChanged(_ sender: NSButton) {
        for r in [scpRadio!, sendFileRadio!, pasteRadio!] {
            r.state = (r === sender) ? .on : .off
        }
    }

    override func applySettings() {
        let action: Action
        if scpRadio.state == .on { action = .sendSCP }
        else if sendFileRadio.state == .on { action = .sendFile }
        else { action = .pastePath }

        result = Result(
            filePath: pathField.stringValue,
            action: action,
            binary: binaryCheck.state == .on,
            escapeSpaces: escapeCheck.state == .on)
    }
}

// MARK: - Change Directory Dialog (IDD_DIRDLG)

final class ChangeDirectoryDialog {

    static func show(currentDir: String, on window: NSWindow,
                     completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = TTL("dialog.changeDir.title")
        alert.informativeText = String(format: TTL("dialog.changeDir.current"), currentDir)
        alert.addButton(withTitle: TTL("OK"))
        alert.addButton(withTitle: TTL("Cancel"))

        let field = NSView.makeTextField(value: "", placeholder: TTL("dialog.changeDir.placeholder"))
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let browseBtn = NSButton(title: TTL("..."), target: nil, action: nil)
        browseBtn.translatesAutoresizingMaskIntoConstraints = false
        browseBtn.bezelStyle = .rounded
        browseBtn.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let row = NSStackView(views: [field, browseBtn])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .centerY
        row.distribution = .fill

        row.widthAnchor.constraint(equalToConstant: 320).isActive = true

        alert.accessoryView = row

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                let path = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                completion(path.isEmpty ? nil : path)
            } else {
                completion(nil)
            }
        }
    }
}

// MARK: - Edit History Dialog (IDD_EDITHISTORYDLG)

final class EditHistoryDialogController: BaseSetupDialogController {

    private var hostField: NSTextField!
    private var historyList: NSTableView!
    private var items: [String]

    var resultHistory: [String] { items }

    init(history: [String]) {
        self.items = history
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.editHistory.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        contentArea.widthAnchor.constraint(equalToConstant: 400).isActive = true

        let hostLabel = NSView.makeLabel(TTL("dialog.editHistory.host"), alignment: .left)
        hostField = NSView.makeTextField(value: "")

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.heightAnchor.constraint(equalToConstant: 180).isActive = true

        historyList = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("host"))
        col.title = TTL("dialog.editHistory.hostColumn")
        col.width = 360
        historyList.addTableColumn(col)
        historyList.headerView = nil
        historyList.dataSource = self
        historyList.reloadData()
        scrollView.documentView = historyList

        let addBtn = NSView.makePushButton(TTL("dialog.editHistory.add"))
        addBtn.target = self
        addBtn.action = #selector(addItem(_:))

        let removeBtn = NSView.makePushButton(TTL("dialog.editHistory.remove"))
        removeBtn.target = self
        removeBtn.action = #selector(removeItem(_:))

        let upBtn = NSView.makePushButton(TTL("dialog.editHistory.up"))
        upBtn.target = self
        upBtn.action = #selector(moveUp(_:))

        let downBtn = NSView.makePushButton(TTL("dialog.editHistory.down"))
        downBtn.target = self
        downBtn.action = #selector(moveDown(_:))

        let btnStack = NSStackView(views: [addBtn, removeBtn, upBtn, downBtn])
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        btnStack.orientation = .horizontal
        btnStack.spacing = 8

        let stack = NSStackView(views: [hostLabel, hostField, scrollView, btnStack])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentArea.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func addItem(_ sender: Any?) {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        items.insert(host, at: 0)
        historyList.reloadData()
        hostField.stringValue = ""
    }

    @objc private func removeItem(_ sender: Any?) {
        let row = historyList.selectedRow
        guard row >= 0 && row < items.count else { return }
        items.remove(at: row)
        historyList.reloadData()
    }

    @objc override func moveUp(_ sender: Any?) {
        let row = historyList.selectedRow
        guard row > 0 && row < items.count else { return }
        items.swapAt(row, row - 1)
        historyList.reloadData()
        historyList.selectRowIndexes(IndexSet(integer: row - 1), byExtendingSelection: false)
    }

    @objc override func moveDown(_ sender: Any?) {
        let row = historyList.selectedRow
        guard row >= 0 && row < items.count - 1 else { return }
        items.swapAt(row, row + 1)
        historyList.reloadData()
        historyList.selectRowIndexes(IndexSet(integer: row + 1), byExtendingSelection: false)
    }

    override func applySettings() {
        // items is already up to date
    }
}

extension EditHistoryDialogController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0 && row < items.count else { return nil }
        return items[row]
    }
}

// MARK: - Macro Error Dialog (IDD_ERRDLG)

final class MacroErrorDialog {

    static func show(errorMessage: String, lineNumber: Int, errorLine: String,
                     on window: NSWindow,
                     completion: @escaping (_ shouldContinue: Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = TTL("dialog.macroError.title")
        alert.informativeText = [
            errorMessage,
            String(format: TTL("dialog.macroError.lineNumber"), lineNumber),
            errorLine
        ].joined(separator: "\n")
        alert.addButton(withTitle: TTL("dialog.macroError.stop"))
        alert.addButton(withTitle: TTL("dialog.macroError.continue"))

        alert.beginSheetModal(for: window) { response in
            completion(response == .alertSecondButtonReturn)
        }
    }
}

// MARK: - Input Dialog (IDD_INPDLG)

final class InputDialog {

    static func show(title: String = TTL("dialog.input.defaultTitle"), prompt: String = "",
                     defaultValue: String = "",
                     on window: NSWindow,
                     completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = prompt
        alert.addButton(withTitle: TTL("OK"))
        alert.addButton(withTitle: TTL("Cancel"))

        let field = NSView.makeTextField(value: defaultValue)
        field.lineBreakMode = .byTruncatingTail
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                completion(field.stringValue)
            } else {
                completion(nil)
            }
        }
    }
}

// MARK: - List Dialog (IDD_LISTDLG)

final class ListDialog {

    static func show(items: [String], title: String = "",
                     on window: NSWindow,
                     completion: @escaping (Int?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: TTL("OK"))
        alert.addButton(withTitle: TTL("Cancel"))

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tableView = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        col.title = ""
        tableView.addTableColumn(col)
        tableView.headerView = nil
        let ds = DialogListBoxDataSource(items: items)
        tableView.dataSource = ds
        tableView.delegate = ds
        tableView.reloadData()
        if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        scrollView.documentView = tableView

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalToConstant: 340),
            scrollView.heightAnchor.constraint(equalToConstant: 180),
        ])
        alert.accessoryView = scrollView

        // Prevent ds from being deallocated
        objc_setAssociatedObject(alert, "ds", ds, .OBJC_ASSOCIATION_RETAIN)

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn && tableView.selectedRow >= 0 {
                completion(tableView.selectedRow)
            } else {
                completion(nil)
            }
        }
    }
}

// MARK: - Log Dialog (IDD_LOGDLG)

final class LogDialogController: BaseSetupDialogController {

    struct Result {
        let filePath: String
        let writeMode: WriteMode
        let format: LogFormat
        let timestamp: Bool
        let plainText: Bool
        let append: Bool
    }

    enum WriteMode: Int {
        case new_ = 0
        case append = 1
    }

    enum LogFormat: Int {
        case text = 0
        case binary = 1
    }

    private var filenameField: NSTextField!
    private var newRadio: NSButton!
    private var appendRadio: NSButton!
    private var textRadio: NSButton!
    private var binaryRadio: NSButton!
    private var timestampCheck: NSButton!
    private var plainTextCheck: NSButton!

    private(set) var result: Result?

    init() {
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.log.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        contentArea.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let fnLabel = NSView.makeLabel(TTL("dialog.log.filename"), alignment: .left)
        filenameField = NSView.makeTextField(value: "", placeholder: TTL("dialog.log.placeholder"))

        let browseBtn = NSButton(title: "...", target: self, action: #selector(browseFile(_:)))
        browseBtn.translatesAutoresizingMaskIntoConstraints = false
        browseBtn.bezelStyle = .rounded
        browseBtn.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let fnRow = NSStackView(views: [filenameField, browseBtn])
        fnRow.translatesAutoresizingMaskIntoConstraints = false
        fnRow.orientation = .horizontal
        fnRow.spacing = 4

        // Write mode
        let modeBox = NSView.makeGroupBox(title: TTL("dialog.log.writeMode"))
        newRadio = NSView.makeRadioButton(TTL("dialog.log.new"), tag: 0)
        newRadio.state = .on
        newRadio.target = self
        newRadio.action = #selector(writeModeChanged(_:))
        appendRadio = NSView.makeRadioButton(TTL("dialog.log.appendMode"), tag: 1)
        appendRadio.target = self
        appendRadio.action = #selector(writeModeChanged(_:))
        let modeStack = NSStackView(views: [newRadio, appendRadio])
        modeStack.translatesAutoresizingMaskIntoConstraints = false
        modeStack.orientation = .horizontal
        modeStack.spacing = 16
        let mc = modeBox.contentView!
        mc.addSubview(modeStack)
        NSLayoutConstraint.activate([
            modeStack.topAnchor.constraint(equalTo: mc.topAnchor, constant: 16),
            modeStack.leadingAnchor.constraint(equalTo: mc.leadingAnchor, constant: 12),
            modeStack.bottomAnchor.constraint(equalTo: mc.bottomAnchor, constant: -8),
        ])

        // Format
        let formatBox = NSView.makeGroupBox(title: TTL("dialog.log.format"))
        textRadio = NSView.makeRadioButton(TTL("dialog.log.formatText"), tag: 0)
        textRadio.state = .on
        textRadio.target = self
        textRadio.action = #selector(formatChanged(_:))
        binaryRadio = NSView.makeRadioButton(TTL("dialog.log.formatBinary"), tag: 1)
        binaryRadio.target = self
        binaryRadio.action = #selector(formatChanged(_:))
        let formatStack = NSStackView(views: [textRadio, binaryRadio])
        formatStack.translatesAutoresizingMaskIntoConstraints = false
        formatStack.orientation = .horizontal
        formatStack.spacing = 16
        let fc = formatBox.contentView!
        fc.addSubview(formatStack)
        NSLayoutConstraint.activate([
            formatStack.topAnchor.constraint(equalTo: fc.topAnchor, constant: 16),
            formatStack.leadingAnchor.constraint(equalTo: fc.leadingAnchor, constant: 12),
            formatStack.bottomAnchor.constraint(equalTo: fc.bottomAnchor, constant: -8),
        ])

        timestampCheck = NSView.makeCheckbox(TTL("dialog.log.timestampOption"))
        plainTextCheck = NSView.makeCheckbox(TTL("dialog.log.plainTextOption"), checked: true)

        let stack = NSStackView(views: [fnLabel, fnRow, modeBox, formatBox, timestampCheck, plainTextCheck])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentArea.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            fnRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func writeModeChanged(_ sender: NSButton) {
        newRadio.state = sender === newRadio ? .on : .off
        appendRadio.state = sender === appendRadio ? .on : .off
    }

    @objc private func formatChanged(_ sender: NSButton) {
        textRadio.state = sender === textRadio ? .on : .off
        binaryRadio.state = sender === binaryRadio ? .on : .off
    }

    @objc private func browseFile(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "teraterm.log"
        if panel.runModal() == .OK, let url = panel.url {
            filenameField.stringValue = url.path
        }
    }

    override func applySettings() {
        let path = filenameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { result = nil; return }
        result = Result(
            filePath: path,
            writeMode: appendRadio.state == .on ? .append : .new_,
            format: binaryRadio.state == .on ? .binary : .text,
            timestamp: timestampCheck.state == .on,
            plainText: plainTextCheck.state == .on,
            append: appendRadio.state == .on)
    }
}

// MARK: - Message Dialog (IDD_MSGDLG)

final class MessageDialog {

    static func show(message: String, title: String = TTL("dialog.message.defaultTitle"),
                     showNoButton: Bool = true,
                     on window: NSWindow,
                     completion: @escaping (_ okClicked: Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: TTL("OK"))
        if showNoButton {
            alert.addButton(withTitle: TTL("No"))
        }

        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }
}

// MARK: - Print Abort Dialog (IDD_PRNABORTDLG)

final class PrintAbortDialog {

    private var panel: NSPanel?
    var onCancel: (() -> Void)?

    func show() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let messageLabel = NSView.makeLabel(TTL("dialog.printAbort.printing"), alignment: .center)
        messageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let cancelBtn = NSView.makePushButton(TTL("Cancel"), keyEquivalent: "\u{1b}")
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelClicked(_:))

        let stack = NSStackView(views: [messageLabel, cancelBtn])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = DialogLayout.rowSpacing
        container.addSubview(stack)

        let m = DialogLayout.margin
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: m),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: m),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -m),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])

        let vc = NSViewController()
        vc.view = container
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: true)
        p.contentViewController = vc
        p.title = TTL("Tera Term")
        p.isFloatingPanel = true
        p.isReleasedWhenClosed = false
        p.center()
        p.orderFront(nil)
        self.panel = p
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    @objc private func cancelClicked(_ sender: Any?) {
        onCancel?()
        close()
    }
}

// MARK: - Status Dialog (IDD_STATDLG)

final class StatusDialog {

    private var panel: NSPanel?
    private var label: NSTextField?

    func show(message: String = TTL("dialog.status.processing")) {
        if let p = panel {
            label?.stringValue = message
            p.orderFront(nil)
            return
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let l = NSTextField(labelWithString: message)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.alignment = .center
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(l)

        let m = DialogLayout.margin
        NSLayoutConstraint.activate([
            l.topAnchor.constraint(equalTo: container.topAnchor, constant: m),
            l.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: m),
            l.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -m),
            l.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m),
            l.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])

        let vc = NSViewController()
        vc.view = container
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 60),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: true)
        p.contentViewController = vc
        p.title = TTL("dialog.status.title")
        p.isFloatingPanel = true
        p.isReleasedWhenClosed = false

        self.label = l
        p.center()
        p.orderFront(nil)
        self.panel = p
    }

    func update(message: String) {
        label?.stringValue = message
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        label = nil
    }
}

// MARK: - Keyboard Setup Dialog (IDD_KEYBDLG)

final class KeyboardSetupDialogController: BaseSetupDialogController {

    private var settings: TerminalSettings

    private var kbTypePopup: NSPopUpButton!
    private var bsPopup: NSPopUpButton!
    private var delPopup: NSPopUpButton!
    private var metaPopup: NSPopUpButton!
    private var ansField: NSTextField!
    private var disableAppKPCheck: NSButton!
    private var disableAppCurCheck: NSButton!

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.keyboardSetup.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        let kbPopupWidth: CGFloat = 180

        kbTypePopup = NSView.makePopUpButton(
            items: TerminalID.allCases.map { $0.displayName }, width: kbPopupWidth)
        if let idx = TerminalID.allCases.firstIndex(of: settings.terminalID) {
            kbTypePopup.selectItem(at: idx)
        }

        bsPopup = NSView.makePopUpButton(items: [TTL("dialog.keyboardSetup.bsOption"), TTL("dialog.keyboardSetup.delOption")], width: kbPopupWidth)
        bsPopup.selectItem(at: settings.bsKey == 8 ? 0 : 1)

        delPopup = NSView.makePopUpButton(
            items: [TTL("dialog.keyboardSetup.delOption"), TTL("dialog.keyboardSetup.bsOption"), TTL("dialog.keyboardSetup.deleteEscSeq")],
            width: kbPopupWidth)
        delPopup.selectItem(at: settings.deleteKey == 127 ? 0 : (settings.deleteKey == 8 ? 1 : 2))

        metaPopup = NSView.makePopUpButton(
            items: [TTL("dialog.keyboardSetup.metaOff"), TTL("dialog.keyboardSetup.metaOn")],
            width: kbPopupWidth)
        metaPopup.selectItem(at: settings.metaKey)

        ansField = NSView.makeTextField(
            value: settings.answerback,
            placeholder: TTL("dialog.keyboardSetup.answerbackPlaceholder"),
            width: DialogLayout.wideFieldWidth)

        disableAppKPCheck = NSView.makeCheckbox(
            TTL("dialog.keyboardSetup.disableAppKeypadOption"),
            checked: settings.disableAppKeypad)
        disableAppCurCheck = NSView.makeCheckbox(
            TTL("dialog.keyboardSetup.disableAppCursorOption"),
            checked: settings.disableAppCursor)

        addFormGrid(rows: [
            ("dialog.keyboardSetup.keyboardType", kbTypePopup),
            ("dialog.keyboardSetup.bsKey", bsPopup),
            ("dialog.keyboardSetup.deleteKey", delPopup),
            ("dialog.keyboardSetup.metaKey", metaPopup),
            ("dialog.keyboardSetup.answerback", ansField),
            ("dialog.keyboardSetup.disableAppKeypad", disableAppKPCheck),
            ("dialog.keyboardSetup.disableAppCursor", disableAppCurCheck),
        ])
    }

    override func applySettings() {
        let allIDs = TerminalID.allCases
        let idx = kbTypePopup.indexOfSelectedItem
        if idx >= 0 && idx < allIDs.count {
            settings.terminalID = allIDs[allIDs.index(allIDs.startIndex, offsetBy: idx)]
        }
        settings.bsKey = bsPopup.indexOfSelectedItem == 0 ? 8 : 127
        switch delPopup.indexOfSelectedItem {
        case 0: settings.deleteKey = 127
        case 1: settings.deleteKey = 8
        default: settings.deleteKey = 0
        }
        settings.metaKey = metaPopup.indexOfSelectedItem
        settings.answerback = ansField.stringValue
        settings.disableAppKeypad = disableAppKPCheck.state == .on
        settings.disableAppCursor = disableAppCurCheck.state == .on
    }
}

// MARK: - TCP/IP Dialog (IDD_TCPIPDLG)

final class TCPIPDialogController: BaseSetupDialogController {

    private var settings: TerminalSettings

    // General
    private var autoCloseCheck: NSButton!
    private var keepAliveCheck: NSButton!
    private var keepAliveIntervalField: NSTextField!
    private var historySizeField: NSTextField!

    // Anti-idle
    private var antiIdleCheck: NSButton!
    private var antiIdleStringField: NSTextField!
    private var antiIdleIntervalField: NSTextField!

    // Telnet
    private var telnetAutoDetectCheck: NSButton!
    private var telnetBinaryOptionCheck: NSButton!
    private var telnetBinaryModeCheck: NSButton!
    private var telnetIgnoreDisconnectCheck: NSButton!

    // SSH
    private var sshHeartbeatField: NSTextField!

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.tcpip.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        minimumContentWidth = 440

        // ── General ──
        autoCloseCheck = NSView.makeCheckbox(
            TTL("dialog.tcpip.autoClose"), checked: settings.autoWindowClose)

        keepAliveCheck = NSView.makeCheckbox(
            TTL("dialog.tcpip.keepAlive"), checked: settings.tcpKeepAlive)
        keepAliveIntervalField = NSView.makeNumberField(
            value: settings.tcpKeepAliveInterval, width: 70)
        let keepAliveRow = NSStackView(views: [
            NSView.makeLabel(TTL("dialog.tcpip.keepAliveInterval"), alignment: .left),
            keepAliveIntervalField,
            NSView.makeLabel("sec", alignment: .left),
        ])
        keepAliveRow.translatesAutoresizingMaskIntoConstraints = false
        keepAliveRow.orientation = .horizontal
        keepAliveRow.spacing = 8

        historySizeField = NSView.makeNumberField(
            value: settings.hostHistorySize, width: 70)
        let historyRow = NSView.createFormRow(
            label: "dialog.tcpip.historySize", control: historySizeField)

        // ── Anti-idle ──
        let antiIdleBox = NSView.makeGroupBox(title: TTL("dialog.tcpip.antiIdle"))
        antiIdleCheck = NSView.makeCheckbox(
            TTL("dialog.tcpip.antiIdleEnable"), checked: settings.antiIdle)
        antiIdleStringField = NSView.makeTextField(
            value: settings.antiIdleString, width: 120)
        antiIdleIntervalField = NSView.makeNumberField(
            value: settings.antiIdleInterval, width: 70)

        let antiIdleStringRow = NSView.createFormRow(
            labelView: NSView.makeLabel(TTL("dialog.tcpip.antiIdleString"), alignment: .right),
            control: antiIdleStringField)
        let antiIdleIntervalRow = NSStackView(views: [
            NSView.makeLabel(TTL("dialog.tcpip.antiIdleInterval"), alignment: .right),
            antiIdleIntervalField,
            NSView.makeLabel("sec", alignment: .left),
        ])
        antiIdleIntervalRow.translatesAutoresizingMaskIntoConstraints = false
        antiIdleIntervalRow.orientation = .horizontal
        antiIdleIntervalRow.spacing = 8

        let antiIdleStack = NSStackView(views: [
            antiIdleCheck, antiIdleStringRow, antiIdleIntervalRow,
        ])
        antiIdleStack.translatesAutoresizingMaskIntoConstraints = false
        antiIdleStack.orientation = .vertical
        antiIdleStack.alignment = .leading
        antiIdleStack.spacing = 8
        // グループボックス内部の余白
        let antiIdleCV = antiIdleBox.contentView!
        antiIdleCV.addSubview(antiIdleStack)
        NSLayoutConstraint.activate([
            antiIdleStack.topAnchor.constraint(equalTo: antiIdleCV.topAnchor, constant: 4),
            antiIdleStack.leadingAnchor.constraint(equalTo: antiIdleCV.leadingAnchor, constant: 8),
            antiIdleStack.trailingAnchor.constraint(equalTo: antiIdleCV.trailingAnchor, constant: -8),
            antiIdleStack.bottomAnchor.constraint(equalTo: antiIdleCV.bottomAnchor, constant: -4),
        ])

        // ── Telnet ──
        let telnetBox = NSView.makeGroupBox(title: TTL("dialog.tcpip.telnetGroup"))
        telnetAutoDetectCheck = NSView.makeCheckbox(
            TTL("dialog.tcpip.telnetAutoDetect"), checked: settings.telnetAutoDetect)
        telnetBinaryOptionCheck = NSView.makeCheckbox(
            TTL("dialog.tcpip.telnetBinaryOption"), checked: settings.telnetBinaryOption)
        telnetBinaryModeCheck = NSView.makeCheckbox(
            TTL("dialog.tcpip.telnetBinaryMode"), checked: settings.telnetBinaryMode)
        telnetIgnoreDisconnectCheck = NSView.makeCheckbox(
            TTL("dialog.tcpip.telnetIgnoreDisconnect"), checked: settings.telnetIgnoreDisconnect)

        let telnetStack = NSStackView(views: [
            telnetAutoDetectCheck, telnetBinaryOptionCheck,
            telnetBinaryModeCheck, telnetIgnoreDisconnectCheck,
        ])
        telnetStack.translatesAutoresizingMaskIntoConstraints = false
        telnetStack.orientation = .vertical
        telnetStack.alignment = .leading
        telnetStack.spacing = 6
        let telnetCV = telnetBox.contentView!
        telnetCV.addSubview(telnetStack)
        NSLayoutConstraint.activate([
            telnetStack.topAnchor.constraint(equalTo: telnetCV.topAnchor, constant: 4),
            telnetStack.leadingAnchor.constraint(equalTo: telnetCV.leadingAnchor, constant: 8),
            telnetStack.trailingAnchor.constraint(equalTo: telnetCV.trailingAnchor, constant: -8),
            telnetStack.bottomAnchor.constraint(equalTo: telnetCV.bottomAnchor, constant: -4),
        ])

        // ── SSH Heartbeat ──
        sshHeartbeatField = NSView.makeNumberField(
            value: settings.sshHeartbeat, width: 70)
        let sshHeartbeatRow = NSStackView(views: [
            NSView.makeLabel(TTL("dialog.tcpip.sshHeartbeat"), alignment: .left),
            sshHeartbeatField,
            NSView.makeLabel("sec", alignment: .left),
        ])
        sshHeartbeatRow.translatesAutoresizingMaskIntoConstraints = false
        sshHeartbeatRow.orientation = .horizontal
        sshHeartbeatRow.spacing = 8

        // ── 全体レイアウト（オリジナル TeraTerm の UI 順序に準拠）──
        addFullWidthView(autoCloseCheck)
        addFullWidthView(keepAliveCheck)
        addFullWidthView(keepAliveRow)
        addFullWidthView(historyRow)
        addSectionSpacing()
        addFullWidthView(antiIdleBox)
        addSectionSpacing()
        addFullWidthView(telnetBox)
        addSectionSpacing()
        addFullWidthView(sshHeartbeatRow)
    }

    override func applySettings() {
        settings.autoWindowClose = autoCloseCheck.state == .on
        settings.tcpKeepAlive = keepAliveCheck.state == .on
        settings.tcpKeepAliveInterval = keepAliveIntervalField.integerValue
        settings.hostHistorySize = max(1, historySizeField.integerValue)
        settings.antiIdle = antiIdleCheck.state == .on
        settings.antiIdleString = antiIdleStringField.stringValue
        settings.antiIdleInterval = max(1, antiIdleIntervalField.integerValue)
        settings.telnetAutoDetect = telnetAutoDetectCheck.state == .on
        settings.telnetBinaryOption = telnetBinaryOptionCheck.state == .on
        settings.telnetBinaryMode = telnetBinaryModeCheck.state == .on
        settings.telnetIgnoreDisconnect = telnetIgnoreDisconnectCheck.state == .on
        settings.sshHeartbeat = max(0, sshHeartbeatField.integerValue)
    }
}

// MARK: - Window List Dialog (IDD_WINLISTDLG)

final class WindowListDialog {

    static func show(on window: NSWindow,
                     completion: @escaping (NSWindow?) -> Void) {
        let alert = NSAlert()
        alert.messageText = TTL("dialog.windowList.title")
        alert.addButton(withTitle: TTL("dialog.windowList.open"))
        alert.addButton(withTitle: TTL("Cancel"))
        alert.addButton(withTitle: TTL("dialog.windowList.closeWindow"))

        let windows = NSApp.windows.filter {
            $0.isVisible && !$0.isSheet && $0 !== window && $0.title != ""
        }
        let windowTitles = windows.map { $0.title }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tableView = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        col.title = TTL("dialog.windowList.windowColumn")
        tableView.addTableColumn(col)
        tableView.headerView = nil
        let ds = DialogListBoxDataSource(items: windowTitles)
        tableView.dataSource = ds
        tableView.delegate = ds
        tableView.reloadData()
        if !windowTitles.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        scrollView.documentView = tableView

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalToConstant: 360),
            scrollView.heightAnchor.constraint(equalToConstant: 180),
        ])
        alert.accessoryView = scrollView

        objc_setAssociatedObject(alert, "ds", ds, .OBJC_ASSOCIATION_RETAIN)

        alert.beginSheetModal(for: window) { response in
            let row = tableView.selectedRow
            guard row >= 0 && row < windows.count else {
                completion(nil)
                return
            }
            let selectedWindow = windows[row]

            switch response {
            case .alertFirstButtonReturn: // Open
                selectedWindow.makeKeyAndOrderFront(nil)
                completion(selectedWindow)
            case .alertThirdButtonReturn: // Close window
                selectedWindow.performClose(nil)
                completion(nil)
            default:
                completion(nil)
            }
        }
    }
}

#endif
