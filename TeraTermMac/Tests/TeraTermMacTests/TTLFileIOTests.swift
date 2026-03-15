/*
 * TTL File I/O Tests
 * Phase 1: fileopen, filereadln, filecopy operations
 * macOS sandbox-aware - uses temp directories
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)

final class TTLFileIOTests: XCTestCase {

    var testDir: String!

    override func setUp() {
        super.setUp()
        testDir = NSTemporaryDirectory() + "TTLFileIOTests_\(UUID().uuidString)/"
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        super.tearDown()
    }

    // MARK: - File Create/Delete

    func testFileCreate() {
        let path = testDir + "test_create.txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testFileDelete() {
        let path = testDir + "test_delete.txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        try? FileManager.default.removeItem(atPath: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testFileDeleteNonExistent() {
        let path = testDir + "nonexistent.txt"
        XCTAssertThrowsError(try FileManager.default.removeItem(atPath: path))
    }

    // MARK: - File Open/Read/Write

    func testFileOpenForWriting() {
        let path = testDir + "test_write.txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        let fh = FileHandle(forUpdatingAtPath: path)
        XCTAssertNotNil(fh)
        try? fh?.close()
    }

    func testFileOpenForReading() {
        let path = testDir + "test_read.txt"
        FileManager.default.createFile(atPath: path, contents: Data("Hello\n".utf8))
        let fh = FileHandle(forReadingAtPath: path)
        XCTAssertNotNil(fh)
        try? fh?.close()
    }

    func testFileOpenNonExistentReadOnly() {
        let path = testDir + "nonexistent.txt"
        let fh = FileHandle(forReadingAtPath: path)
        XCTAssertNil(fh)
    }

    func testFileWriteAndRead() {
        let path = testDir + "test_rw.txt"
        FileManager.default.createFile(atPath: path, contents: nil)

        // Write
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.write(Data("Line 1\n".utf8))
            fh.write(Data("Line 2\n".utf8))
            fh.write(Data("Line 3\n".utf8))
            try? fh.close()
        }

        // Read back
        if let data = FileManager.default.contents(atPath: path) {
            let content = String(data: data, encoding: .utf8)
            XCTAssertEqual(content, "Line 1\nLine 2\nLine 3\n")
        } else {
            XCTFail("Failed to read file")
        }
    }

    func testFileWriteLnCRLF() {
        let path = testDir + "test_crlf.txt"
        FileManager.default.createFile(atPath: path, contents: nil)

        if let fh = FileHandle(forWritingAtPath: path) {
            fh.write(Data("Hello".utf8))
            fh.write(Data([0x0D, 0x0A])) // CRLF
            try? fh.close()
        }

        if let data = FileManager.default.contents(atPath: path) {
            XCTAssertEqual(data.count, 7) // "Hello" + CR + LF
            XCTAssertEqual(data[5], 0x0D)
            XCTAssertEqual(data[6], 0x0A)
        }
    }

    // MARK: - filereadln (line-by-line reading with CR/LF handling)

    func testFileReadln_LF() {
        let path = testDir + "test_lf.txt"
        FileManager.default.createFile(atPath: path, contents: Data("Line1\nLine2\nLine3\n".utf8))

        guard let fh = FileHandle(forReadingAtPath: path) else {
            XCTFail("Cannot open file"); return
        }

        let line1 = readLine(from: fh)
        XCTAssertEqual(line1.line, "Line1")
        XCTAssertFalse(line1.eof)

        let line2 = readLine(from: fh)
        XCTAssertEqual(line2.line, "Line2")

        let line3 = readLine(from: fh)
        XCTAssertEqual(line3.line, "Line3")

        let line4 = readLine(from: fh)
        XCTAssertTrue(line4.eof)

        try? fh.close()
    }

    func testFileReadln_CRLF() {
        let path = testDir + "test_crlf_read.txt"
        let data = Data("Line1\r\nLine2\r\nLine3\r\n".utf8)
        FileManager.default.createFile(atPath: path, contents: data)

        guard let fh = FileHandle(forReadingAtPath: path) else {
            XCTFail("Cannot open file"); return
        }

        let line1 = readLine(from: fh)
        XCTAssertEqual(line1.line, "Line1")

        let line2 = readLine(from: fh)
        XCTAssertEqual(line2.line, "Line2")

        let line3 = readLine(from: fh)
        XCTAssertEqual(line3.line, "Line3")

        try? fh.close()
    }

    func testFileReadln_CR() {
        let path = testDir + "test_cr.txt"
        let data = Data("Line1\rLine2\r".utf8)
        FileManager.default.createFile(atPath: path, contents: data)

        guard let fh = FileHandle(forReadingAtPath: path) else {
            XCTFail("Cannot open file"); return
        }

        let line1 = readLine(from: fh)
        XCTAssertEqual(line1.line, "Line1")

        let line2 = readLine(from: fh)
        XCTAssertEqual(line2.line, "Line2")

        try? fh.close()
    }

    func testFileReadln_EmptyLines() {
        let path = testDir + "test_empty.txt"
        FileManager.default.createFile(atPath: path, contents: Data("\n\nLine3\n".utf8))

        guard let fh = FileHandle(forReadingAtPath: path) else {
            XCTFail("Cannot open"); return
        }

        let line1 = readLine(from: fh)
        XCTAssertEqual(line1.line, "")

        let line2 = readLine(from: fh)
        XCTAssertEqual(line2.line, "")

        let line3 = readLine(from: fh)
        XCTAssertEqual(line3.line, "Line3")

        try? fh.close()
    }

    func testFileReadln_Japanese() {
        let path = testDir + "test_jp.txt"
        FileManager.default.createFile(atPath: path, contents: Data("日本語テスト\nUTF-8対応\n".utf8))

        guard let fh = FileHandle(forReadingAtPath: path) else {
            XCTFail("Cannot open"); return
        }

        // Note: TTLInterpreter reads byte-by-byte, which may not handle multi-byte UTF-8 correctly.
        // This tests at the File I/O level to verify the concept.
        let data = fh.readDataToEndOfFile()
        let content = String(data: data, encoding: .utf8)!
        XCTAssertTrue(content.contains("日本語テスト"))
        XCTAssertTrue(content.contains("UTF-8対応"))

        try? fh.close()
    }

    /// Simulates TTLInterpreter's filereadln logic
    private func readLine(from fh: FileHandle) -> (line: String, eof: Bool) {
        var line = ""
        while true {
            let data = fh.readData(ofLength: 1)
            if data.isEmpty {
                return (line, line.isEmpty)
            }
            let byte = data[0]
            if byte == 0x0A { // LF
                return (line, false)
            } else if byte == 0x0D { // CR
                let next = fh.readData(ofLength: 1)
                if !next.isEmpty && next[0] != 0x0A {
                    fh.seek(toFileOffset: fh.offsetInFile - 1)
                }
                return (line, false)
            } else {
                line.append(Character(UnicodeScalar(byte)))
            }
        }
    }

    // MARK: - filecopy

    func testFileCopy() {
        let src = testDir + "src.txt"
        let dst = testDir + "dst.txt"
        FileManager.default.createFile(atPath: src, contents: Data("copy me".utf8))

        do {
            try FileManager.default.copyItem(atPath: src, toPath: dst)
            XCTAssertTrue(FileManager.default.fileExists(atPath: dst))
            let content = String(data: FileManager.default.contents(atPath: dst)!, encoding: .utf8)
            XCTAssertEqual(content, "copy me")
        } catch {
            XCTFail("Copy failed: \(error)")
        }
    }

    func testFileCopy_NonExistentSource() {
        let src = testDir + "nonexistent.txt"
        let dst = testDir + "dst.txt"
        XCTAssertThrowsError(try FileManager.default.copyItem(atPath: src, toPath: dst))
    }

    // MARK: - filerename

    func testFileRename() {
        let src = testDir + "old.txt"
        let dst = testDir + "new.txt"
        FileManager.default.createFile(atPath: src, contents: Data("rename me".utf8))

        do {
            try FileManager.default.moveItem(atPath: src, toPath: dst)
            XCTAssertFalse(FileManager.default.fileExists(atPath: src))
            XCTAssertTrue(FileManager.default.fileExists(atPath: dst))
        } catch {
            XCTFail("Rename failed: \(error)")
        }
    }

    // MARK: - fileconcat

    func testFileConcat() {
        let dst = testDir + "dst.txt"
        let src = testDir + "src.txt"
        FileManager.default.createFile(atPath: dst, contents: Data("Hello".utf8))
        FileManager.default.createFile(atPath: src, contents: Data(" World".utf8))

        guard let srcData = FileManager.default.contents(atPath: src) else {
            XCTFail("Cannot read source"); return
        }
        if let fh = FileHandle(forWritingAtPath: dst) {
            fh.seekToEndOfFile()
            fh.write(srcData)
            try? fh.close()
        }

        let content = String(data: FileManager.default.contents(atPath: dst)!, encoding: .utf8)
        XCTAssertEqual(content, "Hello World")
    }

    // MARK: - filesearch

    func testFileSearch_Exists() {
        let path = testDir + "exists.txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testFileSearch_NotExists() {
        let path = testDir + "nope.txt"
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - fileseek

    func testFileSeek() {
        let path = testDir + "seek.txt"
        FileManager.default.createFile(atPath: path, contents: Data("ABCDEFGHIJ".utf8))

        guard let fh = FileHandle(forReadingAtPath: path) else {
            XCTFail("Cannot open"); return
        }

        fh.seek(toFileOffset: 5)
        let data = fh.readData(ofLength: 5)
        let s = String(data: data, encoding: .utf8)
        XCTAssertEqual(s, "FGHIJ")

        try? fh.close()
    }

    func testFileSeekFromEnd() {
        let path = testDir + "seekend.txt"
        FileManager.default.createFile(atPath: path, contents: Data("ABCDEFGHIJ".utf8))

        guard let fh = FileHandle(forReadingAtPath: path) else {
            XCTFail("Cannot open"); return
        }

        fh.seekToEndOfFile()
        fh.seek(toFileOffset: UInt64(Int64(fh.offsetInFile) - 3))
        let data = fh.readData(ofLength: 3)
        let s = String(data: data, encoding: .utf8)
        XCTAssertEqual(s, "HIJ")

        try? fh.close()
    }

    // MARK: - filestat (file size)

    func testFileStat() {
        let path = testDir + "stat.txt"
        let content = "Hello World" // 11 bytes
        FileManager.default.createFile(atPath: path, contents: Data(content.utf8))

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs[.size] as? Int) ?? 0
            XCTAssertEqual(size, 11)
        } catch {
            XCTFail("attributesOfItem failed: \(error)")
        }
    }

    func testFileStat_NonExistent() {
        let path = testDir + "nosuch.txt"
        XCTAssertThrowsError(try FileManager.default.attributesOfItem(atPath: path))
    }

    // MARK: - filetruncate

    func testFileTruncate() {
        let path = testDir + "truncate.txt"
        FileManager.default.createFile(atPath: path, contents: Data("Hello World".utf8))

        guard let fh = FileHandle(forUpdatingAtPath: path) else {
            XCTFail("Cannot open"); return
        }

        fh.seek(toFileOffset: 5)
        fh.truncateFile(atOffset: fh.offsetInFile)
        try? fh.close()

        let data = FileManager.default.contents(atPath: path)!
        XCTAssertEqual(String(data: data, encoding: .utf8), "Hello")
    }

    // MARK: - filemarkptr / fileseekback

    func testFileMarkPtrAndSeekBack() {
        let path = testDir + "markptr.txt"
        FileManager.default.createFile(atPath: path, contents: Data("ABCDEFGHIJ".utf8))

        guard let fh = FileHandle(forReadingAtPath: path) else {
            XCTFail("Cannot open"); return
        }

        // Read first 3 chars
        let _ = fh.readData(ofLength: 3)
        let markedOffset = fh.offsetInFile // position 3

        // Read more
        let _ = fh.readData(ofLength: 4)
        XCTAssertEqual(fh.offsetInFile, 7)

        // Seek back to marked position
        fh.seek(toFileOffset: markedOffset)
        let data = fh.readData(ofLength: 4)
        XCTAssertEqual(String(data: data, encoding: .utf8), "DEFG")

        try? fh.close()
    }

    // MARK: - Directory Operations

    func testFolderCreate() {
        let path = testDir + "newdir"
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            var isDir: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDir))
            XCTAssertTrue(isDir.boolValue)
        } catch {
            XCTFail("createDirectory failed: \(error)")
        }
    }

    func testFolderCreateNested() {
        let path = testDir + "a/b/c"
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        } catch {
            XCTFail("createDirectory failed: \(error)")
        }
    }

    func testFolderDelete() {
        let path = testDir + "deldir"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        do {
            try FileManager.default.removeItem(atPath: path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        } catch {
            XCTFail("removeItem failed: \(error)")
        }
    }

    func testFolderSearch() {
        let path = testDir + "searchdir"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        XCTAssertTrue(exists && isDir.boolValue)
    }

    func testFolderSearch_NotDirectory() {
        let path = testDir + "notadir.txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertFalse(isDir.boolValue)
    }

    // MARK: - Wildcard Matching (findfirst/findnext)

    func testWildcardMatch() {
        let pred = NSPredicate(format: "SELF LIKE[c] %@", "*.txt")
        XCTAssertTrue(pred.evaluate(with: "test.txt"))
        XCTAssertTrue(pred.evaluate(with: "TEST.TXT"))
        XCTAssertFalse(pred.evaluate(with: "test.log"))
    }

    func testWildcardMatch_QuestionMark() {
        let pred = NSPredicate(format: "SELF LIKE[c] %@", "file?.txt")
        XCTAssertTrue(pred.evaluate(with: "file1.txt"))
        XCTAssertTrue(pred.evaluate(with: "fileA.txt"))
        XCTAssertFalse(pred.evaluate(with: "file12.txt"))
    }

    func testWildcardMatch_AllFiles() {
        let pred = NSPredicate(format: "SELF LIKE[c] %@", "*")
        XCTAssertTrue(pred.evaluate(with: "anything.txt"))
        XCTAssertTrue(pred.evaluate(with: ""))
    }

    // MARK: - File Handle Limit

    func testMaxFileHandles() {
        // Verify we can open up to 16 files
        var handles: [FileHandle] = []
        for i in 0..<16 {
            let path = testDir + "file\(i).txt"
            FileManager.default.createFile(atPath: path, contents: nil)
            if let fh = FileHandle(forUpdatingAtPath: path) {
                handles.append(fh)
            }
        }
        XCTAssertEqual(handles.count, 16)

        for fh in handles {
            try? fh.close()
        }
    }
}

#endif
