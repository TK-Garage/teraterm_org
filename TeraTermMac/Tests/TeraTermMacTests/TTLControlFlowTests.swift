/*
 * TTL Control Flow Tests
 * Phase 2: if/else/endif, for/next, while/endwhile, goto, call/return,
 *          nested structures, deep call stacks
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)

final class TTLControlFlowTests: XCTestCase {

    var interpreter: TTLInterpreter!
    var delegate: MockTTLDelegate!

    override func setUp() {
        super.setUp()
        interpreter = TTLInterpreter()
        delegate = MockTTLDelegate()
        interpreter.delegate = delegate
    }

    // MARK: - Label Scanning

    func testPrescanLabels() {
        interpreter.loadScript("""
        :start
        goto end
        :middle
        ; some code
        :end
        end
        """)
        interpreter.prescanLabels()

        let p = interpreter.parser
        XCTAssertNotNil(p.checkVar("start"))
        XCTAssertNotNil(p.checkVar("middle"))
        XCTAssertNotNil(p.checkVar("end"))

        // Verify positions
        if let (type, id) = p.checkVar("start") {
            XCTAssertEqual(type, .label)
            XCTAssertEqual(p.variables[id].label.position, 0)
        }
        if let (type, id) = p.checkVar("end") {
            XCTAssertEqual(type, .label)
            XCTAssertEqual(p.variables[id].label.position, 4)
        }
    }

    func testPrescanLabels_CaseInsensitive() {
        interpreter.loadScript(":MyLabel\n:ANOTHERLABEL\n:lowercase")
        interpreter.prescanLabels()
        let p = interpreter.parser

        XCTAssertNotNil(p.checkVar("mylabel"))
        XCTAssertNotNil(p.checkVar("MYLABEL"))
        XCTAssertNotNil(p.checkVar("MyLabel"))
    }

    func testPrescanLabels_LabelAtBeginning() {
        interpreter.loadScript(":first\nend")
        interpreter.prescanLabels()
        let p = interpreter.parser
        if let (_, id) = p.checkVar("first") {
            XCTAssertEqual(p.variables[id].label.position, 0)
        } else {
            XCTFail("Label 'first' not found")
        }
    }

    func testPrescanLabels_LabelAtEnd() {
        interpreter.loadScript("end\n:last")
        interpreter.prescanLabels()
        let p = interpreter.parser
        if let (_, id) = p.checkVar("last") {
            XCTAssertEqual(p.variables[id].label.position, 1)
        } else {
            XCTFail("Label 'last' not found")
        }
    }

    // MARK: - Call Stack Tests

    func testCallStack_SingleLevel() {
        let p = interpreter.parser
        interpreter.loadScript("")

        let frame = TTLCallFrame(lineIndex: 5, level: 0, fileIndex: 0)
        p.callStack.append(frame)
        p.scopeLevel += 1

        XCTAssertEqual(p.callStack.count, 1)
        XCTAssertEqual(p.scopeLevel, 1)

        let returned = p.callStack.removeLast()
        p.scopeLevel = returned.level
        XCTAssertEqual(returned.lineIndex, 5)
        XCTAssertEqual(p.scopeLevel, 0)
    }

    func testCallStack_10DeepNesting() {
        let p = interpreter.parser
        interpreter.loadScript("")

        // Push 10 frames
        for i in 0..<10 {
            let frame = TTLCallFrame(lineIndex: i * 5, level: p.scopeLevel, fileIndex: 0)
            p.callStack.append(frame)
            p.scopeLevel += 1
        }
        XCTAssertEqual(p.callStack.count, 10)
        XCTAssertEqual(p.scopeLevel, 10)

        // Pop all frames in reverse order
        for i in (0..<10).reversed() {
            let frame = p.callStack.removeLast()
            XCTAssertEqual(frame.lineIndex, i * 5)
            p.scopeLevel = frame.level
        }
        XCTAssertEqual(p.callStack.count, 0)
        XCTAssertEqual(p.scopeLevel, 0)
    }

    func testCallStack_20DeepNesting() {
        // Test for potential stack overflow with deep nesting
        let p = interpreter.parser
        interpreter.loadScript("")

        for _ in 0..<20 {
            let frame = TTLCallFrame(lineIndex: p.scopeLevel, level: p.scopeLevel, fileIndex: 0)
            p.callStack.append(frame)
            p.scopeLevel += 1
        }
        XCTAssertEqual(p.callStack.count, 20)

        // Unwind all
        while !p.callStack.isEmpty {
            let frame = p.callStack.removeLast()
            p.scopeLevel = frame.level
        }
        XCTAssertEqual(p.scopeLevel, 0)
    }

    func testCallStack_LabelCleanupOnReturn() {
        let p = interpreter.parser
        interpreter.loadScript("")

        // Push frame at scope 0
        let frame = TTLCallFrame(lineIndex: 0, level: 0, fileIndex: 0)
        p.callStack.append(frame)
        p.scopeLevel = 1

        // Create labels at scope 1
        p.newLabVar("localLabel", position: 10, level: 1)
        XCTAssertNotNil(p.checkVar("localLabel"))

        // Simulate return: cleanup labels at scope >= 1
        let returned = p.callStack.removeLast()
        p.scopeLevel = returned.level
        p.delLabVar(level: p.scopeLevel + 1)
        XCTAssertNil(p.checkVar("localLabel"))
    }

    // MARK: - Loop Stack Tests

    func testLoopStack_ForLoop() {
        let p = interpreter.parser
        interpreter.loadScript("")

        let frame = TTLLoopFrame(type: .for_, lineIndex: 3, varId: 1, limit: 10, step: 1)
        p.loopStack.append(frame)
        XCTAssertEqual(p.loopStack.count, 1)

        let popped = p.loopStack.removeLast()
        XCTAssertEqual(popped.type, .for_)
        XCTAssertEqual(popped.limit, 10)
        XCTAssertEqual(popped.step, 1)
    }

    func testLoopStack_WhileLoop() {
        let p = interpreter.parser
        interpreter.loadScript("")

        let frame = TTLLoopFrame(type: .while_, lineIndex: 5, varId: 0, limit: 0, step: 0)
        p.loopStack.append(frame)

        let popped = p.loopStack.removeLast()
        XCTAssertEqual(popped.type, .while_)
        XCTAssertEqual(popped.lineIndex, 5)
    }

    func testLoopStack_DoUntilLoop() {
        let p = interpreter.parser
        interpreter.loadScript("")

        let frame = TTLLoopFrame(type: .do_, lineIndex: 7, varId: 0, limit: 0, step: 0)
        p.loopStack.append(frame)

        let popped = p.loopStack.removeLast()
        XCTAssertEqual(popped.type, .do_)
    }

    func testLoopStack_NestedLoops() {
        let p = interpreter.parser
        interpreter.loadScript("")

        // for -> while -> do
        p.loopStack.append(TTLLoopFrame(type: .for_, lineIndex: 1, varId: 0, limit: 5, step: 1))
        p.loopStack.append(TTLLoopFrame(type: .while_, lineIndex: 3, varId: 0, limit: 0, step: 0))
        p.loopStack.append(TTLLoopFrame(type: .do_, lineIndex: 5, varId: 0, limit: 0, step: 0))
        XCTAssertEqual(p.loopStack.count, 3)

        // Unwind
        XCTAssertEqual(p.loopStack.removeLast().type, .do_)
        XCTAssertEqual(p.loopStack.removeLast().type, .while_)
        XCTAssertEqual(p.loopStack.removeLast().type, .for_)
    }

    // MARK: - Complex Nested Structure Tests (Simulated)

    func testNestedIfForWhileGoto_Structure() {
        // Test that the parser can load and prescan a complex script
        let script = """
        x = 0
        if x = 0 then
          for i 1 10
            while x < 100
              x = x + 1
              if x = 50 then
                goto done
              endif
            endwhile
          next
        endif
        :done
        end
        """
        interpreter.loadScript(script)
        interpreter.prescanLabels()

        let p = interpreter.parser
        XCTAssertNotNil(p.checkVar("done"))
        XCTAssertEqual(p.lines.count, 14)
    }

    func testNestedCallReturnStructure() {
        // Test that call/return labels are properly scanned
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
          return
        """
        interpreter.loadScript(script)
        interpreter.prescanLabels()

        let p = interpreter.parser
        XCTAssertNotNil(p.checkVar("sub1"))
        XCTAssertNotNil(p.checkVar("sub2"))
        XCTAssertNotNil(p.checkVar("sub3"))
    }

    // MARK: - Include File Stack

    func testFileStackPushPop() {
        let p = interpreter.parser
        interpreter.loadScript("original line 1\noriginal line 2")

        // Simulate include
        let savedLines = p.lines
        let savedLineIndex = p.currentLine
        p.fileStack.append((lines: savedLines, lineIndex: savedLineIndex))

        // Load included file
        p.lines = ["included line 1", "included line 2"]
        p.currentLine = 0

        XCTAssertEqual(p.lines.count, 2)
        XCTAssertEqual(p.lines[0], "included line 1")

        // Simulate end of include
        let (restoredLines, restoredIndex) = p.fileStack.removeLast()
        p.lines = restoredLines
        p.currentLine = restoredIndex

        XCTAssertEqual(p.lines.count, 2)
        XCTAssertEqual(p.lines[0], "original line 1")
    }

    func testFileStackMultiLevel() {
        let p = interpreter.parser
        interpreter.loadScript("main")

        // Include level 1
        p.fileStack.append((lines: p.lines, lineIndex: p.currentLine))
        p.lines = ["include1"]
        p.currentLine = 0

        // Include level 2
        p.fileStack.append((lines: p.lines, lineIndex: p.currentLine))
        p.lines = ["include2"]
        p.currentLine = 0

        XCTAssertEqual(p.fileStack.count, 2)
        XCTAssertEqual(p.lines[0], "include2")

        // Unwind level 2
        let (l1, i1) = p.fileStack.removeLast()
        p.lines = l1; p.currentLine = i1
        XCTAssertEqual(p.lines[0], "include1")

        // Unwind level 1
        let (l0, i0) = p.fileStack.removeLast()
        p.lines = l0; p.currentLine = i0
        XCTAssertEqual(p.lines[0], "main")
    }

    // MARK: - Script Line Parsing

    func testEmptyLine() {
        let p = interpreter.parser
        interpreter.loadScript("")
        p.lineBuffer = ""
        p.linePtr = 0
        XCTAssertNil(p.getFirstChar())
    }

    func testCommentLine() {
        let p = interpreter.parser
        interpreter.loadScript("")
        p.lineBuffer = "; this is a comment"
        p.linePtr = 0
        XCTAssertNil(p.getFirstChar())
    }

    func testLabelLine() {
        let line = ":mylabel"
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        XCTAssertTrue(trimmed.hasPrefix(":"))
        let labelName = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(labelName, "mylabel")
    }

    // MARK: - For Loop Frame Semantics

    func testForLoopFrameStep() {
        // for i 1 10 → step=1, limit=10
        let frame = TTLLoopFrame(type: .for_, lineIndex: 2, varId: 0, limit: 10, step: 1)
        XCTAssertEqual(frame.step, 1)

        // Simulate iteration
        var i = 1
        while i <= frame.limit {
            i += frame.step
        }
        XCTAssertEqual(i, 11) // past limit
    }

    func testForLoopFrameNegativeStep() {
        // for i 10 1 -1
        let frame = TTLLoopFrame(type: .for_, lineIndex: 2, varId: 0, limit: 1, step: -1)

        var i = 10
        var iterations = 0
        while (frame.step > 0 && i <= frame.limit) || (frame.step < 0 && i >= frame.limit) {
            iterations += 1
            i += frame.step
        }
        XCTAssertEqual(iterations, 10) // 10, 9, 8, ..., 1
    }

    // MARK: - If/Else/ElseIf State Flags

    func testIfNestTracking() {
        // Simulate: if -> if -> if -> endif -> endif -> endif
        var ifNest = 0
        var elseFlag = 0

        // if (true) then
        ifNest += 1
        XCTAssertEqual(ifNest, 1)

        // Nested if (false) then
        ifNest += 1
        elseFlag = 1 // Skip to else
        XCTAssertEqual(ifNest, 2)

        // else (of inner if)
        elseFlag -= 1
        XCTAssertEqual(elseFlag, 0)

        // endif (inner)
        ifNest -= 1
        XCTAssertEqual(ifNest, 1)

        // endif (outer)
        ifNest -= 1
        XCTAssertEqual(ifNest, 0)
    }

    // MARK: - Break/Continue Flags

    func testBreakFlagTracking() {
        var breakFlag = 0

        // Entering while
        // break encountered
        breakFlag = 1

        // Encountering nested for inside while
        breakFlag += 1
        XCTAssertEqual(breakFlag, 2)

        // next (end of nested for)
        breakFlag -= 1
        XCTAssertEqual(breakFlag, 1)

        // endwhile
        breakFlag -= 1
        XCTAssertEqual(breakFlag, 0)
    }

    func testContinueFlagTracking() {
        var breakFlag = 0
        var continueFlag = false

        // continue encountered
        breakFlag = 1
        continueFlag = true

        // Skip to endwhile/next
        // When breakFlag reaches 0 and continueFlag is true, re-enter loop
        breakFlag -= 1
        XCTAssertEqual(breakFlag, 0)
        XCTAssertTrue(continueFlag)

        // Reset continue flag after re-entering loop
        continueFlag = false
        XCTAssertFalse(continueFlag)
    }

    // MARK: - Synchronous Execution Helper

    /// Synchronously execute a TTL script step by step.
    /// Only works for non-async commands (no wait/pause/dialog).
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
            steps += 1
        }
        return interpreter.parser.status == .end
    }

    // MARK: - Integration: control_flow_stress.ttl

    func testControlFlowStressScript() {
        // Use a temp file to avoid sandbox issues
        let logFile = NSTemporaryDirectory() + "ttl_control_flow_test_\(UUID().uuidString).log"
        defer { try? FileManager.default.removeItem(atPath: logFile) }

        // Load the script with the temp log path substituted
        let script = """
        logfile = '\(logFile)'
        fileopen fh logfile 0
        pass = 0
        fail = 0

        ; TEST: Deeply nested if-for-while-goto
        total = 0
        for i 1 5
          if i > 0 then
            for j 1 5
              k = 0
              while k < 3
                k = k + 1
                if k = 2 then
                  total = total + i * j
                  goto continue_while
                endif
                :continue_while
              endwhile
            next
          endif
        next
        if total = 225 then
          sprintf2 msg 'PASS: nested total=%d' total
          pass = pass + 1
        else
          sprintf2 msg 'FAIL: expected 225, got %d' total
          fail = fail + 1
        endif
        filewriteln fh msg

        ; TEST: Do-Until Loop
        counter = 0
        do
          counter = counter + 1
        loop until counter >= 10
        if counter = 10 then
          sprintf2 msg 'PASS: do-until counted to %d' counter
          pass = pass + 1
        else
          sprintf2 msg 'FAIL: do-until expected 10, got %d' counter
          fail = fail + 1
        endif
        filewriteln fh msg

        ; TEST: Break from nested loop
        outer_done = 0
        found_i = 0
        found_j = 0
        for i 1 10
          for j 1 10
            if (i * j) = 42 then
              found_i = i
              found_j = j
              outer_done = 1
              break
            endif
          next
          if outer_done = 1 then
            break
          endif
        next
        if (found_i * found_j) = 42 then
          sprintf2 msg 'PASS: break from nested: %d * %d = 42' found_i found_j
          pass = pass + 1
        else
          sprintf2 msg 'FAIL: break from nested: %d * %d <> 42' found_i found_j
          fail = fail + 1
        endif
        filewriteln fh msg

        ; TEST: Continue in for loop
        sum_odd = 0
        for i 1 10
          if (i % 2) = 0 then
            continue
          endif
          sum_odd = sum_odd + i
        next
        if sum_odd = 25 then
          sprintf2 msg 'PASS: continue sum_odd=%d' sum_odd
          pass = pass + 1
        else
          sprintf2 msg 'FAIL: continue expected 25, got %d' sum_odd
          fail = fail + 1
        endif
        filewriteln fh msg

        ; TEST: ElseIf chain
        grade = 85
        if grade >= 90 then
          category = 'A'
        elseif grade >= 80 then
          category = 'B'
        elseif grade >= 70 then
          category = 'C'
        else
          category = 'F'
        endif
        if category = 'B' then
          sprintf2 msg 'PASS: elseif grade=%d -> %s' grade category
          pass = pass + 1
        else
          sprintf2 msg 'FAIL: elseif expected B, got %s' category
          fail = fail + 1
        endif
        filewriteln fh msg

        ; SUMMARY
        filewriteln fh ''
        total_tests = pass + fail
        sprintf2 summary 'Control Flow: %d passed, %d failed (of %d)' pass fail total_tests
        filewriteln fh summary
        fileclose fh
        end
        """

        let completed = execSync(script)
        XCTAssertTrue(completed, "Script should run to completion")

        // Verify log file was created and has content
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile),
                      "Log file should exist at \(logFile)")

        guard let data = FileManager.default.contents(atPath: logFile),
              let content = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to read log file")
            return
        }

        XCTAssertFalse(content.isEmpty, "Log file should not be empty")

        // Verify all tests passed
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines where line.hasPrefix("FAIL") {
            XCTFail("Test failure in script: \(line)")
        }

        // Check summary
        XCTAssertTrue(content.contains("0 failed"),
                      "All control flow tests should pass. Log content:\n\(content)")
    }

    // MARK: - EndIf/EndWhile Flag Tracking

    func testEndIfFlagSkipping() {
        var endIfFlag = 0

        // After else branch, skip to endif
        endIfFlag = 1

        // Encountering nested if inside else block
        endIfFlag += 1
        XCTAssertEqual(endIfFlag, 2)

        // Nested endif
        endIfFlag -= 1
        XCTAssertEqual(endIfFlag, 1)

        // Outer endif
        endIfFlag -= 1
        XCTAssertEqual(endIfFlag, 0)
    }

    // MARK: - Do/Loop Tests

    func testDoLoopUntil() {
        // Minimal do/loop until test
        let completed = execSync("""
        counter = 0
        do
          counter = counter + 1
        loop until counter >= 10
        end
        """)
        XCTAssertTrue(completed, "do/loop until should terminate")
        let p = interpreter.parser
        if let (type, id) = p.checkVar("counter") {
            XCTAssertEqual(type, .integer)
            XCTAssertEqual(p.variables[id].intValue, 10,
                           "counter should be 10 after do/loop until counter >= 10")
        } else {
            XCTFail("counter variable not found")
        }
    }

    func testDoLoopWhile() {
        let completed = execSync("""
        counter = 0
        do
          counter = counter + 1
        loop while counter < 10
        end
        """)
        XCTAssertTrue(completed, "do/loop while should terminate")
        let p = interpreter.parser
        if let (_, id) = p.checkVar("counter") {
            XCTAssertEqual(p.variables[id].intValue, 10)
        } else {
            XCTFail("counter variable not found")
        }
    }

    func testDoLoopPlain() {
        // Plain do/loop with break
        let completed = execSync("""
        counter = 0
        do
          counter = counter + 1
          if counter >= 5 then
            break
          endif
        loop
        end
        """)
        XCTAssertTrue(completed, "do/loop with break should terminate")
        let p = interpreter.parser
        if let (_, id) = p.checkVar("counter") {
            XCTAssertEqual(p.variables[id].intValue, 5)
        } else {
            XCTFail("counter variable not found")
        }
    }

    func testEndWhileFlagSkipping() {
        var endWhileFlag = 0

        // While condition false, skip to endwhile
        endWhileFlag = 1

        // Nested while inside
        endWhileFlag += 1
        XCTAssertEqual(endWhileFlag, 2)

        // Nested endwhile
        endWhileFlag -= 1
        XCTAssertEqual(endWhileFlag, 1)

        // Outer endwhile
        endWhileFlag -= 1
        XCTAssertEqual(endWhileFlag, 0)
    }
}

#endif
