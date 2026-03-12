/*
 * TTL Boundary & Limit Tests
 *
 * Tests variable limits, string max length, integer overflow/underflow,
 * array bounds, call stack depth, loop stack depth, and file handle limits.
 *
 * Based on the TTL specification boundary values:
 *   MaxStrLen = 512, MaxNameLen = 128, MaxLineLen = 4096
 *   maxCallStackDepth = 10, maxLoopStackDepth = 10, maxFileNestLevel = 10
 *   maxFileHandles = 16, maxDirHandles = 8
 *   Integer: Swift Int (64-bit), original C: 32-bit signed
 *   Array index: packed in 16 bits (max 65535)
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)

final class TTLBoundaryTests: XCTestCase {

    var interpreter: TTLInterpreter!
    var delegate: MockTTLDelegate!

    override func setUp() {
        super.setUp()
        interpreter = TTLInterpreter()
        delegate = MockTTLDelegate()
        interpreter.delegate = delegate
    }

    override func tearDown() {
        interpreter.stop()
        interpreter = nil
        delegate = nil
        super.tearDown()
    }

    // MARK: - Helper

    @discardableResult
    private func execSync(_ script: String, maxSteps: Int = 50000) -> Bool {
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
            if interpreter.parser.status == .pause {
                break
            }
            steps += 1
        }
        return interpreter.parser.status == .end
    }

    /// Execute and expect a TTLError to be thrown
    private func execExpectingError(_ script: String, maxSteps: Int = 10000) -> Bool {
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
                return true  // Error was thrown as expected
            }
            steps += 1
        }
        return false  // No error was thrown
    }

    // ================================================================
    // MARK: - TEST 1: String Length Limits
    // ================================================================

    /// 1.1 Build a string up to MaxStrLen (512) via strconcat
    func testStringMaxLength_512chars() {
        // Build a 512-char string using a loop
        let script = """
        s = ''
        for i 1 512
          strconcat s 'A'
        next
        strlen s
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        // result should be 512 (strlen stores result)
        XCTAssertEqual(p.getIntVal(id: p.resultVarId), 512)
    }

    /// 1.2 String beyond MaxStrLen should be truncated (not crash)
    func testStringBeyondMaxLength_Truncation() {
        // Try to build a 600-char string - should truncate at 512
        let script = """
        s = ''
        for i 1 600
          strconcat s 'B'
        next
        strlen s
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        let len = p.getIntVal(id: p.resultVarId)
        // Should be clamped at MaxStrLen (512) or less
        XCTAssertLessThanOrEqual(len, 512)
        XCTAssertGreaterThan(len, 0)
    }

    /// 1.3 Empty string operations
    func testStringEmpty() {
        let script = """
        s = ''
        strlen s
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)
        XCTAssertEqual(interpreter.parser.getIntVal(id: interpreter.parser.resultVarId), 0)
    }

    /// 1.4 strcopy boundary: copy from position 0 with full length
    func testStrcopyFullLength() {
        let script = """
        s = 'ABCDEFGHIJ'
        strcopy s 1 10 t
        strlen t
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)
        XCTAssertEqual(interpreter.parser.getIntVal(id: interpreter.parser.resultVarId), 10)
    }

    /// 1.5 Japanese UTF-8 string length
    func testStringJapaneseLength() {
        let script = """
        s = 'テスト文字列'
        strlen s
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)
        // strlen counts characters (6 Japanese chars)
        XCTAssertEqual(interpreter.parser.getIntVal(id: interpreter.parser.resultVarId), 6)
    }

    // ================================================================
    // MARK: - TEST 2: Integer Boundary Values
    // ================================================================

    /// 2.1 32-bit max value (2,147,483,647)
    func testIntegerMax32bit() {
        let script = """
        x = 2147483647
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 2147483647)
        } else {
            XCTFail("Variable 'x' not found")
        }
    }

    /// 2.2 32-bit min value (-2,147,483,648) via expression
    func testIntegerMin32bit() {
        let script = """
        x = 0 - 2147483648
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), -2147483648)
        } else {
            XCTFail("Variable 'x' not found")
        }
    }

    /// 2.3 Integer overflow: max + 1 should wrap or handle gracefully
    func testIntegerOverflow() {
        let script = """
        x = 2147483647
        x = x + 1
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)
        // On 64-bit Swift Int, this will be 2147483648 (no wrap)
        // On original 32-bit C, this would wrap to -2147483648
        if let (_, id) = interpreter.parser.checkVar("x") {
            let val = interpreter.parser.getIntVal(id: id)
            // Should not crash; value depends on implementation
            XCTAssertNotEqual(val, 2147483647, "Value should have changed")
        }
    }

    /// 2.4 Division by zero should raise error
    func testDivisionByZero() {
        let errored = execExpectingError("""
        x = 10 / 0
        end
        """)
        XCTAssertTrue(errored, "Division by zero should throw an error")
    }

    /// 2.5 Modulo by zero should raise error
    func testModuloByZero() {
        let errored = execExpectingError("""
        x = 10 % 0
        end
        """)
        XCTAssertTrue(errored, "Modulo by zero should throw an error")
    }

    /// 2.6 Negative number arithmetic
    func testNegativeArithmetic() {
        let script = """
        x = 0 - 100
        y = x * 3
        z = y / 2
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("y") {
            XCTAssertEqual(p.getIntVal(id: id), -300)
        }
        if let (_, id) = p.checkVar("z") {
            XCTAssertEqual(p.getIntVal(id: id), -150)
        }
    }

    /// 2.7 Hexadecimal parsing at boundary
    func testHexParsing() {
        let script = """
        x = $7FFFFFFF
        y = $FFFFFFFF
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("x") {
            XCTAssertEqual(p.getIntVal(id: id), 0x7FFFFFFF)
        }
        if let (_, id) = p.checkVar("y") {
            XCTAssertEqual(p.getIntVal(id: id), 0xFFFFFFFF)
        }
    }

    /// 2.8 Operator precedence: multiplication before addition
    func testOperatorPrecedence() {
        let script = """
        x = 2 + 3 * 4
        y = (2 + 3) * 4
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("x") {
            XCTAssertEqual(p.getIntVal(id: id), 14)
        }
        if let (_, id) = p.checkVar("y") {
            XCTAssertEqual(p.getIntVal(id: id), 20)
        }
    }

    /// 2.9 Bitwise operations
    func testBitwiseOperations() {
        let script = """
        a = $FF & $0F
        b = $F0 | $0F
        c = $FF ^ $0F
        d = 1 << 8
        e = 256 >> 4
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("a") { XCTAssertEqual(p.getIntVal(id: id), 0x0F) }
        if let (_, id) = p.checkVar("b") { XCTAssertEqual(p.getIntVal(id: id), 0xFF) }
        if let (_, id) = p.checkVar("c") { XCTAssertEqual(p.getIntVal(id: id), 0xF0) }
        if let (_, id) = p.checkVar("d") { XCTAssertEqual(p.getIntVal(id: id), 256) }
        if let (_, id) = p.checkVar("e") { XCTAssertEqual(p.getIntVal(id: id), 16) }
    }

    // ================================================================
    // MARK: - TEST 3: Array Boundary Values
    // ================================================================

    /// 3.1 strdim with 1024 elements
    func testStrDim_1024Elements() {
        let script = """
        strdim arr 1024
        arr[0] = 'start'
        arr[1023] = 'end'
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, arrId) = p.checkVar("arr") {
            let e0 = p.getStrVarFromArray(varId: arrId, index: 0)
            XCTAssertEqual(p.getStrVal(id: e0), "start")
            let e1023 = p.getStrVarFromArray(varId: arrId, index: 1023)
            XCTAssertEqual(p.getStrVal(id: e1023), "end")
        } else {
            XCTFail("Array 'arr' not found")
        }
    }

    /// 3.2 intdim with 1024 elements
    func testIntDim_1024Elements() {
        let script = """
        intdim arr 1024
        arr[0] = 1
        arr[1023] = 9999
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, arrId) = p.checkVar("arr") {
            let e0 = p.getIntVarFromArray(varId: arrId, index: 0)
            XCTAssertEqual(p.getIntVal(id: e0), 1)
            let e1023 = p.getIntVarFromArray(varId: arrId, index: 1023)
            XCTAssertEqual(p.getIntVal(id: e1023), 9999)
        } else {
            XCTFail("Array 'arr' not found")
        }
    }

    /// 3.3 Array out-of-bounds access should error
    func testArrayOutOfBounds() {
        let errored = execExpectingError("""
        intdim arr 10
        x = arr[10]
        end
        """)
        XCTAssertTrue(errored, "Accessing arr[10] on size-10 array should throw error")
    }

    /// 3.4 Array negative index should error
    func testArrayNegativeIndex() {
        let errored = execExpectingError("""
        intdim arr 10
        x = arr[0 - 1]
        end
        """)
        XCTAssertTrue(errored, "Negative array index should throw error")
    }

    /// 3.5 Array fill and verify all elements
    func testArrayFillAndVerify() {
        let script = """
        intdim arr 100
        for i 0 99
          arr[i] = i * 2
        next
        x = arr[0]
        y = arr[50]
        z = arr[99]
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("x") { XCTAssertEqual(p.getIntVal(id: id), 0) }
        if let (_, id) = p.checkVar("y") { XCTAssertEqual(p.getIntVal(id: id), 100) }
        if let (_, id) = p.checkVar("z") { XCTAssertEqual(p.getIntVal(id: id), 198) }
    }

    /// 3.6 String array fill and verify
    func testStrArrayFillAndVerify() {
        let script = """
        strdim arr 5
        arr[0] = 'alpha'
        arr[1] = 'beta'
        arr[2] = 'gamma'
        arr[3] = 'delta'
        arr[4] = 'epsilon'
        s = arr[2]
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("s") {
            XCTAssertEqual(p.getStrVal(id: id), "gamma")
        }
    }

    // ================================================================
    // MARK: - TEST 4: Call Stack Depth (max 10)
    // ================================================================

    /// 4.1 Call stack at exactly 10 levels should succeed
    func testCallStack_10Levels() {
        let script = """
        call sub1
        end
        :sub1
          call sub2
          return
        :sub2
          call sub3
          return
        :sub3
          call sub4
          return
        :sub4
          call sub5
          return
        :sub5
          call sub6
          return
        :sub6
          call sub7
          return
        :sub7
          call sub8
          return
        :sub8
          call sub9
          return
        :sub9
          call sub10
          return
        :sub10
          x = 999
          return
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 999)
        }
    }

    /// 4.2 Call stack beyond 10 levels should error (stack overflow)
    func testCallStack_11Levels_Overflow() {
        let script = """
        call sub1
        end
        :sub1
          call sub2
          return
        :sub2
          call sub3
          return
        :sub3
          call sub4
          return
        :sub4
          call sub5
          return
        :sub5
          call sub6
          return
        :sub6
          call sub7
          return
        :sub7
          call sub8
          return
        :sub8
          call sub9
          return
        :sub9
          call sub10
          return
        :sub10
          call sub11
          return
        :sub11
          return
        """
        let errored = execExpectingError(script)
        XCTAssertTrue(errored, "11-level call nesting should trigger stack overflow")
    }

    // ================================================================
    // MARK: - TEST 5: Loop Stack Depth (max 10)
    // ================================================================

    /// 5.1 Nested for loops at 10 levels
    func testNestedForLoops_10Levels() {
        let script = """
        x = 0
        for a 1 2
          for b 1 2
            for c 1 2
              for d 1 2
                for e 1 2
                  for f 1 2
                    for g 1 2
                      for h 1 2
                        for i 1 2
                          for j 1 2
                            x = x + 1
                          next
                        next
                      next
                    next
                  next
                next
              next
            next
          next
        next
        end
        """
        let ok = execSync(script, maxSteps: 200000)
        XCTAssertTrue(ok)

        // 2^10 = 1024 iterations
        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 1024)
        }
    }

    // ================================================================
    // MARK: - TEST 6: Flow Control Nesting
    // ================================================================

    /// 6.1 Deep if-elseif-else nesting
    func testDeepIfNesting() {
        let script = """
        x = 5
        r = 0
        if x == 1 then
          r = 1
        elseif x == 2 then
          r = 2
        elseif x == 3 then
          r = 3
        elseif x == 4 then
          r = 4
        elseif x == 5 then
          r = 5
        elseif x == 6 then
          r = 6
        elseif x == 7 then
          r = 7
        elseif x == 8 then
          r = 8
        elseif x == 9 then
          r = 9
        else
          r = 0
        endif
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("r") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 5)
        }
    }

    /// 6.2 While loop with counter boundary
    func testWhileLoop_BoundaryCount() {
        let script = """
        count = 0
        while count < 1000
          count = count + 1
        endwhile
        end
        """
        let ok = execSync(script, maxSteps: 100000)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("count") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 1000)
        }
    }

    /// 6.3 Mixed control flow: if inside while inside for
    func testMixedControlFlow() {
        let script = """
        total = 0
        for i 1 10
          j = 0
          while j < 5
            if j == 3 then
              total = total + i
            endif
            j = j + 1
          endwhile
        next
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        // total = sum of i from 1..10, each added once when j==3 => 55
        if let (_, id) = interpreter.parser.checkVar("total") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 55)
        }
    }

    /// 6.4 Break from while loop
    func testBreakFromWhile() {
        let script = """
        x = 0
        while 1
          x = x + 1
          if x == 42 then
            break
          endif
        endwhile
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 42)
        }
    }

    /// 6.5 Continue in for loop (skip even numbers)
    func testContinueInForLoop() {
        let script = """
        total = 0
        for i 1 10
          x = i % 2
          if x == 0 then
            continue
          endif
          total = total + i
        next
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        // Sum of odd numbers 1..10: 1+3+5+7+9 = 25
        if let (_, id) = interpreter.parser.checkVar("total") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 25)
        }
    }

    /// 6.6 Goto forward and backward
    func testGotoForwardBackward() {
        let script = """
        x = 0
        goto skip
        x = 999
        :skip
        x = 42
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 42)
        }
    }

    // ================================================================
    // MARK: - TEST 7: String Operations Boundary
    // ================================================================

    /// 7.1 strsplit with maximum segments
    func testStrsplit_ManySegments() {
        let script = """
        s = 'a,b,c,d,e,f,g,h,i,j'
        strdim parts 10
        strsplit s ',' parts
        x = parts[0]
        y = parts[9]
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("x") { XCTAssertEqual(p.getStrVal(id: id), "a") }
        if let (_, id) = p.checkVar("y") { XCTAssertEqual(p.getStrVal(id: id), "j") }
        // result should be 10 (number of parts)
        XCTAssertEqual(p.getIntVal(id: p.resultVarId), 10)
    }

    /// 7.2 strcompare case sensitivity
    func testStrcompare_CaseSensitive() {
        let script = """
        strcompare 'ABC' 'abc'
        x = result
        strcompare 'abc' 'abc'
        y = result
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("x") {
            XCTAssertNotEqual(p.getIntVal(id: id), 0, "'ABC' and 'abc' should not be equal")
        }
        if let (_, id) = p.checkVar("y") {
            XCTAssertEqual(p.getIntVal(id: id), 0, "'abc' and 'abc' should be equal")
        }
    }

    /// 7.3 str2int and int2str roundtrip
    func testStr2IntInt2Str_Roundtrip() {
        let script = """
        str2int x '12345'
        int2str s x
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("x") { XCTAssertEqual(p.getIntVal(id: id), 12345) }
        if let (_, id) = p.checkVar("s") { XCTAssertEqual(p.getStrVal(id: id), "12345") }
    }

    /// 7.4 sprintf2 with various format specifiers
    func testSprintf2_Formats() {
        let script = """
        sprintf2 s1 'dec=%d hex=%x' 255 255
        sprintf2 s2 'str=%s num=%d' 'test' 42
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("s1") {
            XCTAssertEqual(p.getStrVal(id: id), "dec=255 hex=ff")
        }
        if let (_, id) = p.checkVar("s2") {
            XCTAssertEqual(p.getStrVal(id: id), "str=test num=42")
        }
    }

    /// 7.5 tolower / toupper
    func testToLowerToUpper() {
        let script = """
        s1 = 'Hello World'
        tolower s1
        s2 = 'Hello World'
        toupper s2
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("s1") { XCTAssertEqual(p.getStrVal(id: id), "hello world") }
        if let (_, id) = p.checkVar("s2") { XCTAssertEqual(p.getStrVal(id: id), "HELLO WORLD") }
    }

    // ================================================================
    // MARK: - TEST 8: File I/O Boundary
    // ================================================================

    /// 8.1 File open with non-existent path should return -1
    func testFileOpen_NonExistent() {
        let script = """
        fileopen fh '/tmp/__nonexistent_ttl_test_file__.txt' 0
        x = result
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), -1)
        }
    }

    /// 8.2 File write and readback
    func testFileWriteReadback() {
        let path = "/tmp/ttl_boundary_test_\(ProcessInfo.processInfo.processIdentifier).txt"
        let script = """
        fileopen fh '\(path)' 0
        filewriteln fh 'line1'
        filewriteln fh 'line2'
        filewriteln fh 'line3'
        fileclose fh
        fileopen fh '\(path)' 0
        filereadln fh s1
        filereadln fh s2
        filereadln fh s3
        fileclose fh
        filedelete '\(path)'
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("s1") { XCTAssertEqual(p.getStrVal(id: id), "line1") }
        if let (_, id) = p.checkVar("s2") { XCTAssertEqual(p.getStrVal(id: id), "line2") }
        if let (_, id) = p.checkVar("s3") { XCTAssertEqual(p.getStrVal(id: id), "line3") }
    }

    // ================================================================
    // MARK: - TEST 9: Parser Token Edge Cases
    // ================================================================

    /// 9.1 Line with only comment
    func testCommentOnlyLine() {
        let script = """
        ; This is a comment
        x = 1
        ; Another comment
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 1)
        }
    }

    /// 9.2 Block comments
    func testBlockComments() {
        let script = """
        x = 1
        /* This is a block comment
           spanning multiple lines */
        y = 2
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("x") { XCTAssertEqual(p.getIntVal(id: id), 1) }
        if let (_, id) = p.checkVar("y") { XCTAssertEqual(p.getIntVal(id: id), 2) }
    }

    /// 9.3 Char code parsing (#65 = 'A', #$41 = 'A')
    func testCharCodeParsing() {
        let script = """
        s1 = #65#66#67
        s2 = #$41#$42#$43
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("s1") { XCTAssertEqual(p.getStrVal(id: id), "ABC") }
        if let (_, id) = p.checkVar("s2") { XCTAssertEqual(p.getStrVal(id: id), "ABC") }
    }

    /// 9.4 Mixed quote styles in strings
    func testMixedQuoteStyles() {
        let script = """
        s1 = "double quoted"
        s2 = 'single quoted'
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        let p = interpreter.parser
        if let (_, id) = p.checkVar("s1") { XCTAssertEqual(p.getStrVal(id: id), "double quoted") }
        if let (_, id) = p.checkVar("s2") { XCTAssertEqual(p.getStrVal(id: id), "single quoted") }
    }

    /// 9.5 Variable name case insensitivity
    func testVariableNameCaseInsensitive() {
        let script = """
        MyVar = 42
        x = myvar
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 42)
        }
    }

    // ================================================================
    // MARK: - TEST 10: Communication Argument Patterns (Parser Only)
    // ================================================================

    /// 10.1 Send with char codes: #65#66#67 = "ABC"
    func testSendCharCodes() {
        delegate.isConnected = true
        let script = """
        send #65#66#67
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)
        XCTAssertTrue(delegate.sentStrings.contains("ABC") || delegate.sentData.contains(Data([65, 66, 67])))
    }

    /// 10.2 Send with hex char codes
    func testSendHexCharCodes() {
        delegate.isConnected = true
        let script = """
        send #$48#$49
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)
        // $48 = 'H', $49 = 'I'
        let found = delegate.sentStrings.contains(where: { $0.contains("HI") }) ||
                    delegate.sentData.contains(where: { $0 == Data([0x48, 0x49]) })
        XCTAssertTrue(found, "Should have sent 'HI' via char codes")
    }

    // ================================================================
    // MARK: - TEST 11: Do-Until / Do-Loop patterns
    // ================================================================

    /// 11.1 Do-until basic
    func testDoUntil_Basic() {
        let script = """
        x = 0
        do
          x = x + 1
        until x == 10
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 10)
        }
    }

    /// 11.2 Do-loop with break
    func testDoLoop_WithBreak() {
        let script = """
        x = 0
        do
          x = x + 1
          if x == 25 then
            break
          endif
        loop
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)

        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 25)
        }
    }

    // ================================================================
    // MARK: - TEST 12: Parser Unit - Direct API
    // ================================================================

    /// 12.1 MaxNameLen (128) - variable name at boundary
    func testMaxNameLen_Boundary() {
        let parser = TTLParser()
        parser.loadScript("")
        let longName = String(repeating: "a", count: 128)
        let id = parser.newIntVar(longName, value: 42)
        XCTAssertEqual(parser.getIntVal(id: id), 42)
        XCTAssertNotNil(parser.checkVar(longName))
    }

    /// 12.2 Packed array index encoding
    func testPackedArrayIndex_HighIndex() {
        let parser = TTLParser()
        parser.loadScript("")
        let arrId = parser.newIntArrayVar("big", size: 65536)
        let elemId = parser.getIntVarFromArray(varId: arrId, index: 65535)
        parser.setIntVal(id: elemId, value: 777)
        XCTAssertEqual(parser.getIntVal(id: elemId), 777)
    }

    /// 12.3 Many variables
    func testManyVariables() {
        let parser = TTLParser()
        parser.loadScript("")
        for i in 0..<200 {
            _ = parser.newIntVar("var\(i)", value: i)
        }
        // Verify first and last
        if let (_, id) = parser.checkVar("var0") {
            XCTAssertEqual(parser.getIntVal(id: id), 0)
        }
        if let (_, id) = parser.checkVar("var199") {
            XCTAssertEqual(parser.getIntVal(id: id), 199)
        }
    }

    /// 12.4 Expression parsing: deeply nested parentheses
    func testDeepParentheses() {
        let script = """
        x = (((((1 + 2) * 3) + 4) * 5) + 6)
        end
        """
        let ok = execSync(script)
        XCTAssertTrue(ok)
        // ((((3)*3)+4)*5)+6 = ((9+4)*5)+6 = (13*5)+6 = 65+6 = 71
        if let (_, id) = interpreter.parser.checkVar("x") {
            XCTAssertEqual(interpreter.parser.getIntVal(id: id), 71)
        }
    }
}

#endif
