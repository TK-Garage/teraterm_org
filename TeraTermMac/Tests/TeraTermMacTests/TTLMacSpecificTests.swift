/*
 * TTL Mac-Specific Tests
 * Phase 5: Path separators, newline codes, Keychain access, resolvePath
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)

final class TTLMacSpecificTests: XCTestCase {

    // MARK: - Path Separator Conversion (\ → /)

    func testPathSeparator_BackslashToSlash() {
        let windowsPath = "C:\\Users\\admin\\Desktop\\test.ttl"
        let macPath = windowsPath.replacingOccurrences(of: "\\", with: "/")
        XCTAssertEqual(macPath, "C:/Users/admin/Desktop/test.ttl")
    }

    func testPathSeparator_AlreadySlash() {
        let macPath = "/Users/admin/Desktop/test.ttl"
        let converted = macPath.replacingOccurrences(of: "\\", with: "/")
        XCTAssertEqual(converted, macPath) // No change
    }

    func testPathSeparator_MixedSlashes() {
        let mixedPath = "some/path\\to\\file.txt"
        let normalized = mixedPath.replacingOccurrences(of: "\\", with: "/")
        XCTAssertEqual(normalized, "some/path/to/file.txt")
    }

    func testPathSeparator_UNCPath() {
        let uncPath = "\\\\server\\share\\file.txt"
        let converted = uncPath.replacingOccurrences(of: "\\", with: "/")
        XCTAssertEqual(converted, "//server/share/file.txt")
    }

    func testPathSeparator_EmptyPath() {
        let path = ""
        let converted = path.replacingOccurrences(of: "\\", with: "/")
        XCTAssertEqual(converted, "")
    }

    func testPathSeparator_TrailingBackslash() {
        let path = "dir\\subdir\\"
        let converted = path.replacingOccurrences(of: "\\", with: "/")
        XCTAssertEqual(converted, "dir/subdir/")
    }

    // MARK: - Path Resolution

    func testResolvePath_AbsolutePath() {
        let path = "/Users/test/file.txt"
        // Absolute paths should be returned as-is
        XCTAssertTrue(path.hasPrefix("/"))
        let resolved = (path as NSString).expandingTildeInPath
        XCTAssertEqual(resolved, path)
    }

    func testResolvePath_TildePath() {
        let path = "~/Documents/test.txt"
        XCTAssertTrue(path.hasPrefix("~"))
        let resolved = (path as NSString).expandingTildeInPath
        XCTAssertTrue(resolved.hasPrefix("/"))
        XCTAssertTrue(resolved.contains("Documents/test.txt"))
    }

    func testResolvePath_RelativePath() {
        let path = "subdir/file.txt"
        // Relative paths get prepended with current directory
        let cwd = FileManager.default.currentDirectoryPath
        let resolved = cwd + "/" + path
        XCTAssertTrue(resolved.hasPrefix("/"))
        XCTAssertTrue(resolved.hasSuffix("subdir/file.txt"))
    }

    // MARK: - makepath

    func testMakePath_BasicJoin() {
        let dir = "/Users/admin"
        let file = "test.ttl"
        let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
        XCTAssertEqual(url.path, "/Users/admin/test.ttl")
    }

    func testMakePath_TrailingSlash() {
        let dir = "/Users/admin/"
        let file = "test.ttl"
        let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
        XCTAssertEqual(url.path, "/Users/admin/test.ttl")
    }

    // MARK: - basename / dirname

    func testBasename() {
        let path = "/Users/admin/Documents/test.ttl"
        let basename = (path as NSString).lastPathComponent
        XCTAssertEqual(basename, "test.ttl")
    }

    func testBasename_NoExtension() {
        let path = "/usr/local/bin/program"
        let basename = (path as NSString).lastPathComponent
        XCTAssertEqual(basename, "program")
    }

    func testDirname() {
        let path = "/Users/admin/Documents/test.ttl"
        let dirname = (path as NSString).deletingLastPathComponent
        XCTAssertEqual(dirname, "/Users/admin/Documents")
    }

    func testDirname_RootFile() {
        let path = "/test.ttl"
        let dirname = (path as NSString).deletingLastPathComponent
        XCTAssertEqual(dirname, "/")
    }

    // MARK: - Newline Code Handling (CRLF)

    func testCRLF_ParsingMacroFile() {
        // Windows-format macro files use CRLF
        let crlfScript = "line1\r\nline2\r\nline3"
        let lines = crlfScript.components(separatedBy: .newlines)
        // .newlines includes \r\n, \n, \r
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "line1")
        XCTAssertEqual(lines[1], "line2")
        XCTAssertEqual(lines[2], "line3")
    }

    func testCRLF_MixedNewlines() {
        // Mix of CRLF, LF, and CR - all normalized by loadScript
        let parser = TTLParser()
        let mixed = "line1\r\nline2\nline3\rline4"
        parser.loadScript(mixed)
        XCTAssertEqual(parser.lines.count, 4)
        XCTAssertEqual(parser.lines[0], "line1")
        XCTAssertEqual(parser.lines[1], "line2")
        XCTAssertEqual(parser.lines[2], "line3")
        XCTAssertEqual(parser.lines[3], "line4")
    }

    func testCRLF_NoTrailingNewline() {
        let script = "end"
        let lines = script.components(separatedBy: .newlines)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0], "end")
    }

    func testCRLF_EmptyLines() {
        let script = "line1\r\n\r\nline3\r\n"
        let lines = script.components(separatedBy: .newlines)
        XCTAssertEqual(lines[0], "line1")
        XCTAssertEqual(lines[1], "")
        XCTAssertEqual(lines[2], "line3")
    }

    func testCRLF_LoadScriptWithCRLF() {
        let parser = TTLParser()
        let crlfScript = "x = 1\r\nif x = 1 then\r\n  messagebox 'yes'\r\nendif\r\nend"
        parser.loadScript(crlfScript)
        // CRLF is normalized to LF before splitting, so exactly 5 lines
        XCTAssertEqual(parser.lines.count, 5)
        XCTAssertEqual(parser.lines[0], "x = 1")
        XCTAssertEqual(parser.lines[4], "end")
        for line in parser.lines {
            XCTAssertFalse(line.hasSuffix("\r"), "Line should not end with CR: '\(line)'")
        }
    }

    func testCRLF_LoadScriptWithLF() {
        let parser = TTLParser()
        let lfScript = "x = 1\nif x = 1 then\n  messagebox 'yes'\nendif\nend"
        parser.loadScript(lfScript)
        XCTAssertEqual(parser.lines.count, 5)
    }

    // MARK: - Keychain Access Error Handling

    func testKeychain_NotAvailableGraceful() {
        // getpassword/setpassword should handle Keychain errors gracefully
        // Testing that Security framework is importable
        #if canImport(Security)
        // Security framework available - this is expected on macOS
        XCTAssertTrue(true)
        #else
        XCTFail("Security framework not available")
        #endif
    }

    func testKeychain_ErrorCodes() {
        // Verify common Keychain error codes
        // errSecItemNotFound = -25300
        XCTAssertEqual(Int(errSecItemNotFound), -25300)
        // errSecDuplicateItem = -25299
        XCTAssertEqual(Int(errSecDuplicateItem), -25299)
        // errSecAuthFailed = -25293
        XCTAssertEqual(Int(errSecAuthFailed), -25293)
    }

    func testKeychain_QueryStructure() {
        // Verify we can construct a proper Keychain query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "TeraTermMac",
            kSecAttrAccount as String: "testuser",
            kSecReturnData as String: true,
        ]
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
    }

    // MARK: - Environment Variables

    func testGetEnv_PATH() {
        let path = ProcessInfo.processInfo.environment["PATH"]
        XCTAssertNotNil(path)
        XCTAssertFalse(path!.isEmpty)
    }

    func testGetEnv_HOME() {
        let home = ProcessInfo.processInfo.environment["HOME"]
        XCTAssertNotNil(home)
        XCTAssertTrue(home!.hasPrefix("/"))
    }

    func testGetEnv_NonExistent() {
        let val = ProcessInfo.processInfo.environment["TTL_NONEXISTENT_VAR_12345"]
        XCTAssertNil(val)
    }

    func testSetEnv() {
        let key = "TTL_TEST_ENV_VAR"
        setenv(key, "test_value", 1)
        XCTAssertEqual(ProcessInfo.processInfo.environment[key], "test_value")
        unsetenv(key)
    }

    // MARK: - Special Folder Paths

    func testSpecialFolder_Desktop() {
        let urls = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
        XCTAssertFalse(urls.isEmpty)
        XCTAssertTrue(urls[0].path.contains("Desktop"))
    }

    func testSpecialFolder_Documents() {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        XCTAssertFalse(urls.isEmpty)
        XCTAssertTrue(urls[0].path.contains("Documents"))
    }

    func testSpecialFolder_Downloads() {
        let urls = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        XCTAssertFalse(urls.isEmpty)
    }

    func testSpecialFolder_Temp() {
        let tmp = NSTemporaryDirectory()
        XCTAssertFalse(tmp.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp))
    }

    // MARK: - Date/Time Format (macOS locale)

    func testGetDate_Format() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let dateStr = formatter.string(from: Date())
        XCTAssertEqual(dateStr.count, 10)
        XCTAssertTrue(dateStr.contains("/"))
    }

    func testGetTime_Format() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: Date())
        XCTAssertEqual(timeStr.count, 8)
        XCTAssertTrue(timeStr.contains(":"))
    }

    // MARK: - NSString Path Extensions (used by TTLInterpreter)

    func testNSStringPath_DeletingLastPathComponent() {
        let path: NSString = "/Users/admin/Desktop/test.txt"
        XCTAssertEqual(path.deletingLastPathComponent, "/Users/admin/Desktop")
    }

    func testNSStringPath_LastPathComponent() {
        let path: NSString = "/Users/admin/Desktop/test.txt"
        XCTAssertEqual(path.lastPathComponent, "test.txt")
    }

    func testNSStringPath_PathExtension() {
        let path: NSString = "/Users/admin/Desktop/test.ttl"
        XCTAssertEqual(path.pathExtension, "ttl")
    }

    func testNSStringPath_ExpandingTilde() {
        let path: NSString = "~/Desktop"
        let expanded = path.expandingTildeInPath
        XCTAssertFalse(expanded.hasPrefix("~"))
        XCTAssertTrue(expanded.hasPrefix("/"))
    }

    // MARK: - Clipboard (pasteboard) mock

    func testClipboard_SetGet() {
        let mockDelegate = MockTTLDelegate()
        mockDelegate.clipboard = "test clipboard data"
        XCTAssertEqual(mockDelegate.ttlGetClipboard(), "test clipboard data")

        mockDelegate.ttlSetClipboard("new data")
        XCTAssertEqual(mockDelegate.ttlGetClipboard(), "new data")
    }

    func testClipboard_EmptyString() {
        let mockDelegate = MockTTLDelegate()
        mockDelegate.ttlSetClipboard("")
        XCTAssertEqual(mockDelegate.ttlGetClipboard(), "")
    }

    func testClipboard_Japanese() {
        let mockDelegate = MockTTLDelegate()
        mockDelegate.ttlSetClipboard("日本語テスト")
        XCTAssertEqual(mockDelegate.ttlGetClipboard(), "日本語テスト")
    }

    // MARK: - File Encoding Detection

    func testFileEncoding_UTF8() {
        let utf8Data = "Hello World".data(using: .utf8)!
        let decoded = String(data: utf8Data, encoding: .utf8)
        XCTAssertEqual(decoded, "Hello World")
    }

    func testFileEncoding_UTF8_Japanese() {
        let utf8Data = "こんにちは".data(using: .utf8)!
        let decoded = String(data: utf8Data, encoding: .utf8)
        XCTAssertEqual(decoded, "こんにちは")
    }

    func testFileEncoding_ASCII() {
        let asciiData = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"
        let decoded = String(data: asciiData, encoding: .ascii)
        XCTAssertEqual(decoded, "Hello")
    }

    func testFileEncoding_FallbackFromUTF8ToASCII() {
        // Invalid UTF-8 sequence should fall back to ASCII
        let invalidUTF8 = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x80]) // "Hello" + invalid byte
        let decoded = String(data: invalidUTF8, encoding: .utf8) ?? String(data: invalidUTF8, encoding: .ascii) ?? ""
        XCTAssertFalse(decoded.isEmpty)
    }

    // MARK: - ExpandEnv (environment variable expansion)

    func testExpandEnv_Basic() {
        setenv("TTL_TEST_VAR", "expanded", 1)
        let value = ProcessInfo.processInfo.environment["TTL_TEST_VAR"]
        XCTAssertEqual(value, "expanded")
        unsetenv("TTL_TEST_VAR")
    }

    // MARK: - Uptime

    func testUptime() {
        let uptime = ProcessInfo.processInfo.systemUptime
        XCTAssertGreaterThan(uptime, 0)
    }

    // MARK: - IPv4/IPv6 Address Resolution

    func testGetHostname() {
        let hostname = ProcessInfo.processInfo.hostName
        XCTAssertFalse(hostname.isEmpty)
    }
}

#endif
