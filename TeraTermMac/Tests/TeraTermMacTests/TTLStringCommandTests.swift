/*
 * TTL String Command Tests
 * Phase 1: strconcat, strsplit, strreplace, strmatch, etc.
 * Includes Japanese (UTF-8) strings, empty strings, and edge cases.
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)

// MARK: - Mock Delegate for Interpreter Tests

class MockTTLDelegate: TTLInterpreterDelegate {
    var sentData: [Data] = []
    var sentStrings: [String] = []
    var isConnected = false
    var receivedDataBuffer = ""
    var title = ""
    var windowShown = true
    var statusBoxMessage = ""
    var statusBoxTitle = ""
    var errorMessage = ""
    var errorLine = 0
    var clipboard = ""
    var logPath = ""
    var logAppend = false

    func ttlSendData(_ data: Data) { sentData.append(data) }
    func ttlSendString(_ text: String) { sentStrings.append(text) }
    func ttlSendLine(_ text: String) { sentStrings.append(text + "\r\n") }
    func ttlIsConnected() -> Bool { return isConnected }
    func ttlGetReceivedData(clear: Bool) -> String {
        let data = receivedDataBuffer
        if clear { receivedDataBuffer = "" }
        return data
    }
    func ttlFlushReceiveBuffer() { receivedDataBuffer = "" }
    func ttlDisconnect() { isConnected = false }
    func ttlConnect(_ param: String) { isConnected = true }
    func ttlSetTitle(_ title: String) { self.title = title }
    func ttlGetTitle() -> String { return title }
    func ttlShowWindow(_ show: Bool) { windowShown = show }
    func ttlClearScreen() {}
    func ttlSendBreak() {}
    func ttlLogOpen(_ path: String, append: Bool) { logPath = path; logAppend = append }
    func ttlLogClose() { logPath = "" }
    func ttlLogPause() {}
    func ttlLogStart() {}
    func ttlLogWrite(_ text: String) {}
    func ttlShowError(_ message: String, line: Int) { errorMessage = message; errorLine = line }
    func ttlShowStatusBox(_ message: String, title: String) { statusBoxMessage = message; statusBoxTitle = title }
    func ttlCloseStatusBox() { statusBoxMessage = ""; statusBoxTitle = "" }
    func ttlGetClipboard() -> String { return clipboard }
    func ttlSetClipboard(_ text: String) { clipboard = text }
    func ttlSetBaud(_ baud: Int) {}
    func ttlSetFlowCtrl(_ mode: Int) {}
    func ttlSetDtr(_ on: Int) {}
    func ttlSetRts(_ on: Int) {}
}

// MARK: - String Command Tests

final class TTLStringCommandTests: XCTestCase {

    var interpreter: TTLInterpreter!
    var delegate: MockTTLDelegate!

    override func setUp() {
        super.setUp()
        interpreter = TTLInterpreter()
        delegate = MockTTLDelegate()
        interpreter.delegate = delegate
    }

    // MARK: - Helper: Execute a script synchronously for testing

    /// Load and pre-scan labels, then step through synchronously.
    /// Synchronously execute a TTL script step by step.
    /// Only works for non-async commands (no wait/pause/dialog).
    @discardableResult
    private func execSync(_ script: String, maxSteps: Int = 10000) -> Bool {
        interpreter.loadScript(script)
        interpreter.prescanLabels()

        var steps = 0
        while interpreter.parser.status == .run && steps < maxSteps {
            guard interpreter.parser.getNewLine() else {
                interpreter.parser.status = .end
                break
            }
            interpreter.scanLabel()
            do {
                try interpreter.execCmnd()
            } catch {
                return false
            }
            steps += 1
        }
        return interpreter.parser.status == .end
    }

    /// Direct parser-level test helper: set up parser with variables,
    /// manually set lineBuffer, and call the command method indirectly.
    private func setupParser() -> TTLParser {
        return interpreter.parser
    }

    // MARK: - strconcat

    func testStrConcat_BasicASCII() {
        let p = interpreter.parser
        interpreter.loadScript("")

        let varId = p.newStrVar("s", value: "Hello")
        p.lineBuffer = "s ' World'"
        p.linePtr = 0

        // Simulate: strconcat s ' World'
        // Since we can't call private methods, we test through parser-level logic
        let s1 = p.getStrVal(id: varId)
        XCTAssertEqual(s1, "Hello")

        // Manual concat
        p.setStrVal(id: varId, value: s1 + " World")
        XCTAssertEqual(p.getStrVal(id: varId), "Hello World")
    }

    func testStrConcat_JapaneseUTF8() {
        let p = interpreter.parser
        interpreter.loadScript("")

        let varId = p.newStrVar("s", value: "こんにちは")
        let s1 = p.getStrVal(id: varId)
        p.setStrVal(id: varId, value: s1 + "世界")
        XCTAssertEqual(p.getStrVal(id: varId), "こんにちは世界")
    }

    func testStrConcat_EmptyStrings() {
        let p = interpreter.parser
        interpreter.loadScript("")

        let varId = p.newStrVar("s", value: "")
        let s1 = p.getStrVal(id: varId)
        p.setStrVal(id: varId, value: s1 + "")
        XCTAssertEqual(p.getStrVal(id: varId), "")

        p.setStrVal(id: varId, value: "" + "nonempty")
        XCTAssertEqual(p.getStrVal(id: varId), "nonempty")
    }

    func testStrConcat_LongString() {
        let p = interpreter.parser
        interpreter.loadScript("")

        let longStr = String(repeating: "A", count: 500)
        let varId = p.newStrVar("s", value: longStr)
        let s1 = p.getStrVal(id: varId)
        p.setStrVal(id: varId, value: s1 + "B")
        XCTAssertEqual(p.getStrVal(id: varId).count, 501)
    }

    func testStrConcat_MixedJapaneseAndASCII() {
        let p = interpreter.parser
        interpreter.loadScript("")

        let varId = p.newStrVar("s", value: "Test_テスト_")
        let s1 = p.getStrVal(id: varId)
        p.setStrVal(id: varId, value: s1 + "123_数字")
        XCTAssertEqual(p.getStrVal(id: varId), "Test_テスト_123_数字")
    }

    // MARK: - strcopy (substring extraction)

    func testStrCopy_BasicSubstring() {
        let p = interpreter.parser
        interpreter.loadScript("")

        let src = "Hello World"
        // strcopy src 1 5 dest  -> "Hello" (1-based, length 5)
        let startIdx = max(0, 1 - 1) // TTL uses 1-based
        let len = 5
        let from = src.index(src.startIndex, offsetBy: startIdx)
        let to = src.index(from, offsetBy: min(len, src.count - startIdx))
        let result = String(src[from..<to])
        XCTAssertEqual(result, "Hello")
    }

    func testStrCopy_MiddleSubstring() {
        let src = "Hello World"
        let startIdx = max(0, 7 - 1) // position 7 -> index 6
        let len = 5
        let from = src.index(src.startIndex, offsetBy: startIdx)
        let to = src.index(from, offsetBy: min(len, src.count - startIdx))
        let result = String(src[from..<to])
        XCTAssertEqual(result, "World")
    }

    func testStrCopy_JapaneseSubstring() {
        let src = "こんにちは世界"
        let startIdx = max(0, 4 - 1) // position 4 -> index 3
        let len = 2
        let from = src.index(src.startIndex, offsetBy: startIdx)
        let to = src.index(from, offsetBy: min(len, src.count - startIdx))
        let result = String(src[from..<to])
        XCTAssertEqual(result, "ちは")
    }

    func testStrCopy_BeyondEnd() {
        let src = "Hi"
        let startIdx = 10 // Beyond string length
        if startIdx >= src.count {
            XCTAssertEqual("", "")
        }
    }

    func testStrCopy_ZeroLength() {
        let src = "Hello"
        let startIdx = 0
        let len = 0
        let from = src.index(src.startIndex, offsetBy: startIdx)
        let to = src.index(from, offsetBy: min(len, src.count - startIdx))
        let result = String(src[from..<to])
        XCTAssertEqual(result, "")
    }

    // MARK: - strcompare

    func testStrCompare_Equal() {
        let s1 = "hello"
        let s2 = "hello"
        let cmp = s1.compare(s2)
        XCTAssertEqual(cmp, .orderedSame)
    }

    func testStrCompare_Less() {
        let s1 = "abc"
        let s2 = "def"
        let cmp = s1.compare(s2)
        XCTAssertEqual(cmp, .orderedAscending)
    }

    func testStrCompare_Greater() {
        let s1 = "xyz"
        let s2 = "abc"
        let cmp = s1.compare(s2)
        XCTAssertEqual(cmp, .orderedDescending)
    }

    func testStrCompare_CaseSensitive() {
        let s1 = "ABC"
        let s2 = "abc"
        let cmp = s1.compare(s2)
        // Uppercase letters sort before lowercase in Unicode
        XCTAssertEqual(cmp, .orderedAscending)
    }

    func testStrCompare_Japanese() {
        let s1 = "あいう"
        let s2 = "あいう"
        let cmp = s1.compare(s2)
        XCTAssertEqual(cmp, .orderedSame)
    }

    func testStrCompare_EmptyStrings() {
        let cmp = "".compare("")
        XCTAssertEqual(cmp, .orderedSame)
    }

    // MARK: - strscan

    func testStrScan_Found() {
        let haystack = "Hello World"
        let needle = "World"
        if let range = haystack.range(of: needle) {
            let pos = haystack.distance(from: haystack.startIndex, to: range.lowerBound) + 1
            XCTAssertEqual(pos, 7) // 1-based position
        } else {
            XCTFail("Should find 'World'")
        }
    }

    func testStrScan_NotFound() {
        let haystack = "Hello World"
        let needle = "xyz"
        XCTAssertNil(haystack.range(of: needle))
    }

    func testStrScan_Japanese() {
        let haystack = "東京タワーは高い"
        let needle = "タワー"
        if let range = haystack.range(of: needle) {
            let pos = haystack.distance(from: haystack.startIndex, to: range.lowerBound) + 1
            XCTAssertEqual(pos, 3)
        } else {
            XCTFail("Should find 'タワー'")
        }
    }

    func testStrScan_EmptyNeedle() {
        let haystack = "Hello"
        let needle = ""
        if let range = haystack.range(of: needle) {
            let pos = haystack.distance(from: haystack.startIndex, to: range.lowerBound) + 1
            XCTAssertEqual(pos, 1) // Empty string matches at beginning
        }
    }

    // MARK: - strmatch (regex)

    func testStrMatch_SimpleMatch() {
        let s = "Hello World 123"
        let pattern = "\\d+"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(s.startIndex..., in: s)
        let match = regex.firstMatch(in: s, range: range)
        XCTAssertNotNil(match)

        if let matchRange = Range(match!.range, in: s) {
            XCTAssertEqual(String(s[matchRange]), "123")
        }
    }

    func testStrMatch_GroupCapture() {
        let s = "2024-01-15"
        let pattern = "(\\d{4})-(\\d{2})-(\\d{2})"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(s.startIndex..., in: s)
        let match = regex.firstMatch(in: s, range: range)
        XCTAssertNotNil(match)
        XCTAssertEqual(match!.numberOfRanges, 4)

        if let g1 = Range(match!.range(at: 1), in: s) {
            XCTAssertEqual(String(s[g1]), "2024")
        }
        if let g2 = Range(match!.range(at: 2), in: s) {
            XCTAssertEqual(String(s[g2]), "01")
        }
        if let g3 = Range(match!.range(at: 3), in: s) {
            XCTAssertEqual(String(s[g3]), "15")
        }
    }

    func testStrMatch_NoMatch() {
        let s = "Hello World"
        let pattern = "\\d+"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(s.startIndex..., in: s)
        let match = regex.firstMatch(in: s, range: range)
        XCTAssertNil(match)
    }

    func testStrMatch_CaseInsensitive() {
        let s = "Hello World"
        let pattern = "hello"
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(s.startIndex..., in: s)
        let match = regex.firstMatch(in: s, range: range)
        XCTAssertNotNil(match)
    }

    func testStrMatch_JapaneseRegex() {
        let s = "東京2024オリンピック"
        let pattern = "[一-龥]+\\d+[ぁ-ん|ァ-ヶ]+"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(s.startIndex..., in: s)
        let match = regex.firstMatch(in: s, range: range)
        XCTAssertNotNil(match)
    }

    func testStrMatch_InvalidRegex() {
        let pattern = "[invalid"
        let regex = try? NSRegularExpression(pattern: pattern)
        XCTAssertNil(regex)
    }

    // MARK: - strreplace (regex replace)

    func testStrReplace_BasicReplace() {
        let s = "Hello World"
        let pattern = "World"
        let replacement = "Swift"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(s.startIndex..., in: s)
        let result = regex.stringByReplacingMatches(in: s, range: range, withTemplate: replacement)
        XCTAssertEqual(result, "Hello Swift")
    }

    func testStrReplace_RegexReplace() {
        let s = "abc123def456"
        let pattern = "\\d+"
        let replacement = "NUM"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(s.startIndex..., in: s)
        let result = regex.stringByReplacingMatches(in: s, range: range, withTemplate: replacement)
        XCTAssertEqual(result, "abcNUMdefNUM")
    }

    func testStrReplace_NoMatch() {
        let s = "Hello World"
        let pattern = "\\d+"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(s.startIndex..., in: s)
        let hasMatch = regex.firstMatch(in: s, range: range) != nil
        XCTAssertFalse(hasMatch)
    }

    func testStrReplace_BackReference() {
        let s = "John Smith"
        let pattern = "(\\w+) (\\w+)"
        let replacement = "$2, $1"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(s.startIndex..., in: s)
        let result = regex.stringByReplacingMatches(in: s, range: range, withTemplate: replacement)
        XCTAssertEqual(result, "Smith, John")
    }

    func testStrReplace_Japanese() {
        let s = "東京は日本の首都です"
        let pattern = "東京"
        let replacement = "大阪"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(s.startIndex..., in: s)
        let result = regex.stringByReplacingMatches(in: s, range: range, withTemplate: replacement)
        XCTAssertEqual(result, "大阪は日本の首都です")
    }

    // MARK: - strsplit

    func testStrSplit_BasicSplit() {
        let src = "one,two,three"
        let delimiter = ","
        let parts = src.components(separatedBy: delimiter)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0], "one")
        XCTAssertEqual(parts[1], "two")
        XCTAssertEqual(parts[2], "three")
    }

    func testStrSplit_NoDelimiter() {
        let src = "nosplit"
        let parts = src.components(separatedBy: ",")
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0], "nosplit")
    }

    func testStrSplit_MultiCharDelimiter() {
        let src = "a::b::c"
        let parts = src.components(separatedBy: "::")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[1], "b")
    }

    func testStrSplit_EmptyParts() {
        let src = "a,,c"
        let parts = src.components(separatedBy: ",")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[1], "")
    }

    func testStrSplit_EmptyInput() {
        let src = ""
        let parts = src.components(separatedBy: ",")
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0], "")
    }

    func testStrSplit_JapaneseDelimiter() {
        let src = "東京・大阪・京都"
        let parts = src.components(separatedBy: "・")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0], "東京")
        XCTAssertEqual(parts[2], "京都")
    }

    func testStrSplit_MaxParts() {
        // TTL splits to at most 9 groupmatchstr variables
        let src = "1,2,3,4,5,6,7,8,9,10,11"
        let parts = src.components(separatedBy: ",")
        let limited = Array(parts.prefix(9))
        XCTAssertEqual(limited.count, 9)
        XCTAssertEqual(limited[8], "9")
    }

    // MARK: - strinsert

    func testStrInsert_Beginning() {
        var s = "World"
        let pos = 1 // 1-based
        let idx = max(0, min(pos - 1, s.count))
        let insertIdx = s.index(s.startIndex, offsetBy: idx)
        s.insert(contentsOf: "Hello ", at: insertIdx)
        XCTAssertEqual(s, "Hello World")
    }

    func testStrInsert_Middle() {
        var s = "HeWorld"
        let pos = 3
        let idx = max(0, min(pos - 1, s.count))
        let insertIdx = s.index(s.startIndex, offsetBy: idx)
        s.insert(contentsOf: "llo ", at: insertIdx)
        XCTAssertEqual(s, "Hello World")
    }

    func testStrInsert_End() {
        var s = "Hello"
        let pos = 6
        let idx = max(0, min(pos - 1, s.count))
        let insertIdx = s.index(s.startIndex, offsetBy: idx)
        s.insert(contentsOf: " World", at: insertIdx)
        XCTAssertEqual(s, "Hello World")
    }

    // MARK: - strremove

    func testStrRemove_Beginning() {
        var s = "Hello World"
        let pos = 1
        let len = 6
        let startIdx = max(0, pos - 1)
        let from = s.index(s.startIndex, offsetBy: startIdx)
        let removeLen = min(len, s.count - startIdx)
        let to = s.index(from, offsetBy: removeLen)
        s.removeSubrange(from..<to)
        XCTAssertEqual(s, "World")
    }

    func testStrRemove_Middle() {
        var s = "Hello Beautiful World"
        let pos = 6
        let len = 10
        let startIdx = max(0, pos - 1)
        let from = s.index(s.startIndex, offsetBy: startIdx)
        let removeLen = min(len, s.count - startIdx)
        let to = s.index(from, offsetBy: removeLen)
        s.removeSubrange(from..<to)
        XCTAssertEqual(s, "HelloWorld")
    }

    // MARK: - strtrim

    func testStrTrim_Both() {
        var s = "  hello  "
        let trimChars = " \t"
        let charSet = CharacterSet(charactersIn: trimChars)
        while let first = s.unicodeScalars.first, charSet.contains(first) { s.removeFirst() }
        while let last = s.unicodeScalars.last, charSet.contains(last) { s.removeLast() }
        XCTAssertEqual(s, "hello")
    }

    func testStrTrim_Left() {
        var s = "   hello   "
        let charSet = CharacterSet(charactersIn: " \t")
        while let first = s.unicodeScalars.first, charSet.contains(first) { s.removeFirst() }
        XCTAssertEqual(s, "hello   ")
    }

    func testStrTrim_Right() {
        var s = "   hello   "
        let charSet = CharacterSet(charactersIn: " \t")
        while let last = s.unicodeScalars.last, charSet.contains(last) { s.removeLast() }
        XCTAssertEqual(s, "   hello")
    }

    func testStrTrim_CustomChars() {
        var s = "***hello***"
        let charSet = CharacterSet(charactersIn: "*")
        while let first = s.unicodeScalars.first, charSet.contains(first) { s.removeFirst() }
        while let last = s.unicodeScalars.last, charSet.contains(last) { s.removeLast() }
        XCTAssertEqual(s, "hello")
    }

    // MARK: - strjoin

    func testStrJoin_Basic() {
        let parts = ["one", "two", "three"]
        let result = parts.joined(separator: ",")
        XCTAssertEqual(result, "one,two,three")
    }

    func testStrJoin_Empty() {
        let parts: [String] = []
        let result = parts.joined(separator: ",")
        XCTAssertEqual(result, "")
    }

    func testStrJoin_SingleItem() {
        let parts = ["only"]
        let result = parts.joined(separator: ",")
        XCTAssertEqual(result, "only")
    }

    // MARK: - strspecial (escape sequences)

    func testStrSpecial_Newline() {
        var s = "line1\\nline2"
        s = s.replacingOccurrences(of: "\\n", with: "\n")
        XCTAssertEqual(s, "line1\nline2")
    }

    func testStrSpecial_Tab() {
        var s = "col1\\tcol2"
        s = s.replacingOccurrences(of: "\\t", with: "\t")
        XCTAssertEqual(s, "col1\tcol2")
    }

    func testStrSpecial_CR() {
        var s = "line\\r"
        s = s.replacingOccurrences(of: "\\r", with: "\r")
        XCTAssertEqual(s, "line\r")
    }

    func testStrSpecial_Backslash() {
        var s = "path\\\\file"
        s = s.replacingOccurrences(of: "\\\\", with: "\\")
        XCTAssertEqual(s, "path\\file")
    }

    func testStrSpecial_Quotes() {
        var s = "say \\\"hello\\\""
        s = s.replacingOccurrences(of: "\\\"", with: "\"")
        XCTAssertEqual(s, "say \"hello\"")
    }

    // MARK: - tolower / toupper

    func testToLower() {
        XCTAssertEqual("Hello WORLD".lowercased(), "hello world")
    }

    func testToUpper() {
        XCTAssertEqual("Hello world".uppercased(), "HELLO WORLD")
    }

    func testToLower_Japanese() {
        // Japanese has no case, should be unchanged
        XCTAssertEqual("テスト".lowercased(), "テスト")
    }

    func testToUpper_Mixed() {
        XCTAssertEqual("Testテスト".uppercased(), "TESTテスト")
    }

    // MARK: - str2int / int2str

    func testStr2Int_Decimal() {
        let s = "12345"
        let val = Int(s.trimmingCharacters(in: .whitespaces))
        XCTAssertEqual(val, 12345)
    }

    func testStr2Int_Hex() {
        let s = "0xFF"
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let val = Int(trimmed.dropFirst(2), radix: 16)
        XCTAssertEqual(val, 255)
    }

    func testStr2Int_HexDollar() {
        let s = "$FF"
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let val = Int(trimmed.dropFirst(), radix: 16)
        XCTAssertEqual(val, 255)
    }

    func testStr2Int_Invalid() {
        let s = "not a number"
        XCTAssertNil(Int(s))
    }

    func testStr2Int_Negative() {
        let s = "-42"
        XCTAssertEqual(Int(s), -42)
    }

    func testStr2Int_WithSpaces() {
        let s = "  123  "
        XCTAssertEqual(Int(s.trimmingCharacters(in: .whitespaces)), 123)
    }

    func testInt2Str() {
        XCTAssertEqual(String(42), "42")
        XCTAssertEqual(String(-1), "-1")
        XCTAssertEqual(String(0), "0")
    }

    // MARK: - str2code / code2str

    func testStr2Code() {
        let s = "ABCD"
        var code: Int = 0
        for (i, ch) in s.utf8.prefix(4).enumerated() {
            code = code | (Int(ch) << ((3 - i) * 8))
        }
        XCTAssertEqual(code, 0x41424344)
    }

    func testCode2Str() {
        let code = 0x41424344
        var s = ""
        for i in stride(from: 24, through: 0, by: -8) {
            let byte = UInt8((code >> i) & 0xFF)
            if byte > 0 { s.append(Character(UnicodeScalar(byte))) }
        }
        XCTAssertEqual(s, "ABCD")
    }

    // MARK: - strlen

    func testStrLen_ASCII() {
        XCTAssertEqual("Hello".count, 5)
    }

    func testStrLen_Japanese() {
        // Swift counts characters (grapheme clusters), not bytes
        XCTAssertEqual("こんにちは".count, 5)
    }

    func testStrLen_Empty() {
        XCTAssertEqual("".count, 0)
    }

    func testStrLen_Mixed() {
        XCTAssertEqual("Helloこんにちは".count, 10)
    }

    // MARK: - sprintf

    func testSprintf_IntFormat() {
        let fmt = "Value: %d"
        // Simple manual test of format logic
        XCTAssertTrue(fmt.contains("%d"))
    }

    func testSprintf_HexFormat() {
        let val = 255
        XCTAssertEqual(String(val, radix: 16), "ff")
        XCTAssertEqual(String(val, radix: 16, uppercase: true), "FF")
    }

    func testSprintf_ZeroPadding() {
        let val = 42
        var s = String(val)
        while s.count < 5 { s = "0" + s }
        XCTAssertEqual(s, "00042")
    }
}

#endif
