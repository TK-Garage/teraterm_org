/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * DialogCommandProvider.swift
 * TTL dialog box commands extracted from TTLInterpreter.
 * Provides messagebox, yesnobox, inputbox, passwordbox, listbox,
 * statusbox, closesbox, filenamebox, dirnamebox, bringupbox
 * with setdlgpos positioning and sheet/floating-panel display mode.
 */

#if canImport(AppKit)
import AppKit

// MARK: - Display Mode

/// Controls how TTL dialogs are presented.
enum TTLDialogDisplayMode: Equatable {
    /// Show as application-modal dialog (default, matches Windows Tera Term)
    case modal
    /// Show as sheet attached to the parent window
    case sheet
    /// Show as floating panel (non-modal, always on top)
    case floatingPanel
}

// MARK: - DialogCommandProvider

/// Manages TTL macro dialog commands with positioning and display mode support.
class DialogCommandProvider {

    // MARK: - State

    /// Dialog position set by setdlgpos command (-1 = centered/default)
    var posX: Int = -1
    var posY: Int = -1

    /// Display mode for dialogs
    var displayMode: TTLDialogDisplayMode = .modal

    /// Currently visible statusbox panel (singleton – updated, never duplicated)
    private var statusPanel: NSPanel?
    private var statusLabel: NSTextField?

    /// Parent window for sheet display mode
    weak var parentWindow: NSWindow?

    // MARK: - Position Helpers

    /// Apply stored dlgpos to a window. Coordinates use top-left origin
    /// (Windows convention) converted to macOS bottom-left origin.
    private func applyPosition(to window: NSWindow) {
        guard posX >= 0 && posY >= 0 else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        // Convert from top-left origin (Windows) to bottom-left (macOS)
        let macY = screenFrame.maxY - CGFloat(posY) - window.frame.height
        let origin = NSPoint(x: screenFrame.origin.x + CGFloat(posX), y: macY)
        window.setFrameOrigin(origin)
    }

    /// Apply position to an NSAlert's window after it becomes visible.
    private func applyPositionToAlert(_ alert: NSAlert) {
        guard posX >= 0 && posY >= 0 else { return }
        // The alert window is available after layout
        let win = alert.window
        applyPosition(to: win)
    }

    // MARK: - Reset

    /// Reset dialog position to default (centered)
    func resetPosition() {
        posX = -1
        posY = -1
    }

    // MARK: - MessageBox

    /// Display a message box with OK button.
    /// Sets result = 1 always.
    func showMessageBox(
        message: String,
        title: String,
        completion: @escaping (_ result: Int) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: TTL("dialog.macro.ok"))

            self?.runAlert(alert) { _ in
                completion(1)
            }
        }
    }

    // MARK: - YesNoBox

    /// Display Yes/No confirmation.
    /// Sets result = 1 (Yes) or 0 (No).
    func showYesNoBox(
        message: String,
        title: String,
        completion: @escaping (_ result: Int) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: TTL("dialog.macro.yes"))
            alert.addButton(withTitle: TTL("dialog.macro.no"))

            self?.runAlert(alert) { response in
                completion(response == .alertFirstButtonReturn ? 1 : 0)
            }
        }
    }

    // MARK: - InputBox / PasswordBox

    /// Display input dialog with text field or secure text field.
    /// Sets result = 1 (OK) / 0 (Cancel), inputstr = entered text.
    func showInputBox(
        prompt: String,
        title: String,
        defaultValue: String = "",
        isPassword: Bool = false,
        completion: @escaping (_ result: Int, _ inputStr: String) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = prompt
            alert.addButton(withTitle: TTL("dialog.macro.ok"))
            alert.addButton(withTitle: TTL("dialog.macro.cancel"))

            let inputField: NSTextField
            if isPassword {
                inputField = NSView.makeSecureTextField(placeholder: "", width: nil)
            } else {
                inputField = NSView.makeTextField(value: defaultValue)
            }
            // NSAlert sizes its accessoryView by frame, not Auto Layout.
            // Set an explicit frame so the field is visible inside the alert.
            inputField.translatesAutoresizingMaskIntoConstraints = true
            inputField.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
            alert.accessoryView = inputField
            alert.window.initialFirstResponder = inputField

            self?.runAlert(alert) { response in
                if response == .alertFirstButtonReturn {
                    completion(1, inputField.stringValue)
                } else {
                    completion(0, "")
                }
            }
        }
    }

    // MARK: - ListBox

    /// Display list selection dialog.
    /// Sets result = selected index (1-based) or 0 (cancel), inputstr = selected item.
    func showListBox(
        items: [String],
        title: String,
        completion: @escaping (_ result: Int, _ inputStr: String) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.addButton(withTitle: TTL("dialog.macro.ok"))
            alert.addButton(withTitle: TTL("dialog.macro.cancel"))

            // Build table view inside scroll view.
            // NSAlert sizes its accessoryView by frame, not Auto Layout,
            // so we use explicit frame-based sizing throughout.
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            scrollView.hasVerticalScroller = true
            scrollView.borderType = .bezelBorder
            scrollView.autoresizingMask = [.width, .height]

            let tableView = NSTableView()
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
            column.title = ""
            column.width = 280
            tableView.addTableColumn(column)
            tableView.headerView = nil
            tableView.allowsMultipleSelection = false

            let dataSource = DialogListBoxDataSource(items: items)
            tableView.dataSource = dataSource
            tableView.delegate = dataSource
            tableView.reloadData()

            // Select first item by default
            if !items.isEmpty {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }

            scrollView.documentView = tableView
            alert.accessoryView = scrollView

            self?.runAlert(alert) { response in
                if response == .alertFirstButtonReturn && tableView.selectedRow >= 0 {
                    let idx = tableView.selectedRow
                    completion(idx + 1, items[idx])
                } else {
                    completion(0, "")
                }
            }
        }
    }

    // MARK: - StatusBox (Non-modal)

    /// Display or update a non-modal status box.
    /// If a status box is already showing, update its message (no duplicate).
    func showStatusBox(message: String, title: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let panel = self.statusPanel, panel.isVisible {
                // Update existing panel
                panel.title = title
                self.statusLabel?.stringValue = message
                if self.posX >= 0 && self.posY >= 0 {
                    self.applyPosition(to: panel)
                }
                return
            }

            // Create new floating panel with Auto Layout content
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(wrappingLabelWithString: message)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isEditable = false
            label.isSelectable = false
            label.alignment = .center
            label.font = NSFont.systemFont(ofSize: 13)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            container.addSubview(label)

            let m = DialogLayout.margin
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: m),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m),
                container.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
                container.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            ])

            let vc = NSViewController()
            vc.view = container
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: true)
            panel.contentViewController = vc
            panel.title = title
            panel.level = .floating
            panel.isReleasedWhenClosed = false

            self.statusPanel = panel
            self.statusLabel = label

            // Auto Layout を確定してから位置を決定する
            panel.layoutIfNeeded()

            if self.posX >= 0 && self.posY >= 0 {
                self.applyPosition(to: panel)
            } else if let parent = self.parentWindow, parent.isVisible {
                // 親ウィンドウの中央に配置
                let parentFrame = parent.frame
                let panelSize = panel.frame.size
                let x = parentFrame.midX - panelSize.width / 2
                let y = parentFrame.midY - panelSize.height / 2
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                panel.center()
            }

            panel.orderFront(nil)
        }
    }

    /// Close the status box if visible.
    func closeStatusBox() {
        DispatchQueue.main.async { [weak self] in
            self?.statusPanel?.close()
            self?.statusPanel = nil
            self?.statusLabel = nil
        }
    }

    /// Whether a status box is currently showing.
    var isStatusBoxVisible: Bool {
        return statusPanel?.isVisible ?? false
    }

    // MARK: - FilenameBox

    /// Display file selection dialog.
    /// Sets result = 1 (selected) / 0 (cancel), sets selected path via callback.
    func showFilenameBox(
        title: String,
        isSave: Bool = false,
        completion: @escaping (_ result: Int, _ path: String) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            if isSave {
                let panel = NSSavePanel()
                panel.title = title
                if let pos = self, pos.posX >= 0 && pos.posY >= 0 {
                    // Pre-position before display
                    panel.setFrameOrigin(NSPoint(x: CGFloat(pos.posX), y: CGFloat(pos.posY)))
                }
                let response = panel.runModal()
                if response == .OK, let url = panel.url {
                    completion(1, url.path)
                } else {
                    completion(0, "")
                }
            } else {
                let panel = NSOpenPanel()
                panel.title = title
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                if let pos = self, pos.posX >= 0 && pos.posY >= 0 {
                    panel.setFrameOrigin(NSPoint(x: CGFloat(pos.posX), y: CGFloat(pos.posY)))
                }
                let response = panel.runModal()
                if response == .OK, let url = panel.url {
                    completion(1, url.path)
                } else {
                    completion(0, "")
                }
            }
        }
    }

    // MARK: - DirnameBox

    /// Display folder selection dialog.
    /// Sets result = 1 (selected) / 0 (cancel), sets selected path via callback.
    func showDirnameBox(
        title: String,
        completion: @escaping (_ result: Int, _ path: String) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            let panel = NSOpenPanel()
            panel.title = title
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            if let pos = self, pos.posX >= 0 && pos.posY >= 0 {
                panel.setFrameOrigin(NSPoint(x: CGFloat(pos.posX), y: CGFloat(pos.posY)))
            }
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                completion(1, url.path)
            } else {
                completion(0, "")
            }
        }
    }

    // MARK: - BringupBox

    /// Bring the application or specified window to the front.
    func bringupBox() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.mainWindow {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Alert Runner (Sheet / Modal / Floating)

    /// Run an NSAlert using the current display mode and apply positioning.
    private func runAlert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        switch displayMode {
        case .sheet:
            if let parent = parentWindow {
                alert.beginSheetModal(for: parent) { response in
                    completion(response)
                }
                return
            }
            // Fall through to modal if no parent window
            fallthrough

        case .modal:
            applyPositionToAlert(alert)
            let response = alert.runModal()
            completion(response)

        case .floatingPanel:
            // For floating mode, still use modal as the macro is paused
            applyPositionToAlert(alert)
            alert.window.level = .floating
            let response = alert.runModal()
            completion(response)
        }
    }

    // MARK: - Cleanup

    /// Close all open dialog resources (call on interpreter stop)
    func cleanup() {
        closeStatusBox()
        resetPosition()
    }
}

// MARK: - ListBox Data Source

class DialogListBoxDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let items: [String]

    init(items: [String]) {
        self.items = items
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0 && row < items.count else { return nil }
        return items[row]
    }
}

#endif
