/*
 * KeycodeLocalizable.swift
 * Localization helper for Keycode.app
 *
 * Provides L() function for bilingual support (Japanese / English).
 * Uses Bundle.module for SPM resource bundles.
 */

import Foundation

/// Localized string lookup for Keycode.app.
/// Falls back to the key itself if no translation is found.
func L(_ key: String) -> String {
    // SPM resource bundle
    let value = Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    if value != key {
        return value
    }
    // Fallback: return key
    return key
}

/// Localized string with format arguments.
func L(_ key: String, _ args: CVarArg...) -> String {
    let fmt = L(key)
    return String(format: fmt, arguments: args)
}
