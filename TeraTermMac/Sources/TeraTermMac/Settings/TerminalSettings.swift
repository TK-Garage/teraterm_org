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
    // Unicode
    case utf8 = 1
    case utf16 = 30
    case utf16be = 31
    case utf16le = 32
    case utf32 = 33
    case utf32be = 34
    case utf32le = 35

    // Japanese
    case sjis = 2
    case eucjp = 3
    case jis = 4       // ISO-2022-JP

    // Chinese
    case gb2312 = 21
    case gbk = 36
    case big5 = 22
    case big5hkscs = 37

    // Korean
    case eucKR = 20

    // Western / ISO 8859
    case iso8859_1 = 5
    case iso8859_2 = 6
    case iso8859_3 = 7
    case iso8859_4 = 8
    case iso8859_5 = 9      // Cyrillic
    case iso8859_6 = 10     // Arabic
    case iso8859_7 = 11     // Greek
    case iso8859_8 = 12     // Hebrew
    case iso8859_9 = 13
    case iso8859_10 = 14
    case iso8859_11 = 15    // Thai (TIS-620)
    case iso8859_13 = 16
    case iso8859_14 = 17
    case iso8859_15 = 18
    case iso8859_16 = 19

    // DOS / Windows
    case cp437 = 38         // DOS Latin US
    case cp932 = 39         // DOS Japanese (≒ Shift_JIS superset)
    case cp1252 = 40        // Windows Latin 1
    case cp1251 = 24        // Windows Cyrillic
    case cp1253 = 41        // Windows Greek
    case cp1255 = 42        // Windows Hebrew
    case cp1256 = 43        // Windows Arabic
    case cp866 = 23         // DOS Russian
    case koi8r = 25

    // Encoding group for menu display
    enum Group: CaseIterable {
        case unicode
        case japanese
        case chinese
        case korean
        case western
        case dosWindows
    }

    var group: Group {
        switch self {
        case .utf8, .utf16, .utf16be, .utf16le, .utf32, .utf32be, .utf32le:
            return .unicode
        case .sjis, .eucjp, .jis:
            return .japanese
        case .gb2312, .gbk, .big5, .big5hkscs:
            return .chinese
        case .eucKR:
            return .korean
        case .iso8859_1, .iso8859_2, .iso8859_3, .iso8859_4, .iso8859_5,
             .iso8859_6, .iso8859_7, .iso8859_8, .iso8859_9, .iso8859_10,
             .iso8859_11, .iso8859_13, .iso8859_14, .iso8859_15, .iso8859_16:
            return .western
        case .cp437, .cp932, .cp1252, .cp1251, .cp1253, .cp1255, .cp1256,
             .cp866, .koi8r:
            return .dosWindows
        }
    }

    static func encodings(in group: Group) -> [CharacterEncoding] {
        allCases.filter { $0.group == group }
    }

    var displayName: String {
        switch self {
        // Unicode
        case .utf8:       return "Unicode (UTF-8)"
        case .utf16:      return "Unicode (UTF-16)"
        case .utf16be:    return "Unicode (UTF-16BE)"
        case .utf16le:    return "Unicode (UTF-16LE)"
        case .utf32:      return "Unicode (UTF-32)"
        case .utf32be:    return "Unicode (UTF-32BE)"
        case .utf32le:    return "Unicode (UTF-32LE)"
        // Japanese
        case .sjis:       return "Japanese (Shift JIS)"
        case .eucjp:      return "Japanese (EUC-JP)"
        case .jis:        return "Japanese (ISO-2022-JP)"
        // Chinese
        case .gb2312:     return "Chinese Simplified (GB2312)"
        case .gbk:        return "Chinese Simplified (GBK)"
        case .big5:       return "Chinese Traditional (Big5)"
        case .big5hkscs:  return "Chinese Traditional (Big5-HKSCS)"
        // Korean
        case .eucKR:      return "Korean (EUC-KR)"
        // Western
        case .iso8859_1:  return "Western (ISO Latin 1)"
        case .iso8859_2:  return "Central European (ISO Latin 2)"
        case .iso8859_3:  return "ISO 8859-3 (Latin-3)"
        case .iso8859_4:  return "ISO 8859-4 (Latin-4)"
        case .iso8859_5:  return "Cyrillic (ISO 8859-5)"
        case .iso8859_6:  return "Arabic (ISO 8859-6)"
        case .iso8859_7:  return "Greek (ISO 8859-7)"
        case .iso8859_8:  return "Hebrew (ISO 8859-8)"
        case .iso8859_9:  return "ISO 8859-9 (Latin-5)"
        case .iso8859_10: return "ISO 8859-10 (Latin-6)"
        case .iso8859_11: return "Thai (TIS-620)"
        case .iso8859_13: return "ISO 8859-13 (Latin-7)"
        case .iso8859_14: return "ISO 8859-14 (Latin-8)"
        case .iso8859_15: return "ISO 8859-15 (Latin-9)"
        case .iso8859_16: return "ISO 8859-16 (Latin-10)"
        // DOS / Windows
        case .cp437:      return "DOS Latin US"
        case .cp932:      return "DOS Japanese"
        case .cp1252:     return "Windows Latin 1"
        case .cp1251:     return "Windows Cyrillic"
        case .cp1253:     return "Windows Greek"
        case .cp1255:     return "Windows Hebrew"
        case .cp1256:     return "Windows Arabic"
        case .cp866:      return "DOS Russian"
        case .koi8r:      return "KOI8-R"
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

// MARK: - Service Type (port of IDC_HOSTTELNET / IDC_HOSTSSH / IDC_HOSTOTHER)

enum ServiceType: Int, Codable {
    case telnet = 0
    case ssh = 1
    case other = 2

    var defaultPort: Int {
        switch self {
        case .telnet: return 23
        case .ssh: return 22
        case .other: return 0
        }
    }
}

// MARK: - SSH Version (port of IDC_SSH_VERSION)

enum SSHVersion: Int, Codable, CaseIterable {
    case ssh1 = 1
    case ssh2 = 2

    var displayName: String {
        switch self {
        case .ssh1: return "SSH1"
        case .ssh2: return "SSH2"
        }
    }
}

// MARK: - SSH Authentication Method (port of IDD_SSHAUTH)

enum SSHAuthMethod: Int, Codable {
    case password = 0
    case publicKey = 1
    case rhosts = 2
    case challengeResponse = 3
    case pageant = 4
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

// MARK: - Protocol Family (port of AF_UNSPEC/AF_INET/AF_INET6 selection)

enum ProtocolFamily: Int, Codable, CaseIterable {
    case auto_ = 0   // AF_UNSPEC
    case ipv6 = 1    // AF_INET6
    case ipv4 = 2    // AF_INET

    var displayName: String {
        switch self {
        case .auto_: return "AUTO"
        case .ipv6: return "IPv6"
        case .ipv4: return "IPv4"
        }
    }
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
    var crReceive: NewLineMode = .auto_

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
    var serviceType: ServiceType = .telnet
    var defaultPort: Int = 23
    var hostname: String = ""
    var telnet: Bool = true
    var protocolFamily: ProtocolFamily = .auto_
    var hostHistory: [String] = []
    var sshVersion: SSHVersion = .ssh2
    var sshAuthMethod: SSHAuthMethod = .password
    var sshUsername: String = ""
    var sshKeyFile: String = ""
    var sshRememberPassword: Bool = false
    var sshForwardAgent: Bool = false
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
    var clipboardConfirmPaste: Bool = true
    var autoScrollOnOutput: Bool = true
    var clearOnResize: Bool = false
    var cursorChangeIME: Bool = true
    var notifySound: Bool = true

    // Title Format
    var titleFormatTCP: Bool = true
    var titleFormatSerial: Bool = true
    var titleFormatSession: Bool = false

    // Copy and Paste
    var continuedLineCopy: Bool = true
    var confirmPasteNewLine: Bool = true
    var pasteDelay: Int = 5
    var autoTextCopy: Bool = true
    var delimiterList: String = " ;,()\"'"

    // Control Sequence
    var titleChangeRequest: Bool = false
    var titleReportRequest: Bool = false
    var windowControlSequence: Bool = true
    var cursorControlSequence: Bool = true
    var clipboardAccessFromRemote: Bool = false

    // Debug
    var debugCharInfoPopup: Bool = false

    // Font additional
    var vtFontProportional: Bool = false
    var vtFontHidden: Bool = false
    var tekFontName: String = "Menlo"
    var tekFontSize: Double = 14.0
    var tekFontProportional: Bool = false
    var tekFontHidden: Bool = false
    var drawingAPI: Int = 0
    var codePage: Int = 65001
    var charSpaceH: Int = 0
    var charSpaceV: Int = 0
    var fontQuality: Int = 0

    // Visual
    var windowOpacityActive: Int = 100
    var windowOpacityInactive: Int = 100
    var mouseCursorType: Int = 0
    var flickerlessMoveEnabled: Bool = false
    var cornerRounding: Int = 0
    var attrBold: Bool = true
    var attrBlink: Bool = true
    var attrReverse: Bool = true
    var attrUnderline: Bool = true
    var attrStrikethrough: Bool = false

    // Plugin
    var pluginDirectories: [String] = []

    // Theme
    var themeEnabled: Bool = false
    var themeFile: String = ""
    var startupTheme: String = ""
    var fastSizeMove: Bool = false
    var susiePath: String = ""

    // UI
    var language: String = "English"
    var dialogFontName: String = ""
    var dialogFontSize: Double = 0
    var dialogFontProportional: Bool = false
    var dialogFontHidden: Bool = false

    // TCP/IP additional
    var tcpKeepAlive: Bool = true
    var tcpKeepAliveInterval: Int = 300
    var autoWindowClose: Bool = true

    // Log additional
    var logViewEditor: String = ""
    var logEditorArguments: String = ""
    var logAppend: Bool = false
    var logBinary: Bool = false
    var logHideDialog: Bool = false
    var logIncludeScreenBuffer: Bool = false
    var logRotateEnabled: Bool = false
    var logRotateSize: Int = 0
    var logRotateStep: Int = 0

    // File Transfer folder
    var fileTransferFolder: String = ""

    // Proxy
    var proxyType: Int = 0  // 0=none, 1=HTTP, 2=SOCKS4, 3=SOCKS5, 4=Telnet
    var proxyHost: String = ""
    var proxyPort: Int = 0
    var proxyUsername: String = ""
    var proxyPassword: String = ""

    // SSH Setup
    var sshHeartbeat: Int = 60
    var sshConfirmAgentForwarding: Bool = true
    var sshNotifyAgentAccess: Bool = false
    var sshVerifyHostKeyDNS: Bool = false
    var sshKnownHostsFile: String = ""
    var sshHostKeyRotation: Int = 0  // 0=disabled, 1=enabled, 2=ask
    var sshLogLevel: Int = 0

    // SSH Forwarding
    var sshPortForwardings: [String] = []
    var sshXForwarding: Bool = false

    // SSH Auth Setup
    var sshDefaultUsernameMode: Int = 0  // 0=don't enter, 1=default, 2=logon
    var sshDefaultUsername: String = ""
    var sshCheckAuthBeforeLogin: Bool = false

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
