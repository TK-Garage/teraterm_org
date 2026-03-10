/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * SSH-related setup dialogs:
 *   - SSH SCP (IDD_SSHSCP)
 *   - Proxy Setup (IDD_SETTING)
 *   - SSH Setup (IDD_SSHSETUP)
 *   - SSH Authentication Setup (IDD_SSHAUTHSETUP)
 *   - SSH Forwarding Setup (IDD_SSHFWDSETUP / IDD_SSHFWDEDIT)
 *   - SSH Key Generation (IDD_SSHKEYGEN)
 *   - General Setup (IDD_GENDLG)
 *   - Print (OS standard)
 *
 * SSH functionality uses macOS system ssh/scp/ssh-keygen commands.
 */

#if canImport(AppKit)
import AppKit

// MARK: - SSH SCP Dialog (IDD_SSHSCP)

/// SCP file transfer dialog using system /usr/bin/scp.
final class SCPDialogController: BaseSetupDialogController {

    private var settings: TerminalSettings
    private var sendFromField: NSTextField!
    private var sendToField: NSTextField!
    private var receiveFromField: NSTextField!
    private var receiveToField: NSTextField!
    private var progressLabel: NSTextField!

    /// Callback for SCP send: (localPath, remotePath)
    var onSend: ((String, String) -> Void)?
    /// Callback for SCP receive: (remotePath, localDir)
    var onReceive: ((String, String) -> Void)?

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.scp.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        okButton.title = TTL("dialog.scp.send")
        setupControls()
    }

    private func setupControls() {
        let dialogWidth: CGFloat = 460
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        // ── Send section ──
        let sendFromLabel = NSView.makeLabel(TTL("dialog.scp.sendFrom"))
        sendFromField = NSView.makeTextField()
        let sendBrowseButton = NSView.makePushButton("...", keyEquivalent: "")
        sendBrowseButton.target = self
        sendBrowseButton.action = #selector(browseSendFile(_:))
        for c in sendBrowseButton.constraints where c.firstAttribute == .width {
            c.isActive = false
        }
        sendBrowseButton.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let sendFromRow = NSStackView(views: [sendFromLabel, sendFromField, sendBrowseButton])
        sendFromRow.translatesAutoresizingMaskIntoConstraints = false
        sendFromRow.orientation = .horizontal
        sendFromRow.spacing = DialogLayout.labelTrailing
        sendFromRow.alignment = .firstBaseline
        sendFromField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let sendToLabel = NSView.makeLabel(TTL("dialog.scp.sendTo"))
        sendToField = NSView.makeTextField(value: "~/")

        let sendToRow = NSStackView(views: [sendToLabel, sendToField])
        sendToRow.translatesAutoresizingMaskIntoConstraints = false
        sendToRow.orientation = .horizontal
        sendToRow.spacing = DialogLayout.labelTrailing
        sendToRow.alignment = .firstBaseline
        sendToField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let dragNote = NSView.makeLabel(TTL("dialog.scp.dragNote"), alignment: .left)
        dragNote.textColor = .secondaryLabelColor
        dragNote.font = NSFont.systemFont(ofSize: 11)

        let sendButton = NSView.makePushButton(TTL("dialog.scp.send"), keyEquivalent: "")
        sendButton.target = self
        sendButton.action = #selector(doSend(_:))

        let sendStack = NSStackView(views: [sendFromRow, sendToRow, dragNote])
        sendStack.translatesAutoresizingMaskIntoConstraints = false
        sendStack.orientation = .vertical
        sendStack.alignment = .leading
        sendStack.spacing = DialogLayout.rowSpacing
        contentArea.addSubview(sendStack)

        // ── Separator ──
        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        contentArea.addSubview(separator)

        // ── Receive section ──
        let recvFromLabel = NSView.makeLabel(TTL("dialog.scp.receiveFrom"))
        receiveFromField = NSView.makeTextField()

        let recvFromRow = NSStackView(views: [recvFromLabel, receiveFromField])
        recvFromRow.translatesAutoresizingMaskIntoConstraints = false
        recvFromRow.orientation = .horizontal
        recvFromRow.spacing = DialogLayout.labelTrailing
        recvFromRow.alignment = .firstBaseline
        receiveFromField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let recvToLabel = NSView.makeLabel(TTL("dialog.scp.receiveTo"))
        receiveToField = NSView.makeTextField(value: "~/Downloads/")
        let recvBrowseButton = NSView.makePushButton("...", keyEquivalent: "")
        recvBrowseButton.target = self
        recvBrowseButton.action = #selector(browseRecvDir(_:))
        for c in recvBrowseButton.constraints where c.firstAttribute == .width {
            c.isActive = false
        }
        recvBrowseButton.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let recvToRow = NSStackView(views: [recvToLabel, receiveToField, recvBrowseButton])
        recvToRow.translatesAutoresizingMaskIntoConstraints = false
        recvToRow.orientation = .horizontal
        recvToRow.spacing = DialogLayout.labelTrailing
        recvToRow.alignment = .firstBaseline
        receiveToField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let receiveButton = NSView.makePushButton(TTL("dialog.scp.receive"), keyEquivalent: "")
        receiveButton.target = self
        receiveButton.action = #selector(doReceive(_:))

        let recvStack = NSStackView(views: [recvFromRow, recvToRow])
        recvStack.translatesAutoresizingMaskIntoConstraints = false
        recvStack.orientation = .vertical
        recvStack.alignment = .leading
        recvStack.spacing = DialogLayout.rowSpacing
        contentArea.addSubview(recvStack)

        // ── Progress label ──
        progressLabel = NSView.makeLabel("", alignment: .left)
        progressLabel.textColor = .secondaryLabelColor
        contentArea.addSubview(progressLabel)

        // ── Layout ──
        NSLayoutConstraint.activate([
            sendStack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            sendStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            sendStack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            sendFromRow.widthAnchor.constraint(equalTo: sendStack.widthAnchor),
            sendToRow.widthAnchor.constraint(equalTo: sendStack.widthAnchor),

            separator.topAnchor.constraint(equalTo: sendStack.bottomAnchor, constant: DialogLayout.sectionSpacing),
            separator.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),

            recvStack.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: DialogLayout.sectionSpacing),
            recvStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            recvStack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            recvFromRow.widthAnchor.constraint(equalTo: recvStack.widthAnchor),
            recvToRow.widthAnchor.constraint(equalTo: recvStack.widthAnchor),

            progressLabel.topAnchor.constraint(equalTo: recvStack.bottomAnchor, constant: DialogLayout.rowSpacing),
            progressLabel.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            progressLabel.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])
    }

    @objc private func browseSendFile(_ sender: Any?) {
        guard let win = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = TTL("dialog.scp.selectFile")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: win) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.sendFromField.stringValue = url.path
        }
    }

    @objc private func browseRecvDir(_ sender: Any?) {
        guard let win = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = TTL("dialog.scp.selectDest")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.beginSheetModal(for: win) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.receiveToField.stringValue = url.path
        }
    }

    @objc private func doSend(_ sender: Any?) {
        let localPath = sendFromField.stringValue
        let remotePath = sendToField.stringValue
        guard !localPath.isEmpty else { return }
        onSend?(localPath, remotePath)
    }

    @objc private func doReceive(_ sender: Any?) {
        let remotePath = receiveFromField.stringValue
        let localDir = receiveToField.stringValue
        guard !remotePath.isEmpty else { return }
        onReceive?(remotePath, localDir)
    }

    override func applySettings() {
        // SCP dialog doesn't modify settings — it triggers transfers
    }

    /// Execute SCP using system /usr/bin/scp command.
    static func executeSCP(
        send: Bool, localPath: String, remotePath: String,
        host: String, port: Int, username: String,
        completion: @escaping (Bool, String) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")

        var args = ["-P", "\(port)", "-o", "StrictHostKeyChecking=accept-new"]
        if send {
            args += [localPath, "\(username)@\(host):\(remotePath)"]
        } else {
            args += ["\(username)@\(host):\(remotePath)", localPath]
        }
        process.arguments = args

        let pipe = Pipe()
        process.standardError = pipe

        DispatchQueue.global().async {
            do {
                try process.run()
                process.waitUntilExit()
                let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                let success = process.terminationStatus == 0
                DispatchQueue.main.async {
                    completion(success, errStr)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Proxy Setup Dialog (IDD_SETTING)

final class ProxySetupDialogController: BaseSetupDialogController {

    private var settings: TerminalSettings
    private var typePopup: NSPopUpButton!
    private var hostnameField: NSTextField!
    private var portField: NSTextField!
    private var usernameField: NSTextField!
    private var passwordField: NSSecureTextField!

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.proxy.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        let dialogWidth: CGFloat = 380
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        let typeLabel = NSView.makeLabel(TTL("dialog.proxy.type"))
        typePopup = NSView.makePopUpButton(items: [
            TTL("dialog.proxy.typeNone"),
            TTL("dialog.proxy.typeHTTP"),
            TTL("dialog.proxy.typeSocks4"),
            TTL("dialog.proxy.typeSocks5"),
            TTL("dialog.proxy.typeTelnet"),
        ])
        typePopup.selectItem(at: settings.proxyType)

        let hostLabel = NSView.makeLabel(TTL("dialog.proxy.hostname"))
        hostnameField = NSView.makeTextField(value: settings.proxyHost)

        let portLabel = NSView.makeLabel(TTL("dialog.proxy.port"))
        portField = NSView.makeNumberField(value: settings.proxyPort, width: DialogLayout.narrowFieldWidth)

        let userLabel = NSView.makeLabel(TTL("dialog.proxy.username"))
        usernameField = NSView.makeTextField(value: settings.proxyUsername)

        let passLabel = NSView.makeLabel(TTL("dialog.proxy.password"))
        passwordField = NSView.makeSecureTextField()

        let grid = NSGridView(views: [
            [typeLabel, typePopup],
            [hostLabel, hostnameField],
            [portLabel, portField],
            [userLabel, usernameField],
            [passLabel, passwordField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = DialogLayout.rowSpacing
        grid.columnSpacing = DialogLayout.labelTrailing
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        for i in 0..<grid.numberOfRows {
            grid.row(at: i).rowAlignment = .firstBaseline
        }
        contentArea.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentArea.topAnchor),
            grid.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])
    }

    override func applySettings() {
        settings.proxyType = typePopup.indexOfSelectedItem
        settings.proxyHost = hostnameField.stringValue
        settings.proxyPort = portField.integerValue
        settings.proxyUsername = usernameField.stringValue
        // proxyPassword is not persisted for security
    }
}

// MARK: - SSH Setup Dialog (IDD_SSHSETUP)

final class SSHSetupDialogController: BaseSetupDialogController {

    private var settings: TerminalSettings

    // Algorithm order lists (matching IDD_SSHSETUP layout: top row of 3 + bottom row of 2)
    private var cipherListView: AlgorithmOrderListView!
    private var kexListView: AlgorithmOrderListView!
    private var hostKeyListView: AlgorithmOrderListView!
    private var macListView: AlgorithmOrderListView!
    private var compListView: AlgorithmOrderListView!

    // Known Hosts
    private var knownHostsFileField: NSTextField!
    private var readOnlyHostsFileField: NSTextField!
    private var hostKeyRotationPopup: NSPopUpButton!

    // Options
    private var heartbeatField: NSTextField!
    private var rememberPasswordCheck: NSButton!
    private var forwardAgentCheck: NSButton!
    private var confirmAgentCheck: NSButton!
    private var notifyAgentCheck: NSButton!
    private var verifyDNSCheck: NSButton!
    private var logLevelField: NSTextField!
    private var compressionSlider: NSSlider!
    private var compressionValueLabel: NSTextField!

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.sshSetup.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        let dialogWidth: CGFloat = 640
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        // ═══════════════════════════════════════════════════
        // Top row: Cipher | KEX | Host Key (3 columns)
        // ═══════════════════════════════════════════════════

        cipherListView = AlgorithmOrderListView(
            title: TTL("dialog.sshSetup.cipherOrder"),
            items: settings.sshCipherOrder,
            moveUpTitle: TTL("dialog.sshSetup.moveUp"),
            moveDownTitle: TTL("dialog.sshSetup.moveDown"))

        kexListView = AlgorithmOrderListView(
            title: TTL("dialog.sshSetup.kexOrder"),
            items: settings.sshKexOrder,
            moveUpTitle: TTL("dialog.sshSetup.moveUp"),
            moveDownTitle: TTL("dialog.sshSetup.moveDown"))

        hostKeyListView = AlgorithmOrderListView(
            title: TTL("dialog.sshSetup.hostKeyOrder"),
            items: settings.sshHostKeyOrder,
            moveUpTitle: TTL("dialog.sshSetup.moveUp"),
            moveDownTitle: TTL("dialog.sshSetup.moveDown"))

        let topRow = NSStackView(views: [cipherListView, kexListView, hostKeyListView])
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.orientation = .horizontal
        topRow.spacing = DialogLayout.innerMargin
        topRow.distribution = .fillEqually

        // ═══════════════════════════════════════════════════
        // Bottom left: MAC | Compression (2 columns)
        // ═══════════════════════════════════════════════════

        macListView = AlgorithmOrderListView(
            title: TTL("dialog.sshSetup.macOrder"),
            items: settings.sshMACOrder,
            moveUpTitle: TTL("dialog.sshSetup.moveUp"),
            moveDownTitle: TTL("dialog.sshSetup.moveDown"))

        compListView = AlgorithmOrderListView(
            title: TTL("dialog.sshSetup.compOrder"),
            items: settings.sshCompressionOrder,
            moveUpTitle: TTL("dialog.sshSetup.moveUp"),
            moveDownTitle: TTL("dialog.sshSetup.moveDown"))

        let bottomAlgoRow = NSStackView(views: [macListView, compListView])
        bottomAlgoRow.translatesAutoresizingMaskIntoConstraints = false
        bottomAlgoRow.orientation = .horizontal
        bottomAlgoRow.spacing = DialogLayout.innerMargin
        bottomAlgoRow.distribution = .fillEqually

        // ═══════════════════════════════════════════════════
        // Known Hosts group box
        // ═══════════════════════════════════════════════════

        let knownHostsBox = NSView.makeGroupBox(title: TTL("dialog.sshSetup.knownHosts"))
        let khContent = NSView()
        khContent.translatesAutoresizingMaskIntoConstraints = false

        let rwLabel = NSView.makeLabel(TTL("dialog.sshSetup.knownHostsFile"))
        knownHostsFileField = NSView.makeTextField(value: settings.sshKnownHostsFile)
        let rwBrowse = NSView.makePushButton(TTL("dialog.sshSetup.browse"))
        rwBrowse.target = self
        rwBrowse.action = #selector(browseKnownHostsFile(_:))

        let rwRow = NSStackView(views: [rwLabel, knownHostsFileField, rwBrowse])
        rwRow.translatesAutoresizingMaskIntoConstraints = false
        rwRow.orientation = .horizontal
        rwRow.spacing = 6
        rwRow.alignment = .firstBaseline

        let roLabel = NSView.makeLabel(TTL("dialog.sshSetup.readOnlyFiles"))
        readOnlyHostsFileField = NSView.makeTextField(value: settings.sshReadOnlyHostsFile)
        let roBrowse = NSView.makePushButton(TTL("dialog.sshSetup.browse"))
        roBrowse.target = self
        roBrowse.action = #selector(browseReadOnlyHostsFile(_:))

        let roRow = NSStackView(views: [roLabel, readOnlyHostsFileField, roBrowse])
        roRow.translatesAutoresizingMaskIntoConstraints = false
        roRow.orientation = .horizontal
        roRow.spacing = 6
        roRow.alignment = .firstBaseline

        let rotLabel = NSView.makeLabel(TTL("dialog.sshSetup.hostKeyRotation"))
        hostKeyRotationPopup = NSView.makePopUpButton(
            items: [
                TTL("dialog.sshSetup.rotationDisabled"),
                TTL("dialog.sshSetup.rotationEnabled"),
                TTL("dialog.sshSetup.rotationAsk"),
            ],
            width: 120)
        if settings.sshHostKeyRotation >= 0 && settings.sshHostKeyRotation <= 2 {
            hostKeyRotationPopup.selectItem(at: settings.sshHostKeyRotation)
        }

        let rotRow = NSStackView(views: [rotLabel, hostKeyRotationPopup])
        rotRow.translatesAutoresizingMaskIntoConstraints = false
        rotRow.orientation = .horizontal
        rotRow.spacing = 6
        rotRow.alignment = .firstBaseline

        let khStack = NSStackView(views: [rwRow, roRow, rotRow])
        khStack.translatesAutoresizingMaskIntoConstraints = false
        khStack.orientation = .vertical
        khStack.alignment = .leading
        khStack.spacing = 6
        khContent.addSubview(khStack)

        let khPad = DialogLayout.groupBoxPadding
        NSLayoutConstraint.activate([
            khStack.topAnchor.constraint(equalTo: khContent.topAnchor, constant: khPad),
            khStack.leadingAnchor.constraint(equalTo: khContent.leadingAnchor, constant: khPad),
            khStack.trailingAnchor.constraint(equalTo: khContent.trailingAnchor, constant: -khPad),
            khStack.bottomAnchor.constraint(equalTo: khContent.bottomAnchor, constant: -khPad),
            knownHostsFileField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            readOnlyHostsFileField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        knownHostsBox.contentView = khContent

        // ═══════════════════════════════════════════════════
        // Bottom options: left side + right side
        // ═══════════════════════════════════════════════════

        // ── Heartbeat ──
        let heartbeatLabel = NSView.makeLabel(TTL("dialog.sshSetup.heartbeat"))
        heartbeatField = NSView.makeNumberField(value: settings.sshHeartbeat, width: 50)
        let heartbeatUnit = NSView.makeLabel(TTL("dialog.sshSetup.heartbeatSec"), alignment: .left)

        let heartbeatRow = NSStackView(views: [heartbeatLabel, heartbeatField, heartbeatUnit])
        heartbeatRow.translatesAutoresizingMaskIntoConstraints = false
        heartbeatRow.orientation = .horizontal
        heartbeatRow.spacing = DialogLayout.labelTrailing
        heartbeatRow.alignment = .firstBaseline

        // ── Checkboxes ──
        rememberPasswordCheck = NSView.makeCheckbox(
            TTL("dialog.sshSetup.rememberPassword"), checked: settings.sshRememberPassword)
        forwardAgentCheck = NSView.makeCheckbox(
            TTL("dialog.sshSetup.forwardAgent"), checked: settings.sshForwardAgent)
        confirmAgentCheck = NSView.makeCheckbox(
            TTL("dialog.sshSetup.confirmAgent"), checked: settings.sshConfirmAgentForwarding)
        notifyAgentCheck = NSView.makeCheckbox(
            TTL("dialog.sshSetup.notifyAgent"), checked: settings.sshNotifyAgentAccess)
        verifyDNSCheck = NSView.makeCheckbox(
            TTL("dialog.sshSetup.verifyDNS"), checked: settings.sshVerifyHostKeyDNS)

        // ── Log Level ──
        let logLabel = NSView.makeLabel(TTL("dialog.sshSetup.logLevel"))
        logLevelField = NSView.makeNumberField(value: settings.sshLogLevel, width: 50)
        let logUnit = NSView.makeLabel(TTL("dialog.sshSetup.logLevelUnit"), alignment: .left)

        let logRow = NSStackView(views: [logLabel, logLevelField, logUnit])
        logRow.translatesAutoresizingMaskIntoConstraints = false
        logRow.orientation = .horizontal
        logRow.spacing = DialogLayout.labelTrailing
        logRow.alignment = .firstBaseline

        // ── Compression Level ──
        let compLabel = NSView.makeLabel(TTL("dialog.sshSetup.compressionLevel"))
        compressionSlider = NSView.makeSlider(min: 0, max: 9, value: Double(settings.sshCompressionLevel))
        compressionSlider.numberOfTickMarks = 10
        compressionSlider.allowsTickMarkValuesOnly = true
        compressionSlider.target = self
        compressionSlider.action = #selector(compressionSliderChanged(_:))
        compressionSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let noneLabel = NSView.makeLabel(TTL("dialog.sshSetup.compressionNone"), alignment: .left)
        noneLabel.font = NSFont.systemFont(ofSize: 10)
        let highLabel = NSView.makeLabel(TTL("dialog.sshSetup.compressionHigh"), alignment: .left)
        highLabel.font = NSFont.systemFont(ofSize: 10)

        compressionValueLabel = NSView.makeLabel("\(settings.sshCompressionLevel)", alignment: .left)
        compressionValueLabel.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let compRow = NSStackView(views: [compLabel, noneLabel, compressionSlider, highLabel, compressionValueLabel])
        compRow.translatesAutoresizingMaskIntoConstraints = false
        compRow.orientation = .horizontal
        compRow.spacing = 4
        compRow.alignment = .centerY

        // ── Notice ──
        let noticeLabel = NSView.makeLabel(TTL("dialog.sshSetup.notice"), alignment: .left)
        noticeLabel.textColor = .secondaryLabelColor
        noticeLabel.font = NSFont.systemFont(ofSize: 11)

        // ── Options column ──
        let optionsStack = NSStackView(views: [
            heartbeatRow,
            rememberPasswordCheck, forwardAgentCheck,
            confirmAgentCheck, notifyAgentCheck, verifyDNSCheck,
            logRow, compRow, noticeLabel,
        ])
        optionsStack.translatesAutoresizingMaskIntoConstraints = false
        optionsStack.orientation = .vertical
        optionsStack.alignment = .leading
        optionsStack.spacing = DialogLayout.rowSpacing

        // ═══════════════════════════════════════════════════
        // Main vertical stack
        // ═══════════════════════════════════════════════════

        let mainStack = NSStackView(views: [
            topRow, bottomAlgoRow, knownHostsBox, optionsStack,
        ])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = DialogLayout.sectionSpacing
        contentArea.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            topRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            bottomAlgoRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            knownHostsBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func browseKnownHostsFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.knownHostsFileField.stringValue = url.path
            }
        }
    }

    @objc private func browseReadOnlyHostsFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.readOnlyHostsFileField.stringValue = url.path
            }
        }
    }

    @objc private func compressionSliderChanged(_ sender: NSSlider) {
        compressionValueLabel.stringValue = "\(sender.integerValue)"
    }

    // MARK: - Apply

    override func applySettings() {
        // Algorithm orders
        settings.sshCipherOrder = cipherListView.orderedItems
        settings.sshKexOrder = kexListView.orderedItems
        settings.sshHostKeyOrder = hostKeyListView.orderedItems
        settings.sshMACOrder = macListView.orderedItems
        settings.sshCompressionOrder = compListView.orderedItems

        // Known Hosts
        settings.sshKnownHostsFile = knownHostsFileField.stringValue
        settings.sshReadOnlyHostsFile = readOnlyHostsFileField.stringValue
        settings.sshHostKeyRotation = hostKeyRotationPopup.indexOfSelectedItem

        // Options
        settings.sshHeartbeat = heartbeatField.integerValue
        settings.sshRememberPassword = rememberPasswordCheck.state == .on
        settings.sshForwardAgent = forwardAgentCheck.state == .on
        settings.sshConfirmAgentForwarding = confirmAgentCheck.state == .on
        settings.sshNotifyAgentAccess = notifyAgentCheck.state == .on
        settings.sshVerifyHostKeyDNS = verifyDNSCheck.state == .on
        settings.sshLogLevel = logLevelField.integerValue
        settings.sshCompressionLevel = compressionSlider.integerValue
    }
}

// MARK: - Algorithm Order List View (reusable for cipher/kex/hostkey/mac/comp)

/// A group box containing a scrollable list and move up/down buttons.
/// Matches the LISTBOX + PUSHBUTTON pattern from IDD_SSHSETUP.
private final class AlgorithmOrderListView: NSView, NSTableViewDataSource, NSTableViewDelegate {

    private var items: [String]
    private let tableView: NSTableView
    private let scrollView: NSScrollView
    private let moveUpButton: NSButton
    private let moveDownButton: NSButton

    var orderedItems: [String] { items }

    init(title: String, items: [String], moveUpTitle: String, moveDownTitle: String) {
        self.items = items

        // Table view
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 18
        tableView.focusRingType = .none
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("algo"))
        column.title = ""
        column.isEditable = false
        tableView.addTableColumn(column)

        // Scroll view
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        // Buttons
        moveUpButton = NSView.makePushButton(moveUpTitle)
        moveDownButton = NSView.makePushButton(moveDownTitle)

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self

        moveUpButton.target = self
        moveUpButton.action = #selector(moveUp(_:))
        moveDownButton.target = self
        moveDownButton.action = #selector(moveDown(_:))

        // Layout: group box containing scroll view + buttons
        let box = NSView.makeGroupBox(title: title)
        let boxContent = NSView()
        boxContent.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [moveUpButton, moveDownButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = DialogLayout.buttonSpacing

        boxContent.addSubview(scrollView)
        boxContent.addSubview(buttonRow)

        let pad = DialogLayout.groupBoxPadding
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: boxContent.topAnchor, constant: pad),
            scrollView.leadingAnchor.constraint(equalTo: boxContent.leadingAnchor, constant: pad),
            scrollView.trailingAnchor.constraint(equalTo: boxContent.trailingAnchor, constant: -pad),
            scrollView.heightAnchor.constraint(equalToConstant: 80),

            buttonRow.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            buttonRow.centerXAnchor.constraint(equalTo: boxContent.centerXAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: boxContent.bottomAnchor, constant: -pad),
        ])
        box.contentView = boxContent

        addSubview(box)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor),
            box.leadingAnchor.constraint(equalTo: leadingAnchor),
            box.trailingAnchor.constraint(equalTo: trailingAnchor),
            box.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Actions

    @objc private func moveUp(_ sender: Any?) {
        let row = tableView.selectedRow
        guard row > 0 else { return }
        items.swapAt(row, row - 1)
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: row - 1), byExtendingSelection: false)
    }

    @objc private func moveDown(_ sender: Any?) {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count - 1 else { return }
        items.swapAt(row, row + 1)
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: row + 1), byExtendingSelection: false)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return items[row]
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("AlgoCell")
        var cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField
        if cell == nil {
            cell = NSTextField(labelWithString: "")
            cell!.identifier = cellID
            cell!.font = NSFont.systemFont(ofSize: 11)
            cell!.lineBreakMode = .byTruncatingTail
        }
        cell!.stringValue = items[row]
        return cell
    }
}

// MARK: - SSH Authentication Setup Dialog (IDD_SSHAUTHSETUP)

final class SSHAuthSetupDialogController: BaseSetupDialogController {

    private var settings: TerminalSettings

    // Username mode radios
    private var noUsernameRadio: NSButton!
    private var defaultUsernameRadio: NSButton!
    private var logonUsernameRadio: NSButton!
    private var defaultUsernameField: NSTextField!

    // Auth method radios
    private var passwordRadio: NSButton!
    private var publicKeyRadio: NSButton!
    private var rhostsRadio: NSButton!
    private var challengeRadio: NSButton!
    private var pageantRadio: NSButton!

    // Private key
    private var privateKeyField: NSTextField!
    private var browseButton: NSButton!

    // Options
    private var checkAuthCheck: NSButton!

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.sshAuthSetup.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        let dialogWidth: CGFloat = 440
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        let bannerLabel = NSView.makeLabel(TTL("dialog.sshAuthSetup.banner"), alignment: .left)

        // ── Username group ──
        let usernameBox = NSView.makeGroupBox(title: TTL("dialog.sshAuthSetup.usernameGroup"))

        noUsernameRadio = NSView.makeRadioButton(TTL("dialog.sshAuthSetup.noUsername"), tag: 0)
        defaultUsernameRadio = NSView.makeRadioButton(TTL("dialog.sshAuthSetup.defaultUsername"), tag: 1)
        logonUsernameRadio = NSView.makeRadioButton(TTL("dialog.sshAuthSetup.logonUsername"), tag: 2)

        for radio in [noUsernameRadio!, defaultUsernameRadio!, logonUsernameRadio!] {
            radio.target = self
            radio.action = #selector(usernameRadioChanged(_:))
        }

        defaultUsernameField = NSView.makeTextField(value: settings.sshDefaultUsername)

        let currentUser = ProcessInfo.processInfo.userName
        let logonUserLabel = NSView.makeLabel(
            TTL("dialog.sshAuthSetup.currentUser", currentUser), alignment: .left)
        logonUserLabel.textColor = .secondaryLabelColor
        logonUserLabel.font = NSFont.systemFont(ofSize: 11)

        let usernameContent = NSView()
        usernameContent.translatesAutoresizingMaskIntoConstraints = false
        let usernameStack = NSStackView(views: [
            noUsernameRadio, defaultUsernameRadio, defaultUsernameField,
            logonUsernameRadio, logonUserLabel,
        ])
        usernameStack.translatesAutoresizingMaskIntoConstraints = false
        usernameStack.orientation = .vertical
        usernameStack.alignment = .leading
        usernameStack.spacing = 6
        usernameContent.addSubview(usernameStack)
        let uPad = DialogLayout.groupBoxPadding
        NSLayoutConstraint.activate([
            usernameStack.topAnchor.constraint(equalTo: usernameContent.topAnchor, constant: uPad),
            usernameStack.leadingAnchor.constraint(equalTo: usernameContent.leadingAnchor, constant: uPad),
            usernameStack.trailingAnchor.constraint(equalTo: usernameContent.trailingAnchor, constant: -uPad),
            usernameStack.bottomAnchor.constraint(equalTo: usernameContent.bottomAnchor, constant: -uPad),
            defaultUsernameField.widthAnchor.constraint(equalToConstant: 200),
        ])
        usernameBox.contentView = usernameContent

        // Set initial radio state
        switch settings.sshDefaultUsernameMode {
        case 1: defaultUsernameRadio.state = .on
        case 2: logonUsernameRadio.state = .on
        default: noUsernameRadio.state = .on
        }

        // ── Auth method group ──
        let authBox = NSView.makeGroupBox(title: TTL("dialog.sshAuth.title"))

        passwordRadio = NSView.makeRadioButton(TTL("dialog.sshAuth.usePassword"), tag: 0)
        publicKeyRadio = NSView.makeRadioButton(TTL("dialog.sshAuth.usePublicKey"), tag: 1)
        rhostsRadio = NSView.makeRadioButton(TTL("dialog.sshAuth.useRhosts"), tag: 2)
        challengeRadio = NSView.makeRadioButton(TTL("dialog.sshAuth.useChallenge"), tag: 3)
        pageantRadio = NSView.makeRadioButton(TTL("dialog.sshAuth.usePageant"), tag: 4)

        for radio in [passwordRadio!, publicKeyRadio!, rhostsRadio!, challengeRadio!, pageantRadio!] {
            radio.target = self
            radio.action = #selector(authMethodChanged(_:))
        }

        switch settings.sshAuthMethod {
        case .password: passwordRadio.state = .on
        case .publicKey: publicKeyRadio.state = .on
        case .rhosts: rhostsRadio.state = .on
        case .challengeResponse: challengeRadio.state = .on
        case .pageant: pageantRadio.state = .on
        }

        let keyLabel = NSView.makeLabel(TTL("dialog.sshAuth.privateKey"), alignment: .left)
        privateKeyField = NSView.makeTextField(value: settings.sshKeyFile)
        privateKeyField.isEditable = false
        browseButton = NSView.makePushButton("...", keyEquivalent: "")
        browseButton.target = self
        browseButton.action = #selector(browseKeyFile(_:))
        for c in browseButton.constraints where c.firstAttribute == .width { c.isActive = false }
        browseButton.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let keyRow = NSStackView(views: [keyLabel, privateKeyField, browseButton])
        keyRow.translatesAutoresizingMaskIntoConstraints = false
        keyRow.orientation = .horizontal
        keyRow.spacing = DialogLayout.labelTrailing
        keyRow.alignment = .firstBaseline
        privateKeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let authContent = NSView()
        authContent.translatesAutoresizingMaskIntoConstraints = false
        let authStack = NSStackView(views: [
            passwordRadio, publicKeyRadio, keyRow,
            rhostsRadio, challengeRadio, pageantRadio,
        ])
        authStack.translatesAutoresizingMaskIntoConstraints = false
        authStack.orientation = .vertical
        authStack.alignment = .leading
        authStack.spacing = 6
        authContent.addSubview(authStack)
        let aPad = DialogLayout.groupBoxPadding
        NSLayoutConstraint.activate([
            authStack.topAnchor.constraint(equalTo: authContent.topAnchor, constant: aPad),
            authStack.leadingAnchor.constraint(equalTo: authContent.leadingAnchor, constant: aPad),
            authStack.trailingAnchor.constraint(equalTo: authContent.trailingAnchor, constant: -aPad),
            authStack.bottomAnchor.constraint(equalTo: authContent.bottomAnchor, constant: -aPad),
            keyRow.widthAnchor.constraint(equalTo: authStack.widthAnchor),
        ])
        authBox.contentView = authContent

        // ── Check auth ──
        checkAuthCheck = NSView.makeCheckbox(
            TTL("dialog.sshAuthSetup.checkAuth"), checked: settings.sshCheckAuthBeforeLogin)

        // ── Main stack ──
        let mainStack = NSStackView(views: [bannerLabel, usernameBox, authBox, checkAuthCheck])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = DialogLayout.rowSpacing
        contentArea.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            usernameBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            authBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    @objc private func usernameRadioChanged(_ sender: NSButton) {
        for radio in [noUsernameRadio!, defaultUsernameRadio!, logonUsernameRadio!] {
            radio.state = (radio === sender) ? .on : .off
        }
        defaultUsernameField.isEnabled = (defaultUsernameRadio.state == .on)
    }

    @objc private func authMethodChanged(_ sender: NSButton) {
        for radio in [passwordRadio!, publicKeyRadio!, rhostsRadio!, challengeRadio!, pageantRadio!] {
            radio.state = (radio === sender) ? .on : .off
        }
        let needsKey = (publicKeyRadio.state == .on)
        privateKeyField.isEnabled = needsKey
        browseButton.isEnabled = needsKey
    }

    @objc private func browseKeyFile(_ sender: Any?) {
        guard let win = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = TTL("dialog.sshAuth.selectKeyFile")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if FileManager.default.fileExists(atPath: sshDir.path) {
            panel.directoryURL = sshDir
        }
        panel.beginSheetModal(for: win) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.privateKeyField.stringValue = url.path
        }
    }

    override func applySettings() {
        if defaultUsernameRadio.state == .on {
            settings.sshDefaultUsernameMode = 1
            settings.sshDefaultUsername = defaultUsernameField.stringValue
        } else if logonUsernameRadio.state == .on {
            settings.sshDefaultUsernameMode = 2
        } else {
            settings.sshDefaultUsernameMode = 0
        }

        if publicKeyRadio.state == .on {
            settings.sshAuthMethod = .publicKey
        } else if rhostsRadio.state == .on {
            settings.sshAuthMethod = .rhosts
        } else if challengeRadio.state == .on {
            settings.sshAuthMethod = .challengeResponse
        } else if pageantRadio.state == .on {
            settings.sshAuthMethod = .pageant
        } else {
            settings.sshAuthMethod = .password
        }

        settings.sshKeyFile = privateKeyField.stringValue
        settings.sshCheckAuthBeforeLogin = checkAuthCheck.state == .on
    }
}

// MARK: - SSH Forwarding Setup Dialog (IDD_SSHFWDSETUP)

final class SSHForwardingSetupDialogController: BaseSetupDialogController {

    private var settings: TerminalSettings
    private var forwardingList: NSTableView!
    private var forwardings: [String] = []
    private var xForwardingCheck: NSButton!

    init(settings: TerminalSettings) {
        self.settings = settings
        self.forwardings = settings.sshPortForwardings
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.sshFwd.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        let dialogWidth: CGFloat = 440
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        // ── Port forwarding group ──
        let fwdBox = NSView.makeGroupBox(title: TTL("dialog.sshFwd.portForwarding"))
        let fwdContent = NSView()
        fwdContent.translatesAutoresizingMaskIntoConstraints = false

        // Table view for forwarding rules
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        forwardingList = NSTableView()
        forwardingList.headerView = nil
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rule"))
        column.title = ""
        forwardingList.addTableColumn(column)
        forwardingList.delegate = self
        forwardingList.dataSource = self
        scrollView.documentView = forwardingList

        // Buttons
        let addButton = NSView.makePushButton(TTL("dialog.sshFwd.add"))
        addButton.target = self
        addButton.action = #selector(addForwarding(_:))

        let editButton = NSView.makePushButton(TTL("dialog.sshFwd.edit"))
        editButton.target = self
        editButton.action = #selector(editForwarding(_:))

        let removeButton = NSView.makePushButton(TTL("dialog.sshFwd.remove"))
        removeButton.target = self
        removeButton.action = #selector(removeForwarding(_:))

        let buttonRow = NSStackView(views: [addButton, editButton, removeButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = DialogLayout.buttonSpacing

        fwdContent.addSubview(scrollView)
        fwdContent.addSubview(buttonRow)

        let fPad = DialogLayout.groupBoxPadding
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: fwdContent.topAnchor, constant: fPad),
            scrollView.leadingAnchor.constraint(equalTo: fwdContent.leadingAnchor, constant: fPad),
            scrollView.trailingAnchor.constraint(equalTo: fwdContent.trailingAnchor, constant: -fPad),
            scrollView.heightAnchor.constraint(equalToConstant: 120),
            buttonRow.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: DialogLayout.rowSpacing),
            buttonRow.centerXAnchor.constraint(equalTo: fwdContent.centerXAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: fwdContent.bottomAnchor, constant: -fPad),
        ])
        fwdBox.contentView = fwdContent

        // ── X Forwarding ──
        let xBox = NSView.makeGroupBox(title: TTL("dialog.sshFwd.xForwarding"))
        let xContent = NSView()
        xContent.translatesAutoresizingMaskIntoConstraints = false
        xForwardingCheck = NSView.makeCheckbox(
            TTL("dialog.sshFwd.xDisplay"), checked: settings.sshXForwarding)
        xContent.addSubview(xForwardingCheck)
        let xPad = DialogLayout.groupBoxPadding
        NSLayoutConstraint.activate([
            xForwardingCheck.topAnchor.constraint(equalTo: xContent.topAnchor, constant: xPad),
            xForwardingCheck.leadingAnchor.constraint(equalTo: xContent.leadingAnchor, constant: xPad),
            xForwardingCheck.bottomAnchor.constraint(equalTo: xContent.bottomAnchor, constant: -xPad),
        ])
        xBox.contentView = xContent

        // ── Main layout ──
        let mainStack = NSStackView(views: [fwdBox, xBox])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = DialogLayout.rowSpacing
        contentArea.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            fwdBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            xBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    @objc private func addForwarding(_ sender: Any?) {
        showForwardingEditDialog(rule: nil) { [weak self] rule in
            self?.forwardings.append(rule)
            self?.forwardingList.reloadData()
        }
    }

    @objc private func editForwarding(_ sender: Any?) {
        let row = forwardingList.selectedRow
        guard row >= 0 && row < forwardings.count else { return }
        showForwardingEditDialog(rule: forwardings[row]) { [weak self] rule in
            self?.forwardings[row] = rule
            self?.forwardingList.reloadData()
        }
    }

    @objc private func removeForwarding(_ sender: Any?) {
        let row = forwardingList.selectedRow
        guard row >= 0 && row < forwardings.count else { return }
        forwardings.remove(at: row)
        forwardingList.reloadData()
    }

    private func showForwardingEditDialog(rule: String?, completion: @escaping (String) -> Void) {
        guard let win = view.window else { return }
        let vc = SSHForwardingEditDialogController(rule: rule)
        vc.onSave = completion
        let dialogWindow = NSWindow(contentViewController: vc)
        dialogWindow.styleMask = [.titled, .closable]
        dialogWindow.title = TTL("dialog.sshFwdEdit.title")
        dialogWindow.isReleasedWhenClosed = false
        dialogWindow.styleMask.remove(.resizable)
        win.beginSheet(dialogWindow) { _ in }
    }

    override func applySettings() {
        settings.sshPortForwardings = forwardings
        settings.sshXForwarding = xForwardingCheck.state == .on
    }
}

extension SSHForwardingSetupDialogController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return forwardings.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return forwardings[row]
    }
}

// MARK: - SSH Forwarding Edit Dialog (IDD_SSHFWDEDIT)

final class SSHForwardingEditDialogController: BaseSetupDialogController {

    private var localPortRadio: NSButton!
    private var remotePortRadio: NSButton!
    private var dynamicPortRadio: NSButton!

    private var localFromField: NSTextField!
    private var localListenField: NSTextField!
    private var localToHostField: NSTextField!
    private var localToPortField: NSTextField!

    private var remoteFromField: NSTextField!
    private var remoteListenField: NSTextField!
    private var remoteToHostField: NSTextField!
    private var remoteToPortField: NSTextField!

    private var dynamicFromField: NSTextField!
    private var dynamicListenField: NSTextField!

    var onSave: ((String) -> Void)?
    private let existingRule: String?

    init(rule: String?) {
        self.existingRule = rule
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.sshFwdEdit.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
        if let rule = existingRule { parseRule(rule) }
    }

    private func setupControls() {
        let dialogWidth: CGFloat = 460
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        let bannerLabel = NSView.makeLabel(TTL("dialog.sshFwdEdit.banner"), alignment: .left)

        // Local forwarding
        localPortRadio = NSView.makeRadioButton(TTL("dialog.sshFwdEdit.localPort"), tag: 0)
        localPortRadio.target = self
        localPortRadio.action = #selector(directionChanged(_:))
        localPortRadio.state = .on

        localFromField = NSView.makeTextField(width: 60)
        let localListenLabel = NSView.makeLabel(TTL("dialog.sshFwdEdit.listen"), alignment: .left)
        localListenField = NSView.makeTextField(value: "localhost", width: 120)
        let localRow1 = NSStackView(views: [localPortRadio, localFromField, localListenLabel, localListenField])
        localRow1.translatesAutoresizingMaskIntoConstraints = false
        localRow1.orientation = .horizontal
        localRow1.spacing = DialogLayout.labelTrailing
        localRow1.alignment = .firstBaseline

        let localToHostLabel = NSView.makeLabel(TTL("dialog.sshFwdEdit.toRemote"), alignment: .left)
        localToHostField = NSView.makeTextField(width: 120)
        let localToPortLabel = NSView.makeLabel(TTL("dialog.sshFwdEdit.port"), alignment: .left)
        localToPortField = NSView.makeTextField(width: 60)
        let localRow2 = NSStackView(views: [localToHostLabel, localToHostField, localToPortLabel, localToPortField])
        localRow2.translatesAutoresizingMaskIntoConstraints = false
        localRow2.orientation = .horizontal
        localRow2.spacing = DialogLayout.labelTrailing
        localRow2.alignment = .firstBaseline

        let localBox = NSBox()
        localBox.translatesAutoresizingMaskIntoConstraints = false
        localBox.titlePosition = .noTitle
        let localContent = NSView()
        localContent.translatesAutoresizingMaskIntoConstraints = false
        let localStack = NSStackView(views: [localRow1, localRow2])
        localStack.translatesAutoresizingMaskIntoConstraints = false
        localStack.orientation = .vertical
        localStack.alignment = .leading
        localStack.spacing = DialogLayout.rowSpacing
        localContent.addSubview(localStack)
        let p: CGFloat = 8
        NSLayoutConstraint.activate([
            localStack.topAnchor.constraint(equalTo: localContent.topAnchor, constant: p),
            localStack.leadingAnchor.constraint(equalTo: localContent.leadingAnchor, constant: p),
            localStack.trailingAnchor.constraint(equalTo: localContent.trailingAnchor, constant: -p),
            localStack.bottomAnchor.constraint(equalTo: localContent.bottomAnchor, constant: -p),
        ])
        localBox.contentView = localContent

        // Remote forwarding
        remotePortRadio = NSView.makeRadioButton(TTL("dialog.sshFwdEdit.remotePort"), tag: 1)
        remotePortRadio.target = self
        remotePortRadio.action = #selector(directionChanged(_:))

        remoteFromField = NSView.makeTextField(width: 60)
        let remoteListenLabel = NSView.makeLabel(TTL("dialog.sshFwdEdit.listen"), alignment: .left)
        remoteListenField = NSView.makeTextField(value: "localhost", width: 120)
        let remoteRow1 = NSStackView(views: [remotePortRadio, remoteFromField, remoteListenLabel, remoteListenField])
        remoteRow1.translatesAutoresizingMaskIntoConstraints = false
        remoteRow1.orientation = .horizontal
        remoteRow1.spacing = DialogLayout.labelTrailing
        remoteRow1.alignment = .firstBaseline

        let remoteToHostLabel = NSView.makeLabel(TTL("dialog.sshFwdEdit.toLocal"), alignment: .left)
        remoteToHostField = NSView.makeTextField(value: "localhost", width: 120)
        let remoteToPortLabel = NSView.makeLabel(TTL("dialog.sshFwdEdit.port"), alignment: .left)
        remoteToPortField = NSView.makeTextField(width: 60)
        let remoteRow2 = NSStackView(views: [remoteToHostLabel, remoteToHostField, remoteToPortLabel, remoteToPortField])
        remoteRow2.translatesAutoresizingMaskIntoConstraints = false
        remoteRow2.orientation = .horizontal
        remoteRow2.spacing = DialogLayout.labelTrailing
        remoteRow2.alignment = .firstBaseline

        let remoteBox = NSBox()
        remoteBox.translatesAutoresizingMaskIntoConstraints = false
        remoteBox.titlePosition = .noTitle
        let remoteContent = NSView()
        remoteContent.translatesAutoresizingMaskIntoConstraints = false
        let remoteStack = NSStackView(views: [remoteRow1, remoteRow2])
        remoteStack.translatesAutoresizingMaskIntoConstraints = false
        remoteStack.orientation = .vertical
        remoteStack.alignment = .leading
        remoteStack.spacing = DialogLayout.rowSpacing
        remoteContent.addSubview(remoteStack)
        NSLayoutConstraint.activate([
            remoteStack.topAnchor.constraint(equalTo: remoteContent.topAnchor, constant: p),
            remoteStack.leadingAnchor.constraint(equalTo: remoteContent.leadingAnchor, constant: p),
            remoteStack.trailingAnchor.constraint(equalTo: remoteContent.trailingAnchor, constant: -p),
            remoteStack.bottomAnchor.constraint(equalTo: remoteContent.bottomAnchor, constant: -p),
        ])
        remoteBox.contentView = remoteContent

        // Dynamic forwarding
        dynamicPortRadio = NSView.makeRadioButton(TTL("dialog.sshFwdEdit.dynamicPort"), tag: 2)
        dynamicPortRadio.target = self
        dynamicPortRadio.action = #selector(directionChanged(_:))

        dynamicFromField = NSView.makeTextField(width: 60)
        let dynamicListenLabel = NSView.makeLabel(TTL("dialog.sshFwdEdit.listen"), alignment: .left)
        dynamicListenField = NSView.makeTextField(value: "localhost", width: 120)
        let dynamicRow = NSStackView(views: [dynamicPortRadio, dynamicFromField, dynamicListenLabel, dynamicListenField])
        dynamicRow.translatesAutoresizingMaskIntoConstraints = false
        dynamicRow.orientation = .horizontal
        dynamicRow.spacing = DialogLayout.labelTrailing
        dynamicRow.alignment = .firstBaseline

        let dynamicBox = NSBox()
        dynamicBox.translatesAutoresizingMaskIntoConstraints = false
        dynamicBox.titlePosition = .noTitle
        let dynamicContent = NSView()
        dynamicContent.translatesAutoresizingMaskIntoConstraints = false
        dynamicContent.addSubview(dynamicRow)
        NSLayoutConstraint.activate([
            dynamicRow.topAnchor.constraint(equalTo: dynamicContent.topAnchor, constant: p),
            dynamicRow.leadingAnchor.constraint(equalTo: dynamicContent.leadingAnchor, constant: p),
            dynamicRow.trailingAnchor.constraint(equalTo: dynamicContent.trailingAnchor, constant: -p),
            dynamicRow.bottomAnchor.constraint(equalTo: dynamicContent.bottomAnchor, constant: -p),
        ])
        dynamicBox.contentView = dynamicContent

        let mainStack = NSStackView(views: [bannerLabel, localBox, remoteBox, dynamicBox])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = DialogLayout.rowSpacing
        contentArea.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            localBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            remoteBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            dynamicBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    @objc private func directionChanged(_ sender: NSButton) {
        for radio in [localPortRadio!, remotePortRadio!, dynamicPortRadio!] {
            radio.state = (radio === sender) ? .on : .off
        }
    }

    private func parseRule(_ rule: String) {
        // Format: L:port:listen:host:port or R:port:listen:host:port or D:port:listen
        let parts = rule.components(separatedBy: ":")
        guard parts.count >= 2 else { return }
        switch parts[0] {
        case "L":
            localPortRadio.state = .on
            remotePortRadio.state = .off
            dynamicPortRadio.state = .off
            if parts.count >= 5 {
                localFromField.stringValue = parts[1]
                localListenField.stringValue = parts[2]
                localToHostField.stringValue = parts[3]
                localToPortField.stringValue = parts[4]
            }
        case "R":
            remotePortRadio.state = .on
            localPortRadio.state = .off
            dynamicPortRadio.state = .off
            if parts.count >= 5 {
                remoteFromField.stringValue = parts[1]
                remoteListenField.stringValue = parts[2]
                remoteToHostField.stringValue = parts[3]
                remoteToPortField.stringValue = parts[4]
            }
        case "D":
            dynamicPortRadio.state = .on
            localPortRadio.state = .off
            remotePortRadio.state = .off
            if parts.count >= 3 {
                dynamicFromField.stringValue = parts[1]
                dynamicListenField.stringValue = parts[2]
            }
        default: break
        }
    }

    override func applySettings() {
        let rule: String
        if localPortRadio.state == .on {
            rule = "L:\(localFromField.stringValue):\(localListenField.stringValue):\(localToHostField.stringValue):\(localToPortField.stringValue)"
        } else if remotePortRadio.state == .on {
            rule = "R:\(remoteFromField.stringValue):\(remoteListenField.stringValue):\(remoteToHostField.stringValue):\(remoteToPortField.stringValue)"
        } else {
            rule = "D:\(dynamicFromField.stringValue):\(dynamicListenField.stringValue)"
        }
        onSave?(rule)
    }
}

// MARK: - SSH Key Generation Dialog (IDD_SSHKEYGEN)

/// SSH key generation using system /usr/bin/ssh-keygen.
final class SSHKeyGenDialogController: BaseSetupDialogController {

    private var keyTypePopup: NSPopUpButton!
    private var keyBitsField: NSTextField!
    private var passphraseField: NSSecureTextField!
    private var confirmField: NSSecureTextField!
    private var commentField: NSTextField!
    private var progressLabel: NSTextField!
    private var savePublicButton: NSButton!
    private var savePrivateButton: NSButton!

    private var generatedPublicKeyPath: String?
    private var generatedPrivateKeyPath: String?

    init() {
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.sshKeyGen.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        okButton.title = TTL("dialog.sshKeyGen.generate")
        cancelButton.title = TTL("Cancel")
        setupControls()
    }

    private func setupControls() {
        let dialogWidth: CGFloat = 420
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        // ── Key type group ──
        let keyTypeBox = NSView.makeGroupBox(title: TTL("dialog.sshKeyGen.keyType"))
        let keyTypeContent = NSView()
        keyTypeContent.translatesAutoresizingMaskIntoConstraints = false

        keyTypePopup = NSView.makePopUpButton(items: [
            "RSA", "DSA", "ECDSA-256", "ECDSA-384", "ECDSA-521", "ED25519",
        ], selected: "ED25519")

        let bitsLabel = NSView.makeLabel(TTL("dialog.sshKeyGen.keyBits"))
        keyBitsField = NSView.makeNumberField(value: 256, width: 60)

        let typeRow = NSStackView(views: [keyTypePopup, bitsLabel, keyBitsField])
        typeRow.translatesAutoresizingMaskIntoConstraints = false
        typeRow.orientation = .horizontal
        typeRow.spacing = DialogLayout.labelTrailing
        typeRow.alignment = .firstBaseline

        keyTypeContent.addSubview(typeRow)
        let tPad = DialogLayout.groupBoxPadding
        NSLayoutConstraint.activate([
            typeRow.topAnchor.constraint(equalTo: keyTypeContent.topAnchor, constant: tPad),
            typeRow.leadingAnchor.constraint(equalTo: keyTypeContent.leadingAnchor, constant: tPad),
            typeRow.bottomAnchor.constraint(equalTo: keyTypeContent.bottomAnchor, constant: -tPad),
        ])
        keyTypeBox.contentView = keyTypeContent

        // ── Passphrase / Confirm / Comment ──
        let passLabel = NSView.makeLabel(TTL("dialog.sshKeyGen.passphrase"))
        passphraseField = NSView.makeSecureTextField()

        let confirmLabel = NSView.makeLabel(TTL("dialog.sshKeyGen.confirm"))
        confirmField = NSView.makeSecureTextField()

        let commentLabel = NSView.makeLabel(TTL("dialog.sshKeyGen.comment"))
        commentField = NSView.makeTextField()

        let grid = NSGridView(views: [
            [passLabel, passphraseField],
            [confirmLabel, confirmField],
            [commentLabel, commentField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = DialogLayout.rowSpacing
        grid.columnSpacing = DialogLayout.labelTrailing
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        for i in 0..<grid.numberOfRows {
            grid.row(at: i).rowAlignment = .firstBaseline
        }

        // ── Progress label ──
        progressLabel = NSView.makeLabel("", alignment: .left)
        progressLabel.textColor = .secondaryLabelColor

        // ── Save buttons ──
        savePublicButton = NSView.makePushButton(TTL("dialog.sshKeyGen.savePublic"))
        savePublicButton.target = self
        savePublicButton.action = #selector(savePublicKey(_:))
        savePublicButton.isEnabled = false

        savePrivateButton = NSView.makePushButton(TTL("dialog.sshKeyGen.savePrivate"))
        savePrivateButton.target = self
        savePrivateButton.action = #selector(savePrivateKey(_:))
        savePrivateButton.isEnabled = false

        let saveRow = NSStackView(views: [savePublicButton, savePrivateButton])
        saveRow.translatesAutoresizingMaskIntoConstraints = false
        saveRow.orientation = .horizontal
        saveRow.spacing = DialogLayout.buttonSpacing

        // ── Main stack ──
        let mainStack = NSStackView(views: [keyTypeBox, grid, progressLabel, saveRow])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = DialogLayout.rowSpacing
        contentArea.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            keyTypeBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    override func applySettings() {
        // Generate key using ssh-keygen
        let passphrase = passphraseField.stringValue
        let confirm = confirmField.stringValue

        if passphrase != confirm {
            let alert = NSAlert()
            alert.messageText = TTL("dialog.sshKeyGen.mismatch")
            alert.alertStyle = .warning
            alert.addButton(withTitle: TTL("OK"))
            alert.runModal()
            return
        }

        if passphrase.isEmpty {
            let alert = NSAlert()
            alert.messageText = TTL("dialog.sshKeyGen.emptyPassphrase")
            alert.alertStyle = .warning
            alert.addButton(withTitle: TTL("OK"))
            alert.addButton(withTitle: TTL("Cancel"))
            if alert.runModal() != .alertFirstButtonReturn { return }
        }

        progressLabel.stringValue = TTL("dialog.sshKeyGen.generating")

        let keyType = sshKeygenType()
        let bits = keyBitsField.integerValue
        let comment = commentField.stringValue

        let tempDir = NSTemporaryDirectory()
        let keyPath = (tempDir as NSString).appendingPathComponent("teraterm_keygen_\(ProcessInfo.processInfo.processIdentifier)")

        // Remove any existing file
        try? FileManager.default.removeItem(atPath: keyPath)
        try? FileManager.default.removeItem(atPath: keyPath + ".pub")

        DispatchQueue.global().async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            var args = ["-t", keyType, "-f", keyPath, "-N", passphrase]
            if !comment.isEmpty { args += ["-C", comment] }
            // Add bits for RSA/DSA
            if keyType == "rsa" || keyType == "dsa" {
                args += ["-b", "\(bits)"]
            }
            process.arguments = args

            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()  // suppress stdout

            do {
                try process.run()
                process.waitUntilExit()

                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if process.terminationStatus == 0 {
                        self.progressLabel.stringValue = TTL("dialog.sshKeyGen.generated")
                        self.generatedPrivateKeyPath = keyPath
                        self.generatedPublicKeyPath = keyPath + ".pub"
                        self.savePublicButton.isEnabled = true
                        self.savePrivateButton.isEnabled = true
                    } else {
                        self.progressLabel.stringValue = TTL("dialog.sshKeyGen.error", errStr)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.progressLabel.stringValue = TTL("dialog.sshKeyGen.error", error.localizedDescription)
                }
            }
        }
    }

    private func sshKeygenType() -> String {
        switch keyTypePopup.indexOfSelectedItem {
        case 0: return "rsa"
        case 1: return "dsa"
        case 2: return "ecdsa"  // 256
        case 3: return "ecdsa"  // 384
        case 4: return "ecdsa"  // 521
        case 5: return "ed25519"
        default: return "ed25519"
        }
    }

    @objc private func savePublicKey(_ sender: Any?) {
        guard let srcPath = generatedPublicKeyPath else { return }
        let panel = NSSavePanel()
        panel.title = TTL("dialog.sshKeyGen.savePublicTitle")
        panel.nameFieldStringValue = URL(fileURLWithPath: srcPath).lastPathComponent
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? FileManager.default.copyItem(atPath: srcPath, toPath: url.path)
        }
    }

    @objc private func savePrivateKey(_ sender: Any?) {
        guard let srcPath = generatedPrivateKeyPath else { return }
        let panel = NSSavePanel()
        panel.title = TTL("dialog.sshKeyGen.savePrivateTitle")
        panel.nameFieldStringValue = URL(fileURLWithPath: srcPath).lastPathComponent
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? FileManager.default.copyItem(atPath: srcPath, toPath: url.path)
            // Set proper permissions
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

// MARK: - General Setup Dialog (IDD_GENDLG)

final class GeneralSetupDialogController: BaseSetupDialogController {

    private var settings: TerminalSettings
    private var languagePopup: NSPopUpButton!
    private var defaultPortPopup: NSPopUpButton!
    private var autoCloseCheck: NSButton!
    private var titleHostnameCheck: NSButton!
    private var titleSessionCheck: NSButton!

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.generalSetup.title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupControls()
    }

    private func setupControls() {
        let dialogWidth: CGFloat = 380
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        let langLabel = NSView.makeLabel(TTL("dialog.generalSetup.language"))
        languagePopup = NSView.makePopUpButton(items: [
            TTL("dialog.generalSetup.languageEnglish"),
            TTL("dialog.generalSetup.languageJapanese"),
        ], selected: settings.language == "Japanese"
            ? TTL("dialog.generalSetup.languageJapanese")
            : TTL("dialog.generalSetup.languageEnglish"))

        let portLabel = NSView.makeLabel(TTL("dialog.generalSetup.defaultPort"))
        defaultPortPopup = NSView.makePopUpButton(items: [
            "Telnet (23)", "SSH (22)", "Other",
        ])
        switch settings.serviceType {
        case .telnet: defaultPortPopup.selectItem(at: 0)
        case .ssh: defaultPortPopup.selectItem(at: 1)
        default: defaultPortPopup.selectItem(at: 2)
        }

        let grid = NSGridView(views: [
            [langLabel, languagePopup],
            [portLabel, defaultPortPopup],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = DialogLayout.rowSpacing
        grid.columnSpacing = DialogLayout.labelTrailing
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        for i in 0..<grid.numberOfRows {
            grid.row(at: i).rowAlignment = .firstBaseline
        }

        autoCloseCheck = NSView.makeCheckbox(
            TTL("dialog.generalSetup.autoWindowClose"), checked: settings.autoWindowClose)

        // Title format
        let titleBox = NSView.makeGroupBox(title: TTL("dialog.generalSetup.titleFormat"))
        let titleContent = NSView()
        titleContent.translatesAutoresizingMaskIntoConstraints = false
        titleHostnameCheck = NSView.makeCheckbox(
            TTL("dialog.generalSetup.titleHostname"), checked: settings.titleFormatTCP)
        titleSessionCheck = NSView.makeCheckbox(
            TTL("dialog.generalSetup.titleSession"), checked: settings.titleFormatSession)
        let titleStack = NSStackView(views: [titleHostnameCheck, titleSessionCheck])
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 6
        titleContent.addSubview(titleStack)
        let tPad = DialogLayout.groupBoxPadding
        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: titleContent.topAnchor, constant: tPad),
            titleStack.leadingAnchor.constraint(equalTo: titleContent.leadingAnchor, constant: tPad),
            titleStack.trailingAnchor.constraint(equalTo: titleContent.trailingAnchor, constant: -tPad),
            titleStack.bottomAnchor.constraint(equalTo: titleContent.bottomAnchor, constant: -tPad),
        ])
        titleBox.contentView = titleContent

        let mainStack = NSStackView(views: [grid, autoCloseCheck, titleBox])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = DialogLayout.sectionSpacing
        contentArea.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentArea.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            titleBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    override func applySettings() {
        settings.language = (languagePopup.indexOfSelectedItem == 1) ? "Japanese" : "English"

        switch defaultPortPopup.indexOfSelectedItem {
        case 0:
            settings.serviceType = .telnet
            settings.defaultPort = 23
        case 1:
            settings.serviceType = .ssh
            settings.defaultPort = 22
        default: break
        }

        settings.autoWindowClose = autoCloseCheck.state == .on
        settings.titleFormatTCP = titleHostnameCheck.state == .on
        settings.titleFormatSession = titleSessionCheck.state == .on
    }
}

// MARK: - Print Helper

/// Print terminal content using macOS standard print infrastructure.
final class TerminalPrintHelper {

    /// Print the current terminal buffer content using NSPrintOperation.
    static func printTerminalContent(from windowController: Any?, window: NSWindow?) {
        guard let win = window else { return }

        // Use NSPrintPanel with standard macOS print dialog
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false

        // Create a text view with terminal content for printing
        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        printView.isEditable = false
        printView.isSelectable = false
        printView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        // Get terminal text from the buffer
        if let wc = windowController as? TerminalWindowController {
            let buffer = wc.terminalEmulator.buffer
            // Save current selection state
            let savedSelection = buffer.selection
            // Select all buffer content
            buffer.selection.isActive = true
            buffer.selection.startX = 0
            buffer.selection.startY = 0
            buffer.selection.endX = buffer.width - 1
            buffer.selection.endY = buffer.totalLines - 1
            buffer.selection.isRectangular = false
            if let text = buffer.getSelectedText() {
                printView.string = text
            }
            // Restore previous selection state
            buffer.selection = savedSelection
        }

        let printOp = NSPrintOperation(view: printView, printInfo: printInfo)
        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true
        printOp.runModal(for: win, delegate: nil, didRun: nil, contextInfo: nil)
    }
}

#endif
