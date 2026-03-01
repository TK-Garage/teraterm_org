/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * (See LICENSE.md for full license text)
 */

import Foundation

// MARK: - Terminal ID (port of tttypes_termid.h)

enum TerminalID: Int, Codable, CaseIterable {
    case vt100 = 1
    case vt100j = 2
    case vt101 = 3
    case vt102 = 4
    case vt102j = 5
    case vt220 = 6
    case vt220j = 7
    case vt282 = 8
    case vt320 = 9
    case vt382 = 10
    case vt420 = 11
    case vt520 = 12
    case vt525 = 13
    case dumb = 14

    var displayName: String {
        switch self {
        case .vt100: return "VT100"
        case .vt100j: return "VT100J"
        case .vt101: return "VT101"
        case .vt102: return "VT102"
        case .vt102j: return "VT102J"
        case .vt220: return "VT220"
        case .vt220j: return "VT220J"
        case .vt282: return "VT282"
        case .vt320: return "VT320"
        case .vt382: return "VT382"
        case .vt420: return "VT420"
        case .vt520: return "VT520"
        case .vt525: return "VT525"
        case .dumb: return "DUMB"
        }
    }
}

// MARK: - Character Encoding (port of tttypes_charset.h)

enum CharacterEncoding: Int, Codable, CaseIterable {
    case utf8 = 1
    case sjis = 2
    case eucjp = 3
    case jis = 4
    case iso8859_1 = 5
    case iso8859_2 = 6
    case iso8859_3 = 7
    case iso8859_4 = 8
    case iso8859_5 = 9
    case iso8859_6 = 10
    case iso8859_7 = 11
    case iso8859_8 = 12
    case iso8859_9 = 13
    case iso8859_10 = 14
    case iso8859_11 = 15
    case iso8859_13 = 16
    case iso8859_14 = 17
    case iso8859_15 = 18
    case iso8859_16 = 19
    case cp949 = 20     // Korean
    case gb2312 = 21    // Chinese Simplified
    case big5 = 22      // Chinese Traditional
    case cp866 = 23     // Russian DOS
    case cp1251 = 24    // Russian Windows
    case koi8r = 25     // Russian KOI8-R

    var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .sjis: return "Shift_JIS"
        case .eucjp: return "EUC-JP"
        case .jis: return "JIS"
        case .iso8859_1: return "ISO 8859-1 (Latin-1)"
        case .iso8859_2: return "ISO 8859-2 (Latin-2)"
        case .iso8859_3: return "ISO 8859-3 (Latin-3)"
        case .iso8859_4: return "ISO 8859-4 (Latin-4)"
        case .iso8859_5: return "ISO 8859-5 (Cyrillic)"
        case .iso8859_6: return "ISO 8859-6 (Arabic)"
        case .iso8859_7: return "ISO 8859-7 (Greek)"
        case .iso8859_8: return "ISO 8859-8 (Hebrew)"
        case .iso8859_9: return "ISO 8859-9 (Latin-5)"
        case .iso8859_10: return "ISO 8859-10 (Latin-6)"
        case .iso8859_11: return "ISO 8859-11 (Thai)"
        case .iso8859_13: return "ISO 8859-13 (Latin-7)"
        case .iso8859_14: return "ISO 8859-14 (Latin-8)"
        case .iso8859_15: return "ISO 8859-15 (Latin-9)"
        case .iso8859_16: return "ISO 8859-16 (Latin-10)"
        case .cp949: return "CP949 (Korean)"
        case .gb2312: return "GB2312 (Chinese Simplified)"
        case .big5: return "Big5 (Chinese Traditional)"
        case .cp866: return "CP866 (Russian DOS)"
        case .cp1251: return "CP1251 (Russian Windows)"
        case .koi8r: return "KOI8-R (Russian)"
        }
    }
}

// MARK: - Port Type

enum PortType: Int, Codable {
    case tcpip = 0
    case serial = 1
    case file = 2
    case namedPipe = 3
}

// MARK: - Cursor Shape

enum CursorShape: Int, Codable {
    case block = 0
    case vertical = 1
    case horizontal = 2
}

// MARK: - New Line Mode

enum NewLineMode: Int, Codable {
    case cr = 0
    case crlf = 1
    case lf = 2
    case auto_ = 3
}

// MARK: - Flow Control

enum FlowControl: Int, Codable {
    case none = 0
    case xonXoff = 1
    case hardware = 2
}

// MARK: - Parity

enum Parity: Int, Codable {
    case none = 0
    case odd = 1
    case even = 2
    case mark = 3
    case space = 4
}

// MARK: - Beep Type

enum BeepType: Int, Codable {
    case none = 0
    case system = 1
    case visual = 2
}

// MARK: - Color Theme

struct TerminalColorTheme: Codable {
    var foreground: TerminalColor = TerminalColor(r: 255, g: 255, b: 255)
    var background: TerminalColor = TerminalColor(r: 0, g: 0, b: 0)
    var cursorColor: TerminalColor = TerminalColor(r: 0, g: 255, b: 0)
    var selectionForeground: TerminalColor = TerminalColor(r: 0, g: 0, b: 0)
    var selectionBackground: TerminalColor = TerminalColor(r: 128, g: 128, b: 255)
    var urlColor: TerminalColor = TerminalColor(r: 0, g: 128, b: 255)

    // ANSI 16 colors
    var ansiColors: [TerminalColor] = TerminalColorTheme.defaultAnsiColors

    static let defaultAnsiColors: [TerminalColor] = [
        TerminalColor(r: 0,   g: 0,   b: 0),     // Black
        TerminalColor(r: 187, g: 0,   b: 0),     // Red
        TerminalColor(r: 0,   g: 187, b: 0),     // Green
        TerminalColor(r: 187, g: 187, b: 0),     // Yellow
        TerminalColor(r: 0,   g: 0,   b: 187),   // Blue
        TerminalColor(r: 187, g: 0,   b: 187),   // Magenta
        TerminalColor(r: 0,   g: 187, b: 187),   // Cyan
        TerminalColor(r: 187, g: 187, b: 187),   // White
        TerminalColor(r: 85,  g: 85,  b: 85),    // Bright Black
        TerminalColor(r: 255, g: 85,  b: 85),    // Bright Red
        TerminalColor(r: 85,  g: 255, b: 85),    // Bright Green
        TerminalColor(r: 255, g: 255, b: 85),    // Bright Yellow
        TerminalColor(r: 85,  g: 85,  b: 255),   // Bright Blue
        TerminalColor(r: 255, g: 85,  b: 255),   // Bright Magenta
        TerminalColor(r: 85,  g: 255, b: 255),   // Bright Cyan
        TerminalColor(r: 255, g: 255, b: 255),   // Bright White
    ]
}

struct TerminalColor: Codable, Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
}

// MARK: - TTTSet equivalent (port of tttypes.h TTTSet)

class TerminalSettings: Codable {
    // Terminal Emulation
    var terminalID: TerminalID = .vt220
    var terminalWidth: Int = 80
    var terminalHeight: Int = 24
    var autoWinResize: Bool = false
    var termIsWin: Bool = true

    // Character Handling
    var encoding: CharacterEncoding = .utf8
    var sendEncoding: CharacterEncoding = .utf8
    var localEcho: Bool = false
    var answerback: String = ""

    // New line
    var crSend: NewLineMode = .cr
    var crReceive: NewLineMode = .cr

    // Cursor
    var cursorShape: CursorShape = .block
    var cursorBlink: Bool = true

    // Scroll Buffer
    var enableScrollBuffer: Bool = true
    var scrollBufferSize: Int = 10000
    var scrollBufferMax: Int = 500000

    // Display
    var fontName: String = "Menlo"
    var fontSize: Double = 14.0
    var colorTheme: TerminalColorTheme = TerminalColorTheme()

    // Unicode
    var unicodeAmbiguousWidth: Int = 1  // 1=narrow, 2=wide
    var unicodeEmojiWidth: Int = 2

    // Window
    var title: String = "Tera Term"
    var titleFormat: Int = 0  // 0=title, 1=hostname, etc.
    var windowAlpha: Double = 1.0

    // Connection
    var portType: PortType = .tcpip
    var defaultPort: Int = 23
    var hostname: String = ""
    var telnet: Bool = true
    var termType: String = "xterm"

    // Serial Port
    var serialPort: String = ""
    var baudRate: Int = 9600
    var dataBits: Int = 8
    var parity: Parity = .none
    var stopBits: Int = 1
    var flowControl: FlowControl = .none

    // Keyboard
    var bsKey: Int = 8  // 8=BS, 127=DEL
    var deleteKey: Int = 127
    var metaKey: Int = 0  // 0=off, 1=on

    // Beep
    var beepType: BeepType = .system

    // Log
    var logAutoStart: Bool = false
    var logDefaultDirectory: String = ""
    var logDefaultName: String = "teraterm.log"
    var logTimestamp: Bool = false
    var logPlainText: Bool = true

    // File Transfer
    var xmodemOption: Int = 1  // 1=checksum, 2=CRC, 3=1K
    var zmodemDataLen: Int = 1024
    var zmodemWindowSize: Int = 32767

    // Mouse
    var mouseTracking: Bool = true
    var mouseWheelScrollLines: Int = 3

    // Misc
    var confirmOnDisconnect: Bool = true
    var beepOnConnect: Bool = false

    // Paths
    var setupDirectory: String = ""
    var macroDirectory: String = ""

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let dir = appSupport?.appendingPathComponent("TeraTermMac").path {
            setupDirectory = dir
            macroDirectory = dir
            logDefaultDirectory = dir
        }
    }

    // MARK: - Save/Load

    func save(to url: URL? = nil) {
        let fileURL = url ?? defaultSettingsURL
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }

    static func load(from url: URL? = nil) -> TerminalSettings {
        let fileURL = url ?? TerminalSettings().defaultSettingsURL
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(TerminalSettings.self, from: data)
        } catch {
            return TerminalSettings()
        }
    }

    private var defaultSettingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TeraTermMac/settings.json")
    }
}
