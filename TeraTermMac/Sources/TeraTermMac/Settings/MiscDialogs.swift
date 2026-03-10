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

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 250))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

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

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 40))

        let field = NSView.makeTextField(value: "", placeholder: TTL("dialog.changeDir.placeholder"))
        container.addSubview(field)

        let browseBtn = NSButton(title: "...", target: nil, action: nil)
        browseBtn.translatesAutoresizingMaskIntoConstraints = false
        browseBtn.bezelStyle = .rounded
        container.addSubview(browseBtn)

        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: container.topAnchor),
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: browseBtn.leadingAnchor, constant: -4),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            browseBtn.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            browseBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            browseBtn.widthAnchor.constraint(equalToConstant: 30),
        ])

        alert.accessoryView = container

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
        col.title = "Host"
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

    static func show(title: String = "Input", prompt: String = "",
                     defaultValue: String = "",
                     on window: NSWindow,
                     completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = prompt
        alert.addButton(withTitle: TTL("OK"))
        alert.addButton(withTitle: TTL("Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
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

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tableView = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        col.title = ""
        col.width = 320
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
        filenameField = NSView.makeTextField(value: "", placeholder: "teraterm.log")

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

    static func show(message: String, title: String = "Message",
                     showNoButton: Bool = true,
                     on window: NSWindow,
                     completion: @escaping (_ okClicked: Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: TTL("OK"))
        if showNoButton {
            alert.addButton(withTitle: "No")
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
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered, defer: false)
        p.title = "Tera Term"
        p.isFloatingPanel = true
        p.isReleasedWhenClosed = false

        let cv = p.contentView!
        let cancelBtn = NSButton(title: TTL("Cancel"), target: self, action: #selector(cancelClicked(_:)))
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.bezelStyle = .rounded
        cv.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            cancelBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            cancelBtn.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
        ])

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

    func show(message: String = "Processing...") {
        if let p = panel {
            label?.stringValue = message
            p.orderFront(nil)
            return
        }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 60),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered, defer: false)
        p.title = "Status"
        p.isFloatingPanel = true
        p.isReleasedWhenClosed = false

        let l = NSTextField(labelWithString: message)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.alignment = .center
        p.contentView!.addSubview(l)

        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: p.contentView!.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: p.contentView!.centerYAnchor),
        ])

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

// MARK: - TCP/IP Dialog (IDD_TCPIPDLG)

final class TCPIPDialogController: BaseSetupDialogController {

    private var settings: TerminalSettings

    private var hostField: NSTextField!
    private var portField: NSTextField!
    private var keepAliveCheck: NSButton!
    private var keepAliveIntervalField: NSTextField!
    private var autoCloseCheck: NSButton!

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
        contentArea.widthAnchor.constraint(equalToConstant: 380).isActive = true

        let hostLabel = NSView.makeLabel(TTL("dialog.tcpip.host"))
        hostField = NSView.makeTextField(value: settings.hostname)

        let portLabel = NSView.makeLabel(TTL("dialog.tcpip.port"))
        portField = NSView.makeNumberField(value: settings.defaultPort, width: 80)

        let grid = NSGridView(views: [
            [hostLabel, hostField],
            [portLabel, portField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        keepAliveCheck = NSView.makeCheckbox(TTL("dialog.tcpip.keepAlive"), checked: settings.tcpKeepAlive)
        let intervalLabel = NSView.makeLabel(TTL("dialog.tcpip.keepAliveInterval"), alignment: .left)
        keepAliveIntervalField = NSView.makeNumberField(value: settings.tcpKeepAliveInterval, width: 80)
        let secLabel = NSView.makeLabel("sec", alignment: .left)
        let intervalRow = NSStackView(views: [intervalLabel, keepAliveIntervalField, secLabel])
        intervalRow.translatesAutoresizingMaskIntoConstraints = false
        intervalRow.orientation = .horizontal
        intervalRow.spacing = 8

        autoCloseCheck = NSView.makeCheckbox(TTL("dialog.tcpip.autoClose"), checked: settings.autoWindowClose)

        let stack = NSStackView(views: [grid, keepAliveCheck, intervalRow, autoCloseCheck])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        contentArea.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])
    }

    override func applySettings() {
        settings.hostname = hostField.stringValue
        settings.defaultPort = portField.integerValue
        settings.tcpKeepAlive = keepAliveCheck.state == .on
        settings.tcpKeepAliveInterval = keepAliveIntervalField.integerValue
        settings.autoWindowClose = autoCloseCheck.state == .on
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

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tableView = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        col.title = "Window"
        col.width = 340
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
