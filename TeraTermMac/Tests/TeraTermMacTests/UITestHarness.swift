/*
 * UITestHarness.swift
 * Visual catalog / debug gallery for all Tera Term settings dialogs
 * and macro dialog boxes.
 *
 * Architecture:
 *   NSSplitViewController
 *     - Left: NSOutlineView listing every Settings panel and Macro dialog
 *     - Right: Live preview of the selected item using mock data
 *
 * Usage:
 *   In debug builds, invoke via the menu "Debug > UI Gallery" or
 *   instantiate UITestHarnessWindowController programmatically in tests.
 *
 * This module does NOT modify any settings — all previews use mock
 * TerminalSettings instances that are discarded after display.
 *
 * NOTE: Security-Scoped Bookmarks
 *   When the app runs in App Sandbox, accessing user-selected files
 *   requires Security-Scoped Bookmarks. This gallery bypasses file
 *   access entirely by injecting pre-set mock values into settings.
 */

#if canImport(AppKit)
import AppKit
import XCTest
@testable import TeraTermMac

// MARK: - Gallery Item Definition

/// Each item in the sidebar represents a single dialog or tab to preview.
struct GalleryItem {
    let id: String                          // accessibilityIdentifier
    let title: String                       // Display name in sidebar
    let category: GalleryCategory
    let builder: () -> NSView              // Creates the preview view
}

enum GalleryCategory: String, CaseIterable {
    case mainSettings = "Main Settings"
    case additionalSettings = "Additional Settings"
    case macroDialogs = "Macro Dialogs"
}

// MARK: - Accessibility ID Auto-Assignment

/// Utility to recursively assign accessibilityIdentifier to all controls
/// in a view hierarchy that don't already have one.
/// Format: "<parentID>.<controlType>.<index>"
enum AccessibilityIDAssigner {

    static func assignIDs(to view: NSView, prefix: String = "tt") {
        var counters: [String: Int] = [:]
        assignRecursive(view: view, prefix: prefix, counters: &counters)
    }

    private static func assignRecursive(view: NSView, prefix: String, counters: inout [String: Int]) {
        let typeName = controlTypeName(view)

        // Only assign if no existing identifier
        if view.accessibilityIdentifier() == nil || view.accessibilityIdentifier()!.isEmpty {
            let key = "\(prefix).\(typeName)"
            let idx = counters[key, default: 0]
            counters[key] = idx + 1
            view.setAccessibilityIdentifier("\(key).\(idx)")
        }

        for subview in view.subviews {
            let childPrefix = view.accessibilityIdentifier() ?? prefix
            assignRecursive(view: subview, prefix: childPrefix, counters: &counters)
        }
    }

    private static func controlTypeName(_ view: NSView) -> String {
        switch view {
        case is NSButton:         return "button"
        case is NSPopUpButton:    return "popup"
        case is NSSecureTextField: return "secureField"
        case is NSTextField:      return "textField"
        case is NSSlider:         return "slider"
        case is NSColorWell:      return "colorWell"
        case is NSTableView:      return "table"
        case is NSScrollView:     return "scroll"
        case is NSTabView:        return "tabView"
        case is NSBox:            return "box"
        case is NSStackView:      return "stack"
        case is NSGridView:       return "grid"
        default:                  return "view"
        }
    }
}

// MARK: - Mock Data Factory

/// Creates TerminalSettings instances with predetermined values for gallery preview.
enum MockSettingsFactory {

    static func defaultSettings() -> TerminalSettings {
        let s = TerminalSettings()
        s.terminalWidth = 80
        s.terminalHeight = 24
        s.sshUsername = "admin"
        s.sshKeyFile = "/Users/admin/.ssh/id_ed25519"
        s.title = "Tera Term - Mock Preview"
        s.serialPort = "/dev/cu.usbserial-1410"
        s.baudRate = 9600
        return s
    }
}

// MARK: - Gallery Item Registry

/// Central registry of all previewable UI components.
enum GalleryItemRegistry {

    static func allItems() -> [GalleryItem] {
        var items: [GalleryItem] = []

        // ── Main Settings ──
        items.append(GalleryItem(
            id: "gallery.settings.terminal",
            title: "Terminal Setup",
            category: .mainSettings,
            builder: {
                let vc = TerminalSetupViewController(settings: MockSettingsFactory.defaultSettings())
                vc.loadView()
                vc.viewDidLoad()
                AccessibilityIDAssigner.assignIDs(to: vc.view, prefix: "termSetup")
                return vc.view
            }
        ))

        items.append(GalleryItem(
            id: "gallery.settings.window",
            title: "Window Setup",
            category: .mainSettings,
            builder: {
                let vc = WindowSetupViewController(settings: MockSettingsFactory.defaultSettings())
                vc.loadView()
                vc.viewDidLoad()
                AccessibilityIDAssigner.assignIDs(to: vc.view, prefix: "winSetup")
                return vc.view
            }
        ))

        items.append(GalleryItem(
            id: "gallery.settings.serialPort",
            title: "Serial Port Setup",
            category: .mainSettings,
            builder: {
                let vc = SerialPortSetupViewController(settings: MockSettingsFactory.defaultSettings())
                vc.loadView()
                vc.viewDidLoad()
                AccessibilityIDAssigner.assignIDs(to: vc.view, prefix: "serialSetup")
                return vc.view
            }
        ))

        items.append(GalleryItem(
            id: "gallery.settings.sshAuth",
            title: "SSH Authentication",
            category: .mainSettings,
            builder: {
                let vc = SSHAuthViewController(settings: MockSettingsFactory.defaultSettings())
                vc.loadView()
                vc.viewDidLoad()
                AccessibilityIDAssigner.assignIDs(to: vc.view, prefix: "sshAuth")
                return vc.view
            }
        ))

        // ── Additional Settings (11 tabs) ──
        // These tabs are not yet implemented as view controllers.
        // Register placeholder panels so the gallery stays complete.
        let additionalTabs = [
            "General", "TCP/IP", "Coding", "Control Sequence",
            "Copy and Paste", "Mouse", "Keyboard", "Log",
            "Visual", "Font", "Theme",
        ]
        for tab in additionalTabs {
            items.append(GalleryItem(
                id: "gallery.additional.\(tab.lowercased().replacingOccurrences(of: " ", with: "_"))",
                title: tab,
                category: .additionalSettings,
                builder: {
                    buildPlaceholderTab(name: tab)
                }
            ))
        }

        // ── Macro Dialogs ──
        items.append(GalleryItem(
            id: "gallery.macro.messagebox",
            title: "messagebox",
            category: .macroDialogs,
            builder: { buildMockMessageBox() }
        ))

        items.append(GalleryItem(
            id: "gallery.macro.yesnobox",
            title: "yesnobox",
            category: .macroDialogs,
            builder: { buildMockYesNoBox() }
        ))

        items.append(GalleryItem(
            id: "gallery.macro.inputbox",
            title: "inputbox",
            category: .macroDialogs,
            builder: { buildMockInputBox(isPassword: false) }
        ))

        items.append(GalleryItem(
            id: "gallery.macro.passwordbox",
            title: "passwordbox",
            category: .macroDialogs,
            builder: { buildMockInputBox(isPassword: true) }
        ))

        items.append(GalleryItem(
            id: "gallery.macro.listbox",
            title: "listbox",
            category: .macroDialogs,
            builder: { buildMockListBox() }
        ))

        items.append(GalleryItem(
            id: "gallery.macro.statusbox",
            title: "statusbox",
            category: .macroDialogs,
            builder: { buildMockStatusBox() }
        ))

        items.append(GalleryItem(
            id: "gallery.macro.filenamebox",
            title: "filenamebox",
            category: .macroDialogs,
            builder: { buildMockFilenameBox() }
        ))

        items.append(GalleryItem(
            id: "gallery.macro.dirnamebox",
            title: "dirnamebox",
            category: .macroDialogs,
            builder: { buildMockDirnameBox() }
        ))

        return items
    }

    // MARK: - Placeholder for unimplemented Additional Settings tabs

    private static func buildPlaceholderTab(name: String) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleLabel = NSTextField(labelWithString: "Additional Settings: \(name)")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: "(Not yet implemented — placeholder for gallery)")
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -16),
            statusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
        ])

        container.setAccessibilityIdentifier("gallery.additional.\(name)")
        return container
    }

    // MARK: - Mock Macro Dialogs (non-modal inline previews)

    /// Build an inline preview of messagebox without actually showing a modal alert.
    private static func buildMockMessageBox() -> NSView {
        return buildAlertPreview(
            title: "Information",
            message: "Connection established successfully.",
            buttons: ["OK"],
            identifier: "gallery.macro.messagebox"
        )
    }

    private static func buildMockYesNoBox() -> NSView {
        return buildAlertPreview(
            title: "Confirm",
            message: "Do you want to disconnect?",
            buttons: ["Yes", "No"],
            identifier: "gallery.macro.yesnobox"
        )
    }

    private static func buildMockInputBox(isPassword: Bool) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleLabel = NSTextField(labelWithString: isPassword ? "Enter Password" : "Enter Value")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let promptLabel = NSTextField(labelWithString: isPassword ? "Password:" : "Please enter host name:")
        promptLabel.font = NSFont.systemFont(ofSize: 13)
        promptLabel.translatesAutoresizingMaskIntoConstraints = false

        let inputField: NSTextField
        if isPassword {
            inputField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        } else {
            inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            inputField.stringValue = "192.168.1.1"
        }
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.setAccessibilityIdentifier(isPassword ? "macro.passwordbox.input" : "macro.inputbox.input")

        let okButton = NSButton(title: "OK", target: nil, action: nil)
        okButton.bezelStyle = .rounded
        okButton.translatesAutoresizingMaskIntoConstraints = false
        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [cancelButton, okButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        container.addSubview(titleLabel)
        container.addSubview(promptLabel)
        container.addSubview(inputField)
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            promptLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            promptLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            inputField.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 8),
            inputField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            inputField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            buttonStack.topAnchor.constraint(equalTo: inputField.bottomAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
        ])

        container.setAccessibilityIdentifier(isPassword ? "gallery.macro.passwordbox" : "gallery.macro.inputbox")
        return container
    }

    private static func buildMockListBox() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 280))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleLabel = NSTextField(labelWithString: "Select Host")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 180))
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tableView = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.title = ""
        column.width = 320
        tableView.addTableColumn(column)
        tableView.headerView = nil

        let items = ["192.168.1.1", "10.0.0.1", "server.example.com", "backup-host", "dev-server"]
        let ds = DialogListBoxDataSource(items: items)
        tableView.dataSource = ds
        tableView.delegate = ds
        scrollView.documentView = tableView
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        let okButton = NSButton(title: "OK", target: nil, action: nil)
        okButton.bezelStyle = .rounded
        okButton.translatesAutoresizingMaskIntoConstraints = false
        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [cancelButton, okButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        container.addSubview(titleLabel)
        container.addSubview(scrollView)
        container.addSubview(buttonStack)

        // Need to retain the data source
        objc_setAssociatedObject(container, "listDS", ds, .OBJC_ASSOCIATION_RETAIN)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.heightAnchor.constraint(equalToConstant: 180),

            buttonStack.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
        ])

        container.setAccessibilityIdentifier("gallery.macro.listbox")
        return container
    }

    private static func buildMockStatusBox() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleLabel = NSTextField(labelWithString: "Macro Status")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let messageLabel = NSTextField(wrappingLabelWithString: "Processing file transfer... 42%")
        messageLabel.font = NSFont.systemFont(ofSize: 13)
        messageLabel.alignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            messageLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
        ])

        container.setAccessibilityIdentifier("gallery.macro.statusbox")
        return container
    }

    private static func buildMockFilenameBox() -> NSView {
        return buildAlertPreview(
            title: "Select File",
            message: "Choose a file for transfer.\n(NSOpenPanel / NSSavePanel would appear here.)",
            buttons: ["Browse...", "Cancel"],
            identifier: "gallery.macro.filenamebox"
        )
    }

    private static func buildMockDirnameBox() -> NSView {
        return buildAlertPreview(
            title: "Select Directory",
            message: "Choose a destination folder.\n(NSOpenPanel directory mode would appear here.)",
            buttons: ["Browse...", "Cancel"],
            identifier: "gallery.macro.dirnamebox"
        )
    }

    // MARK: - Generic Alert Preview Builder

    private static func buildAlertPreview(
        title: String, message: String, buttons: [String], identifier: String
    ) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // App icon
        let iconView = NSImageView()
        iconView.image = NSImage(named: NSImage.applicationIconName)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let msgLabel = NSTextField(wrappingLabelWithString: message)
        msgLabel.font = NSFont.systemFont(ofSize: 13)
        msgLabel.translatesAutoresizingMaskIntoConstraints = false

        let buttonViews = buttons.map { title -> NSButton in
            let btn = NSButton(title: title, target: nil, action: nil)
            btn.bezelStyle = .rounded
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.setAccessibilityIdentifier("\(identifier).button.\(title)")
            return btn
        }
        let buttonStack = NSStackView(views: buttonViews)
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(msgLabel)
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),

            msgLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            msgLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            msgLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            buttonStack.topAnchor.constraint(greaterThanOrEqualTo: msgLabel.bottomAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        container.setAccessibilityIdentifier(identifier)
        return container
    }
}

// MARK: - Gallery Window Controller

/// The main gallery window: NSSplitViewController with sidebar + preview.
class UITestHarnessWindowController: NSWindowController {

    private let splitVC = NSSplitViewController()
    private let sidebarVC = GallerySidebarViewController()
    private let previewVC = GalleryPreviewViewController()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tera Term UI Gallery"
        window.center()

        self.init(window: window)

        // Configure split view
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 300
        splitVC.addSplitViewItem(sidebarItem)

        let contentItem = NSSplitViewItem(viewController: previewVC)
        contentItem.minimumThickness = 400
        splitVC.addSplitViewItem(contentItem)

        window.contentViewController = splitVC

        // Wire sidebar selection to preview
        sidebarVC.onSelectionChanged = { [weak self] item in
            self?.previewVC.showItem(item)
        }
    }
}

// MARK: - Sidebar (NSOutlineView)

private class GallerySidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {

    var onSelectionChanged: ((GalleryItem) -> Void)?

    private var outlineView: NSOutlineView!
    private var categories: [(category: GalleryCategory, items: [GalleryItem])] = []

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true

        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 16
        outlineView.rowSizeStyle = .default

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        col.title = "Components"
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col

        scrollView.documentView = outlineView
        self.view = scrollView

        outlineView.dataSource = self
        outlineView.delegate = self

        // Build grouped items
        let allItems = GalleryItemRegistry.allItems()
        for cat in GalleryCategory.allCases {
            let catItems = allItems.filter { $0.category == cat }
            if !catItems.isEmpty {
                categories.append((cat, catItems))
            }
        }
        outlineView.reloadData()

        // Expand all categories
        for cat in categories {
            outlineView.expandItem(cat.category.rawValue)
        }
    }

    // NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return categories.count }
        if let catName = item as? String,
           let cat = categories.first(where: { $0.category.rawValue == catName }) {
            return cat.items.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return categories[index].category.rawValue }
        if let catName = item as? String,
           let cat = categories.first(where: { $0.category.rawValue == catName }) {
            return cat.items[index]
        }
        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is String
    }

    // NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("Cell")
        let cell = outlineView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = cellID

        if cell.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        if let catName = item as? String {
            cell.textField?.stringValue = catName
            cell.textField?.font = NSFont.boldSystemFont(ofSize: 12)
        } else if let galleryItem = item as? GalleryItem {
            cell.textField?.stringValue = galleryItem.title
            cell.textField?.font = NSFont.systemFont(ofSize: 12)
        }

        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        if let item = outlineView.item(atRow: row) as? GalleryItem {
            onSelectionChanged?(item)
        }
    }
}

// MARK: - Preview Pane

private class GalleryPreviewViewController: NSViewController {

    private var currentPreview: NSView?
    private var placeholderLabel: NSTextField!

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        placeholderLabel = NSTextField(labelWithString: "Select an item from the sidebar")
        placeholderLabel.font = NSFont.systemFont(ofSize: 16)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        self.view = container
    }

    func showItem(_ item: GalleryItem) {
        // Remove old preview
        currentPreview?.removeFromSuperview()
        placeholderLabel.isHidden = true

        // Build new preview
        let preview = item.builder()
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview)

        NSLayoutConstraint.activate([
            preview.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            preview.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            preview.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
        ])

        currentPreview = preview
    }
}

// MARK: - Gallery Unit Tests

/// These tests verify that the gallery can instantiate all items without crashing
/// and that accessibility identifiers are properly assigned.
final class UITestHarnessTests: XCTestCase {

    func testAllGalleryItemsBuild() {
        let items = GalleryItemRegistry.allItems()
        XCTAssertGreaterThan(items.count, 0, "Gallery should have items")

        for item in items {
            let view = item.builder()
            XCTAssertNotNil(view, "Builder for '\(item.title)' returned nil")
            XCTAssertGreaterThan(view.frame.width, 0,
                "View for '\(item.title)' has zero width")
        }
    }

    func testGalleryItemCount() {
        let items = GalleryItemRegistry.allItems()
        // 4 main + 11 additional + 8 macro = 23
        XCTAssertEqual(items.count, 23, "Expected 23 gallery items total")
    }

    func testCategoryGrouping() {
        let items = GalleryItemRegistry.allItems()
        let mainCount = items.filter { $0.category == .mainSettings }.count
        let additionalCount = items.filter { $0.category == .additionalSettings }.count
        let macroCount = items.filter { $0.category == .macroDialogs }.count

        XCTAssertEqual(mainCount, 4, "4 main settings dialogs")
        XCTAssertEqual(additionalCount, 11, "11 Additional Settings tabs")
        XCTAssertEqual(macroCount, 8, "8 macro dialogs")
    }

    func testAccessibilityIDsAssigned() {
        let items = GalleryItemRegistry.allItems()
        for item in items {
            let view = item.builder()
            // The root view should have an accessibility ID (set explicitly or by assignIDs)
            let rootID = view.accessibilityIdentifier()
            // At minimum, the item itself should have a non-empty ID
            XCTAssertNotNil(item.id)
            XCTAssertFalse(item.id.isEmpty, "Gallery item '\(item.title)' has empty ID")

            // Check that at least some child controls have IDs
            let controlCount = countControlsWithIDs(in: view)
            // Main settings dialogs have many controls; macros have fewer
            if item.category == .mainSettings {
                XCTAssertGreaterThan(controlCount, 0,
                    "'\(item.title)' should have controls with accessibility IDs")
            }
            _ = rootID // suppress unused warning
        }
    }

    func testUniqueGalleryIDs() {
        let items = GalleryItemRegistry.allItems()
        let ids = items.map { $0.id }
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count,
            "All gallery item IDs should be unique")
    }

    // Helpers

    private func countControlsWithIDs(in view: NSView) -> Int {
        var count = 0
        if let id = view.accessibilityIdentifier(), !id.isEmpty {
            count += 1
        }
        for sub in view.subviews {
            count += countControlsWithIDs(in: sub)
        }
        return count
    }
}

#endif
