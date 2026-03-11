/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * ConfigPersistenceManager.swift
 * Manages TERATERM.INI in ~/Library/Application Support/com.teraterm.mac/
 * with format-version checking and safe atomic writes.
 */

import Foundation

// MARK: - TeraTermConfig

/// In-memory representation of settings stored in TERATERM.INI.
/// Mirrors the key fields of `TerminalSettings` but is decoupled
/// so that the INI persistence layer can evolve independently.
struct TeraTermConfig {

    /// Current format version written to [Tera Term] Version=
    static let currentVersion = "5.6"

    // [Tera Term] meta
    var version: String = TeraTermConfig.currentVersion

    // Terminal
    var terminalID: String = "VT220"
    var terminalWidth: Int = 80
    var terminalHeight: Int = 24
    var encoding: String = "UTF-8"
    var localEcho: Bool = false
    var autoWrap: Bool = true

    // New-line
    var crSend: Int = 0      // 0=CR, 1=CRLF, 2=LF
    var crReceive: Int = 3   // 0=CR, 1=CRLF, 2=LF, 3=AUTO

    // Display
    var fontName: String = "Menlo"
    var fontSize: Int = 14
    var vtColor: String = "255,255,255 0,0,0"  // fg r,g,b  bg r,g,b
    var cursorShape: Int = 0  // 0=block,1=vertical,2=horizontal
    var cursorBlink: Bool = true

    // Window
    var title: String = "Tera Term"
    var windowAlpha: Int = 255

    // Scroll
    var enableScrollBuffer: Bool = true
    var scrollBufferSize: Int = 10000

    // Connection
    var hostName: String = ""
    var tcpPort: Int = 23
    var telnet: Bool = true
    var portType: Int = 0   // 0=TCP/IP, 1=Serial

    // Serial
    var serialPort: String = ""
    var baudRate: Int = 9600
    var dataBits: Int = 8
    var parity: Int = 0
    var stopBits: Int = 1
    var flowControl: Int = 0

    // Keyboard
    var bsKey: Int = 8
    var deleteKey: Int = 127
    var metaKey: Int = 0

    // Beep
    var beep: Int = 1

    // Log
    var logAutoStart: Bool = false
    var logDefaultName: String = "teraterm.log"
    var logTimestamp: Bool = false

    // Mouse
    var mouseTracking: Bool = true

    // Misc
    var answerback: String = ""
    var confirmOnDisconnect: Bool = true

    // Terminal extended
    var terminalSpeed: String = "38400"
    var killFocusCursor: Bool = true
    // Scroll extended
    var scrollThreshold: Int = 12
    var scrollWindowClearScreen: Bool = true
    // Beep extended
    var beepOverUsedCount: Int = 5
    var beepOverUsedTime: Int = 2
    var beepSuppressTime: Int = 5
    // Connection
    var connectingTimeout: Int = 0
    // Serial extended
    var clearComBuffOnOpen: Bool = true
    var autoComPortReconnect: Bool = true
    // Log extended
    var logTimestampFormat: String = "%Y-%m-%d %H:%M:%S.%N"
    // Control Sequences
    var accept8BitCtrl: Bool = true
    var send8BitCtrl: Bool = false
    var alternateScreenBuffer: Bool = true
    var bracketedPasteMode: Bool = true
    var bracketedControlOnly: Bool = false
    var allowWrongSequence: Bool = false
    var maxOSCBufferSize: Int = 4096
    var enableLineMode: Bool = true
    // Copy/Paste
    var mouseSelectStartDelay: Int = 0
    // Mouse
    var translateWheelToCursor: Bool = true
    var disableWheelToCursorByCtrl: Bool = true
    // Broadcast
    var maxBroadcastHistory: Int = 99
    // Debug
    var debugModes: String = "all"
    // URL
    var joinSplitURL: Bool = false
    var joinSplitURLIgnoreEOLChar: String = "\\\\"
    // Unicode
    var unicodeEmojiOverride: Bool = false
    // Color
    var pcBoldColor: Bool = false
    // File Transfer
    var zmodemAutoReceive: Bool = false
    var confirmFileDragAndDrop: Bool = true
    var autoFileRename: Bool = false
    // Misc
    var clearScreenOnCloseConnection: Bool = false
    var backWrap: Bool = false
    var vtCompatTab: Bool = false
    var fallbackToCP932: Bool = false
    var saveVTWinPos: Bool = false
}

// MARK: - ConfigPersistenceManager

/// Manages the lifecycle of `TERATERM.INI` under Application Support.
///
/// Responsibilities:
/// - Creates the app-specific directory on first use.
/// - Checks format version; deletes and recreates stale files.
/// - Provides atomic writes to prevent corruption.
final class ConfigPersistenceManager {

    // MARK: - Constants

    /// Bundle-ID-based subdirectory (sandbox-safe).
    static let appDirectoryName = "com.teraterm.mac"

    /// Traditional INI filename.
    static let iniFileName = "TERATERM.INI"

    /// Section name that carries the version key.
    static let mainSection = "Tera Term"

    /// Key name inside the main section.
    static let versionKey = "Version"

    // MARK: - Paths

    /// URL of the app-specific Application Support directory.
    var appSupportDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return base.appendingPathComponent(Self.appDirectoryName, isDirectory: true)
    }

    /// URL of TERATERM.INI inside the app support directory.
    var iniFileURL: URL {
        appSupportDirectory.appendingPathComponent(Self.iniFileName)
    }

    // MARK: - Directory Bootstrap

    /// Ensure the app-specific directory exists.
    @discardableResult
    func ensureDirectory() throws -> URL {
        let dir = appSupportDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return dir
    }

    // MARK: - Load

    /// Load configuration from `TERATERM.INI`.
    ///
    /// - If the file does not exist, creates a fresh one with defaults.
    /// - If the file exists but has no version or an outdated version,
    ///   deletes it and recreates with defaults.
    /// - Otherwise reads and returns the stored configuration.
    func loadConfig() -> TeraTermConfig {
        do {
            try ensureDirectory()
        } catch {
            print("ConfigPersistenceManager: Failed to create directory: \(error)")
            return TeraTermConfig()
        }

        let fm = FileManager.default
        let path = iniFileURL

        guard fm.fileExists(atPath: path.path) else {
            // First launch – create defaults
            let config = TeraTermConfig()
            saveConfig(config)
            return config
        }

        // Read existing file
        guard let data = fm.contents(atPath: path.path),
              let text = String(data: data, encoding: .utf8) else {
            // Unreadable – recreate
            print("Old configuration format detected. Recreating...")
            try? fm.removeItem(at: path)
            let config = TeraTermConfig()
            saveConfig(config)
            return config
        }

        let (sections, _) = INISerializer.parse(text)

        // Version check
        let fileVersion = INISerializer.getValue(
            from: sections, section: Self.mainSection, key: Self.versionKey
        )

        if !isVersionCurrent(fileVersion) {
            print("Old configuration format detected. Recreating...")
            try? fm.removeItem(at: path)
            let config = TeraTermConfig()
            saveConfig(config)
            return config
        }

        // Parse into config
        return decode(sections: sections)
    }

    // MARK: - Save

    /// Write configuration to `TERATERM.INI` atomically.
    func saveConfig(_ config: TeraTermConfig) {
        do {
            try ensureDirectory()
        } catch {
            print("ConfigPersistenceManager: Failed to create directory: \(error)")
            return
        }

        let sections = encode(config)
        let text = INISerializer.serialize(sections, lineEnding: .lf)

        guard let data = text.data(using: .utf8) else { return }

        // Atomic write: write to a temp file, then replace.
        let dest = iniFileURL
        let tmpURL = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(Self.iniFileName).tmp")

        do {
            try data.write(to: tmpURL, options: .atomic)

            // If the destination already exists, use replaceItemAt for safety.
            let fm = FileManager.default
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: tmpURL)
            } else {
                try fm.moveItem(at: tmpURL, to: dest)
            }
        } catch {
            print("ConfigPersistenceManager: Failed to save: \(error)")
            // Clean up temp
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    // MARK: - Version Comparison

    /// Returns `true` when `fileVersion` is non-nil and its major.minor
    /// is >= the current version.
    func isVersionCurrent(_ fileVersion: String?) -> Bool {
        guard let fv = fileVersion, !fv.isEmpty else { return false }
        let fileParts  = fv.split(separator: ".").compactMap { Int($0) }
        let curParts   = TeraTermConfig.currentVersion.split(separator: ".").compactMap { Int($0) }
        guard fileParts.count >= 2, curParts.count >= 2 else { return false }

        if fileParts[0] > curParts[0] { return true }
        if fileParts[0] < curParts[0] { return false }
        return fileParts[1] >= curParts[1]
    }

    // MARK: - Encode / Decode

    /// Build INI sections from a `TeraTermConfig`.
    func encode(_ config: TeraTermConfig) -> [INISerializer.Section] {
        var sections: [INISerializer.Section] = []

        // [Tera Term]
        sections.append(.init(name: Self.mainSection, pairs: [
            (key: Self.versionKey, value: config.version),
            // Terminal
            (key: "TerminalID",     value: config.terminalID),
            (key: "TerminalWidth",  value: String(config.terminalWidth)),
            (key: "TerminalHeight", value: String(config.terminalHeight)),
            (key: "Encoding",       value: config.encoding),
            (key: "LocalEcho",      value: config.localEcho ? "on" : "off"),
            (key: "AutoWrap",       value: config.autoWrap ? "on" : "off"),
            (key: "Answerback",     value: config.answerback),
            // New-line
            (key: "CRSend",         value: String(config.crSend)),
            (key: "CRReceive",      value: String(config.crReceive)),
            // Display
            (key: "FontName",       value: config.fontName),
            (key: "FontSize",       value: String(config.fontSize)),
            (key: "VTColor",        value: config.vtColor),
            (key: "CursorShape",    value: String(config.cursorShape)),
            (key: "CursorBlink",    value: config.cursorBlink ? "on" : "off"),
            // Window
            (key: "Title",          value: config.title),
            (key: "WindowAlpha",    value: String(config.windowAlpha)),
            // Scroll
            (key: "EnableScrollBuffer", value: config.enableScrollBuffer ? "on" : "off"),
            (key: "ScrollBufferSize",   value: String(config.scrollBufferSize)),
            // Keyboard
            (key: "BSKey",          value: String(config.bsKey)),
            (key: "DeleteKey",      value: String(config.deleteKey)),
            (key: "MetaKey",        value: String(config.metaKey)),
            // Beep
            (key: "Beep",           value: String(config.beep)),
            // Log
            (key: "LogAutoStart",   value: config.logAutoStart ? "on" : "off"),
            (key: "LogDefaultName", value: config.logDefaultName),
            (key: "LogTimestamp",   value: config.logTimestamp ? "on" : "off"),
            // Mouse
            (key: "MouseTracking",  value: config.mouseTracking ? "on" : "off"),
            // Misc
            (key: "ConfirmOnDisconnect", value: config.confirmOnDisconnect ? "on" : "off"),
            // Terminal extended
            (key: "TerminalSpeed", value: config.terminalSpeed),
            (key: "KillFocusCursor", value: config.killFocusCursor ? "on" : "off"),
            // Scroll extended
            (key: "ScrollThreshold", value: String(config.scrollThreshold)),
            (key: "ScrollWindowClearScreen", value: config.scrollWindowClearScreen ? "on" : "off"),
            // Beep extended
            (key: "BeepOverUsedCount", value: String(config.beepOverUsedCount)),
            (key: "BeepOverUsedTime", value: String(config.beepOverUsedTime)),
            (key: "BeepSuppressTime", value: String(config.beepSuppressTime)),
            // Connection
            (key: "ConnectingTimeout", value: String(config.connectingTimeout)),
            // Serial extended
            (key: "ClearComBuffOnOpen", value: config.clearComBuffOnOpen ? "on" : "off"),
            (key: "AutoComPortReconnect", value: config.autoComPortReconnect ? "on" : "off"),
            // Log extended
            (key: "LogTimestampFormat", value: config.logTimestampFormat),
            // Control sequences
            (key: "Accept8BitCtrl", value: config.accept8BitCtrl ? "on" : "off"),
            (key: "Send8BitCtrl", value: config.send8BitCtrl ? "on" : "off"),
            (key: "AlternateScreenBuffer", value: config.alternateScreenBuffer ? "on" : "off"),
            (key: "BracketedSupport", value: config.bracketedPasteMode ? "on" : "off"),
            (key: "BracketedControlOnly", value: config.bracketedControlOnly ? "on" : "off"),
            (key: "AllowWrongSequence", value: config.allowWrongSequence ? "on" : "off"),
            (key: "MaxOSCBufferSize", value: String(config.maxOSCBufferSize)),
            (key: "EnableLineMode", value: config.enableLineMode ? "on" : "off"),
            // Copy/Paste
            (key: "MouseSelectStartDelay", value: String(config.mouseSelectStartDelay)),
            // Mouse
            (key: "TranslateWheelToCursor", value: config.translateWheelToCursor ? "on" : "off"),
            (key: "DisableWheelToCursorByCtrl", value: config.disableWheelToCursorByCtrl ? "on" : "off"),
            // Broadcast
            (key: "MaxBroadcatHistory", value: String(config.maxBroadcastHistory)),
            // Debug
            (key: "DebugModes", value: config.debugModes),
            // URL
            (key: "JoinSplitURL", value: config.joinSplitURL ? "on" : "off"),
            (key: "JoinSplitURLIgnoreEOLChar", value: config.joinSplitURLIgnoreEOLChar),
            // Unicode
            (key: "UnicodeEmojiOverride", value: config.unicodeEmojiOverride ? "on" : "off"),
            // Color
            (key: "PcBoldColor", value: config.pcBoldColor ? "on" : "off"),
            // File Transfer
            (key: "ZmodemAuto", value: config.zmodemAutoReceive ? "on" : "off"),
            (key: "ConfirmFileDragAndDrop", value: config.confirmFileDragAndDrop ? "on" : "off"),
            (key: "AutoFileRename", value: config.autoFileRename ? "on" : "off"),
            // Misc
            (key: "ClearScreenOnCloseConnection", value: config.clearScreenOnCloseConnection ? "on" : "off"),
            (key: "BackWrap", value: config.backWrap ? "on" : "off"),
            (key: "VTCompatTab", value: config.vtCompatTab ? "on" : "off"),
            (key: "FallbackToCP932", value: config.fallbackToCP932 ? "on" : "off"),
            (key: "SaveVTWinPos", value: config.saveVTWinPos ? "on" : "off"),
        ]))

        // [TCP/IP]
        sections.append(.init(name: "TCP/IP", pairs: [
            (key: "HostName",   value: config.hostName),
            (key: "TCPPort",    value: String(config.tcpPort)),
            (key: "Telnet",     value: config.telnet ? "on" : "off"),
            (key: "PortType",   value: String(config.portType)),
        ]))

        // [Serial]
        sections.append(.init(name: "Serial", pairs: [
            (key: "SerialPort",  value: config.serialPort),
            (key: "BaudRate",    value: String(config.baudRate)),
            (key: "DataBits",    value: String(config.dataBits)),
            (key: "Parity",      value: String(config.parity)),
            (key: "StopBits",    value: String(config.stopBits)),
            (key: "FlowControl", value: String(config.flowControl)),
        ]))

        return sections
    }

    /// Decode INI sections into a `TeraTermConfig`.
    func decode(sections: [INISerializer.Section]) -> TeraTermConfig {
        var c = TeraTermConfig()
        let get = { (sec: String, key: String) -> String? in
            INISerializer.getValue(from: sections, section: sec, key: key)
        }
        let main = Self.mainSection

        // Version
        c.version = get(main, Self.versionKey) ?? TeraTermConfig.currentVersion

        // Terminal
        if let v = get(main, "TerminalID")     { c.terminalID = v }
        if let v = get(main, "TerminalWidth"),  let n = Int(v) { c.terminalWidth = n }
        if let v = get(main, "TerminalHeight"), let n = Int(v) { c.terminalHeight = n }
        if let v = get(main, "Encoding")       { c.encoding = v }
        if let v = get(main, "LocalEcho")      { c.localEcho = (v == "on") }
        if let v = get(main, "AutoWrap")       { c.autoWrap = (v == "on") }
        if let v = get(main, "Answerback")     { c.answerback = v }

        // New-line
        if let v = get(main, "CRSend"),    let n = Int(v) { c.crSend = n }
        if let v = get(main, "CRReceive"), let n = Int(v) { c.crReceive = n }

        // Display
        if let v = get(main, "FontName")              { c.fontName = v }
        if let v = get(main, "FontSize"),  let n = Int(v) { c.fontSize = n }
        if let v = get(main, "VTColor")               { c.vtColor = v }
        if let v = get(main, "CursorShape"), let n = Int(v) { c.cursorShape = n }
        if let v = get(main, "CursorBlink")           { c.cursorBlink = (v == "on") }

        // Window
        if let v = get(main, "Title")                    { c.title = v }
        if let v = get(main, "WindowAlpha"), let n = Int(v) { c.windowAlpha = n }

        // Scroll
        if let v = get(main, "EnableScrollBuffer")            { c.enableScrollBuffer = (v == "on") }
        if let v = get(main, "ScrollBufferSize"), let n = Int(v) { c.scrollBufferSize = n }

        // Keyboard
        if let v = get(main, "BSKey"),     let n = Int(v) { c.bsKey = n }
        if let v = get(main, "DeleteKey"), let n = Int(v) { c.deleteKey = n }
        if let v = get(main, "MetaKey"),   let n = Int(v) { c.metaKey = n }

        // Beep
        if let v = get(main, "Beep"), let n = Int(v) { c.beep = n }

        // Log
        if let v = get(main, "LogAutoStart")   { c.logAutoStart = (v == "on") }
        if let v = get(main, "LogDefaultName") { c.logDefaultName = v }
        if let v = get(main, "LogTimestamp")   { c.logTimestamp = (v == "on") }

        // Mouse
        if let v = get(main, "MouseTracking") { c.mouseTracking = (v == "on") }

        // Misc
        if let v = get(main, "ConfirmOnDisconnect") { c.confirmOnDisconnect = (v == "on") }

        // Terminal extended
        if let v = get(main, "TerminalSpeed") { c.terminalSpeed = v }
        if let v = get(main, "KillFocusCursor") { c.killFocusCursor = (v == "on") }
        // Scroll extended
        if let v = get(main, "ScrollThreshold"), let n = Int(v) { c.scrollThreshold = n }
        if let v = get(main, "ScrollWindowClearScreen") { c.scrollWindowClearScreen = (v == "on") }
        // Beep extended
        if let v = get(main, "BeepOverUsedCount"), let n = Int(v) { c.beepOverUsedCount = n }
        if let v = get(main, "BeepOverUsedTime"), let n = Int(v) { c.beepOverUsedTime = n }
        if let v = get(main, "BeepSuppressTime"), let n = Int(v) { c.beepSuppressTime = n }
        // Connection
        if let v = get(main, "ConnectingTimeout"), let n = Int(v) { c.connectingTimeout = n }
        // Serial extended
        if let v = get(main, "ClearComBuffOnOpen") { c.clearComBuffOnOpen = (v == "on") }
        if let v = get(main, "AutoComPortReconnect") { c.autoComPortReconnect = (v == "on") }
        // Log extended
        if let v = get(main, "LogTimestampFormat") { c.logTimestampFormat = v }
        // Control sequences
        if let v = get(main, "Accept8BitCtrl") { c.accept8BitCtrl = (v == "on") }
        if let v = get(main, "Send8BitCtrl") { c.send8BitCtrl = (v == "on") }
        if let v = get(main, "AlternateScreenBuffer") { c.alternateScreenBuffer = (v == "on") }
        if let v = get(main, "BracketedSupport") { c.bracketedPasteMode = (v == "on") }
        if let v = get(main, "BracketedControlOnly") { c.bracketedControlOnly = (v == "on") }
        if let v = get(main, "AllowWrongSequence") { c.allowWrongSequence = (v == "on") }
        if let v = get(main, "MaxOSCBufferSize"), let n = Int(v) { c.maxOSCBufferSize = n }
        if let v = get(main, "EnableLineMode") { c.enableLineMode = (v == "on") }
        // Copy/Paste
        if let v = get(main, "MouseSelectStartDelay"), let n = Int(v) { c.mouseSelectStartDelay = n }
        // Mouse
        if let v = get(main, "TranslateWheelToCursor") { c.translateWheelToCursor = (v == "on") }
        if let v = get(main, "DisableWheelToCursorByCtrl") { c.disableWheelToCursorByCtrl = (v == "on") }
        // Broadcast
        if let v = get(main, "MaxBroadcatHistory"), let n = Int(v) { c.maxBroadcastHistory = n }
        // Debug
        if let v = get(main, "DebugModes") { c.debugModes = v }
        // URL
        if let v = get(main, "JoinSplitURL") { c.joinSplitURL = (v == "on") }
        if let v = get(main, "JoinSplitURLIgnoreEOLChar") { c.joinSplitURLIgnoreEOLChar = v }
        // Unicode
        if let v = get(main, "UnicodeEmojiOverride") { c.unicodeEmojiOverride = (v == "on") }
        // Color
        if let v = get(main, "PcBoldColor") { c.pcBoldColor = (v == "on") }
        // File Transfer
        if let v = get(main, "ZmodemAuto") { c.zmodemAutoReceive = (v == "on") }
        if let v = get(main, "ConfirmFileDragAndDrop") { c.confirmFileDragAndDrop = (v == "on") }
        if let v = get(main, "AutoFileRename") { c.autoFileRename = (v == "on") }
        // Misc
        if let v = get(main, "ClearScreenOnCloseConnection") { c.clearScreenOnCloseConnection = (v == "on") }
        if let v = get(main, "BackWrap") { c.backWrap = (v == "on") }
        if let v = get(main, "VTCompatTab") { c.vtCompatTab = (v == "on") }
        if let v = get(main, "FallbackToCP932") { c.fallbackToCP932 = (v == "on") }
        if let v = get(main, "SaveVTWinPos") { c.saveVTWinPos = (v == "on") }

        // [TCP/IP]
        if let v = get("TCP/IP", "HostName")             { c.hostName = v }
        if let v = get("TCP/IP", "TCPPort"),  let n = Int(v) { c.tcpPort = n }
        if let v = get("TCP/IP", "Telnet")               { c.telnet = (v == "on") }
        if let v = get("TCP/IP", "PortType"), let n = Int(v) { c.portType = n }

        // [Serial]
        if let v = get("Serial", "SerialPort")              { c.serialPort = v }
        if let v = get("Serial", "BaudRate"),    let n = Int(v) { c.baudRate = n }
        if let v = get("Serial", "DataBits"),    let n = Int(v) { c.dataBits = n }
        if let v = get("Serial", "Parity"),      let n = Int(v) { c.parity = n }
        if let v = get("Serial", "StopBits"),    let n = Int(v) { c.stopBits = n }
        if let v = get("Serial", "FlowControl"), let n = Int(v) { c.flowControl = n }

        return c
    }
}
