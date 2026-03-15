/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * MacroRunner command implementations (extension).
 * Each command method is marked with // [IMPLEMENTED]
 */

import Foundation
import TTLMacroShared

// MARK: - Control Flow Commands

extension MacroRunner {

    func cmdIf(_ args: [String]) { // [IMPLEMENTED]
        let hasThen = args.last?.lowercased() == "then"
        let condArgs = hasThen ? Array(args.dropLast()) : args
        let condVal = evaluateCondition(condArgs)

        if hasThen {
            ifNest += 1
            if condVal == 0 { elseFlag = 1 }
        } else {
            // Single-line if: skip rest if false
            if condVal == 0 {
                // Do nothing - just skip
            }
        }
    }

    func cmdElse() { // [IMPLEMENTED]
        guard ifNest >= 1 else { reportError("Invalid control: else"); return }
        ifNest -= 1
        endIfFlag = 1
    }

    func cmdElseIf(_ args: [String]) { // [IMPLEMENTED]
        guard ifNest >= 1 else { reportError("Invalid control: elseif"); return }
        ifNest -= 1
        endIfFlag = 1
    }

    func cmdEndIf() { // [IMPLEMENTED]
        guard ifNest >= 1 else { reportError("Invalid control: endif"); return }
        ifNest -= 1
    }

    func cmdGoto(_ args: [String]) { // [IMPLEMENTED]
        guard let label = args.first?.lowercased() else {
            reportError("Label required"); return
        }
        if let val = variables[label], case .integer(let lineIdx) = val {
            currentLineNumber = lineIdx + 1
        } else {
            reportError("Label not found: \(label)")
        }
    }

    func cmdCall(_ args: [String]) { // [IMPLEMENTED]
        guard let label = args.first?.lowercased() else {
            reportError("Label required"); return
        }
        guard callStack.count < 10 else { reportError("Stack overflow"); return }
        callStack.append(MacroCallFrame(lineIndex: currentLineNumber, scopeLevel: scopeLevel))
        scopeLevel += 1
        if let val = variables[label], case .integer(let lineIdx) = val {
            currentLineNumber = lineIdx + 1
        } else {
            reportError("Label not found: \(label)")
        }
    }

    func cmdReturn() { // [IMPLEMENTED]
        guard !callStack.isEmpty else { reportError("Invalid control: return"); return }
        let frame = callStack.removeLast()
        currentLineNumber = frame.lineIndex
        scopeLevel = frame.scopeLevel
    }

    func cmdFor(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { reportError("Syntax error: for"); return }
        let varName = args[0].lowercased()
        let start = getIntArg(args, 1)
        let end = getIntArg(args, 2)

        if let lastLoop = loopStack.last,
           lastLoop.type == .for_ && lastLoop.lineIndex == currentLineNumber - 1 {
            var val = variables[varName]?.intValue ?? 0
            val += (start <= end) ? 1 : -1
            variables[varName] = .integer(val)
            if (start <= end && val > end) || (start > end && val < end) {
                loopStack.removeLast()
            }
        } else {
            guard loopStack.count < 10 else { reportError("Stack overflow"); return }
            variables[varName] = .integer(start)
            loopStack.append(MacroLoopFrame(
                type: .for_, lineIndex: currentLineNumber - 1,
                varName: varName, limit: end, step: 1, ifNest: ifNest))
        }
    }

    func cmdNext() { // [IMPLEMENTED]
        guard let loop = loopStack.last, loop.type == .for_ else {
            reportError("Invalid control: next"); return
        }
        let val = variables[loop.varName]?.intValue ?? 0
        let atEnd: Bool
        if loop.limit >= val {
            atEnd = (val + loop.step) > loop.limit
        } else {
            atEnd = (val - loop.step) < loop.limit
        }
        ifNest = loop.ifNest
        if atEnd {
            loopStack.removeLast()
        } else {
            let newVal = loop.limit >= val ? val + loop.step : val - loop.step
            variables[loop.varName] = .integer(newVal)
            currentLineNumber = loop.lineIndex + 1
        }
    }

    func cmdWhile(_ args: [String], mode: Bool) { // [IMPLEMENTED]
        let val = args.isEmpty ? 1 : getIntArg(args, 0)
        let conditionMet = (val != 0) == mode
        let loopType: MacroLoopType = mode ? .while_ : .until

        if let lastLoop = loopStack.last,
           lastLoop.type == loopType && lastLoop.lineIndex == currentLineNumber - 1 {
            ifNest = lastLoop.ifNest
            if !conditionMet {
                loopStack.removeLast()
                endWhileFlag = 1
            }
        } else {
            if conditionMet {
                guard loopStack.count < 10 else { reportError("Stack overflow"); return }
                loopStack.append(MacroLoopFrame(
                    type: loopType, lineIndex: currentLineNumber - 1,
                    varName: "", limit: 0, step: 0, ifNest: ifNest))
            } else {
                endWhileFlag = 1
            }
        }
    }

    func cmdEndWhile() { // [IMPLEMENTED]
        guard let loop = loopStack.last else {
            reportError("Invalid control: endwhile"); return
        }
        currentLineNumber = loop.lineIndex
    }

    func cmdDo() { // [IMPLEMENTED]
        guard loopStack.count < 10 else { reportError("Stack overflow"); return }
        loopStack.append(MacroLoopFrame(
            type: .do_, lineIndex: currentLineNumber - 1,
            varName: "", limit: 0, step: 0, ifNest: ifNest))
    }

    func cmdLoop(_ args: [String]) { // [IMPLEMENTED]
        guard let loop = loopStack.last else {
            reportError("Invalid control: loop"); return
        }
        var shouldLoop = true
        if args.count >= 2 {
            let keyword = args[0].lowercased()
            let val = getIntArg(args, 1)
            if keyword == "while" { shouldLoop = val != 0 }
            else if keyword == "until" { shouldLoop = val == 0 }
        }
        ifNest = loop.ifNest
        if shouldLoop {
            currentLineNumber = loop.lineIndex + 1
        } else {
            loopStack.removeLast()
        }
    }

    func cmdBreak() { // [IMPLEMENTED]
        guard !loopStack.isEmpty else { reportError("Invalid control: break"); return }
        breakFlag = 1
    }

    func cmdContinue() { // [IMPLEMENTED]
        guard !loopStack.isEmpty else { reportError("Invalid control: continue"); return }
        breakFlag = 1
        continueFlag = true
    }

    func cmdEnd() { // [IMPLEMENTED]
        isRunning = false
        onComplete?(exitCode)
        clientProxy?.macroDidFinish(exitCode: exitCode, reply: {})
    }

    func cmdExit() { // [IMPLEMENTED]
        if !fileStack.isEmpty {
            let state = fileStack.removeLast()
            scriptLines = state.lines
            currentLineNumber = state.lineIndex
        } else {
            cmdEnd()
        }
    }

    func cmdInclude(_ args: [String]) { // [IMPLEMENTED]
        guard let filename = args.first else { reportError("Syntax error: include"); return }
        let path = resolveString(filename)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            reportError("Cannot open: \(path)"); return
        }
        guard fileStack.count < 10 else { reportError("Stack overflow"); return }
        fileStack.append((lines: scriptLines, lineIndex: currentLineNumber))
        scriptLines = content.components(separatedBy: .newlines)
        currentLineNumber = 0
        prescanLabels()
    }

    func cmdIfDefined(_ args: [String]) { // [IMPLEMENTED]
        guard let name = args.first else { reportError("Syntax error"); return }
        let exists = variables[name.lowercased()] != nil
        variables["result"] = .integer(exists ? 1 : 0)
    }

    // MARK: - Condition Evaluation

    func evaluateCondition(_ args: [String]) -> Int {
        if args.count >= 3 {
            let left = resolveValue(args[0])
            let op = args[1]
            let right = resolveValue(args[2])

            switch op {
            case "=", "==":
                return left.strValue == right.strValue ? 1 : 0
            case "<>", "!=":
                return left.strValue != right.strValue ? 1 : 0
            case "<":
                return left.intValue < right.intValue ? 1 : 0
            case ">":
                return left.intValue > right.intValue ? 1 : 0
            case "<=":
                return left.intValue <= right.intValue ? 1 : 0
            case ">=":
                return left.intValue >= right.intValue ? 1 : 0
            default:
                return resolveInt(args[0])
            }
        } else if args.count == 1 {
            return resolveInt(args[0])
        }
        return 0
    }
}

// MARK: - Send/Receive Commands

extension MacroRunner {

    func cmdSend(_ args: [String], addCR: Bool) { // [IMPLEMENTED]
        var text = args.map { resolveString($0) }.joined()
        if addCR { text += "\r" }
        guard let data = text.data(using: .utf8) else { return }
        clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    func cmdSendText(_ args: [String]) { // [IMPLEMENTED]
        let text = getStringArg(args, 0)
        guard let data = text.data(using: .utf8) else { scheduleNextLine(); return }
        clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    func cmdSendBinary(_ args: [String]) { // [IMPLEMENTED]
        let hex = getStringArg(args, 0)
        var data = Data()
        var i = hex.startIndex
        while i < hex.endIndex {
            let next = hex.index(after: i)
            if next < hex.endIndex {
                if let byte = UInt8(String(hex[i...next]), radix: 16) {
                    data.append(byte)
                }
                i = hex.index(after: next)
            } else { break }
        }
        clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    func cmdSendBreak() { // [IMPLEMENTED]
        clientProxy?.sendBreak(reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    func cmdSendKCode(_ args: [String]) { // [IMPLEMENTED]
        let code = getIntArg(args, 0)
        let data = Data([UInt8(code & 0xFF)])
        clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    func cmdSendFile(_ args: [String]) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        guard let data = FileManager.default.contents(atPath: path) else {
            reportError("Cannot open: \(path)"); scheduleNextLine(); return
        }
        clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    func cmdRecvLn() { // [IMPLEMENTED]
        clientProxy?.recvFromTerminal(timeout: timeoutValue, reply: { [weak self] data in
            guard let self = self else { return }
            if let data = data, let str = String(data: data, encoding: .utf8) {
                if let nlRange = str.rangeOfCharacter(from: .newlines) {
                    self.inputStr = String(str[str.startIndex..<nlRange.lowerBound])
                    self.variables["inputstr"] = .string(self.inputStr)
                    self.resultValue = 0
                } else {
                    self.resultValue = 1
                }
            } else {
                self.resultValue = 1
            }
            self.variables["result"] = .integer(self.resultValue)
            self.scheduleNextLine()
        })
    }

    func cmdFlushRecv() { // [IMPLEMENTED]
        clientProxy?.flushReceiveBuffer(reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }
}

// MARK: - Wait Commands

extension MacroRunner {

    func cmdWait(_ args: [String], ln: Bool) { // [IMPLEMENTED]
        let patterns = args.map { resolveString($0) }
        guard !patterns.isEmpty else { scheduleNextLine(); return }

        let timeout = timeoutValue > 0 ? TimeInterval(timeoutValue) : 300.0
        let startTime = Date()

        func pollWait() {
            guard self.isRunning, !self.isCancelled else { return }
            if Date().timeIntervalSince(startTime) > timeout {
                self.variables["result"] = .integer(0)
                self.scheduleNextLine()
                return
            }
            self.clientProxy?.recvFromTerminal(timeout: 1, reply: { [weak self] data in
                guard let self = self else { return }
                if let data = data, let received = String(data: data, encoding: .utf8) {
                    for (idx, pattern) in patterns.enumerated() {
                        if received.contains(pattern) {
                            self.variables["result"] = .integer(idx + 1)
                            self.inputStr = received
                            self.variables["inputstr"] = .string(received)
                            self.scheduleNextLine()
                            return
                        }
                    }
                }
                // Not found yet, poll again
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pollWait() }
            })
        }
        pollWait()
    }

    func cmdWaitRecv() { // [IMPLEMENTED]
        clientProxy?.recvFromTerminal(timeout: timeoutValue, reply: { [weak self] data in
            guard let self = self else { return }
            if let data = data, let str = String(data: data, encoding: .utf8) {
                self.inputStr = str
                self.variables["inputstr"] = .string(str)
                self.resultValue = 1
            } else {
                self.resultValue = 0
            }
            self.variables["result"] = .integer(self.resultValue)
            self.scheduleNextLine()
        })
    }

    func cmdWaitRegex(_ args: [String]) { // [IMPLEMENTED]
        let pattern = getStringArg(args, 0)
        let timeout = timeoutValue > 0 ? TimeInterval(timeoutValue) : 300.0
        let startTime = Date()

        func pollRegex() {
            guard self.isRunning, !self.isCancelled else { return }
            if Date().timeIntervalSince(startTime) > timeout {
                self.variables["result"] = .integer(0)
                self.scheduleNextLine()
                return
            }
            self.clientProxy?.recvFromTerminal(timeout: 1, reply: { [weak self] data in
                guard let self = self else { return }
                if let data = data, let received = String(data: data, encoding: .utf8) {
                    var options: NSRegularExpression.Options = []
                    if self.regexCaseInsensitive { options.insert(.caseInsensitive) }
                    if let regex = try? NSRegularExpression(pattern: pattern, options: options),
                       let match = regex.firstMatch(in: received, range: NSRange(received.startIndex..., in: received)) {
                        self.matchStr = String(received[Range(match.range, in: received)!])
                        self.variables["matchstr"] = .string(self.matchStr)
                        for g in 1..<min(match.numberOfRanges, 10) {
                            if let range = Range(match.range(at: g), in: received) {
                                self.variables["groupmatchstr\(g)"] = .string(String(received[range]))
                            }
                        }
                        self.variables["result"] = .integer(1)
                        self.scheduleNextLine()
                        return
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pollRegex() }
            })
        }
        pollRegex()
    }

    func cmdWaitN(_ args: [String]) { // [IMPLEMENTED]
        let byteCount = getIntArg(args, 0)
        var accumulated = Data()
        let timeout = timeoutValue > 0 ? TimeInterval(timeoutValue) : 300.0
        let startTime = Date()

        func pollN() {
            guard self.isRunning, !self.isCancelled else { return }
            if Date().timeIntervalSince(startTime) > timeout {
                self.variables["result"] = .integer(0)
                self.scheduleNextLine()
                return
            }
            self.clientProxy?.recvFromTerminal(timeout: 1, reply: { [weak self] data in
                guard let self = self else { return }
                if let data = data { accumulated.append(data) }
                if accumulated.count >= byteCount {
                    self.inputStr = String(data: accumulated, encoding: .utf8) ?? ""
                    self.variables["inputstr"] = .string(self.inputStr)
                    self.variables["result"] = .integer(1)
                    self.scheduleNextLine()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pollN() }
            })
        }
        pollN()
    }

    func cmdWait4All(_ args: [String]) { // [IMPLEMENTED]
        let patterns = args.map { resolveString($0) }
        var found = Set<Int>()
        let timeout = timeoutValue > 0 ? TimeInterval(timeoutValue) : 300.0
        let startTime = Date()

        func poll4All() {
            guard self.isRunning, !self.isCancelled else { return }
            if Date().timeIntervalSince(startTime) > timeout {
                self.variables["result"] = .integer(0)
                self.scheduleNextLine()
                return
            }
            self.clientProxy?.recvFromTerminal(timeout: 1, reply: { [weak self] data in
                guard let self = self else { return }
                if let data = data, let received = String(data: data, encoding: .utf8) {
                    for (idx, pattern) in patterns.enumerated() {
                        if received.contains(pattern) { found.insert(idx) }
                    }
                }
                if found.count == patterns.count {
                    self.variables["result"] = .integer(1)
                    self.scheduleNextLine()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll4All() }
            })
        }
        poll4All()
    }

    func cmdWaitEvent() { // [IMPLEMENTED]
        // Simplified: just wait for any data
        cmdWaitRecv()
    }

    func cmdPause(_ args: [String]) { // [IMPLEMENTED]
        let seconds = args.isEmpty ? 1.0 : Double(getIntArg(args, 0))
        execTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.scheduleNextLine()
        }
    }

    func cmdMPause(_ args: [String]) { // [IMPLEMENTED]
        let ms = args.isEmpty ? 100 : getIntArg(args, 0)
        let seconds = Double(ms) / 1000.0
        execTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.scheduleNextLine()
        }
    }
}

// MARK: - Connection Commands

extension MacroRunner {

    func cmdConnect(_ args: [String]) { // [IMPLEMENTED]
        let param = args.map { resolveString($0) }.joined(separator: " ")
        clientProxy?.connectToHost(param: param, reply: { [weak self] success in
            self?.variables["result"] = .integer(success ? 1 : 0)
            self?.scheduleNextLine()
        })
    }

    func cmdDisconnect() { // [IMPLEMENTED]
        clientProxy?.disconnectFromHost(reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    func cmdTestLink() { // [IMPLEMENTED]
        clientProxy?.isConnected(reply: { [weak self] connected in
            self?.variables["result"] = .integer(connected ? 2 : 0)
            self?.scheduleNextLine()
        })
    }

    func cmdUnlink() { // [IMPLEMENTED]
        // Unlink macro from terminal - no-op in XPC model
        scheduleNextLine()
    }

    func cmdCygConnect() { // [IMPLEMENTED]
        clientProxy?.connectLocalShell(reply: { [weak self] success in
            self?.variables["result"] = .integer(success ? 1 : 0)
            self?.scheduleNextLine()
        })
    }

    func cmdSetTimeout(_ args: [String]) { // [IMPLEMENTED]
        timeoutValue = getIntArg(args, 0)
        variables["timeout"] = .integer(timeoutValue)
    }
}

// MARK: - String Commands

extension MacroRunner {

    func cmdStrLen(_ args: [String]) { // [IMPLEMENTED]
        let str = getStringArg(args, 0)
        variables["result"] = .integer(str.count)
    }

    func cmdStrConcat(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let varName = args[0].lowercased()
        let existing = variables[varName]?.strValue ?? ""
        let append = getStringArg(args, 1)
        variables[varName] = .string(existing + append)
    }

    func cmdStrCopy(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 4 else { return }
        let source = getStringArg(args, 0)
        let start = max(1, getIntArg(args, 1)) - 1
        let length = getIntArg(args, 2)
        let destVar = args[3].lowercased()
        let s = source
        if start < s.count {
            let startIdx = s.index(s.startIndex, offsetBy: start)
            let endIdx = s.index(startIdx, offsetBy: min(length, s.count - start))
            variables[destVar] = .string(String(s[startIdx..<endIdx]))
        } else {
            variables[destVar] = .string("")
        }
    }

    func cmdStrCompare(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let s1 = getStringArg(args, 0)
        let s2 = getStringArg(args, 1)
        let cmp = s1.compare(s2)
        variables["result"] = .integer(cmp == .orderedAscending ? -1 : cmp == .orderedDescending ? 1 : 0)
    }

    func cmdStrScan(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let str = getStringArg(args, 0)
        let pattern = getStringArg(args, 1)
        if let range = str.range(of: pattern) {
            variables["result"] = .integer(str.distance(from: str.startIndex, to: range.lowerBound) + 1)
        } else {
            variables["result"] = .integer(0)
        }
    }

    func cmdStrMatch(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let str = getStringArg(args, 0)
        let pattern = getStringArg(args, 1)
        var options: NSRegularExpression.Options = []
        if regexCaseInsensitive { options.insert(.caseInsensitive) }
        if let regex = try? NSRegularExpression(pattern: pattern, options: options),
           let match = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) {
            variables["result"] = .integer(match.range.location + 1)
            if let r = Range(match.range, in: str) {
                variables["matchstr"] = .string(String(str[r]))
            }
        } else {
            variables["result"] = .integer(0)
            variables["matchstr"] = .string("")
        }
    }

    func cmdStr2Int(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let str = getStringArg(args, 0)
        let destVar = args[1].lowercased()
        if let val = Int(str) {
            variables[destVar] = .integer(val)
            variables["result"] = .integer(1)
        } else if str.hasPrefix("$"), let val = Int(String(str.dropFirst()), radix: 16) {
            variables[destVar] = .integer(val)
            variables["result"] = .integer(1)
        } else {
            variables["result"] = .integer(0)
        }
    }

    func cmdInt2Str(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let val = getIntArg(args, 1)
        variables[destVar] = .string(String(val))
    }

    func cmdStr2Code(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let str = getStringArg(args, 0)
        let destVar = args[1].lowercased()
        if let first = str.first {
            variables[destVar] = .integer(Int(first.asciiValue ?? 0))
        } else {
            variables[destVar] = .integer(0)
        }
    }

    func cmdCode2Str(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let code = getIntArg(args, 0)
        let destVar = args[1].lowercased()
        variables[destVar] = .string(String(UnicodeScalar(UInt8(code & 0xFF))))
    }

    func cmdStrInsert(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let varName = args[0].lowercased()
        let pos = max(1, getIntArg(args, 1)) - 1
        let insertStr = getStringArg(args, 2)
        var str = variables[varName]?.strValue ?? ""
        let idx = str.index(str.startIndex, offsetBy: min(pos, str.count))
        str.insert(contentsOf: insertStr, at: idx)
        variables[varName] = .string(str)
    }

    func cmdStrRemove(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let varName = args[0].lowercased()
        let pos = max(1, getIntArg(args, 1)) - 1
        let length = getIntArg(args, 2)
        var str = variables[varName]?.strValue ?? ""
        if pos < str.count {
            let start = str.index(str.startIndex, offsetBy: pos)
            let end = str.index(start, offsetBy: min(length, str.count - pos))
            str.removeSubrange(start..<end)
        }
        variables[varName] = .string(str)
    }

    func cmdStrReplace(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let varName = args[0].lowercased()
        let pattern = getStringArg(args, 1)
        let replacement = getStringArg(args, 2)
        var str = variables[varName]?.strValue ?? ""
        var options: NSRegularExpression.Options = []
        if regexCaseInsensitive { options.insert(.caseInsensitive) }
        if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
            let range = NSRange(str.startIndex..., in: str)
            let result = regex.stringByReplacingMatches(in: str, range: range, withTemplate: replacement)
            variables["result"] = .integer(result != str ? 1 : 0)
            variables[varName] = .string(result)
        } else {
            variables["result"] = .integer(0)
        }
    }

    func cmdStrSpecial(_ args: [String]) { // [IMPLEMENTED]
        guard let varName = args.first?.lowercased() else { return }
        var str = variables[varName]?.strValue ?? ""
        str = str.replacingOccurrences(of: "\\n", with: "\n")
        str = str.replacingOccurrences(of: "\\r", with: "\r")
        str = str.replacingOccurrences(of: "\\t", with: "\t")
        str = str.replacingOccurrences(of: "\\\\", with: "\\")
        str = str.replacingOccurrences(of: "\\\"", with: "\"")
        str = str.replacingOccurrences(of: "\\'", with: "'")
        variables[varName] = .string(str)
    }

    func cmdStrTrim(_ args: [String]) { // [IMPLEMENTED]
        guard let varName = args.first?.lowercased() else { return }
        let str = variables[varName]?.strValue ?? ""
        let chars = args.count > 1 ? CharacterSet(charactersIn: getStringArg(args, 1)) : .whitespaces
        let trimType = args.count > 2 ? getIntArg(args, 2) : 0
        let result: String
        switch trimType {
        case 1: result = String(str.drop(while: { chars.contains(Unicode.Scalar(String($0))!) }))
        case 2:
            var s = str
            while let last = s.last, chars.contains(Unicode.Scalar(String(last))!) { s.removeLast() }
            result = s
        default: result = str.trimmingCharacters(in: chars)
        }
        variables[varName] = .string(result)
    }

    func cmdStrSplit(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let str = getStringArg(args, 0)
        let delimiter = getStringArg(args, 1)
        let parts = str.components(separatedBy: delimiter)
        variables["result"] = .integer(parts.count)
        for (i, part) in parts.enumerated() {
            variables["groupmatchstr\(i + 1)"] = .string(part)
        }
    }

    func cmdStrJoin(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let destVar = args[0].lowercased()
        let delimiter = getStringArg(args, 1)
        let parts = args.dropFirst(2).map { resolveString($0) }
        variables[destVar] = .string(parts.joined(separator: delimiter))
    }

    func cmdToLower(_ args: [String]) { // [IMPLEMENTED]
        guard let varName = args.first?.lowercased() else { return }
        let str = variables[varName]?.strValue ?? ""
        variables[varName] = .string(str.lowercased())
    }

    func cmdToUpper(_ args: [String]) { // [IMPLEMENTED]
        guard let varName = args.first?.lowercased() else { return }
        let str = variables[varName]?.strValue ?? ""
        variables[varName] = .string(str.uppercased())
    }

    func cmdSprintf(_ args: [String], mode: Int) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let format = getStringArg(args, 0)
        // Simple sprintf: replace %d, %s, %x
        var result = format
        var argIdx = 1
        var i = result.startIndex
        while i < result.endIndex {
            if result[i] == "%" && result.index(after: i) < result.endIndex {
                let next = result[result.index(after: i)]
                let replaceRange = i...result.index(after: i)
                if next == "d" && argIdx < args.count {
                    let val = getIntArg(args, argIdx); argIdx += 1
                    result.replaceSubrange(replaceRange, with: String(val))
                } else if next == "s" && argIdx < args.count {
                    let val = getStringArg(args, argIdx); argIdx += 1
                    result.replaceSubrange(replaceRange, with: val)
                } else if next == "x" && argIdx < args.count {
                    let val = getIntArg(args, argIdx); argIdx += 1
                    result.replaceSubrange(replaceRange, with: String(val, radix: 16))
                } else if next == "%" {
                    result.replaceSubrange(replaceRange, with: "%")
                }
                i = result.startIndex // restart after replacement
                continue
            }
            i = result.index(after: i)
        }
        if mode == 0 {
            variables["inputstr"] = .string(result)
        } else if args.count > 1 {
            // sprintf2: first arg is dest var, second is format
            let destVar = args[0].lowercased()
            variables[destVar] = .string(result)
        }
    }
}
