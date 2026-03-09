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

// MARK: - Testable Subclass

/// Overrides the directory to a temp location for isolated testing.
private class TestableConfigManager: ConfigPersistenceManager {
    private let _dir: URL

    init(directory: URL) {
        _dir = directory
    }

    override var appSupportDirectory: URL { _dir }
}
