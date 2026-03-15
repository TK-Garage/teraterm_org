/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * Broadcast dialog — faithful port of Tera Term 5.6 IDD_BROADCAST_DIALOG.
 *
 * Features:
 *   - Command text entry with history
 *   - Send to this process only option
 *   - Enter key send option
 *   - Real-time mode toggle
 *   - Window list with right-click context menu
 *     (bring to front, minimize, invert selection)
 */

#if canImport(AppKit)
import AppKit

// MARK: - Broadcast Dialog Controller

final class BroadcastDialogController: NSObject {

    private var window: NSWindow?
    private var commandField: NSComboBox!
    private var windowListView: NSTableView!
    private var sendToThisOnlyCheck: NSButton!
    private var sendEnterCheck: NSButton!
    private var realtimeCheck: NSButton!

    private var settings: TerminalSettings
    private var windowEntries: [BroadcastWindowEntry] = []

    /// Callback: (command, selectedWindowIDs, sendEnter, realtime)
    var onSend: ((String, [Int], Bool, Bool) -> Void)?

    struct BroadcastWindowEntry {
        let windowID: Int
        let title: String
        var selected: Bool
    }

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init()
    }

    func show(on parent: NSWindow) {
        if window != nil { return }
        buildWindow()
        guard let win = window else { return }
        win.center()
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - Build Window

    private func buildWindow() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Command input with history (NSComboBox)
        let commandLabel = NSView.makeLabel(TTL("dialog.broadcast.label"), alignment: .left)

        commandField = NSComboBox()
        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        commandField.placeholderString = TTL("dialog.broadcast.placeholder")
        commandField.isEditable = true
        commandField.completes = false
        commandField.usesDataSource = false
        // Load history
        for item in settings.broadcastHistory {
            commandField.addItem(withObjectValue: item)
        }

        // Options
        sendToThisOnlyCheck = NSView.makeCheckbox(
            TTL("dialog.broadcast.sendToThisOnly"),
            checked: settings.broadcastSendToThisOnly)
        sendEnterCheck = NSView.makeCheckbox(
            TTL("dialog.broadcast.sendEnter"),
            checked: settings.broadcastSendEnter)
        realtimeCheck = NSView.makeCheckbox(
            TTL("dialog.broadcast.realtime"),
            checked: settings.broadcastRealtime)

        // Window list
        let windowListLabel = NSView.makeLabel(TTL("dialog.broadcast.windowList"), alignment: .left)
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.heightAnchor.constraint(equalToConstant: 160).isActive = true

        windowListView = NSTableView()
        let checkCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        checkCol.title = ""
        checkCol.width = 24
        let titleCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleCol.title = TTL("dialog.broadcast.windowTitle")
        titleCol.width = 340
        windowListView.addTableColumn(checkCol)
        windowListView.addTableColumn(titleCol)
        windowListView.headerView?.isHidden = false
        windowListView.dataSource = self
        windowListView.delegate = self
        windowListView.allowsMultipleSelection = true

        // Build window entries from open terminal windows
        refreshWindowList()

        scrollView.documentView = windowListView

        // Right-click context menu for window list
        let contextMenu = NSMenu()
        contextMenu.addItem(NSMenuItem(title: TTL("dialog.broadcast.bringToFront"),
                                       action: #selector(bringToFront(_:)),
                                       keyEquivalent: ""))
        contextMenu.addItem(NSMenuItem(title: TTL("dialog.broadcast.minimize"),
                                       action: #selector(minimizeSelected(_:)),
                                       keyEquivalent: ""))
        contextMenu.addItem(NSMenuItem.separator())
        contextMenu.addItem(NSMenuItem(title: TTL("dialog.broadcast.selectAll"),
                                       action: #selector(selectAllWindows(_:)),
                                       keyEquivalent: ""))
        contextMenu.addItem(NSMenuItem(title: TTL("dialog.broadcast.invertSelection"),
                                       action: #selector(invertSelection(_:)),
                                       keyEquivalent: ""))
        for item in contextMenu.items {
            item.target = self
        }
        windowListView.menu = contextMenu

        // HIG button bar: [Close] --- [Send]
        let buttonBar = DialogButtonBar.build(
            config: DialogButtonBar.Configuration(
                okTitle: "dialog.broadcast.send",
                cancelTitle: "Close",
                showHelp: false
            ),
            okTarget: self, okAction: #selector(sendAction(_:)),
            cancelTarget: self, cancelAction: #selector(closeAction(_:))
        )
        let buttonRow = buttonBar.bar

        // Layout
        let optionRow = NSStackView(views: [sendToThisOnlyCheck, sendEnterCheck, realtimeCheck])
        optionRow.translatesAutoresizingMaskIntoConstraints = false
        optionRow.orientation = .horizontal
        optionRow.spacing = 16

        let stack = NSStackView(views: [
            commandLabel, commandField, optionRow,
            windowListLabel, scrollView, buttonRow
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        container.addSubview(stack)

        let m: CGFloat = 16
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: m),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m),
            commandField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        // Use content-driven sizing — window expands for longer localized labels
        let vc = NSViewController()
        vc.view = container
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true)
        win.contentViewController = vc
        win.title = TTL("dialog.broadcast.title")
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 400, height: 300)
        self.window = win
    }

    // MARK: - Window List Management

    private func refreshWindowList() {
        windowEntries = []
        for (index, w) in NSApp.windows.enumerated() {
            if w.isVisible && !w.isSheet && w !== window && !w.title.isEmpty {
                windowEntries.append(BroadcastWindowEntry(
                    windowID: index,
                    title: w.title,
                    selected: true))
            }
        }
        windowListView?.reloadData()
    }

    // MARK: - Actions

    @objc private func sendAction(_ sender: Any?) {
        let command = commandField.stringValue
        guard !command.isEmpty else { return }

        // Save to history
        if !settings.broadcastHistory.contains(command) {
            settings.broadcastHistory.insert(command, at: 0)
            if settings.broadcastHistory.count > 50 {
                settings.broadcastHistory = Array(settings.broadcastHistory.prefix(50))
            }
            commandField.insertItem(withObjectValue: command, at: 0)
        }

        // Save options
        settings.broadcastSendToThisOnly = sendToThisOnlyCheck.state == .on
        settings.broadcastSendEnter = sendEnterCheck.state == .on
        settings.broadcastRealtime = realtimeCheck.state == .on

        let selectedIDs = windowEntries.filter { $0.selected }.map { $0.windowID }
        let sendEnter = sendEnterCheck.state == .on
        let realtime = realtimeCheck.state == .on

        onSend?(command, selectedIDs, sendEnter, realtime)
    }

    @objc private func closeAction(_ sender: Any?) {
        close()
    }

    // MARK: - Context Menu Actions

    @objc private func bringToFront(_ sender: Any?) {
        let row = windowListView.clickedRow
        guard row >= 0 && row < windowEntries.count else { return }
        let entry = windowEntries[row]
        let windows = NSApp.windows
        if entry.windowID < windows.count {
            windows[entry.windowID].makeKeyAndOrderFront(nil)
        }
    }

    @objc private func minimizeSelected(_ sender: Any?) {
        let row = windowListView.clickedRow
        guard row >= 0 && row < windowEntries.count else { return }
        let entry = windowEntries[row]
        let windows = NSApp.windows
        if entry.windowID < windows.count {
            windows[entry.windowID].miniaturize(nil)
        }
    }

    @objc private func selectAllWindows(_ sender: Any?) {
        for i in 0..<windowEntries.count {
            windowEntries[i].selected = true
        }
        windowListView.reloadData()
    }

    @objc private func invertSelection(_ sender: Any?) {
        for i in 0..<windowEntries.count {
            windowEntries[i].selected = !windowEntries[i].selected
        }
        windowListView.reloadData()
    }
}

// MARK: - NSTableView Data Source / Delegate

extension BroadcastDialogController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        windowEntries.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0 && row < windowEntries.count else { return nil }
        let entry = windowEntries[row]
        switch tableColumn?.identifier.rawValue {
        case "check":
            return entry.selected ? NSControl.StateValue.on : NSControl.StateValue.off
        case "title":
            return entry.title
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard tableColumn?.identifier.rawValue == "check",
              row >= 0 && row < windowEntries.count else { return }
        if let state = object as? Int {
            windowEntries[row].selected = (state == NSControl.StateValue.on.rawValue)
        }
    }
}

#endif
