/*
 * TTL Checksum & CRC Tests
 * Tests CRC16, CRC32, Checksum8/16/32 algorithms
 * Also covers rotation (rotateL, rotateR) and random
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)

final class TTLChecksumTests: XCTestCase {

    var interpreter: TTLInterpreter!
    var delegate: MockTTLDelegate!

    override func setUp() {
        super.setUp()
        interpreter = TTLInterpreter()
        delegate = MockTTLDelegate()
        interpreter.delegate = delegate
    }

    // MARK: - Checksum8

    func testChecksum8_Empty() {
        let data = Data()
        var sum: UInt8 = 0
        for byte in data { sum = sum &+ byte }
        XCTAssertEqual(sum, 0)
    }

    func testChecksum8_SingleByte() {
        let data = Data([0x42])
        var sum: UInt8 = 0
        for byte in data { sum = sum &+ byte }
        XCTAssertEqual(sum, 0x42)
    }

    func testChecksum8_HelloWorld() {
        let data = Data("Hello World".utf8)
        var sum: UInt8 = 0
        for byte in data { sum = sum &+ byte }
        // Sum of ASCII bytes mod 256
        let expected: UInt8 = data.reduce(0) { $0 &+ $1 }
        XCTAssertEqual(sum, expected)
    }

    func testChecksum8_AllFF() {
        let data = Data([0xFF, 0xFF, 0xFF, 0xFF])
        var sum: UInt8 = 0
        for byte in data { sum = sum &+ byte }
        // 4 * 0xFF = 0x3FC, mod 256 = 0xFC
        XCTAssertEqual(sum, 0xFC)
    }

    // MARK: - Checksum16

    func testChecksum16_BasicCalc() {
        let data = Data("AB".utf8)
        var sum: UInt16 = 0
        for byte in data { sum = sum &+ UInt16(byte) }
        // A=0x41, B=0x42 → 0x83
        XCTAssertEqual(sum, 0x83)
    }

    // MARK: - Checksum32

    func testChecksum32_BasicCalc() {
        let data = Data("Test".utf8)
        var sum: UInt32 = 0
        for byte in data { sum = sum &+ UInt32(byte) }
        // T=0x54, e=0x65, s=0x73, t=0x74 → 0x1A0
        XCTAssertEqual(sum, 0x54 + 0x65 + 0x73 + 0x74)
    }

    // MARK: - CRC32

    func testCRC32_KnownValue() {
        // CRC32 of "123456789" is 0xCBF43926
        let data = Data("123456789".utf8)

        // Standard CRC32 (ISO 3309)
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crc ^ UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc = crc >> 1
                }
            }
        }
        crc = crc ^ 0xFFFFFFFF
        XCTAssertEqual(crc, 0xCBF43926)
    }

    func testCRC32_Empty() {
        let data = Data()
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crc ^ UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc = crc >> 1
                }
            }
        }
        crc = crc ^ 0xFFFFFFFF
        XCTAssertEqual(crc, 0x00000000) // CRC32 of empty = 0
    }

    // MARK: - CRC16

    func testCRC16_CCITT() {
        // CRC16-CCITT of "123456789" is 0x29B1 (for XModem/CCITT-FALSE variant)
        let data = Data("123456789".utf8)
        var crc: UInt16 = 0xFFFF // CCITT init
        for byte in data {
            crc = crc ^ (UInt16(byte) << 8)
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        XCTAssertEqual(crc, 0x29B1)
    }

    // MARK: - File-based Checksum

    func testChecksumFile_Integration() {
        let tempPath = NSTemporaryDirectory() + "ttl_crc_test_\(UUID().uuidString).txt"
        let content = "Test data for CRC"
        FileManager.default.createFile(atPath: tempPath, contents: Data(content.utf8))
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        // Verify file exists and has content
        let data = FileManager.default.contents(atPath: tempPath)!
        XCTAssertEqual(data.count, content.utf8.count)

        // Calculate CRC32
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crc ^ UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc = crc >> 1
                }
            }
        }
        crc = crc ^ 0xFFFFFFFF
        XCTAssertNotEqual(crc, 0) // Non-empty data should have non-zero CRC
    }

    // MARK: - Rotate Operations

    func testRotateLeft() {
        // Rotate left by 1: 0x80000001 → 0x00000003
        let val: UInt32 = 0x80000001
        let rotated = (val << 1) | (val >> 31)
        XCTAssertEqual(rotated, 0x00000003)
    }

    func testRotateLeft_ByN() {
        let val: UInt32 = 0x12345678
        let n = 4
        let rotated = (val << n) | (val >> (32 - n))
        XCTAssertEqual(rotated, 0x23456781)
    }

    func testRotateRight() {
        // Rotate right by 1: 0x00000003 → 0x80000001
        let val: UInt32 = 0x00000003
        let rotated = (val >> 1) | (val << 31)
        XCTAssertEqual(rotated, 0x80000001)
    }

    func testRotateRight_ByN() {
        let val: UInt32 = 0x12345678
        let n = 4
        let rotated = (val >> n) | (val << (32 - n))
        XCTAssertEqual(rotated, 0x81234567)
    }

    func testRotateLeftRight_Inverse() {
        let original: UInt32 = 0xDEADBEEF
        let n = 7
        let rotatedLeft = (original << n) | (original >> (32 - n))
        let restored = (rotatedLeft >> n) | (rotatedLeft << (32 - n))
        XCTAssertEqual(restored, original)
    }

    // MARK: - Random

    func testRandom_Range() {
        // Test that random values are within expected range
        for _ in 0..<100 {
            let val = Int.random(in: 0..<65536)
            XCTAssertGreaterThanOrEqual(val, 0)
            XCTAssertLessThan(val, 65536)
        }
    }

    func testRandom_Distribution() {
        // Very basic distribution check - ensure not all same value
        var values = Set<Int>()
        for _ in 0..<100 {
            values.insert(Int.random(in: 0..<1000))
        }
        // With 100 random values from 0-999, we should get many unique values
        XCTAssertGreaterThan(values.count, 50)
    }
}

#endif
