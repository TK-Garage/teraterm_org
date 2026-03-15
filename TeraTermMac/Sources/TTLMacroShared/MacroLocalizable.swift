/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Localization helper for TTLMacro shared strings.
 * Uses Bundle.module for SPM resource bundles.
 */

import Foundation

// MARK: - Localization Helper

/// Localized string lookup from the TTLMacroShared bundle.
/// Falls back to the key itself if the translation is not found.
public func L(_ key: String) -> String {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle.main
    #endif

    let value = bundle.localizedString(forKey: key, value: nil, table: nil)
    if value != key {
        return value
    }

    // Try to find the preferred language bundle explicitly
    let savedLanguage = UserDefaults.standard.string(forKey: "TeraTermUILanguage") ?? "Japanese"
    let langCode: String
    switch savedLanguage {
    case "Auto":
        let preferredLangs = Bundle.preferredLocalizations(from: bundle.localizations)
        langCode = preferredLangs.first ?? "ja"
    case "English":
        langCode = "en"
    default:
        langCode = "ja"
    }

    if let path = bundle.path(forResource: langCode, ofType: "lproj"),
       let langBundle = Bundle(path: path) {
        let localized = langBundle.localizedString(forKey: key, value: nil, table: nil)
        if localized != key {
            return localized
        }
    }

    return key
}

/// Localized string with format arguments.
public func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L(key)
    return String(format: format, arguments: args)
}
