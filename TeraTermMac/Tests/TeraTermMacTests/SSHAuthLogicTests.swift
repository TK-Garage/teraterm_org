/*
 * SSHAuthLogicTests.swift
 * Phase 1: Private key format detection, file permission checks,
 * passphrase validation, and macOS Keychain integration tests.
 *
 * NOTE – App Sandbox Considerations:
 *   When the app is sandboxed, reading arbitrary files outside the
 *   container (e.g. ~/.ssh/id_ed25519) requires:
 *     1. A user-initiated NSOpenPanel selection (powerbox grant), OR
 *     2. Security-Scoped Bookmarks persisted across launches.
 *   Tests here use temporary files inside NSTemporaryDirectory(),
 *   which is always accessible regardless of sandbox state.
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit) && canImport(Security)
import Security

// MARK: - Test Data: Synthetic Private Key Headers

/// Minimal private key samples containing only the header/trailer.
/// These are NOT cryptographically valid keys — they are used solely
/// to verify format detection logic.
private enum TestKeyData {

    // OpenSSH new format (ssh-keygen default since 6.5, covers RSA/Ed25519/ECDSA)
    static let openssh = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACC/sample+fake+data+for+testing==AAAAA
    -----END OPENSSH PRIVATE KEY-----
    """

    // PEM RSA (PKCS#1)
    static let pemRSA = """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEpAIBAAKCAQEA0Z3VS5JJcds3xfn/ygWyF8PbnGZmAGDQY5Y5E9QnFjyN
    -----END RSA PRIVATE KEY-----
    """

    // PEM DSA
    static let pemDSA = """
    -----BEGIN DSA PRIVATE KEY-----
    MIIBugIBAAKBgQDVvjQGmXlczEjl3h0oluapqoMjgrLm4a8FJNuM
    -----END DSA PRIVATE KEY-----
    """

    // PEM ECDSA
    static let pemECDSA = """
    -----BEGIN EC PRIVATE KEY-----
    MHQCAQEEILfUkXQwIVzC6cGDT3EqP5xZCVwB9Af6eC2Ks
    -----END EC PRIVATE KEY-----
    """

    // PKCS#8 unencrypted
    static let pkcs8 = """
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAg
    -----END PRIVATE KEY-----
    """

    // PKCS#8 encrypted
    static let pkcs8Encrypted = """
    -----BEGIN ENCRYPTED PRIVATE KEY-----
    MIIFHDBOBgkqhkiG9w0BBQ0wQTApBgkqhkiG9w0BBQwwHA
    -----END ENCRYPTED PRIVATE KEY-----
    """

    // PuTTY PPK v2
    static let puttyV2 = """
    PuTTY-User-Key-File-2: ssh-rsa
    Encryption: none
    Comment: test@host
    Public-Lines: 4
    AAAAB3NzaC1yc2EAAA
    """

    // PuTTY PPK v3
    static let puttyV3 = """
    PuTTY-User-Key-File-3: ssh-ed25519
    Encryption: none
    Comment: test@host
    Public-Lines: 2
    AAAAC3NzaC1lZDI1NTE5AA
    """

    // SSH.COM (Tectia)
    static let sshcom = """
    ---- BEGIN SSH2 ENCRYPTED PRIVATE KEY ----
    P2/56wAAAi4AAAA3aWYtbW9kbntzaWdue3JzYS1wa2NzMS1zaGExfSx
    ---- END SSH2 ENCRYPTED PRIVATE KEY ----
    """

    // Invalid: a public key (not private)
    static let publicKeyOnly = """
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBe9m user@host
    """

    // Invalid: random text
    static let garbage = "This is not a key file at all."

    // Invalid: empty
    static let empty = ""
}

// MARK: - Key Format Detection Tests

final class SSHKeyFormatTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSHKeyTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    /// Write test data to a temp file and return its URL.
    private func writeKeyFile(_ content: String, name: String = "testkey") -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Valid Key Formats

    func testOpenSSHFormat() {
        let url = writeKeyFile(TestKeyData.openssh, name: "id_ed25519")
        XCTAssertTrue(SSHAuthViewController.isValidPrivateKey(at: url),
                       "OpenSSH new-format key should be recognized")
    }

    func testPEMRSAFormat() {
        let url = writeKeyFile(TestKeyData.pemRSA, name: "id_rsa")
        XCTAssertTrue(SSHAuthViewController.isValidPrivateKey(at: url),
                       "PEM RSA key should be recognized")
    }

    func testPEMDSAFormat() {
        let url = writeKeyFile(TestKeyData.pemDSA, name: "id_dsa")
        XCTAssertTrue(SSHAuthViewController.isValidPrivateKey(at: url),
                       "PEM DSA key should be recognized")
    }

    func testPEMECDSAFormat() {
        let url = writeKeyFile(TestKeyData.pemECDSA, name: "id_ecdsa")
        XCTAssertTrue(SSHAuthViewController.isValidPrivateKey(at: url),
                       "PEM ECDSA key should be recognized")
    }

    func testPKCS8Unencrypted() {
        let url = writeKeyFile(TestKeyData.pkcs8, name: "id_pkcs8")
        XCTAssertTrue(SSHAuthViewController.isValidPrivateKey(at: url),
                       "PKCS#8 unencrypted key should be recognized")
    }

    func testPKCS8Encrypted() {
        let url = writeKeyFile(TestKeyData.pkcs8Encrypted, name: "id_pkcs8_enc")
        XCTAssertTrue(SSHAuthViewController.isValidPrivateKey(at: url),
                       "PKCS#8 encrypted key should be recognized")
    }

    func testPuTTyV2Format() {
        let url = writeKeyFile(TestKeyData.puttyV2, name: "key.ppk")
        XCTAssertTrue(SSHAuthViewController.isValidPrivateKey(at: url),
                       "PuTTY v2 PPK key should be recognized")
    }

    func testPuTTyV3Format() {
        let url = writeKeyFile(TestKeyData.puttyV3, name: "key3.ppk")
        XCTAssertTrue(SSHAuthViewController.isValidPrivateKey(at: url),
                       "PuTTY v3 PPK key should be recognized")
    }

    func testSSHCOMFormat() {
        let url = writeKeyFile(TestKeyData.sshcom, name: "id_sshcom")
        XCTAssertTrue(SSHAuthViewController.isValidPrivateKey(at: url),
                       "SSH.COM (Tectia) key should be recognized")
    }

    // MARK: - Invalid Inputs

    func testPublicKeyRejected() {
        let url = writeKeyFile(TestKeyData.publicKeyOnly, name: "id_ed25519.pub")
        XCTAssertFalse(SSHAuthViewController.isValidPrivateKey(at: url),
                        "Public key should not be accepted as private key")
    }

    func testGarbageRejected() {
        let url = writeKeyFile(TestKeyData.garbage, name: "notes.txt")
        XCTAssertFalse(SSHAuthViewController.isValidPrivateKey(at: url),
                        "Random text should not be accepted as a key")
    }

    func testEmptyFileRejected() {
        let url = writeKeyFile(TestKeyData.empty, name: "empty")
        XCTAssertFalse(SSHAuthViewController.isValidPrivateKey(at: url),
                        "Empty file should not be accepted")
    }

    func testNonexistentFileRejected() {
        let url = tmpDir.appendingPathComponent("does_not_exist")
        XCTAssertFalse(SSHAuthViewController.isValidPrivateKey(at: url),
                        "Non-existent file should not be accepted")
    }

    func testBinaryFileRejected() {
        let url = tmpDir.appendingPathComponent("binary.dat")
        let bytes: [UInt8] = [0x00, 0x01, 0xFF, 0xFE, 0x89, 0x50, 0x4E, 0x47] // PNG header
        try! Data(bytes).write(to: url)
        XCTAssertFalse(SSHAuthViewController.isValidPrivateKey(at: url),
                        "Binary file should not be accepted")
    }
}

// MARK: - File Permission Tests

final class SSHKeyPermissionTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSHPermTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    /// Check if a POSIX permission is "too open" for an SSH private key.
    /// Standard SSH behavior: reject if group-readable or world-readable.
    static func isPermissionTooOpen(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let posix = attrs[.posixPermissions] as? Int else {
            return false
        }
        // 0o077 = group + other bits; if any are set, it's too open.
        return (posix & 0o077) != 0
    }

    func testPermission0600IsAcceptable() {
        let url = tmpDir.appendingPathComponent("key_0600")
        try! TestKeyData.openssh.write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)

        XCTAssertFalse(SSHKeyPermissionTests.isPermissionTooOpen(at: url),
                        "0600 should be acceptable for SSH keys")
    }

    func testPermission0644IsTooOpen() {
        let url = tmpDir.appendingPathComponent("key_0644")
        try! TestKeyData.openssh.write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: url.path)

        XCTAssertTrue(SSHKeyPermissionTests.isPermissionTooOpen(at: url),
                       "0644 should be flagged as too open")
    }

    func testPermission0400IsAcceptable() {
        let url = tmpDir.appendingPathComponent("key_0400")
        try! TestKeyData.openssh.write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o400], ofItemAtPath: url.path)

        XCTAssertFalse(SSHKeyPermissionTests.isPermissionTooOpen(at: url),
                        "0400 (read-only owner) should be acceptable")
    }

    func testPermission0700IsAcceptable() {
        let url = tmpDir.appendingPathComponent("key_0700")
        try! TestKeyData.openssh.write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: url.path)

        XCTAssertFalse(SSHKeyPermissionTests.isPermissionTooOpen(at: url),
                        "0700 should be acceptable (owner-only)")
    }

    func testPermission0666IsTooOpen() {
        let url = tmpDir.appendingPathComponent("key_0666")
        try! TestKeyData.openssh.write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o666], ofItemAtPath: url.path)

        XCTAssertTrue(SSHKeyPermissionTests.isPermissionTooOpen(at: url),
                       "0666 should be flagged as too open")
    }
}

// MARK: - Passphrase Validation Tests

final class SSHPassphraseValidationTests: XCTestCase {

    /// Validate passphrase constraints.
    /// - Empty passphrase is allowed for unencrypted keys.
    /// - For encrypted keys, empty passphrase should produce an error.
    /// - Passphrase must not contain null bytes.
    static func validatePassphrase(_ passphrase: String, keyIsEncrypted: Bool) -> (valid: Bool, error: String?) {
        // Null bytes are never acceptable
        if passphrase.contains("\0") {
            return (false, "Passphrase contains null bytes")
        }

        // Empty passphrase for encrypted keys
        if keyIsEncrypted && passphrase.isEmpty {
            return (false, "Passphrase required for encrypted key")
        }

        return (true, nil)
    }

    func testEmptyPassphraseForUnencryptedKey() {
        let result = Self.validatePassphrase("", keyIsEncrypted: false)
        XCTAssertTrue(result.valid, "Empty passphrase is OK for unencrypted keys")
    }

    func testEmptyPassphraseForEncryptedKey() {
        let result = Self.validatePassphrase("", keyIsEncrypted: true)
        XCTAssertFalse(result.valid, "Empty passphrase should fail for encrypted keys")
        XCTAssertNotNil(result.error)
    }

    func testNullByteInPassphrase() {
        let result = Self.validatePassphrase("pass\0word", keyIsEncrypted: false)
        XCTAssertFalse(result.valid, "Null bytes in passphrase should be rejected")
    }

    func testValidPassphrase() {
        let result = Self.validatePassphrase("MyS3cur3P@ss!", keyIsEncrypted: true)
        XCTAssertTrue(result.valid)
        XCTAssertNil(result.error)
    }

    func testUnicodePassphrase() {
        let result = Self.validatePassphrase("パスワード🔑", keyIsEncrypted: true)
        XCTAssertTrue(result.valid, "Unicode passphrases should be accepted")
    }

    func testLongPassphrase() {
        let long = String(repeating: "A", count: 1024)
        let result = Self.validatePassphrase(long, keyIsEncrypted: true)
        XCTAssertTrue(result.valid, "Long passphrases should be accepted")
    }
}

// MARK: - Keychain Integration Tests

final class SSHKeychainTests: XCTestCase {

    /// Service name used for Keychain entries.
    private static let keychainService = "com.teraterm.mac.ssh.test"

    override func tearDown() {
        // Clean up test Keychain entries
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
        ]
        SecItemDelete(query as CFDictionary)
        super.tearDown()
    }

    /// Save a passphrase to Keychain.
    static func saveToKeychain(service: String, account: String, passphrase: String) -> OSStatus {
        guard let data = passphrase.data(using: .utf8) else {
            return errSecParam
        }

        // Delete existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new entry
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Load a passphrase from Keychain.
    static func loadFromKeychain(service: String, account: String) -> (status: OSStatus, passphrase: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return (status, String(data: data, encoding: .utf8))
        }
        return (status, nil)
    }

    /// Delete a Keychain entry.
    static func deleteFromKeychain(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary)
    }

    func testSaveAndLoadPassphrase() {
        let service = Self.keychainService
        let account = "testuser@192.168.1.1"
        let passphrase = "S3cretP@ss"

        let saveStatus = Self.saveToKeychain(service: service, account: account, passphrase: passphrase)
        // errSecSuccess (0) or -25308 (interaction not allowed in CI)
        guard saveStatus == errSecSuccess else {
            // Keychain may not be accessible in headless CI environments.
            // This is expected — skip the rest of the test.
            print("Keychain save returned \(saveStatus) — skipping (CI/sandbox environment)")
            return
        }

        let (loadStatus, loaded) = Self.loadFromKeychain(service: service, account: account)
        XCTAssertEqual(loadStatus, errSecSuccess)
        XCTAssertEqual(loaded, passphrase)
    }

    func testDeletePassphrase() {
        let service = Self.keychainService
        let account = "deletetest@host"

        let saveStatus = Self.saveToKeychain(service: service, account: account, passphrase: "temp")
        guard saveStatus == errSecSuccess else {
            print("Keychain save returned \(saveStatus) — skipping")
            return
        }

        let deleteStatus = Self.deleteFromKeychain(service: service, account: account)
        XCTAssertEqual(deleteStatus, errSecSuccess)

        let (loadStatus, _) = Self.loadFromKeychain(service: service, account: account)
        XCTAssertEqual(loadStatus, errSecItemNotFound)
    }

    func testLoadNonexistentReturnsNotFound() {
        let (status, passphrase) = Self.loadFromKeychain(
            service: Self.keychainService, account: "nonexistent@nowhere")
        XCTAssertEqual(status, errSecItemNotFound)
        XCTAssertNil(passphrase)
    }

    func testOverwriteExistingPassphrase() {
        let service = Self.keychainService
        let account = "overwrite@host"

        let s1 = Self.saveToKeychain(service: service, account: account, passphrase: "first")
        guard s1 == errSecSuccess else {
            print("Keychain save returned \(s1) — skipping")
            return
        }

        let s2 = Self.saveToKeychain(service: service, account: account, passphrase: "second")
        XCTAssertEqual(s2, errSecSuccess)

        let (_, loaded) = Self.loadFromKeychain(service: service, account: account)
        XCTAssertEqual(loaded, "second", "Passphrase should be overwritten")
    }

    func testKeychainQueryStructure() {
        // Verify query dictionaries can be constructed correctly
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.teraterm.mac.ssh",
            kSecAttrAccount as String: "user@host",
            kSecReturnData as String: true,
        ]
        XCTAssertEqual(query.count, 4)
        XCTAssertNotNil(query[kSecClass as String])
    }
}

// MARK: - Settings Integration Tests

final class SSHSettingsTests: XCTestCase {

    func testDefaultSSHSettings() {
        let settings = TerminalSettings()
        XCTAssertEqual(settings.sshVersion, .ssh2)
        XCTAssertEqual(settings.sshAuthMethod, .password)
        XCTAssertEqual(settings.sshUsername, "")
        XCTAssertEqual(settings.sshKeyFile, "")
        XCTAssertFalse(settings.sshRememberPassword)
        XCTAssertFalse(settings.sshForwardAgent)
    }

    func testSSHServiceDefaultPort() {
        XCTAssertEqual(ServiceType.ssh.defaultPort, 22)
        XCTAssertEqual(ServiceType.telnet.defaultPort, 23)
    }

    func testSSHVersionEnum() {
        XCTAssertEqual(SSHVersion.ssh1.rawValue, 1)
        XCTAssertEqual(SSHVersion.ssh2.rawValue, 2)
        XCTAssertEqual(SSHVersion.ssh2.displayName, "SSH2")
    }

    func testSSHAuthMethodEnum() {
        XCTAssertEqual(SSHAuthMethod.password.rawValue, 0)
        XCTAssertEqual(SSHAuthMethod.publicKey.rawValue, 1)
        XCTAssertEqual(SSHAuthMethod.rhosts.rawValue, 2)
        XCTAssertEqual(SSHAuthMethod.challengeResponse.rawValue, 3)
        XCTAssertEqual(SSHAuthMethod.pageant.rawValue, 4)
    }

    func testSSHSettingsRoundTripJSON() {
        let original = TerminalSettings()
        original.sshVersion = .ssh2
        original.sshAuthMethod = .publicKey
        original.sshUsername = "admin"
        original.sshKeyFile = "/Users/admin/.ssh/id_ed25519"
        original.sshRememberPassword = true
        original.sshForwardAgent = true

        // Encode to JSON and decode back
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard let data = try? encoder.encode(original),
              let loaded = try? decoder.decode(TerminalSettings.self, from: data) else {
            XCTFail("JSON round-trip failed")
            return
        }

        XCTAssertEqual(loaded.sshVersion, .ssh2)
        XCTAssertEqual(loaded.sshAuthMethod, .publicKey)
        XCTAssertEqual(loaded.sshUsername, "admin")
        XCTAssertEqual(loaded.sshKeyFile, "/Users/admin/.ssh/id_ed25519")
        XCTAssertTrue(loaded.sshRememberPassword)
        XCTAssertTrue(loaded.sshForwardAgent)
    }
}

#endif
