/*
 * TTL Parser Unit Tests
 * Phase 1: Tokenizer, expression parser, variable management
 */

import XCTest
@testable import TeraTermMac

// MARK: - TTL Parser Tests

final class TTLParserTests: XCTestCase {

    var parser: TTLParser!

    override func setUp() {
        super.setUp()
        parser = TTLParser()
    }

    // MARK: - Script Loading

    func testLoadScript() {
        parser.loadScript("a = 1\nb = 2")
        XCTAssertEqual(parser.lines.count, 2)
        XCTAssertEqual(parser.currentLine, 0)
        XCTAssertEqual(parser.status, .run)
    }

    func testLoadScriptCreatesSystemVariables() {
        parser.loadScript("")
        XCTAssertGreaterThanOrEqual(parser.resultVarId, 0)
        XCTAssertGreaterThanOrEqual(parser.inputStrVarId, 0)
        XCTAssertGreaterThanOrEqual(parser.matchStrVarId, 0)
        XCTAssertGreaterThanOrEqual(parser.timeoutVarId, 0)
        XCTAssertGreaterThanOrEqual(parser.mtimeoutVarId, 0)
        XCTAssertGreaterThanOrEqual(parser.paramCntVarId, 0)
        XCTAssertEqual(parser.paramVarIds.count, 9)
    }

    func testLoadScriptResetsState() {
        parser.loadScript("line1")
        parser.currentLine = 1
        parser.commenting = true
        parser.loadScript("new script")
        XCTAssertEqual(parser.currentLine, 0)
        XCTAssertFalse(parser.commenting)
        XCTAssertTrue(parser.callStack.isEmpty)
        XCTAssertTrue(parser.loopStack.isEmpty)
    }

    // MARK: - Line Management

    func testGetNewLine() {
        parser.loadScript("line0\nline1\nline2")
        XCTAssertTrue(parser.getNewLine())
        XCTAssertEqual(parser.lineBuffer, "line0")
        XCTAssertEqual(parser.currentLine, 1)

        XCTAssertTrue(parser.getNewLine())
        XCTAssertEqual(parser.lineBuffer, "line1")

        XCTAssertTrue(parser.getNewLine())
        XCTAssertEqual(parser.lineBuffer, "line2")

        XCTAssertFalse(parser.getNewLine()) // past end
    }

    // MARK: - Variable Management

    func testNewIntVar() {
        parser.loadScript("")
        let id = parser.newIntVar("count", value: 42)
        XCTAssertEqual(parser.getIntVal(id: id), 42)
    }

    func testNewStrVar() {
        parser.loadScript("")
        let id = parser.newStrVar("name", value: "test")
        XCTAssertEqual(parser.getStrVal(id: id), "test")
    }

    func testNewIntArrayVar() {
        parser.loadScript("")
        let id = parser.newIntArrayVar("arr", size: 5)
        XCTAssertEqual(parser.variables[id].intArray.count, 5)

        // Set/get via packed ID
        let elemId = parser.getIntVarFromArray(varId: id, index: 2)
        parser.setIntVal(id: elemId, value: 99)
        XCTAssertEqual(parser.getIntVal(id: elemId), 99)
    }

    func testNewStrArrayVar() {
        parser.loadScript("")
        let id = parser.newStrArrayVar("sarr", size: 3)
        XCTAssertEqual(parser.variables[id].strArray.count, 3)

        let elemId = parser.getStrVarFromArray(varId: id, index: 1)
        parser.setStrVal(id: elemId, value: "hello")
        XCTAssertEqual(parser.getStrVal(id: elemId), "hello")
    }

    func testCheckVar() {
        parser.loadScript("")
        let id = parser.newIntVar("counter", value: 10)
        let result = parser.checkVar("counter")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .integer)
        XCTAssertEqual(result?.id, id)
    }

    func testCheckVarCaseInsensitive() {
        parser.loadScript("")
        parser.newStrVar("MyVar", value: "abc")
        XCTAssertNotNil(parser.checkVar("myvar"))
        XCTAssertNotNil(parser.checkVar("MYVAR"))
        XCTAssertNotNil(parser.checkVar("MyVar"))
    }

    func testCheckVarNotFound() {
        parser.loadScript("")
        XCTAssertNil(parser.checkVar("nonexistent"))
    }

    func testSetResult() {
        parser.loadScript("")
        parser.setResult(42)
        XCTAssertEqual(parser.getIntVal(id: parser.resultVarId), 42)
    }

    func testSetInputStr() {
        parser.loadScript("")
        parser.setInputStr("test input")
        XCTAssertEqual(parser.getStrVal(id: parser.inputStrVarId), "test input")
    }

    func testSetMatchStr() {
        parser.loadScript("")
        parser.setMatchStr("matched text")
        XCTAssertEqual(parser.getStrVal(id: parser.matchStrVarId), "matched text")
    }

    func testLabelVar() {
        parser.loadScript("")
        let id = parser.newLabVar("myLabel", position: 10, level: 0)
        let result = parser.checkVar("myLabel")
        XCTAssertEqual(result?.type, .label)
        XCTAssertEqual(parser.variables[id].label.position, 10)
    }

    func testDelLabVar() {
        parser.loadScript("")
        parser.newLabVar("lab1", position: 0, level: 0)
        parser.newLabVar("lab2", position: 5, level: 1)
        parser.newLabVar("lab3", position: 10, level: 2)
        parser.delLabVar(level: 1)
        XCTAssertNotNil(parser.checkVar("lab1"))
        XCTAssertNil(parser.checkVar("lab2"))
        XCTAssertNil(parser.checkVar("lab3"))
    }

    // MARK: - Tokenizer

    func testGetFirstCharSkipsWhitespace() {
        parser.loadScript("")
        parser.lineBuffer = "   A"
        parser.linePtr = 0
        let ch = parser.getFirstChar()
        XCTAssertEqual(ch, "A")
    }

    func testGetFirstCharSkipsTab() {
        parser.loadScript("")
        parser.lineBuffer = "\t\tB"
        parser.linePtr = 0
        let ch = parser.getFirstChar()
        XCTAssertEqual(ch, "B")
    }

    func testGetFirstCharSkipsLineComment() {
        parser.loadScript("")
        parser.lineBuffer = "; this is a comment"
        parser.linePtr = 0
        XCTAssertNil(parser.getFirstChar())
    }

    func testGetFirstCharSkipsBlockComment() {
        parser.loadScript("")
        parser.lineBuffer = "/* comment */ X"
        parser.linePtr = 0
        let ch = parser.getFirstChar()
        XCTAssertEqual(ch, "X")
    }

    func testGetFirstCharMultilineBlockComment() {
        parser.loadScript("")
        parser.lineBuffer = "/* start of comment"
        parser.linePtr = 0
        XCTAssertNil(parser.getFirstChar())
        XCTAssertTrue(parser.commenting)

        parser.lineBuffer = "end of comment */ Y"
        parser.linePtr = 0
        let ch = parser.getFirstChar()
        XCTAssertEqual(ch, "Y")
        XCTAssertFalse(parser.commenting)
    }

    func testGetIdentifier() {
        parser.loadScript("")
        parser.lineBuffer = "myVar123"
        parser.linePtr = 0
        XCTAssertEqual(parser.getIdentifier(), "myVar123")
    }

    func testGetIdentifierWithUnderscore() {
        parser.loadScript("")
        parser.lineBuffer = "_my_var"
        parser.linePtr = 0
        XCTAssertEqual(parser.getIdentifier(), "_my_var")
    }

    func testGetIdentifierFailsOnNumber() {
        parser.loadScript("")
        parser.lineBuffer = "123abc"
        parser.linePtr = 0
        XCTAssertNil(parser.getIdentifier())
    }

    func testGetString() {
        parser.loadScript("")
        parser.lineBuffer = "'Hello World'"
        parser.linePtr = 0
        let result = parser.getString()
        if case .success(let s) = result {
            XCTAssertEqual(s, "Hello World")
        } else {
            XCTFail("Expected success")
        }
    }

    func testGetStringDoubleQuoted() {
        parser.loadScript("")
        parser.lineBuffer = "\"Test String\""
        parser.linePtr = 0
        let result = parser.getString()
        if case .success(let s) = result {
            XCTAssertEqual(s, "Test String")
        } else {
            XCTFail("Expected success")
        }
    }

    func testGetStringWithCharCode() {
        parser.loadScript("")
        parser.lineBuffer = "#65" // 'A'
        parser.linePtr = 0
        let result = parser.getString()
        if case .success(let s) = result {
            XCTAssertEqual(s, "A")
        } else {
            XCTFail("Expected success")
        }
    }

    func testGetStringWithHexCharCode() {
        parser.loadScript("")
        parser.lineBuffer = "#$41" // 'A' in hex
        parser.linePtr = 0
        let result = parser.getString()
        if case .success(let s) = result {
            XCTAssertEqual(s, "A")
        } else {
            XCTFail("Expected success")
        }
    }

    func testGetNumber() {
        parser.loadScript("")
        parser.lineBuffer = "12345"
        parser.linePtr = 0
        XCTAssertEqual(parser.getNumber(), 12345)
    }

    func testGetNumberHex() {
        parser.loadScript("")
        parser.lineBuffer = "$FF"
        parser.linePtr = 0
        XCTAssertEqual(parser.getNumber(), 255)
    }

    func testGetNumberHexLarge() {
        parser.loadScript("")
        parser.lineBuffer = "$DEADBEEF"
        parser.linePtr = 0
        XCTAssertEqual(parser.getNumber(), 0xDEADBEEF)
    }

    func testCheckParameterGiven() {
        parser.loadScript("")
        parser.lineBuffer = "  'hello'"
        parser.linePtr = 0
        XCTAssertTrue(parser.checkParameterGiven())
        XCTAssertEqual(parser.linePtr, 0) // Should not consume
    }

    func testCheckParameterGivenEmpty() {
        parser.loadScript("")
        parser.lineBuffer = ""
        parser.linePtr = 0
        XCTAssertFalse(parser.checkParameterGiven())
    }

    // MARK: - Reserved Word Lookup

    func testCheckReservedWord() {
        parser.loadScript("")
        XCTAssertEqual(parser.checkReservedWord("strconcat"), .strConcat)
        XCTAssertEqual(parser.checkReservedWord("STRCONCAT"), .strConcat)
        XCTAssertEqual(parser.checkReservedWord("StrConcat"), .strConcat)
    }

    func testCheckReservedWordAllCategories() {
        parser.loadScript("")
        // Control flow
        XCTAssertEqual(parser.checkReservedWord("if"), .if_)
        XCTAssertEqual(parser.checkReservedWord("else"), .else_)
        XCTAssertEqual(parser.checkReservedWord("elseif"), .elseIf)
        XCTAssertEqual(parser.checkReservedWord("endif"), .endIf)
        XCTAssertEqual(parser.checkReservedWord("goto"), .goto_)
        XCTAssertEqual(parser.checkReservedWord("call"), .call)
        XCTAssertEqual(parser.checkReservedWord("return"), .return)
        XCTAssertEqual(parser.checkReservedWord("for"), .for_)
        XCTAssertEqual(parser.checkReservedWord("next"), .next)
        XCTAssertEqual(parser.checkReservedWord("while"), .while_)
        XCTAssertEqual(parser.checkReservedWord("endwhile"), .endWhile)
        XCTAssertEqual(parser.checkReservedWord("do"), .do_)
        XCTAssertEqual(parser.checkReservedWord("loop"), .loop)
        XCTAssertEqual(parser.checkReservedWord("until"), .until)
        XCTAssertEqual(parser.checkReservedWord("enduntil"), .endUntil)
        XCTAssertEqual(parser.checkReservedWord("break"), .break_)
        XCTAssertEqual(parser.checkReservedWord("continue"), .continue_)
        XCTAssertEqual(parser.checkReservedWord("end"), .end)
        XCTAssertEqual(parser.checkReservedWord("exit"), .exit)
        XCTAssertEqual(parser.checkReservedWord("include"), .include)

        // String operations
        XCTAssertEqual(parser.checkReservedWord("strlen"), .strLen)
        XCTAssertEqual(parser.checkReservedWord("strcopy"), .strCopy)
        XCTAssertEqual(parser.checkReservedWord("strcompare"), .strCompare)
        XCTAssertEqual(parser.checkReservedWord("strscan"), .strScan)
        XCTAssertEqual(parser.checkReservedWord("strmatch"), .strMatch)
        XCTAssertEqual(parser.checkReservedWord("strinsert"), .strInsert)
        XCTAssertEqual(parser.checkReservedWord("strremove"), .strRemove)
        XCTAssertEqual(parser.checkReservedWord("strreplace"), .strReplace)
        XCTAssertEqual(parser.checkReservedWord("strtrim"), .strTrim)
        XCTAssertEqual(parser.checkReservedWord("strsplit"), .strSplit)
        XCTAssertEqual(parser.checkReservedWord("strjoin"), .strJoin)
        XCTAssertEqual(parser.checkReservedWord("strspecial"), .strSpecial)
        XCTAssertEqual(parser.checkReservedWord("tolower"), .toLower)
        XCTAssertEqual(parser.checkReservedWord("toupper"), .toUpper)
        XCTAssertEqual(parser.checkReservedWord("str2int"), .str2Int)
        XCTAssertEqual(parser.checkReservedWord("int2str"), .int2Str)
        XCTAssertEqual(parser.checkReservedWord("str2code"), .str2Code)
        XCTAssertEqual(parser.checkReservedWord("code2str"), .code2Str)
        XCTAssertEqual(parser.checkReservedWord("sprintf"), .sprintf)
        XCTAssertEqual(parser.checkReservedWord("sprintf2"), .sprintf2)

        // File I/O
        XCTAssertEqual(parser.checkReservedWord("fileopen"), .fileOpen)
        XCTAssertEqual(parser.checkReservedWord("fileclose"), .fileClose)
        XCTAssertEqual(parser.checkReservedWord("filereadln"), .fileReadln)
        XCTAssertEqual(parser.checkReservedWord("fileread"), .fileRead)
        XCTAssertEqual(parser.checkReservedWord("filewrite"), .fileWrite)
        XCTAssertEqual(parser.checkReservedWord("filewriteln"), .fileWriteLn)
        XCTAssertEqual(parser.checkReservedWord("filecreate"), .fileCreate)
        XCTAssertEqual(parser.checkReservedWord("filedelete"), .fileDelete)
        XCTAssertEqual(parser.checkReservedWord("filecopy"), .fileCopy)
        XCTAssertEqual(parser.checkReservedWord("filerename"), .fileRename)
        XCTAssertEqual(parser.checkReservedWord("filesearch"), .fileSearch)

        // Communication
        XCTAssertEqual(parser.checkReservedWord("send"), .send)
        XCTAssertEqual(parser.checkReservedWord("sendln"), .sendLn)
        XCTAssertEqual(parser.checkReservedWord("wait"), .wait)
        XCTAssertEqual(parser.checkReservedWord("waitln"), .waitLn)
        XCTAssertEqual(parser.checkReservedWord("waitregex"), .waitRegex)
        XCTAssertEqual(parser.checkReservedWord("waitn"), .waitN)
        XCTAssertEqual(parser.checkReservedWord("wait4all"), .wait4all)
        XCTAssertEqual(parser.checkReservedWord("recvln"), .recvLn)
        XCTAssertEqual(parser.checkReservedWord("flushrecv"), .flushRecv)

        // Array
        XCTAssertEqual(parser.checkReservedWord("intdim"), .intDim)
        XCTAssertEqual(parser.checkReservedWord("strdim"), .strDim)

        // Misc
        XCTAssertEqual(parser.checkReservedWord("beep"), .beep)
        XCTAssertEqual(parser.checkReservedWord("messagebox"), .messageBox)
        XCTAssertEqual(parser.checkReservedWord("yesnobox"), .yesNoBox)
        XCTAssertEqual(parser.checkReservedWord("random"), .random)
        XCTAssertEqual(parser.checkReservedWord("setdlgpos"), .setDlgPos)

        // Checksum/CRC
        XCTAssertEqual(parser.checkReservedWord("crc16"), .crc16)
        XCTAssertEqual(parser.checkReservedWord("crc32"), .crc32)
        XCTAssertEqual(parser.checkReservedWord("checksum8"), .checksum8)
        XCTAssertEqual(parser.checkReservedWord("checksum16"), .checksum16)
        XCTAssertEqual(parser.checkReservedWord("checksum32"), .checksum32)
    }

    func testCheckReservedWordUnknown() {
        parser.loadScript("")
        XCTAssertNil(parser.checkReservedWord("notacommand"))
    }

    func testCheckReservedOperator() {
        parser.loadScript("")
        XCTAssertEqual(parser.checkReservedOperator("and"), .bAnd)
        XCTAssertEqual(parser.checkReservedOperator("or"), .bOr)
        XCTAssertEqual(parser.checkReservedOperator("not"), .bNot)
        XCTAssertEqual(parser.checkReservedOperator("xor"), .bXor)
        XCTAssertNil(parser.checkReservedOperator("foo"))
    }

    // MARK: - Operator Parsing

    func testGetOperatorArithmetic() {
        parser.loadScript("")
        let ops: [(String, TTLOperator)] = [
            ("*", .mul), ("+", .plus), ("-", .minus),
            ("/", .div), ("%", .mod),
        ]
        for (input, expected) in ops {
            parser.lineBuffer = input
            parser.linePtr = 0
            XCTAssertEqual(parser.getOperator(), expected, "Failed for '\(input)'")
        }
    }

    func testGetOperatorComparison() {
        parser.loadScript("")
        let ops: [(String, TTLOperator)] = [
            ("<", .lt), (">", .gt), ("<=", .le),
            (">=", .ge), ("<>", .ne), ("!=", .ne),
            ("==", .eq), ("=", .eq),
        ]
        for (input, expected) in ops {
            parser.lineBuffer = input + " "
            parser.linePtr = 0
            XCTAssertEqual(parser.getOperator(), expected, "Failed for '\(input)'")
        }
    }

    func testGetOperatorBitwise() {
        parser.loadScript("")
        parser.lineBuffer = "^"
        parser.linePtr = 0
        XCTAssertEqual(parser.getOperator(), .bXor)

        parser.lineBuffer = "~ "
        parser.linePtr = 0
        XCTAssertEqual(parser.getOperator(), .bNot)
    }

    func testGetOperatorLogical() {
        parser.loadScript("")
        parser.lineBuffer = "&& "
        parser.linePtr = 0
        XCTAssertEqual(parser.getOperator(), .lAnd)

        parser.lineBuffer = "|| "
        parser.linePtr = 0
        XCTAssertEqual(parser.getOperator(), .lOr)
    }

    func testGetOperatorShift() {
        parser.loadScript("")
        parser.lineBuffer = "<< "
        parser.linePtr = 0
        XCTAssertEqual(parser.getOperator(), .alShift)

        parser.lineBuffer = ">> "
        parser.linePtr = 0
        XCTAssertEqual(parser.getOperator(), .arShift)
    }

    // MARK: - Expression Parser

    func testGetExpressionSimpleInt() {
        parser.loadScript("")
        parser.newIntVar("x", value: 42)
        parser.lineBuffer = "x"
        parser.linePtr = 0
        let result = try? parser.getExpression()
        if case .integer(let v) = result {
            XCTAssertEqual(v, 42)
        } else {
            XCTFail("Expected integer result")
        }
    }

    func testGetExpressionNumber() {
        parser.loadScript("")
        parser.lineBuffer = "100"
        parser.linePtr = 0
        let result = try? parser.getExpression()
        if case .integer(let v) = result {
            XCTAssertEqual(v, 100)
        } else {
            XCTFail("Expected integer 100")
        }
    }

    func testGetExpressionHexNumber() {
        parser.loadScript("")
        parser.lineBuffer = "$FF"
        parser.linePtr = 0
        let result = try? parser.getExpression()
        if case .integer(let v) = result {
            XCTAssertEqual(v, 255)
        } else {
            XCTFail("Expected integer 255")
        }
    }

    func testGetExpressionAddition() {
        parser.loadScript("")
        parser.newIntVar("a", value: 10)
        parser.newIntVar("b", value: 20)
        parser.lineBuffer = "a + b"
        parser.linePtr = 0
        let result = try? parser.getIntExpression()
        XCTAssertEqual(result, 30)
    }

    func testGetExpressionSubtraction() {
        parser.loadScript("")
        parser.newIntVar("x", value: 50)
        parser.lineBuffer = "x - 20"
        parser.linePtr = 0
        let result = try? parser.getIntExpression()
        XCTAssertEqual(result, 30)
    }

    func testGetExpressionMultiplication() {
        parser.loadScript("")
        parser.newIntVar("x", value: 5)
        parser.lineBuffer = "x * 6"
        parser.linePtr = 0
        let result = try? parser.getIntExpression()
        XCTAssertEqual(result, 30)
    }

    func testGetExpressionDivision() {
        parser.loadScript("")
        parser.newIntVar("x", value: 100)
        parser.lineBuffer = "x / 4"
        parser.linePtr = 0
        let result = try? parser.getIntExpression()
        XCTAssertEqual(result, 25)
    }

    func testGetExpressionModulo() {
        parser.loadScript("")
        parser.newIntVar("x", value: 17)
        parser.lineBuffer = "x % 5"
        parser.linePtr = 0
        let result = try? parser.getIntExpression()
        XCTAssertEqual(result, 2)
    }

    func testGetExpressionPrecedence() {
        parser.loadScript("")
        parser.newIntVar("a", value: 2)
        parser.newIntVar("b", value: 3)
        parser.newIntVar("c", value: 4)
        parser.lineBuffer = "a + b * c"
        parser.linePtr = 0
        let result = try? parser.getIntExpression()
        XCTAssertEqual(result, 14) // 2 + (3 * 4)
    }

    func testGetExpressionParentheses() {
        parser.loadScript("")
        parser.newIntVar("a", value: 2)
        parser.newIntVar("b", value: 3)
        parser.newIntVar("c", value: 4)
        parser.lineBuffer = "(a + b) * c"
        parser.linePtr = 0
        let result = try? parser.getIntExpression()
        XCTAssertEqual(result, 20)
    }

    func testGetExpressionNegation() {
        parser.loadScript("")
        parser.newIntVar("x", value: 42)
        parser.lineBuffer = "-x"
        parser.linePtr = 0
        let result = try? parser.getIntExpression()
        XCTAssertEqual(result, -42)
    }

    func testGetExpressionComparison() {
        parser.loadScript("")
        parser.newIntVar("a", value: 5)
        parser.newIntVar("b", value: 10)

        parser.lineBuffer = "a < b"
        parser.linePtr = 0
        XCTAssertEqual(try? parser.getIntExpression(), 1)

        parser.lineBuffer = "a > b"
        parser.linePtr = 0
        XCTAssertEqual(try? parser.getIntExpression(), 0)

        parser.lineBuffer = "a = a"
        parser.linePtr = 0
        XCTAssertEqual(try? parser.getIntExpression(), 1)
    }

    func testGetExpressionBitwiseOps() {
        parser.loadScript("")
        parser.newIntVar("a", value: 0xFF)
        parser.newIntVar("b", value: 0x0F)

        parser.lineBuffer = "a & b"
        parser.linePtr = 0
        XCTAssertEqual(try? parser.getIntExpression(), 0x0F)

        parser.lineBuffer = "a ^ b"
        parser.linePtr = 0
        XCTAssertEqual(try? parser.getIntExpression(), 0xF0)
    }

    func testGetExpressionLogicalOps() {
        parser.loadScript("")
        parser.newIntVar("t", value: 1)
        parser.newIntVar("f", value: 0)

        parser.lineBuffer = "t && f"
        parser.linePtr = 0
        XCTAssertEqual(try? parser.getIntExpression(), 0)

        parser.lineBuffer = "t || f"
        parser.linePtr = 0
        XCTAssertEqual(try? parser.getIntExpression(), 1)
    }

    func testGetExpressionStringVar() {
        parser.loadScript("")
        let sid = parser.newStrVar("msg", value: "hello")
        parser.lineBuffer = "msg"
        parser.linePtr = 0
        let result = try? parser.getExpression()
        if case .string(let id) = result {
            XCTAssertEqual(parser.getStrVal(id: id), "hello")
        } else {
            XCTFail("Expected string result")
        }
    }

    func testGetStrExpression() {
        parser.loadScript("")
        parser.lineBuffer = "'hello world'"
        parser.linePtr = 0
        let result = try? parser.getStrExpression()
        XCTAssertEqual(result, "hello world")
    }

    func testGetStrExpressionFromVar() {
        parser.loadScript("")
        parser.newStrVar("s", value: "from var")
        parser.lineBuffer = "s"
        parser.linePtr = 0
        let result = try? parser.getStrExpression()
        XCTAssertEqual(result, "from var")
    }

    func testGetIntExpressionTypeMismatch() {
        parser.loadScript("")
        parser.newStrVar("s", value: "text")
        parser.lineBuffer = "s"
        parser.linePtr = 0
        XCTAssertThrowsError(try parser.getIntExpression())
    }

    // MARK: - Array Index Parsing

    func testGetIndexParsing() {
        parser.loadScript("")
        parser.newIntVar("idx", value: 3)
        parser.lineBuffer = "[idx]"
        parser.linePtr = 0
        let index = try? parser.getIndex()
        XCTAssertEqual(index, 3)
    }

    func testGetIndexLiteral() {
        parser.loadScript("")
        parser.lineBuffer = "[5]"
        parser.linePtr = 0
        let index = try? parser.getIndex()
        XCTAssertEqual(index, 5)
    }

    func testGetIntVarFromArrayPackedId() {
        parser.loadScript("")
        let arrId = parser.newIntArrayVar("arr", size: 10)
        let packedId = parser.getIntVarFromArray(varId: arrId, index: 3)

        // Verify packed format: (varId+1) << 16 | index
        XCTAssertEqual(packedId >> 16, arrId + 1)
        XCTAssertEqual(packedId & 0xFFFF, 3)

        parser.setIntVal(id: packedId, value: 777)
        XCTAssertEqual(parser.getIntVal(id: packedId), 777)
    }

    func testArrayBoundsCheck() {
        parser.loadScript("")
        let arrId = parser.newIntArrayVar("arr", size: 3)
        let outOfBounds = parser.getIntVarFromArray(varId: arrId, index: 100)
        // Out of bounds returns 0
        XCTAssertEqual(parser.getIntVal(id: outOfBounds), 0)
    }

    // MARK: - Get Int/Str Var

    func testGetIntVar() {
        parser.loadScript("")
        parser.newIntVar("count", value: 0)
        parser.lineBuffer = "count"
        parser.linePtr = 0
        let id = try? parser.getIntVar()
        XCTAssertNotNil(id)
    }

    func testGetStrVar() {
        parser.loadScript("")
        parser.newStrVar("name", value: "")
        parser.lineBuffer = "name"
        parser.linePtr = 0
        let id = try? parser.getStrVar()
        XCTAssertNotNil(id)
    }

    func testGetIntVarCreatesNew() {
        parser.loadScript("")
        parser.lineBuffer = "newvar"
        parser.linePtr = 0
        let id = try? parser.getIntVar()
        XCTAssertNotNil(id)
        XCTAssertNotNil(parser.checkVar("newvar"))
    }
}
