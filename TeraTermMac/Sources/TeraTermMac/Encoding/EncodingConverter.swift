/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of charset.cpp / unicode.cpp to Swift/macOS
 * Character encoding conversion and Unicode support
 */

import Foundation

// MARK: - Encoding Converter

class EncodingConverter {
    // MARK: - String Encoding Mapping

    static func cfStringEncoding(for encoding: CharacterEncoding) -> CFStringEncoding {
        switch encoding {
        case .utf8:       return CFStringBuiltInEncodings.UTF8.rawValue
        case .sjis:       return CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
        case .eucjp:      return CFStringEncoding(CFStringEncodings.EUC_JP.rawValue)
        case .jis:        return CFStringEncoding(CFStringEncodings.ISO_2022_JP.rawValue)
        case .iso8859_1:  return CFStringBuiltInEncodings.isoLatin1.rawValue
        case .iso8859_2:  return CFStringEncoding(CFStringEncodings.isoLatin2.rawValue)
        case .iso8859_3:  return CFStringEncoding(CFStringEncodings.isoLatin3.rawValue)
        case .iso8859_4:  return CFStringEncoding(CFStringEncodings.isoLatin4.rawValue)
        case .iso8859_5:  return CFStringEncoding(CFStringEncodings.isoLatinCyrillic.rawValue)
        case .iso8859_6:  return CFStringEncoding(CFStringEncodings.isoLatinArabic.rawValue)
        case .iso8859_7:  return CFStringEncoding(CFStringEncodings.isoLatinGreek.rawValue)
        case .iso8859_8:  return CFStringEncoding(CFStringEncodings.isoLatinHebrew.rawValue)
        case .iso8859_9:  return CFStringEncoding(CFStringEncodings.isoLatin5.rawValue)
        case .iso8859_10: return CFStringEncoding(CFStringEncodings.isoLatin6.rawValue)
        case .iso8859_11: return CFStringEncoding(CFStringEncodings.isoLatinThai.rawValue)
        case .iso8859_13: return CFStringEncoding(CFStringEncodings.isoLatin7.rawValue)
        case .iso8859_14: return CFStringEncoding(CFStringEncodings.isoLatin8.rawValue)
        case .iso8859_15: return CFStringEncoding(CFStringEncodings.isoLatin9.rawValue)
        case .iso8859_16: return CFStringEncoding(CFStringEncodings.isoLatin10.rawValue)
        case .cp949:      return CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        case .gb2312:     return CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue)
        case .big5:       return CFStringEncoding(CFStringEncodings.big5.rawValue)
        case .cp866:      return CFStringEncoding(CFStringEncodings.dosRussian.rawValue)
        case .cp1251:     return CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)
        case .koi8r:      return CFStringEncoding(CFStringEncodings.KOI8_R.rawValue)
        }
    }

    static func nsStringEncoding(for encoding: CharacterEncoding) -> String.Encoding {
        let cfEnc = cfStringEncoding(for: encoding)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        return String.Encoding(rawValue: nsEnc)
    }

    // MARK: - Convert Data to String

    static func decode(_ data: Data, encoding: CharacterEncoding) -> String {
        let strEncoding = nsStringEncoding(for: encoding)
        if let str = String(data: data, encoding: strEncoding) {
            return str
        }
        // Fallback to UTF-8 with lossy replacement
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Convert String to Data

    static func encode(_ string: String, encoding: CharacterEncoding) -> Data {
        let strEncoding = nsStringEncoding(for: encoding)
        if let data = string.data(using: strEncoding) {
            return data
        }
        return Data(string.utf8)
    }

    // MARK: - Unicode Width Detection (port of unicode.cpp)

    /// East Asian Width property based character width
    static func unicodeWidth(_ scalar: UnicodeScalar) -> Int {
        let v = scalar.value

        // Control characters
        if v < 0x20 || (v >= 0x7F && v < 0xA0) { return 0 }

        // Combining characters (width = 0)
        if isCombining(scalar) { return 0 }

        // Full-width and wide characters
        if isWide(scalar) { return 2 }

        return 1
    }

    /// Check if a scalar is a combining character
    static func isCombining(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        // Combining Diacritical Marks
        if v >= 0x0300 && v <= 0x036F { return true }
        // Combining Diacritical Marks Extended
        if v >= 0x1AB0 && v <= 0x1AFF { return true }
        // Combining Diacritical Marks Supplement
        if v >= 0x1DC0 && v <= 0x1DFF { return true }
        // Combining Diacritical Marks for Symbols
        if v >= 0x20D0 && v <= 0x20FF { return true }
        // Combining Half Marks
        if v >= 0xFE20 && v <= 0xFE2F { return true }
        // CJK Compatibility Ideographs (some combining)
        if v >= 0xFE00 && v <= 0xFE0F { return true } // Variation Selectors
        if v >= 0xE0100 && v <= 0xE01EF { return true } // Variation Selectors Supplement

        return false
    }

    /// Check if a scalar is wide (East Asian Width W or F)
    static func isWide(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value

        // CJK ranges
        if v >= 0x1100 && v <= 0x115F { return true }   // Hangul Jamo
        if v >= 0x2329 && v <= 0x232A { return true }   // Angle brackets
        if v >= 0x2E80 && v <= 0x303E { return true }   // CJK Radicals
        if v >= 0x3041 && v <= 0x33BF { return true }   // Hiragana, Katakana, CJK
        if v >= 0x3400 && v <= 0x4DBF { return true }   // CJK Unified Ext A
        if v >= 0x4E00 && v <= 0x9FFF { return true }   // CJK Unified
        if v >= 0xA000 && v <= 0xA4CF { return true }   // Yi
        if v >= 0xAC00 && v <= 0xD7AF { return true }   // Hangul Syllables
        if v >= 0xF900 && v <= 0xFAFF { return true }   // CJK Compatibility
        if v >= 0xFE10 && v <= 0xFE19 { return true }   // Vertical Forms
        if v >= 0xFE30 && v <= 0xFE6F { return true }   // CJK Compatibility Forms
        if v >= 0xFF01 && v <= 0xFF60 { return true }   // Fullwidth Forms
        if v >= 0xFFE0 && v <= 0xFFE6 { return true }   // Fullwidth Signs
        if v >= 0x20000 && v <= 0x2FFFD { return true } // CJK Unified Ext B+
        if v >= 0x30000 && v <= 0x3FFFD { return true } // CJK Unified Ext G+

        // Emoji that are typically wide
        if v >= 0x1F300 && v <= 0x1F9FF { return true }
        if v >= 0x1FA00 && v <= 0x1FA6F { return true }
        if v >= 0x1FA70 && v <= 0x1FAFF { return true }

        return false
    }

    // MARK: - DEC Special Graphics Character Translation

    static func decSpecialGraphics(_ char: Character) -> Character {
        guard let ascii = char.asciiValue else { return char }
        // Map range 0x60-0x7E to DEC Special Graphics
        switch ascii {
        case 0x60: return "\u{25C6}" // Diamond
        case 0x61: return "\u{2592}" // Checkerboard
        case 0x62: return "\u{2409}" // HT symbol
        case 0x63: return "\u{240C}" // FF symbol
        case 0x64: return "\u{240D}" // CR symbol
        case 0x65: return "\u{240A}" // LF symbol
        case 0x66: return "\u{00B0}" // Degree
        case 0x67: return "\u{00B1}" // Plus/minus
        case 0x68: return "\u{2424}" // NL symbol
        case 0x69: return "\u{240B}" // VT symbol
        case 0x6A: return "\u{2518}" // Lower right corner
        case 0x6B: return "\u{2510}" // Upper right corner
        case 0x6C: return "\u{250C}" // Upper left corner
        case 0x6D: return "\u{2514}" // Lower left corner
        case 0x6E: return "\u{253C}" // Crossing lines
        case 0x6F: return "\u{23BA}" // Horizontal line - scan 1
        case 0x70: return "\u{23BB}" // Horizontal line - scan 3
        case 0x71: return "\u{2500}" // Horizontal line - scan 5
        case 0x72: return "\u{23BC}" // Horizontal line - scan 7
        case 0x73: return "\u{23BD}" // Horizontal line - scan 9
        case 0x74: return "\u{251C}" // Left T
        case 0x75: return "\u{2524}" // Right T
        case 0x76: return "\u{2534}" // Bottom T
        case 0x77: return "\u{252C}" // Top T
        case 0x78: return "\u{2502}" // Vertical line
        case 0x79: return "\u{2264}" // Less or equal
        case 0x7A: return "\u{2265}" // Greater or equal
        case 0x7B: return "\u{03C0}" // Pi
        case 0x7C: return "\u{2260}" // Not equal
        case 0x7D: return "\u{00A3}" // Pound sterling
        case 0x7E: return "\u{00B7}" // Middle dot
        default: return char
        }
    }
}
