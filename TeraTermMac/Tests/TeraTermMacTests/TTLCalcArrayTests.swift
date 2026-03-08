/*
 * TTL Calculation & Array Tests
 * Phase 1: intdim, strdim, variable calculations, multi-loop integrity
 */

import XCTest
@testable import TeraTermMac

final class TTLCalcArrayTests: XCTestCase {

    var parser: TTLParser!

    override func setUp() {
        super.setUp()
        parser = TTLParser()
        parser.loadScript("")
    }

    // MARK: - intdim / strdim

    func testIntDim_BasicAllocation() {
        let id = parser.newIntArrayVar("arr", size: 10)
        XCTAssertEqual(parser.variables[id].intArray.count, 10)
        XCTAssertEqual(parser.variables[id].type, .intArray)
    }

    func testIntDim_AllZeroInit() {
        let id = parser.newIntArrayVar("arr", size: 5)
        for i in 0..<5 {
            XCTAssertEqual(parser.variables[id].intArray[i], 0)
        }
    }

    func testStrDim_BasicAllocation() {
        let id = parser.newStrArrayVar("sarr", size: 8)
        XCTAssertEqual(parser.variables[id].strArray.count, 8)
        XCTAssertEqual(parser.variables[id].type, .strArray)
    }

    func testStrDim_AllEmptyInit() {
        let id = parser.newStrArrayVar("sarr", size: 4)
        for i in 0..<4 {
            XCTAssertEqual(parser.variables[id].strArray[i], "")
        }
    }

    func testIntDim_LargeArray() {
        let id = parser.newIntArrayVar("big", size: 1000)
        XCTAssertEqual(parser.variables[id].intArray.count, 1000)
    }

    func testStrDim_LargeArray() {
        let id = parser.newStrArrayVar("big", size: 1000)
        XCTAssertEqual(parser.variables[id].strArray.count, 1000)
    }

    // MARK: - Array Element Access via Packed IDs

    func testIntArraySetGet() {
        let arrId = parser.newIntArrayVar("arr", size: 5)
        for i in 0..<5 {
            let elemId = parser.getIntVarFromArray(varId: arrId, index: i)
            parser.setIntVal(id: elemId, value: i * 10)
        }
        for i in 0..<5 {
            let elemId = parser.getIntVarFromArray(varId: arrId, index: i)
            XCTAssertEqual(parser.getIntVal(id: elemId), i * 10)
        }
    }

    func testStrArraySetGet() {
        let arrId = parser.newStrArrayVar("sarr", size: 3)
        let values = ["alpha", "beta", "gamma"]
        for i in 0..<3 {
            let elemId = parser.getStrVarFromArray(varId: arrId, index: i)
            parser.setStrVal(id: elemId, value: values[i])
        }
        for i in 0..<3 {
            let elemId = parser.getStrVarFromArray(varId: arrId, index: i)
            XCTAssertEqual(parser.getStrVal(id: elemId), values[i])
        }
    }

    func testIntArrayOutOfBounds() {
        let arrId = parser.newIntArrayVar("arr", size: 3)
        let elemId = parser.getIntVarFromArray(varId: arrId, index: 99)
        // Out of bounds should return 0 gracefully
        XCTAssertEqual(parser.getIntVal(id: elemId), 0)
    }

    func testStrArrayOutOfBounds() {
        let arrId = parser.newStrArrayVar("sarr", size: 3)
        let elemId = parser.getStrVarFromArray(varId: arrId, index: 99)
        XCTAssertEqual(parser.getStrVal(id: elemId), "")
    }

    // MARK: - Multi-loop Variable Calculation Integrity

    func testMultiLoopVariableIntegrity() {
        // Simulate: for i=0..9 { for j=0..9 { arr[i*10+j] = i*10+j } }
        let arrId = parser.newIntArrayVar("arr", size: 100)
        let iId = parser.newIntVar("i", value: 0)
        let jId = parser.newIntVar("j", value: 0)

        for i in 0..<10 {
            parser.setIntVal(id: iId, value: i)
            for j in 0..<10 {
                parser.setIntVal(id: jId, value: j)
                let idx = i * 10 + j
                let elemId = parser.getIntVarFromArray(varId: arrId, index: idx)
                parser.setIntVal(id: elemId, value: idx)
            }
        }

        // Verify all values
        for k in 0..<100 {
            let elemId = parser.getIntVarFromArray(varId: arrId, index: k)
            XCTAssertEqual(parser.getIntVal(id: elemId), k)
        }
    }

    func testTripleNestedLoopAccumulation() {
        // Simulate: sum = 0; for i=1..3 { for j=1..3 { for k=1..3 { sum = sum + i*j*k } } }
        let sumId = parser.newIntVar("sum", value: 0)
        var expectedSum = 0

        for i in 1...3 {
            for j in 1...3 {
                for k in 1...3 {
                    let currentSum = parser.getIntVal(id: sumId)
                    parser.setIntVal(id: sumId, value: currentSum + i * j * k)
                    expectedSum += i * j * k
                }
            }
        }

        XCTAssertEqual(parser.getIntVal(id: sumId), expectedSum)
        // Expected: (1+2+3)^3 / some formula = 216
        XCTAssertEqual(expectedSum, 216) // sum of i*j*k for i,j,k in 1..3
    }

    func testLoopCounterIncrement() {
        // Simulate: i = 0; while i < 100 { i = i + 1 }
        let iId = parser.newIntVar("i", value: 0)
        while parser.getIntVal(id: iId) < 100 {
            let current = parser.getIntVal(id: iId)
            parser.setIntVal(id: iId, value: current + 1)
        }
        XCTAssertEqual(parser.getIntVal(id: iId), 100)
    }

    // MARK: - Variable Scope and Call Stack

    func testCallStackPushPop() {
        let frame = TTLCallFrame(lineIndex: 10, level: 0, fileIndex: 0)
        parser.callStack.append(frame)
        parser.scopeLevel += 1

        XCTAssertEqual(parser.callStack.count, 1)
        XCTAssertEqual(parser.scopeLevel, 1)

        let popped = parser.callStack.removeLast()
        parser.scopeLevel = popped.level
        XCTAssertEqual(parser.callStack.count, 0)
        XCTAssertEqual(parser.scopeLevel, 0)
    }

    func testDeepCallStack() {
        // Simulate 10-deep call nesting
        for i in 0..<10 {
            let frame = TTLCallFrame(lineIndex: i * 10, level: parser.scopeLevel, fileIndex: 0)
            parser.callStack.append(frame)
            parser.scopeLevel += 1
        }
        XCTAssertEqual(parser.callStack.count, 10)
        XCTAssertEqual(parser.scopeLevel, 10)

        // Unwind
        for _ in 0..<10 {
            let frame = parser.callStack.removeLast()
            parser.scopeLevel = frame.level
        }
        XCTAssertEqual(parser.callStack.count, 0)
        XCTAssertEqual(parser.scopeLevel, 0)
    }

    func testLoopStackPushPop() {
        // Push while-loop frame
        let whileFrame = TTLLoopFrame(type: .while_, lineIndex: 5, varId: 0, limit: 0, step: 0)
        parser.loopStack.append(whileFrame)

        // Push for-loop frame inside while
        let forFrame = TTLLoopFrame(type: .for_, lineIndex: 8, varId: 1, limit: 10, step: 1)
        parser.loopStack.append(forFrame)

        XCTAssertEqual(parser.loopStack.count, 2)

        let popped = parser.loopStack.removeLast()
        XCTAssertEqual(popped.type, .for_)
        XCTAssertEqual(popped.limit, 10)
        XCTAssertEqual(parser.loopStack.count, 1)

        let popped2 = parser.loopStack.removeLast()
        XCTAssertEqual(popped2.type, .while_)
    }

    // MARK: - Expression Calculations in Loop Context

    func testArraySumCalculation() {
        let arrId = parser.newIntArrayVar("data", size: 10)
        let sumId = parser.newIntVar("total", value: 0)

        // Fill array with 1..10
        for i in 0..<10 {
            let elemId = parser.getIntVarFromArray(varId: arrId, index: i)
            parser.setIntVal(id: elemId, value: i + 1)
        }

        // Sum
        for i in 0..<10 {
            let elemId = parser.getIntVarFromArray(varId: arrId, index: i)
            let val = parser.getIntVal(id: elemId)
            let currentSum = parser.getIntVal(id: sumId)
            parser.setIntVal(id: sumId, value: currentSum + val)
        }

        XCTAssertEqual(parser.getIntVal(id: sumId), 55) // 1+2+...+10
    }

    func testArrayStringConcatenation() {
        let arrId = parser.newStrArrayVar("words", size: 3)
        let resultId = parser.newStrVar("sentence", value: "")

        let words = ["Hello", " ", "World"]
        for i in 0..<3 {
            let elemId = parser.getStrVarFromArray(varId: arrId, index: i)
            parser.setStrVal(id: elemId, value: words[i])
        }

        // Concatenate all
        for i in 0..<3 {
            let elemId = parser.getStrVarFromArray(varId: arrId, index: i)
            let word = parser.getStrVal(id: elemId)
            let current = parser.getStrVal(id: resultId)
            parser.setStrVal(id: resultId, value: current + word)
        }

        XCTAssertEqual(parser.getStrVal(id: resultId), "Hello World")
    }

    // MARK: - Bitwise Operations

    func testBitwiseAnd() {
        XCTAssertEqual(0xFF & 0x0F, 0x0F)
    }

    func testBitwiseOr() {
        XCTAssertEqual(0xF0 | 0x0F, 0xFF)
    }

    func testBitwiseXor() {
        XCTAssertEqual(0xFF ^ 0x0F, 0xF0)
    }

    func testBitwiseNot() {
        let val: Int = 0
        XCTAssertEqual(~val, -1)
    }

    func testLeftShift() {
        XCTAssertEqual(1 << 8, 256)
    }

    func testRightShift() {
        XCTAssertEqual(256 >> 4, 16)
    }

    // MARK: - System Variable Integrity

    func testResultVariable() {
        parser.setResult(42)
        XCTAssertEqual(parser.getIntVal(id: parser.resultVarId), 42)
        parser.setResult(0)
        XCTAssertEqual(parser.getIntVal(id: parser.resultVarId), 0)
        parser.setResult(-1)
        XCTAssertEqual(parser.getIntVal(id: parser.resultVarId), -1)
    }

    func testTimeoutVariable() {
        parser.setIntVal(id: parser.timeoutVarId, value: 10)
        XCTAssertEqual(parser.getIntVal(id: parser.timeoutVarId), 10)
    }

    func testMtimeoutVariable() {
        parser.setIntVal(id: parser.mtimeoutVarId, value: 500)
        XCTAssertEqual(parser.getIntVal(id: parser.mtimeoutVarId), 500)
    }

    func testParamVariables() {
        for (i, id) in parser.paramVarIds.enumerated() {
            parser.setStrVal(id: id, value: "param\(i + 1)")
            XCTAssertEqual(parser.getStrVal(id: id), "param\(i + 1)")
        }
    }
}
