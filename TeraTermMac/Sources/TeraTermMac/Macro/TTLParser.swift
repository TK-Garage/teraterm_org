/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of ttmparse.cpp / ttmparse.h to Swift/macOS
 * TTL (Tera Term Language) parser - tokenizer, expression evaluator, variable management
 */

import Foundation

// MARK: - Constants

let MaxNameLen = 128
let MaxStrLen = 512
let MaxLineLen = 4096

// MARK: - TTL Execution Status

enum TTLStatus: Int {
    case run = 1
    case wait = 2
    case waitLn = 3
    case waitNL = 4
    case wait2 = 5
    case initDDE = 6
    case pause = 7
    case waitCmndEnd = 8
    case waitCmndResult = 9
    case sleep = 10
    case end = 11
    case waitN = 12
    case wait4all = 13
}

// MARK: - Error Codes

enum TTLError: Int, Error {
    case closeParen = 1
    case cantCall = 2
    case cantConnect = 3
    case cantOpen = 4
    case divByZero = 5
    case invalidCtl = 6
    case labelAlreadyDef = 7
    case labelReq = 8
    case linkFirst = 9
    case stackOver = 10
    case syntax = 11
    case tooManyLabels = 12
    case tooManyVar = 13
    case typeMismatch = 14
    case varNotInit = 15
    case closeComment = 16
    case outOfRange = 17
    case closeBracket = 18
    case fewMemory = 19
    case notSupported = 20
    case cantExec = 21

    var message: String {
        switch self {
        case .closeParen:      return "\")\" expected."
        case .cantCall:        return "Can't call sub."
        case .cantConnect:     return "Can't link macro."
        case .cantOpen:        return "Can't open file."
        case .divByZero:       return "Divide by zero."
        case .invalidCtl:      return "Invalid control."
        case .labelAlreadyDef: return "Label already defined."
        case .labelReq:        return "Label required."
        case .linkFirst:       return "Link macro first. Use 'connect' macro."
        case .stackOver:       return "Stack overflow."
        case .syntax:          return "Syntax error."
        case .tooManyLabels:   return "Too many labels."
        case .tooManyVar:      return "Too many variables."
        case .typeMismatch:    return "Type mismatch."
        case .varNotInit:      return "Variable not initialized."
        case .closeComment:    return "\"*/\" expected."
        case .outOfRange:      return "Index out of range."
        case .closeBracket:    return "\"]\" expected."
        case .fewMemory:       return "Can't allocate memory."
        case .notSupported:    return "Unknown command."
        case .cantExec:        return "Can't execute command."
        }
    }
}

// MARK: - Variable Types

enum TTLVarType {
    case unknown
    case integer
    case string
    case label
    case intArray
    case strArray
}

// MARK: - TTL Command IDs (port of ttmparse.h reserved word IDs)

enum TTLCommand: Int {
    // Basic commands 1-158
    case beep = 1, bplusRecv, bplusSend, call, changeDir
    case clearScreen, closeSBox, closeTT, code2Str, connect
    case delPassword, disconnect, else_, elseIf, enableKeyb
    case end, endIf, endWhile, exec, execCmnd
    case exit, fileClose, fileConcat, fileCopy, fileCreate
    case fileDelete, fileMarkPtr, fileOpen, fileReadln, fileRename
    case fileSearch, fileSeek, fileSeekBack, fileStrSeek, fileStrSeek2
    case fileWrite, fileWriteLn, findClose, findFirst, findNext
    case flushRecv, for_, getDate, getDir, getEnv
    case getPassword, getTime, getTitle, goto_, if_
    case include, inputBox, int2Str, kmtFinish, kmtGet
    case kmtRecv, kmtSend, loadKeyMap, logClose, logOpen
    case logPause, logStart, logWrite, makePath, messageBox
    case next, passwordBox, pause, quickVANRecv, quickVANSend
    case recvLn, restoreSetup, `return`, send, sendBreak
    case sendFile, sendKCode, sendLn, setDate, setDir
    case setDlgPos, setEcho, setExitCode, setSync, setTime
    case setTitle, show, showTT, statusBox, str2Code
    case str2Int, strCompare, strConcat, strCopy, strLen
    case strScan, testLink, then, unlink, wait
    case waitEvent, waitLn, waitRecv, while_, xmodemRecv
    case xmodemSend, yesNoBox, zmodemRecv, zmodemSend, waitRegex
    case milliPause, random, clipb2Var, var2Clipb, ifDefined
    case fileRead, sprintf, toLower, toUpper, break_
    case rotateR, rotateL, setEnv, filenameBox, callMenu
    case do_, loop, until, endUntil, cygConnect
    case scpRecv, scpSend, getVer, setBaud, strMatch
    case setRts, setDtr, crc32, crc32File, getTTDir
    case getHostname, sprintf2, waitN, sendBroadcast, sendMulticast
    case setMulticastName, sendlnBroadcast, wait4all, dispStr, intDim
    case strDim, logInfo, fileLock, fileUnLock, continue_
    case regexOption, sendlnMulticast, recvFile

    // Extended commands 175-225
    case setDebug = 175, ymodemRecv, ymodemSend, fileStat, fileTruncate
    case strInsert, strRemove, strReplace, strTrim, strSplit
    case strJoin, strSpecial, basename, dirname, getFileAttr
    case setFileAttr, folderCreate, folderDelete, folderSearch, expandEnv
    case getSpecialFolder, setPassword, isPassword, listBox, getIPv4Addr
    case getIPv6Addr, logRotate, crc16, crc16File, checksum8
    case checksum8File, checksum16, checksum16File, checksum32, checksum32File
    case bringupBox, logAutoClose, uptime, getModemStatus, dirnameBox
    case setFlowCtrl
    case sendText = 217, sendBinary
    case setPassword2, getPassword2, delPassword2, isPassword2
    case getTTPos, setSerialDelayChar, setSerialDelayLine
}

// MARK: - Operator IDs

enum TTLOperator: Int {
    case base = 1000
    case bNot, bAnd, bOr, bXor
    case mul, plus, minus, div, mod
    case lt, eq, gt, le, ne, ge
    case lNot, lAnd, lOr, lXor
    case arShift, alShift, lrShift
}

// MARK: - Variable Storage

struct TTLLabel {
    var position: Int   // File/line position
    var level: Int      // Scope level
}

class TTLVariable {
    var name: String
    var type: TTLVarType
    var intValue: Int = 0
    var strValue: String = ""
    var label: TTLLabel = TTLLabel(position: 0, level: 0)
    var intArray: [Int] = []
    var strArray: [String] = []

    init(name: String, type: TTLVarType) {
        self.name = name
        self.type = type
    }
}

// MARK: - Call Stack Entry

struct TTLCallFrame {
    var lineIndex: Int      // Return line index
    var level: Int          // Scope level
    var fileIndex: Int      // File index for include
}

// MARK: - Loop Stack Entry

enum TTLLoopType {
    case while_
    case until
    case do_
    case for_
}

struct TTLLoopFrame {
    var type: TTLLoopType
    var lineIndex: Int      // Top of loop line index
    var varId: Int          // For-loop variable
    var limit: Int          // For-loop limit
    var step: Int           // For-loop step
}

// MARK: - TTL Parser

class TTLParser {
    // Source
    var lines: [String] = []
    var currentLine: Int = 0    // Current line index
    var lineBuffer: String = "" // Current line content
    var linePtr: Int = 0        // Current parse position in line
    var lineParsePtr: Int = 0   // Token parse start position

    // Variables
    var variables: [TTLVariable] = []

    // System variables (auto-created)
    private(set) var resultVarId: Int = -1
    private(set) var inputStrVarId: Int = -1
    private(set) var matchStrVarId: Int = -1
    private(set) var paramCntVarId: Int = -1
    private(set) var paramVarIds: [Int] = []    // param1..param9 + param(N) expansion
    private(set) var timeoutVarId: Int = -1
    private(set) var mtimeoutVarId: Int = -1

    // State
    var commenting: Bool = false
    var status: TTLStatus = .run

    // Call stack
    var callStack: [TTLCallFrame] = []
    var scopeLevel: Int = 0

    // Loop stack
    var loopStack: [TTLLoopFrame] = []

    // Include file stack
    var fileStack: [(lines: [String], lineIndex: Int)] = []

    // Wait state
    var waitStrings: [String] = []
    var waitTimeout: Double = 0
    var waitStartTime: Date?

    // MARK: - Initialization

    func loadScript(_ source: String) {
        // Normalize CRLF (Windows) and CR (old Mac) to LF before splitting
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
                               .replacingOccurrences(of: "\r", with: "\n")
        lines = normalized.components(separatedBy: "\n")
        currentLine = 0
        linePtr = 0
        commenting = false
        variables.removeAll()
        callStack.removeAll()
        loopStack.removeAll()
        fileStack.removeAll()
        scopeLevel = 0
        status = .run

        initSystemVariables()
    }

    func loadScript(from url: URL) throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        loadScript(source)
    }

    private func initSystemVariables() {
        // Create system variables matching original TTL
        resultVarId = newIntVar("result", value: 0)
        inputStrVarId = newStrVar("inputstr", value: "")
        matchStrVarId = newStrVar("matchstr", value: "")
        timeoutVarId = newIntVar("timeout", value: 0)
        mtimeoutVarId = newIntVar("mtimeout", value: 0)
        paramCntVarId = newIntVar("paramcnt", value: 0)

        // param1 - param9
        paramVarIds = []
        for i in 1...9 {
            let id = newStrVar("param\(i)", value: "")
            paramVarIds.append(id)
        }
    }

    // MARK: - Line Management

    func getNewLine() -> Bool {
        guard currentLine < lines.count else { return false }
        lineBuffer = lines[currentLine]
        currentLine += 1
        linePtr = 0
        lineParsePtr = 0
        return true
    }

    // MARK: - Variable Management

    @discardableResult
    func newIntVar(_ name: String, value: Int) -> Int {
        let v = TTLVariable(name: name, type: .integer)
        v.intValue = value
        variables.append(v)
        return variables.count - 1
    }

    @discardableResult
    func newStrVar(_ name: String, value: String) -> Int {
        let v = TTLVariable(name: name, type: .string)
        v.strValue = value
        variables.append(v)
        return variables.count - 1
    }

    @discardableResult
    func newLabVar(_ name: String, position: Int, level: Int) -> Int {
        let v = TTLVariable(name: name, type: .label)
        v.label = TTLLabel(position: position, level: level)
        variables.append(v)
        return variables.count - 1
    }

    @discardableResult
    func newIntArrayVar(_ name: String, size: Int) -> Int {
        let v = TTLVariable(name: name, type: .intArray)
        v.intArray = [Int](repeating: 0, count: size)
        variables.append(v)
        return variables.count - 1
    }

    @discardableResult
    func newStrArrayVar(_ name: String, size: Int) -> Int {
        let v = TTLVariable(name: name, type: .strArray)
        v.strArray = [String](repeating: "", count: size)
        variables.append(v)
        return variables.count - 1
    }

    func checkVar(_ name: String) -> (type: TTLVarType, id: Int)? {
        for (i, v) in variables.enumerated() {
            if v.name.caseInsensitiveCompare(name) == .orderedSame {
                return (v.type, i)
            }
        }
        return nil
    }

    func delLabVar(level: Int) {
        variables.removeAll { v in
            v.type == .label && v.label.level >= level
        }
    }

    func setIntVal(id: Int, value: Int) {
        let arrayId = id >> 16
        if arrayId > 0 {
            let varIdx = arrayId - 1
            let index = id & 0xFFFF
            guard varIdx < variables.count, index < variables[varIdx].intArray.count else { return }
            variables[varIdx].intArray[index] = value
        } else {
            guard id >= 0 && id < variables.count else { return }
            variables[id].intValue = value
        }
    }

    func getIntVal(id: Int) -> Int {
        let arrayId = id >> 16
        if arrayId > 0 {
            let varIdx = arrayId - 1
            let index = id & 0xFFFF
            guard varIdx < variables.count, index < variables[varIdx].intArray.count else { return 0 }
            return variables[varIdx].intArray[index]
        } else {
            guard id >= 0 && id < variables.count else { return 0 }
            return variables[id].intValue
        }
    }

    func setStrVal(id: Int, value: String) {
        let arrayId = id >> 16
        if arrayId > 0 {
            let varIdx = arrayId - 1
            let index = id & 0xFFFF
            guard varIdx < variables.count, index < variables[varIdx].strArray.count else { return }
            variables[varIdx].strArray[index] = value
        } else {
            guard id >= 0 && id < variables.count else { return }
            variables[id].strValue = value
        }
    }

    func getStrVal(id: Int) -> String {
        let arrayId = id >> 16
        if arrayId > 0 {
            let varIdx = arrayId - 1
            let index = id & 0xFFFF
            guard varIdx < variables.count, index < variables[varIdx].strArray.count else { return "" }
            return variables[varIdx].strArray[index]
        } else {
            guard id >= 0 && id < variables.count else { return "" }
            return variables[id].strValue
        }
    }

    func setResult(_ value: Int) {
        guard resultVarId >= 0 else { return }
        setIntVal(id: resultVarId, value: value)
    }

    func setInputStr(_ value: String) {
        guard inputStrVarId >= 0 else { return }
        setStrVal(id: inputStrVarId, value: value)
    }

    func setMatchStr(_ value: String) {
        guard matchStrVarId >= 0 else { return }
        setStrVal(id: matchStrVarId, value: value)
    }

    // MARK: - Tokenizer

    /// Skip whitespace and handle C-style comments. Returns next non-whitespace char or nil.
    func getFirstChar() -> Character? {
        // Skip whitespace
        while linePtr < lineBuffer.count {
            let ch = charAtPtr()
            if ch != " " && ch != "\t" { break }
            linePtr += 1
        }

        // Handle ongoing block comment
        if commenting {
            while linePtr < lineBuffer.count {
                if charAtPtr() == "*" && linePtr + 1 < lineBuffer.count && charAt(linePtr + 1) == "/" {
                    commenting = false
                    linePtr += 2
                    break
                }
                linePtr += 1
            }
            if commenting { return nil }

            // Skip whitespace again
            while linePtr < lineBuffer.count {
                let ch = charAtPtr()
                if ch != " " && ch != "\t" { break }
                linePtr += 1
            }
        }

        // Handle /* */ comments
        while linePtr + 1 < lineBuffer.count && charAtPtr() == "/" && charAt(linePtr + 1) == "*" {
            linePtr += 2
            var closed = false
            while linePtr < lineBuffer.count {
                if charAtPtr() == "*" && linePtr + 1 < lineBuffer.count && charAt(linePtr + 1) == "/" {
                    linePtr += 2
                    closed = true
                    break
                }
                linePtr += 1
            }
            if !closed {
                commenting = true
                return nil
            }
            // Skip whitespace after closed comment
            while linePtr < lineBuffer.count {
                let ch = charAtPtr()
                if ch != " " && ch != "\t" { break }
                linePtr += 1
            }
        }

        guard linePtr < lineBuffer.count else { return nil }
        let ch = charAtPtr()

        // Skip line comment (;)
        if ch == ";" { return nil }

        // Only return printable characters
        if ch > " " {
            linePtr += 1
            return ch
        }
        return nil
    }

    func checkParameterGiven() -> Bool {
        let saved = linePtr
        let result = getFirstChar() != nil
        linePtr = saved
        return result
    }

    /// Read an identifier [A-Za-z_][0-9A-Za-z_]*
    func getIdentifier() -> String? {
        let saved = linePtr
        guard let first = getFirstChar() else { return nil }

        if !first.isLetter && first != "_" {
            linePtr = saved
            return nil
        }

        var name = String(first)
        while linePtr < lineBuffer.count {
            let ch = charAtPtr()
            if ch.isLetter || ch.isNumber || ch == "_" {
                name.append(ch)
                linePtr += 1
            } else {
                break
            }
        }
        return name
    }

    /// Read a label name (same as identifier but allows any starting char)
    func getLabelName() -> String? {
        _ = linePtr
        guard let first = getFirstChar() else { return nil }

        var name = String(first)
        while linePtr < lineBuffer.count {
            let ch = charAtPtr()
            if ch.isLetter || ch.isNumber || ch == "_" {
                name.append(ch)
                linePtr += 1
            } else {
                break
            }
        }
        return name.isEmpty ? nil : name
    }

    /// Read a quoted string "..." or '...' or #NNN character codes
    func getString() -> Result<String, TTLError>? {
        let saved = linePtr
        guard let q = getFirstChar() else { return nil }

        if q != "\"" && q != "'" && q != "#" {
            linePtr = saved
            return nil
        }

        linePtr -= 1  // Back up to the quote/hash
        var result = ""

        while linePtr < lineBuffer.count {
            let ch = charAtPtr()
            if ch == "\"" || ch == "'" {
                linePtr += 1  // Skip opening quote
                // Read until matching quote
                while linePtr < lineBuffer.count {
                    let c = charAtPtr()
                    if c == ch {
                        linePtr += 1
                        break
                    }
                    result.append(c)
                    linePtr += 1
                }
            } else if ch == "#" {
                linePtr += 1
                // Read char by code: #decimal or #$hex
                if let code = getCharByCode() {
                    result.append(Character(UnicodeScalar(code)))
                } else {
                    return .failure(.syntax)
                }
            } else {
                break
            }
        }
        return .success(result)
    }

    private func getCharByCode() -> UInt8? {
        guard linePtr < lineBuffer.count else { return nil }
        let ch = charAtPtr()

        var n: UInt32 = 0
        if ch == "$" {
            // Hexadecimal
            linePtr += 1
            while linePtr < lineBuffer.count {
                let c = charAtPtr()
                if c.isHexDigit {
                    if let digit = c.hexDigitValue {
                        n = n * 16 + UInt32(digit)
                    }
                    linePtr += 1
                } else {
                    break
                }
            }
        } else if ch.isNumber {
            // Decimal
            while linePtr < lineBuffer.count {
                let c = charAtPtr()
                if c.isNumber {
                    n = n * 10 + UInt32(c.asciiValue! - Character("0").asciiValue!)
                    linePtr += 1
                } else {
                    break
                }
            }
        } else {
            return nil
        }

        guard n > 0 && n <= 255 else { return nil }
        return UInt8(n)
    }

    /// Read a number: decimal or $hex
    func getNumber() -> Int? {
        let saved = linePtr
        guard let first = getFirstChar() else { return nil }

        if first.isNumber {
            var num = Int(first.asciiValue! - Character("0").asciiValue!)
            while linePtr < lineBuffer.count {
                let ch = charAtPtr()
                if ch.isNumber {
                    num = num * 10 + Int(ch.asciiValue! - Character("0").asciiValue!)
                    linePtr += 1
                } else {
                    break
                }
            }
            return num
        } else if first == "$" {
            // Hexadecimal
            var num = 0
            while linePtr < lineBuffer.count {
                let ch = charAtPtr()
                if ch.isHexDigit, let digit = ch.hexDigitValue {
                    num = num * 16 + digit
                    linePtr += 1
                } else {
                    break
                }
            }
            return num
        } else {
            linePtr = saved
            return nil
        }
    }

    // MARK: - Reserved Word Lookup

    /// Check if identifier is a reserved command word
    func checkReservedWord(_ name: String) -> TTLCommand? {
        let lower = name.lowercased()
        return reservedWords[lower]
    }

    /// Check if identifier is a reserved operator word
    func checkReservedOperator(_ name: String) -> TTLOperator? {
        switch name.lowercased() {
        case "and": return .bAnd
        case "or":  return .bOr
        case "not": return .bNot
        case "xor": return .bXor
        default:    return nil
        }
    }

    /// Get a reserved word from current position
    func getReservedWord() -> TTLCommand? {
        let saved = linePtr
        guard let name = getIdentifier() else { return nil }
        if let cmd = checkReservedWord(name) {
            return cmd
        }
        linePtr = saved
        return nil
    }

    /// Get an operator from current position
    func getOperator() -> TTLOperator? {
        let saved = linePtr
        guard let ch = getFirstChar() else { return nil }

        switch ch {
        case "*": return .mul
        case "+": return .plus
        case "-": return .minus
        case "/": return .div
        case "%": return .mod
        case "=":
            if linePtr < lineBuffer.count && charAtPtr() == "=" { linePtr += 1 }
            return .eq
        case "<":
            if linePtr < lineBuffer.count {
                switch charAtPtr() {
                case "=": linePtr += 1; return .le
                case ">": linePtr += 1; return .ne
                case "<": linePtr += 1; return .alShift
                default: break
                }
            }
            return .lt
        case ">":
            if linePtr < lineBuffer.count {
                switch charAtPtr() {
                case "=": linePtr += 1; return .ge
                case ">":
                    linePtr += 1
                    if linePtr < lineBuffer.count && charAtPtr() == ">" {
                        linePtr += 1; return .lrShift
                    }
                    return .arShift
                default: break
                }
            }
            return .gt
        case "&":
            if linePtr < lineBuffer.count && charAtPtr() == "&" {
                linePtr += 1; return .lAnd
            }
            return .bAnd
        case "|":
            if linePtr < lineBuffer.count && charAtPtr() == "|" {
                linePtr += 1; return .lOr
            }
            return .bOr
        case "^": return .bXor
        case "~": return .bNot
        case "!":
            if linePtr < lineBuffer.count && charAtPtr() == "=" {
                linePtr += 1; return .ne
            }
            return .lNot
        default:
            linePtr -= 1
            // Try reserved word operator (and, or, not, xor)
            if let name = getIdentifier(), let op = checkReservedOperator(name) {
                return op
            }
            linePtr = saved
            return nil
        }
    }

    // MARK: - Expression Parser (recursive descent with operator precedence)

    enum ExprResult {
        case integer(Int)
        case string(Int)    // Variable ID for string
        case intArray(Int)  // Variable ID for int array
        case strArray(Int)  // Variable ID for str array
    }

    /// Parse a full expression (top-level: ||, ^^)
    func getExpression() throws -> ExprResult {
        lineParsePtr = linePtr

        let result = try evalLogicalOr()
        return result
    }

    /// Get an integer value from expression
    func getIntExpression() throws -> Int {
        let result = try getExpression()
        switch result {
        case .integer(let v): return v
        default: throw TTLError.typeMismatch
        }
    }

    /// Get a string value from expression or string literal
    func getStrExpression() throws -> String {
        lineParsePtr = linePtr

        // Try string literal first
        if let strResult = getString() {
            switch strResult {
            case .success(let s): return s
            case .failure(let e): throw e
            }
        }

        // Try expression
        let result = try getExpression()
        switch result {
        case .string(let id): return getStrVal(id: id)
        case .integer(_): throw TTLError.typeMismatch
        default: throw TTLError.typeMismatch
        }
    }

    /// Get a string value, with optional auto-conversion from int
    func getStrExpression(autoConvert: Bool) throws -> String {
        lineParsePtr = linePtr

        // Try string literal first
        if let strResult = getString() {
            switch strResult {
            case .success(let s): return s
            case .failure(let e): throw e
            }
        }

        // Try expression
        let result = try getExpression()
        switch result {
        case .string(let id): return getStrVal(id: id)
        case .integer(let v):
            if autoConvert { return String(v) }
            throw TTLError.typeMismatch
        default: throw TTLError.typeMismatch
        }
    }

    /// Get an integer variable reference (creates if not exists)
    func getIntVar() throws -> Int {
        guard let name = getIdentifier() else { throw TTLError.syntax }
        if let (type, id) = checkVar(name) {
            switch type {
            case .integer: return id
            case .intArray:
                let index = try getIndex()
                return getIntVarFromArray(varId: id, index: index)
            default: throw TTLError.typeMismatch
            }
        } else {
            let id = newIntVar(name, value: 0)
            return id
        }
    }

    /// Get a string variable reference (creates if not exists)
    func getStrVar() throws -> Int {
        guard let name = getIdentifier() else { throw TTLError.syntax }
        if let (type, id) = checkVar(name) {
            switch type {
            case .string: return id
            case .strArray:
                let index = try getIndex()
                return getStrVarFromArray(varId: id, index: index)
            default: throw TTLError.typeMismatch
            }
        } else {
            let id = newStrVar(name, value: "")
            return id
        }
    }

    /// Parse array index [expr]
    func getIndex() throws -> Int {
        let saved = linePtr
        guard getFirstChar() == "[" else {
            linePtr = saved
            throw TTLError.syntax
        }
        let index = try getIntExpression()
        guard getFirstChar() == "]" else {
            throw TTLError.closeBracket
        }
        return index
    }

    func getIntVarFromArray(varId: Int, index: Int) -> Int {
        guard varId < variables.count else { return 0 }
        guard index >= 0 && index < variables[varId].intArray.count else { return 0 }
        return ((varId + 1) << 16) | index
    }

    func getStrVarFromArray(varId: Int, index: Int) -> Int {
        guard varId < variables.count else { return 0 }
        guard index >= 0 && index < variables[varId].strArray.count else { return 0 }
        return ((varId + 1) << 16) | index
    }

    // MARK: - Expression Evaluation (Precedence Climbing)

    // Precedence 1: Factor (variables, numbers, unary ops, parens)
    private func getFactor() throws -> ExprResult {
        let saved = linePtr

        // Try identifier (variable or unary operator keyword)
        if let name = getIdentifier() {
            // Unary operators: not, ~
            if let op = checkReservedOperator(name) {
                let val = try getFactor()
                guard case .integer(let v) = val else { throw TTLError.typeMismatch }
                switch op {
                case .bNot: return .integer(~v)
                case .lNot: return .integer(v == 0 ? 1 : 0)
                default: throw TTLError.syntax
                }
            }
            // Variable
            if let (type, id) = checkVar(name) {
                switch type {
                case .integer: return .integer(variables[id].intValue)
                case .string:  return .string(id)
                case .intArray:
                    let idxSaved = linePtr
                    if let _ = try? getIndex() {
                        linePtr = idxSaved
                        let index = try getIndex()
                        guard index >= 0 && index < variables[id].intArray.count else {
                            throw TTLError.outOfRange
                        }
                        return .integer(variables[id].intArray[index])
                    }
                    return .intArray(id)
                case .strArray:
                    let idxSaved = linePtr
                    if let _ = try? getIndex() {
                        linePtr = idxSaved
                        let index = try getIndex()
                        let arrayVarId = getStrVarFromArray(varId: id, index: index)
                        return .string(arrayVarId)
                    }
                    return .strArray(id)
                default: throw TTLError.varNotInit
                }
            }
            throw TTLError.varNotInit
        }

        // Try number
        if let num = getNumber() {
            return .integer(num)
        }

        // Try unary operator (+, -, ~, !)
        if let op = getOperator() {
            let val = try getFactor()
            guard case .integer(let v) = val else { throw TTLError.typeMismatch }
            switch op {
            case .plus:  return .integer(v)
            case .minus: return .integer(-v)
            case .bNot:  return .integer(~v)
            case .lNot:  return .integer(v == 0 ? 1 : 0)
            default:
                linePtr = saved
                throw TTLError.syntax
            }
        }

        // Try parenthesized expression
        if getFirstChar() == "(" {
            let result = try evalLogicalOr()
            guard getFirstChar() == ")" else { throw TTLError.closeParen }
            return result
        }

        linePtr = saved
        throw TTLError.syntax
    }

    // Precedence 2: *, /, %
    private func evalMultiplication() throws -> ExprResult {
        let result = try getFactor()
        guard case .integer(var val1) = result else { return result }

        while true {
            let saved = linePtr
            guard let op = getOperator() else { return .integer(val1) }
            guard op == .mul || op == .div || op == .mod else {
                linePtr = saved
                return .integer(val1)
            }

            let rhs = try getFactor()
            guard case .integer(let val2) = rhs else { throw TTLError.typeMismatch }

            switch op {
            case .mul: val1 = val1 &* val2
            case .div:
                guard val2 != 0 else { throw TTLError.divByZero }
                val1 = val1 / val2
            case .mod:
                guard val2 != 0 else { throw TTLError.divByZero }
                val1 = val1 % val2
            default: break
            }
        }
    }

    // Precedence 3: +, -
    private func evalAddition() throws -> ExprResult {
        let result = try evalMultiplication()
        guard case .integer(var val1) = result else { return result }

        while true {
            let saved = linePtr
            guard let op = getOperator() else { return .integer(val1) }
            guard op == .plus || op == .minus else {
                linePtr = saved
                return .integer(val1)
            }

            let rhs = try evalMultiplication()
            guard case .integer(let val2) = rhs else { throw TTLError.typeMismatch }

            switch op {
            case .plus:  val1 = val1 &+ val2
            case .minus: val1 = val1 &- val2
            default: break
            }
        }
    }

    // Precedence 4: <<, >>, >>>
    private func evalBitShift() throws -> ExprResult {
        let result = try evalAddition()
        guard case .integer(var val1) = result else { return result }

        while true {
            let saved = linePtr
            guard let op = getOperator() else { return .integer(val1) }
            guard op == .arShift || op == .alShift || op == .lrShift else {
                linePtr = saved
                return .integer(val1)
            }

            let rhs = try evalAddition()
            guard case .integer(let val2) = rhs else { throw TTLError.typeMismatch }

            switch op {
            case .alShift: val1 = val1 << val2
            case .arShift: val1 = val1 >> val2
            case .lrShift: val1 = Int(bitPattern: UInt(bitPattern: val1) >> val2)
            default: break
            }
        }
    }

    // Precedence 5: &
    private func evalBitAnd() throws -> ExprResult {
        let result = try evalBitShift()
        guard case .integer(var val1) = result else { return result }

        while true {
            let saved = linePtr
            guard let op = getOperator() else { return .integer(val1) }
            guard op == .bAnd else { linePtr = saved; return .integer(val1) }

            let rhs = try evalBitShift()
            guard case .integer(let val2) = rhs else { throw TTLError.typeMismatch }
            val1 = val1 & val2
        }
    }

    // Precedence 6: ^
    private func evalBitXor() throws -> ExprResult {
        let result = try evalBitAnd()
        guard case .integer(var val1) = result else { return result }

        while true {
            let saved = linePtr
            guard let op = getOperator() else { return .integer(val1) }
            guard op == .bXor else { linePtr = saved; return .integer(val1) }

            let rhs = try evalBitAnd()
            guard case .integer(let val2) = rhs else { throw TTLError.typeMismatch }
            val1 = val1 ^ val2
        }
    }

    // Precedence 7: |
    private func evalBitOr() throws -> ExprResult {
        let result = try evalBitXor()
        guard case .integer(var val1) = result else { return result }

        while true {
            let saved = linePtr
            guard let op = getOperator() else { return .integer(val1) }
            guard op == .bOr else { linePtr = saved; return .integer(val1) }

            let rhs = try evalBitXor()
            guard case .integer(let val2) = rhs else { throw TTLError.typeMismatch }
            val1 = val1 | val2
        }
    }

    // Precedence 8: <, >, <=, >=
    private func evalComparison() throws -> ExprResult {
        let result = try evalBitOr()
        guard case .integer(var val1) = result else { return result }

        while true {
            let saved = linePtr
            guard let op = getOperator() else { return .integer(val1) }
            guard op == .lt || op == .gt || op == .le || op == .ge else {
                linePtr = saved; return .integer(val1)
            }

            let rhs = try evalBitOr()
            guard case .integer(let val2) = rhs else { throw TTLError.typeMismatch }

            switch op {
            case .lt: val1 = val1 < val2 ? 1 : 0
            case .gt: val1 = val1 > val2 ? 1 : 0
            case .le: val1 = val1 <= val2 ? 1 : 0
            case .ge: val1 = val1 >= val2 ? 1 : 0
            default: break
            }
        }
    }

    // Precedence 9: ==, !=
    private func evalEquality() throws -> ExprResult {
        let result = try evalComparison()
        guard case .integer(var val1) = result else { return result }

        while true {
            let saved = linePtr
            guard let op = getOperator() else { return .integer(val1) }
            guard op == .eq || op == .ne else {
                linePtr = saved; return .integer(val1)
            }

            let rhs = try evalComparison()
            guard case .integer(let val2) = rhs else { throw TTLError.typeMismatch }

            switch op {
            case .eq: val1 = val1 == val2 ? 1 : 0
            case .ne: val1 = val1 != val2 ? 1 : 0
            default: break
            }
        }
    }

    // Precedence 10: &&
    private func evalLogicalAnd() throws -> ExprResult {
        let result = try evalEquality()
        guard case .integer(var val1) = result else { return result }

        while true {
            let saved = linePtr
            guard let op = getOperator() else { return .integer(val1) }
            guard op == .lAnd else { linePtr = saved; return .integer(val1) }

            let rhs = try evalEquality()
            guard case .integer(let val2) = rhs else { throw TTLError.typeMismatch }
            val1 = (val1 != 0 && val2 != 0) ? 1 : 0
        }
    }

    // Precedence 11: ||, xor
    private func evalLogicalOr() throws -> ExprResult {
        let result = try evalLogicalAnd()
        guard case .integer(var val1) = result else { return result }

        while true {
            let saved = linePtr
            guard let op = getOperator() else { return .integer(val1) }
            guard op == .lOr || op == .lXor else {
                linePtr = saved; return .integer(val1)
            }

            let rhs = try evalLogicalAnd()
            guard case .integer(let val2) = rhs else { throw TTLError.typeMismatch }

            switch op {
            case .lOr:  val1 = (val1 != 0 || val2 != 0) ? 1 : 0
            case .lXor: val1 = ((val1 != 0) != (val2 != 0)) ? 1 : 0
            default: break
            }
        }
    }

    // MARK: - Character Access Helpers

    private func charAtPtr() -> Character {
        let idx = lineBuffer.index(lineBuffer.startIndex, offsetBy: linePtr)
        return lineBuffer[idx]
    }

    private func charAt(_ pos: Int) -> Character {
        let idx = lineBuffer.index(lineBuffer.startIndex, offsetBy: pos)
        return lineBuffer[idx]
    }

    // MARK: - Reserved Word Dictionary

    static let sharedReservedWords: [String: TTLCommand] = {
        var dict: [String: TTLCommand] = [:]
        // Basic commands
        dict["beep"] = .beep;       dict["bplusrecv"] = .bplusRecv; dict["bplussend"] = .bplusSend
        dict["break"] = .break_;    dict["bringupbox"] = .bringupBox; dict["basename"] = .basename
        dict["call"] = .call;       dict["callmenu"] = .callMenu;  dict["changedir"] = .changeDir
        dict["checksum8"] = .checksum8; dict["checksum8file"] = .checksum8File
        dict["checksum16"] = .checksum16; dict["checksum16file"] = .checksum16File
        dict["checksum32"] = .checksum32; dict["checksum32file"] = .checksum32File
        dict["clearscreen"] = .clearScreen; dict["clipb2var"] = .clipb2Var
        dict["closesbox"] = .closeSBox; dict["closett"] = .closeTT
        dict["code2str"] = .code2Str;   dict["connect"] = .connect; dict["continue"] = .continue_
        dict["crc16"] = .crc16;     dict["crc16file"] = .crc16File
        dict["crc32"] = .crc32;     dict["crc32file"] = .crc32File; dict["cygconnect"] = .cygConnect
        dict["delpassword"] = .delPassword; dict["delpassword2"] = .delPassword2
        dict["disconnect"] = .disconnect; dict["dispstr"] = .dispStr
        dict["do"] = .do_;          dict["dirname"] = .dirname;     dict["dirnamebox"] = .dirnameBox
        dict["else"] = .else_;      dict["elseif"] = .elseIf
        dict["enablekeyb"] = .enableKeyb; dict["end"] = .end
        dict["endif"] = .endIf;     dict["enduntil"] = .endUntil;   dict["endwhile"] = .endWhile
        dict["exec"] = .exec;       dict["execcmnd"] = .execCmnd;   dict["exit"] = .exit
        dict["expandenv"] = .expandEnv
        dict["fileclose"] = .fileClose; dict["fileconcat"] = .fileConcat; dict["filecopy"] = .fileCopy
        dict["filecreate"] = .fileCreate; dict["filedelete"] = .fileDelete
        dict["filelock"] = .fileLock; dict["filemarkptr"] = .fileMarkPtr
        dict["filenamebox"] = .filenameBox; dict["fileopen"] = .fileOpen
        dict["filereadln"] = .fileReadln; dict["fileread"] = .fileRead
        dict["filerename"] = .fileRename; dict["filesearch"] = .fileSearch
        dict["fileseek"] = .fileSeek; dict["fileseekback"] = .fileSeekBack
        dict["filestat"] = .fileStat; dict["filestrseek"] = .fileStrSeek
        dict["filestrseek2"] = .fileStrSeek2; dict["filetruncate"] = .fileTruncate
        dict["fileunlock"] = .fileUnLock
        dict["filewrite"] = .fileWrite; dict["filewriteln"] = .fileWriteLn
        dict["findclose"] = .findClose; dict["findfirst"] = .findFirst; dict["findnext"] = .findNext
        dict["flushrecv"] = .flushRecv
        dict["foldercreate"] = .folderCreate; dict["folderdelete"] = .folderDelete
        dict["foldersearch"] = .folderSearch; dict["for"] = .for_
        dict["getdate"] = .getDate; dict["getdir"] = .getDir; dict["getenv"] = .getEnv
        dict["getfileattr"] = .getFileAttr; dict["gethostname"] = .getHostname
        dict["getipv4addr"] = .getIPv4Addr; dict["getipv6addr"] = .getIPv6Addr
        dict["getmodemstatus"] = .getModemStatus
        dict["getpassword"] = .getPassword; dict["getpassword2"] = .getPassword2
        dict["getspecialfolder"] = .getSpecialFolder
        dict["gettime"] = .getTime; dict["gettitle"] = .getTitle
        dict["getttdir"] = .getTTDir; dict["getttpos"] = .getTTPos; dict["getver"] = .getVer
        dict["goto"] = .goto_
        dict["if"] = .if_;          dict["ifdefined"] = .ifDefined; dict["include"] = .include
        dict["inputbox"] = .inputBox; dict["int2str"] = .int2Str
        dict["intdim"] = .intDim;   dict["ispassword"] = .isPassword; dict["ispassword2"] = .isPassword2
        dict["kmtfinish"] = .kmtFinish; dict["kmtget"] = .kmtGet
        dict["kmtrecv"] = .kmtRecv; dict["kmtsend"] = .kmtSend
        dict["listbox"] = .listBox; dict["loadkeymap"] = .loadKeyMap
        dict["logautoclosemode"] = .logAutoClose
        dict["logclose"] = .logClose; dict["loginfo"] = .logInfo
        dict["logopen"] = .logOpen; dict["logpause"] = .logPause
        dict["logrotate"] = .logRotate; dict["logstart"] = .logStart; dict["logwrite"] = .logWrite
        dict["loop"] = .loop
        dict["makepath"] = .makePath; dict["messagebox"] = .messageBox; dict["mpause"] = .milliPause
        dict["next"] = .next
        dict["passwordbox"] = .passwordBox; dict["pause"] = .pause
        dict["quickvanrecv"] = .quickVANRecv; dict["quickvansend"] = .quickVANSend
        dict["random"] = .random;   dict["recvln"] = .recvLn; dict["recvfile"] = .recvFile
        dict["regexoption"] = .regexOption; dict["restoresetup"] = .restoreSetup
        dict["return"] = .return;   dict["rotateleft"] = .rotateL; dict["rotateright"] = .rotateR
        dict["scprecv"] = .scpRecv; dict["scpsend"] = .scpSend
        dict["send"] = .send;       dict["sendbreak"] = .sendBreak
        dict["sendbroadcast"] = .sendBroadcast; dict["sendbinary"] = .sendBinary
        dict["sendlnbroadcast"] = .sendlnBroadcast; dict["sendlnmulticast"] = .sendlnMulticast
        dict["sendmulticast"] = .sendMulticast; dict["sendtext"] = .sendText
        dict["setfileattr"] = .setFileAttr; dict["setmulticastname"] = .setMulticastName
        dict["sendfile"] = .sendFile; dict["sendkcode"] = .sendKCode; dict["sendln"] = .sendLn
        dict["setbaud"] = .setBaud; dict["setdate"] = .setDate; dict["setdebug"] = .setDebug
        dict["setdir"] = .setDir;   dict["setdlgpos"] = .setDlgPos
        dict["setdtr"] = .setDtr;   dict["setecho"] = .setEcho
        dict["setenv"] = .setEnv;   dict["setexitcode"] = .setExitCode
        dict["setflowctrl"] = .setFlowCtrl
        dict["setpassword"] = .setPassword; dict["setpassword2"] = .setPassword2
        dict["setrts"] = .setRts
        dict["setserialdelaychar"] = .setSerialDelayChar; dict["setserialdelayline"] = .setSerialDelayLine
        dict["setspeed"] = .setBaud
        dict["setsync"] = .setSync; dict["settime"] = .setTime; dict["settitle"] = .setTitle
        dict["show"] = .show;       dict["showtt"] = .showTT
        dict["sprintf"] = .sprintf; dict["sprintf2"] = .sprintf2
        dict["statusbox"] = .statusBox
        dict["str2code"] = .str2Code; dict["str2int"] = .str2Int
        dict["strcompare"] = .strCompare; dict["strconcat"] = .strConcat; dict["strcopy"] = .strCopy
        dict["strdim"] = .strDim;   dict["strinsert"] = .strInsert; dict["strjoin"] = .strJoin
        dict["strlen"] = .strLen;   dict["strmatch"] = .strMatch
        dict["strremove"] = .strRemove; dict["strreplace"] = .strReplace
        dict["strscan"] = .strScan; dict["strspecial"] = .strSpecial
        dict["strsplit"] = .strSplit; dict["strtrim"] = .strTrim
        dict["testlink"] = .testLink; dict["then"] = .then
        dict["tolower"] = .toLower; dict["toupper"] = .toUpper
        dict["unlink"] = .unlink;   dict["until"] = .until; dict["uptime"] = .uptime
        dict["var2clipb"] = .var2Clipb
        dict["waitregex"] = .waitRegex; dict["wait"] = .wait
        dict["wait4all"] = .wait4all; dict["waitevent"] = .waitEvent
        dict["waitln"] = .waitLn;   dict["waitn"] = .waitN; dict["waitrecv"] = .waitRecv
        dict["while"] = .while_
        dict["xmodemrecv"] = .xmodemRecv; dict["xmodemsend"] = .xmodemSend
        dict["yesnobox"] = .yesNoBox
        dict["ymodemrecv"] = .ymodemRecv; dict["ymodemsend"] = .ymodemSend
        dict["zmodemrecv"] = .zmodemRecv; dict["zmodemsend"] = .zmodemSend
        return dict
    }()

    var reservedWords: [String: TTLCommand] { TTLParser.sharedReservedWords }
}
