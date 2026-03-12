/*
 * ConfigPersistenceManagerTests
 * Tests for INI serialization, version checking, format migration,
 * and round-trip config persistence.
 */

import XCTest
@testable import TeraTermMac

final class INISerializerTests: XCTestCase {

    // MARK: - Parsing

    func testParseSimple() {
        let ini = """
        [Section1]
        Key1=Value1
        Key2=Value2

        [Section2]
        Foo=Bar
        """
        let (sections, _) = INISerializer.parse(ini)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].name, "Section1")
        XCTAssertEqual(sections[0].pairs.count, 2)
        XCTAssertEqual(sections[0].pairs[0].key, "Key1")
        XCTAssertEqual(sections[0].pairs[0].value, "Value1")
        XCTAssertEqual(sections[1].name, "Section2")
        XCTAssertEqual(sections[1].pairs[0].value, "Bar")
    }

    func testParseSkipsComments() {
        let ini = """
        [Main]
        ; This is a comment
        Key1=Value1
        # This is also a comment
        Key2=Value2
        """
        let (sections, _) = INISerializer.parse(ini)
        XCTAssertEqual(sections[0].pairs.count, 2)
    }

    func testParseHandlesSpacesAroundEquals() {
        let ini = "[S]\n  Key  =  Value  \n"
        let (sections, _) = INISerializer.parse(ini)
        XCTAssertEqual(sections[0].pairs[0].key, "Key")
        XCTAssertEqual(sections[0].pairs[0].value, "Value")
    }

    func testParseEmptyValue() {
        let ini = "[S]\nKey=\n"
        let (sections, _) = INISerializer.parse(ini)
        XCTAssertEqual(sections[0].pairs[0].value, "")
    }

    func testParseDetectsLineEndingCRLF() {
        let ini = "[Section]\r\nKey=Value\r\n"
        let (_, lineEnding) = INISerializer.parse(ini)
        XCTAssertEqual(lineEnding, .crlf)
    }

    func testParseDetectsLineEndingLF() {
        let ini = "[Section]\nKey=Value\n"
        let (_, lineEnding) = INISerializer.parse(ini)
        XCTAssertEqual(lineEnding, .lf)
    }

    // MARK: - Serialization

    func testSerializeRoundTrip() {
        let original: [INISerializer.Section] = [
            .init(name: "Tera Term", pairs: [
                (key: "Version", value: "5.6"),
                (key: "FontName", value: "Menlo"),
            ]),
            .init(name: "TCP/IP", pairs: [
                (key: "HostName", value: "example.com"),
            ]),
        ]
        let text = INISerializer.serialize(original, lineEnding: .lf)
        let (parsed, _) = INISerializer.parse(text)

        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(INISerializer.getValue(from: parsed, section: "Tera Term", key: "Version"), "5.6")
        XCTAssertEqual(INISerializer.getValue(from: parsed, section: "TCP/IP", key: "HostName"), "example.com")
    }

    // MARK: - GetValue / SetValue

    func testGetValueCaseInsensitive() {
        let sections: [INISerializer.Section] = [
            .init(name: "Tera Term", pairs: [(key: "Version", value: "5.6")])
        ]
        XCTAssertEqual(INISerializer.getValue(from: sections, section: "tera term", key: "version"), "5.6")
        XCTAssertEqual(INISerializer.getValue(from: sections, section: "TERA TERM", key: "VERSION"), "5.6")
    }

    func testSetValueCreatesNew() {
        var sections: [INISerializer.Section] = []
        INISerializer.setValue(in: &sections, section: "New", key: "Key", value: "Val")
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].pairs[0].value, "Val")
    }

    func testSetValueUpdatesExisting() {
        var sections: [INISerializer.Section] = [
            .init(name: "S", pairs: [(key: "K", value: "old")])
        ]
        INISerializer.setValue(in: &sections, section: "S", key: "K", value: "new")
        XCTAssertEqual(sections[0].pairs[0].value, "new")
        XCTAssertEqual(sections[0].pairs.count, 1)
    }
}

final class ConfigPersistenceManagerTests: XCTestCase {

    var testDir: URL!
    var manager: ConfigPersistenceManager!

    override func setUp() {
        super.setUp()
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigPersistenceTest-\(UUID().uuidString)")
        manager = ConfigPersistenceManager()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
        super.tearDown()
    }

    /// Helper: create a custom manager that uses testDir.
    private func makeManager() -> TestableConfigManager {
        return TestableConfigManager(directory: testDir)
    }

    // MARK: - Version Checking

    func testVersionCurrentWithMatchingVersion() {
        let mgr = ConfigPersistenceManager()
        XCTAssertTrue(mgr.isVersionCurrent("5.6"))
    }

    func testVersionCurrentWithNewerVersion() {
        let mgr = ConfigPersistenceManager()
        XCTAssertTrue(mgr.isVersionCurrent("6.0"))
        XCTAssertTrue(mgr.isVersionCurrent("5.7"))
    }

    func testVersionCurrentWithOlderVersion() {
        let mgr = ConfigPersistenceManager()
        XCTAssertFalse(mgr.isVersionCurrent("5.5"))
        XCTAssertFalse(mgr.isVersionCurrent("4.0"))
    }

    func testVersionCurrentWithNil() {
        let mgr = ConfigPersistenceManager()
        XCTAssertFalse(mgr.isVersionCurrent(nil))
        XCTAssertFalse(mgr.isVersionCurrent(""))
    }

    func testVersionCurrentWithInvalidFormat() {
        let mgr = ConfigPersistenceManager()
        XCTAssertFalse(mgr.isVersionCurrent("abc"))
        XCTAssertFalse(mgr.isVersionCurrent("5"))
    }

    // MARK: - Encode / Decode Round-Trip

    func testEncodeDecodeRoundTrip() {
        let mgr = ConfigPersistenceManager()
        var original = TeraTermConfig()
        original.terminalID = "VT102"
        original.terminalWidth = 132
        original.terminalHeight = 50
        original.fontName = "Monaco"
        original.fontSize = 16
        original.hostName = "192.168.1.1"
        original.tcpPort = 2323
        original.baudRate = 115200
        original.localEcho = true
        original.logAutoStart = true
        original.mouseTracking = false

        let sections = mgr.encode(original)
        let decoded = mgr.decode(sections: sections)

        XCTAssertEqual(decoded.version, TeraTermConfig.currentVersion)
        XCTAssertEqual(decoded.terminalID, "VT102")
        XCTAssertEqual(decoded.terminalWidth, 132)
        XCTAssertEqual(decoded.terminalHeight, 50)
        XCTAssertEqual(decoded.fontName, "Monaco")
        XCTAssertEqual(decoded.fontSize, 16)
        XCTAssertEqual(decoded.hostName, "192.168.1.1")
        XCTAssertEqual(decoded.tcpPort, 2323)
        XCTAssertEqual(decoded.baudRate, 115200)
        XCTAssertTrue(decoded.localEcho)
        XCTAssertTrue(decoded.logAutoStart)
        XCTAssertFalse(decoded.mouseTracking)
    }

    // MARK: - File I/O Scenarios

    func testNewInstallCreatesDefaultFile() {
        let mgr = makeManager()

        // No file should exist yet
        XCTAssertFalse(FileManager.default.fileExists(atPath: mgr.iniFileURL.path))

        let config = mgr.loadConfig()

        // File should now exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: mgr.iniFileURL.path))

        // Should have defaults
        XCTAssertEqual(config.version, TeraTermConfig.currentVersion)
        XCTAssertEqual(config.terminalWidth, 80)
        XCTAssertEqual(config.fontName, "Menlo")
    }

    func testOldFormatFileIsRecreated() {
        let mgr = makeManager()
        try! mgr.ensureDirectory()

        // Write a legacy file without Version key
        let legacyINI = """
        [Tera Term]
        FontName=Courier
        FontSize=12
        """
        try! legacyINI.write(to: mgr.iniFileURL, atomically: true, encoding: .utf8)

        let config = mgr.loadConfig()

        // Should have defaults (old file was replaced)
        XCTAssertEqual(config.version, TeraTermConfig.currentVersion)
        XCTAssertEqual(config.fontName, "Menlo")  // default, not "Courier"
        XCTAssertEqual(config.fontSize, 14)        // default, not 12
    }

    func testOldVersionFileIsRecreated() {
        let mgr = makeManager()
        try! mgr.ensureDirectory()

        // Write a file with an old version
        let oldINI = """
        [Tera Term]
        Version=4.0
        FontName=Courier
        """
        try! oldINI.write(to: mgr.iniFileURL, atomically: true, encoding: .utf8)

        let config = mgr.loadConfig()

        // Should have been replaced with defaults
        XCTAssertEqual(config.version, TeraTermConfig.currentVersion)
        XCTAssertEqual(config.fontName, "Menlo")
    }

    func testCurrentVersionFileIsPreserved() {
        let mgr = makeManager()
        try! mgr.ensureDirectory()

        // Write a valid file with current version and custom values
        var custom = TeraTermConfig()
        custom.fontName = "Monaco"
        custom.fontSize = 18
        custom.terminalWidth = 120
        mgr.saveConfig(custom)

        let config = mgr.loadConfig()

        // Custom values should be preserved
        XCTAssertEqual(config.fontName, "Monaco")
        XCTAssertEqual(config.fontSize, 18)
        XCTAssertEqual(config.terminalWidth, 120)
    }

    func testSaveAndLoadPersistsAllSections() {
        let mgr = makeManager()

        var config = TeraTermConfig()
        config.hostName = "test.example.com"
        config.tcpPort = 8022
        config.serialPort = "/dev/cu.usbserial"
        config.baudRate = 57600

        mgr.saveConfig(config)
        let loaded = mgr.loadConfig()

        XCTAssertEqual(loaded.hostName, "test.example.com")
        XCTAssertEqual(loaded.tcpPort, 8022)
        XCTAssertEqual(loaded.serialPort, "/dev/cu.usbserial")
        XCTAssertEqual(loaded.baudRate, 57600)
    }

    func testSaveCreatesDirectoryIfMissing() {
        let mgr = makeManager()

        // Directory doesn't exist yet
        XCTAssertFalse(FileManager.default.fileExists(atPath: mgr.appSupportDirectory.path))

        mgr.saveConfig(TeraTermConfig())

        XCTAssertTrue(FileManager.default.fileExists(atPath: mgr.iniFileURL.path))
    }
}

// MARK: - Unknown / Invalid Key Filtering Tests

final class UnknownKeyFilteringTests: XCTestCase {

    let mgr = ConfigPersistenceManager()

    // MARK: - Unknown keys from original Tera Term (Windows) are skipped

    func testFilterRemovesUnknownKeysFromMainSection() {
        let ini = """
        [Tera Term]
        Version=5.6
        FontName=Menlo
        VTFont=,0,-13,128
        CygwinDirectory=C:\\cygwin
        ClickableUrlBrowser=1
        FontSize=14
        """
        let (sections, _) = INISerializer.parse(ini)
        let (filtered, skipped) = mgr.filterUnknownKeys(sections)

        // Known keys preserved
        XCTAssertEqual(INISerializer.getValue(from: filtered, section: "Tera Term", key: "Version"), "5.6")
        XCTAssertEqual(INISerializer.getValue(from: filtered, section: "Tera Term", key: "FontName"), "Menlo")
        XCTAssertEqual(INISerializer.getValue(from: filtered, section: "Tera Term", key: "FontSize"), "14")

        // Unknown keys removed
        XCTAssertNil(INISerializer.getValue(from: filtered, section: "Tera Term", key: "VTFont"))
        XCTAssertNil(INISerializer.getValue(from: filtered, section: "Tera Term", key: "CygwinDirectory"))
        XCTAssertNil(INISerializer.getValue(from: filtered, section: "Tera Term", key: "ClickableUrlBrowser"))

        // Skipped entries reported
        XCTAssertEqual(skipped.count, 3)
        XCTAssertTrue(skipped.contains(where: { $0.key == "VTFont" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "CygwinDirectory" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "ClickableUrlBrowser" }))
    }

    func testFilterRemovesUnknownKeysFromTTSSHSection() {
        let ini = """
        [TTSSH]
        SSHVersion=2
        DefaultUserName=admin
        WindowsSpecificSSHKey=rsa2048
        AgentAuth=on
        """
        let (sections, _) = INISerializer.parse(ini)
        let (filtered, skipped) = mgr.filterUnknownKeys(sections)

        XCTAssertEqual(INISerializer.getValue(from: filtered, section: "TTSSH", key: "SSHVersion"), "2")
        XCTAssertEqual(INISerializer.getValue(from: filtered, section: "TTSSH", key: "DefaultUserName"), "admin")
        XCTAssertNil(INISerializer.getValue(from: filtered, section: "TTSSH", key: "WindowsSpecificSSHKey"))
        XCTAssertNil(INISerializer.getValue(from: filtered, section: "TTSSH", key: "AgentAuth"))
        XCTAssertEqual(skipped.count, 2)
    }

    func testFilterSkipsEntireUnknownSection() {
        let ini = """
        [Tera Term]
        Version=5.6
        FontName=Menlo

        [CygTerm]
        CygwinDirectory=C:\\cygwin
        LoginShell=/bin/bash
        """
        let (sections, _) = INISerializer.parse(ini)
        let (filtered, skipped) = mgr.filterUnknownKeys(sections)

        // Known section preserved
        XCTAssertEqual(INISerializer.getValue(from: filtered, section: "Tera Term", key: "FontName"), "Menlo")

        // Unknown section's keys are in skipped list
        XCTAssertEqual(skipped.count, 2)
        XCTAssertTrue(skipped.allSatisfy { $0.section == "CygTerm" })
    }

    // MARK: - Valid keys pass through unchanged

    func testFilterPreservesAllKnownKeys() {
        let config = TeraTermConfig()
        let sections = mgr.encode(config)
        let (filtered, skipped) = mgr.filterUnknownKeys(sections)

        // No keys should be skipped for our own encoded output
        XCTAssertEqual(skipped.count, 0)

        // Total pair counts should match
        let originalCount = sections.flatMap { $0.pairs }.count
        let filteredCount = filtered.flatMap { $0.pairs }.count
        XCTAssertEqual(originalCount, filteredCount)
    }

    // MARK: - Mixed known and unknown keys

    func testFilterMixedKeysPreservesOrder() {
        let ini = """
        [Tera Term]
        Version=5.6
        UnknownKey1=foo
        FontName=Menlo
        UnknownKey2=bar
        FontSize=14
        UnknownKey3=baz
        """
        let (sections, _) = INISerializer.parse(ini)
        let (filtered, skipped) = mgr.filterUnknownKeys(sections)

        let pairs = filtered[0].pairs
        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs[0].key, "Version")
        XCTAssertEqual(pairs[1].key, "FontName")
        XCTAssertEqual(pairs[2].key, "FontSize")
        XCTAssertEqual(skipped.count, 3)
    }

    // MARK: - Case insensitive key matching

    func testFilterIsCaseInsensitive() {
        let ini = """
        [Tera Term]
        version=5.6
        FONTNAME=Menlo
        fontSize=14
        """
        let (sections, _) = INISerializer.parse(ini)
        let (filtered, skipped) = mgr.filterUnknownKeys(sections)

        XCTAssertEqual(filtered[0].pairs.count, 3)
        XCTAssertEqual(skipped.count, 0)
    }

    // MARK: - Invalid values for integer fields are handled gracefully

    func testDecodeSkipsInvalidIntegerValues() {
        let ini = """
        [Tera Term]
        Version=5.6
        TerminalWidth=abc
        TerminalHeight=24
        FontSize=not_a_number
        Beep=3
        """
        let (sections, _) = INISerializer.parse(ini)
        let config = mgr.decode(sections: sections)

        // Invalid integer values fall back to defaults
        XCTAssertEqual(config.terminalWidth, 80)   // default, "abc" skipped
        XCTAssertEqual(config.terminalHeight, 24)   // valid
        XCTAssertEqual(config.fontSize, 14)         // default, "not_a_number" skipped
        XCTAssertEqual(config.beep, 3)              // valid
    }

    // MARK: - Full original Tera Term INI with Windows-specific keys

    func testLoadOriginalTeraTermINISkipsWindowsOnlyKeys() {
        let ini = """
        [Tera Term]
        Version=5.6
        FontName=Terminal
        FontSize=12
        VTFont=Terminal,0,-13,128,1,0,0,0,0,0,0,0,0,128
        FontCharSet=128
        RussFont=,0,-13,0,0,0,0,0,0,0,0,0,0,0
        DlgFont=,0,-13,0
        CygwinDirectory=C:\\cygwin64
        Locale=japanese
        CodePage=65001
        WindowMenu=on
        ClickableUrlBrowser=1
        TerminalWidth=80

        [TCP/IP]
        HostName=192.168.1.1
        TCPPort=22
        HistoryList=ssh://host1:22,host2:23
        Telnet=off

        [TTSSH]
        SSHVersion=2
        DefaultUserName=root
        AuthBanner=on
        Subsystem=sftp
        """
        let (rawSections, _) = INISerializer.parse(ini)
        let (filtered, skipped) = mgr.filterUnknownKeys(rawSections)

        // Windows-only keys skipped
        XCTAssertTrue(skipped.contains(where: { $0.key == "VTFont" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "FontCharSet" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "RussFont" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "CygwinDirectory" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "Locale" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "CodePage" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "WindowMenu" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "ClickableUrlBrowser" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "AuthBanner" }))
        XCTAssertTrue(skipped.contains(where: { $0.key == "Subsystem" }))

        // Known keys decoded correctly
        let config = mgr.decode(sections: filtered)
        XCTAssertEqual(config.fontName, "Terminal")
        XCTAssertEqual(config.fontSize, 12)
        XCTAssertEqual(config.terminalWidth, 80)
        XCTAssertEqual(config.hostName, "192.168.1.1")
        XCTAssertEqual(config.tcpPort, 22)
        XCTAssertEqual(config.sshVersion, 2)
        XCTAssertEqual(config.sshDefaultUserName, "root")
    }

    // MARK: - TCP/IP HistoryList (Windows-only key in TCP/IP section)

    func testFilterTCPIPUnknownKeys() {
        let ini = """
        [TCP/IP]
        HostName=server.local
        TCPPort=22
        HistoryList=host1,host2,host3
        """
        let (sections, _) = INISerializer.parse(ini)
        let (filtered, skipped) = mgr.filterUnknownKeys(sections)

        XCTAssertEqual(INISerializer.getValue(from: filtered, section: "TCP/IP", key: "HostName"), "server.local")
        XCTAssertEqual(INISerializer.getValue(from: filtered, section: "TCP/IP", key: "TCPPort"), "22")
        // HistoryList is not a known key in TCP/IP section
        XCTAssertNil(INISerializer.getValue(from: filtered, section: "TCP/IP", key: "HistoryList"))
        XCTAssertEqual(skipped.count, 1)
    }

    // MARK: - Empty INI

    func testFilterEmptyINI() {
        let ini = ""
        let (sections, _) = INISerializer.parse(ini)
        let (filtered, skipped) = mgr.filterUnknownKeys(sections)
        XCTAssertEqual(filtered.count, 0)
        XCTAssertEqual(skipped.count, 0)
    }

    // MARK: - File I/O with unknown keys

    func testLoadConfigWithUnknownKeysSkipsThem() {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnknownKeyTest-\(UUID().uuidString)")
        let mgr = TestableConfigManagerForFilter(directory: testDir)
        defer { try? FileManager.default.removeItem(at: testDir) }

        try! mgr.ensureDirectory()

        // Write an INI with mixed known + unknown keys
        let ini = """
        [Tera Term]
        Version=5.6
        FontName=Monaco
        FontSize=16
        VTFont=Terminal,0,-13,128
        CygwinDirectory=C:\\cygwin
        TerminalWidth=100

        [TCP/IP]
        HostName=test.host
        TCPPort=2222
        """
        try! ini.write(to: mgr.iniFileURL, atomically: true, encoding: .utf8)

        let config = mgr.loadConfig()

        // Known keys loaded correctly
        XCTAssertEqual(config.fontName, "Monaco")
        XCTAssertEqual(config.fontSize, 16)
        XCTAssertEqual(config.terminalWidth, 100)
        XCTAssertEqual(config.hostName, "test.host")
        XCTAssertEqual(config.tcpPort, 2222)
    }
}

/// Testable subclass for unknown-key filtering tests.
private class TestableConfigManagerForFilter: ConfigPersistenceManager {
    private let _dir: URL
    init(directory: URL) { _dir = directory }
    override var appSupportDirectory: URL { _dir }
}

// MARK: - Extended Round-Trip Tests

final class ExtendedConfigRoundTripTests: XCTestCase {

    let mgr = ConfigPersistenceManager()

    /// Helper: modify, encode, decode, and return decoded config.
    private func roundTrip(_ modify: (inout TeraTermConfig) -> Void) -> TeraTermConfig {
        var config = TeraTermConfig()
        modify(&config)
        let sections = mgr.encode(config)
        return mgr.decode(sections: sections)
    }

    // MARK: - Terminal Emulation

    func testTerminalEmulationRoundTrip() {
        let d = roundTrip { c in
            c.terminalID = "VT100"
            c.terminalWidth = 132
            c.terminalHeight = 48
            c.termIsWin = true
            c.autoWinResize = true
            c.termType = "vt100"
            c.answerback = "HELLO"
            c.terminalUID = "AABBCCDD"
            c.terminalSpeed = "115200"
        }
        XCTAssertEqual(d.terminalID, "VT100")
        XCTAssertEqual(d.terminalWidth, 132)
        XCTAssertEqual(d.terminalHeight, 48)
        XCTAssertTrue(d.termIsWin)
        XCTAssertTrue(d.autoWinResize)
        XCTAssertEqual(d.termType, "vt100")
        XCTAssertEqual(d.answerback, "HELLO")
        XCTAssertEqual(d.terminalUID, "AABBCCDD")
        XCTAssertEqual(d.terminalSpeed, "115200")
    }

    // MARK: - New-line & Encoding

    func testNewLineAndEncodingRoundTrip() {
        let d = roundTrip { c in
            c.crReceive = 2
            c.crSend = 1
            c.encoding = "SJIS"
            c.sendEncoding = "EUC"
            c.katakanaReceive = "7"
            c.katakanaSend = "7"
            c.kanjiIn = "@"
            c.kanjiOut = "B"
        }
        XCTAssertEqual(d.crReceive, 2)
        XCTAssertEqual(d.crSend, 1)
        XCTAssertEqual(d.encoding, "SJIS")
        XCTAssertEqual(d.sendEncoding, "EUC")
        XCTAssertEqual(d.katakanaReceive, "7")
        XCTAssertEqual(d.katakanaSend, "7")
        XCTAssertEqual(d.kanjiIn, "@")
        XCTAssertEqual(d.kanjiOut, "B")
    }

    // MARK: - Cursor & Window

    func testCursorAndWindowRoundTrip() {
        let d = roundTrip { c in
            c.cursorShape = 2
            c.cursorBlink = false
            c.killFocusCursor = false
            c.title = "My Terminal"
            c.titleFormat = 5
            c.saveVTWinPos = true
        }
        XCTAssertEqual(d.cursorShape, 2)
        XCTAssertFalse(d.cursorBlink)
        XCTAssertFalse(d.killFocusCursor)
        XCTAssertEqual(d.title, "My Terminal")
        XCTAssertEqual(d.titleFormat, 5)
        XCTAssertTrue(d.saveVTWinPos)
    }

    // MARK: - Scroll

    func testScrollRoundTrip() {
        let d = roundTrip { c in
            c.enableScrollBuffer = false
            c.scrollBufferSize = 50000
            c.scrollBufferMax = 1000000
            c.scrollThreshold = 24
            c.scrollWindowClearScreen = false
        }
        XCTAssertFalse(d.enableScrollBuffer)
        XCTAssertEqual(d.scrollBufferSize, 50000)
        XCTAssertEqual(d.scrollBufferMax, 1000000)
        XCTAssertEqual(d.scrollThreshold, 24)
        XCTAssertFalse(d.scrollWindowClearScreen)
    }

    // MARK: - Color

    func testColorRoundTrip() {
        let d = roundTrip { c in
            c.vtColor = "0,0,0,255,255,255"
            c.vtBoldColor = "255,0,0,0,0,0"
            c.vtBlinkColor = "0,255,0,0,0,0"
            c.vtReverseColor = "0,0,255,255,255,255"
            c.vtUnderlineColor = "128,128,128,0,0,0"
            c.urlColor = "0,128,255,255,255,255"
            c.tekColor = "255,255,0,0,0,0"
            c.ansiColor = "0,0,0,1,1,1"
            c.enableBoldColor = false
            c.enableBlinkColor = false
            c.enableReverseColor = true
            c.enableURLColor = false
            c.enableANSIColor = false
            c.pcBoldColor = true
            c.enableAixtermColors = true
            c.enableXterm256Colors = false
            c.useTextColor = true
            c.useStandardBGColor = true
            c.tekColorEmulation = true
        }
        XCTAssertEqual(d.vtColor, "0,0,0,255,255,255")
        XCTAssertEqual(d.vtBoldColor, "255,0,0,0,0,0")
        XCTAssertEqual(d.vtBlinkColor, "0,255,0,0,0,0")
        XCTAssertEqual(d.vtReverseColor, "0,0,255,255,255,255")
        XCTAssertEqual(d.vtUnderlineColor, "128,128,128,0,0,0")
        XCTAssertEqual(d.urlColor, "0,128,255,255,255,255")
        XCTAssertEqual(d.tekColor, "255,255,0,0,0,0")
        XCTAssertEqual(d.ansiColor, "0,0,0,1,1,1")
        XCTAssertFalse(d.enableBoldColor)
        XCTAssertFalse(d.enableBlinkColor)
        XCTAssertTrue(d.enableReverseColor)
        XCTAssertFalse(d.enableURLColor)
        XCTAssertFalse(d.enableANSIColor)
        XCTAssertTrue(d.pcBoldColor)
        XCTAssertTrue(d.enableAixtermColors)
        XCTAssertFalse(d.enableXterm256Colors)
        XCTAssertTrue(d.useTextColor)
        XCTAssertTrue(d.useStandardBGColor)
        XCTAssertTrue(d.tekColorEmulation)
    }

    // MARK: - Font

    func testFontRoundTrip() {
        let d = roundTrip { c in
            c.fontName = "SF Mono"
            c.fontSize = 12
            c.tekFont = "Courier,0,-13,0"
            c.enableBoldFont = false
            c.enableURLUnderline = false
            c.enableUnderlineDecoration = false
            c.enableUnderlineColor = false
            c.vtFontSpace = "1,2,3,4"
            c.fontQuality = "cleartype"
            c.fontScaling = true
            c.drawingResizedFont = false
            c.dialogFont = "Helvetica,12,0"
            c.drawingAPI = "DirectWrite"
            c.codePage = 65001
        }
        XCTAssertEqual(d.fontName, "SF Mono")
        XCTAssertEqual(d.fontSize, 12)
        XCTAssertEqual(d.tekFont, "Courier,0,-13,0")
        XCTAssertFalse(d.enableBoldFont)
        XCTAssertFalse(d.enableURLUnderline)
        XCTAssertFalse(d.enableUnderlineDecoration)
        XCTAssertFalse(d.enableUnderlineColor)
        XCTAssertEqual(d.vtFontSpace, "1,2,3,4")
        XCTAssertEqual(d.fontQuality, "cleartype")
        XCTAssertTrue(d.fontScaling)
        XCTAssertFalse(d.drawingResizedFont)
        XCTAssertEqual(d.dialogFont, "Helvetica,12,0")
        XCTAssertEqual(d.drawingAPI, "DirectWrite")
        XCTAssertEqual(d.codePage, 65001)
    }

    // MARK: - Keyboard

    func testKeyboardRoundTrip() {
        let d = roundTrip { c in
            c.bsKey = 127
            c.deleteKey = 8
            c.metaKey = 2
            c.meta8Bit = "raw"
            c.disableAppKeypad = true
            c.disableAppCursor = true
            c.strictKeyMapping = true
            c.russKeyb = "jcuken"
            c.cursorChangeIME = true
        }
        XCTAssertEqual(d.bsKey, 127)
        XCTAssertEqual(d.deleteKey, 8)
        XCTAssertEqual(d.metaKey, 2)
        XCTAssertEqual(d.meta8Bit, "raw")
        XCTAssertTrue(d.disableAppKeypad)
        XCTAssertTrue(d.disableAppCursor)
        XCTAssertTrue(d.strictKeyMapping)
        XCTAssertEqual(d.russKeyb, "jcuken")
        XCTAssertTrue(d.cursorChangeIME)
    }

    // MARK: - Beep

    func testBeepRoundTrip() {
        let d = roundTrip { c in
            c.beep = 2
            c.beepOnConnect = true
            c.beepOverUsedCount = 10
            c.beepOverUsedTime = 5
            c.beepSuppressTime = 10
            c.beepVBellWait = 20
            c.notifySound = false
        }
        XCTAssertEqual(d.beep, 2)
        XCTAssertTrue(d.beepOnConnect)
        XCTAssertEqual(d.beepOverUsedCount, 10)
        XCTAssertEqual(d.beepOverUsedTime, 5)
        XCTAssertEqual(d.beepSuppressTime, 10)
        XCTAssertEqual(d.beepVBellWait, 20)
        XCTAssertFalse(d.notifySound)
    }

    // MARK: - Connection

    func testConnectionRoundTrip() {
        let d = roundTrip { c in
            c.telnet = false
            c.tcpPort = 22
            c.telPort = 2323
            c.autoWindowClose = false
            c.hostHistory = true
            c.connectingTimeout = 30
            c.telAutoDetect = false
            c.telBin = true
            c.telEcho = true
            c.tcpKeepAliveInterval = 60
            c.tcpLocalEcho = true
            c.tcpCRSend = "CR"
            c.disableTCPEchoCR = true
        }
        XCTAssertFalse(d.telnet)
        XCTAssertEqual(d.tcpPort, 22)
        XCTAssertEqual(d.telPort, 2323)
        XCTAssertFalse(d.autoWindowClose)
        XCTAssertTrue(d.hostHistory)
        XCTAssertEqual(d.connectingTimeout, 30)
        XCTAssertFalse(d.telAutoDetect)
        XCTAssertTrue(d.telBin)
        XCTAssertTrue(d.telEcho)
        XCTAssertEqual(d.tcpKeepAliveInterval, 60)
        XCTAssertTrue(d.tcpLocalEcho)
        XCTAssertEqual(d.tcpCRSend, "CR")
        XCTAssertTrue(d.disableTCPEchoCR)
    }

    // MARK: - Serial

    func testSerialRoundTrip() {
        let d = roundTrip { c in
            c.serialPort = "/dev/cu.usbserial"
            c.baudRate = 115200
            c.dataBits = 7
            c.parity = 1
            c.stopBits = 2
            c.flowControl = 2
            c.serialDelayPerChar = 5
            c.serialDelayPerLine = 100
            c.clearComBuffOnOpen = false
            c.waitCom = true
            c.autoComPortReconnect = false
            c.autoComPortReconnectDelayNormal = 1000
            c.autoComPortReconnectDelayIllegal = 5000
            c.autoComPortReconnectRetryInterval = 2000
            c.autoComPortReconnectRetryCount = 5
        }
        XCTAssertEqual(d.serialPort, "/dev/cu.usbserial")
        XCTAssertEqual(d.baudRate, 115200)
        XCTAssertEqual(d.dataBits, 7)
        XCTAssertEqual(d.parity, 1)
        XCTAssertEqual(d.stopBits, 2)
        XCTAssertEqual(d.flowControl, 2)
        XCTAssertEqual(d.serialDelayPerChar, 5)
        XCTAssertEqual(d.serialDelayPerLine, 100)
        XCTAssertFalse(d.clearComBuffOnOpen)
        XCTAssertTrue(d.waitCom)
        XCTAssertFalse(d.autoComPortReconnect)
        XCTAssertEqual(d.autoComPortReconnectDelayNormal, 1000)
        XCTAssertEqual(d.autoComPortReconnectDelayIllegal, 5000)
        XCTAssertEqual(d.autoComPortReconnectRetryInterval, 2000)
        XCTAssertEqual(d.autoComPortReconnectRetryCount, 5)
    }

    // MARK: - Log

    func testLogRoundTrip() {
        let d = roundTrip { c in
            c.logAutoStart = true
            c.logDefaultName = "session.log"
            c.logDefaultPath = "/tmp/logs"
            c.logTimestamp = true
            c.logTimestampFormat = "%H:%M:%S"
            c.logTimestampType = "UTC"
            c.logPlainText = false
            c.logBinary = true
            c.logAppend = true
            c.logHideDialog = true
            c.logIncludeScreenBuffer = true
            c.logRotateEnabled = 1
            c.logRotateSize = 1048576
            c.logRotateSizeType = 2
            c.logRotateStep = 5
            c.deferredLogWriteMode = false
            c.logViewEditor = "/usr/bin/vi"
            c.logEditorArguments = "-R"
            c.logBOM = true
        }
        XCTAssertTrue(d.logAutoStart)
        XCTAssertEqual(d.logDefaultName, "session.log")
        XCTAssertEqual(d.logDefaultPath, "/tmp/logs")
        XCTAssertTrue(d.logTimestamp)
        XCTAssertEqual(d.logTimestampFormat, "%H:%M:%S")
        XCTAssertEqual(d.logTimestampType, "UTC")
        XCTAssertFalse(d.logPlainText)
        XCTAssertTrue(d.logBinary)
        XCTAssertTrue(d.logAppend)
        XCTAssertTrue(d.logHideDialog)
        XCTAssertTrue(d.logIncludeScreenBuffer)
        XCTAssertEqual(d.logRotateEnabled, 1)
        XCTAssertEqual(d.logRotateSize, 1048576)
        XCTAssertEqual(d.logRotateSizeType, 2)
        XCTAssertEqual(d.logRotateStep, 5)
        XCTAssertFalse(d.deferredLogWriteMode)
        XCTAssertEqual(d.logViewEditor, "/usr/bin/vi")
        XCTAssertEqual(d.logEditorArguments, "-R")
        XCTAssertTrue(d.logBOM)
    }

    // MARK: - File Transfer

    func testFileTransferRoundTrip() {
        let d = roundTrip { c in
            c.transBin = true
            c.xmodemOption = "crc"
            c.xmodemBin = false
            c.xModemRcvCommand = "rx"
            c.yModemRcvCommand = "rb -y"
            c.zmodemDataLen = 2048
            c.zmodemWindowSize = 65535
            c.zModemRcvCommand = "rz -y"
            c.zmodemAutoReceive = true
            c.zmodemEscCtl = true
            c.fileTransferFolder = "/home/user/downloads"
            c.fileSendFilter = "*.txt"
            c.scpSendDir = "/remote/dir"
            c.ftHideDialog = true
            c.autoFileRename = true
            c.confirmFileDragAndDrop = false
        }
        XCTAssertTrue(d.transBin)
        XCTAssertEqual(d.xmodemOption, "crc")
        XCTAssertFalse(d.xmodemBin)
        XCTAssertEqual(d.xModemRcvCommand, "rx")
        XCTAssertEqual(d.yModemRcvCommand, "rb -y")
        XCTAssertEqual(d.zmodemDataLen, 2048)
        XCTAssertEqual(d.zmodemWindowSize, 65535)
        XCTAssertEqual(d.zModemRcvCommand, "rz -y")
        XCTAssertTrue(d.zmodemAutoReceive)
        XCTAssertTrue(d.zmodemEscCtl)
        XCTAssertEqual(d.fileTransferFolder, "/home/user/downloads")
        XCTAssertEqual(d.fileSendFilter, "*.txt")
        XCTAssertEqual(d.scpSendDir, "/remote/dir")
        XCTAssertTrue(d.ftHideDialog)
        XCTAssertTrue(d.autoFileRename)
        XCTAssertFalse(d.confirmFileDragAndDrop)
    }

    // MARK: - Control Sequences

    func testControlSequencesRoundTrip() {
        let d = roundTrip { c in
            c.accept8BitCtrl = false
            c.allowWrongSequence = true
            c.titleChangeRequest = "ahead"
            c.windowControlSequence = false
            c.cursorControlSequence = true
            c.windowInfoReportSequence = false
            c.titleReportRequest = "accept"
            c.clipboardAccessFromRemote = "on"
            c.notifyClipboardAccess = false
            c.acceptScrollBufferClear = false
            c.clearOnResize = true
            c.alternateScreenBuffer = false
            c.enableStatusLine = false
            c.enableLineMode = false
            c.disablePrintSequence = true
            c.useInvalidDECRQSSResponse = true
            c.tabStopModifySequence = "off"
            c.iso2022ShiftFunction = "off"
            c.maxOSCBufferSize = 8192
            c.send8BitCtrl = true
        }
        XCTAssertFalse(d.accept8BitCtrl)
        XCTAssertTrue(d.allowWrongSequence)
        XCTAssertEqual(d.titleChangeRequest, "ahead")
        XCTAssertFalse(d.windowControlSequence)
        XCTAssertTrue(d.cursorControlSequence)
        XCTAssertFalse(d.windowInfoReportSequence)
        XCTAssertEqual(d.titleReportRequest, "accept")
        XCTAssertEqual(d.clipboardAccessFromRemote, "on")
        XCTAssertFalse(d.notifyClipboardAccess)
        XCTAssertFalse(d.acceptScrollBufferClear)
        XCTAssertTrue(d.clearOnResize)
        XCTAssertFalse(d.alternateScreenBuffer)
        XCTAssertFalse(d.enableStatusLine)
        XCTAssertFalse(d.enableLineMode)
        XCTAssertTrue(d.disablePrintSequence)
        XCTAssertTrue(d.useInvalidDECRQSSResponse)
        XCTAssertEqual(d.tabStopModifySequence, "off")
        XCTAssertEqual(d.iso2022ShiftFunction, "off")
        XCTAssertEqual(d.maxOSCBufferSize, 8192)
        XCTAssertTrue(d.send8BitCtrl)
    }

    // MARK: - Copy & Paste

    func testCopyPasteRoundTrip() {
        let d = roundTrip { c in
            c.autoTextCopy = false
            c.continuedLineCopy = false
            c.leftClickOnlySelection = false
            c.enableSelectionOnActivate = false
            c.disableRightClickPaste = true
            c.disableMiddleClickPaste = false
            c.confirmRightClickPaste = true
            c.clipboardConfirmPaste = false
            c.confirmPasteNewLine = false
            c.dangerousKeywordFile = "/etc/dangerous.txt"
            c.trimTrailingNewline = true
            c.pasteDelay = 50
            c.delimiterList = "$20$09"
            c.delimDBCS = false
            c.mouseSelectStartDelay = 100
        }
        XCTAssertFalse(d.autoTextCopy)
        XCTAssertFalse(d.continuedLineCopy)
        XCTAssertFalse(d.leftClickOnlySelection)
        XCTAssertFalse(d.enableSelectionOnActivate)
        XCTAssertTrue(d.disableRightClickPaste)
        XCTAssertFalse(d.disableMiddleClickPaste)
        XCTAssertTrue(d.confirmRightClickPaste)
        XCTAssertFalse(d.clipboardConfirmPaste)
        XCTAssertFalse(d.confirmPasteNewLine)
        XCTAssertEqual(d.dangerousKeywordFile, "/etc/dangerous.txt")
        XCTAssertTrue(d.trimTrailingNewline)
        XCTAssertEqual(d.pasteDelay, 50)
        XCTAssertEqual(d.delimiterList, "$20$09")
        XCTAssertFalse(d.delimDBCS)
        XCTAssertEqual(d.mouseSelectStartDelay, 100)
    }

    // MARK: - Mouse

    func testMouseRoundTrip() {
        let d = roundTrip { c in
            c.mouseTracking = false
            c.mouseWheelScrollLines = 5
            c.mouseCursorType = "ARROW"
            c.translateWheelToCursor = false
            c.disableControlKeyMouseEvent = false
            c.disableWheelToCursorByCtrl = false
        }
        XCTAssertFalse(d.mouseTracking)
        XCTAssertEqual(d.mouseWheelScrollLines, 5)
        XCTAssertEqual(d.mouseCursorType, "ARROW")
        XCTAssertFalse(d.translateWheelToCursor)
        XCTAssertFalse(d.disableControlKeyMouseEvent)
        XCTAssertFalse(d.disableWheelToCursorByCtrl)
    }

    // MARK: - Window Opacity & Broadcast

    func testOpacityAndBroadcastRoundTrip() {
        let d = roundTrip { c in
            c.windowOpacityInactive = 200
            c.windowOpacityActive = 230
            c.broadcastHistory = true
            c.acceptBroadcast = false
            c.maxBroadcastHistory = 50
        }
        XCTAssertEqual(d.windowOpacityInactive, 200)
        XCTAssertEqual(d.windowOpacityActive, 230)
        XCTAssertTrue(d.broadcastHistory)
        XCTAssertFalse(d.acceptBroadcast)
        XCTAssertEqual(d.maxBroadcastHistory, 50)
    }

    // MARK: - Debug & URL & Unicode

    func testDebugURLUnicodeRoundTrip() {
        let d = roundTrip { c in
            c.debugCharInfoPopup = true
            c.debugModes = "hex"
            c.enableClickableUrl = true
            c.joinSplitURL = true
            c.joinSplitURLIgnoreEOLChar = "/"
            c.unicodeAmbiguousWidth = 2
            c.unicodeEmojiOverride = true
            c.unicodeEmojiWidth = 2
            c.unicodeToDecSpMapping = 1
            c.decSpMappingDir = 0
        }
        XCTAssertTrue(d.debugCharInfoPopup)
        XCTAssertEqual(d.debugModes, "hex")
        XCTAssertTrue(d.enableClickableUrl)
        XCTAssertTrue(d.joinSplitURL)
        XCTAssertEqual(d.joinSplitURLIgnoreEOLChar, "/")
        XCTAssertEqual(d.unicodeAmbiguousWidth, 2)
        XCTAssertTrue(d.unicodeEmojiOverride)
        XCTAssertEqual(d.unicodeEmojiWidth, 2)
        XCTAssertEqual(d.unicodeToDecSpMapping, 1)
        XCTAssertEqual(d.decSpMappingDir, 0)
    }

    // MARK: - Sendfile & Receivefile

    func testSendfileReceivefileRoundTrip() {
        let d = roundTrip { c in
            c.sendfileDelayType = "PerChar"
            c.sendfileDelayTick = 100
            c.sendfileSize = 8192
            c.sendfileSequential = true
            c.sendfileSkipOptionDialog = true
            c.fileReceiveFilter = "*.bin"
            c.receivefileSkipOptionDialog = true
            c.receivefileAutoStopWaitTime = 10
        }
        XCTAssertEqual(d.sendfileDelayType, "PerChar")
        XCTAssertEqual(d.sendfileDelayTick, 100)
        XCTAssertEqual(d.sendfileSize, 8192)
        XCTAssertTrue(d.sendfileSequential)
        XCTAssertTrue(d.sendfileSkipOptionDialog)
        XCTAssertEqual(d.fileReceiveFilter, "*.bin")
        XCTAssertTrue(d.receivefileSkipOptionDialog)
        XCTAssertEqual(d.receivefileAutoStopWaitTime, 10)
    }

    // MARK: - Protocol Logs & Legacy Protocols

    func testProtocolLogsRoundTrip() {
        let d = roundTrip { c in
            c.telLog = true
            c.xmodemLog = true
            c.ymodemLog = true
            c.zmodemLog = true
            c.kmtLog = true
            c.kmtLongPacket = true
            c.kmtFileAttr = true
            c.bpAuto = true
            c.bpEscCtl = true
            c.bpLog = true
            c.qvLog = true
            c.qvWinSize = 16
        }
        XCTAssertTrue(d.telLog)
        XCTAssertTrue(d.xmodemLog)
        XCTAssertTrue(d.ymodemLog)
        XCTAssertTrue(d.zmodemLog)
        XCTAssertTrue(d.kmtLog)
        XCTAssertTrue(d.kmtLongPacket)
        XCTAssertTrue(d.kmtFileAttr)
        XCTAssertTrue(d.bpAuto)
        XCTAssertTrue(d.bpEscCtl)
        XCTAssertTrue(d.bpLog)
        XCTAssertTrue(d.qvLog)
        XCTAssertEqual(d.qvWinSize, 16)
    }

    // MARK: - Other Special Options

    func testSpecialOptionsRoundTrip() {
        let d = roundTrip { c in
            c.autoWinSwitch = true
            c.ctrlInKanji = false
            c.fixedJIS = true
            c.backWrap = true
            c.autoInvoke = true
            c.confirmOnDisconnect = false
            c.vtCompatTab = true
            c.tekIcon = "Custom"
            c.tekGINMouseCode = 64
            c.sendBreakTime = 500
            c.wait4allMacroCommand = true
            c.clearScreenOnCloseConnection = true
            c.fileSendHighSpeedMode = false
            c.fallbackToCP932 = true
            c.startupMacro = "startup.ttl"
            c.autoScrollOnlyInBottomLine = true
            c.lockTUID = false
            c.cornerRounding = true
            c.iniAutoBackup = false
            c.bracketedPasteMode = false
            c.bracketedControlOnly = true
            c.port = "serial"
            c.language = "ja"
        }
        XCTAssertTrue(d.autoWinSwitch)
        XCTAssertFalse(d.ctrlInKanji)
        XCTAssertTrue(d.fixedJIS)
        XCTAssertTrue(d.backWrap)
        XCTAssertTrue(d.autoInvoke)
        XCTAssertFalse(d.confirmOnDisconnect)
        XCTAssertTrue(d.vtCompatTab)
        XCTAssertEqual(d.tekIcon, "Custom")
        XCTAssertEqual(d.tekGINMouseCode, 64)
        XCTAssertEqual(d.sendBreakTime, 500)
        XCTAssertTrue(d.wait4allMacroCommand)
        XCTAssertTrue(d.clearScreenOnCloseConnection)
        XCTAssertFalse(d.fileSendHighSpeedMode)
        XCTAssertTrue(d.fallbackToCP932)
        XCTAssertEqual(d.startupMacro, "startup.ttl")
        XCTAssertTrue(d.autoScrollOnlyInBottomLine)
        XCTAssertFalse(d.lockTUID)
        XCTAssertTrue(d.cornerRounding)
        XCTAssertFalse(d.iniAutoBackup)
        XCTAssertFalse(d.bracketedPasteMode)
        XCTAssertTrue(d.bracketedControlOnly)
        XCTAssertEqual(d.port, "serial")
        XCTAssertEqual(d.language, "ja")
    }

    // MARK: - Timeouts

    func testTimeoutsRoundTrip() {
        let d = roundTrip { c in
            c.xmodemTimeouts = "15,5,15,30,90"
            c.ymodemTimeouts = "15,5,15,30,90"
            c.zmodemTimeouts = "15,0,15,5"
        }
        XCTAssertEqual(d.xmodemTimeouts, "15,5,15,30,90")
        XCTAssertEqual(d.ymodemTimeouts, "15,5,15,30,90")
        XCTAssertEqual(d.zmodemTimeouts, "15,0,15,5")
    }

    // MARK: - TEK

    func testTEKRoundTrip() {
        let d = roundTrip { c in
            c.tekPos = "100,200"
            c.tekPPI = "96,96"
        }
        XCTAssertEqual(d.tekPos, "100,200")
        XCTAssertEqual(d.tekPPI, "96,96")
    }

    // MARK: - [BG] Section

    func testBGSectionRoundTrip() {
        let d = roundTrip { c in
            c.bgEnable = 1
            c.bgThemeFile = "/path/to/theme.ini"
            c.bgSPIPath = "/path/to/spi"
            c.bgFastSizeMove = 1
            c.bgNoFrame = 1
        }
        XCTAssertEqual(d.bgEnable, 1)
        XCTAssertEqual(d.bgThemeFile, "/path/to/theme.ini")
        XCTAssertEqual(d.bgSPIPath, "/path/to/spi")
        XCTAssertEqual(d.bgFastSizeMove, 1)
        XCTAssertEqual(d.bgNoFrame, 1)
    }

    // MARK: - [TTSSH] Section

    func testTTSSHSectionRoundTrip() {
        let d = roundTrip { c in
            c.sshVersion = 2
            c.sshDefaultAuthMethod = 3
            c.sshDefaultUserName = "testuser"
            c.sshDefaultUserNameMode = 1
            c.sshDefaultForwarding = "L8080:localhost:80"
            c.sshHeartBeat = 30
            c.sshForwardAgent = true
            c.sshConfirmForwardAgent = false
            c.sshNotifyForwardAgent = true
            c.sshVerifyHostKeyDNS = true
            c.sshKnownHostsFile = "~/.ssh/known_hosts"
            c.sshKnownHostsReadOnlyFile = "/etc/ssh/known_hosts"
            c.sshHostKeyRotation = 1
            c.sshLogLevel = 3
            c.sshCompressionLevel = 6
            c.sshXForwarding = true
            c.sshCheckAuthBeforeLogin = true
            c.sshCipherOrder = "aes256-ctr,aes128-ctr"
            c.sshKexOrder = "curve25519-sha256"
            c.sshHostKeyOrder = "ssh-ed25519,rsa-sha2-512"
            c.sshMACOrder = "hmac-sha2-256"
            c.sshCompOrder = "zlib@openssh.com,none"
        }
        XCTAssertEqual(d.sshVersion, 2)
        XCTAssertEqual(d.sshDefaultAuthMethod, 3)
        XCTAssertEqual(d.sshDefaultUserName, "testuser")
        XCTAssertEqual(d.sshDefaultUserNameMode, 1)
        XCTAssertEqual(d.sshDefaultForwarding, "L8080:localhost:80")
        XCTAssertEqual(d.sshHeartBeat, 30)
        XCTAssertTrue(d.sshForwardAgent)
        XCTAssertFalse(d.sshConfirmForwardAgent)
        XCTAssertTrue(d.sshNotifyForwardAgent)
        XCTAssertTrue(d.sshVerifyHostKeyDNS)
        XCTAssertEqual(d.sshKnownHostsFile, "~/.ssh/known_hosts")
        XCTAssertEqual(d.sshKnownHostsReadOnlyFile, "/etc/ssh/known_hosts")
        XCTAssertEqual(d.sshHostKeyRotation, 1)
        XCTAssertEqual(d.sshLogLevel, 3)
        XCTAssertEqual(d.sshCompressionLevel, 6)
        XCTAssertTrue(d.sshXForwarding)
        XCTAssertTrue(d.sshCheckAuthBeforeLogin)
        XCTAssertEqual(d.sshCipherOrder, "aes256-ctr,aes128-ctr")
        XCTAssertEqual(d.sshKexOrder, "curve25519-sha256")
        XCTAssertEqual(d.sshHostKeyOrder, "ssh-ed25519,rsa-sha2-512")
        XCTAssertEqual(d.sshMACOrder, "hmac-sha2-256")
        XCTAssertEqual(d.sshCompOrder, "zlib@openssh.com,none")
    }

    // MARK: - [Proxy] Section

    func testProxySectionRoundTrip() {
        let d = roundTrip { c in
            c.proxyType = 1
            c.proxyHost = "proxy.example.com"
            c.proxyPort = 8080
            c.proxyUser = "proxyuser"
            c.proxyPass = "proxypass123"
        }
        XCTAssertEqual(d.proxyType, 1)
        XCTAssertEqual(d.proxyHost, "proxy.example.com")
        XCTAssertEqual(d.proxyPort, 8080)
        XCTAssertEqual(d.proxyUser, "proxyuser")
        XCTAssertEqual(d.proxyPass, "proxypass123")
    }

    // MARK: - Default Values

    func testDefaultValues() {
        let c = TeraTermConfig()

        // Terminal
        XCTAssertEqual(c.terminalID, "VT220")
        XCTAssertEqual(c.terminalWidth, 80)
        XCTAssertEqual(c.terminalHeight, 24)
        XCTAssertFalse(c.termIsWin)
        XCTAssertFalse(c.autoWinResize)
        XCTAssertEqual(c.termType, "xterm")
        XCTAssertEqual(c.terminalSpeed, "38400")

        // Encoding
        XCTAssertEqual(c.encoding, "UTF-8")
        XCTAssertEqual(c.katakanaReceive, "8")

        // Cursor
        XCTAssertEqual(c.cursorShape, 0)
        XCTAssertTrue(c.cursorBlink)

        // Scroll
        XCTAssertTrue(c.enableScrollBuffer)
        XCTAssertEqual(c.scrollBufferSize, 10000)
        XCTAssertEqual(c.scrollBufferMax, 500000)

        // Color
        XCTAssertTrue(c.enableBoldColor)
        XCTAssertTrue(c.enableANSIColor)
        XCTAssertTrue(c.enableXterm256Colors)
        XCTAssertFalse(c.enableAixtermColors)

        // Font
        XCTAssertEqual(c.fontName, "Menlo")
        XCTAssertEqual(c.fontSize, 14)
        XCTAssertTrue(c.enableBoldFont)

        // Keyboard
        XCTAssertFalse(c.disableAppKeypad)
        XCTAssertFalse(c.disableAppCursor)

        // Beep
        XCTAssertEqual(c.beep, 1)
        XCTAssertFalse(c.beepOnConnect)
        XCTAssertTrue(c.notifySound)

        // Connection
        XCTAssertTrue(c.telnet)
        XCTAssertEqual(c.tcpPort, 23)
        XCTAssertTrue(c.autoWindowClose)
        XCTAssertEqual(c.tcpKeepAliveInterval, 300)

        // Log
        XCTAssertFalse(c.logAutoStart)
        XCTAssertTrue(c.logPlainText)
        XCTAssertEqual(c.logViewEditor, "open")

        // Copy & Paste
        XCTAssertTrue(c.autoTextCopy)
        XCTAssertTrue(c.continuedLineCopy)
        XCTAssertTrue(c.clipboardConfirmPaste)
        XCTAssertEqual(c.pasteDelay, 5)

        // Mouse
        XCTAssertTrue(c.mouseTracking)
        XCTAssertEqual(c.mouseWheelScrollLines, 3)

        // SSH
        XCTAssertEqual(c.sshVersion, 2)
        XCTAssertEqual(c.sshHeartBeat, 60)
        XCTAssertFalse(c.sshForwardAgent)

        // Proxy
        XCTAssertEqual(c.proxyType, 0)

        // Misc
        XCTAssertTrue(c.confirmOnDisconnect)
        XCTAssertTrue(c.bracketedPasteMode)
        XCTAssertFalse(c.bracketedControlOnly)
    }

    // MARK: - PrinterCtrlSequence Inversion

    func testPrinterCtrlSequenceInversion() {
        // PrinterCtrlSequence=on means disablePrintSequence=false
        let d1 = roundTrip { c in
            c.disablePrintSequence = false
        }
        XCTAssertFalse(d1.disablePrintSequence)

        // PrinterCtrlSequence=off means disablePrintSequence=true
        let d2 = roundTrip { c in
            c.disablePrintSequence = true
        }
        XCTAssertTrue(d2.disablePrintSequence)
    }

    // MARK: - Full Encode Contains All Sections

    func testEncodeContainsAllSections() {
        let config = TeraTermConfig()
        let sections = mgr.encode(config)
        let sectionNames = sections.map { $0.name }

        XCTAssertTrue(sectionNames.contains("Tera Term"))
        XCTAssertTrue(sectionNames.contains("TCP/IP"))
        XCTAssertTrue(sectionNames.contains("Serial"))
        XCTAssertTrue(sectionNames.contains("BG"))
        XCTAssertTrue(sectionNames.contains("TTSSH"))
        XCTAssertTrue(sectionNames.contains("Proxy"))
    }

    // MARK: - INI Text Round-Trip

    func testSerializeDeserializeFullConfig() {
        var config = TeraTermConfig()
        config.sshVersion = 2
        config.sshDefaultUserName = "admin"
        config.proxyHost = "proxy.local"
        config.bgEnable = 1
        config.bgThemeFile = "ocean.ini"

        let sections = mgr.encode(config)
        let text = INISerializer.serialize(sections, lineEnding: .lf)
        let (parsed, _) = INISerializer.parse(text)
        let decoded = mgr.decode(sections: parsed)

        XCTAssertEqual(decoded.sshVersion, 2)
        XCTAssertEqual(decoded.sshDefaultUserName, "admin")
        XCTAssertEqual(decoded.proxyHost, "proxy.local")
        XCTAssertEqual(decoded.bgEnable, 1)
        XCTAssertEqual(decoded.bgThemeFile, "ocean.ini")
    }
}

// MARK: - Testable Subclass

/// Overrides the directory to a temp location for isolated testing.
private class TestableConfigManager: ConfigPersistenceManager {
    private let _dir: URL

    init(directory: URL) {
        _dir = directory
    }

    override var appSupportDirectory: URL { _dir }
}
