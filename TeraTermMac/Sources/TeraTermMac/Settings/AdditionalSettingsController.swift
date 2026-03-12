/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * Additional Settings — tabbed dialog containing 14 setting pages
 * (all Tera Term 5.6 tab sheets; Cygwin tab ported as Local Shell).
 *
 * Tab sheets ported:
 *   IDD_TABSHEET_GENERAL, IDD_TABSHEET_CODING, IDD_TABSHEET_COPYPASTE,
 *   IDD_TABSHEET_SEQUENCE, IDD_TABSHEET_MOUSE, IDD_TABSHEET_LOG,
 *   IDD_TABSHEET_VISUAL, IDD_TABSHEET_FONT, IDD_TABSHEET_TEKFONT,
 *   IDD_TABSHEET_THEME, IDD_TABSHEET_UI, IDD_TABSHEET_PLUGIN,
 *   IDD_TABSHEET_DEBUG, IDD_TABSHEET_CYGWIN (as Local Shell)
 */

#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers

// MARK: - Additional Settings Window Controller

final class AdditionalSettingsController: NSObject {

    private var window: NSWindow?
    private var tabView: NSTabView?
    private var settings: TerminalSettings
    var onApply: (() -> Void)?

    private var tabControllers: [AdditionalSettingsTab] = []

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init()
    }

    func showAsSheet(on parent: NSWindow) {
        if window != nil { return }
        buildWindow()
        guard let win = window else { return }
        parent.beginSheet(win) { [weak self] response in
            if response == .OK {
                self?.applyAll()
                self?.onApply?()
            }
            self?.window = nil
        }
    }

    func showModal() {
        if window != nil { return }
        buildWindow()
        guard let win = window else { return }
        win.center()
        let response = NSApplication.shared.runModal(for: win)
        if response == .OK {
            applyAll()
            onApply?()
        }
        window = nil
    }

    private func applyAll() {
        for tc in tabControllers {
            tc.apply(to: settings)
        }
    }

    private func buildWindow() {
        let tv = NSTabView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.tabViewType = .topTabsBezelBorder

        tabControllers = [
            GeneralTab(settings: settings),
            CodingTab(settings: settings),
            CopyPasteTab(settings: settings),
            SequenceTab(settings: settings),
            MouseTab(settings: settings),
            LogTab(settings: settings),
            VisualTab(settings: settings),
            FontTab(settings: settings),
            TEKFontTab(settings: settings),
            ThemeTab(settings: settings),
            UITab(settings: settings),
            PluginTab(settings: settings),
            LocalShellTab(settings: settings),
            DebugTab(settings: settings),
        ]

        for tc in tabControllers {
            let item = NSTabViewItem(identifier: tc.tabTitle)
            item.label = tc.tabTitle
            item.view = tc.contentView
            tv.addTabViewItem(item)
        }

        // Buttons
        let okButton = NSView.makePushButton(TTL("OK"), keyEquivalent: "\r")
        okButton.target = self
        okButton.action = #selector(okAction(_:))

        let cancelButton = NSView.makePushButton(TTL("Cancel"), keyEquivalent: "\u{1b}")
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction(_:))

        let helpButton = NSView.makePushButton(TTL("Help"))
        helpButton.target = self
        helpButton.action = #selector(helpAction(_:))

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tv)
        container.addSubview(okButton)
        container.addSubview(cancelButton)
        container.addSubview(helpButton)

        let m: CGFloat = 16
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: container.topAnchor, constant: m),
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),

            okButton.topAnchor.constraint(equalTo: tv.bottomAnchor, constant: m),
            okButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -m),
            okButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -m),

            cancelButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: okButton.leadingAnchor, constant: -8),

            helpButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),
            helpButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: m),

            tv.widthAnchor.constraint(greaterThanOrEqualToConstant: 540),
            tv.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),
        ])

        // Content-driven sizing — the window sizes to fit Auto Layout content
        let vc = NSViewController()
        vc.view = container
        let win = NSWindow(contentViewController: vc)
        win.styleMask = [.titled, .closable]
        win.title = TTL("dialog.additionalSettings.title")
        win.isReleasedWhenClosed = false
        self.window = win
        self.tabView = tv
    }

    @objc private func okAction(_ sender: Any?) {
        if let sheet = window, let parent = sheet.sheetParent {
            parent.endSheet(sheet, returnCode: .OK)
        } else if let win = window {
            NSApplication.shared.stopModal(withCode: .OK)
            win.close()
        }
    }

    @objc private func cancelAction(_ sender: Any?) {
        if let sheet = window, let parent = sheet.sheetParent {
            parent.endSheet(sheet, returnCode: .cancel)
        } else if let win = window {
            NSApplication.shared.stopModal(withCode: .cancel)
            win.close()
        }
    }

    @objc private func helpAction(_ sender: Any?) {
        if let url = URL(string: "https://teratermproject.github.io/") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Tab Protocol

protocol AdditionalSettingsTab: AnyObject {
    var tabTitle: String { get }
    var contentView: NSView { get }
    func apply(to settings: TerminalSettings)
}

// MARK: - General Tab (IDD_TABSHEET_GENERAL)

final class GeneralTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.general")
    let contentView = NSView()

    private var sendBreakCheck: NSButton!
    private var broadcastCheck: NSButton!
    private var autoScrollCheck: NSButton!
    private var clearOnResizeCheck: NSButton!
    private var cursorIMECheck: NSButton!
    private var defaultPortPopup: NSPopUpButton!
    private var titleFormatTCPCheck: NSButton!
    private var titleFormatSerialCheck: NSButton!
    private var titleFormatSessionCheck: NSButton!
    private var notifySoundCheck: NSButton!
    private var fileTransferField: NSTextField!
    // New settings
    private var connectingTimeoutField: NSTextField!
    private var clearScreenOnCloseCheck: NSButton!
    private var saveWindowPositionCheck: NSButton!
    private var backWrapCheck: NSButton!
    private var vtCompatTabCheck: NSButton!
    private var scrollThresholdField: NSTextField!
    private var scrollClearScreenCheck: NSButton!
    private var clearBuffOnOpenCheck: NSButton!
    private var autoReconnectCheck: NSButton!
    private var beepOverUsedCountField: NSTextField!
    private var beepOverUsedTimeField: NSTextField!
    private var beepSuppressTimeField: NSTextField!
    private var maxBroadcastHistoryField: NSTextField!
    private var zmodemAutoCheck: NSButton!
    private var confirmDragDropCheck: NSButton!
    private var autoFileRenameCheck: NSButton!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        sendBreakCheck = NSView.makeCheckbox(TTL("dialog.general.sendBreak"))
        broadcastCheck = NSView.makeCheckbox(TTL("dialog.general.broadcast"))
        autoScrollCheck = NSView.makeCheckbox(TTL("dialog.general.autoScroll"), checked: s.autoScrollOnOutput)
        clearOnResizeCheck = NSView.makeCheckbox(TTL("dialog.general.clearOnResize"), checked: s.clearOnResize)
        cursorIMECheck = NSView.makeCheckbox(TTL("dialog.general.cursorIME"), checked: s.cursorChangeIME)

        let portLabel = NSView.makeLabel(TTL("dialog.general.defaultPort"), alignment: .left)
        defaultPortPopup = NSView.makePopUpButton(items: ["TCP/IP", "Serial"], width: 120)
        defaultPortPopup.selectItem(at: s.portType == .serial ? 1 : 0)

        let portRow = NSStackView(views: [portLabel, defaultPortPopup])
        portRow.translatesAutoresizingMaskIntoConstraints = false
        portRow.orientation = .horizontal
        portRow.spacing = 8

        let titleBox = NSView.makeGroupBox(title: TTL("dialog.general.titleFormat"))
        titleFormatTCPCheck = NSView.makeCheckbox(TTL("dialog.general.titleTCPIP"), checked: s.titleFormatTCP)
        titleFormatSerialCheck = NSView.makeCheckbox(TTL("dialog.general.titleSerial"), checked: s.titleFormatSerial)
        titleFormatSessionCheck = NSView.makeCheckbox(TTL("dialog.general.titleSession"), checked: s.titleFormatSession)
        let titleStack = NSStackView(views: [titleFormatTCPCheck, titleFormatSerialCheck, titleFormatSessionCheck])
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 4
        let tc = titleBox.contentView!
        tc.addSubview(titleStack)
        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: tc.topAnchor, constant: 16),
            titleStack.leadingAnchor.constraint(equalTo: tc.leadingAnchor, constant: 12),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: tc.trailingAnchor, constant: -12),
            titleStack.bottomAnchor.constraint(equalTo: tc.bottomAnchor, constant: -8),
        ])

        notifySoundCheck = NSView.makeCheckbox(TTL("dialog.general.notifySound"), checked: s.notifySound)

        let ftLabel = NSView.makeLabel(TTL("dialog.general.fileTransferFolder"), alignment: .left)
        fileTransferField = NSView.makeTextField(value: s.fileTransferFolder)
        let ftRow = NSStackView(views: [ftLabel, fileTransferField])
        ftRow.translatesAutoresizingMaskIntoConstraints = false
        ftRow.orientation = .horizontal
        ftRow.spacing = 8

        // Connection timeout
        let timeoutLabel = NSView.makeLabel(TTL("dialog.general.connectingTimeout"), alignment: .left)
        connectingTimeoutField = NSView.makeNumberField(value: s.connectingTimeout, width: 60)
        let timeoutRow = NSStackView(views: [timeoutLabel, connectingTimeoutField])
        timeoutRow.translatesAutoresizingMaskIntoConstraints = false
        timeoutRow.orientation = .horizontal
        timeoutRow.spacing = 8

        // Misc checkboxes
        clearScreenOnCloseCheck = NSView.makeCheckbox(TTL("dialog.general.clearScreenOnClose"), checked: s.clearScreenOnCloseConnection)
        saveWindowPositionCheck = NSView.makeCheckbox(TTL("dialog.general.saveWindowPosition"), checked: s.saveVTWinPos)
        backWrapCheck = NSView.makeCheckbox(TTL("dialog.general.backWrap"), checked: s.backWrap)
        vtCompatTabCheck = NSView.makeCheckbox(TTL("dialog.general.vtCompatTab"), checked: s.vtCompatTab)

        // Scroll settings
        let scrollThresholdLabel = NSView.makeLabel(TTL("dialog.general.scrollThreshold"), alignment: .left)
        scrollThresholdField = NSView.makeNumberField(value: s.scrollThreshold, width: 60)
        let scrollThresholdRow = NSStackView(views: [scrollThresholdLabel, scrollThresholdField])
        scrollThresholdRow.translatesAutoresizingMaskIntoConstraints = false
        scrollThresholdRow.orientation = .horizontal
        scrollThresholdRow.spacing = 8
        scrollClearScreenCheck = NSView.makeCheckbox(TTL("dialog.general.scrollClearScreen"), checked: s.scrollWindowClearScreen)

        // Serial settings
        clearBuffOnOpenCheck = NSView.makeCheckbox(TTL("dialog.general.clearBuffOnOpen"), checked: s.clearComBuffOnOpen)
        autoReconnectCheck = NSView.makeCheckbox(TTL("dialog.general.autoReconnect"), checked: s.autoComPortReconnect)

        // Beep overuse settings
        let beepBox = NSView.makeGroupBox(title: TTL("dialog.sequence.beep"))
        let beepCountLabel = NSView.makeLabel(TTL("dialog.general.beepOverUsedCount"), alignment: .left)
        beepOverUsedCountField = NSView.makeNumberField(value: s.beepOverUsedCount, width: 50)
        let beepTimeLabel = NSView.makeLabel(TTL("dialog.general.beepOverUsedTime"), alignment: .left)
        beepOverUsedTimeField = NSView.makeNumberField(value: s.beepOverUsedTime, width: 50)
        let beepSuppressLabel = NSView.makeLabel(TTL("dialog.general.beepSuppressTime"), alignment: .left)
        beepSuppressTimeField = NSView.makeNumberField(value: s.beepSuppressTime, width: 50)
        let beepGrid = NSGridView(views: [
            [beepCountLabel, beepOverUsedCountField],
            [beepTimeLabel, beepOverUsedTimeField],
            [beepSuppressLabel, beepSuppressTimeField],
        ])
        beepGrid.translatesAutoresizingMaskIntoConstraints = false
        beepGrid.rowSpacing = 6
        beepGrid.columnSpacing = 8
        let bbc = beepBox.contentView!
        bbc.addSubview(beepGrid)
        NSLayoutConstraint.activate([
            beepGrid.topAnchor.constraint(equalTo: bbc.topAnchor, constant: 16),
            beepGrid.leadingAnchor.constraint(equalTo: bbc.leadingAnchor, constant: 12),
            beepGrid.trailingAnchor.constraint(lessThanOrEqualTo: bbc.trailingAnchor, constant: -12),
            beepGrid.bottomAnchor.constraint(equalTo: bbc.bottomAnchor, constant: -8),
        ])

        // Broadcast history
        let maxBCLabel = NSView.makeLabel(TTL("dialog.general.maxBroadcastHistory"), alignment: .left)
        maxBroadcastHistoryField = NSView.makeNumberField(value: s.maxBroadcastHistory, width: 60)
        let maxBCRow = NSStackView(views: [maxBCLabel, maxBroadcastHistoryField])
        maxBCRow.translatesAutoresizingMaskIntoConstraints = false
        maxBCRow.orientation = .horizontal
        maxBCRow.spacing = 8

        // File transfer
        zmodemAutoCheck = NSView.makeCheckbox(TTL("dialog.general.zmodemAuto"), checked: s.zmodemAutoReceive)
        confirmDragDropCheck = NSView.makeCheckbox(TTL("dialog.general.confirmDragDrop"), checked: s.confirmFileDragAndDrop)
        autoFileRenameCheck = NSView.makeCheckbox(TTL("dialog.general.autoFileRename"), checked: s.autoFileRename)

        let stack = NSStackView(views: [
            sendBreakCheck, broadcastCheck, autoScrollCheck, clearOnResizeCheck,
            cursorIMECheck, portRow, titleBox, notifySoundCheck, ftRow,
            timeoutRow, clearScreenOnCloseCheck, saveWindowPositionCheck,
            backWrapCheck, vtCompatTabCheck,
            scrollThresholdRow, scrollClearScreenCheck,
            clearBuffOnOpenCheck, autoReconnectCheck,
            beepBox, maxBCRow,
            zmodemAutoCheck, confirmDragDropCheck, autoFileRenameCheck
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    func apply(to s: TerminalSettings) {
        s.autoScrollOnOutput = autoScrollCheck.state == .on
        s.clearOnResize = clearOnResizeCheck.state == .on
        s.cursorChangeIME = cursorIMECheck.state == .on
        s.portType = defaultPortPopup.indexOfSelectedItem == 1 ? .serial : .tcpip
        s.titleFormatTCP = titleFormatTCPCheck.state == .on
        s.titleFormatSerial = titleFormatSerialCheck.state == .on
        s.titleFormatSession = titleFormatSessionCheck.state == .on
        s.notifySound = notifySoundCheck.state == .on
        s.fileTransferFolder = fileTransferField.stringValue
        // New settings
        s.connectingTimeout = connectingTimeoutField.integerValue
        s.clearScreenOnCloseConnection = clearScreenOnCloseCheck.state == .on
        s.saveVTWinPos = saveWindowPositionCheck.state == .on
        s.backWrap = backWrapCheck.state == .on
        s.vtCompatTab = vtCompatTabCheck.state == .on
        s.scrollThreshold = scrollThresholdField.integerValue
        s.scrollWindowClearScreen = scrollClearScreenCheck.state == .on
        s.clearComBuffOnOpen = clearBuffOnOpenCheck.state == .on
        s.autoComPortReconnect = autoReconnectCheck.state == .on
        s.beepOverUsedCount = beepOverUsedCountField.integerValue
        s.beepOverUsedTime = beepOverUsedTimeField.integerValue
        s.beepSuppressTime = beepSuppressTimeField.integerValue
        s.maxBroadcastHistory = maxBroadcastHistoryField.integerValue
        s.zmodemAutoReceive = zmodemAutoCheck.state == .on
        s.confirmFileDragAndDrop = confirmDragDropCheck.state == .on
        s.autoFileRename = autoFileRenameCheck.state == .on
    }
}

// MARK: - Coding Tab (IDD_TABSHEET_CODING)

final class CodingTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.coding")
    let contentView = NSView()

    private var recvEncodingPopup: NSPopUpButton!
    private var sendEncodingPopup: NSPopUpButton!
    private var ambiguousWidthPopup: NSPopUpButton!
    private var emojiWidthPopup: NSPopUpButton!
    private var emojiOverrideCheck: NSButton!
    private var fallbackCP932Check: NSButton!

    private let encodingItems = ["UTF-8", "Shift_JIS", "EUC-JP", "ISO-2022-JP"]

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        let recvLabel = NSView.makeLabel(TTL("dialog.coding.receiveEncoding"), alignment: .left)
        recvEncodingPopup = NSView.makePopUpButton(
            items: CharacterEncoding.allCases.map { $0.displayName }, width: 240)
        if let idx = CharacterEncoding.allCases.firstIndex(of: s.encoding) {
            recvEncodingPopup.selectItem(at: idx)
        }

        let sendLabel = NSView.makeLabel(TTL("dialog.coding.sendEncoding"), alignment: .left)
        sendEncodingPopup = NSView.makePopUpButton(
            items: CharacterEncoding.allCases.map { $0.displayName }, width: 240)
        if let idx = CharacterEncoding.allCases.firstIndex(of: s.sendEncoding) {
            sendEncodingPopup.selectItem(at: idx)
        }

        let ambLabel = NSView.makeLabel(TTL("dialog.coding.ambiguousWidth"), alignment: .left)
        ambiguousWidthPopup = NSView.makePopUpButton(items: ["1 (Narrow)", "2 (Wide)"], width: 120)
        ambiguousWidthPopup.selectItem(at: s.unicodeAmbiguousWidth == 2 ? 1 : 0)

        let emojiLabel = NSView.makeLabel(TTL("dialog.coding.emojiWidth"), alignment: .left)
        emojiWidthPopup = NSView.makePopUpButton(items: ["1 (Narrow)", "2 (Wide)"], width: 120)
        emojiWidthPopup.selectItem(at: s.unicodeEmojiWidth == 2 ? 1 : 0)

        emojiOverrideCheck = NSView.makeCheckbox(
            TTL("dialog.coding.emojiOverride"), checked: s.unicodeEmojiOverride)
        fallbackCP932Check = NSView.makeCheckbox(
            TTL("dialog.coding.fallbackCP932"), checked: s.fallbackToCP932)

        let grid = NSGridView(views: [
            [recvLabel, recvEncodingPopup],
            [sendLabel, sendEncodingPopup],
            [ambLabel, ambiguousWidthPopup],
            [emojiLabel, emojiWidthPopup],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        contentView.addSubview(grid)

        contentView.addSubview(emojiOverrideCheck)
        contentView.addSubview(fallbackCP932Check)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            emojiOverrideCheck.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12),
            emojiOverrideCheck.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            fallbackCP932Check.topAnchor.constraint(equalTo: emojiOverrideCheck.bottomAnchor, constant: 6),
            fallbackCP932Check.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        ])
    }

    func apply(to s: TerminalSettings) {
        let allEncodings = CharacterEncoding.allCases
        let recvIdx = recvEncodingPopup.indexOfSelectedItem
        if recvIdx >= 0 && recvIdx < allEncodings.count {
            s.encoding = allEncodings[recvIdx]
        }
        let sendIdx = sendEncodingPopup.indexOfSelectedItem
        if sendIdx >= 0 && sendIdx < allEncodings.count {
            s.sendEncoding = allEncodings[sendIdx]
        }
        s.unicodeAmbiguousWidth = ambiguousWidthPopup.indexOfSelectedItem == 1 ? 2 : 1
        s.unicodeEmojiWidth = emojiWidthPopup.indexOfSelectedItem == 1 ? 2 : 1
        s.unicodeEmojiOverride = emojiOverrideCheck.state == .on
        s.fallbackToCP932 = fallbackCP932Check.state == .on
    }
}

// MARK: - Copy and Paste Tab (IDD_TABSHEET_COPYPASTE)

final class CopyPasteTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.copyPaste")
    let contentView = NSView()

    private var continuedLineCopyCheck: NSButton!
    private var confirmPasteNewLineCheck: NSButton!
    private var delimiterField: NSTextField!
    private var pasteDelayField: NSTextField!
    private var autoTextCopyCheck: NSButton!
    private var disableRightClickPasteCheck: NSButton!
    private var confirmRightClickPasteCheck: NSButton!
    private var disableMiddleClickPasteCheck: NSButton!
    private var leftClickOnlySelectionCheck: NSButton!
    private var trimTrailingNewlineCheck: NSButton!
    private var confirmDangerousClipboardCheck: NSButton!
    private var dangerousKeywordField: NSTextField!
    private var enableSelectionOnActivateCheck: NSButton!
    private var mouseSelectDelayField: NSTextField!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        continuedLineCopyCheck = NSView.makeCheckbox(
            TTL("dialog.copyPaste.continuedLineCopy"), checked: s.continuedLineCopy)
        confirmPasteNewLineCheck = NSView.makeCheckbox(
            TTL("dialog.copyPaste.confirmPasteNewLine"), checked: s.confirmPasteNewLine)
        autoTextCopyCheck = NSView.makeCheckbox(
            TTL("dialog.copyPaste.autoTextCopy"), checked: s.autoTextCopy)

        let delimLabel = NSView.makeLabel(TTL("dialog.copyPaste.delimiterList"), alignment: .left)
        delimiterField = NSView.makeTextField(value: s.delimiterList, width: 200)
        let delimRow = NSStackView(views: [delimLabel, delimiterField])
        delimRow.translatesAutoresizingMaskIntoConstraints = false
        delimRow.orientation = .horizontal
        delimRow.spacing = 8

        let delayLabel = NSView.makeLabel(TTL("dialog.copyPaste.pasteDelay"), alignment: .left)
        pasteDelayField = NSView.makeNumberField(value: s.pasteDelay, width: 60)
        let msLabel = NSView.makeLabel("ms", alignment: .left)
        let delayRow = NSStackView(views: [delayLabel, pasteDelayField, msLabel])
        delayRow.translatesAutoresizingMaskIntoConstraints = false
        delayRow.orientation = .horizontal
        delayRow.spacing = 8

        // New paste settings
        disableRightClickPasteCheck = NSView.makeCheckbox(
            TTL("dialog.copyPaste.disableRightClickPaste"), checked: s.disableRightClickPaste)
        confirmRightClickPasteCheck = NSView.makeCheckbox(
            TTL("dialog.copyPaste.confirmRightClickPaste"), checked: s.confirmRightClickPaste)
        disableMiddleClickPasteCheck = NSView.makeCheckbox(
            TTL("dialog.copyPaste.disableMiddleClickPaste"), checked: s.disableMiddleClickPaste)
        leftClickOnlySelectionCheck = NSView.makeCheckbox(
            TTL("dialog.copyPaste.leftClickOnlySelection"), checked: s.leftClickOnlySelection)
        trimTrailingNewlineCheck = NSView.makeCheckbox(
            TTL("dialog.copyPaste.trimTrailingNewline"), checked: s.trimTrailingNewline)
        confirmDangerousClipboardCheck = NSView.makeCheckbox(
            TTL("dialog.copyPaste.confirmDangerousClipboard"), checked: s.confirmDangerousClipboard)
        enableSelectionOnActivateCheck = NSView.makeCheckbox(
            TTL("dialog.copyPaste.enableSelectionOnActivate"), checked: s.enableSelectionOnActivate)

        let keywordLabel = NSView.makeLabel(TTL("dialog.copyPaste.dangerousKeywordFile"), alignment: .left)
        dangerousKeywordField = NSView.makeTextField(value: s.dangerousKeywordFile, width: 200)
        let keywordRow = NSStackView(views: [keywordLabel, dangerousKeywordField])
        keywordRow.translatesAutoresizingMaskIntoConstraints = false
        keywordRow.orientation = .horizontal
        keywordRow.spacing = 8

        // Mouse paste settings group
        let pasteBox = NSView.makeGroupBox(title: TTL("dialog.copyPaste.pasteSettings"))
        let pasteStack = NSStackView(views: [
            disableRightClickPasteCheck, confirmRightClickPasteCheck,
            disableMiddleClickPasteCheck
        ])
        pasteStack.translatesAutoresizingMaskIntoConstraints = false
        pasteStack.orientation = .vertical
        pasteStack.alignment = .leading
        pasteStack.spacing = 4
        let pc = pasteBox.contentView!
        pc.addSubview(pasteStack)
        NSLayoutConstraint.activate([
            pasteStack.topAnchor.constraint(equalTo: pc.topAnchor, constant: 16),
            pasteStack.leadingAnchor.constraint(equalTo: pc.leadingAnchor, constant: 12),
            pasteStack.trailingAnchor.constraint(lessThanOrEqualTo: pc.trailingAnchor, constant: -12),
            pasteStack.bottomAnchor.constraint(equalTo: pc.bottomAnchor, constant: -8),
        ])

        // Security group
        let secBox = NSView.makeGroupBox(title: TTL("dialog.copyPaste.securitySettings"))
        let secStack = NSStackView(views: [
            confirmDangerousClipboardCheck, keywordRow
        ])
        secStack.translatesAutoresizingMaskIntoConstraints = false
        secStack.orientation = .vertical
        secStack.alignment = .leading
        secStack.spacing = 6
        let sc = secBox.contentView!
        sc.addSubview(secStack)
        NSLayoutConstraint.activate([
            secStack.topAnchor.constraint(equalTo: sc.topAnchor, constant: 16),
            secStack.leadingAnchor.constraint(equalTo: sc.leadingAnchor, constant: 12),
            secStack.trailingAnchor.constraint(lessThanOrEqualTo: sc.trailingAnchor, constant: -12),
            secStack.bottomAnchor.constraint(equalTo: sc.bottomAnchor, constant: -8),
        ])

        let mouseDelayLabel = NSView.makeLabel(TTL("dialog.copyPaste.mouseSelectDelay"), alignment: .left)
        mouseSelectDelayField = NSView.makeNumberField(value: s.mouseSelectStartDelay, width: 60)
        let mouseDelayMs = NSView.makeLabel("ms", alignment: .left)
        let mouseDelayRow = NSStackView(views: [mouseDelayLabel, mouseSelectDelayField, mouseDelayMs])
        mouseDelayRow.translatesAutoresizingMaskIntoConstraints = false
        mouseDelayRow.orientation = .horizontal
        mouseDelayRow.spacing = 8

        let stack = NSStackView(views: [
            continuedLineCopyCheck, confirmPasteNewLineCheck,
            delimRow, delayRow, autoTextCopyCheck,
            pasteBox,
            leftClickOnlySelectionCheck, trimTrailingNewlineCheck,
            enableSelectionOnActivateCheck, mouseDelayRow,
            secBox
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    func apply(to s: TerminalSettings) {
        s.continuedLineCopy = continuedLineCopyCheck.state == .on
        s.confirmPasteNewLine = confirmPasteNewLineCheck.state == .on
        s.delimiterList = delimiterField.stringValue
        s.pasteDelay = pasteDelayField.integerValue
        s.autoTextCopy = autoTextCopyCheck.state == .on
        s.disableRightClickPaste = disableRightClickPasteCheck.state == .on
        s.confirmRightClickPaste = confirmRightClickPasteCheck.state == .on
        s.disableMiddleClickPaste = disableMiddleClickPasteCheck.state == .on
        s.leftClickOnlySelection = leftClickOnlySelectionCheck.state == .on
        s.trimTrailingNewline = trimTrailingNewlineCheck.state == .on
        s.confirmDangerousClipboard = confirmDangerousClipboardCheck.state == .on
        s.dangerousKeywordFile = dangerousKeywordField.stringValue
        s.enableSelectionOnActivate = enableSelectionOnActivateCheck.state == .on
        s.mouseSelectStartDelay = mouseSelectDelayField.integerValue
    }
}

// MARK: - Sequence Tab (IDD_TABSHEET_SEQUENCE)

final class SequenceTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.sequence")
    let contentView = NSView()

    private var mouseEventCheck: NSButton!
    private var titleChangeCheck: NSButton!
    private var titleReportCheck: NSButton!
    private var windowControlCheck: NSButton!
    private var cursorControlCheck: NSButton!
    private var clipboardAccessCheck: NSButton!
    private var beepPopup: NSPopUpButton!
    private var disableControlKeyMouseCheck: NSButton!
    private var titleChangeModePopup: NSPopUpButton!
    private var windowInfoReportCheck: NSButton!
    private var clipboardAccessModePopup: NSPopUpButton!
    private var notifyClipboardAccessCheck: NSButton!
    private var acceptScrollBufferClearCheck: NSButton!
    private var disablePrintSequenceCheck: NSButton!
    // New controls
    private var accept8BitCtrlCheck: NSButton!
    private var send8BitCtrlCheck: NSButton!
    private var alternateScreenCheck: NSButton!
    private var bracketedPasteCheck: NSButton!
    private var bracketedControlOnlyCheck: NSButton!
    private var allowWrongSequenceCheck: NSButton!
    private var maxOSCBufferField: NSTextField!
    private var enableLineModeCheck: NSButton!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        mouseEventCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.mouseEventTracking"), checked: s.mouseTracking)
        disableControlKeyMouseCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.disableControlKeyMouse"), checked: s.disableControlKeyMouseEvent)
        titleChangeCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.titleChanging"), checked: s.titleChangeRequest)

        let titleModeLabel = NSView.makeLabel(TTL("dialog.sequence.titleChangeMode"), alignment: .left)
        titleChangeModePopup = NSView.makePopUpButton(
            items: [TTL("dialog.sequence.titleModeOverwrite"),
                    TTL("dialog.sequence.titleModePrepend"),
                    TTL("dialog.sequence.titleModeAppend")],
            width: 140)
        titleChangeModePopup.selectItem(at: s.titleChangeMode)
        let titleModeRow = NSStackView(views: [titleModeLabel, titleChangeModePopup])
        titleModeRow.translatesAutoresizingMaskIntoConstraints = false
        titleModeRow.orientation = .horizontal
        titleModeRow.spacing = 8

        titleReportCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.titleReport"), checked: s.titleReportRequest)
        windowControlCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.windowControl"), checked: s.windowControlSequence)
        windowInfoReportCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.windowInfoReport"), checked: s.windowInfoReportSequence)
        cursorControlCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.cursorControl"), checked: s.cursorControlSequence)

        // Clipboard access detail
        clipboardAccessCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.clipboardAccess"), checked: s.clipboardAccessFromRemote)
        let clipModeLabel = NSView.makeLabel(TTL("dialog.sequence.clipboardAccessMode"), alignment: .left)
        clipboardAccessModePopup = NSView.makePopUpButton(
            items: [TTL("dialog.sequence.clipOff"),
                    TTL("dialog.sequence.clipReadWrite"),
                    TTL("dialog.sequence.clipReadOnly"),
                    TTL("dialog.sequence.clipWriteOnly")],
            width: 160)
        clipboardAccessModePopup.selectItem(at: s.clipboardAccessMode)
        let clipModeRow = NSStackView(views: [clipModeLabel, clipboardAccessModePopup])
        clipModeRow.translatesAutoresizingMaskIntoConstraints = false
        clipModeRow.orientation = .horizontal
        clipModeRow.spacing = 8

        notifyClipboardAccessCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.notifyClipboardAccess"), checked: s.notifyClipboardAccess)
        acceptScrollBufferClearCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.acceptScrollBufferClear"), checked: s.acceptScrollBufferClear)
        disablePrintSequenceCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.disablePrintSequence"), checked: s.disablePrintSequence)

        let beepLabel = NSView.makeLabel(TTL("dialog.sequence.beep"), alignment: .left)
        beepPopup = NSView.makePopUpButton(
            items: [TTL("dialog.sequence.beepOff"),
                    TTL("dialog.sequence.beepSystem"),
                    TTL("dialog.sequence.beepVisual")],
            width: 140)
        beepPopup.selectItem(at: s.beepType.rawValue)
        let beepRow = NSStackView(views: [beepLabel, beepPopup])
        beepRow.translatesAutoresizingMaskIntoConstraints = false
        beepRow.orientation = .horizontal
        beepRow.spacing = 8

        // New control sequence settings
        accept8BitCtrlCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.accept8BitCtrl"), checked: s.accept8BitCtrl)
        send8BitCtrlCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.send8BitCtrl"), checked: s.send8BitCtrl)
        alternateScreenCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.alternateScreen"), checked: s.alternateScreenBuffer)
        bracketedPasteCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.bracketedPaste"), checked: s.bracketedPasteMode)
        bracketedControlOnlyCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.bracketedControlOnly"), checked: s.bracketedControlOnly)
        allowWrongSequenceCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.allowWrongSequence"), checked: s.allowWrongSequence)
        enableLineModeCheck = NSView.makeCheckbox(
            TTL("dialog.sequence.enableLineMode"), checked: s.enableLineMode)

        let oscLabel = NSView.makeLabel(TTL("dialog.sequence.maxOSCBuffer"), alignment: .left)
        maxOSCBufferField = NSView.makeNumberField(value: s.maxOSCBufferSize, width: 80)
        let oscRow = NSStackView(views: [oscLabel, maxOSCBufferField])
        oscRow.translatesAutoresizingMaskIntoConstraints = false
        oscRow.orientation = .horizontal
        oscRow.spacing = 8

        let stack = NSStackView(views: [
            mouseEventCheck, disableControlKeyMouseCheck,
            titleChangeCheck, titleModeRow,
            titleReportCheck, windowControlCheck, windowInfoReportCheck,
            cursorControlCheck,
            clipboardAccessCheck, clipModeRow, notifyClipboardAccessCheck,
            acceptScrollBufferClearCheck, disablePrintSequenceCheck,
            beepRow,
            accept8BitCtrlCheck, send8BitCtrlCheck,
            alternateScreenCheck, bracketedPasteCheck, bracketedControlOnlyCheck,
            allowWrongSequenceCheck, enableLineModeCheck, oscRow
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    func apply(to s: TerminalSettings) {
        s.mouseTracking = mouseEventCheck.state == .on
        s.disableControlKeyMouseEvent = disableControlKeyMouseCheck.state == .on
        s.titleChangeRequest = titleChangeCheck.state == .on
        s.titleChangeMode = titleChangeModePopup.indexOfSelectedItem
        s.titleReportRequest = titleReportCheck.state == .on
        s.windowControlSequence = windowControlCheck.state == .on
        s.windowInfoReportSequence = windowInfoReportCheck.state == .on
        s.cursorControlSequence = cursorControlCheck.state == .on
        s.clipboardAccessFromRemote = clipboardAccessCheck.state == .on
        s.clipboardAccessMode = clipboardAccessModePopup.indexOfSelectedItem
        s.notifyClipboardAccess = notifyClipboardAccessCheck.state == .on
        s.acceptScrollBufferClear = acceptScrollBufferClearCheck.state == .on
        s.disablePrintSequence = disablePrintSequenceCheck.state == .on
        if let bt = BeepType(rawValue: beepPopup.indexOfSelectedItem) {
            s.beepType = bt
        }
        // New settings
        s.accept8BitCtrl = accept8BitCtrlCheck.state == .on
        s.send8BitCtrl = send8BitCtrlCheck.state == .on
        s.alternateScreenBuffer = alternateScreenCheck.state == .on
        s.bracketedPasteMode = bracketedPasteCheck.state == .on
        s.bracketedControlOnly = bracketedControlOnlyCheck.state == .on
        s.allowWrongSequence = allowWrongSequenceCheck.state == .on
        s.enableLineMode = enableLineModeCheck.state == .on
        s.maxOSCBufferSize = maxOSCBufferField.integerValue
    }
}

// MARK: - Mouse Tab (IDD_TABSHEET_MOUSE)

final class MouseTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.mouse")
    let contentView = NSView()

    private var clickableURLCheck: NSButton!
    private var wheelScrollField: NSTextField!
    private var translateWheelCheck: NSButton!
    private var disableWheelByCtrlCheck: NSButton!
    private var joinSplitURLCheck: NSButton!
    private var joinSplitURLEOLField: NSTextField!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        clickableURLCheck = NSView.makeCheckbox(
            TTL("dialog.mouse.clickableURL"), checked: true)

        let wheelLabel = NSView.makeLabel(TTL("dialog.mouse.wheelScrollLines"), alignment: .left)
        wheelScrollField = NSView.makeNumberField(value: s.mouseWheelScrollLines, width: 60)
        let linesLabel = NSView.makeLabel(TTL("dialog.mouse.lines"), alignment: .left)

        let wheelRow = NSStackView(views: [wheelLabel, wheelScrollField, linesLabel])
        wheelRow.translatesAutoresizingMaskIntoConstraints = false
        wheelRow.orientation = .horizontal
        wheelRow.spacing = 8

        translateWheelCheck = NSView.makeCheckbox(
            TTL("dialog.mouse.translateWheelToCursor"), checked: s.translateWheelToCursor)
        disableWheelByCtrlCheck = NSView.makeCheckbox(
            TTL("dialog.mouse.disableWheelToCursorByCtrl"), checked: s.disableWheelToCursorByCtrl)

        joinSplitURLCheck = NSView.makeCheckbox(
            TTL("dialog.mouse.joinSplitURL"), checked: s.joinSplitURL)
        let eolLabel = NSView.makeLabel(TTL("dialog.mouse.joinSplitURLIgnoreEOL"), alignment: .left)
        joinSplitURLEOLField = NSView.makeTextField(value: s.joinSplitURLIgnoreEOLChar, width: 60)
        let eolRow = NSStackView(views: [eolLabel, joinSplitURLEOLField])
        eolRow.translatesAutoresizingMaskIntoConstraints = false
        eolRow.orientation = .horizontal
        eolRow.spacing = 8

        let stack = NSStackView(views: [
            clickableURLCheck, wheelRow,
            translateWheelCheck, disableWheelByCtrlCheck,
            joinSplitURLCheck, eolRow
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        ])
    }

    func apply(to s: TerminalSettings) {
        s.mouseWheelScrollLines = max(1, wheelScrollField.integerValue)
        s.translateWheelToCursor = translateWheelCheck.state == .on
        s.disableWheelToCursorByCtrl = disableWheelByCtrlCheck.state == .on
        s.joinSplitURL = joinSplitURLCheck.state == .on
        s.joinSplitURLIgnoreEOLChar = joinSplitURLEOLField.stringValue
    }
}

// MARK: - Log Tab (IDD_TABSHEET_LOG)

final class LogTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.log")
    let contentView = NSView()

    private var editorField: NSTextField!
    private var editorArgsField: NSTextField!
    private var defaultNameField: NSTextField!
    private var defaultPathField: NSTextField!
    private var autoStartCheck: NSButton!
    private var binaryCheck: NSButton!
    private var appendCheck: NSButton!
    private var plainTextCheck: NSButton!
    private var hideDialogCheck: NSButton!
    private var screenBufferCheck: NSButton!
    private var timestampCheck: NSButton!
    private var rotateEnabledCheck: NSButton!
    private var rotateSizeField: NSTextField!
    private var rotateStepField: NSTextField!
    private var bomCheck: NSButton!
    private var timestampTypePopup: NSPopUpButton!
    private var timestampFormatField: NSTextField!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        let editorLabel = NSView.makeLabel(TTL("dialog.log.viewEditor"), alignment: .left)
        editorField = NSView.makeTextField(value: s.logViewEditor)
        let editorRow = NSStackView(views: [editorLabel, editorField])
        editorRow.translatesAutoresizingMaskIntoConstraints = false
        editorRow.orientation = .horizontal
        editorRow.spacing = 8

        let argsLabel = NSView.makeLabel(TTL("dialog.log.editorArguments"), alignment: .left)
        editorArgsField = NSView.makeTextField(value: s.logEditorArguments)
        let argsRow = NSStackView(views: [argsLabel, editorArgsField])
        argsRow.translatesAutoresizingMaskIntoConstraints = false
        argsRow.orientation = .horizontal
        argsRow.spacing = 8

        let nameLabel = NSView.makeLabel(TTL("dialog.log.defaultName"), alignment: .left)
        defaultNameField = NSView.makeTextField(value: s.logDefaultName)
        let nameRow = NSStackView(views: [nameLabel, defaultNameField])
        nameRow.translatesAutoresizingMaskIntoConstraints = false
        nameRow.orientation = .horizontal
        nameRow.spacing = 8

        let pathLabel = NSView.makeLabel(TTL("dialog.log.defaultPath"), alignment: .left)
        defaultPathField = NSView.makeTextField(value: s.logDefaultDirectory)
        let pathRow = NSStackView(views: [pathLabel, defaultPathField])
        pathRow.translatesAutoresizingMaskIntoConstraints = false
        pathRow.orientation = .horizontal
        pathRow.spacing = 8

        autoStartCheck = NSView.makeCheckbox(TTL("dialog.log.autoStart"), checked: s.logAutoStart)

        let optionsBox = NSView.makeGroupBox(title: TTL("dialog.log.options"))
        binaryCheck = NSView.makeCheckbox(TTL("dialog.log.binary"), checked: s.logBinary)
        appendCheck = NSView.makeCheckbox(TTL("dialog.log.append"), checked: s.logAppend)
        plainTextCheck = NSView.makeCheckbox(TTL("dialog.log.plainText"), checked: s.logPlainText)
        hideDialogCheck = NSView.makeCheckbox(TTL("dialog.log.hideDialog"), checked: s.logHideDialog)
        screenBufferCheck = NSView.makeCheckbox(TTL("dialog.log.screenBuffer"), checked: s.logIncludeScreenBuffer)
        timestampCheck = NSView.makeCheckbox(TTL("dialog.log.timestamp"), checked: s.logTimestamp)
        let optStack = NSStackView(views: [
            binaryCheck, appendCheck, plainTextCheck, hideDialogCheck, screenBufferCheck, timestampCheck
        ])
        optStack.translatesAutoresizingMaskIntoConstraints = false
        optStack.orientation = .vertical
        optStack.alignment = .leading
        optStack.spacing = 4
        let oc = optionsBox.contentView!
        oc.addSubview(optStack)
        NSLayoutConstraint.activate([
            optStack.topAnchor.constraint(equalTo: oc.topAnchor, constant: 16),
            optStack.leadingAnchor.constraint(equalTo: oc.leadingAnchor, constant: 12),
            optStack.trailingAnchor.constraint(lessThanOrEqualTo: oc.trailingAnchor, constant: -12),
            optStack.bottomAnchor.constraint(equalTo: oc.bottomAnchor, constant: -8),
        ])

        let rotateBox = NSView.makeGroupBox(title: TTL("dialog.log.logRotate"))
        rotateEnabledCheck = NSView.makeCheckbox(TTL("dialog.log.rotateEnabled"), checked: s.logRotateEnabled)
        let sizeLabel = NSView.makeLabel(TTL("dialog.log.rotateSize"), alignment: .left)
        rotateSizeField = NSView.makeNumberField(value: s.logRotateSize, width: 80)
        let stepLabel = NSView.makeLabel(TTL("dialog.log.rotateStep"), alignment: .left)
        rotateStepField = NSView.makeNumberField(value: s.logRotateStep, width: 60)
        let rotateStack = NSStackView(views: [
            rotateEnabledCheck,
            NSStackView(views: [sizeLabel, rotateSizeField]),
            NSStackView(views: [stepLabel, rotateStepField]),
        ])
        rotateStack.translatesAutoresizingMaskIntoConstraints = false
        rotateStack.orientation = .vertical
        rotateStack.alignment = .leading
        rotateStack.spacing = 6
        let rc = rotateBox.contentView!
        rc.addSubview(rotateStack)
        NSLayoutConstraint.activate([
            rotateStack.topAnchor.constraint(equalTo: rc.topAnchor, constant: 16),
            rotateStack.leadingAnchor.constraint(equalTo: rc.leadingAnchor, constant: 12),
            rotateStack.trailingAnchor.constraint(lessThanOrEqualTo: rc.trailingAnchor, constant: -12),
            rotateStack.bottomAnchor.constraint(equalTo: rc.bottomAnchor, constant: -8),
        ])

        // BOM output
        bomCheck = NSView.makeCheckbox(TTL("dialog.log.bom"), checked: s.logBOM)

        // Timestamp type
        let tsTypeLabel = NSView.makeLabel(TTL("dialog.log.timestampType"), alignment: .left)
        timestampTypePopup = NSView.makePopUpButton(
            items: LogTimestampType.allCases.map { $0.displayName }, width: 160)
        timestampTypePopup.selectItem(at: s.logTimestampType)
        let tsTypeRow = NSStackView(views: [tsTypeLabel, timestampTypePopup])
        tsTypeRow.translatesAutoresizingMaskIntoConstraints = false
        tsTypeRow.orientation = .horizontal
        tsTypeRow.spacing = 8

        // Timestamp format
        let tsFormatLabel = NSView.makeLabel(TTL("dialog.log.timestampFormat"), alignment: .left)
        timestampFormatField = NSView.makeTextField(value: s.logTimestampFormat, width: 200)
        let tsFormatRow = NSStackView(views: [tsFormatLabel, timestampFormatField])
        tsFormatRow.translatesAutoresizingMaskIntoConstraints = false
        tsFormatRow.orientation = .horizontal
        tsFormatRow.spacing = 8

        let stack = NSStackView(views: [
            editorRow, argsRow, nameRow, pathRow, autoStartCheck, optionsBox,
            bomCheck, tsTypeRow, tsFormatRow, rotateBox
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    func apply(to s: TerminalSettings) {
        s.logViewEditor = editorField.stringValue
        s.logEditorArguments = editorArgsField.stringValue
        s.logDefaultName = defaultNameField.stringValue
        s.logDefaultDirectory = defaultPathField.stringValue
        s.logAutoStart = autoStartCheck.state == .on
        s.logBinary = binaryCheck.state == .on
        s.logAppend = appendCheck.state == .on
        s.logPlainText = plainTextCheck.state == .on
        s.logHideDialog = hideDialogCheck.state == .on
        s.logIncludeScreenBuffer = screenBufferCheck.state == .on
        s.logTimestamp = timestampCheck.state == .on
        s.logRotateEnabled = rotateEnabledCheck.state == .on
        s.logRotateSize = rotateSizeField.integerValue
        s.logRotateStep = rotateStepField.integerValue
        s.logBOM = bomCheck.state == .on
        s.logTimestampType = timestampTypePopup.indexOfSelectedItem
        s.logTimestampFormat = timestampFormatField.stringValue
    }
}

// MARK: - Visual Tab (IDD_TABSHEET_VISUAL)

final class VisualTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.visual")
    let contentView = NSView()

    private var opacityActiveSlider: NSSlider!
    private var opacityInactiveSlider: NSSlider!
    private var opacityActiveLabel: NSTextField!
    private var opacityInactiveLabel: NSTextField!
    private var mouseCursorPopup: NSPopUpButton!
    private var fontQualityPopup: NSPopUpButton!
    private var fontRenderingQualityPopup: NSPopUpButton!
    private var flickerlessCheck: NSButton!
    private var cornerField: NSTextField!
    private var boldCheck: NSButton!
    private var blinkCheck: NSButton!
    private var reverseCheck: NSButton!
    private var underlineCheck: NSButton!
    private var strikethroughCheck: NSButton!
    private var colorWells: [NSColorWell] = []
    // New attribute color/font controls
    private var enableBoldColorCheck: NSButton!
    private var enableBoldFontCheck: NSButton!
    private var enableBlinkColorCheck: NSButton!
    private var enableReverseColorCheck: NSButton!
    private var enableUnderlineColorCheck: NSButton!
    private var enableUnderlineDecorationCheck: NSButton!
    private var enableURLColorCheck: NSButton!
    private var enableURLUnderlineCheck: NSButton!
    private var enableANSIColorCheck: NSButton!
    private var killFocusCursorCheck: NSButton!
    private var pcBoldColorCheck: NSButton!

    // Window extended settings
    private var enableBoldDisplayCheck: NSButton!
    private var hideWindowFrameCheck: NSButton!
    private var enableAixtermColorsCheck: NSButton!
    private var enableXterm256ColorsCheck: NSButton!
    private var useStandardBGColorCheck: NSButton!
    // Attribute color wells
    private var attrColorNormalWell: NSColorWell!
    private var attrColorBoldWell: NSColorWell!
    private var attrColorBlinkWell: NSColorWell!
    private var attrColorReverseWell: NSColorWell!
    private var attrColorURLWell: NSColorWell!
    private var attrColorUnderlineWell: NSColorWell!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        // Mouse cursor
        let cursorLabel = NSView.makeLabel(TTL("dialog.visual.mouseCursor"), alignment: .left)
        mouseCursorPopup = NSView.makePopUpButton(
            items: [TTL("dialog.visual.cursorArrow"),
                    TTL("dialog.visual.cursorIBeam"),
                    TTL("dialog.visual.cursorCrosshair"),
                    TTL("dialog.visual.cursorHidden")],
            width: 140)
        mouseCursorPopup.selectItem(at: s.mouseCursorType)
        let cursorRow = NSStackView(views: [cursorLabel, mouseCursorPopup])
        cursorRow.translatesAutoresizingMaskIntoConstraints = false
        cursorRow.orientation = .horizontal
        cursorRow.spacing = 8

        // Font rendering quality
        let qualityLabel = NSView.makeLabel(TTL("dialog.visual.fontRenderingQuality"), alignment: .left)
        fontRenderingQualityPopup = NSView.makePopUpButton(
            items: [TTL("dialog.visual.qualityDefault"),
                    TTL("dialog.visual.qualityAntiAlias"),
                    TTL("dialog.visual.qualitySubpixel")],
            width: 140)
        fontRenderingQualityPopup.selectItem(at: s.fontRenderingQuality)
        let qualityRow = NSStackView(views: [qualityLabel, fontRenderingQualityPopup])
        qualityRow.translatesAutoresizingMaskIntoConstraints = false
        qualityRow.orientation = .horizontal
        qualityRow.spacing = 8

        // Opacity
        let opacityBox = NSView.makeGroupBox(title: TTL("dialog.visual.windowOpacity"))
        let activeLabel = NSView.makeLabel(TTL("dialog.visual.active"), alignment: .left)
        opacityActiveSlider = NSView.makeSlider(min: 20, max: 100, value: Double(s.windowOpacityActive))
        opacityActiveSlider.target = self
        opacityActiveSlider.action = #selector(activeSliderChanged(_:))
        opacityActiveLabel = NSView.makeLabel("\(s.windowOpacityActive)%", alignment: .left)
        opacityActiveLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let inactiveLabel = NSView.makeLabel(TTL("dialog.visual.inactive"), alignment: .left)
        opacityInactiveSlider = NSView.makeSlider(min: 20, max: 100, value: Double(s.windowOpacityInactive))
        opacityInactiveSlider.target = self
        opacityInactiveSlider.action = #selector(inactiveSliderChanged(_:))
        opacityInactiveLabel = NSView.makeLabel("\(s.windowOpacityInactive)%", alignment: .left)
        opacityInactiveLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let opGrid = NSGridView(views: [
            [activeLabel, opacityActiveSlider, opacityActiveLabel],
            [inactiveLabel, opacityInactiveSlider, opacityInactiveLabel],
        ])
        opGrid.translatesAutoresizingMaskIntoConstraints = false
        opGrid.rowSpacing = 8
        opGrid.columnSpacing = 8
        let opc = opacityBox.contentView!
        opc.addSubview(opGrid)
        NSLayoutConstraint.activate([
            opGrid.topAnchor.constraint(equalTo: opc.topAnchor, constant: 16),
            opGrid.leadingAnchor.constraint(equalTo: opc.leadingAnchor, constant: 12),
            opGrid.trailingAnchor.constraint(equalTo: opc.trailingAnchor, constant: -12),
            opGrid.bottomAnchor.constraint(equalTo: opc.bottomAnchor, constant: -8),
        ])

        // ANSI color palette
        let colorBox = NSView.makeGroupBox(title: TTL("dialog.visual.ansiColorPalette"))
        let colorNames = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White",
                          "Bright Black", "Bright Red", "Bright Green", "Bright Yellow",
                          "Bright Blue", "Bright Magenta", "Bright Cyan", "Bright White"]
        let colorGrid = NSView()
        colorGrid.translatesAutoresizingMaskIntoConstraints = false
        colorWells = []
        for i in 0..<16 {
            let c = i < s.colorTheme.ansiColors.count ? s.colorTheme.ansiColors[i] : TerminalColor(r: 0, g: 0, b: 0)
            let well = NSView.makeColorWell(color: NSColor(
                red: CGFloat(c.r)/255, green: CGFloat(c.g)/255, blue: CGFloat(c.b)/255, alpha: 1))
            well.toolTip = colorNames[i]
            colorWells.append(well)
            colorGrid.addSubview(well)
        }
        // Layout: 2 rows of 8
        for i in 0..<16 {
            let row = i / 8
            let col = i % 8
            NSLayoutConstraint.activate([
                colorWells[i].topAnchor.constraint(equalTo: colorGrid.topAnchor, constant: CGFloat(row) * 36),
                colorWells[i].leadingAnchor.constraint(equalTo: colorGrid.leadingAnchor, constant: CGFloat(col) * 36),
            ])
        }
        colorGrid.heightAnchor.constraint(equalToConstant: 72).isActive = true
        colorGrid.widthAnchor.constraint(equalToConstant: 288).isActive = true
        let cbc = colorBox.contentView!
        cbc.addSubview(colorGrid)
        NSLayoutConstraint.activate([
            colorGrid.topAnchor.constraint(equalTo: cbc.topAnchor, constant: 16),
            colorGrid.leadingAnchor.constraint(equalTo: cbc.leadingAnchor, constant: 12),
            colorGrid.bottomAnchor.constraint(equalTo: cbc.bottomAnchor, constant: -8),
        ])

        // Attributes
        let attrBox = NSView.makeGroupBox(title: TTL("dialog.visual.charAttributes"))
        boldCheck = NSView.makeCheckbox(TTL("dialog.visual.attrBold"), checked: s.attrBold)
        blinkCheck = NSView.makeCheckbox(TTL("dialog.visual.attrBlink"), checked: s.attrBlink)
        reverseCheck = NSView.makeCheckbox(TTL("dialog.visual.attrReverse"), checked: s.attrReverse)
        underlineCheck = NSView.makeCheckbox(TTL("dialog.visual.attrUnderline"), checked: s.attrUnderline)
        strikethroughCheck = NSView.makeCheckbox(TTL("dialog.visual.attrStrikethrough"), checked: s.attrStrikethrough)
        let attrStack = NSStackView(views: [boldCheck, blinkCheck, reverseCheck, underlineCheck, strikethroughCheck])
        attrStack.translatesAutoresizingMaskIntoConstraints = false
        attrStack.orientation = .horizontal
        attrStack.spacing = 12
        let abc = attrBox.contentView!
        abc.addSubview(attrStack)
        NSLayoutConstraint.activate([
            attrStack.topAnchor.constraint(equalTo: abc.topAnchor, constant: 16),
            attrStack.leadingAnchor.constraint(equalTo: abc.leadingAnchor, constant: 12),
            attrStack.bottomAnchor.constraint(equalTo: abc.bottomAnchor, constant: -8),
        ])

        // Attribute color/font settings
        let attrColorBox = NSView.makeGroupBox(title: TTL("dialog.visual.attrColorFont"))
        enableBoldColorCheck = NSView.makeCheckbox(
            TTL("dialog.visual.enableBoldColor"), checked: s.enableBoldColor)
        enableBoldFontCheck = NSView.makeCheckbox(
            TTL("dialog.visual.enableBoldFont"), checked: s.enableBoldFont)
        enableBlinkColorCheck = NSView.makeCheckbox(
            TTL("dialog.visual.enableBlinkColor"), checked: s.enableBlinkColor)
        enableReverseColorCheck = NSView.makeCheckbox(
            TTL("dialog.visual.enableReverseColor"), checked: s.enableReverseColor)
        enableUnderlineColorCheck = NSView.makeCheckbox(
            TTL("dialog.visual.enableUnderlineColor"), checked: s.enableUnderlineColor)
        enableUnderlineDecorationCheck = NSView.makeCheckbox(
            TTL("dialog.visual.enableUnderlineDecoration"), checked: s.enableUnderlineDecoration)
        enableURLColorCheck = NSView.makeCheckbox(
            TTL("dialog.visual.enableURLColor"), checked: s.enableURLColor)
        enableURLUnderlineCheck = NSView.makeCheckbox(
            TTL("dialog.visual.enableURLUnderline"), checked: s.enableURLUnderline)
        enableANSIColorCheck = NSView.makeCheckbox(
            TTL("dialog.visual.enableANSIColor"), checked: s.enableANSIColor)

        let acStack = NSStackView(views: [
            enableBoldColorCheck, enableBoldFontCheck,
            enableBlinkColorCheck, enableReverseColorCheck,
            enableUnderlineColorCheck, enableUnderlineDecorationCheck,
            enableURLColorCheck, enableURLUnderlineCheck,
            enableANSIColorCheck
        ])
        acStack.translatesAutoresizingMaskIntoConstraints = false
        acStack.orientation = .vertical
        acStack.alignment = .leading
        acStack.spacing = 4
        let acc = attrColorBox.contentView!
        acc.addSubview(acStack)
        NSLayoutConstraint.activate([
            acStack.topAnchor.constraint(equalTo: acc.topAnchor, constant: 16),
            acStack.leadingAnchor.constraint(equalTo: acc.leadingAnchor, constant: 12),
            acStack.trailingAnchor.constraint(lessThanOrEqualTo: acc.trailingAnchor, constant: -12),
            acStack.bottomAnchor.constraint(equalTo: acc.bottomAnchor, constant: -8),
        ])

        flickerlessCheck = NSView.makeCheckbox(TTL("dialog.visual.flickerlessMove"), checked: s.flickerlessMoveEnabled)
        killFocusCursorCheck = NSView.makeCheckbox(TTL("dialog.visual.killFocusCursor"), checked: s.killFocusCursor)
        pcBoldColorCheck = NSView.makeCheckbox(TTL("dialog.visual.pcBoldColor"), checked: s.pcBoldColor)

        // ── Window Extended Settings Group Box ──
        let winExtBox = NSView.makeGroupBox(title: TTL("dialog.visual.windowExtended"))
        enableBoldDisplayCheck = NSView.makeCheckbox(
            TTL("dialog.visual.enableBoldDisplay"), checked: s.enableBoldDisplay)
        hideWindowFrameCheck = NSView.makeCheckbox(
            TTL("dialog.visual.hideWindowFrame"), checked: s.hideWindowFrame)
        enableAixtermColorsCheck = NSView.makeCheckbox(
            TTL("dialog.visual.aixtermColors"), checked: s.enableAixtermColors)
        enableXterm256ColorsCheck = NSView.makeCheckbox(
            TTL("dialog.visual.xterm256Colors"), checked: s.enableXterm256Colors)
        useStandardBGColorCheck = NSView.makeCheckbox(
            TTL("dialog.visual.useStandardBGColor"), checked: s.useStandardBGColor)

        let winExtStack = NSStackView(views: [
            enableBoldDisplayCheck, hideWindowFrameCheck,
            enableAixtermColorsCheck, enableXterm256ColorsCheck,
            useStandardBGColorCheck
        ])
        winExtStack.translatesAutoresizingMaskIntoConstraints = false
        winExtStack.orientation = .vertical
        winExtStack.alignment = .leading
        winExtStack.spacing = 4
        let wec = winExtBox.contentView!
        wec.addSubview(winExtStack)
        NSLayoutConstraint.activate([
            winExtStack.topAnchor.constraint(equalTo: wec.topAnchor, constant: 16),
            winExtStack.leadingAnchor.constraint(equalTo: wec.leadingAnchor, constant: 12),
            winExtStack.trailingAnchor.constraint(lessThanOrEqualTo: wec.trailingAnchor, constant: -12),
            winExtStack.bottomAnchor.constraint(equalTo: wec.bottomAnchor, constant: -8),
        ])

        // ── Attribute Color Settings Group Box ──
        let attrColorSettingsBox = NSView.makeGroupBox(title: TTL("dialog.visual.attrColorSettings"))
        func colorWell(for c: TerminalColor) -> NSColorWell {
            NSView.makeColorWell(color: NSColor(
                red: CGFloat(c.r)/255, green: CGFloat(c.g)/255, blue: CGFloat(c.b)/255, alpha: 1))
        }
        attrColorNormalWell = colorWell(for: s.attrColorNormal)
        attrColorBoldWell = colorWell(for: s.attrColorBold)
        attrColorBlinkWell = colorWell(for: s.attrColorBlink)
        attrColorReverseWell = colorWell(for: s.attrColorReverse)
        attrColorURLWell = colorWell(for: s.attrColorURL)
        attrColorUnderlineWell = colorWell(for: s.attrColorUnderline)

        let attrColorGrid = NSGridView(views: [
            [NSView.makeLabel(TTL("dialog.visual.colorNormal"), alignment: .right), attrColorNormalWell,
             NSView.makeLabel(TTL("dialog.visual.colorBold"), alignment: .right), attrColorBoldWell],
            [NSView.makeLabel(TTL("dialog.visual.colorBlink"), alignment: .right), attrColorBlinkWell,
             NSView.makeLabel(TTL("dialog.visual.colorReverse"), alignment: .right), attrColorReverseWell],
            [NSView.makeLabel(TTL("dialog.visual.colorURL"), alignment: .right), attrColorURLWell,
             NSView.makeLabel(TTL("dialog.visual.colorUnderline"), alignment: .right), attrColorUnderlineWell],
        ])
        attrColorGrid.translatesAutoresizingMaskIntoConstraints = false
        attrColorGrid.rowSpacing = 8
        attrColorGrid.columnSpacing = 8
        let acsc = attrColorSettingsBox.contentView!
        acsc.addSubview(attrColorGrid)
        NSLayoutConstraint.activate([
            attrColorGrid.topAnchor.constraint(equalTo: acsc.topAnchor, constant: 16),
            attrColorGrid.leadingAnchor.constraint(equalTo: acsc.leadingAnchor, constant: 12),
            attrColorGrid.trailingAnchor.constraint(lessThanOrEqualTo: acsc.trailingAnchor, constant: -12),
            attrColorGrid.bottomAnchor.constraint(equalTo: acsc.bottomAnchor, constant: -8),
        ])

        let stack = NSStackView(views: [
            cursorRow, qualityRow,
            opacityBox, colorBox, attrBox, attrColorBox,
            winExtBox, attrColorSettingsBox, flickerlessCheck,
            killFocusCursorCheck, pcBoldColorCheck
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        ])
    }

    @objc private func activeSliderChanged(_ sender: NSSlider) {
        opacityActiveLabel.stringValue = "\(Int(sender.doubleValue))%"
    }
    @objc private func inactiveSliderChanged(_ sender: NSSlider) {
        opacityInactiveLabel.stringValue = "\(Int(sender.doubleValue))%"
    }

    func apply(to s: TerminalSettings) {
        s.mouseCursorType = mouseCursorPopup.indexOfSelectedItem
        s.fontRenderingQuality = fontRenderingQualityPopup.indexOfSelectedItem
        s.windowOpacityActive = Int(opacityActiveSlider.doubleValue)
        s.windowOpacityInactive = Int(opacityInactiveSlider.doubleValue)
        s.flickerlessMoveEnabled = flickerlessCheck.state == .on
        s.attrBold = boldCheck.state == .on
        s.attrBlink = blinkCheck.state == .on
        s.attrReverse = reverseCheck.state == .on
        s.attrUnderline = underlineCheck.state == .on
        s.attrStrikethrough = strikethroughCheck.state == .on
        s.enableBoldColor = enableBoldColorCheck.state == .on
        s.enableBoldFont = enableBoldFontCheck.state == .on
        s.enableBlinkColor = enableBlinkColorCheck.state == .on
        s.enableReverseColor = enableReverseColorCheck.state == .on
        s.enableUnderlineColor = enableUnderlineColorCheck.state == .on
        s.enableUnderlineDecoration = enableUnderlineDecorationCheck.state == .on
        s.enableURLColor = enableURLColorCheck.state == .on
        s.enableURLUnderline = enableURLUnderlineCheck.state == .on
        s.enableANSIColor = enableANSIColorCheck.state == .on

        for i in 0..<min(16, colorWells.count) {
            let c = colorWells[i].color
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            let converted = c.usingColorSpace(.sRGB) ?? c
            converted.getRed(&r, green: &g, blue: &b, alpha: nil)
            if i < s.colorTheme.ansiColors.count {
                s.colorTheme.ansiColors[i] = TerminalColor(
                    r: UInt8(clamping: Int(r * 255)),
                    g: UInt8(clamping: Int(g * 255)),
                    b: UInt8(clamping: Int(b * 255)))
            }
        }

        // Window extended settings
        s.enableBoldDisplay = enableBoldDisplayCheck.state == .on
        s.hideWindowFrame = hideWindowFrameCheck.state == .on
        s.enableAixtermColors = enableAixtermColorsCheck.state == .on
        s.enableXterm256Colors = enableXterm256ColorsCheck.state == .on
        s.useStandardBGColor = useStandardBGColorCheck.state == .on

        // Attribute colors
        func extractColor(_ well: NSColorWell) -> TerminalColor {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            let c = well.color.usingColorSpace(.sRGB) ?? well.color
            c.getRed(&r, green: &g, blue: &b, alpha: nil)
            return TerminalColor(r: UInt8(clamping: Int(r * 255)),
                                 g: UInt8(clamping: Int(g * 255)),
                                 b: UInt8(clamping: Int(b * 255)))
        }
        s.attrColorNormal = extractColor(attrColorNormalWell)
        s.attrColorBold = extractColor(attrColorBoldWell)
        s.attrColorBlink = extractColor(attrColorBlinkWell)
        s.attrColorReverse = extractColor(attrColorReverseWell)
        s.attrColorURL = extractColor(attrColorURLWell)
        s.attrColorUnderline = extractColor(attrColorUnderlineWell)
        s.killFocusCursor = killFocusCursorCheck.state == .on
        s.pcBoldColor = pcBoldColorCheck.state == .on
    }
}

// MARK: - Font Tab (IDD_TABSHEET_FONT)

final class FontTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.font")
    let contentView = NSView()

    private var fontNameField: NSTextField!
    private var proportionalCheck: NSButton!
    private var hiddenCheck: NSButton!
    private var drawingAPIPopup: NSPopUpButton!
    private var codePageField: NSTextField!
    private var charSpaceHField: NSTextField!
    private var charSpaceVField: NSTextField!
    private var resizeFontToFitCheck: NSButton!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        let fontBox = NSView.makeGroupBox(title: TTL("dialog.font.vtWindowFont"))

        let fontLabel = NSView.makeLabel(TTL("dialog.font.fontName"), alignment: .left)
        fontNameField = NSView.makeTextField(value: "\(s.fontName) \(Int(s.fontSize))pt")
        fontNameField.isEditable = false

        let chooseFontBtn = NSView.makePushButton(TTL("dialog.font.choose"))
        chooseFontBtn.target = self
        chooseFontBtn.action = #selector(chooseFont(_:))

        let fontRow = NSStackView(views: [fontLabel, fontNameField, chooseFontBtn])
        fontRow.translatesAutoresizingMaskIntoConstraints = false
        fontRow.orientation = .horizontal
        fontRow.spacing = 8

        proportionalCheck = NSView.makeCheckbox(TTL("dialog.font.proportional"), checked: s.vtFontProportional)
        hiddenCheck = NSView.makeCheckbox(TTL("dialog.font.hidden"), checked: s.vtFontHidden)
        resizeFontToFitCheck = NSView.makeCheckbox(
            TTL("dialog.font.resizeFontToFit"), checked: s.resizeFontToFitWidth)

        let fc = fontBox.contentView!
        let fontStack = NSStackView(views: [fontRow, proportionalCheck, hiddenCheck, resizeFontToFitCheck])
        fontStack.translatesAutoresizingMaskIntoConstraints = false
        fontStack.orientation = .vertical
        fontStack.alignment = .leading
        fontStack.spacing = 6
        fc.addSubview(fontStack)
        NSLayoutConstraint.activate([
            fontStack.topAnchor.constraint(equalTo: fc.topAnchor, constant: 16),
            fontStack.leadingAnchor.constraint(equalTo: fc.leadingAnchor, constant: 12),
            fontStack.trailingAnchor.constraint(equalTo: fc.trailingAnchor, constant: -12),
            fontStack.bottomAnchor.constraint(equalTo: fc.bottomAnchor, constant: -8),
        ])

        let apiLabel = NSView.makeLabel(TTL("dialog.font.drawingAPI"), alignment: .left)
        drawingAPIPopup = NSView.makePopUpButton(items: ["Default", "CoreText", "CoreGraphics"], width: 140)
        drawingAPIPopup.selectItem(at: s.drawingAPI)
        let apiRow = NSStackView(views: [apiLabel, drawingAPIPopup])
        apiRow.translatesAutoresizingMaskIntoConstraints = false
        apiRow.orientation = .horizontal
        apiRow.spacing = 8

        let cpLabel = NSView.makeLabel(TTL("dialog.font.codePage"), alignment: .left)
        codePageField = NSView.makeNumberField(value: s.codePage, width: 80)
        let cpRow = NSStackView(views: [cpLabel, codePageField])
        cpRow.translatesAutoresizingMaskIntoConstraints = false
        cpRow.orientation = .horizontal
        cpRow.spacing = 8

        let spaceBox = NSView.makeGroupBox(title: TTL("dialog.font.charSpace"))
        let hLabel = NSView.makeLabel("H:", alignment: .left)
        charSpaceHField = NSView.makeNumberField(value: s.charSpaceH, width: 50)
        let vLabel = NSView.makeLabel("V:", alignment: .left)
        charSpaceVField = NSView.makeNumberField(value: s.charSpaceV, width: 50)
        let spaceRow = NSStackView(views: [hLabel, charSpaceHField, vLabel, charSpaceVField])
        spaceRow.translatesAutoresizingMaskIntoConstraints = false
        spaceRow.orientation = .horizontal
        spaceRow.spacing = 8
        let sc = spaceBox.contentView!
        sc.addSubview(spaceRow)
        NSLayoutConstraint.activate([
            spaceRow.topAnchor.constraint(equalTo: sc.topAnchor, constant: 16),
            spaceRow.leadingAnchor.constraint(equalTo: sc.leadingAnchor, constant: 12),
            spaceRow.bottomAnchor.constraint(equalTo: sc.bottomAnchor, constant: -8),
        ])

        let stack = NSStackView(views: [fontBox, apiRow, cpRow, spaceBox])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    @objc private func chooseFont(_ sender: Any?) {
        let fm = NSFontManager.shared
        fm.orderFrontFontPanel(sender)
    }

    func apply(to s: TerminalSettings) {
        s.vtFontProportional = proportionalCheck.state == .on
        s.vtFontHidden = hiddenCheck.state == .on
        s.resizeFontToFitWidth = resizeFontToFitCheck.state == .on
        s.drawingAPI = drawingAPIPopup.indexOfSelectedItem
        s.codePage = codePageField.integerValue
        s.charSpaceH = charSpaceHField.integerValue
        s.charSpaceV = charSpaceVField.integerValue
    }
}

// MARK: - TEK Font Tab (IDD_TABSHEET_TEKFONT)

final class TEKFontTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.tekFont")
    let contentView = NSView()

    private var fontNameField: NSTextField!
    private var proportionalCheck: NSButton!
    private var hiddenCheck: NSButton!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        let fontLabel = NSView.makeLabel(TTL("dialog.tekFont.fontName"), alignment: .left)
        fontNameField = NSView.makeTextField(value: "\(s.tekFontName) \(Int(s.tekFontSize))pt")
        fontNameField.isEditable = false

        let chooseFontBtn = NSView.makePushButton(TTL("dialog.tekFont.choose"))
        chooseFontBtn.target = self
        chooseFontBtn.action = #selector(chooseFont(_:))

        let fontRow = NSStackView(views: [fontLabel, fontNameField, chooseFontBtn])
        fontRow.translatesAutoresizingMaskIntoConstraints = false
        fontRow.orientation = .horizontal
        fontRow.spacing = 8

        proportionalCheck = NSView.makeCheckbox(TTL("dialog.tekFont.proportional"), checked: s.tekFontProportional)
        hiddenCheck = NSView.makeCheckbox(TTL("dialog.tekFont.hidden"), checked: s.tekFontHidden)

        let stack = NSStackView(views: [fontRow, proportionalCheck, hiddenCheck])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        ])
    }

    @objc private func chooseFont(_ sender: Any?) {
        NSFontManager.shared.orderFrontFontPanel(sender)
    }

    func apply(to s: TerminalSettings) {
        s.tekFontProportional = proportionalCheck.state == .on
        s.tekFontHidden = hiddenCheck.state == .on
    }
}

// MARK: - Theme Tab (IDD_TABSHEET_THEME)

final class ThemeTab: NSObject, AdditionalSettingsTab {
    let tabTitle = TTL("tab.theme")
    let contentView = NSView()

    private var enableCheck: NSButton!
    private var themeFileField: NSTextField!
    private var startupThemeField: NSTextField!
    private var fastSizeMoveCheck: NSButton!
    private var susiePathField: NSTextField!

    // Background image settings
    private var bgImagePathField: NSTextField!
    private var bgAlphaNormalSlider: NSSlider!
    private var bgAlphaReverseSlider: NSSlider!
    private var bgAlphaOtherSlider: NSSlider!
    private var bgAlphaNormalLabel: NSTextField!
    private var bgAlphaReverseLabel: NSTextField!
    private var bgAlphaOtherLabel: NSTextField!

    // Theme color editor wells
    private var themeForegroundWell: NSColorWell!
    private var themeBackgroundWell: NSColorWell!
    private var themeCursorWell: NSColorWell!
    private var themeSelFgWell: NSColorWell!
    private var themeSelBgWell: NSColorWell!
    private var themeURLWell: NSColorWell!

    init(settings: TerminalSettings) {
        super.init()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        enableCheck = NSView.makeCheckbox(TTL("dialog.theme.enable"), checked: s.themeEnabled)
        fastSizeMoveCheck = NSView.makeCheckbox(TTL("dialog.theme.fastSizeMove"), checked: s.fastSizeMove)

        let themeLabel = NSView.makeLabel(TTL("dialog.theme.themeFile"), alignment: .left)
        themeFileField = NSView.makeTextField(value: s.themeFile)
        let themeRow = NSStackView(views: [themeLabel, themeFileField])
        themeRow.translatesAutoresizingMaskIntoConstraints = false
        themeRow.orientation = .horizontal
        themeRow.spacing = 8

        let startupLabel = NSView.makeLabel(TTL("dialog.theme.startupTheme"), alignment: .left)
        startupThemeField = NSView.makeTextField(value: s.startupTheme)
        let startupRow = NSStackView(views: [startupLabel, startupThemeField])
        startupRow.translatesAutoresizingMaskIntoConstraints = false
        startupRow.orientation = .horizontal
        startupRow.spacing = 8

        let susieLabel = NSView.makeLabel(TTL("dialog.theme.susiePath"), alignment: .left)
        susiePathField = NSView.makeTextField(value: s.susiePath)
        let susieRow = NSStackView(views: [susieLabel, susiePathField])
        susieRow.translatesAutoresizingMaskIntoConstraints = false
        susieRow.orientation = .horizontal
        susieRow.spacing = 8

        let editorBtn = NSView.makePushButton(TTL("dialog.theme.themeEditor"))

        // ── Background Image Group Box ──
        let bgBox = NSView.makeGroupBox(title: TTL("dialog.theme.bgImage"))
        let bgPathLabel = NSView.makeLabel(TTL("dialog.theme.bgImagePath"), alignment: .left)
        bgImagePathField = NSView.makeTextField(value: s.bgImagePath, width: 240)
        let browseBtn = NSView.makePushButton(TTL("dialog.theme.browse"))
        browseBtn.target = self
        browseBtn.action = #selector(browseBGImage(_:))
        let bgPathRow = NSStackView(views: [bgPathLabel, bgImagePathField, browseBtn])
        bgPathRow.translatesAutoresizingMaskIntoConstraints = false
        bgPathRow.orientation = .horizontal
        bgPathRow.spacing = 8

        // Alpha sliders for transparency
        let normalAlphaLabel = NSView.makeLabel(TTL("dialog.theme.alphaNormal"), alignment: .left)
        bgAlphaNormalSlider = NSView.makeSlider(min: 0, max: 100, value: s.bgImageAlphaNormal * 100)
        bgAlphaNormalSlider.target = self
        bgAlphaNormalSlider.action = #selector(bgAlphaChanged(_:))
        bgAlphaNormalLabel = NSView.makeLabel("\(Int(s.bgImageAlphaNormal * 100))%", alignment: .left)
        bgAlphaNormalLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let reverseAlphaLabel = NSView.makeLabel(TTL("dialog.theme.alphaReverse"), alignment: .left)
        bgAlphaReverseSlider = NSView.makeSlider(min: 0, max: 100, value: s.bgImageAlphaReverse * 100)
        bgAlphaReverseSlider.target = self
        bgAlphaReverseSlider.action = #selector(bgAlphaChanged(_:))
        bgAlphaReverseLabel = NSView.makeLabel("\(Int(s.bgImageAlphaReverse * 100))%", alignment: .left)
        bgAlphaReverseLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let otherAlphaLabel = NSView.makeLabel(TTL("dialog.theme.alphaOther"), alignment: .left)
        bgAlphaOtherSlider = NSView.makeSlider(min: 0, max: 100, value: s.bgImageAlphaOther * 100)
        bgAlphaOtherSlider.target = self
        bgAlphaOtherSlider.action = #selector(bgAlphaChanged(_:))
        bgAlphaOtherLabel = NSView.makeLabel("\(Int(s.bgImageAlphaOther * 100))%", alignment: .left)
        bgAlphaOtherLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let alphaGrid = NSGridView(views: [
            [normalAlphaLabel, bgAlphaNormalSlider, bgAlphaNormalLabel],
            [reverseAlphaLabel, bgAlphaReverseSlider, bgAlphaReverseLabel],
            [otherAlphaLabel, bgAlphaOtherSlider, bgAlphaOtherLabel],
        ])
        alphaGrid.translatesAutoresizingMaskIntoConstraints = false
        alphaGrid.rowSpacing = 6
        alphaGrid.columnSpacing = 8

        let bgStack = NSStackView(views: [bgPathRow, alphaGrid])
        bgStack.translatesAutoresizingMaskIntoConstraints = false
        bgStack.orientation = .vertical
        bgStack.alignment = .leading
        bgStack.spacing = 8
        let bgc = bgBox.contentView!
        bgc.addSubview(bgStack)
        NSLayoutConstraint.activate([
            bgStack.topAnchor.constraint(equalTo: bgc.topAnchor, constant: 16),
            bgStack.leadingAnchor.constraint(equalTo: bgc.leadingAnchor, constant: 12),
            bgStack.trailingAnchor.constraint(equalTo: bgc.trailingAnchor, constant: -12),
            bgStack.bottomAnchor.constraint(equalTo: bgc.bottomAnchor, constant: -8),
        ])

        // ── Theme Color Editor Group Box ──
        let colorEditorBox = NSView.makeGroupBox(title: TTL("dialog.theme.colorEditor"))
        func wellFor(_ c: TerminalColor) -> NSColorWell {
            NSView.makeColorWell(color: NSColor(
                red: CGFloat(c.r)/255, green: CGFloat(c.g)/255, blue: CGFloat(c.b)/255, alpha: 1))
        }
        themeForegroundWell = wellFor(s.colorTheme.foreground)
        themeBackgroundWell = wellFor(s.colorTheme.background)
        themeCursorWell = wellFor(s.colorTheme.cursorColor)
        themeSelFgWell = wellFor(s.colorTheme.selectionForeground)
        themeSelBgWell = wellFor(s.colorTheme.selectionBackground)
        themeURLWell = wellFor(s.colorTheme.urlColor)

        let colorEditorGrid = NSGridView(views: [
            [NSView.makeLabel(TTL("dialog.theme.foreground"), alignment: .right), themeForegroundWell,
             NSView.makeLabel(TTL("dialog.theme.background"), alignment: .right), themeBackgroundWell],
            [NSView.makeLabel(TTL("dialog.theme.cursor"), alignment: .right), themeCursorWell,
             NSView.makeLabel(TTL("dialog.theme.url"), alignment: .right), themeURLWell],
            [NSView.makeLabel(TTL("dialog.theme.selFg"), alignment: .right), themeSelFgWell,
             NSView.makeLabel(TTL("dialog.theme.selBg"), alignment: .right), themeSelBgWell],
        ])
        colorEditorGrid.translatesAutoresizingMaskIntoConstraints = false
        colorEditorGrid.rowSpacing = 8
        colorEditorGrid.columnSpacing = 8
        let cec = colorEditorBox.contentView!
        cec.addSubview(colorEditorGrid)
        NSLayoutConstraint.activate([
            colorEditorGrid.topAnchor.constraint(equalTo: cec.topAnchor, constant: 16),
            colorEditorGrid.leadingAnchor.constraint(equalTo: cec.leadingAnchor, constant: 12),
            colorEditorGrid.trailingAnchor.constraint(lessThanOrEqualTo: cec.trailingAnchor, constant: -12),
            colorEditorGrid.bottomAnchor.constraint(equalTo: cec.bottomAnchor, constant: -8),
        ])

        let stack = NSStackView(views: [
            enableCheck, editorBtn, fastSizeMoveCheck, startupRow, themeRow, susieRow,
            bgBox, colorEditorBox
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    @objc private func browseBGImage(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            bgImagePathField.stringValue = url.path
        }
    }

    @objc private func bgAlphaChanged(_ sender: NSSlider) {
        if sender === bgAlphaNormalSlider {
            bgAlphaNormalLabel.stringValue = "\(Int(sender.doubleValue))%"
        } else if sender === bgAlphaReverseSlider {
            bgAlphaReverseLabel.stringValue = "\(Int(sender.doubleValue))%"
        } else if sender === bgAlphaOtherSlider {
            bgAlphaOtherLabel.stringValue = "\(Int(sender.doubleValue))%"
        }
    }

    func apply(to s: TerminalSettings) {
        s.themeEnabled = enableCheck.state == .on
        s.themeFile = themeFileField.stringValue
        s.startupTheme = startupThemeField.stringValue
        s.fastSizeMove = fastSizeMoveCheck.state == .on
        s.susiePath = susiePathField.stringValue

        // Background image
        s.bgImagePath = bgImagePathField.stringValue
        s.bgImageAlphaNormal = bgAlphaNormalSlider.doubleValue / 100.0
        s.bgImageAlphaReverse = bgAlphaReverseSlider.doubleValue / 100.0
        s.bgImageAlphaOther = bgAlphaOtherSlider.doubleValue / 100.0

        // Theme color editor
        func extractColor(_ well: NSColorWell) -> TerminalColor {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            let c = well.color.usingColorSpace(.sRGB) ?? well.color
            c.getRed(&r, green: &g, blue: &b, alpha: nil)
            return TerminalColor(r: UInt8(clamping: Int(r * 255)),
                                 g: UInt8(clamping: Int(g * 255)),
                                 b: UInt8(clamping: Int(b * 255)))
        }
        s.colorTheme.foreground = extractColor(themeForegroundWell)
        s.colorTheme.background = extractColor(themeBackgroundWell)
        s.colorTheme.cursorColor = extractColor(themeCursorWell)
        s.colorTheme.selectionForeground = extractColor(themeSelFgWell)
        s.colorTheme.selectionBackground = extractColor(themeSelBgWell)
        s.colorTheme.urlColor = extractColor(themeURLWell)
    }
}

// MARK: - UI Tab (IDD_TABSHEET_UI)

final class UITab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.ui")
    let contentView = NSView()

    private var languagePopup: NSPopUpButton!
    private var dialogFontField: NSTextField!
    private var proportionalCheck: NSButton!
    private var hiddenCheck: NSButton!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        let langLabel = NSView.makeLabel(TTL("dialog.ui.language"), alignment: .left)
        languagePopup = NSView.makePopUpButton(
            items: ["English", "Japanese", "German", "French", "Russian", "Korean", "Chinese (Simplified)", "Chinese (Traditional)"],
            selected: s.language, width: 200)
        let langRow = NSStackView(views: [langLabel, languagePopup])
        langRow.translatesAutoresizingMaskIntoConstraints = false
        langRow.orientation = .horizontal
        langRow.spacing = 8

        let fontBox = NSView.makeGroupBox(title: TTL("dialog.ui.dialogFont"))
        let fontLabel = NSView.makeLabel(TTL("dialog.ui.fontName"), alignment: .left)
        let displayName = s.dialogFontName.isEmpty ? "(System Default)" : "\(s.dialogFontName) \(Int(s.dialogFontSize))pt"
        dialogFontField = NSView.makeTextField(value: displayName)
        dialogFontField.isEditable = false

        let chooseFontBtn = NSView.makePushButton(TTL("dialog.ui.chooseFont"))
        proportionalCheck = NSView.makeCheckbox(TTL("dialog.ui.proportional"), checked: s.dialogFontProportional)
        hiddenCheck = NSView.makeCheckbox(TTL("dialog.ui.hidden"), checked: s.dialogFontHidden)

        let fontRow = NSStackView(views: [fontLabel, dialogFontField, chooseFontBtn])
        fontRow.translatesAutoresizingMaskIntoConstraints = false
        fontRow.orientation = .horizontal
        fontRow.spacing = 8

        let fontStack = NSStackView(views: [fontRow, proportionalCheck, hiddenCheck])
        fontStack.translatesAutoresizingMaskIntoConstraints = false
        fontStack.orientation = .vertical
        fontStack.alignment = .leading
        fontStack.spacing = 6
        let fc = fontBox.contentView!
        fc.addSubview(fontStack)
        NSLayoutConstraint.activate([
            fontStack.topAnchor.constraint(equalTo: fc.topAnchor, constant: 16),
            fontStack.leadingAnchor.constraint(equalTo: fc.leadingAnchor, constant: 12),
            fontStack.trailingAnchor.constraint(equalTo: fc.trailingAnchor, constant: -12),
            fontStack.bottomAnchor.constraint(equalTo: fc.bottomAnchor, constant: -8),
        ])

        let stack = NSStackView(views: [langRow, fontBox])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    func apply(to s: TerminalSettings) {
        s.language = languagePopup.titleOfSelectedItem ?? "English"
        s.dialogFontProportional = proportionalCheck.state == .on
        s.dialogFontHidden = hiddenCheck.state == .on
    }
}

// MARK: - Plugin Tab (IDD_TABSHEET_PLUGIN)

final class PluginTab: NSObject, AdditionalSettingsTab {
    let tabTitle = TTL("tab.plugin")
    let contentView = NSView()

    private var directoryList: NSTableView!
    private var directories: [String]

    init(settings: TerminalSettings) {
        self.directories = settings.pluginDirectories
        super.init()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI()
    }

    private func buildUI() {
        let label = NSView.makeLabel(TTL("dialog.plugin.setupDirectories"), alignment: .left)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        directoryList = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dir"))
        col.title = "Directory"
        col.width = 400
        directoryList.addTableColumn(col)
        directoryList.headerView = nil
        directoryList.dataSource = self
        directoryList.reloadData()
        scrollView.documentView = directoryList

        let addBtn = NSView.makePushButton(TTL("dialog.plugin.add"))
        addBtn.target = self
        addBtn.action = #selector(addDirectory(_:))

        let removeBtn = NSView.makePushButton(TTL("dialog.plugin.remove"))
        removeBtn.target = self
        removeBtn.action = #selector(removeDirectory(_:))

        let btnRow = NSStackView(views: [addBtn, removeBtn])
        btnRow.translatesAutoresizingMaskIntoConstraints = false
        btnRow.orientation = .horizontal
        btnRow.spacing = 8

        let stack = NSStackView(views: [label, scrollView, btnRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.heightAnchor.constraint(equalToConstant: 150),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func addDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            directories.append(url.path)
            directoryList.reloadData()
        }
    }

    @objc private func removeDirectory(_ sender: Any?) {
        let row = directoryList.selectedRow
        guard row >= 0 && row < directories.count else { return }
        directories.remove(at: row)
        directoryList.reloadData()
    }

    func apply(to s: TerminalSettings) {
        s.pluginDirectories = directories
    }
}

extension PluginTab: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { directories.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0 && row < directories.count else { return nil }
        return directories[row]
    }
}

// MARK: - Local Shell Tab (port of IDD_TABSHEET_CYGWIN)

final class LocalShellTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.localShell")
    let contentView = NSView()

    private var shellPathField: NSTextField!
    private var termEnvField: NSTextField!
    private var loginShellCheck: NSButton!
    private var homeChdirCheck: NSButton!
    private var env1Field: NSTextField!
    private var env2Field: NSTextField!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        // Shell path
        let pathLabel = NSView.makeLabel(TTL("dialog.localShell.shellPath"), alignment: .right)
        pathLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        shellPathField = NSView.makeTextField(s.localShellPath.isEmpty ? defaultShell : s.localShellPath)
        shellPathField.placeholderString = defaultShell
        shellPathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        // TERM environment
        let termLabel = NSView.makeLabel("TERM", alignment: .right)
        termLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        termEnvField = NSView.makeTextField(s.localShellTermEnv)
        termEnvField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        // Options
        loginShellCheck = NSView.makeCheckbox(TTL("dialog.localShell.loginShell"), checked: s.localShellLoginShell)
        homeChdirCheck = NSView.makeCheckbox(TTL("dialog.localShell.homeChdir"), checked: s.localShellHomeChdir)

        let optionRow = NSStackView(views: [loginShellCheck, homeChdirCheck])
        optionRow.translatesAutoresizingMaskIntoConstraints = false
        optionRow.orientation = .horizontal
        optionRow.spacing = 16

        // Custom environment variables
        let env1Label = NSView.makeLabel(TTL("dialog.localShell.env1"), alignment: .right)
        env1Label.setContentCompressionResistancePriority(.required, for: .horizontal)
        env1Field = NSView.makeTextField(s.localShellEnv1)
        env1Field.placeholderString = "KEY=VALUE"
        env1Field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        let env2Label = NSView.makeLabel(TTL("dialog.localShell.env2"), alignment: .right)
        env2Label.setContentCompressionResistancePriority(.required, for: .horizontal)
        env2Field = NSView.makeTextField(s.localShellEnv2)
        env2Field.placeholderString = "KEY=VALUE"
        env2Field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        // Layout with NSGridView for 2-column form
        let grid = NSGridView(views: [
            [pathLabel, shellPathField],
            [termLabel, termEnvField],
            [NSGridCell.emptyContentView, optionRow],
            [env1Label, env1Field],
            [env2Label, env2Field],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = DialogLayout.rowSpacing
        grid.columnSpacing = DialogLayout.labelTrailing
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        contentView.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    func apply(to s: TerminalSettings) {
        let defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let path = shellPathField.stringValue
        s.localShellPath = (path == defaultShell) ? "" : path
        s.localShellTermEnv = termEnvField.stringValue.isEmpty ? "xterm-256color" : termEnvField.stringValue
        s.localShellLoginShell = loginShellCheck.state == .on
        s.localShellHomeChdir = homeChdirCheck.state == .on
        s.localShellEnv1 = env1Field.stringValue
        s.localShellEnv2 = env2Field.stringValue
    }
}

// MARK: - Debug Tab (IDD_TABSHEET_DEBUG)

final class DebugTab: AdditionalSettingsTab {
    let tabTitle = TTL("tab.debug")
    let contentView = NSView()

    private var charInfoCheck: NSButton!
    private var debugModesPopup: NSPopUpButton!

    init(settings: TerminalSettings) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        buildUI(settings)
    }

    private func buildUI(_ s: TerminalSettings) {
        charInfoCheck = NSView.makeCheckbox(TTL("dialog.debug.charInfoPopup"), checked: s.debugCharInfoPopup)

        let modesLabel = NSView.makeLabel(TTL("dialog.debug.debugModes"), alignment: .left)
        debugModesPopup = NSView.makePopUpButton(
            items: ["all", "none", "normal", "hex", "noout"],
            selected: s.debugModes, width: 120)
        let modesRow = NSStackView(views: [modesLabel, debugModesPopup])
        modesRow.translatesAutoresizingMaskIntoConstraints = false
        modesRow.orientation = .horizontal
        modesRow.spacing = 8

        let stack = NSStackView(views: [charInfoCheck, modesRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        ])
    }

    func apply(to s: TerminalSettings) {
        s.debugCharInfoPopup = charInfoCheck.state == .on
        s.debugModes = debugModesPopup.titleOfSelectedItem ?? "all"
    }
}

#endif
