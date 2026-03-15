/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Keychain integration for TTLMacro password commands.
 * Uses macOS Security framework for secure password storage.
 */

import Foundation
import Security

// MARK: - Keychain Error

enum TTLKeychainError: Error, CustomStringConvertible {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case notFound
    case encodingFailed
    case decodingFailed

    var description: String {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed: \(status)"
        case .loadFailed(let status):
            return "Keychain load failed: \(status)"
        case .deleteFailed(let status):
            return "Keychain delete failed: \(status)"
        case .notFound:
            return "Keychain item not found"
        case .encodingFailed:
            return "Password encoding failed"
        case .decodingFailed:
            return "Password decoding failed"
        }
    }
}

// MARK: - TTLKeychainManager

/// Manages password storage in macOS Keychain for TTLMacro.
/// Account naming convention: "host:username" (e.g., "192.168.1.1:admin")
///
/// Security requirements:
/// - Passwords are NEVER stored in UserDefaults, files, or logs.
/// - XPC communication uses Data type, zeroed after use.
/// - Keychain access: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
class TTLKeychainManager {

    static let shared = TTLKeychainManager()
    let serviceName: String

    init(serviceName: String = "com.yourapp.TeraTermMac.TTLMacro") {
        self.serviceName = serviceName
    }

    // MARK: - Save

    /// Save a password to Keychain.
    /// - Parameters:
    ///   - password: The password to store
    ///   - account: Account identifier (e.g., "host:username")
    func save(password: String, account: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw TTLKeychainError.encodingFailed
        }

        // Delete existing entry first (ignore errors)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TTLKeychainError.saveFailed(status)
        }
    }

    // MARK: - Load

    /// Load a password from Keychain.
    /// - Parameter account: Account identifier (e.g., "host:username")
    /// - Returns: The stored password
    func load(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw TTLKeychainError.notFound
            }
            throw TTLKeychainError.loadFailed(status)
        }

        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw TTLKeychainError.decodingFailed
        }

        return password
    }

    // MARK: - Delete

    /// Delete a password from Keychain.
    /// - Parameter account: Account identifier (e.g., "host:username")
    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TTLKeychainError.deleteFailed(status)
        }
    }

    // MARK: - Exists

    /// Check if a password exists in Keychain.
    /// - Parameter account: Account identifier
    /// - Returns: true if password exists
    func exists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Secure Data Helpers

    /// Create a zeroed-out copy of data for secure disposal.
    /// Call this after sending password data over XPC.
    static func zeroData(_ data: inout Data) {
        let count = data.count
        data.withUnsafeMutableBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                memset(baseAddress, 0, count)
            }
        }
    }
}
