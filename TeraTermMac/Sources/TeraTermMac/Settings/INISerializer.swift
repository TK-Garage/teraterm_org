/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * INISerializer.swift
 * Platform-independent INI file parser and serializer with automatic
 * line-ending detection (CRLF / LF / CR).
 */

import Foundation

// MARK: - INI File Parser / Serializer

/// Reads and writes Windows-style INI files with section and key=value pairs.
/// Preserves ordering on round-trip and auto-detects line endings.
struct INISerializer {

    // MARK: - Types

    /// One section of an INI file.
    struct Section {
        var name: String
        var pairs: [(key: String, value: String)]
    }

    /// Detected (or desired) line ending style.
    enum LineEnding: String {
        case crlf = "\r\n"
        case lf   = "\n"
        case cr   = "\r"
    }

    // MARK: - Parsing

    /// Parse an INI string into ordered sections.
    /// Keys before any `[Section]` header go into a section with an empty name.
    static func parse(_ text: String) -> (sections: [Section], lineEnding: LineEnding) {
        let lineEnding = detectLineEnding(text)
        let lines = text.components(separatedBy: .newlines)

        var sections: [Section] = []
        var current = Section(name: "", pairs: [])

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {
                continue
            }

            // Section header
            if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                // Save previous section
                sections.append(current)
                let name = String(line[line.index(after: line.startIndex)..<close])
                current = Section(name: name, pairs: [])
                continue
            }

            // Key=Value
            if let eqIdx = line.firstIndex(of: "=") {
                let key = String(line[line.startIndex..<eqIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                current.pairs.append((key: key, value: value))
            }
        }
        sections.append(current)

        // Remove leading empty section if it has no pairs
        if let first = sections.first, first.name.isEmpty && first.pairs.isEmpty {
            sections.removeFirst()
        }

        return (sections, lineEnding)
    }

    // MARK: - Serialization

    /// Serialize sections to an INI string.
    static func serialize(_ sections: [Section], lineEnding: LineEnding = .lf) -> String {
        let nl = lineEnding.rawValue
        var out = ""

        for (i, section) in sections.enumerated() {
            if !section.name.isEmpty {
                if i > 0 { out += nl }
                out += "[\(section.name)]" + nl
            }
            for pair in section.pairs {
                out += "\(pair.key)=\(pair.value)" + nl
            }
        }
        return out
    }

    // MARK: - Convenience Accessors

    /// Get a value for a key in a named section.
    static func getValue(from sections: [Section], section: String, key: String) -> String? {
        guard let sec = sections.first(where: { $0.name.caseInsensitiveCompare(section) == .orderedSame }) else {
            return nil
        }
        return sec.pairs.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
    }

    /// Set a value for a key in a named section.  Creates the section/key if absent.
    static func setValue(in sections: inout [Section], section: String, key: String, value: String) {
        if let si = sections.firstIndex(where: { $0.name.caseInsensitiveCompare(section) == .orderedSame }) {
            if let ki = sections[si].pairs.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
                sections[si].pairs[ki].value = value
            } else {
                sections[si].pairs.append((key: key, value: value))
            }
        } else {
            sections.append(Section(name: section, pairs: [(key: key, value: value)]))
        }
    }

    // MARK: - Line Ending Detection

    static func detectLineEnding(_ text: String) -> LineEnding {
        let crlfCount = text.components(separatedBy: "\r\n").count - 1
        let crOnly    = text.components(separatedBy: "\r").count - 1 - crlfCount
        let lfOnly    = text.components(separatedBy: "\n").count - 1 - crlfCount

        if crlfCount >= lfOnly && crlfCount >= crOnly { return .crlf }
        if crOnly > lfOnly { return .cr }
        return .lf
    }
}
