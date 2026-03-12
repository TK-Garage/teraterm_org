/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * SSH security warning dialogs — faithful port of Tera Term 5.6 host key
 * verification dialogs.
 *
 * Dialogs ported:
 *   - Unknown Host warning (first connection)
 *   - Different Key warning (host key changed)
 *   - Different Type Key warning (key type mismatch)
 *   - Host Key Rotation confirmation
 *   - SSHFP (DNS key fingerprint) display
 */

#if canImport(AppKit)
import AppKit

// MARK: - Host Key Verification Result

enum HostKeyAction {
    case accept          // Add/update the key
    case acceptOnce      // Accept for this session only
    case reject          // Disconnect
}

// MARK: - Unknown Host Warning Dialog

/// Shown on first connection when the host is not in known_hosts.
/// Port of Tera Term's "HOSTS_NOTFOUND" dialog.
final class UnknownHostDialog {

    static func show(hostname: String,
                     keyType: String,
                     fingerprint: String,
                     sshfpResult: String? = nil,
                     on window: NSWindow,
                     completion: @escaping (HostKeyAction) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = TTL("dialog.security.unknownHost.title")

        var info = String(format: TTL("dialog.security.unknownHost.message"),
                          hostname, keyType, fingerprint)
        if let sshfp = sshfpResult, !sshfp.isEmpty {
            info += "\n\n" + String(format: TTL("dialog.security.sshfp.result"), sshfp)
        }
        alert.informativeText = info

        // Fingerprint display
        let fpView = makeFingerPrintView(keyType: keyType, fingerprint: fingerprint)
        alert.accessoryView = fpView

        alert.addButton(withTitle: TTL("dialog.security.accept"))
        alert.addButton(withTitle: TTL("dialog.security.acceptOnce"))
        alert.addButton(withTitle: TTL("dialog.security.reject"))

        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                completion(.accept)
            case .alertSecondButtonReturn:
                completion(.acceptOnce)
            default:
                completion(.reject)
            }
        }
    }
}

// MARK: - Different Key Warning Dialog

/// Shown when the host key has changed from what is stored in known_hosts.
/// Port of Tera Term's "HOSTS_DIFFERENT" dialog.
final class DifferentKeyDialog {

    static func show(hostname: String,
                     keyType: String,
                     storedFingerprint: String,
                     newFingerprint: String,
                     on window: NSWindow,
                     completion: @escaping (HostKeyAction) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = TTL("dialog.security.differentKey.title")
        alert.informativeText = String(format: TTL("dialog.security.differentKey.message"),
                                       hostname, keyType)

        let storedLabel = NSView.makeLabel(TTL("dialog.security.storedFingerprint"), alignment: .left)
        let storedField = NSView.makeTextField(value: storedFingerprint)
        storedField.isEditable = false
        storedField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        storedField.setContentCompressionResistancePriority(.required, for: .horizontal)

        let newLabel = NSView.makeLabel(TTL("dialog.security.newFingerprint"), alignment: .left)
        let newField = NSView.makeTextField(value: newFingerprint)
        newField.isEditable = false
        newField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        newField.textColor = .systemRed
        newField.setContentCompressionResistancePriority(.required, for: .horizontal)

        let warningLabel = NSView.makeLabel(TTL("dialog.security.differentKey.warning"), alignment: .left)
        warningLabel.textColor = .systemRed
        warningLabel.font = NSFont.boldSystemFont(ofSize: 12)
        warningLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [storedLabel, storedField, newLabel, newField, warningLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        // Let the stack size itself via intrinsic content
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 440).isActive = true
        storedField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        newField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        alert.accessoryView = stack
        alert.addButton(withTitle: TTL("dialog.security.accept"))
        alert.addButton(withTitle: TTL("dialog.security.acceptOnce"))
        alert.addButton(withTitle: TTL("dialog.security.reject"))

        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                completion(.accept)
            case .alertSecondButtonReturn:
                completion(.acceptOnce)
            default:
                completion(.reject)
            }
        }
    }
}

// MARK: - Different Type Key Warning Dialog

/// Shown when the host key type differs from what is stored.
/// Port of Tera Term's "HOSTS_DIFFERENT_TYPE" dialog.
final class DifferentTypeKeyDialog {

    static func show(hostname: String,
                     storedKeyType: String,
                     newKeyType: String,
                     newFingerprint: String,
                     on window: NSWindow,
                     completion: @escaping (HostKeyAction) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = TTL("dialog.security.differentTypeKey.title")
        alert.informativeText = String(format: TTL("dialog.security.differentTypeKey.message"),
                                       hostname, storedKeyType, newKeyType, newFingerprint)

        alert.addButton(withTitle: TTL("dialog.security.accept"))
        alert.addButton(withTitle: TTL("dialog.security.acceptOnce"))
        alert.addButton(withTitle: TTL("dialog.security.reject"))

        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                completion(.accept)
            case .alertSecondButtonReturn:
                completion(.acceptOnce)
            default:
                completion(.reject)
            }
        }
    }
}

// MARK: - Host Key Rotation Confirmation Dialog

/// Shown when the server offers a new host key via the key rotation mechanism
/// (openssh hostkeys-00@openssh.com extension).
final class HostKeyRotationDialog {

    static func show(hostname: String,
                     oldKeyType: String,
                     newKeyType: String,
                     newFingerprint: String,
                     on window: NSWindow,
                     completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = TTL("dialog.security.keyRotation.title")
        alert.informativeText = String(format: TTL("dialog.security.keyRotation.message"),
                                       hostname, oldKeyType, newKeyType, newFingerprint)

        let fpView = makeFingerPrintView(keyType: newKeyType, fingerprint: newFingerprint)
        alert.accessoryView = fpView

        alert.addButton(withTitle: TTL("dialog.security.keyRotation.accept"))
        alert.addButton(withTitle: TTL("dialog.security.keyRotation.reject"))

        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }
}

// MARK: - SSHFP Display Dialog

/// Displays DNS-based SSH Fingerprint (SSHFP RR) verification result.
final class SSHFPDialog {

    enum SSHFPStatus {
        case matched
        case notMatched
        case notFound
        case insecure  // DNS response without DNSSEC
    }

    static func show(hostname: String,
                     keyType: String,
                     fingerprint: String,
                     status: SSHFPStatus,
                     on window: NSWindow,
                     completion: @escaping () -> Void) {
        let alert = NSAlert()

        switch status {
        case .matched:
            alert.alertStyle = .informational
            alert.messageText = TTL("dialog.security.sshfp.matchedTitle")
            alert.informativeText = String(format: TTL("dialog.security.sshfp.matchedMessage"),
                                           hostname, keyType, fingerprint)
        case .notMatched:
            alert.alertStyle = .critical
            alert.messageText = TTL("dialog.security.sshfp.notMatchedTitle")
            alert.informativeText = String(format: TTL("dialog.security.sshfp.notMatchedMessage"),
                                           hostname, keyType, fingerprint)
        case .notFound:
            alert.alertStyle = .warning
            alert.messageText = TTL("dialog.security.sshfp.notFoundTitle")
            alert.informativeText = String(format: TTL("dialog.security.sshfp.notFoundMessage"),
                                           hostname)
        case .insecure:
            alert.alertStyle = .warning
            alert.messageText = TTL("dialog.security.sshfp.insecureTitle")
            alert.informativeText = String(format: TTL("dialog.security.sshfp.insecureMessage"),
                                           hostname)
        }

        alert.addButton(withTitle: TTL("OK"))

        alert.beginSheetModal(for: window) { _ in
            completion()
        }
    }
}

// MARK: - Helper

private func makeFingerPrintView(keyType: String, fingerprint: String) -> NSView {
    let typeLabel = NSView.makeLabel(
        String(format: TTL("dialog.security.keyType"), keyType), alignment: .left)
    typeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    let fpLabel = NSView.makeLabel(
        String(format: TTL("dialog.security.fingerprint"), fingerprint), alignment: .left)
    fpLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    fpLabel.lineBreakMode = .byCharWrapping
    fpLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    let stack = NSStackView(views: [typeLabel, fpLabel])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4

    // Allow auto-expansion for longer localized strings
    stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true

    return stack
}

#endif
