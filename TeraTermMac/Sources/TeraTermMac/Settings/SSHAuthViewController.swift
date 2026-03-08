/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * SSH Authentication dialog — faithful reproduction of Tera Term 5.6 IDD_SSHAUTH.
 * Layout uses NSGridView / NSStackView with proper Auto Layout constraints.
 *
 * Original dialog layout:
 *
 *   User name:    [____________________]
 *   Passphrase:   [____________________]
 *
 *   ◉ Use plain password to log in
 *   ○ Use RSA/DSA/ECDSA/ED25519 key to log in
 *   ○ Use rhosts to log in (SSH1)
 *   ○ Use challenge/response to log in (keyboard-interactive)
 *   ○ Use Pageant
 *
 *   Private key file: [______________] [...]
 *
 *   ☑ Remember password in memory
 *   ☑ Forward agent
 *
 *                          [Help]  [Disconnect]  [OK]
 */

#if canImport(AppKit)
import AppKit

class SSHAuthViewController: BaseSetupDialogController {

    private var settings: TerminalSettings

    // Input fields
    private var usernameField: NSTextField!
    private var passphraseField: NSSecureTextField!
    private var privateKeyField: NSTextField!

    // Auth method radios
    private var passwordRadio: NSButton!
    private var publicKeyRadio: NSButton!
    private var rhostsRadio: NSButton!
    private var challengeRadio: NSButton!
    private var pageantRadio: NSButton!

    // Checkboxes
    private var rememberPasswordCheck: NSButton!
    private var forwardAgentCheck: NSButton!

    // Browse button
    private var browseButton: NSButton!

    /// Called when user clicks OK with valid auth info.
    /// Parameters: (username, passphrase, authMethod, keyFile)
    var onAuthenticate: ((String, String, SSHAuthMethod, String) -> Void)?

    init(settings: TerminalSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        self.title = TTL("dialog.sshAuth.title")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Change "Cancel" button text to "Disconnect"
        cancelButton.title = TTL("dialog.sshAuth.disconnect")
        setupControls()
    }

    private func setupControls() {
        let dialogWidth: CGFloat = 420
        contentArea.widthAnchor.constraint(equalToConstant: dialogWidth).isActive = true

        // ── Username / Passphrase grid ──
        let userLabel = NSView.makeLabel(TTL("dialog.sshAuth.username"))
        let passLabel = NSView.makeLabel(TTL("dialog.sshAuth.passphrase"))

        usernameField = NSView.makeTextField(value: settings.sshUsername)
        passphraseField = NSView.makeSecureTextField()

        let inputGrid = NSGridView(views: [
            [userLabel, usernameField],
            [passLabel, passphraseField],
        ])
        inputGrid.translatesAutoresizingMaskIntoConstraints = false
        inputGrid.rowSpacing = DialogLayout.rowSpacing
        inputGrid.columnSpacing = DialogLayout.labelTrailing
        inputGrid.column(at: 0).xPlacement = .trailing
        inputGrid.column(at: 1).xPlacement = .fill
        for i in 0..<inputGrid.numberOfRows {
            inputGrid.row(at: i).rowAlignment = .firstBaseline
        }
        contentArea.addSubview(inputGrid)

        // ── Auth method radio buttons ──
        passwordRadio = NSView.makeRadioButton(
            TTL("dialog.sshAuth.usePassword"), tag: SSHAuthMethod.password.rawValue)
        publicKeyRadio = NSView.makeRadioButton(
            TTL("dialog.sshAuth.usePublicKey"), tag: SSHAuthMethod.publicKey.rawValue)
        rhostsRadio = NSView.makeRadioButton(
            TTL("dialog.sshAuth.useRhosts"), tag: SSHAuthMethod.rhosts.rawValue)
        challengeRadio = NSView.makeRadioButton(
            TTL("dialog.sshAuth.useChallenge"), tag: SSHAuthMethod.challengeResponse.rawValue)
        pageantRadio = NSView.makeRadioButton(
            TTL("dialog.sshAuth.usePageant"), tag: SSHAuthMethod.pageant.rawValue)

        let allRadios = [passwordRadio!, publicKeyRadio!, rhostsRadio!, challengeRadio!, pageantRadio!]
        for radio in allRadios {
            radio.target = self
            radio.action = #selector(authMethodChanged(_:))
        }

        // Set current selection
        switch settings.sshAuthMethod {
        case .password:        passwordRadio.state = .on
        case .publicKey:       publicKeyRadio.state = .on
        case .rhosts:          rhostsRadio.state = .on
        case .challengeResponse: challengeRadio.state = .on
        case .pageant:         pageantRadio.state = .on
        }

        let radioStack = NSStackView(views: allRadios)
        radioStack.translatesAutoresizingMaskIntoConstraints = false
        radioStack.orientation = .vertical
        radioStack.alignment = .leading
        radioStack.spacing = 4
        contentArea.addSubview(radioStack)

        // ── Private key file row ──
        let keyLabel = NSView.makeLabel(TTL("dialog.sshAuth.privateKey"), alignment: .left)
        keyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        privateKeyField = NSView.makeTextField(value: settings.sshKeyFile)
        privateKeyField.isEditable = false

        browseButton = NSView.makePushButton("...", keyEquivalent: "")
        browseButton.target = self
        browseButton.action = #selector(browseKeyFile(_:))
        // Override minimum width for the small "..." button
        for c in browseButton.constraints where c.firstAttribute == .width {
            c.isActive = false
        }
        browseButton.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let keyRow = NSStackView(views: [keyLabel, privateKeyField, browseButton])
        keyRow.translatesAutoresizingMaskIntoConstraints = false
        keyRow.orientation = .horizontal
        keyRow.spacing = DialogLayout.labelTrailing
        keyRow.alignment = .firstBaseline
        // Let the text field expand
        privateKeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentArea.addSubview(keyRow)

        // ── Checkboxes ──
        rememberPasswordCheck = NSView.makeCheckbox(
            TTL("dialog.sshAuth.rememberPassword"), checked: settings.sshRememberPassword)
        forwardAgentCheck = NSView.makeCheckbox(
            TTL("dialog.sshAuth.forwardAgent"), checked: settings.sshForwardAgent)

        let checkStack = NSStackView(views: [rememberPasswordCheck, forwardAgentCheck])
        checkStack.translatesAutoresizingMaskIntoConstraints = false
        checkStack.orientation = .vertical
        checkStack.alignment = .leading
        checkStack.spacing = 6
        contentArea.addSubview(checkStack)

        // ── Layout constraints ──
        NSLayoutConstraint.activate([
            // Input grid
            inputGrid.topAnchor.constraint(equalTo: contentArea.topAnchor),
            inputGrid.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            inputGrid.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),

            // Radio stack
            radioStack.topAnchor.constraint(equalTo: inputGrid.bottomAnchor,
                                            constant: DialogLayout.sectionSpacing),
            radioStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor,
                                                constant: 8),
            radioStack.trailingAnchor.constraint(lessThanOrEqualTo: contentArea.trailingAnchor),

            // Private key row
            keyRow.topAnchor.constraint(equalTo: radioStack.bottomAnchor,
                                        constant: DialogLayout.sectionSpacing),
            keyRow.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            keyRow.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),

            // Checkboxes
            checkStack.topAnchor.constraint(equalTo: keyRow.bottomAnchor,
                                            constant: DialogLayout.sectionSpacing),
            checkStack.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor,
                                                constant: 8),
            checkStack.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
        ])

        // Apply initial enable/disable state
        updateControlStates()
    }

    // MARK: - Actions

    @objc private func authMethodChanged(_ sender: NSButton) {
        let allRadios = [passwordRadio!, publicKeyRadio!, rhostsRadio!, challengeRadio!, pageantRadio!]
        for radio in allRadios {
            radio.state = (radio === sender) ? .on : .off
        }
        updateControlStates()
    }

    @objc private func browseKeyFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = TTL("dialog.sshAuth.selectKeyFile")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        // Start from ~/.ssh if no key file is set
        if privateKeyField.stringValue.isEmpty {
            let sshDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ssh")
            if FileManager.default.fileExists(atPath: sshDir.path) {
                panel.directoryURL = sshDir
            }
        } else {
            let url = URL(fileURLWithPath: privateKeyField.stringValue)
            panel.directoryURL = url.deletingLastPathComponent()
        }

        if let win = view.window {
            panel.beginSheetModal(for: win) { [weak self] response in
                if response == .OK, let url = panel.url {
                    self?.privateKeyField.stringValue = url.path
                }
            }
        }
    }

    /// Enable/disable controls based on the selected auth method.
    private func updateControlStates() {
        let method = selectedAuthMethod

        // Passphrase is used for password and public key auth
        let needsPassphrase = (method == .password || method == .publicKey)
        passphraseField.isEnabled = needsPassphrase

        // Private key file only for public key auth
        let needsKeyFile = (method == .publicKey)
        privateKeyField.isEnabled = needsKeyFile
        browseButton.isEnabled = needsKeyFile

        // Remember password for password and challenge/response
        let canRemember = (method == .password || method == .challengeResponse)
        rememberPasswordCheck.isEnabled = canRemember

        // Forward agent for public key and pageant
        let canForward = (method == .publicKey || method == .pageant)
        forwardAgentCheck.isEnabled = canForward
    }

    private var selectedAuthMethod: SSHAuthMethod {
        if publicKeyRadio.state == .on { return .publicKey }
        if rhostsRadio.state == .on { return .rhosts }
        if challengeRadio.state == .on { return .challengeResponse }
        if pageantRadio.state == .on { return .pageant }
        return .password
    }

    // MARK: - Apply

    override func applySettings() {
        let method = selectedAuthMethod
        settings.sshAuthMethod = method
        settings.sshUsername = usernameField.stringValue
        settings.sshKeyFile = privateKeyField.stringValue
        settings.sshRememberPassword = rememberPasswordCheck.state == .on
        settings.sshForwardAgent = forwardAgentCheck.state == .on

        onAuthenticate?(
            usernameField.stringValue,
            passphraseField.stringValue,
            method,
            privateKeyField.stringValue
        )
    }
}
#endif
