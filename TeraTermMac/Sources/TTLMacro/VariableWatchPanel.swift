/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * VariableWatchPanel.swift
 * Floating utility panel that displays macro variable values in real-time
 * during debugger step execution. Uses NSTableView with name/value columns.
 */

#if canImport(AppKit)
import AppKit

// MARK: - VariableWatchPanel

final class VariableWatchPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: - Data

    private var variables: [(name: String, value: String)] = []
    private var filterText: String = ""

    // MARK: - UI Elements

    private var panel: NSPanel?
    private var tableView: NSTableView?
    private var searchField: NSSearchField?

    // MARK: - Lifecycle

    deinit {
        close()
    }

    /// Show the variable watch panel. Creates it on first call.
    func show() {
        if panel == nil {
            buildPanel()
        }
        panel?.orderFront(nil)
    }

    /// Hide the panel without destroying it.
    func hide() {
        panel?.orderOut(nil)
    }

    /// Close and release the panel.
    func close() {
        panel?.orderOut(nil)
        panel = nil
        tableView = nil
        searchField = nil
    }

    /// Whether the panel is currently visible.
    var isVisible: Bool {
        return panel?.isVisible ?? false
    }

    // MARK: - Data Update

    /// Update the displayed variables. Safe to call from any thread.
    /// Sorts alphabetically by variable name.
    func updateVariables(_ vars: [String: String]) {
        let sorted = vars.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        let update: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.variables = sorted.map { (name: $0.key, value: $0.value) }
            self.applyFilter()
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    // MARK: - Panel Construction

    private func buildPanel() {
        // --- Search / Filter Field ---
        let search = NSSearchField()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholderString = "Filter variables..."
        search.target = self
        search.action = #selector(searchFieldChanged(_:))
        search.sendsSearchStringImmediately = true
        self.searchField = search

        // --- Table View ---
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Variable"
        nameColumn.width = 140
        nameColumn.minWidth = 80

        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueColumn.title = "Value"
        valueColumn.width = 220
        valueColumn.minWidth = 80

        let tv = NSTableView()
        tv.addTableColumn(nameColumn)
        tv.addTableColumn(valueColumn)
        tv.dataSource = self
        tv.delegate = self
        tv.usesAlternatingRowBackgroundColors = true
        tv.rowHeight = 20
        tv.allowsColumnResizing = true
        tv.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tv.headerView = NSTableHeaderView()
        if #available(macOS 11.0, *) {
            tv.style = .inset
        }
        self.tableView = tv

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tv
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        // --- Layout ---
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(search)
        container.addSubview(scrollView)

        let pad: CGFloat = 8
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: container.topAnchor, constant: pad),
            search.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            search.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),

            scrollView.topAnchor.constraint(equalTo: search.bottomAnchor, constant: pad),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])

        // --- Panel ---
        let vc = NSViewController()
        vc.view = container
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: true)
        p.contentViewController = vc
        p.title = "Variable Watch"
        p.isFloatingPanel = true
        p.level = .floating
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.minSize = NSSize(width: 300, height: 200)

        // Position to the right of center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX + 100
            let y = screenFrame.midY - 160
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = p
    }

    // MARK: - Filter

    private var filteredVariables: [(name: String, value: String)] = []

    private func applyFilter() {
        if filterText.isEmpty {
            filteredVariables = variables
        } else {
            let lower = filterText.lowercased()
            filteredVariables = variables.filter {
                $0.name.lowercased().contains(lower) || $0.value.lowercased().contains(lower)
            }
        }
        tableView?.reloadData()
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        filterText = sender.stringValue
        applyFilter()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredVariables.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredVariables.count else { return nil }

        let entry = filteredVariables[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("name")

        let cellView: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cellView = existing
        } else {
            let cv = NSTableCellView()
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            tf.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            cv.addSubview(tf)
            cv.textField = tf
            cv.identifier = identifier
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            ])
            cellView = cv
        }

        if identifier.rawValue == "name" {
            cellView.textField?.stringValue = entry.name
            cellView.textField?.textColor = .labelColor
        } else {
            cellView.textField?.stringValue = entry.value
            cellView.textField?.textColor = .secondaryLabelColor
        }

        return cellView
    }
}

#endif
