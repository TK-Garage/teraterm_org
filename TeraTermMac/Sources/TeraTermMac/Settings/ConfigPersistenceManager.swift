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

    // ── [Tera Term] Meta ──────────────────────────────────────
    var version: String = TeraTermConfig.currentVersion
    var port: String = "tcpip"   // "tcpip" / "serial"

    // ── Terminal Emulation ────────────────────────────────────
    var terminalID: String = "VT220"
    var terminalWidth: Int = 80
    var terminalHeight: Int = 24
    var termIsWin: Bool = false
    var autoWinResize: Bool = false
    var termType: String = "xterm"
    var answerback: String = ""
    var terminalUID: String = "FFFFFFFF"
    var terminalSpeed: String = "38400"

    // ── New-line ──────────────────────────────────────────────
    var crReceive: Int = 3   // 0=CR, 1=CRLF, 2=LF, 3=AUTO
    var crSend: Int = 0      // 0=CR, 1=CRLF, 2=LF

    // ── Character Encoding ────────────────────────────────────
    var encoding: String = "UTF-8"
    var sendEncoding: String = ""
    var katakanaReceive: String = "8"
    var katakanaSend: String = "8"
    var kanjiIn: String = "B"
    var kanjiOut: String = "J"

    // ── Local Echo ────────────────────────────────────────────
    var localEcho: Bool = false

    // ── Cursor ────────────────────────────────────────────────
    var cursorShape: Int = 0   // 0=block, 1=vertical, 2=horizontal
    var cursorBlink: Bool = true
    var killFocusCursor: Bool = true

    // ── Window Display ────────────────────────────────────────
    var title: String = "Tera Term"
    var titleFormat: Int = 13
    var saveVTWinPos: Bool = false

    // ── Scroll ────────────────────────────────────────────────
    var enableScrollBuffer: Bool = true
    var scrollBufferSize: Int = 10000
    var scrollBufferMax: Int = 500000
    var scrollThreshold: Int = 12
    var scrollWindowClearScreen: Bool = true

    // ── Color ─────────────────────────────────────────────────
    var vtColor: String = "255,255,255 0,0,0"
    var vtBoldColor: String = "0,0,255,255,255,255"
    var vtBlinkColor: String = "255,0,0,255,255,255"
    var vtReverseColor: String = "255,255,255,0,0,0"
    var vtUnderlineColor: String = "255,0,255,255,255,255"
    var urlColor: String = "0,255,0,255,255,255"
    var tekColor: String = "0,0,0,255,255,255"
    var ansiColor: String = ""
    var enableBoldColor: Bool = true
    var enableBlinkColor: Bool = true
    var enableReverseColor: Bool = false
    var enableURLColor: Bool = true
    var enableANSIColor: Bool = true
    var pcBoldColor: Bool = false
    var enableAixtermColors: Bool = false
    var enableXterm256Colors: Bool = true
    var useTextColor: Bool = false
    var useStandardBGColor: Bool = false
    var tekColorEmulation: Bool = false

    // ── Font ──────────────────────────────────────────────────
    var fontName: String = "Menlo"
    var fontSize: Int = 14
    var tekFont: String = ""
    var enableBoldFont: Bool = true
    var enableURLUnderline: Bool = true
    var enableUnderlineDecoration: Bool = true
    var enableUnderlineColor: Bool = true
    var vtFontSpace: String = "0,0,0,0"
    var fontQuality: String = "default"
    var fontScaling: Bool = false
    var drawingResizedFont: Bool = true
    var dialogFont: String = ""
    var drawingAPI: String = "Auto"
    var codePage: Int = 0

    // ── Keyboard ──────────────────────────────────────────────
    var bsKey: Int = 8
    var deleteKey: Int = 127
    var metaKey: Int = 0
    var meta8Bit: String = "off"
    var disableAppKeypad: Bool = false
    var disableAppCursor: Bool = false
    var strictKeyMapping: Bool = false
    var russKeyb: String = ""
    var cursorChangeIME: Bool = false

    // ── Beep ──────────────────────────────────────────────────
    var beep: Int = 1
    var beepOnConnect: Bool = false
    var beepOverUsedCount: Int = 5
    var beepOverUsedTime: Int = 2
    var beepSuppressTime: Int = 5
    var beepVBellWait: Int = 10
    var notifySound: Bool = true

    // ── Connection (TCP/IP) ───────────────────────────────────
    var hostName: String = ""
    var tcpPort: Int = 23
    var telnet: Bool = true
    var portType: Int = 0   // 0=TCP/IP, 1=Serial
    var autoWindowClose: Bool = true
    var hostHistory: Bool = false
    var connectingTimeout: Int = 0
    var telPort: Int = 23
    var telAutoDetect: Bool = true
    var telBin: Bool = false
    var telEcho: Bool = false
    var tcpKeepAliveInterval: Int = 300
    var tcpLocalEcho: Bool = false
    var tcpCRSend: String = ""
    var disableTCPEchoCR: Bool = false

    // ── Serial Port ───────────────────────────────────────────
    var serialPort: String = ""
    var baudRate: Int = 9600
    var dataBits: Int = 8
    var parity: Int = 0
    var stopBits: Int = 1
    var flowControl: Int = 0
    var serialDelayPerChar: Int = 0
    var serialDelayPerLine: Int = 0
    var clearComBuffOnOpen: Bool = true
    var waitCom: Bool = false
    var autoComPortReconnect: Bool = true
    var autoComPortReconnectDelayNormal: Int = 500
    var autoComPortReconnectDelayIllegal: Int = 2000
    var autoComPortReconnectRetryInterval: Int = 1000
    var autoComPortReconnectRetryCount: Int = 3

    // ── Log ───────────────────────────────────────────────────
    var logAutoStart: Bool = false
    var logDefaultName: String = "teraterm.log"
    var logDefaultPath: String = ""
    var logTimestamp: Bool = false
    var logTimestampFormat: String = "%Y-%m-%d %H:%M:%S.%N"
    var logTimestampType: String = "Local"
    var logPlainText: Bool = true
    var logBinary: Bool = false
    var logAppend: Bool = false
    var logHideDialog: Bool = false
    var logIncludeScreenBuffer: Bool = false
    var logRotateEnabled: Int = 0
    var logRotateSize: Int = 0
    var logRotateSizeType: Int = 0
    var logRotateStep: Int = 0
    var deferredLogWriteMode: Bool = true
    var logViewEditor: String = "open"
    var logEditorArguments: String = ""
    var logBOM: Bool = false

    // ── File Transfer ─────────────────────────────────────────
    var transBin: Bool = false
    var xmodemOption: String = "checksum"
    var xmodemBin: Bool = true
    var xModemRcvCommand: String = ""
    var yModemRcvCommand: String = "rb"
    var zmodemDataLen: Int = 1024
    var zmodemWindowSize: Int = 32767
    var zModemRcvCommand: String = "rz"
    var zmodemAutoReceive: Bool = false
    var zmodemEscCtl: Bool = false
    var fileTransferFolder: String = ""
    var fileSendFilter: String = ""
    var scpSendDir: String = ""
    var ftHideDialog: Bool = false
    var autoFileRename: Bool = false
    var confirmFileDragAndDrop: Bool = true

    // ── XMODEM/YMODEM/ZMODEM Timeouts ─────────────────────────
    var xmodemTimeouts: String = "10,3,10,20,60"
    var ymodemTimeouts: String = "10,3,10,20,60"
    var zmodemTimeouts: String = "10,0,10,3"

    // ── Control Sequences ─────────────────────────────────────
    var accept8BitCtrl: Bool = true
    var allowWrongSequence: Bool = false
    var titleChangeRequest: String = "overwrite"
    var windowControlSequence: Bool = true
    var cursorControlSequence: Bool = false
    var windowInfoReportSequence: Bool = true
    var titleReportRequest: String = "Empty"
    var clipboardAccessFromRemote: String = "off"
    var notifyClipboardAccess: Bool = true
    var acceptScrollBufferClear: Bool = true
    var clearOnResize: Bool = false
    var alternateScreenBuffer: Bool = true
    var enableStatusLine: Bool = true
    var enableLineMode: Bool = true
    var disablePrintSequence: Bool = false
    var useInvalidDECRQSSResponse: Bool = false
    var tabStopModifySequence: String = "on"
    var iso2022ShiftFunction: String = "on"
    var maxOSCBufferSize: Int = 4096
    var send8BitCtrl: Bool = false

    // ── Copy & Paste ──────────────────────────────────────────
    var autoTextCopy: Bool = true
    var continuedLineCopy: Bool = true
    var leftClickOnlySelection: Bool = true
    var enableSelectionOnActivate: Bool = true
    var disableRightClickPaste: Bool = false
    var disableMiddleClickPaste: Bool = true
    var confirmRightClickPaste: Bool = false
    var clipboardConfirmPaste: Bool = true
    var confirmPasteNewLine: Bool = true
    var dangerousKeywordFile: String = ""
    var trimTrailingNewline: Bool = false
    var pasteDelay: Int = 5
    var delimiterList: String = ""
    var delimDBCS: Bool = true
    var mouseSelectStartDelay: Int = 0

    // ── Mouse ─────────────────────────────────────────────────
    var mouseTracking: Bool = true
    var mouseWheelScrollLines: Int = 3
    var mouseCursorType: String = "IBEAM"
    var translateWheelToCursor: Bool = true
    var disableControlKeyMouseEvent: Bool = true
    var disableWheelToCursorByCtrl: Bool = true

    // ── Window Opacity ────────────────────────────────────────
    var windowOpacityInactive: Int = 255
    var windowOpacityActive: Int = 255

    // ── Broadcast ─────────────────────────────────────────────
    var broadcastHistory: Bool = false
    var acceptBroadcast: Bool = true
    var maxBroadcastHistory: Int = 99

    // ── Debug ─────────────────────────────────────────────────
    var debugCharInfoPopup: Bool = false
    var debugModes: String = "all"

    // ── URL ───────────────────────────────────────────────────
    var enableClickableUrl: Bool = false
    var joinSplitURL: Bool = false
    var joinSplitURLIgnoreEOLChar: String = "\\\\"

    // ── Unicode ───────────────────────────────────────────────
    var unicodeAmbiguousWidth: Int = 0
    var unicodeEmojiOverride: Bool = false
    var unicodeEmojiWidth: Int = 0
    var unicodeToDecSpMapping: Int = 3
    var decSpMappingDir: Int = 2

    // ── Sendfile ──────────────────────────────────────────────
    var sendfileDelayType: String = "NoDelay"
    var sendfileDelayTick: Int = 0
    var sendfileSize: Int = 4096
    var sendfileSequential: Bool = false
    var sendfileSkipOptionDialog: Bool = false

    // ── Receivefile ───────────────────────────────────────────
    var fileReceiveFilter: String = ""
    var receivefileSkipOptionDialog: Bool = false
    var receivefileAutoStopWaitTime: Int = 5

    // ── UI Language ───────────────────────────────────────────
    var language: String = ""

    // ── Protocol Logs ─────────────────────────────────────────
    var telLog: Bool = false
    var xmodemLog: Bool = false
    var ymodemLog: Bool = false
    var zmodemLog: Bool = false

    // ── Kermit ────────────────────────────────────────────────
    var kmtLog: Bool = false
    var kmtLongPacket: Bool = false
    var kmtFileAttr: Bool = false

    // ── B-Plus ────────────────────────────────────────────────
    var bpAuto: Bool = false
    var bpEscCtl: Bool = false
    var bpLog: Bool = false

    // ── Quick-VAN ─────────────────────────────────────────────
    var qvLog: Bool = false
    var qvWinSize: Int = 8

    // ── Other Special Options ─────────────────────────────────
    var autoWinSwitch: Bool = false
    var ctrlInKanji: Bool = true
    var fixedJIS: Bool = false
    var backWrap: Bool = false
    var autoInvoke: Bool = false
    var confirmOnDisconnect: Bool = true
    var vtCompatTab: Bool = false
    var tekIcon: String = "Default"
    var tekGINMouseCode: Int = 32
    var sendBreakTime: Int = 1000
    var wait4allMacroCommand: Bool = false
    var clearScreenOnCloseConnection: Bool = false
    var fileSendHighSpeedMode: Bool = true
    var fallbackToCP932: Bool = false
    var startupMacro: String = ""
    var autoScrollOnlyInBottomLine: Bool = false
    var lockTUID: Bool = true
    var cornerRounding: Bool = false
    var iniAutoBackup: Bool = true
    var bracketedPasteMode: Bool = true
    var bracketedControlOnly: Bool = false

    // ── TEK ───────────────────────────────────────────────────
    var tekPos: String = "-2147483648,-2147483648"
    var tekPPI: String = "0,0"

    // ── [BG] Theme ────────────────────────────────────────────
    var bgEnable: Int = 0
    var bgThemeFile: String = ""
    var bgSPIPath: String = ""
    var bgFastSizeMove: Int = 0
    var bgNoFrame: Int = 0

    // ── [TTSSH] SSH ───────────────────────────────────────────
    var sshVersion: Int = 2
    var sshDefaultAuthMethod: Int = 0
    var sshDefaultUserName: String = ""
    var sshDefaultUserNameMode: Int = 0
    var sshDefaultForwarding: String = ""
    var sshHeartBeat: Int = 60
    var sshForwardAgent: Bool = false
    var sshConfirmForwardAgent: Bool = true
    var sshNotifyForwardAgent: Bool = false
    var sshVerifyHostKeyDNS: Bool = false
    var sshKnownHostsFile: String = ""
    var sshKnownHostsReadOnlyFile: String = ""
    var sshHostKeyRotation: Int = 0
    var sshLogLevel: Int = 0
    var sshCompressionLevel: Int = 0
    var sshXForwarding: Bool = false
    var sshCheckAuthBeforeLogin: Bool = false
    var sshCipherOrder: String = ""
    var sshKexOrder: String = ""
    var sshHostKeyOrder: String = ""
    var sshMACOrder: String = ""
    var sshCompOrder: String = ""

    // ── [Proxy] ───────────────────────────────────────────────
    var proxyType: Int = 0
    var proxyHost: String = ""
    var proxyPort: Int = 0
    var proxyUser: String = ""
    var proxyPass: String = ""

    // ── Legacy compat (kept for encode/decode) ────────────────
    var autoWrap: Bool = true
}

// MARK: - ConfigPersistenceManager

/// Manages the lifecycle of `TERATERM.INI` under Application Support.
///
/// Responsibilities:
/// - Creates the app-specific directory on first use.
/// - Checks format version; deletes and recreates stale files.
/// - Provides atomic writes to prevent corruption.
class ConfigPersistenceManager {

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
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
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

        // Read existing file with auto-detection of character encoding.
        // Try UTF-8 first (Mac standard), then Shift_JIS / EUC-JP / Latin-1
        // for compatibility with Windows-originated TERATERM.INI files.
        guard let data = fm.contents(atPath: path.path),
              let text = Self.decodeText(data) else {
            // Unreadable – recreate
            print("Old configuration format detected. Recreating...")
            try? fm.removeItem(at: path)
            let config = TeraTermConfig()
            saveConfig(config)
            return config
        }

        let (rawSections, _) = INISerializer.parse(text)

        // Filter out unknown / unsupported keys from original Tera Term INI.
        // Each unrecognised line is silently skipped and parsing continues
        // with the next line.
        let (sections, skipped) = filterUnknownKeys(rawSections)
        for entry in skipped {
            print("ConfigPersistenceManager: Skipping unknown key " +
                  "[\(entry.section)] \(entry.key)=\(entry.value)")
        }

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

    // MARK: - Encoding Auto-Detection

    /// Decode raw bytes into a String, trying multiple encodings.
    /// Order: UTF-8 (with/without BOM) → Shift_JIS (CP932) → EUC-JP → ISO Latin-1.
    /// Line endings (CRLF / LF / CR) are handled transparently by INISerializer.
    static func decodeText(_ data: Data) -> String? {
        // Strip UTF-8 BOM if present
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let stripped: Data
        if data.count >= 3, Array(data.prefix(3)) == bom {
            stripped = data.dropFirst(3)
        } else {
            stripped = data
        }

        // Try UTF-8 first (Mac standard)
        if let text = String(data: stripped, encoding: .utf8) {
            return text
        }

        // Try Shift_JIS (Windows Japanese default, CP932)
        if let text = String(data: stripped, encoding: .shiftJIS) {
            return text
        }

        // Try EUC-JP
        if let text = String(data: stripped, encoding: .japaneseEUC) {
            return text
        }

        // Fallback: ISO Latin-1 (always succeeds for any byte sequence)
        return String(data: stripped, encoding: .isoLatin1)
    }

    // MARK: - Save

    /// Write configuration to `TERATERM.INI` atomically.
    /// Saves as UTF-8 with LF line endings (macOS standard).
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

    // MARK: - Helpers

    private func onOff(_ b: Bool) -> String { b ? "on" : "off" }

    // MARK: - Known Keys Registry

    /// Set of known INI key names per section (case-insensitive comparison).
    /// Keys not in this registry are from the original Windows Tera Term
    /// or are otherwise unsupported, and will be silently skipped.
    static let knownKeys: [String: Set<String>] = {
        var map: [String: Set<String>] = [:]

        map["Tera Term"] = [
            "Version", "Port",
            // Terminal Emulation
            "TerminalID", "TerminalWidth", "TerminalHeight",
            "TermIsWin", "AutoWinResize", "TermType", "Answerback",
            "TerminalUID", "TerminalSpeed",
            // New-line
            "CRReceive", "CRSend",
            // Character Encoding
            "Encoding", "KanjiSend", "KatakanaReceive", "KatakanaSend",
            "KanjiIn", "KanjiOut",
            // Local Echo
            "LocalEcho",
            // Cursor
            "CursorShape", "CursorBlink", "KillFocusCursor",
            // Window Display
            "Title", "TitleFormat", "SaveVTWinPos",
            // Scroll
            "EnableScrollBuffer", "ScrollBuffSize", "MaxBuffSize",
            "ScrollThreshold", "ScrollWindowClearScreen",
            // Color
            "VTColor", "VTBoldColor", "VTBlinkColor", "VTReverseColor",
            "VTUnderlineColor", "URLColor", "TEKColor", "ANSIColor",
            "EnableBoldAttrColor", "EnableBlinkAttrColor",
            "EnableReverseAttrColor", "EnableURLColor", "EnableANSIColor",
            "PcBoldColor", "Aixterm16Color", "Xterm256Color",
            "UseTextColor", "UseNormalBGColor", "TEKColorEmulation",
            // Font
            "FontName", "FontSize", "TEKFont", "EnableBold",
            "URLUnderline", "UnderlineAttrFont", "UnderlineAttrColor",
            "VTFontSpace", "FontQuality", "FontScaling",
            "DrawingResizedFont", "DlgFont", "VTDrawAPI", "VTDrawACP",
            // Keyboard
            "BSKey", "DeleteKey", "MetaKey", "Meta8Bit",
            "DisableAppKeypad", "DisableAppCursor", "StrictKeyMapping",
            "RussKeyb", "IMERelatedCursor",
            // Beep
            "Beep", "BeepOnConnect", "BeepOverUsedCount",
            "BeepOverUsedTime", "BeepSuppressTime", "BeepVBellWait",
            "NotifySound",
            // Connection
            "Telnet", "TCPPort", "TelPort", "AutoWinClose",
            "HistoryList", "ConnectingTimeout", "TelAutoDetect",
            "TelBin", "TelEcho", "TelKeepAliveInterval",
            "TCPLocalEcho", "TCPCRSend", "DisableTCPEchoCR",
            // Serial
            "DelayPerChar", "DelayPerLine", "ClearComBuffOnOpen",
            "WaitCom", "AutoComPortReconnect",
            "AutoComPortReconnectDelayNormal",
            "AutoComPortReconnectDelayIllegal",
            "AutoComPortReconnectRetryInterval",
            "AutoComPortReconnectRetryCount",
            // Log
            "LogAutoStart", "LogDefaultName", "LogDefaultPath",
            "LogTimestamp", "LogTimestampFormat", "LogTimestampType",
            "LogTypePlainText", "LogBinary", "LogAppend",
            "LogHideDialog", "LogIncludeScreenBuffer",
            "LogRotate", "LogRotateSize", "LogRotateSizeType",
            "LogRotateStep", "DeferredLogWriteMode",
            "ViewlogEditor", "ViewlogEditorArg", "LogBOM",
            // File Transfer
            "TransBin", "XmodemOpt", "XmodemBin",
            "XModemRcvCommand", "YModemRcvCommand",
            "ZmodemDataLen", "ZmodemWinSize", "ZModemRcvCommand",
            "ZmodemAuto", "ZmodemEscCtl",
            "FileDir", "FileSendFilter", "ScpSendDir",
            "FTHideDialog", "AutoFileRename", "ConfirmFileDragAndDrop",
            // Timeouts
            "XmodemTimeouts", "YmodemTimeouts", "ZmodemTimeouts",
            // Control Sequences
            "Accept8BitCtrl", "AllowWrongSequence",
            "AcceptTitleChangeRequest", "WindowCtrlSequence",
            "CursorCtrlSequence", "WindowReportSequence",
            "TitleReportSequence", "ClipboardAccessFromRemote",
            "NotifyClipboardAccess", "ClearScrollBufferFromRemote",
            "ClearOnResize", "AlternateScreenBuffer",
            "EnableStatusLine", "EnableLineMode",
            "PrinterCtrlSequence", "UseInvalidDECRQSSResponse",
            "TabStopModifySequence", "ISO2022ShiftFunction",
            "MaxOSCBufferSize", "Send8BitCtrl",
            // Copy & Paste
            "AutoTextCopy", "EnableContinuedLineCopy",
            "SelectOnlyByLButton", "SelectOnActivate",
            "DisablePasteMouseRButton", "DisablePasteMouseMButton",
            "ConfirmPasteMouseRButton", "ConfirmChangePaste",
            "ConfirmChangePasteCR", "ConfirmChangePasteStringFile",
            "TrimTrailingNLonPaste", "PasteDelayPerLine",
            "DelimList", "DelimDBCS", "MouseSelectStartDelay",
            // Mouse
            "MouseEventTracking", "MouseWheelScrollLine", "MouseCursor",
            "TranslateWheelToCursor", "DisableMouseTrackingByCtrl",
            "DisableWheelToCursorByCtrl",
            // Window Opacity
            "AlphaBlend", "AlphaBlendActive",
            // Broadcast
            "BroadcastCommandHistory", "AcceptBroadcast",
            "MaxBroadcatHistory",
            // Debug
            "Debug", "DebugModes",
            // URL
            "EnableClickableUrl", "JoinSplitURL",
            "JoinSplitURLIgnoreEOLChar",
            // Unicode
            "UnicodeAmbiguousWidth", "UnicodeEmojiOverride",
            "UnicodeEmojiWidth", "UnicodeToDecSpMapping",
            "DecSpMappingDir",
            // Sendfile
            "SendfileDelayType", "SendfileDelayTick", "SendfileSize",
            "SendfileSequential", "SendfileSkipOptionDialog",
            // Receivefile
            "FileReceiveFilter", "ReceivefileSkipOptionDialog",
            "ReceivefileAutoStopWaitTime",
            // UI Language
            "UILanguageFile",
            // Protocol Logs
            "TelLog", "XmodemLog", "YmodemLog", "ZmodemLog",
            // Kermit
            "KmtLog", "KmtLongPacket", "KmtFileAttr",
            // B-Plus
            "BPAuto", "BPEscCtl", "BPLog",
            // Quick-VAN
            "QVLog", "QVWinSize",
            // Other Special Options
            "AutoWinSwitch", "CtrlInKanji", "FixedJIS", "BackWrap",
            "AutoInvoke", "ConfirmDisconnect", "VTCompatTab",
            "TEKIcon", "TEKGINMouseCode", "SendBreakTime",
            "Wait4allMacroCommand", "ClearScreenOnCloseConnection",
            "FileSendHighSpeedMode", "FallbackToCP932",
            "StartupMacro", "AutoScrollOnlyInBottomLine",
            "LockTUID", "WindowCornerDontround", "IniAutoBackup",
            "BracketedSupport", "BracketedControlOnly", "AutoWrap",
            // TEK
            "TEKPos", "TEKPPI",
        ]

        map["TCP/IP"] = [
            "HostName", "TCPPort", "Telnet", "PortType",
        ]

        map["Serial"] = [
            "SerialPort", "BaudRate", "DataBits", "Parity",
            "StopBits", "FlowControl",
        ]

        map["BG"] = [
            "BGEnable", "BGThemeFile", "BGSPIPath",
            "BGFastSizeMove", "BGNoFrame",
        ]

        map["TTSSH"] = [
            "SSHVersion", "DefaultAuthMethod", "DefaultUserName",
            "DefaultUserNameMode", "DefaultForwarding",
            "HeartBeat", "ForwardAgent", "ConfirmForwardAgent",
            "NotifyForwardAgent", "VerifyHostKeyDNS",
            "KnownHostsFile", "KnownHostsReadOnlyFile",
            "HostKeyRotation", "LogLevel", "CompressionLevel",
            "XForwarding", "CheckAuthBeforeLogin",
            "CipherOrder", "KexOrder", "HostKeyOrder",
            "MACOrder", "CompOrder",
        ]

        map["Proxy"] = [
            "ProxyType", "ProxyHost", "ProxyPort",
            "ProxyUser", "ProxyPass",
        ]

        return map
    }()

    // MARK: - Unknown / Invalid Key Filtering

    /// Filter parsed INI sections, removing keys that are not in the
    /// known-keys registry.  Returns the filtered sections and a list
    /// of skipped entries for diagnostics.
    func filterUnknownKeys(
        _ sections: [INISerializer.Section]
    ) -> (filtered: [INISerializer.Section], skipped: [(section: String, key: String, value: String)]) {
        var filtered: [INISerializer.Section] = []
        var skipped: [(section: String, key: String, value: String)] = []

        for section in sections {
            let knownSet = Self.knownKeys[section.name]
            var validPairs: [(key: String, value: String)] = []

            for pair in section.pairs {
                if let known = knownSet,
                   known.contains(where: { $0.caseInsensitiveCompare(pair.key) == .orderedSame }) {
                    validPairs.append(pair)
                } else if knownSet == nil {
                    // Unknown section entirely – skip all its keys
                    skipped.append((section: section.name, key: pair.key, value: pair.value))
                } else {
                    // Known section but unknown key
                    skipped.append((section: section.name, key: pair.key, value: pair.value))
                }
            }

            filtered.append(.init(name: section.name, pairs: validPairs))
        }

        return (filtered, skipped)
    }

    // MARK: - Encode

    /// Build INI sections from a `TeraTermConfig`.
    func encode(_ config: TeraTermConfig) -> [INISerializer.Section] {
        var sections: [INISerializer.Section] = []

        // ── [Tera Term] ──────────────────────────────────────
        // Build pairs in smaller chunks to help the Swift type-checker.
        typealias P = (key: String, value: String)

        // Meta & Terminal Emulation
        var mainPairs: [P] = [
            (key: Self.versionKey,     value: config.version),
            (key: "Port",              value: config.port),
            (key: "TerminalID",        value: config.terminalID),
            (key: "TerminalWidth",     value: String(config.terminalWidth)),
            (key: "TerminalHeight",    value: String(config.terminalHeight)),
            (key: "TermIsWin",         value: onOff(config.termIsWin)),
            (key: "AutoWinResize",     value: onOff(config.autoWinResize)),
            (key: "TermType",          value: config.termType),
            (key: "Answerback",        value: config.answerback),
            (key: "TerminalUID",       value: config.terminalUID),
            (key: "TerminalSpeed",     value: config.terminalSpeed),
            (key: "CRReceive",         value: String(config.crReceive)),
            (key: "CRSend",            value: String(config.crSend)),
            (key: "Encoding",          value: config.encoding),
            (key: "KanjiSend",         value: config.sendEncoding),
            (key: "KatakanaReceive",   value: config.katakanaReceive),
            (key: "KatakanaSend",      value: config.katakanaSend),
            (key: "KanjiIn",           value: config.kanjiIn),
            (key: "KanjiOut",          value: config.kanjiOut),
            (key: "LocalEcho",         value: onOff(config.localEcho)),
        ]

        // Cursor, Window, Scroll, Color
        mainPairs += [
            (key: "CursorShape",       value: String(config.cursorShape)),
            (key: "CursorBlink",       value: onOff(config.cursorBlink)),
            (key: "KillFocusCursor",   value: onOff(config.killFocusCursor)),
            (key: "Title",             value: config.title),
            (key: "TitleFormat",       value: String(config.titleFormat)),
            (key: "SaveVTWinPos",      value: onOff(config.saveVTWinPos)),
            (key: "EnableScrollBuffer",    value: onOff(config.enableScrollBuffer)),
            (key: "ScrollBuffSize",        value: String(config.scrollBufferSize)),
            (key: "MaxBuffSize",           value: String(config.scrollBufferMax)),
            (key: "ScrollThreshold",       value: String(config.scrollThreshold)),
            (key: "ScrollWindowClearScreen", value: onOff(config.scrollWindowClearScreen)),
            (key: "VTColor",           value: config.vtColor),
            (key: "VTBoldColor",       value: config.vtBoldColor),
            (key: "VTBlinkColor",      value: config.vtBlinkColor),
            (key: "VTReverseColor",    value: config.vtReverseColor),
            (key: "VTUnderlineColor",  value: config.vtUnderlineColor),
            (key: "URLColor",          value: config.urlColor),
            (key: "TEKColor",          value: config.tekColor),
            (key: "ANSIColor",         value: config.ansiColor),
            (key: "EnableBoldAttrColor",   value: onOff(config.enableBoldColor)),
            (key: "EnableBlinkAttrColor",  value: onOff(config.enableBlinkColor)),
            (key: "EnableReverseAttrColor", value: onOff(config.enableReverseColor)),
            (key: "EnableURLColor",    value: onOff(config.enableURLColor)),
            (key: "EnableANSIColor",   value: onOff(config.enableANSIColor)),
            (key: "PcBoldColor",       value: onOff(config.pcBoldColor)),
            (key: "Aixterm16Color",    value: onOff(config.enableAixtermColors)),
            (key: "Xterm256Color",     value: onOff(config.enableXterm256Colors)),
            (key: "UseTextColor",      value: onOff(config.useTextColor)),
            (key: "UseNormalBGColor",  value: onOff(config.useStandardBGColor)),
            (key: "TEKColorEmulation", value: onOff(config.tekColorEmulation)),
        ]

        // Font, Keyboard, Beep
        mainPairs += [
            (key: "FontName",          value: config.fontName),
            (key: "FontSize",          value: String(config.fontSize)),
            (key: "TEKFont",           value: config.tekFont),
            (key: "EnableBold",        value: onOff(config.enableBoldFont)),
            (key: "URLUnderline",      value: onOff(config.enableURLUnderline)),
            (key: "UnderlineAttrFont", value: onOff(config.enableUnderlineDecoration)),
            (key: "UnderlineAttrColor", value: onOff(config.enableUnderlineColor)),
            (key: "VTFontSpace",       value: config.vtFontSpace),
            (key: "FontQuality",       value: config.fontQuality),
            (key: "FontScaling",       value: onOff(config.fontScaling)),
            (key: "DrawingResizedFont", value: onOff(config.drawingResizedFont)),
            (key: "DlgFont",           value: config.dialogFont),
            (key: "VTDrawAPI",         value: config.drawingAPI),
            (key: "VTDrawACP",         value: String(config.codePage)),
            (key: "BSKey",             value: String(config.bsKey)),
            (key: "DeleteKey",         value: String(config.deleteKey)),
            (key: "MetaKey",           value: String(config.metaKey)),
            (key: "Meta8Bit",          value: config.meta8Bit),
            (key: "DisableAppKeypad",  value: onOff(config.disableAppKeypad)),
            (key: "DisableAppCursor",  value: onOff(config.disableAppCursor)),
            (key: "StrictKeyMapping",  value: onOff(config.strictKeyMapping)),
            (key: "RussKeyb",          value: config.russKeyb),
            (key: "IMERelatedCursor",  value: onOff(config.cursorChangeIME)),
            (key: "Beep",              value: String(config.beep)),
            (key: "BeepOnConnect",     value: onOff(config.beepOnConnect)),
            (key: "BeepOverUsedCount", value: String(config.beepOverUsedCount)),
            (key: "BeepOverUsedTime",  value: String(config.beepOverUsedTime)),
            (key: "BeepSuppressTime",  value: String(config.beepSuppressTime)),
            (key: "BeepVBellWait",     value: String(config.beepVBellWait)),
            (key: "NotifySound",       value: onOff(config.notifySound)),
        ]

        // Connection, Serial
        mainPairs += [
            (key: "Telnet",            value: onOff(config.telnet)),
            (key: "TCPPort",           value: String(config.tcpPort)),
            (key: "TelPort",           value: String(config.telPort)),
            (key: "AutoWinClose",      value: onOff(config.autoWindowClose)),
            (key: "HistoryList",       value: onOff(config.hostHistory)),
            (key: "ConnectingTimeout", value: String(config.connectingTimeout)),
            (key: "TelAutoDetect",     value: onOff(config.telAutoDetect)),
            (key: "TelBin",            value: onOff(config.telBin)),
            (key: "TelEcho",           value: onOff(config.telEcho)),
            (key: "TelKeepAliveInterval", value: String(config.tcpKeepAliveInterval)),
            (key: "TCPLocalEcho",      value: onOff(config.tcpLocalEcho)),
            (key: "TCPCRSend",         value: config.tcpCRSend),
            (key: "DisableTCPEchoCR",  value: onOff(config.disableTCPEchoCR)),
            (key: "DelayPerChar",      value: String(config.serialDelayPerChar)),
            (key: "DelayPerLine",      value: String(config.serialDelayPerLine)),
            (key: "ClearComBuffOnOpen", value: onOff(config.clearComBuffOnOpen)),
            (key: "WaitCom",           value: onOff(config.waitCom)),
            (key: "AutoComPortReconnect", value: onOff(config.autoComPortReconnect)),
            (key: "AutoComPortReconnectDelayNormal",   value: String(config.autoComPortReconnectDelayNormal)),
            (key: "AutoComPortReconnectDelayIllegal",  value: String(config.autoComPortReconnectDelayIllegal)),
            (key: "AutoComPortReconnectRetryInterval", value: String(config.autoComPortReconnectRetryInterval)),
            (key: "AutoComPortReconnectRetryCount",    value: String(config.autoComPortReconnectRetryCount)),
        ]

        // Log
        mainPairs += [
            (key: "LogAutoStart",      value: onOff(config.logAutoStart)),
            (key: "LogDefaultName",    value: config.logDefaultName),
            (key: "LogDefaultPath",    value: config.logDefaultPath),
            (key: "LogTimestamp",      value: onOff(config.logTimestamp)),
            (key: "LogTimestampFormat", value: config.logTimestampFormat),
            (key: "LogTimestampType",  value: config.logTimestampType),
            (key: "LogTypePlainText",  value: onOff(config.logPlainText)),
            (key: "LogBinary",         value: onOff(config.logBinary)),
            (key: "LogAppend",         value: onOff(config.logAppend)),
            (key: "LogHideDialog",     value: onOff(config.logHideDialog)),
            (key: "LogIncludeScreenBuffer", value: onOff(config.logIncludeScreenBuffer)),
            (key: "LogRotate",         value: String(config.logRotateEnabled)),
            (key: "LogRotateSize",     value: String(config.logRotateSize)),
            (key: "LogRotateSizeType", value: String(config.logRotateSizeType)),
            (key: "LogRotateStep",     value: String(config.logRotateStep)),
            (key: "DeferredLogWriteMode", value: onOff(config.deferredLogWriteMode)),
            (key: "ViewlogEditor",     value: config.logViewEditor),
            (key: "ViewlogEditorArg",  value: config.logEditorArguments),
            (key: "LogBOM",            value: onOff(config.logBOM)),
        ]

        // File Transfer, Timeouts
        mainPairs += [
            (key: "TransBin",          value: onOff(config.transBin)),
            (key: "XmodemOpt",         value: config.xmodemOption),
            (key: "XmodemBin",         value: onOff(config.xmodemBin)),
            (key: "XModemRcvCommand",  value: config.xModemRcvCommand),
            (key: "YModemRcvCommand",  value: config.yModemRcvCommand),
            (key: "ZmodemDataLen",     value: String(config.zmodemDataLen)),
            (key: "ZmodemWinSize",     value: String(config.zmodemWindowSize)),
            (key: "ZModemRcvCommand",  value: config.zModemRcvCommand),
            (key: "ZmodemAuto",        value: onOff(config.zmodemAutoReceive)),
            (key: "ZmodemEscCtl",      value: onOff(config.zmodemEscCtl)),
            (key: "FileDir",           value: config.fileTransferFolder),
            (key: "FileSendFilter",    value: config.fileSendFilter),
            (key: "ScpSendDir",        value: config.scpSendDir),
            (key: "FTHideDialog",      value: onOff(config.ftHideDialog)),
            (key: "AutoFileRename",    value: onOff(config.autoFileRename)),
            (key: "ConfirmFileDragAndDrop", value: onOff(config.confirmFileDragAndDrop)),
            (key: "XmodemTimeouts",    value: config.xmodemTimeouts),
            (key: "YmodemTimeouts",    value: config.ymodemTimeouts),
            (key: "ZmodemTimeouts",    value: config.zmodemTimeouts),
        ]

        // Control Sequences
        mainPairs += [
            (key: "Accept8BitCtrl",    value: onOff(config.accept8BitCtrl)),
            (key: "AllowWrongSequence", value: onOff(config.allowWrongSequence)),
            (key: "AcceptTitleChangeRequest", value: config.titleChangeRequest),
            (key: "WindowCtrlSequence", value: onOff(config.windowControlSequence)),
            (key: "CursorCtrlSequence", value: onOff(config.cursorControlSequence)),
            (key: "WindowReportSequence", value: onOff(config.windowInfoReportSequence)),
            (key: "TitleReportSequence", value: config.titleReportRequest),
            (key: "ClipboardAccessFromRemote", value: config.clipboardAccessFromRemote),
            (key: "NotifyClipboardAccess", value: onOff(config.notifyClipboardAccess)),
            (key: "ClearScrollBufferFromRemote", value: onOff(config.acceptScrollBufferClear)),
            (key: "ClearOnResize",     value: onOff(config.clearOnResize)),
            (key: "AlternateScreenBuffer", value: onOff(config.alternateScreenBuffer)),
            (key: "EnableStatusLine",  value: onOff(config.enableStatusLine)),
            (key: "EnableLineMode",    value: onOff(config.enableLineMode)),
            (key: "PrinterCtrlSequence", value: onOff(!config.disablePrintSequence)),
            (key: "UseInvalidDECRQSSResponse", value: onOff(config.useInvalidDECRQSSResponse)),
            (key: "TabStopModifySequence", value: config.tabStopModifySequence),
            (key: "ISO2022ShiftFunction", value: config.iso2022ShiftFunction),
            (key: "MaxOSCBufferSize",  value: String(config.maxOSCBufferSize)),
            (key: "Send8BitCtrl",      value: onOff(config.send8BitCtrl)),
        ]

        // Copy & Paste, Mouse, Opacity, Broadcast, Debug, URL, Unicode
        mainPairs += [
            (key: "AutoTextCopy",      value: onOff(config.autoTextCopy)),
            (key: "EnableContinuedLineCopy", value: onOff(config.continuedLineCopy)),
            (key: "SelectOnlyByLButton", value: onOff(config.leftClickOnlySelection)),
            (key: "SelectOnActivate",  value: onOff(config.enableSelectionOnActivate)),
            (key: "DisablePasteMouseRButton", value: onOff(config.disableRightClickPaste)),
            (key: "DisablePasteMouseMButton", value: onOff(config.disableMiddleClickPaste)),
            (key: "ConfirmPasteMouseRButton", value: onOff(config.confirmRightClickPaste)),
            (key: "ConfirmChangePaste", value: onOff(config.clipboardConfirmPaste)),
            (key: "ConfirmChangePasteCR", value: onOff(config.confirmPasteNewLine)),
            (key: "ConfirmChangePasteStringFile", value: config.dangerousKeywordFile),
            (key: "TrimTrailingNLonPaste", value: onOff(config.trimTrailingNewline)),
            (key: "PasteDelayPerLine", value: String(config.pasteDelay)),
            (key: "DelimList",         value: config.delimiterList),
            (key: "DelimDBCS",         value: onOff(config.delimDBCS)),
            (key: "MouseSelectStartDelay", value: String(config.mouseSelectStartDelay)),
            (key: "MouseEventTracking", value: onOff(config.mouseTracking)),
            (key: "MouseWheelScrollLine", value: String(config.mouseWheelScrollLines)),
            (key: "MouseCursor",       value: config.mouseCursorType),
            (key: "TranslateWheelToCursor", value: onOff(config.translateWheelToCursor)),
            (key: "DisableMouseTrackingByCtrl", value: onOff(config.disableControlKeyMouseEvent)),
            (key: "DisableWheelToCursorByCtrl", value: onOff(config.disableWheelToCursorByCtrl)),
            (key: "AlphaBlend",        value: String(config.windowOpacityInactive)),
            (key: "AlphaBlendActive",  value: String(config.windowOpacityActive)),
            (key: "BroadcastCommandHistory", value: onOff(config.broadcastHistory)),
            (key: "AcceptBroadcast",   value: onOff(config.acceptBroadcast)),
            (key: "MaxBroadcatHistory", value: String(config.maxBroadcastHistory)),
            (key: "Debug",             value: onOff(config.debugCharInfoPopup)),
            (key: "DebugModes",        value: config.debugModes),
            (key: "EnableClickableUrl", value: onOff(config.enableClickableUrl)),
            (key: "JoinSplitURL",      value: onOff(config.joinSplitURL)),
            (key: "JoinSplitURLIgnoreEOLChar", value: config.joinSplitURLIgnoreEOLChar),
            (key: "UnicodeAmbiguousWidth", value: String(config.unicodeAmbiguousWidth)),
            (key: "UnicodeEmojiOverride", value: onOff(config.unicodeEmojiOverride)),
            (key: "UnicodeEmojiWidth", value: String(config.unicodeEmojiWidth)),
            (key: "UnicodeToDecSpMapping", value: String(config.unicodeToDecSpMapping)),
            (key: "DecSpMappingDir",   value: String(config.decSpMappingDir)),
        ]

        // Sendfile, Receivefile, Language, Protocol Logs, Kermit, B-Plus, Quick-VAN, Special Options, TEK
        mainPairs += [
            (key: "SendfileDelayType", value: config.sendfileDelayType),
            (key: "SendfileDelayTick", value: String(config.sendfileDelayTick)),
            (key: "SendfileSize",      value: String(config.sendfileSize)),
            (key: "SendfileSequential", value: onOff(config.sendfileSequential)),
            (key: "SendfileSkipOptionDialog", value: onOff(config.sendfileSkipOptionDialog)),
            (key: "FileReceiveFilter", value: config.fileReceiveFilter),
            (key: "ReceivefileSkipOptionDialog", value: onOff(config.receivefileSkipOptionDialog)),
            (key: "ReceivefileAutoStopWaitTime", value: String(config.receivefileAutoStopWaitTime)),
            (key: "UILanguageFile",    value: config.language),
            (key: "TelLog",            value: onOff(config.telLog)),
            (key: "XmodemLog",         value: onOff(config.xmodemLog)),
            (key: "YmodemLog",         value: onOff(config.ymodemLog)),
            (key: "ZmodemLog",         value: onOff(config.zmodemLog)),
            (key: "KmtLog",            value: onOff(config.kmtLog)),
            (key: "KmtLongPacket",     value: onOff(config.kmtLongPacket)),
            (key: "KmtFileAttr",       value: onOff(config.kmtFileAttr)),
            (key: "BPAuto",            value: onOff(config.bpAuto)),
            (key: "BPEscCtl",          value: onOff(config.bpEscCtl)),
            (key: "BPLog",             value: onOff(config.bpLog)),
            (key: "QVLog",             value: onOff(config.qvLog)),
            (key: "QVWinSize",         value: String(config.qvWinSize)),
            (key: "AutoWinSwitch",     value: onOff(config.autoWinSwitch)),
            (key: "CtrlInKanji",       value: onOff(config.ctrlInKanji)),
            (key: "FixedJIS",          value: onOff(config.fixedJIS)),
            (key: "BackWrap",          value: onOff(config.backWrap)),
            (key: "AutoInvoke",        value: onOff(config.autoInvoke)),
            (key: "ConfirmDisconnect", value: onOff(config.confirmOnDisconnect)),
            (key: "VTCompatTab",       value: onOff(config.vtCompatTab)),
            (key: "TEKIcon",           value: config.tekIcon),
            (key: "TEKGINMouseCode",   value: String(config.tekGINMouseCode)),
            (key: "SendBreakTime",     value: String(config.sendBreakTime)),
            (key: "Wait4allMacroCommand", value: onOff(config.wait4allMacroCommand)),
            (key: "ClearScreenOnCloseConnection", value: onOff(config.clearScreenOnCloseConnection)),
            (key: "FileSendHighSpeedMode", value: onOff(config.fileSendHighSpeedMode)),
            (key: "FallbackToCP932",   value: onOff(config.fallbackToCP932)),
            (key: "StartupMacro",      value: config.startupMacro),
            (key: "AutoScrollOnlyInBottomLine", value: onOff(config.autoScrollOnlyInBottomLine)),
            (key: "LockTUID",          value: onOff(config.lockTUID)),
            (key: "WindowCornerDontround", value: onOff(config.cornerRounding)),
            (key: "IniAutoBackup",     value: onOff(config.iniAutoBackup)),
            (key: "BracketedSupport",  value: onOff(config.bracketedPasteMode)),
            (key: "BracketedControlOnly", value: onOff(config.bracketedControlOnly)),
            (key: "AutoWrap",          value: onOff(config.autoWrap)),
            (key: "TEKPos",            value: config.tekPos),
            (key: "TEKPPI",            value: config.tekPPI),
        ]

        sections.append(.init(name: Self.mainSection, pairs: mainPairs))

        // ── [TCP/IP] ─────────────────────────────────────────
        sections.append(.init(name: "TCP/IP", pairs: [
            (key: "HostName",          value: config.hostName),
            (key: "TCPPort",           value: String(config.tcpPort)),
            (key: "Telnet",            value: onOff(config.telnet)),
            (key: "PortType",          value: String(config.portType)),
        ]))

        // ── [Serial] ─────────────────────────────────────────
        sections.append(.init(name: "Serial", pairs: [
            (key: "SerialPort",        value: config.serialPort),
            (key: "BaudRate",          value: String(config.baudRate)),
            (key: "DataBits",          value: String(config.dataBits)),
            (key: "Parity",            value: String(config.parity)),
            (key: "StopBits",          value: String(config.stopBits)),
            (key: "FlowControl",       value: String(config.flowControl)),
        ]))

        // ── [BG] ─────────────────────────────────────────────
        sections.append(.init(name: "BG", pairs: [
            (key: "BGEnable",          value: String(config.bgEnable)),
            (key: "BGThemeFile",       value: config.bgThemeFile),
            (key: "BGSPIPath",         value: config.bgSPIPath),
            (key: "BGFastSizeMove",    value: String(config.bgFastSizeMove)),
            (key: "BGNoFrame",         value: String(config.bgNoFrame)),
        ]))

        // ── [TTSSH] ──────────────────────────────────────────
        sections.append(.init(name: "TTSSH", pairs: [
            (key: "SSHVersion",        value: String(config.sshVersion)),
            (key: "DefaultAuthMethod", value: String(config.sshDefaultAuthMethod)),
            (key: "DefaultUserName",   value: config.sshDefaultUserName),
            (key: "DefaultUserNameMode", value: String(config.sshDefaultUserNameMode)),
            (key: "DefaultForwarding", value: config.sshDefaultForwarding),
            (key: "HeartBeat",         value: String(config.sshHeartBeat)),
            (key: "ForwardAgent",      value: onOff(config.sshForwardAgent)),
            (key: "ConfirmForwardAgent", value: onOff(config.sshConfirmForwardAgent)),
            (key: "NotifyForwardAgent", value: onOff(config.sshNotifyForwardAgent)),
            (key: "VerifyHostKeyDNS",  value: onOff(config.sshVerifyHostKeyDNS)),
            (key: "KnownHostsFile",    value: config.sshKnownHostsFile),
            (key: "KnownHostsReadOnlyFile", value: config.sshKnownHostsReadOnlyFile),
            (key: "HostKeyRotation",   value: String(config.sshHostKeyRotation)),
            (key: "LogLevel",          value: String(config.sshLogLevel)),
            (key: "CompressionLevel",  value: String(config.sshCompressionLevel)),
            (key: "XForwarding",       value: onOff(config.sshXForwarding)),
            (key: "CheckAuthBeforeLogin", value: onOff(config.sshCheckAuthBeforeLogin)),
            (key: "CipherOrder",       value: config.sshCipherOrder),
            (key: "KexOrder",          value: config.sshKexOrder),
            (key: "HostKeyOrder",      value: config.sshHostKeyOrder),
            (key: "MACOrder",          value: config.sshMACOrder),
            (key: "CompOrder",         value: config.sshCompOrder),
        ]))

        // ── [Proxy] ──────────────────────────────────────────
        sections.append(.init(name: "Proxy", pairs: [
            (key: "ProxyType",         value: String(config.proxyType)),
            (key: "ProxyHost",         value: config.proxyHost),
            (key: "ProxyPort",         value: String(config.proxyPort)),
            (key: "ProxyUser",         value: config.proxyUser),
            (key: "ProxyPass",         value: config.proxyPass),
        ]))

        return sections
    }

    // MARK: - Decode

    /// Decode INI sections into a `TeraTermConfig`.
    func decode(sections: [INISerializer.Section]) -> TeraTermConfig {
        var c = TeraTermConfig()
        let get = { (sec: String, key: String) -> String? in
            INISerializer.getValue(from: sections, section: sec, key: key)
        }
        let main = Self.mainSection
        let isOn = { (v: String) -> Bool in v == "on" }

        // ── Meta ──────────────────────────────────────────
        c.version = get(main, Self.versionKey) ?? TeraTermConfig.currentVersion
        if let v = get(main, "Port") { c.port = v }

        // ── Terminal Emulation ────────────────────────────
        if let v = get(main, "TerminalID")                   { c.terminalID = v }
        if let v = get(main, "TerminalWidth"),  let n = Int(v) { c.terminalWidth = n }
        if let v = get(main, "TerminalHeight"), let n = Int(v) { c.terminalHeight = n }
        if let v = get(main, "TermIsWin")                    { c.termIsWin = isOn(v) }
        if let v = get(main, "AutoWinResize")                { c.autoWinResize = isOn(v) }
        if let v = get(main, "TermType")                     { c.termType = v }
        if let v = get(main, "Answerback")                   { c.answerback = v }
        if let v = get(main, "TerminalUID")                  { c.terminalUID = v }
        if let v = get(main, "TerminalSpeed")                { c.terminalSpeed = v }

        // ── New-line ──────────────────────────────────────
        if let v = get(main, "CRReceive"), let n = Int(v) { c.crReceive = n }
        if let v = get(main, "CRSend"),    let n = Int(v) { c.crSend = n }

        // ── Character Encoding ────────────────────────────
        if let v = get(main, "Encoding")        { c.encoding = v }
        if let v = get(main, "KanjiSend")       { c.sendEncoding = v }
        if let v = get(main, "KatakanaReceive") { c.katakanaReceive = v }
        if let v = get(main, "KatakanaSend")    { c.katakanaSend = v }
        if let v = get(main, "KanjiIn")         { c.kanjiIn = v }
        if let v = get(main, "KanjiOut")        { c.kanjiOut = v }

        // ── Local Echo ────────────────────────────────────
        if let v = get(main, "LocalEcho") { c.localEcho = isOn(v) }

        // ── Cursor ────────────────────────────────────────
        if let v = get(main, "CursorShape"), let n = Int(v) { c.cursorShape = n }
        if let v = get(main, "CursorBlink")                 { c.cursorBlink = isOn(v) }
        if let v = get(main, "KillFocusCursor")             { c.killFocusCursor = isOn(v) }

        // ── Window Display ────────────────────────────────
        if let v = get(main, "Title")                         { c.title = v }
        if let v = get(main, "TitleFormat"),  let n = Int(v)  { c.titleFormat = n }
        if let v = get(main, "SaveVTWinPos")                  { c.saveVTWinPos = isOn(v) }

        // ── Scroll ────────────────────────────────────────
        if let v = get(main, "EnableScrollBuffer")                { c.enableScrollBuffer = isOn(v) }
        if let v = get(main, "ScrollBuffSize"),    let n = Int(v) { c.scrollBufferSize = n }
        if let v = get(main, "MaxBuffSize"),       let n = Int(v) { c.scrollBufferMax = n }
        if let v = get(main, "ScrollThreshold"),   let n = Int(v) { c.scrollThreshold = n }
        if let v = get(main, "ScrollWindowClearScreen")           { c.scrollWindowClearScreen = isOn(v) }

        // ── Color ─────────────────────────────────────────
        if let v = get(main, "VTColor")          { c.vtColor = v }
        if let v = get(main, "VTBoldColor")      { c.vtBoldColor = v }
        if let v = get(main, "VTBlinkColor")     { c.vtBlinkColor = v }
        if let v = get(main, "VTReverseColor")   { c.vtReverseColor = v }
        if let v = get(main, "VTUnderlineColor") { c.vtUnderlineColor = v }
        if let v = get(main, "URLColor")         { c.urlColor = v }
        if let v = get(main, "TEKColor")         { c.tekColor = v }
        if let v = get(main, "ANSIColor")        { c.ansiColor = v }
        if let v = get(main, "EnableBoldAttrColor")    { c.enableBoldColor = isOn(v) }
        if let v = get(main, "EnableBlinkAttrColor")   { c.enableBlinkColor = isOn(v) }
        if let v = get(main, "EnableReverseAttrColor") { c.enableReverseColor = isOn(v) }
        if let v = get(main, "EnableURLColor")         { c.enableURLColor = isOn(v) }
        if let v = get(main, "EnableANSIColor")        { c.enableANSIColor = isOn(v) }
        if let v = get(main, "PcBoldColor")            { c.pcBoldColor = isOn(v) }
        if let v = get(main, "Aixterm16Color")         { c.enableAixtermColors = isOn(v) }
        if let v = get(main, "Xterm256Color")          { c.enableXterm256Colors = isOn(v) }
        if let v = get(main, "UseTextColor")           { c.useTextColor = isOn(v) }
        if let v = get(main, "UseNormalBGColor")       { c.useStandardBGColor = isOn(v) }
        if let v = get(main, "TEKColorEmulation")      { c.tekColorEmulation = isOn(v) }

        // ── Font ──────────────────────────────────────────
        if let v = get(main, "FontName")            { c.fontName = v }
        if let v = get(main, "FontSize"), let n = Int(v) { c.fontSize = n }
        if let v = get(main, "TEKFont")             { c.tekFont = v }
        if let v = get(main, "EnableBold")          { c.enableBoldFont = isOn(v) }
        if let v = get(main, "URLUnderline")        { c.enableURLUnderline = isOn(v) }
        if let v = get(main, "UnderlineAttrFont")   { c.enableUnderlineDecoration = isOn(v) }
        if let v = get(main, "UnderlineAttrColor")  { c.enableUnderlineColor = isOn(v) }
        if let v = get(main, "VTFontSpace")         { c.vtFontSpace = v }
        if let v = get(main, "FontQuality")         { c.fontQuality = v }
        if let v = get(main, "FontScaling")         { c.fontScaling = isOn(v) }
        if let v = get(main, "DrawingResizedFont")  { c.drawingResizedFont = isOn(v) }
        if let v = get(main, "DlgFont")             { c.dialogFont = v }
        if let v = get(main, "VTDrawAPI")            { c.drawingAPI = v }
        if let v = get(main, "VTDrawACP"), let n = Int(v) { c.codePage = n }

        // ── Keyboard ──────────────────────────────────────
        if let v = get(main, "BSKey"),     let n = Int(v) { c.bsKey = n }
        if let v = get(main, "DeleteKey"), let n = Int(v) { c.deleteKey = n }
        if let v = get(main, "MetaKey"),   let n = Int(v) { c.metaKey = n }
        if let v = get(main, "Meta8Bit")                  { c.meta8Bit = v }
        if let v = get(main, "DisableAppKeypad")          { c.disableAppKeypad = isOn(v) }
        if let v = get(main, "DisableAppCursor")          { c.disableAppCursor = isOn(v) }
        if let v = get(main, "StrictKeyMapping")          { c.strictKeyMapping = isOn(v) }
        if let v = get(main, "RussKeyb")                  { c.russKeyb = v }
        if let v = get(main, "IMERelatedCursor")          { c.cursorChangeIME = isOn(v) }

        // ── Beep ──────────────────────────────────────────
        if let v = get(main, "Beep"),              let n = Int(v) { c.beep = n }
        if let v = get(main, "BeepOnConnect")                     { c.beepOnConnect = isOn(v) }
        if let v = get(main, "BeepOverUsedCount"), let n = Int(v) { c.beepOverUsedCount = n }
        if let v = get(main, "BeepOverUsedTime"),  let n = Int(v) { c.beepOverUsedTime = n }
        if let v = get(main, "BeepSuppressTime"),  let n = Int(v) { c.beepSuppressTime = n }
        if let v = get(main, "BeepVBellWait"),     let n = Int(v) { c.beepVBellWait = n }
        if let v = get(main, "NotifySound")                       { c.notifySound = isOn(v) }

        // ── Connection ────────────────────────────────────
        if let v = get(main, "Telnet")                            { c.telnet = isOn(v) }
        if let v = get(main, "TCPPort"),           let n = Int(v) { c.tcpPort = n }
        if let v = get(main, "TelPort"),           let n = Int(v) { c.telPort = n }
        if let v = get(main, "AutoWinClose")                      { c.autoWindowClose = isOn(v) }
        if let v = get(main, "HistoryList")                       { c.hostHistory = isOn(v) }
        if let v = get(main, "ConnectingTimeout"), let n = Int(v) { c.connectingTimeout = n }
        if let v = get(main, "TelAutoDetect")                     { c.telAutoDetect = isOn(v) }
        if let v = get(main, "TelBin")                            { c.telBin = isOn(v) }
        if let v = get(main, "TelEcho")                           { c.telEcho = isOn(v) }
        if let v = get(main, "TelKeepAliveInterval"), let n = Int(v) { c.tcpKeepAliveInterval = n }
        if let v = get(main, "TCPLocalEcho")                      { c.tcpLocalEcho = isOn(v) }
        if let v = get(main, "TCPCRSend")                         { c.tcpCRSend = v }
        if let v = get(main, "DisableTCPEchoCR")                  { c.disableTCPEchoCR = isOn(v) }

        // ── Serial ────────────────────────────────────────
        if let v = get(main, "DelayPerChar"),      let n = Int(v) { c.serialDelayPerChar = n }
        if let v = get(main, "DelayPerLine"),      let n = Int(v) { c.serialDelayPerLine = n }
        if let v = get(main, "ClearComBuffOnOpen")                { c.clearComBuffOnOpen = isOn(v) }
        if let v = get(main, "WaitCom")                           { c.waitCom = isOn(v) }
        if let v = get(main, "AutoComPortReconnect")              { c.autoComPortReconnect = isOn(v) }
        if let v = get(main, "AutoComPortReconnectDelayNormal"),   let n = Int(v) { c.autoComPortReconnectDelayNormal = n }
        if let v = get(main, "AutoComPortReconnectDelayIllegal"),  let n = Int(v) { c.autoComPortReconnectDelayIllegal = n }
        if let v = get(main, "AutoComPortReconnectRetryInterval"), let n = Int(v) { c.autoComPortReconnectRetryInterval = n }
        if let v = get(main, "AutoComPortReconnectRetryCount"),    let n = Int(v) { c.autoComPortReconnectRetryCount = n }

        // ── Log ───────────────────────────────────────────
        if let v = get(main, "LogAutoStart")           { c.logAutoStart = isOn(v) }
        if let v = get(main, "LogDefaultName")         { c.logDefaultName = v }
        if let v = get(main, "LogDefaultPath")         { c.logDefaultPath = v }
        if let v = get(main, "LogTimestamp")           { c.logTimestamp = isOn(v) }
        if let v = get(main, "LogTimestampFormat")     { c.logTimestampFormat = v }
        if let v = get(main, "LogTimestampType")       { c.logTimestampType = v }
        if let v = get(main, "LogTypePlainText")       { c.logPlainText = isOn(v) }
        if let v = get(main, "LogBinary")              { c.logBinary = isOn(v) }
        if let v = get(main, "LogAppend")              { c.logAppend = isOn(v) }
        if let v = get(main, "LogHideDialog")          { c.logHideDialog = isOn(v) }
        if let v = get(main, "LogIncludeScreenBuffer") { c.logIncludeScreenBuffer = isOn(v) }
        if let v = get(main, "LogRotate"),         let n = Int(v) { c.logRotateEnabled = n }
        if let v = get(main, "LogRotateSize"),     let n = Int(v) { c.logRotateSize = n }
        if let v = get(main, "LogRotateSizeType"), let n = Int(v) { c.logRotateSizeType = n }
        if let v = get(main, "LogRotateStep"),     let n = Int(v) { c.logRotateStep = n }
        if let v = get(main, "DeferredLogWriteMode")   { c.deferredLogWriteMode = isOn(v) }
        if let v = get(main, "ViewlogEditor")          { c.logViewEditor = v }
        if let v = get(main, "ViewlogEditorArg")       { c.logEditorArguments = v }
        if let v = get(main, "LogBOM")                 { c.logBOM = isOn(v) }

        // ── File Transfer ─────────────────────────────────
        if let v = get(main, "TransBin")           { c.transBin = isOn(v) }
        if let v = get(main, "XmodemOpt")          { c.xmodemOption = v }
        if let v = get(main, "XmodemBin")          { c.xmodemBin = isOn(v) }
        if let v = get(main, "XModemRcvCommand")   { c.xModemRcvCommand = v }
        if let v = get(main, "YModemRcvCommand")   { c.yModemRcvCommand = v }
        if let v = get(main, "ZmodemDataLen"),     let n = Int(v) { c.zmodemDataLen = n }
        if let v = get(main, "ZmodemWinSize"),     let n = Int(v) { c.zmodemWindowSize = n }
        if let v = get(main, "ZModemRcvCommand")   { c.zModemRcvCommand = v }
        if let v = get(main, "ZmodemAuto")         { c.zmodemAutoReceive = isOn(v) }
        if let v = get(main, "ZmodemEscCtl")       { c.zmodemEscCtl = isOn(v) }
        if let v = get(main, "FileDir")            { c.fileTransferFolder = v }
        if let v = get(main, "FileSendFilter")     { c.fileSendFilter = v }
        if let v = get(main, "ScpSendDir")         { c.scpSendDir = v }
        if let v = get(main, "FTHideDialog")       { c.ftHideDialog = isOn(v) }
        if let v = get(main, "AutoFileRename")     { c.autoFileRename = isOn(v) }
        if let v = get(main, "ConfirmFileDragAndDrop") { c.confirmFileDragAndDrop = isOn(v) }

        // ── Timeouts ──────────────────────────────────────
        if let v = get(main, "XmodemTimeouts") { c.xmodemTimeouts = v }
        if let v = get(main, "YmodemTimeouts") { c.ymodemTimeouts = v }
        if let v = get(main, "ZmodemTimeouts") { c.zmodemTimeouts = v }

        // ── Control Sequences ─────────────────────────────
        if let v = get(main, "Accept8BitCtrl")           { c.accept8BitCtrl = isOn(v) }
        if let v = get(main, "AllowWrongSequence")       { c.allowWrongSequence = isOn(v) }
        if let v = get(main, "AcceptTitleChangeRequest") { c.titleChangeRequest = v }
        if let v = get(main, "WindowCtrlSequence")       { c.windowControlSequence = isOn(v) }
        if let v = get(main, "CursorCtrlSequence")       { c.cursorControlSequence = isOn(v) }
        if let v = get(main, "WindowReportSequence")     { c.windowInfoReportSequence = isOn(v) }
        if let v = get(main, "TitleReportSequence")      { c.titleReportRequest = v }
        if let v = get(main, "ClipboardAccessFromRemote") { c.clipboardAccessFromRemote = v }
        if let v = get(main, "NotifyClipboardAccess")    { c.notifyClipboardAccess = isOn(v) }
        if let v = get(main, "ClearScrollBufferFromRemote") { c.acceptScrollBufferClear = isOn(v) }
        if let v = get(main, "ClearOnResize")            { c.clearOnResize = isOn(v) }
        if let v = get(main, "AlternateScreenBuffer")    { c.alternateScreenBuffer = isOn(v) }
        if let v = get(main, "EnableStatusLine")         { c.enableStatusLine = isOn(v) }
        if let v = get(main, "EnableLineMode")           { c.enableLineMode = isOn(v) }
        if let v = get(main, "PrinterCtrlSequence")      { c.disablePrintSequence = !isOn(v) }
        if let v = get(main, "UseInvalidDECRQSSResponse") { c.useInvalidDECRQSSResponse = isOn(v) }
        if let v = get(main, "TabStopModifySequence")    { c.tabStopModifySequence = v }
        if let v = get(main, "ISO2022ShiftFunction")     { c.iso2022ShiftFunction = v }
        if let v = get(main, "MaxOSCBufferSize"), let n = Int(v) { c.maxOSCBufferSize = n }
        if let v = get(main, "Send8BitCtrl")             { c.send8BitCtrl = isOn(v) }

        // ── Copy & Paste ──────────────────────────────────
        if let v = get(main, "AutoTextCopy")              { c.autoTextCopy = isOn(v) }
        if let v = get(main, "EnableContinuedLineCopy")   { c.continuedLineCopy = isOn(v) }
        if let v = get(main, "SelectOnlyByLButton")       { c.leftClickOnlySelection = isOn(v) }
        if let v = get(main, "SelectOnActivate")          { c.enableSelectionOnActivate = isOn(v) }
        if let v = get(main, "DisablePasteMouseRButton")  { c.disableRightClickPaste = isOn(v) }
        if let v = get(main, "DisablePasteMouseMButton")  { c.disableMiddleClickPaste = isOn(v) }
        if let v = get(main, "ConfirmPasteMouseRButton")  { c.confirmRightClickPaste = isOn(v) }
        if let v = get(main, "ConfirmChangePaste")        { c.clipboardConfirmPaste = isOn(v) }
        if let v = get(main, "ConfirmChangePasteCR")      { c.confirmPasteNewLine = isOn(v) }
        if let v = get(main, "ConfirmChangePasteStringFile") { c.dangerousKeywordFile = v }
        if let v = get(main, "TrimTrailingNLonPaste")     { c.trimTrailingNewline = isOn(v) }
        if let v = get(main, "PasteDelayPerLine"), let n = Int(v) { c.pasteDelay = n }
        if let v = get(main, "DelimList")                 { c.delimiterList = v }
        if let v = get(main, "DelimDBCS")                 { c.delimDBCS = isOn(v) }
        if let v = get(main, "MouseSelectStartDelay"), let n = Int(v) { c.mouseSelectStartDelay = n }

        // ── Mouse ─────────────────────────────────────────
        if let v = get(main, "MouseEventTracking")        { c.mouseTracking = isOn(v) }
        if let v = get(main, "MouseWheelScrollLine"), let n = Int(v) { c.mouseWheelScrollLines = n }
        if let v = get(main, "MouseCursor")               { c.mouseCursorType = v }
        if let v = get(main, "TranslateWheelToCursor")    { c.translateWheelToCursor = isOn(v) }
        if let v = get(main, "DisableMouseTrackingByCtrl") { c.disableControlKeyMouseEvent = isOn(v) }
        if let v = get(main, "DisableWheelToCursorByCtrl") { c.disableWheelToCursorByCtrl = isOn(v) }

        // ── Window Opacity ────────────────────────────────
        if let v = get(main, "AlphaBlend"),       let n = Int(v) { c.windowOpacityInactive = n }
        if let v = get(main, "AlphaBlendActive"), let n = Int(v) { c.windowOpacityActive = n }

        // ── Broadcast ─────────────────────────────────────
        if let v = get(main, "BroadcastCommandHistory")   { c.broadcastHistory = isOn(v) }
        if let v = get(main, "AcceptBroadcast")           { c.acceptBroadcast = isOn(v) }
        if let v = get(main, "MaxBroadcatHistory"), let n = Int(v) { c.maxBroadcastHistory = n }

        // ── Debug ─────────────────────────────────────────
        if let v = get(main, "Debug")      { c.debugCharInfoPopup = isOn(v) }
        if let v = get(main, "DebugModes") { c.debugModes = v }

        // ── URL ───────────────────────────────────────────
        if let v = get(main, "EnableClickableUrl")        { c.enableClickableUrl = isOn(v) }
        if let v = get(main, "JoinSplitURL")              { c.joinSplitURL = isOn(v) }
        if let v = get(main, "JoinSplitURLIgnoreEOLChar") { c.joinSplitURLIgnoreEOLChar = v }

        // ── Unicode ───────────────────────────────────────
        if let v = get(main, "UnicodeAmbiguousWidth"), let n = Int(v) { c.unicodeAmbiguousWidth = n }
        if let v = get(main, "UnicodeEmojiOverride")      { c.unicodeEmojiOverride = isOn(v) }
        if let v = get(main, "UnicodeEmojiWidth"), let n = Int(v) { c.unicodeEmojiWidth = n }
        if let v = get(main, "UnicodeToDecSpMapping"), let n = Int(v) { c.unicodeToDecSpMapping = n }
        if let v = get(main, "DecSpMappingDir"), let n = Int(v) { c.decSpMappingDir = n }

        // ── Sendfile ──────────────────────────────────────
        if let v = get(main, "SendfileDelayType")  { c.sendfileDelayType = v }
        if let v = get(main, "SendfileDelayTick"), let n = Int(v) { c.sendfileDelayTick = n }
        if let v = get(main, "SendfileSize"), let n = Int(v) { c.sendfileSize = n }
        if let v = get(main, "SendfileSequential") { c.sendfileSequential = isOn(v) }
        if let v = get(main, "SendfileSkipOptionDialog") { c.sendfileSkipOptionDialog = isOn(v) }

        // ── Receivefile ───────────────────────────────────
        if let v = get(main, "FileReceiveFilter")  { c.fileReceiveFilter = v }
        if let v = get(main, "ReceivefileSkipOptionDialog") { c.receivefileSkipOptionDialog = isOn(v) }
        if let v = get(main, "ReceivefileAutoStopWaitTime"), let n = Int(v) { c.receivefileAutoStopWaitTime = n }

        // ── UI Language ───────────────────────────────────
        if let v = get(main, "UILanguageFile") { c.language = v }

        // ── Protocol Logs ─────────────────────────────────
        if let v = get(main, "TelLog")    { c.telLog = isOn(v) }
        if let v = get(main, "XmodemLog") { c.xmodemLog = isOn(v) }
        if let v = get(main, "YmodemLog") { c.ymodemLog = isOn(v) }
        if let v = get(main, "ZmodemLog") { c.zmodemLog = isOn(v) }

        // ── Kermit ────────────────────────────────────────
        if let v = get(main, "KmtLog")        { c.kmtLog = isOn(v) }
        if let v = get(main, "KmtLongPacket") { c.kmtLongPacket = isOn(v) }
        if let v = get(main, "KmtFileAttr")   { c.kmtFileAttr = isOn(v) }

        // ── B-Plus ────────────────────────────────────────
        if let v = get(main, "BPAuto")   { c.bpAuto = isOn(v) }
        if let v = get(main, "BPEscCtl") { c.bpEscCtl = isOn(v) }
        if let v = get(main, "BPLog")    { c.bpLog = isOn(v) }

        // ── Quick-VAN ─────────────────────────────────────
        if let v = get(main, "QVLog")                      { c.qvLog = isOn(v) }
        if let v = get(main, "QVWinSize"), let n = Int(v)  { c.qvWinSize = n }

        // ── Other Special Options ─────────────────────────
        if let v = get(main, "AutoWinSwitch")     { c.autoWinSwitch = isOn(v) }
        if let v = get(main, "CtrlInKanji")       { c.ctrlInKanji = isOn(v) }
        if let v = get(main, "FixedJIS")          { c.fixedJIS = isOn(v) }
        if let v = get(main, "BackWrap")          { c.backWrap = isOn(v) }
        if let v = get(main, "AutoInvoke")        { c.autoInvoke = isOn(v) }
        if let v = get(main, "ConfirmDisconnect") { c.confirmOnDisconnect = isOn(v) }
        if let v = get(main, "VTCompatTab")       { c.vtCompatTab = isOn(v) }
        if let v = get(main, "TEKIcon")           { c.tekIcon = v }
        if let v = get(main, "TEKGINMouseCode"), let n = Int(v) { c.tekGINMouseCode = n }
        if let v = get(main, "SendBreakTime"),   let n = Int(v) { c.sendBreakTime = n }
        if let v = get(main, "Wait4allMacroCommand")      { c.wait4allMacroCommand = isOn(v) }
        if let v = get(main, "ClearScreenOnCloseConnection") { c.clearScreenOnCloseConnection = isOn(v) }
        if let v = get(main, "FileSendHighSpeedMode")     { c.fileSendHighSpeedMode = isOn(v) }
        if let v = get(main, "FallbackToCP932")           { c.fallbackToCP932 = isOn(v) }
        if let v = get(main, "StartupMacro")              { c.startupMacro = v }
        if let v = get(main, "AutoScrollOnlyInBottomLine") { c.autoScrollOnlyInBottomLine = isOn(v) }
        if let v = get(main, "LockTUID")                  { c.lockTUID = isOn(v) }
        if let v = get(main, "WindowCornerDontround")     { c.cornerRounding = isOn(v) }
        if let v = get(main, "IniAutoBackup")             { c.iniAutoBackup = isOn(v) }
        if let v = get(main, "BracketedSupport")          { c.bracketedPasteMode = isOn(v) }
        if let v = get(main, "BracketedControlOnly")      { c.bracketedControlOnly = isOn(v) }
        if let v = get(main, "AutoWrap")                  { c.autoWrap = isOn(v) }

        // ── TEK ───────────────────────────────────────────
        if let v = get(main, "TEKPos")  { c.tekPos = v }
        if let v = get(main, "TEKPPI")  { c.tekPPI = v }

        // ── [TCP/IP] ─────────────────────────────────────
        if let v = get("TCP/IP", "HostName")              { c.hostName = v }
        if let v = get("TCP/IP", "TCPPort"),  let n = Int(v) { c.tcpPort = n }
        if let v = get("TCP/IP", "Telnet")                { c.telnet = isOn(v) }
        if let v = get("TCP/IP", "PortType"), let n = Int(v) { c.portType = n }

        // ── [Serial] ─────────────────────────────────────
        if let v = get("Serial", "SerialPort")               { c.serialPort = v }
        if let v = get("Serial", "BaudRate"),    let n = Int(v) { c.baudRate = n }
        if let v = get("Serial", "DataBits"),    let n = Int(v) { c.dataBits = n }
        if let v = get("Serial", "Parity"),      let n = Int(v) { c.parity = n }
        if let v = get("Serial", "StopBits"),    let n = Int(v) { c.stopBits = n }
        if let v = get("Serial", "FlowControl"), let n = Int(v) { c.flowControl = n }

        // ── [BG] ─────────────────────────────────────────
        if let v = get("BG", "BGEnable"),       let n = Int(v) { c.bgEnable = n }
        if let v = get("BG", "BGThemeFile")     { c.bgThemeFile = v }
        if let v = get("BG", "BGSPIPath")       { c.bgSPIPath = v }
        if let v = get("BG", "BGFastSizeMove"), let n = Int(v) { c.bgFastSizeMove = n }
        if let v = get("BG", "BGNoFrame"),      let n = Int(v) { c.bgNoFrame = n }

        // ── [TTSSH] ──────────────────────────────────────
        if let v = get("TTSSH", "SSHVersion"),        let n = Int(v) { c.sshVersion = n }
        if let v = get("TTSSH", "DefaultAuthMethod"), let n = Int(v) { c.sshDefaultAuthMethod = n }
        if let v = get("TTSSH", "DefaultUserName")    { c.sshDefaultUserName = v }
        if let v = get("TTSSH", "DefaultUserNameMode"), let n = Int(v) { c.sshDefaultUserNameMode = n }
        if let v = get("TTSSH", "DefaultForwarding")  { c.sshDefaultForwarding = v }
        if let v = get("TTSSH", "HeartBeat"),         let n = Int(v) { c.sshHeartBeat = n }
        if let v = get("TTSSH", "ForwardAgent")       { c.sshForwardAgent = isOn(v) }
        if let v = get("TTSSH", "ConfirmForwardAgent") { c.sshConfirmForwardAgent = isOn(v) }
        if let v = get("TTSSH", "NotifyForwardAgent") { c.sshNotifyForwardAgent = isOn(v) }
        if let v = get("TTSSH", "VerifyHostKeyDNS")   { c.sshVerifyHostKeyDNS = isOn(v) }
        if let v = get("TTSSH", "KnownHostsFile")     { c.sshKnownHostsFile = v }
        if let v = get("TTSSH", "KnownHostsReadOnlyFile") { c.sshKnownHostsReadOnlyFile = v }
        if let v = get("TTSSH", "HostKeyRotation"),   let n = Int(v) { c.sshHostKeyRotation = n }
        if let v = get("TTSSH", "LogLevel"),          let n = Int(v) { c.sshLogLevel = n }
        if let v = get("TTSSH", "CompressionLevel"),  let n = Int(v) { c.sshCompressionLevel = n }
        if let v = get("TTSSH", "XForwarding")        { c.sshXForwarding = isOn(v) }
        if let v = get("TTSSH", "CheckAuthBeforeLogin") { c.sshCheckAuthBeforeLogin = isOn(v) }
        if let v = get("TTSSH", "CipherOrder")        { c.sshCipherOrder = v }
        if let v = get("TTSSH", "KexOrder")           { c.sshKexOrder = v }
        if let v = get("TTSSH", "HostKeyOrder")       { c.sshHostKeyOrder = v }
        if let v = get("TTSSH", "MACOrder")           { c.sshMACOrder = v }
        if let v = get("TTSSH", "CompOrder")          { c.sshCompOrder = v }

        // ── [Proxy] ──────────────────────────────────────
        if let v = get("Proxy", "ProxyType"), let n = Int(v) { c.proxyType = n }
        if let v = get("Proxy", "ProxyHost")      { c.proxyHost = v }
        if let v = get("Proxy", "ProxyPort"), let n = Int(v) { c.proxyPort = n }
        if let v = get("Proxy", "ProxyUser")      { c.proxyUser = v }
        if let v = get("Proxy", "ProxyPass")      { c.proxyPass = v }

        return c
    }
}
