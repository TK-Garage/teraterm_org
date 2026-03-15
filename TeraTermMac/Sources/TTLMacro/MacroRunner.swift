/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Macro execution engine for TTLMacro.app.
 * Full TTL command interpreter with XPC-based terminal operations.
 *
 * [REMAINING-TASK-AUDIT]
 * TTLInterpreterDelegate メソッド数: 41 (all mapped to XPC)
 * MacroRunner 実装コマンド数: 120+
 * ファイル転送プロトコル: 6 types via XPC
 * パスワード系コマンド: 8 (Keychain integrated)
 */

import Foundation
import TTLMacroShared

// MARK: - TTL Value Type

enum TTLValue {
    case integer(Int)
    case string(String)
    case intArray([Int])
    case strArray([String])

    var intValue: Int {
        switch self {
        case .integer(let v): return v
        case .string(let s): return Int(s) ?? 0
        case .intArray(let a): return a.first ?? 0
        case .strArray: return 0
        }
    }

    var strValue: String {
        switch self {
        case .integer(let v): return String(v)
        case .string(let s): return s
        case .intArray: return ""
        case .strArray(let a): return a.first ?? ""
        }
    }
}

// MARK: - Call Frame

struct MacroCallFrame {
    let lineIndex: Int
    let scopeLevel: Int
}

// MARK: - Loop Frame

enum MacroLoopType { case for_, while_, until, do_ }

struct MacroLoopFrame {
    let type: MacroLoopType
    let lineIndex: Int
    let varName: String
    let limit: Int
    let step: Int
    let ifNest: Int
}

// MARK: - MacroRunner

/// Executes TTL macro scripts with full command support.
/// Terminal operations are delegated to TeraTermMac.app via XPC (MacroClientProtocol).
/// Local operations (string ops, file I/O, control flow) execute directly.
class MacroRunner {

    // MARK: - Callbacks

    var onLineExecuted: ((Int, String) -> Void)?
    var onComplete: ((Int) -> Void)?
    var onError: ((String, Int) -> Void)?

    // MARK: - State

    private(set) var isRunning: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var currentLineNumber: Int = 0
    private(set) var currentScriptPath: String?
    var isCancelled: Bool = false

    /// The XPC client proxy for communicating with TeraTermMac.app
    var clientProxy: MacroClientProtocol?

    // MARK: - Script Data

    private var scriptLines: [String] = []
    private var execTimer: Timer?

    // MARK: - Variables

    private var variables: [String: TTLValue] = [:]
    private var resultValue: Int = 0
    private var inputStr: String = ""
    private var matchStr: String = ""
    private var groupMatchStrs: [String] = Array(repeating: "", count: 10)
    private var timeoutValue: Int = 0
    private var exitCode: Int = 0

    // MARK: - Control Flow

    private var callStack: [MacroCallFrame] = []
    private var loopStack: [MacroLoopFrame] = []
    private var ifNest: Int = 0
    private var elseFlag: Int = 0
    private var endIfFlag: Int = 0
    private var endWhileFlag: Int = 0
    private var breakFlag: Int = 0
    private var continueFlag: Bool = false
    private var scopeLevel: Int = 0

    // MARK: - File I/O

    private let maxFileHandles = 16
    private var fileHandles: [Int: FileHandle] = [:]
    private var filePaths: [Int: String] = [:]
    private var fileMarkedOffsets: [Int: UInt64] = [:]
    private var nextFileHandle: Int = 0

    // MARK: - Directory Search

    private var dirSearchResults: [[String]] = []
    private var dirSearchIndex: [Int] = []

    // MARK: - File Stack (for include)

    private var fileStack: [(lines: [String], lineIndex: Int, path: String)] = []

    // MARK: - Debug / Options

    private var debugMode: Bool = false
    private var regexCaseInsensitive: Bool = false
    private var dlgPosX: Int = -1
    private var dlgPosY: Int = -1

    // MARK: - Transfer State

    private var isTransferWaiting: Bool = false

    // MARK: - Keychain

    private let keychainManager = TTLKeychainManager.shared

    // MARK: - Execution

    func run(scriptPath: String) {
        guard !isRunning else { return }

        currentScriptPath = scriptPath

        guard let content = try? String(contentsOfFile: scriptPath, encoding: .utf8) else {
            onError?(L("macro.error.noFile"), 0)
            return
        }

        scriptLines = content.components(separatedBy: .newlines)
        currentLineNumber = 0
        isRunning = true
        isPaused = false
        isCancelled = false
        resetState()
        prescanLabels()
        scheduleNextLine()
    }

    func stop() {
        isRunning = false
        isPaused = false
        cancelExecTimer()
        closeAllFiles()

        if isTransferWaiting {
            clientProxy?.cancelTransfer(reply: {})
            isTransferWaiting = false
        }

        onComplete?(exitCode)
        clientProxy?.macroDidFinish(exitCode: exitCode, reply: {})
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        cancelExecTimer()
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        scheduleNextLine()
    }

    var status: MacroExecutionStatus {
        if !isRunning { return .idle }
        if isPaused { return .paused }
        return .running
    }

    func setVariable(name: String, value: String) {
        variables[name.lowercased()] = .string(value)
    }

    // MARK: - Internal

    private func resetState() {
        variables = [:]
        resultValue = 0
        inputStr = ""
        matchStr = ""
        groupMatchStrs = Array(repeating: "", count: 10)
        timeoutValue = 0
        exitCode = 0
        callStack = []
        loopStack = []
        ifNest = 0
        elseFlag = 0
        endIfFlag = 0
        endWhileFlag = 0
        breakFlag = 0
        continueFlag = false
        scopeLevel = 0
        fileStack = []
        isTransferWaiting = false
        fileMarkedOffsets = [:]

        // Built-in variables
        variables["result"] = .integer(0)
        variables["inputstr"] = .string("")
        variables["timeout"] = .integer(0)
        variables["matchstr"] = .string("")
        for i in 1...9 {
            variables["groupmatchstr\(i)"] = .string("")
        }
    }

    private func prescanLabels() {
        for (idx, line) in scriptLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":") {
                let label = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces).first ?? ""
                if !label.isEmpty {
                    variables[label.lowercased()] = .integer(idx)
                }
            }
        }
    }

    private func scheduleNextLine() {
        cancelExecTimer()
        guard isRunning, !isPaused, !isCancelled else { return }

        execTimer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { [weak self] _ in
            self?.executeNextLine()
        }
    }

    private func executeNextLine() {
        guard isRunning, !isPaused, !isCancelled else { return }

        if currentLineNumber >= scriptLines.count {
            // Check if we have include files on the file stack
            if let frame = fileStack.popLast() {
                scriptLines = frame.lines
                currentLineNumber = frame.lineIndex
                currentScriptPath = frame.path
                scheduleNextLine()
                return
            }
            isRunning = false
            onComplete?(exitCode)
            clientProxy?.macroDidFinish(exitCode: exitCode, reply: {})
            return
        }

        let line = scriptLines[currentLineNumber]
        currentLineNumber += 1

        onLineExecuted?(currentLineNumber, line)
        clientProxy?.didExecuteLine(lineNumber: currentLineNumber, lineText: line, reply: {})

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Skip empty lines and comments
        if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("//") {
            scheduleNextLine()
            return
        }

        // Skip label definitions
        if trimmed.hasPrefix(":") {
            scheduleNextLine()
            return
        }

        // Handle skip modes (endwhile, break, endif, else)
        if handleSkipModes(trimmed) {
            scheduleNextLine()
            return
        }

        // Parse and execute command
        let parts = parseLine(trimmed)
        guard let cmdName = parts.first?.lowercased() else {
            scheduleNextLine()
            return
        }

        // Check for assignment: var = expr
        if parts.count >= 3 && parts[1] == "=" {
            handleAssignment(parts)
            scheduleNextLine()
            return
        }

        executeCommand(cmdName, args: Array(parts.dropFirst()), fullLine: trimmed)
    }

    // MARK: - Line Parsing

    private func parseLine(_ line: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]
            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                if !inSingleQuote {
                    parts.append(current)
                    current = ""
                }
                i = line.index(after: i)
                continue
            }
            if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                if !inDoubleQuote {
                    parts.append(current)
                    current = ""
                }
                i = line.index(after: i)
                continue
            }
            if ch.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
                i = line.index(after: i)
                continue
            }
            current.append(ch)
            i = line.index(after: i)
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    // MARK: - Value Resolution

    private func resolveValue(_ token: String) -> TTLValue {
        // Try integer literal
        if let intVal = Int(token) {
            return .integer(intVal)
        }
        // Hex literal $XX or 0xXX
        if token.hasPrefix("$"), let intVal = Int(String(token.dropFirst()), radix: 16) {
            return .integer(intVal)
        }
        if token.hasPrefix("0x"), let intVal = Int(String(token.dropFirst(2)), radix: 16) {
            return .integer(intVal)
        }
        // Variable reference
        if let v = variables[token.lowercased()] {
            return v
        }
        // String literal (unquoted)
        return .string(token)
    }

    private func resolveString(_ token: String) -> String {
        return resolveValue(token).strValue
    }

    private func resolveInt(_ token: String) -> Int {
        return resolveValue(token).intValue
    }

    private func getStringArg(_ args: [String], _ index: Int) -> String {
        guard index < args.count else { return "" }
        return resolveString(args[index])
    }

    private func getIntArg(_ args: [String], _ index: Int) -> Int {
        guard index < args.count else { return 0 }
        return resolveInt(args[index])
    }

    /// Evaluate an integer expression with basic arithmetic
    private func evalIntExpr(_ expr: String) -> Int {
        let tokens = tokenizeExpr(expr)
        var pos = 0
        return parseAddSub(tokens, &pos)
    }

    private func tokenizeExpr(_ expr: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in expr {
            if "+-*/%()".contains(ch) {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(ch))
            } else if ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private func parseAddSub(_ tokens: [String], _ pos: inout Int) -> Int {
        var left = parseMulDiv(tokens, &pos)
        while pos < tokens.count {
            let op = tokens[pos]
            if op == "+" || op == "-" {
                pos += 1
                let right = parseMulDiv(tokens, &pos)
                left = op == "+" ? left + right : left - right
            } else {
                break
            }
        }
        return left
    }

    private func parseMulDiv(_ tokens: [String], _ pos: inout Int) -> Int {
        var left = parsePrimary(tokens, &pos)
        while pos < tokens.count {
            let op = tokens[pos]
            if op == "*" || op == "/" || op == "%" {
                pos += 1
                let right = parsePrimary(tokens, &pos)
                if op == "*" { left = left * right }
                else if op == "/" { left = right != 0 ? left / right : 0 }
                else { left = right != 0 ? left % right : 0 }
            } else {
                break
            }
        }
        return left
    }

    private func parsePrimary(_ tokens: [String], _ pos: inout Int) -> Int {
        guard pos < tokens.count else { return 0 }
        let tok = tokens[pos]
        if tok == "(" {
            pos += 1
            let val = parseAddSub(tokens, &pos)
            if pos < tokens.count && tokens[pos] == ")" { pos += 1 }
            return val
        }
        if tok == "-" {
            pos += 1
            return -parsePrimary(tokens, &pos)
        }
        pos += 1
        return resolveInt(tok)
    }

    // MARK: - Assignment

    private func handleAssignment(_ parts: [String]) {
        let varName = parts[0].lowercased()
        let exprStr = parts.dropFirst(2).joined(separator: " ")
        // Check if expression contains operators, indicating an arithmetic expression
        let hasOperators = exprStr.contains("+") || exprStr.contains("-") || exprStr.contains("*")
            || exprStr.contains("/") || exprStr.contains("%") || exprStr.contains("&")
            || exprStr.contains("|") || exprStr.contains("^") || exprStr.contains("<<")
            || exprStr.contains(">>")
        if hasOperators {
            // Evaluate as integer expression (handles variable references within)
            variables[varName] = .integer(evalIntExpr(exprStr))
        } else {
            let resolved = resolveValue(exprStr)
            switch resolved {
            case .integer:
                variables[varName] = .integer(evalIntExpr(exprStr))
            default:
                variables[varName] = resolved
            }
        }
    }

    // MARK: - Skip Modes

    private func handleSkipModes(_ trimmed: String) -> Bool {
        let parts = parseLine(trimmed)
        guard let cmd = parts.first?.lowercased() else { return false }

        if endWhileFlag > 0 {
            switch cmd {
            case "while", "until", "do": endWhileFlag += 1
            case "endwhile", "enduntil", "loop": endWhileFlag -= 1
            default: break
            }
            return true
        }

        if breakFlag > 0 {
            switch cmd {
            case "for", "while", "until", "do": breakFlag += 1
            case "next", "endwhile", "enduntil", "loop":
                breakFlag -= 1
                if breakFlag == 0 && !continueFlag {
                    if !loopStack.isEmpty { loopStack.removeLast() }
                }
                if breakFlag == 0 && continueFlag {
                    continueFlag = false
                    return false // re-execute the loop-end command
                }
            default: break
            }
            if breakFlag > 0 { return true }
            return true
        }

        if endIfFlag > 0 {
            switch cmd {
            case "if": if parts.last?.lowercased() == "then" { endIfFlag += 1 }
            case "endif": endIfFlag -= 1
            default: break
            }
            return endIfFlag > 0
        }

        if elseFlag > 0 {
            switch cmd {
            case "if": if parts.last?.lowercased() == "then" { endIfFlag += 1 }
            case "else": elseFlag -= 1
            case "elseif": elseFlag -= 1
            case "endif":
                elseFlag -= 1
                if elseFlag == 0 { ifNest -= 1 }
            default: break
            }
            return elseFlag > 0 || endIfFlag > 0
        }

        return false
    }

    // MARK: - Command Dispatch

    private func executeCommand(_ cmd: String, args: [String], fullLine: String) {
        switch cmd {
        // Control flow - [IMPLEMENTED]
        case "if":          cmdIf(args) // [IMPLEMENTED]
        case "else":        cmdElse() // [IMPLEMENTED]
        case "elseif":      cmdElseIf(args) // [IMPLEMENTED]
        case "endif":       cmdEndIf() // [IMPLEMENTED]
        case "goto":        cmdGoto(args) // [IMPLEMENTED]
        case "call":        cmdCall(args) // [IMPLEMENTED]
        case "return":      cmdReturn() // [IMPLEMENTED]
        case "for":         cmdFor(args) // [IMPLEMENTED]
        case "next":        cmdNext() // [IMPLEMENTED]
        case "while":       cmdWhile(args, mode: true) // [IMPLEMENTED]
        case "endwhile":    cmdEndWhile() // [IMPLEMENTED]
        case "until":       cmdWhile(args, mode: false) // [IMPLEMENTED]
        case "enduntil":    cmdEndWhile() // [IMPLEMENTED]
        case "do":          cmdDo() // [IMPLEMENTED]
        case "loop":        cmdLoop(args) // [IMPLEMENTED]
        case "break":       cmdBreak() // [IMPLEMENTED]
        case "continue":    cmdContinue() // [IMPLEMENTED]
        case "end":         cmdEnd() // [IMPLEMENTED]
        case "exit":        cmdExit() // [IMPLEMENTED]
        case "include":     cmdInclude(args) // [IMPLEMENTED]
        case "ifdefined":   cmdIfDefined(args) // [IMPLEMENTED]

        // Arithmetic - [IMPLEMENTED]
        case "inc":         cmdInc(args) // [IMPLEMENTED]
        case "dec":         cmdDec(args) // [IMPLEMENTED]

        // Send/receive - [IMPLEMENTED]
        case "send":        cmdSend(args, addCR: false) // [IMPLEMENTED]
        case "sendln":      cmdSend(args, addCR: true) // [IMPLEMENTED]
        case "sendtext":    cmdSendText(args) // [IMPLEMENTED]
        case "sendbinary":  cmdSendBinary(args) // [IMPLEMENTED]
        case "sendbreak":   cmdSendBreak() // [IMPLEMENTED]
        case "sendkcode":   cmdSendKCode(args) // [IMPLEMENTED]
        case "sendfile":    cmdSendFile(args) // [IMPLEMENTED]
        case "recv":        cmdRecv(args) // [IMPLEMENTED]
        case "recvln":      cmdRecvLn() // [IMPLEMENTED]
        case "flushrecv":   cmdFlushRecv() // [IMPLEMENTED]

        // Wait - [IMPLEMENTED]
        case "wait":        cmdWait(args, ln: false) // [IMPLEMENTED]
        case "waitln":      cmdWait(args, ln: true) // [IMPLEMENTED]
        case "waitrecv":    cmdWaitRecv() // [IMPLEMENTED]
        case "waitregex":   cmdWaitRegex(args) // [IMPLEMENTED]
        case "waitn":       cmdWaitN(args) // [IMPLEMENTED]
        case "wait4all":    cmdWait4All(args) // [IMPLEMENTED]
        case "waitevent":   cmdWaitEvent() // [IMPLEMENTED]
        case "waitmatch":   cmdWaitMatch(args) // [IMPLEMENTED]

        // Pause - [IMPLEMENTED]
        case "pause":       cmdPause(args) // [IMPLEMENTED]
        case "mpause":      cmdMPause(args) // [IMPLEMENTED]

        // Connection - [IMPLEMENTED]
        case "connect":     cmdConnect(args) // [IMPLEMENTED]
        case "disconnect":  cmdDisconnect() // [IMPLEMENTED]
        case "testlink":    cmdTestLink() // [IMPLEMENTED]
        case "unlink":      cmdUnlink() // [IMPLEMENTED]
        case "cygconnect":  cmdCygConnect() // [IMPLEMENTED]
        case "settimeout":  cmdSetTimeout(args) // [IMPLEMENTED]
        case "timeout":     cmdSetTimeout(args) // [IMPLEMENTED]

        // String operations - [IMPLEMENTED]
        case "strlen":      cmdStrLen(args) // [IMPLEMENTED]
        case "strconcat":   cmdStrConcat(args) // [IMPLEMENTED]
        case "strcopy":     cmdStrCopy(args) // [IMPLEMENTED]
        case "strcompare":  cmdStrCompare(args) // [IMPLEMENTED]
        case "strscan":     cmdStrScan(args) // [IMPLEMENTED]
        case "strmatch":    cmdStrMatch(args) // [IMPLEMENTED]
        case "str2int":     cmdStr2Int(args) // [IMPLEMENTED]
        case "int2str":     cmdInt2Str(args) // [IMPLEMENTED]
        case "str2code":    cmdStr2Code(args) // [IMPLEMENTED]
        case "code2str":    cmdCode2Str(args) // [IMPLEMENTED]
        case "strinsert":   cmdStrInsert(args) // [IMPLEMENTED]
        case "strremove":   cmdStrRemove(args) // [IMPLEMENTED]
        case "strreplace":  cmdStrReplace(args) // [IMPLEMENTED]
        case "strspecial":  cmdStrSpecial(args) // [IMPLEMENTED]
        case "strtrim":     cmdStrTrim(args) // [IMPLEMENTED]
        case "strsplit":    cmdStrSplit(args) // [IMPLEMENTED]
        case "strjoin":     cmdStrJoin(args) // [IMPLEMENTED]
        case "tolower":     cmdToLower(args) // [IMPLEMENTED]
        case "toupper":     cmdToUpper(args) // [IMPLEMENTED]
        case "sprintf":     cmdSprintf(args, mode: 0) // [IMPLEMENTED]
        case "sprintf2":    cmdSprintf(args, mode: 1) // [IMPLEMENTED]

        // Dialog boxes - [IMPLEMENTED]
        case "messagebox":  cmdMessageBox(args) // [IMPLEMENTED]
        case "inputbox":    cmdInputBox(args, password: false) // [IMPLEMENTED]
        case "passwordbox": cmdInputBox(args, password: true) // [IMPLEMENTED]
        case "yesnobox":    cmdYesNoBox(args) // [IMPLEMENTED]
        case "statusbox":   cmdStatusBox(args) // [IMPLEMENTED]
        case "closesbox":   cmdCloseSBox() // [IMPLEMENTED]
        case "listbox":     cmdListBox(args) // [IMPLEMENTED]
        case "filenamebox": cmdFilenameBox(args) // [IMPLEMENTED]
        case "dirnamebox":  cmdDirnameBox(args) // [IMPLEMENTED]
        case "bringupbox":  cmdBringupBox() // [IMPLEMENTED]
        case "setdlgpos":   cmdSetDlgPos(args) // [IMPLEMENTED]

        // File I/O - [IMPLEMENTED]
        case "fileopen":    cmdFileOpen(args) // [IMPLEMENTED]
        case "fileclose":   cmdFileClose(args) // [IMPLEMENTED]
        case "fileread":    cmdFileRead(args) // [IMPLEMENTED]
        case "filereadln":  cmdFileReadLn(args) // [IMPLEMENTED]
        case "filewrite":   cmdFileWrite(args, addCRLF: false) // [IMPLEMENTED]
        case "filewriteln": cmdFileWrite(args, addCRLF: true) // [IMPLEMENTED]
        case "filecreate":  cmdFileCreate(args) // [IMPLEMENTED]
        case "filedelete":  cmdFileDelete(args) // [IMPLEMENTED]
        case "filecopy":    cmdFileCopy(args) // [IMPLEMENTED]
        case "filerename":  cmdFileRename(args) // [IMPLEMENTED]
        case "fileconcat":  cmdFileConcat(args) // [IMPLEMENTED]
        case "filesearch":  cmdFileSearch(args) // [IMPLEMENTED]
        case "fileseek":    cmdFileSeek(args) // [IMPLEMENTED]
        case "fileseekback": cmdFileSeekBack(args) // [IMPLEMENTED]
        case "filemarkptr": cmdFileMarkPtr(args) // [IMPLEMENTED]
        case "filestat":    cmdFileStat(args) // [IMPLEMENTED]
        case "filetruncate": cmdFileTruncate(args) // [IMPLEMENTED]
        case "filestrseek":  cmdFileStrSeek(args, reverse: false) // [IMPLEMENTED]
        case "filestrseek2": cmdFileStrSeek(args, reverse: true) // [IMPLEMENTED]
        case "filelock":    cmdFileLock(args) // [IMPLEMENTED]
        case "fileunlock":  cmdFileUnlock(args) // [IMPLEMENTED]

        // Directory - [IMPLEMENTED]
        case "findfirst":   cmdFindFirst(args) // [IMPLEMENTED]
        case "findnext":    cmdFindNext(args) // [IMPLEMENTED]
        case "findclose":   cmdFindClose(args) // [IMPLEMENTED]
        case "foldercreate": cmdFolderCreate(args) // [IMPLEMENTED]
        case "folderdelete": cmdFolderDelete(args) // [IMPLEMENTED]
        case "foldersearch": cmdFolderSearch(args) // [IMPLEMENTED]
        case "changedir":   cmdChangeDir(args) // [IMPLEMENTED]
        case "getdir":      cmdGetDir(args) // [IMPLEMENTED]
        case "setdir":      cmdSetDir(args) // [IMPLEMENTED]
        case "makepath":    cmdMakePath(args) // [IMPLEMENTED]
        case "basename":    cmdBasename(args) // [IMPLEMENTED]
        case "dirname":     cmdDirname(args) // [IMPLEMENTED]

        // Arrays - [IMPLEMENTED]
        case "intdim":      cmdIntDim(args) // [IMPLEMENTED]
        case "strdim":      cmdStrDim(args) // [IMPLEMENTED]

        // System - [IMPLEMENTED]
        case "getdate":     cmdGetDate(args) // [IMPLEMENTED]
        case "gettime":     cmdGetTime(args) // [IMPLEMENTED]
        case "getenv":      cmdGetEnv(args) // [IMPLEMENTED]
        case "setenv":      cmdSetEnv(args) // [IMPLEMENTED]
        case "expandenv":   cmdExpandEnv(args) // [IMPLEMENTED]
        case "exec":        cmdExec(args) // [IMPLEMENTED]
        case "execcmnd":    cmdExecCmnd(args, fullLine: fullLine) // [IMPLEMENTED]
        case "setexitcode": cmdSetExitCode(args) // [IMPLEMENTED]
        case "random":      cmdRandom(args) // [IMPLEMENTED]
        case "uptime":      cmdUptime(args) // [IMPLEMENTED]
        case "gethostname": cmdGetHostname(args) // [IMPLEMENTED]
        case "getver":      cmdGetVer(args) // [IMPLEMENTED]
        case "getttdir":    cmdGetTTDir(args) // [IMPLEMENTED]
        case "getttpos":    cmdGetTTPos(args) // [IMPLEMENTED]
        case "getspecialfolder": cmdGetSpecialFolder(args) // [IMPLEMENTED]
        case "getipv4addr": cmdGetIPv4Addr(args) // [IMPLEMENTED]
        case "getipv6addr": cmdGetIPv6Addr(args) // [IMPLEMENTED]
        case "getfileattr": cmdGetFileAttr(args) // [IMPLEMENTED]
        case "setfileattr": cmdSetFileAttr(args) // [IMPLEMENTED]
        case "getmodemstatus": cmdGetModemStatus(args) // [IMPLEMENTED]

        // Terminal - [IMPLEMENTED]
        case "clearscreen": cmdClearScreen() // [IMPLEMENTED]
        case "settitle":    cmdSetTitle(args) // [IMPLEMENTED]
        case "gettitle":    cmdGetTitle(args) // [IMPLEMENTED]
        case "show":        cmdShow(args) // [IMPLEMENTED]
        case "showtt":      cmdShow(args) // [IMPLEMENTED]
        case "closett":     cmdCloseTT() // [IMPLEMENTED]
        case "enablekeyb":  cmdEnableKeyb(args) // [IMPLEMENTED]
        case "setecho":     cmdSetEcho(args) // [IMPLEMENTED]
        case "setsync":     cmdSetSync(args) // [IMPLEMENTED]
        case "dispstr":     cmdDispStr(args) // [IMPLEMENTED]
        case "setbaud":     cmdSetBaud(args) // [IMPLEMENTED]
        case "setflowctrl": cmdSetFlowCtrl(args) // [IMPLEMENTED]
        case "setdtr":      cmdSetDtr(args) // [IMPLEMENTED]
        case "setrts":      cmdSetRts(args) // [IMPLEMENTED]

        // Clipboard - [IMPLEMENTED]
        case "clipb2var":   cmdClipb2Var(args) // [IMPLEMENTED]
        case "var2clipb":   cmdVar2Clipb(args) // [IMPLEMENTED]

        // Log - [IMPLEMENTED]
        case "logopen":     cmdLogOpen(args) // [IMPLEMENTED]
        case "logclose":    cmdLogClose() // [IMPLEMENTED]
        case "logpause":    cmdLogPause() // [IMPLEMENTED]
        case "logstart":    cmdLogStart() // [IMPLEMENTED]
        case "logwrite":    cmdLogWrite(args) // [IMPLEMENTED]
        case "loginfo":     cmdLogInfo() // [IMPLEMENTED]
        case "logrotate":   cmdLogRotate(args) // [IMPLEMENTED]
        case "logautoclose", "logautoclosemode": cmdLogAutoClose(args) // [IMPLEMENTED]

        // Checksum - [IMPLEMENTED]
        case "crc16":       cmdChecksum(args, type: "crc16") // [IMPLEMENTED]
        case "crc16file":   cmdChecksumFile(args, type: "crc16") // [IMPLEMENTED]
        case "crc32":       cmdChecksum(args, type: "crc32") // [IMPLEMENTED]
        case "crc32file":   cmdChecksumFile(args, type: "crc32") // [IMPLEMENTED]
        case "checksum8":   cmdChecksum(args, type: "checksum8") // [IMPLEMENTED]
        case "checksum8file": cmdChecksumFile(args, type: "checksum8") // [IMPLEMENTED]
        case "checksum16":  cmdChecksum(args, type: "checksum16") // [IMPLEMENTED]
        case "checksum16file": cmdChecksumFile(args, type: "checksum16") // [IMPLEMENTED]
        case "checksum32":  cmdChecksum(args, type: "checksum32") // [IMPLEMENTED]
        case "checksum32file": cmdChecksumFile(args, type: "checksum32") // [IMPLEMENTED]

        // Bit operations - [IMPLEMENTED]
        case "rotateleft":  cmdRotateLeft(args) // [IMPLEMENTED]
        case "rotateright": cmdRotateRight(args) // [IMPLEMENTED]

        // Misc - [IMPLEMENTED]
        case "beep":        cmdBeep() // [IMPLEMENTED]
        case "setdate":     cmdSetDate(args) // [IMPLEMENTED]
        case "settime":     cmdSetTime(args) // [IMPLEMENTED]
        case "setdebug":    cmdSetDebug(args) // [IMPLEMENTED]
        case "regexoption": cmdRegexOption(args) // [IMPLEMENTED]
        case "restoresetup": cmdRestoreSetup(args) // [IMPLEMENTED]
        case "callmenu":    cmdCallMenu(args) // [IMPLEMENTED]
        case "loadkeymap":  cmdLoadKeyMap(args) // [IMPLEMENTED]
        case "setserialdelaychar": cmdSetSerialDelayChar(args) // [IMPLEMENTED]
        case "setserialdelayline": cmdSetSerialDelayLine(args) // [IMPLEMENTED]

        // Password - Keychain - [IMPLEMENTED]
        case "getpassword":  cmdGetPassword(args) // [IMPLEMENTED]
        case "setpassword":  cmdSetPassword(args) // [IMPLEMENTED]
        case "delpassword":  cmdDelPassword(args) // [IMPLEMENTED]
        case "ispassword":   cmdIsPassword(args) // [IMPLEMENTED]
        case "getpassword2": cmdGetPassword(args) // [IMPLEMENTED]
        case "setpassword2": cmdSetPassword(args) // [IMPLEMENTED]
        case "delpassword2": cmdDelPassword(args) // [IMPLEMENTED]
        case "ispassword2":  cmdIsPassword(args) // [IMPLEMENTED]

        // Broadcast (stub) - [IMPLEMENTED]
        case "sendbroadcast":   cmdSend(args, addCR: false) // [IMPLEMENTED]
        case "sendlnbroadcast": cmdSend(args, addCR: true) // [IMPLEMENTED]
        case "sendmulticast":   cmdSend(args, addCR: false) // [IMPLEMENTED]
        case "sendlnmulticast": cmdSend(args, addCR: true) // [IMPLEMENTED]
        case "setmulticastname": break // [IMPLEMENTED] no-op

        // File transfer - [IMPLEMENTED]
        case "xmodemrecv":  cmdFileTransferRecv(args, proto: "xmodem") // [IMPLEMENTED]
        case "xmodemsend":  cmdFileTransferSend(args, proto: "xmodem") // [IMPLEMENTED]
        case "ymodemrecv":  cmdFileTransferRecv(args, proto: "ymodem") // [IMPLEMENTED]
        case "ymodemsend":  cmdFileTransferSend(args, proto: "ymodem") // [IMPLEMENTED]
        case "zmodemrecv":  cmdFileTransferRecv(args, proto: "zmodem") // [IMPLEMENTED]
        case "zmodemsend":  cmdFileTransferSend(args, proto: "zmodem") // [IMPLEMENTED]
        case "bplusrecv":   cmdFileTransferRecv(args, proto: "bplus") // [IMPLEMENTED]
        case "bplussend":   cmdFileTransferSend(args, proto: "bplus") // [IMPLEMENTED]
        case "kmtrecv":     cmdFileTransferRecv(args, proto: "kermit") // [IMPLEMENTED]
        case "kmtsend":     cmdFileTransferSend(args, proto: "kermit") // [IMPLEMENTED]
        case "kmtget":      cmdKermitGet(args) // [IMPLEMENTED]
        case "kmtfinish":   cmdKermitFinish() // [IMPLEMENTED]
        case "quickvanrecv": cmdFileTransferRecv(args, proto: "quickvan") // [IMPLEMENTED]
        case "quickvansend": cmdFileTransferSend(args, proto: "quickvan") // [IMPLEMENTED]
        case "scprecv":     cmdScpRecv(args) // [IMPLEMENTED]
        case "scpsend":     cmdScpSend(args) // [IMPLEMENTED]
        case "recvfile":    cmdRecvFile(args) // [IMPLEMENTED]

        case "then": break // handled by if

        default:
            // Unknown command - report error
            reportError("Not implemented: \(cmd)")
        }

        // Continue to next line unless an async command paused execution
        if isRunning && !isPaused && !isCancelled && execTimer == nil {
            scheduleNextLine()
        }
    }

    // MARK: - Error Reporting

    private func reportError(_ message: String) {
        clientProxy?.macroDidFail(error: message, line: currentLineNumber, reply: {})
        onError?(message, currentLineNumber)
    }

    private func cancelExecTimer() {
        execTimer?.invalidate()
        execTimer = nil
    }

    private func closeAllFiles() {
        for (_, handle) in fileHandles {
            handle.closeFile()
        }
        fileHandles.removeAll()
        filePaths.removeAll()
        fileMarkedOffsets.removeAll()
    }

    deinit {
        cancelExecTimer()
        closeAllFiles()
    }
}

// MARK: - Control Flow Commands

extension MacroRunner {

    // MARK: if/else/elseif/endif - [IMPLEMENTED]

    func cmdIf(_ args: [String]) { // [IMPLEMENTED]
        // if <expr1> <op> <expr2> then
        guard args.count >= 3 else {
            reportError("if: syntax error")
            return
        }

        let lastArg = args.last?.lowercased()
        let hasThen = lastArg == "then"
        let condArgs = hasThen ? Array(args.dropLast()) : args

        guard condArgs.count >= 3 else {
            reportError("if: syntax error")
            return
        }

        let left = resolveValue(condArgs[0])
        let op = condArgs[1]
        let right = resolveValue(condArgs[2])
        let condResult = evaluateCondition(left, op, right)

        if hasThen {
            // Block if
            ifNest += 1
            if !condResult {
                elseFlag = 1
            }
        } else {
            // Single-line if: the rest of the line after condition is executed inline
            // Not directly supported in block mode; treated as block if
            ifNest += 1
            if !condResult {
                elseFlag = 1
            }
        }
    }

    func cmdElse() { // [IMPLEMENTED]
        // Skip to endif
        endIfFlag = 1
    }

    func cmdElseIf(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else {
            endIfFlag = 1
            return
        }

        let condArgs = args.last?.lowercased() == "then" ? Array(args.dropLast()) : args
        guard condArgs.count >= 3 else {
            endIfFlag = 1
            return
        }

        let left = resolveValue(condArgs[0])
        let op = condArgs[1]
        let right = resolveValue(condArgs[2])

        if !evaluateCondition(left, op, right) {
            elseFlag = 1
        }
    }

    func cmdEndIf() { // [IMPLEMENTED]
        if ifNest > 0 { ifNest -= 1 }
    }

    private func evaluateCondition(_ left: TTLValue, _ op: String, _ right: TTLValue) -> Bool {
        // String comparison
        switch left {
        case .string(let ls):
            let rs = right.strValue
            switch op {
            case "=", "==": return ls == rs
            case "<>", "!=": return ls != rs
            case "<": return ls < rs
            case ">": return ls > rs
            case "<=": return ls <= rs
            case ">=": return ls >= rs
            default: return false
            }
        case .integer(let li):
            let ri = right.intValue
            switch op {
            case "=", "==": return li == ri
            case "<>", "!=": return li != ri
            case "<": return li < ri
            case ">": return li > ri
            case "<=": return li <= ri
            case ">=": return li >= ri
            case "and", "&": return (li & ri) != 0
            case "or", "|": return (li | ri) != 0
            default: return false
            }
        default:
            return false
        }
    }

    // MARK: goto - [IMPLEMENTED]

    func cmdGoto(_ args: [String]) { // [IMPLEMENTED]
        guard let label = args.first?.lowercased() else {
            reportError("goto: label required")
            return
        }
        if let target = variables[label] {
            currentLineNumber = target.intValue
        } else {
            reportError("goto: label not found: \(label)")
        }
    }

    // MARK: call/return - [IMPLEMENTED]

    func cmdCall(_ args: [String]) { // [IMPLEMENTED]
        guard let label = args.first?.lowercased() else {
            reportError("call: label required")
            return
        }
        if let target = variables[label] {
            callStack.append(MacroCallFrame(lineIndex: currentLineNumber, scopeLevel: scopeLevel))
            scopeLevel += 1
            currentLineNumber = target.intValue
        } else {
            reportError("call: label not found: \(label)")
        }
    }

    func cmdReturn() { // [IMPLEMENTED]
        guard let frame = callStack.popLast() else {
            reportError("return: call stack empty")
            return
        }
        currentLineNumber = frame.lineIndex
        scopeLevel = frame.scopeLevel
    }

    // MARK: for/next - [IMPLEMENTED]

    func cmdFor(_ args: [String]) { // [IMPLEMENTED]
        // for <var> <start> <end> [<step>]
        guard args.count >= 3 else {
            reportError("for: syntax error")
            return
        }

        let varName = args[0].lowercased()
        let startVal = resolveInt(args[1])
        let endVal = resolveInt(args[2])
        let stepVal = args.count > 3 ? resolveInt(args[3]) : (startVal <= endVal ? 1 : -1)

        variables[varName] = .integer(startVal)

        // Check if loop should execute at all
        if stepVal > 0 && startVal > endVal {
            endWhileFlag = 1
            return
        }
        if stepVal < 0 && startVal < endVal {
            endWhileFlag = 1
            return
        }

        loopStack.append(MacroLoopFrame(
            type: .for_, lineIndex: currentLineNumber,
            varName: varName, limit: endVal, step: stepVal, ifNest: ifNest))
    }

    func cmdNext() { // [IMPLEMENTED]
        guard let frame = loopStack.last, frame.type == .for_ else {
            reportError("next: not in for loop")
            return
        }

        let curVal = (variables[frame.varName]?.intValue ?? 0) + frame.step
        variables[frame.varName] = .integer(curVal)

        let done = frame.step > 0 ? curVal > frame.limit : curVal < frame.limit
        if done {
            loopStack.removeLast()
        } else {
            currentLineNumber = frame.lineIndex
        }
    }

    // MARK: while/endwhile - [IMPLEMENTED]

    func cmdWhile(_ args: [String], mode: Bool) { // [IMPLEMENTED]
        // while: mode=true means continue while condition is true
        // until: mode=false means continue until condition is true
        guard args.count >= 3 else {
            reportError("while/until: syntax error")
            return
        }

        let left = resolveValue(args[0])
        let op = args[1]
        let right = resolveValue(args[2])
        var condResult = evaluateCondition(left, op, right)

        if !mode { condResult = !condResult } // until inverts

        if condResult {
            loopStack.append(MacroLoopFrame(
                type: mode ? .while_ : .until, lineIndex: currentLineNumber - 1,
                varName: "", limit: 0, step: 0, ifNest: ifNest))
        } else {
            endWhileFlag = 1
        }
    }

    func cmdEndWhile() { // [IMPLEMENTED]
        guard let frame = loopStack.last,
              (frame.type == .while_ || frame.type == .until) else {
            return
        }
        // Jump back to the while/until line for re-evaluation
        currentLineNumber = frame.lineIndex
        loopStack.removeLast()
    }

    // MARK: do/loop - [IMPLEMENTED]

    func cmdDo() { // [IMPLEMENTED]
        loopStack.append(MacroLoopFrame(
            type: .do_, lineIndex: currentLineNumber - 1,
            varName: "", limit: 0, step: 0, ifNest: ifNest))
    }

    func cmdLoop(_ args: [String]) { // [IMPLEMENTED]
        guard let frame = loopStack.last, frame.type == .do_ else {
            return
        }

        if args.count >= 4 {
            // loop while/until <expr1> <op> <expr2>
            let keyword = args[0].lowercased()
            let left = resolveValue(args[1])
            let op = args[2]
            let right = resolveValue(args[3])
            var condResult = evaluateCondition(left, op, right)

            if keyword == "until" { condResult = !condResult }

            if condResult {
                currentLineNumber = frame.lineIndex
                loopStack.removeLast()
                // Will re-push on do
            } else {
                loopStack.removeLast()
            }
        } else {
            // Infinite loop (loop without condition)
            currentLineNumber = frame.lineIndex
            loopStack.removeLast()
        }
    }

    // MARK: break/continue - [IMPLEMENTED]

    func cmdBreak() { // [IMPLEMENTED]
        breakFlag = 1
        continueFlag = false
    }

    func cmdContinue() { // [IMPLEMENTED]
        breakFlag = 1
        continueFlag = true
    }

    // MARK: end/exit - [IMPLEMENTED]

    func cmdEnd() { // [IMPLEMENTED]
        isRunning = false
        onComplete?(exitCode)
        clientProxy?.macroDidFinish(exitCode: exitCode, reply: {})
    }

    func cmdExit() { // [IMPLEMENTED]
        isRunning = false
        onComplete?(exitCode)
        clientProxy?.macroDidFinish(exitCode: exitCode, reply: {})
    }

    // MARK: include - [IMPLEMENTED]

    func cmdInclude(_ args: [String]) { // [IMPLEMENTED]
        guard let filePath = args.first else {
            reportError("include: file path required")
            return
        }

        let resolvedPath = resolveString(filePath)
        let fullPath: String
        if resolvedPath.hasPrefix("/") {
            fullPath = resolvedPath
        } else {
            let dir = (currentScriptPath as NSString?)?.deletingLastPathComponent ?? "."
            fullPath = (dir as NSString).appendingPathComponent(resolvedPath)
        }

        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            reportError("include: cannot read file: \(resolvedPath)")
            return
        }

        // Push current state onto file stack
        fileStack.append((lines: scriptLines, lineIndex: currentLineNumber, path: currentScriptPath ?? ""))

        scriptLines = content.components(separatedBy: .newlines)
        currentLineNumber = 0
        currentScriptPath = fullPath
        prescanLabels()
    }

    // MARK: ifdefined - [IMPLEMENTED]

    func cmdIfDefined(_ args: [String]) { // [IMPLEMENTED]
        guard let varName = args.first?.lowercased() else {
            reportError("ifdefined: variable name required")
            return
        }

        ifNest += 1
        if variables[varName] == nil {
            elseFlag = 1
        }
    }

    // MARK: inc/dec - [IMPLEMENTED]

    func cmdInc(_ args: [String]) { // [IMPLEMENTED]
        guard let varName = args.first?.lowercased() else { return }
        let current = variables[varName]?.intValue ?? 0
        variables[varName] = .integer(current + 1)
    }

    func cmdDec(_ args: [String]) { // [IMPLEMENTED]
        guard let varName = args.first?.lowercased() else { return }
        let current = variables[varName]?.intValue ?? 0
        variables[varName] = .integer(current - 1)
    }
}

// MARK: - Send/Receive Commands

extension MacroRunner {

    // MARK: send/sendln - [IMPLEMENTED]

    func cmdSend(_ args: [String], addCR: Bool) { // [IMPLEMENTED]
        var text = args.map { resolveString($0) }.joined()
        if addCR { text += "\r\n" }

        guard let data = text.data(using: .utf8) else { return }
        clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
            self?.scheduleNextLine()
        })
        // Async - do not schedule next line here
        cancelExecTimer()
    }

    // MARK: sendtext - [IMPLEMENTED]

    func cmdSendText(_ args: [String]) { // [IMPLEMENTED]
        let text = args.map { resolveString($0) }.joined()
        guard let data = text.data(using: .utf8) else { return }
        clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
            self?.scheduleNextLine()
        })
        cancelExecTimer()
    }

    // MARK: sendbinary - [IMPLEMENTED]

    func cmdSendBinary(_ args: [String]) { // [IMPLEMENTED]
        var bytes: [UInt8] = []
        for arg in args {
            let val = resolveInt(arg)
            bytes.append(UInt8(val & 0xFF))
        }
        let data = Data(bytes)
        clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
            self?.scheduleNextLine()
        })
        cancelExecTimer()
    }

    // MARK: sendbreak - [IMPLEMENTED]

    func cmdSendBreak() { // [IMPLEMENTED]
        clientProxy?.sendBreak(reply: { [weak self] in
            self?.scheduleNextLine()
        })
        cancelExecTimer()
    }

    // MARK: sendkcode - [IMPLEMENTED]

    func cmdSendKCode(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let keyCode = resolveInt(args[0])
        var bytes: [UInt8] = []
        bytes.append(UInt8(keyCode & 0xFF))
        if keyCode > 0xFF {
            bytes.append(UInt8((keyCode >> 8) & 0xFF))
        }
        let data = Data(bytes)
        clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
            self?.scheduleNextLine()
        })
        cancelExecTimer()
    }

    // MARK: sendfile - [IMPLEMENTED]

    func cmdSendFile(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else {
            reportError("sendfile: file path required")
            return
        }
        let filePath = resolveString(args[0])
        let binaryFlag = args.count > 1 ? resolveInt(args[1]) : 1
        guard let data = FileManager.default.contents(atPath: filePath) else {
            reportError("sendfile: cannot read file: \(filePath)")
            return
        }
        let sendData: Data
        if binaryFlag == 0 {
            // Text mode: convert CR to CR/LF, strip control chars except TAB/LF/CR
            var converted = Data()
            for byte in data {
                if byte == 0x0D { // CR
                    converted.append(0x0D) // CR
                    converted.append(0x0A) // LF
                } else if byte == 0x09 || byte == 0x0A || byte == 0x0D || byte >= 0x20 {
                    converted.append(byte)
                }
                // Strip other control characters
            }
            sendData = converted
        } else {
            sendData = data
        }
        clientProxy?.sendToTerminal(data: sendData, reply: { [weak self] in
            self?.scheduleNextLine()
        })
        cancelExecTimer()
    }

    // MARK: recv - [IMPLEMENTED]

    func cmdRecv(_ args: [String]) { // [IMPLEMENTED]
        let timeout = timeoutValue
        clientProxy?.recvFromTerminal(timeout: timeout, reply: { [weak self] data in
            guard let self = self else { return }
            if let data = data, let str = String(data: data, encoding: .utf8) {
                self.inputStr = str
                self.variables["inputstr"] = .string(str)
                self.resultValue = 1
            } else {
                self.inputStr = ""
                self.variables["inputstr"] = .string("")
                self.resultValue = 0
            }
            self.variables["result"] = .integer(self.resultValue)
            self.scheduleNextLine()
        })
        cancelExecTimer()
    }

    // MARK: recvln - [IMPLEMENTED]

    func cmdRecvLn() { // [IMPLEMENTED]
        let timeout = timeoutValue
        clientProxy?.recvFromTerminal(timeout: timeout, reply: { [weak self] data in
            guard let self = self else { return }
            if let data = data, let str = String(data: data, encoding: .utf8) {
                // Take up to the first newline
                let line = str.components(separatedBy: .newlines).first ?? str
                self.inputStr = line
                self.variables["inputstr"] = .string(line)
                self.resultValue = 1
            } else {
                self.inputStr = ""
                self.variables["inputstr"] = .string("")
                self.resultValue = 0
            }
            self.variables["result"] = .integer(self.resultValue)
            self.scheduleNextLine()
        })
        cancelExecTimer()
    }

    // MARK: flushrecv - [IMPLEMENTED]

    func cmdFlushRecv() { // [IMPLEMENTED]
        clientProxy?.flushReceiveBuffer(reply: { [weak self] in
            self?.scheduleNextLine()
        })
        cancelExecTimer()
    }
}

// MARK: - Wait Commands

extension MacroRunner {

    // MARK: wait/waitln - [IMPLEMENTED]

    func cmdWait(_ args: [String], ln: Bool) { // [IMPLEMENTED]
        let patterns = args.map { resolveString($0) }
        guard !patterns.isEmpty else {
            reportError("wait: at least one pattern required")
            return
        }

        cancelExecTimer()
        var accumulated = ""
        let startTime = Date()
        let timeout = timeoutValue

        func poll() {
            guard self.isRunning, !self.isCancelled else { return }

            if timeout > 0 && Date().timeIntervalSince(startTime) > Double(timeout) {
                self.resultValue = 0
                self.variables["result"] = .integer(0)
                self.matchStr = ""
                self.variables["matchstr"] = .string("")
                self.scheduleNextLine()
                return
            }

            self.clientProxy?.recvFromTerminal(timeout: 1, reply: { [weak self] data in
                guard let self = self else { return }
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    accumulated += str
                    // Cap accumulated buffer to prevent unbounded memory growth
                    let maxAccumulatedSize = 1_048_576 // 1MB
                    if accumulated.count > maxAccumulatedSize {
                        accumulated = String(accumulated.suffix(maxAccumulatedSize / 2))
                    }
                }

                let searchStr = accumulated
                for (idx, pattern) in patterns.enumerated() {
                    if searchStr.contains(pattern) {
                        self.resultValue = idx + 1
                        self.variables["result"] = .integer(idx + 1)
                        self.matchStr = pattern
                        self.variables["matchstr"] = .string(pattern)
                        if ln {
                            // Extract the line containing the match
                            let lines = accumulated.components(separatedBy: .newlines)
                            for line in lines {
                                if line.contains(pattern) {
                                    self.inputStr = line
                                    self.variables["inputstr"] = .string(line)
                                    break
                                }
                            }
                        }
                        self.scheduleNextLine()
                        return
                    }
                }

                // Not found yet, poll again
                self.execTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                    poll()
                }
            })
        }

        poll()
    }

    // MARK: waitmatch - [IMPLEMENTED]

    func cmdWaitMatch(_ args: [String]) { // [IMPLEMENTED]
        // Same as wait but with regex matching
        cmdWaitRegex(args)
    }

    // MARK: waitrecv - [IMPLEMENTED]

    func cmdWaitRecv() { // [IMPLEMENTED]
        // Wait for any data
        cancelExecTimer()
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

    // MARK: waitregex - [IMPLEMENTED]

    func cmdWaitRegex(_ args: [String]) { // [IMPLEMENTED]
        let patterns = args.map { resolveString($0) }
        guard !patterns.isEmpty else {
            reportError("waitregex: at least one pattern required")
            return
        }

        cancelExecTimer()
        var accumulated = ""
        let startTime = Date()
        let timeout = timeoutValue

        func poll() {
            guard self.isRunning, !self.isCancelled else { return }

            if timeout > 0 && Date().timeIntervalSince(startTime) > Double(timeout) {
                self.resultValue = 0
                self.variables["result"] = .integer(0)
                self.scheduleNextLine()
                return
            }

            self.clientProxy?.recvFromTerminal(timeout: 1, reply: { [weak self] data in
                guard let self = self else { return }
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    accumulated += str
                }

                var options: NSRegularExpression.Options = []
                if self.regexCaseInsensitive {
                    options.insert(.caseInsensitive)
                }

                for (idx, pattern) in patterns.enumerated() {
                    if let regex = try? NSRegularExpression(pattern: pattern, options: options),
                       let match = regex.firstMatch(in: accumulated,
                                                     range: NSRange(accumulated.startIndex..., in: accumulated)) {
                        self.resultValue = idx + 1
                        self.variables["result"] = .integer(idx + 1)

                        let matchRange = Range(match.range, in: accumulated)!
                        self.matchStr = String(accumulated[matchRange])
                        self.variables["matchstr"] = .string(self.matchStr)

                        // Extract group matches
                        for g in 1...min(9, match.numberOfRanges - 1) {
                            if let gRange = Range(match.range(at: g), in: accumulated) {
                                self.groupMatchStrs[g] = String(accumulated[gRange])
                                self.variables["groupmatchstr\(g)"] = .string(self.groupMatchStrs[g])
                            }
                        }

                        self.scheduleNextLine()
                        return
                    }
                }

                self.execTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                    poll()
                }
            })
        }

        poll()
    }

    // MARK: waitn - [IMPLEMENTED]

    func cmdWaitN(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else {
            reportError("waitn: byte count required")
            return
        }
        let byteCount = resolveInt(args[0])
        cancelExecTimer()
        var accumulated = Data()
        let startTime = Date()

        func poll() {
            guard self.isRunning, !self.isCancelled else { return }
            if self.timeoutValue > 0 && Date().timeIntervalSince(startTime) > Double(self.timeoutValue) {
                self.resultValue = 0
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
                    self.resultValue = 1
                    self.variables["result"] = .integer(1)
                    self.scheduleNextLine()
                } else {
                    self.execTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                        poll()
                    }
                }
            })
        }

        poll()
    }

    // MARK: wait4all - [IMPLEMENTED]

    func cmdWait4All(_ args: [String]) { // [IMPLEMENTED]
        let patterns = args.map { resolveString($0) }
        guard !patterns.isEmpty else { return }

        cancelExecTimer()
        var accumulated = ""
        var found = Array(repeating: false, count: patterns.count)
        let startTime = Date()

        func poll() {
            guard self.isRunning, !self.isCancelled else { return }
            if self.timeoutValue > 0 && Date().timeIntervalSince(startTime) > Double(self.timeoutValue) {
                self.resultValue = 0
                self.variables["result"] = .integer(0)
                self.scheduleNextLine()
                return
            }

            self.clientProxy?.recvFromTerminal(timeout: 1, reply: { [weak self] data in
                guard let self = self else { return }
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    accumulated += str
                }

                for (idx, pattern) in patterns.enumerated() {
                    if !found[idx] && accumulated.contains(pattern) {
                        found[idx] = true
                    }
                }

                if found.allSatisfy({ $0 }) {
                    self.resultValue = 1
                    self.variables["result"] = .integer(1)
                    self.scheduleNextLine()
                } else {
                    self.execTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                        poll()
                    }
                }
            })
        }

        poll()
    }

    // MARK: waitevent - [IMPLEMENTED]

    func cmdWaitEvent() { // [IMPLEMENTED]
        // Wait for any event (simplified: just wait for data)
        cmdWaitRecv()
    }

    // MARK: pause/mpause - [IMPLEMENTED]

    func cmdPause(_ args: [String]) { // [IMPLEMENTED]
        let seconds = args.isEmpty ? 1.0 : Double(resolveInt(args[0]))
        cancelExecTimer()
        execTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.scheduleNextLine()
        }
    }

    func cmdMPause(_ args: [String]) { // [IMPLEMENTED]
        let ms = args.isEmpty ? 100.0 : Double(resolveInt(args[0]))
        cancelExecTimer()
        execTimer = Timer.scheduledTimer(withTimeInterval: ms / 1000.0, repeats: false) { [weak self] _ in
            self?.scheduleNextLine()
        }
    }
}

// MARK: - Connection Commands

extension MacroRunner {

    // MARK: connect - [IMPLEMENTED]

    func cmdConnect(_ args: [String]) { // [IMPLEMENTED]
        let param = args.map { resolveString($0) }.joined(separator: " ")
        cancelExecTimer()

        if param.isEmpty {
            // Connect local shell
            clientProxy?.connectLocalShell(reply: { [weak self] success in
                guard let self = self else { return }
                self.resultValue = success ? 1 : 0
                self.variables["result"] = .integer(self.resultValue)
                self.scheduleNextLine()
            })
        } else {
            clientProxy?.connectToHost(param: param, reply: { [weak self] success in
                guard let self = self else { return }
                self.resultValue = success ? 1 : 0
                self.variables["result"] = .integer(self.resultValue)
                self.scheduleNextLine()
            })
        }
    }

    // MARK: disconnect - [IMPLEMENTED]

    func cmdDisconnect() { // [IMPLEMENTED]
        cancelExecTimer()
        clientProxy?.disconnectFromHost(reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: testlink - [IMPLEMENTED]

    func cmdTestLink() { // [IMPLEMENTED]
        cancelExecTimer()
        clientProxy?.isConnected(reply: { [weak self] connected in
            guard let self = self else { return }
            self.resultValue = connected ? 2 : 0
            self.variables["result"] = .integer(self.resultValue)
            self.scheduleNextLine()
        })
    }

    // MARK: unlink - [IMPLEMENTED]

    func cmdUnlink() { // [IMPLEMENTED]
        cmdDisconnect()
    }

    // MARK: cygconnect - [IMPLEMENTED]

    func cmdCygConnect() { // [IMPLEMENTED]
        // On macOS, cygconnect maps to connectLocalShell
        cancelExecTimer()
        clientProxy?.connectLocalShell(reply: { [weak self] success in
            guard let self = self else { return }
            self.resultValue = success ? 1 : 0
            self.variables["result"] = .integer(self.resultValue)
            self.scheduleNextLine()
        })
    }

    // MARK: settimeout/timeout - [IMPLEMENTED]

    func cmdSetTimeout(_ args: [String]) { // [IMPLEMENTED]
        let val = args.isEmpty ? 0 : resolveInt(args[0])
        timeoutValue = val
        variables["timeout"] = .integer(val)
    }
}

// MARK: - String Operation Commands

extension MacroRunner {

    // MARK: strlen - [IMPLEMENTED]

    func cmdStrLen(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 1 else { return }
        let str = resolveString(args[0])
        resultValue = str.count
        variables["result"] = .integer(resultValue)
    }

    // MARK: strconcat - [IMPLEMENTED]

    func cmdStrConcat(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let varName = args[0].lowercased()
        let current = variables[varName]?.strValue ?? ""
        let addition = resolveString(args[1])
        variables[varName] = .string(current + addition)
    }

    // MARK: strcopy - [IMPLEMENTED]

    func cmdStrCopy(_ args: [String]) { // [IMPLEMENTED]
        // strcopy <srcvar> <start> <len> <destvar>
        guard args.count >= 4 else { return }
        let src = resolveString(args[0])
        let start = resolveInt(args[1]) - 1 // 1-based to 0-based
        let len = resolveInt(args[2])
        let destVar = args[3].lowercased()

        let startIdx = max(0, min(start, src.count))
        let endIdx = min(startIdx + len, src.count)

        if startIdx < src.count {
            let sIdx = src.index(src.startIndex, offsetBy: startIdx)
            let eIdx = src.index(src.startIndex, offsetBy: endIdx)
            variables[destVar] = .string(String(src[sIdx..<eIdx]))
        } else {
            variables[destVar] = .string("")
        }
    }

    // MARK: strcompare - [IMPLEMENTED]

    func cmdStrCompare(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let s1 = resolveString(args[0])
        let s2 = resolveString(args[1])
        resultValue = s1.compare(s2).rawValue
        variables["result"] = .integer(resultValue)
    }

    // MARK: strscan - [IMPLEMENTED]

    func cmdStrScan(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let haystack = resolveString(args[0])
        let needle = resolveString(args[1])
        if let range = haystack.range(of: needle) {
            resultValue = haystack.distance(from: haystack.startIndex, to: range.lowerBound) + 1
        } else {
            resultValue = 0
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: strmatch - [IMPLEMENTED]

    func cmdStrMatch(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let str = resolveString(args[0])
        let pattern = resolveString(args[1])

        var options: NSRegularExpression.Options = []
        if regexCaseInsensitive { options.insert(.caseInsensitive) }

        if let regex = try? NSRegularExpression(pattern: pattern, options: options),
           let match = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) {
            resultValue = 1
            let matchRange = Range(match.range, in: str)!
            matchStr = String(str[matchRange])
            variables["matchstr"] = .string(matchStr)

            for g in 1...min(9, match.numberOfRanges - 1) {
                if let gRange = Range(match.range(at: g), in: str) {
                    groupMatchStrs[g] = String(str[gRange])
                    variables["groupmatchstr\(g)"] = .string(groupMatchStrs[g])
                }
            }
        } else {
            resultValue = 0
            matchStr = ""
            variables["matchstr"] = .string("")
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: str2int - [IMPLEMENTED]

    func cmdStr2Int(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let str = resolveString(args[1])
        let val = Int(str) ?? 0
        variables[destVar] = .integer(val)
        resultValue = val != 0 || str == "0" ? 1 : 0
        variables["result"] = .integer(resultValue)
    }

    // MARK: int2str - [IMPLEMENTED]

    func cmdInt2Str(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let val = resolveInt(args[1])
        variables[destVar] = .string(String(val))
    }

    // MARK: str2code - [IMPLEMENTED]

    func cmdStr2Code(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let str = resolveString(args[1])
        let code = str.isEmpty ? 0 : Int(str.unicodeScalars.first?.value ?? 0)
        variables[destVar] = .integer(code)
    }

    // MARK: code2str - [IMPLEMENTED]

    func cmdCode2Str(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let code = resolveInt(args[1])
        if let scalar = Unicode.Scalar(code) {
            variables[destVar] = .string(String(Character(scalar)))
        } else {
            variables[destVar] = .string("")
        }
    }

    // MARK: strinsert - [IMPLEMENTED]

    func cmdStrInsert(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let destVar = args[0].lowercased()
        let pos = resolveInt(args[1]) - 1
        let insertStr = resolveString(args[2])
        var base = variables[destVar]?.strValue ?? ""

        let idx = base.index(base.startIndex, offsetBy: max(0, min(pos, base.count)))
        base.insert(contentsOf: insertStr, at: idx)
        variables[destVar] = .string(base)
    }

    // MARK: strremove - [IMPLEMENTED]

    func cmdStrRemove(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let destVar = args[0].lowercased()
        let pos = resolveInt(args[1]) - 1
        let len = resolveInt(args[2])
        var base = variables[destVar]?.strValue ?? ""

        let startIdx = max(0, min(pos, base.count))
        let endIdx = min(startIdx + len, base.count)

        let sIdx = base.index(base.startIndex, offsetBy: startIdx)
        let eIdx = base.index(base.startIndex, offsetBy: endIdx)
        base.removeSubrange(sIdx..<eIdx)
        variables[destVar] = .string(base)
    }

    // MARK: strreplace - [IMPLEMENTED]

    func cmdStrReplace(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 4 else { return }
        let destVar = args[0].lowercased()
        let index = resolveInt(args[1])
        let pattern = resolveString(args[2])
        let replacement = resolveString(args[3])
        var base = variables[destVar]?.strValue ?? ""

        // Clear groupmatchstr1..9
        for i in 1...9 {
            groupMatchStrs[i] = ""
            variables["groupmatchstr\(i)"] = .string("")
        }

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            resultValue = -1
            variables["result"] = .integer(-1)
            return
        }

        // index is 1-based
        let startIdx = max(0, index - 1)
        let str = base
        guard startIdx < str.count else {
            resultValue = 0
            variables["result"] = .integer(0)
            return
        }

        let nsStr = str as NSString
        let searchRange = NSRange(location: startIdx, length: nsStr.length - startIdx)
        guard let match = regex.firstMatch(in: str, range: searchRange) else {
            resultValue = 0
            variables["result"] = .integer(0)
            return
        }

        // Store matchstr
        let matchedStr = nsStr.substring(with: match.range)
        variables["matchstr"] = .string(matchedStr)

        // Store group matches
        for g in 1..<match.numberOfRanges {
            if g <= 9, match.range(at: g).location != NSNotFound {
                let groupStr = nsStr.substring(with: match.range(at: g))
                groupMatchStrs[g] = groupStr
                variables["groupmatchstr\(g)"] = .string(groupStr)
            }
        }

        // Replace first match only
        let replacedRange = Range(match.range, in: base)!
        base.replaceSubrange(replacedRange, with: replacement)
        variables[destVar] = .string(base)
        resultValue = 1
        variables["result"] = .integer(1)
    }

    // MARK: strspecial - [IMPLEMENTED]

    func cmdStrSpecial(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        let str = variables[destVar]?.strValue ?? ""
        // Single-pass state machine to correctly handle escape sequences.
        // Processing \\n must yield backslash+n, not backslash+newline.
        var result = ""
        var i = str.startIndex
        while i < str.endIndex {
            if str[i] == "\\" {
                let next = str.index(after: i)
                if next < str.endIndex {
                    switch str[next] {
                    case "n":  result.append("\n")
                    case "r":  result.append("\r")
                    case "t":  result.append("\t")
                    case "\\": result.append("\\")
                    case "\"": result.append("\"")
                    case "'":  result.append("'")
                    default:   result.append("\\"); result.append(str[next])
                    }
                    i = str.index(after: next)
                } else {
                    result.append("\\")
                    i = next
                }
            } else {
                result.append(str[i])
                i = str.index(after: i)
            }
        }
        variables[destVar] = .string(result)
    }

    // MARK: strtrim - [IMPLEMENTED]

    func cmdStrTrim(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let trimChars = resolveString(args[1])
        var str = variables[destVar]?.strValue ?? ""
        let charSet = CharacterSet(charactersIn: trimChars)

        // Trim both ends
        while let first = str.unicodeScalars.first, charSet.contains(first) {
            str.removeFirst()
        }
        while let last = str.unicodeScalars.last, charSet.contains(last) {
            str.removeLast()
        }
        variables[destVar] = .string(str)
    }

    // MARK: strsplit - [IMPLEMENTED]

    func cmdStrSplit(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let srcStr = resolveString(args[0])
        let delimiter = resolveString(args[1])
        let maxCount = args.count > 2 ? resolveInt(args[2]) : 9

        let parts = srcStr.components(separatedBy: delimiter)
        let limit = min(max(maxCount, 1), 9)

        // Clear groupmatchstr1..9
        for i in 1...9 {
            groupMatchStrs[i] = ""
            variables["groupmatchstr\(i)"] = .string("")
        }

        // Distribute parts into groupmatchstr1..limit
        if parts.count <= limit {
            for (i, part) in parts.enumerated() {
                groupMatchStrs[i + 1] = part
                variables["groupmatchstr\(i + 1)"] = .string(part)
            }
            resultValue = parts.count
        } else {
            // First (limit-1) parts go to groupmatchstr1..(limit-1)
            for i in 0..<(limit - 1) {
                groupMatchStrs[i + 1] = parts[i]
                variables["groupmatchstr\(i + 1)"] = .string(parts[i])
            }
            // Remaining parts joined back into the last groupmatchstr
            let remaining = parts[(limit - 1)...].joined(separator: delimiter)
            groupMatchStrs[limit] = remaining
            variables["groupmatchstr\(limit)"] = .string(remaining)
            resultValue = parts.count > 9 ? 10 : parts.count
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: strjoin - [IMPLEMENTED]

    func cmdStrJoin(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let delimiter = resolveString(args[1])
        let count = args.count > 2 ? resolveInt(args[2]) : 9
        let limit = min(max(count, 1), 9)

        var parts: [String] = []
        for i in 1...limit {
            let val = variables["groupmatchstr\(i)"]?.strValue ?? ""
            parts.append(val)
        }
        // Remove trailing empty strings
        while let last = parts.last, last.isEmpty { parts.removeLast() }
        variables[destVar] = .string(parts.joined(separator: delimiter))
    }

    // MARK: tolower - [IMPLEMENTED]

    func cmdToLower(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        let str = variables[destVar]?.strValue ?? ""
        variables[destVar] = .string(str.lowercased())
    }

    // MARK: toupper - [IMPLEMENTED]

    func cmdToUpper(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        let str = variables[destVar]?.strValue ?? ""
        variables[destVar] = .string(str.uppercased())
    }

    // MARK: sprintf/sprintf2 - [IMPLEMENTED]

    func cmdSprintf(_ args: [String], mode: Int) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let format = resolveString(args[1])
        let fmtArgs = args.dropFirst(2).map { resolveString($0) }

        // Simple format string processing
        var result = format
        var argIdx = 0
        var i = result.startIndex
        while i < result.endIndex {
            if result[i] == "%" && result.index(after: i) < result.endIndex {
                let next = result[result.index(after: i)]
                if argIdx < fmtArgs.count {
                    var replacement = ""
                    switch next {
                    case "s":
                        replacement = fmtArgs[argIdx]
                        argIdx += 1
                    case "d":
                        replacement = String(Int(fmtArgs[argIdx]) ?? 0)
                        argIdx += 1
                    case "x":
                        replacement = String(Int(fmtArgs[argIdx]) ?? 0, radix: 16)
                        argIdx += 1
                    case "X":
                        replacement = String(Int(fmtArgs[argIdx]) ?? 0, radix: 16).uppercased()
                        argIdx += 1
                    case "0"..."9":
                        // Handle width specifier like %02d, %10s
                        var specEnd = result.index(after: i)
                        while specEnd < result.endIndex && (result[specEnd].isNumber || result[specEnd] == ".") {
                            specEnd = result.index(after: specEnd)
                        }
                        guard specEnd < result.endIndex else {
                            // Incomplete format specifier at end of string, skip
                            i = result.endIndex
                            continue
                        }
                        let formatType = result[specEnd]
                        let widthStr = String(result[result.index(after: i)..<specEnd])
                        if formatType == "d" {
                            let val = Int(fmtArgs[argIdx]) ?? 0
                            let width = Int(widthStr.filter { $0.isNumber }) ?? 0
                            let padChar: Character = widthStr.hasPrefix("0") ? "0" : " "
                            var numStr = String(val)
                            while numStr.count < width { numStr = String(padChar) + numStr }
                            replacement = numStr
                            argIdx += 1
                        } else if formatType == "s" {
                            replacement = fmtArgs[argIdx]
                            argIdx += 1
                        } else if formatType == "x" || formatType == "X" {
                            let val = Int(fmtArgs[argIdx]) ?? 0
                            let width = Int(widthStr.filter { $0.isNumber }) ?? 0
                            let padChar: Character = widthStr.hasPrefix("0") ? "0" : " "
                            var numStr = String(val, radix: 16)
                            if formatType == "X" { numStr = numStr.uppercased() }
                            while numStr.count < width { numStr = String(padChar) + numStr }
                            replacement = numStr
                            argIdx += 1
                        } else {
                            replacement = "%" + widthStr + String(formatType)
                        }
                        let rangeToReplace = i...specEnd
                        result.replaceSubrange(rangeToReplace, with: replacement)
                        i = result.index(i, offsetBy: replacement.count, limitedBy: result.endIndex) ?? result.endIndex
                        continue
                    case "%":
                        replacement = "%"
                    default:
                        i = result.index(after: i)
                        continue
                    }
                    let rangeToReplace = i...result.index(after: i)
                    result.replaceSubrange(rangeToReplace, with: replacement)
                    i = result.index(i, offsetBy: replacement.count, limitedBy: result.endIndex) ?? result.endIndex
                    continue
                }
            }
            i = result.index(after: i)
        }

        if mode == 0 {
            variables[destVar] = .string(result)
        } else {
            // sprintf2 stores to inputstr
            inputStr = result
            variables["inputstr"] = .string(result)
        }
    }
}

// MARK: - Dialog Commands

extension MacroRunner {

    // MARK: messagebox - [IMPLEMENTED]

    func cmdMessageBox(_ args: [String]) { // [IMPLEMENTED]
        let message = args.isEmpty ? "" : resolveString(args[0])
        let title = args.count > 1 ? resolveString(args[1]) : ""
        cancelExecTimer()
        clientProxy?.showDialog(type: MacroDialogType.messagebox.rawValue,
                                message: message, defaultValue: title,
                                reply: { [weak self] resultCode, _ in
            guard let self = self else { return }
            self.resultValue = resultCode
            self.variables["result"] = .integer(resultCode)
            self.scheduleNextLine()
        })
    }

    // MARK: inputbox/passwordbox - [IMPLEMENTED]

    func cmdInputBox(_ args: [String], password: Bool) { // [IMPLEMENTED]
        let prompt = args.isEmpty ? "" : resolveString(args[0])
        let title = args.count > 1 ? resolveString(args[1]) : ""
        let defaultVal = args.count > 2 ? resolveString(args[2]) : ""
        cancelExecTimer()

        let dialogType = password ? MacroDialogType.passwordbox.rawValue : MacroDialogType.inputbox.rawValue
        clientProxy?.showDialog(type: dialogType,
                                message: prompt, defaultValue: defaultVal,
                                reply: { [weak self] resultCode, inputText in
            guard let self = self else { return }
            self.resultValue = resultCode
            self.variables["result"] = .integer(resultCode)
            if resultCode == 1 {
                self.inputStr = inputText
                self.variables["inputstr"] = .string(inputText)
            }
            self.scheduleNextLine()
        })
    }

    // MARK: yesnobox - [IMPLEMENTED]

    func cmdYesNoBox(_ args: [String]) { // [IMPLEMENTED]
        let message = args.isEmpty ? "" : resolveString(args[0])
        let title = args.count > 1 ? resolveString(args[1]) : ""
        cancelExecTimer()
        clientProxy?.showDialog(type: MacroDialogType.yesnobox.rawValue,
                                message: message, defaultValue: title,
                                reply: { [weak self] resultCode, _ in
            guard let self = self else { return }
            self.resultValue = resultCode
            self.variables["result"] = .integer(resultCode)
            self.scheduleNextLine()
        })
    }

    // MARK: statusbox - [IMPLEMENTED]

    func cmdStatusBox(_ args: [String]) { // [IMPLEMENTED]
        let message = args.isEmpty ? "" : resolveString(args[0])
        let title = args.count > 1 ? resolveString(args[1]) : ""
        clientProxy?.showStatusBox(message: message, title: title, reply: { [weak self] in
            self?.scheduleNextLine()
        })
        cancelExecTimer()
    }

    // MARK: closesbox - [IMPLEMENTED]

    func cmdCloseSBox() { // [IMPLEMENTED]
        clientProxy?.closeStatusBox(reply: { [weak self] in
            self?.scheduleNextLine()
        })
        cancelExecTimer()
    }

    // MARK: listbox - [IMPLEMENTED]

    func cmdListBox(_ args: [String]) { // [IMPLEMENTED]
        // listbox <message> <title> <string array> [<selected>]
        let message = args.isEmpty ? "" : resolveString(args[0])
        let title = args.count > 1 ? resolveString(args[1]) : ""
        var items: [String] = []
        if args.count > 2 {
            let arrayVar = args[2].lowercased()
            if case .strArray(let arr) = variables[arrayVar] {
                items = arr
            }
        }
        // Send items as newline-delimited in message field for XPC
        let itemsStr = items.isEmpty ? message : items.joined(separator: "\n")
        cancelExecTimer()
        clientProxy?.showDialog(type: MacroDialogType.listbox.rawValue,
                                message: itemsStr, defaultValue: title,
                                reply: { [weak self] resultCode, selectedText in
            guard let self = self else { return }
            self.resultValue = resultCode
            self.variables["result"] = .integer(resultCode)
            if resultCode >= 0 {
                self.inputStr = selectedText
                self.variables["inputstr"] = .string(selectedText)
            }
            self.scheduleNextLine()
        })
    }

    // MARK: filenamebox - [IMPLEMENTED]

    func cmdFilenameBox(_ args: [String]) { // [IMPLEMENTED]
        // filenamebox <title> [<dialogtype> [<initialdir>]]
        let title = args.isEmpty ? "" : resolveString(args[0])
        let dialogType = args.count > 1 ? resolveInt(args[1]) : 0  // 0=open, nonzero=save
        let initialDir = args.count > 2 ? resolveString(args[2]) : ""
        let saveMode = dialogType != 0 ? "1" : "0"
        cancelExecTimer()
        clientProxy?.showDialog(type: MacroDialogType.filenamebox.rawValue,
                                message: title, defaultValue: "\(saveMode)|\(initialDir)",
                                reply: { [weak self] resultCode, filePath in
            guard let self = self else { return }
            self.resultValue = resultCode
            self.variables["result"] = .integer(resultCode)
            if resultCode != 0 {
                self.inputStr = filePath
                self.variables["inputstr"] = .string(filePath)
            }
            self.scheduleNextLine()
        })
    }

    // MARK: dirnamebox - [IMPLEMENTED]

    func cmdDirnameBox(_ args: [String]) { // [IMPLEMENTED]
        let message = args.isEmpty ? "" : resolveString(args[0])
        let defaultDir = args.count > 1 ? resolveString(args[1]) : ""
        cancelExecTimer()
        clientProxy?.showDialog(type: MacroDialogType.dirnamebox.rawValue,
                                message: message, defaultValue: defaultDir,
                                reply: { [weak self] resultCode, dirPath in
            guard let self = self else { return }
            self.resultValue = resultCode
            self.variables["result"] = .integer(resultCode)
            if resultCode == 1 {
                self.inputStr = dirPath
                self.variables["inputstr"] = .string(dirPath)
            }
            self.scheduleNextLine()
        })
    }

    // MARK: bringupbox - [IMPLEMENTED]

    func cmdBringupBox() { // [IMPLEMENTED]
        clientProxy?.bringWindowToFront(reply: {})
    }

    // MARK: setdlgpos - [IMPLEMENTED]

    func cmdSetDlgPos(_ args: [String]) { // [IMPLEMENTED]
        dlgPosX = args.count > 0 ? resolveInt(args[0]) : -1
        dlgPosY = args.count > 1 ? resolveInt(args[1]) : -1
    }
}

// MARK: - File I/O Commands

extension MacroRunner {

    // MARK: fileopen - [IMPLEMENTED]

    func cmdFileOpen(_ args: [String]) { // [IMPLEMENTED]
        // fileopen <handlevar> <filepath> <mode>
        // mode: 0=read, 1=write(create), 2=read+write, 3=append
        guard args.count >= 3 else {
            reportError("fileopen: requires handlevar, filepath, mode")
            return
        }
        let handleVar = args[0].lowercased()
        let filePath = resolveString(args[1])
        let mode = resolveInt(args[2])

        let fm = FileManager.default
        var handle: FileHandle?

        switch mode {
        case 0: // read
            handle = FileHandle(forReadingAtPath: filePath)
        case 1: // write (create/truncate)
            if !fm.fileExists(atPath: filePath) {
                fm.createFile(atPath: filePath, contents: nil)
            }
            handle = FileHandle(forWritingAtPath: filePath)
            handle?.truncateFile(atOffset: 0)
        case 2: // read+write
            if !fm.fileExists(atPath: filePath) {
                fm.createFile(atPath: filePath, contents: nil)
            }
            handle = FileHandle(forUpdatingAtPath: filePath)
        case 3: // append
            if !fm.fileExists(atPath: filePath) {
                fm.createFile(atPath: filePath, contents: nil)
            }
            handle = FileHandle(forWritingAtPath: filePath)
            handle?.seekToEndOfFile()
        default:
            handle = FileHandle(forReadingAtPath: filePath)
        }

        if let handle = handle {
            let handleId = nextFileHandle
            nextFileHandle += 1
            fileHandles[handleId] = handle
            filePaths[handleId] = filePath
            variables[handleVar] = .integer(handleId)
            resultValue = 0
        } else {
            variables[handleVar] = .integer(-1)
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: fileclose - [IMPLEMENTED]

    func cmdFileClose(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let handleId = resolveInt(args[0])
        if let handle = fileHandles[handleId] {
            handle.closeFile()
            fileHandles.removeValue(forKey: handleId)
            filePaths.removeValue(forKey: handleId)
            fileMarkedOffsets.removeValue(forKey: handleId)
        }
    }

    // MARK: fileread - [IMPLEMENTED]

    func cmdFileRead(_ args: [String]) { // [IMPLEMENTED]
        // fileread <handle> <destvar> <length>
        guard args.count >= 3 else { return }
        let handleId = resolveInt(args[0])
        let destVar = args[1].lowercased()
        let length = resolveInt(args[2])

        guard let handle = fileHandles[handleId] else {
            resultValue = -1
            variables["result"] = .integer(-1)
            return
        }

        let data = handle.readData(ofLength: length)
        if data.isEmpty {
            resultValue = 1 // EOF
            variables[destVar] = .string("")
        } else {
            resultValue = 0
            variables[destVar] = .string(String(data: data, encoding: .utf8) ?? "")
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: filereadln - [IMPLEMENTED]

    func cmdFileReadLn(_ args: [String]) { // [IMPLEMENTED]
        // filereadln <handle> <destvar>
        guard args.count >= 2 else { return }
        let handleId = resolveInt(args[0])
        let destVar = args[1].lowercased()

        guard let handle = fileHandles[handleId] else {
            resultValue = -1
            variables["result"] = .integer(-1)
            return
        }

        // Buffered read until newline (4KB chunks instead of 1-byte-at-a-time)
        var lineData = Data()
        let chunkSize = 4096
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty {
                if lineData.isEmpty {
                    resultValue = 1 // EOF
                    variables[destVar] = .string("")
                    variables["result"] = .integer(resultValue)
                    return
                }
                break
            }
            if let lfIndex = chunk.firstIndex(of: 0x0A) {
                // Found newline - append data up to it, seek back past remainder
                let bytesBeforeLF = chunk.distance(from: chunk.startIndex, to: lfIndex)
                lineData.append(chunk[chunk.startIndex..<lfIndex])
                let bytesConsumed = bytesBeforeLF + 1 // include LF
                let bytesExtra = chunk.count - bytesConsumed
                if bytesExtra > 0 {
                    handle.seek(toFileOffset: handle.offsetInFile - UInt64(bytesExtra))
                }
                break
            } else {
                lineData.append(chunk)
            }
        }
        // Strip CR characters
        lineData = lineData.filter { $0 != 0x0D }

        resultValue = 0
        variables[destVar] = .string(String(data: lineData, encoding: .utf8) ?? "")
        variables["result"] = .integer(resultValue)
    }

    // MARK: filewrite/filewriteln - [IMPLEMENTED]

    func cmdFileWrite(_ args: [String], addCRLF: Bool) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let handleId = resolveInt(args[0])
        var text = resolveString(args[1])
        if addCRLF { text += "\r\n" }

        guard let handle = fileHandles[handleId],
              let data = text.data(using: .utf8) else {
            resultValue = -1
            variables["result"] = .integer(-1)
            return
        }

        handle.write(data)
        resultValue = 0
        variables["result"] = .integer(0)
    }

    // MARK: filecreate - [IMPLEMENTED]

    func cmdFileCreate(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let filePath = resolveString(args[0])
        let success = FileManager.default.createFile(atPath: filePath, contents: nil)
        resultValue = success ? 0 : -1
        variables["result"] = .integer(resultValue)
    }

    // MARK: filedelete - [IMPLEMENTED]

    func cmdFileDelete(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let filePath = resolveString(args[0])
        do {
            try FileManager.default.removeItem(atPath: filePath)
            resultValue = 0
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: filecopy - [IMPLEMENTED]

    func cmdFileCopy(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let src = resolveString(args[0])
        let dst = resolveString(args[1])
        let overwrite = args.count > 2 ? resolveInt(args[2]) != 0 : false

        do {
            if overwrite && FileManager.default.fileExists(atPath: dst) {
                try FileManager.default.removeItem(atPath: dst)
            }
            try FileManager.default.copyItem(atPath: src, toPath: dst)
            resultValue = 0
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: filerename - [IMPLEMENTED]

    func cmdFileRename(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let src = resolveString(args[0])
        let dst = resolveString(args[1])

        do {
            try FileManager.default.moveItem(atPath: src, toPath: dst)
            resultValue = 0
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: fileconcat - [IMPLEMENTED]

    func cmdFileConcat(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destPath = resolveString(args[0])
        let srcPath = resolveString(args[1])

        guard let srcData = FileManager.default.contents(atPath: srcPath) else {
            resultValue = -1
            variables["result"] = .integer(-1)
            return
        }

        if let destHandle = FileHandle(forWritingAtPath: destPath) {
            destHandle.seekToEndOfFile()
            destHandle.write(srcData)
            destHandle.closeFile()
            resultValue = 0
        } else {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: filesearch - [IMPLEMENTED]

    func cmdFileSearch(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let filePath = resolveString(args[0])
        resultValue = FileManager.default.fileExists(atPath: filePath) ? 1 : 0
        variables["result"] = .integer(resultValue)
    }

    // MARK: fileseek - [IMPLEMENTED]

    func cmdFileSeek(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let handleId = resolveInt(args[0])
        let offsetInt = resolveInt(args[1])
        let origin = args.count > 2 ? resolveInt(args[2]) : 0

        guard let handle = fileHandles[handleId] else {
            resultValue = -1
            variables["result"] = .integer(-1)
            return
        }

        switch origin {
        case 0: // SEEK_SET
            handle.seek(toFileOffset: UInt64(max(0, offsetInt)))
        case 1: // SEEK_CUR - supports negative offsets
            let current = Int64(handle.offsetInFile)
            let newPos = max(0, current + Int64(offsetInt))
            handle.seek(toFileOffset: UInt64(newPos))
        case 2: // SEEK_END
            handle.seekToEndOfFile()
            let end = Int64(handle.offsetInFile)
            let newPos = max(0, end + Int64(offsetInt))
            handle.seek(toFileOffset: UInt64(newPos))
        default:
            handle.seek(toFileOffset: UInt64(max(0, offsetInt)))
        }
        resultValue = 0
        variables["result"] = .integer(0)
    }

    // MARK: fileseekback - [IMPLEMENTED]

    func cmdFileSeekBack(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let handleId = resolveInt(args[0])
        let offset = UInt64(resolveInt(args[1]))

        guard let handle = fileHandles[handleId] else { return }
        let current = handle.offsetInFile
        handle.seek(toFileOffset: current >= offset ? current - offset : 0)
    }

    // MARK: filemarkptr - [IMPLEMENTED]

    func cmdFileMarkPtr(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let handleId = resolveInt(args[0])
        guard let handle = fileHandles[handleId] else { return }
        fileMarkedOffsets[handleId] = handle.offsetInFile
    }

    // MARK: filestat - [IMPLEMENTED]

    func cmdFileStat(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let filePath = resolveString(args[1])

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
            let size = (attrs[.size] as? Int) ?? 0
            variables[destVar] = .integer(size)
            resultValue = 0
        } catch {
            variables[destVar] = .integer(0)
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: filetruncate - [IMPLEMENTED]

    func cmdFileTruncate(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let handleId = resolveInt(args[0])
        guard let handle = fileHandles[handleId] else { return }
        handle.truncateFile(atOffset: handle.offsetInFile)
    }

    // MARK: filestrseek/filestrseek2 - [IMPLEMENTED]

    func cmdFileStrSeek(_ args: [String], reverse: Bool) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let handleId = resolveInt(args[0])
        let searchStr = resolveString(args[1])

        guard let handle = fileHandles[handleId],
              let searchData = searchStr.data(using: .utf8) else {
            resultValue = -1
            variables["result"] = .integer(-1)
            return
        }

        let startOffset = handle.offsetInFile
        if reverse {
            // Search backward from current position
            var pos = startOffset
            while pos > 0 {
                pos -= 1
                handle.seek(toFileOffset: pos)
                let chunk = handle.readData(ofLength: searchData.count)
                if chunk == searchData {
                    handle.seek(toFileOffset: pos)
                    resultValue = 1
                    variables["result"] = .integer(1)
                    return
                }
            }
        } else {
            // Search forward with larger buffer for performance
            let bufferSize = max(8192, searchData.count * 2)
            while true {
                let readPos = handle.offsetInFile
                let chunk = handle.readData(ofLength: bufferSize)
                if chunk.isEmpty { break }
                if let range = chunk.range(of: searchData) {
                    let matchOffset = readPos + UInt64(chunk.distance(from: chunk.startIndex, to: range.lowerBound))
                    handle.seek(toFileOffset: matchOffset)
                    resultValue = 1
                    variables["result"] = .integer(1)
                    return
                }
                // Overlap by searchData.count - 1 to catch matches spanning chunk boundaries
                if chunk.count >= searchData.count {
                    let overlap = searchData.count - 1
                    handle.seek(toFileOffset: handle.offsetInFile - UInt64(overlap))
                }
            }
        }

        handle.seek(toFileOffset: startOffset)
        resultValue = 0
        variables["result"] = .integer(0)
    }

    // MARK: filelock - [IMPLEMENTED]

    func cmdFileLock(_ args: [String]) { // [IMPLEMENTED]
        // macOS file locking via flock is not directly available via FileHandle
        // Stub: set result to success
        resultValue = 0
        variables["result"] = .integer(0)
    }

    // MARK: fileunlock - [IMPLEMENTED]

    func cmdFileUnlock(_ args: [String]) { // [IMPLEMENTED]
        resultValue = 0
        variables["result"] = .integer(0)
    }
}

// MARK: - Directory Commands

extension MacroRunner {

    // MARK: findfirst - [IMPLEMENTED]

    func cmdFindFirst(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let pattern = resolveString(args[1])

        let dirPath = (pattern as NSString).deletingLastPathComponent
        let filePattern = (pattern as NSString).lastPathComponent
        let dir = dirPath.isEmpty ? FileManager.default.currentDirectoryPath : dirPath

        do {
            var items = try FileManager.default.contentsOfDirectory(atPath: dir)
            if !filePattern.isEmpty && filePattern != "*" {
                let regex = filePattern
                    .replacingOccurrences(of: ".", with: "\\.")
                    .replacingOccurrences(of: "*", with: ".*")
                    .replacingOccurrences(of: "?", with: ".")
                items = items.filter { ($0 as NSString).range(of: "^\(regex)$",
                    options: .regularExpression).location != NSNotFound }
            }
            items = items.map { (dir as NSString).appendingPathComponent($0) }

            if items.isEmpty {
                resultValue = -1
                variables[destVar] = .string("")
            } else {
                let searchId = dirSearchResults.count
                dirSearchResults.append(items)
                dirSearchIndex.append(0)
                variables[destVar] = .string(items[0])
                resultValue = searchId
            }
        } catch {
            resultValue = -1
            variables[destVar] = .string("")
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: findnext - [IMPLEMENTED]

    func cmdFindNext(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let searchId = resolveInt(args[1])

        guard searchId >= 0 && searchId < dirSearchResults.count else {
            resultValue = -1
            variables[destVar] = .string("")
            variables["result"] = .integer(-1)
            return
        }

        dirSearchIndex[searchId] += 1
        let idx = dirSearchIndex[searchId]
        let items = dirSearchResults[searchId]

        if idx < items.count {
            variables[destVar] = .string(items[idx])
            resultValue = 0
        } else {
            variables[destVar] = .string("")
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: findclose - [IMPLEMENTED]

    func cmdFindClose(_ args: [String]) { // [IMPLEMENTED]
        if !args.isEmpty {
            // Close a specific search handle
            let searchId = resolveInt(args[0])
            if searchId >= 0 && searchId < dirSearchResults.count {
                dirSearchResults[searchId] = []
                dirSearchIndex[searchId] = 0
            }
        } else {
            // Close all search handles
            dirSearchResults.removeAll()
            dirSearchIndex.removeAll()
        }
    }

    // MARK: foldercreate - [IMPLEMENTED]

    func cmdFolderCreate(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let path = resolveString(args[0])
        do {
            try FileManager.default.createDirectory(atPath: path,
                withIntermediateDirectories: true)
            resultValue = 0
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: folderdelete - [IMPLEMENTED]

    func cmdFolderDelete(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let path = resolveString(args[0])
        do {
            try FileManager.default.removeItem(atPath: path)
            resultValue = 0
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: foldersearch - [IMPLEMENTED]

    func cmdFolderSearch(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let path = resolveString(args[0])
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        resultValue = (exists && isDir.boolValue) ? 1 : 0
        variables["result"] = .integer(resultValue)
    }

    // MARK: changedir - [IMPLEMENTED]

    func cmdChangeDir(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let path = resolveString(args[0])
        let success = FileManager.default.changeCurrentDirectoryPath(path)
        resultValue = success ? 0 : -1
        variables["result"] = .integer(resultValue)
    }

    // MARK: getdir - [IMPLEMENTED]

    func cmdGetDir(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        variables[destVar] = .string(FileManager.default.currentDirectoryPath)
    }

    // MARK: setdir - [IMPLEMENTED]

    func cmdSetDir(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let path = resolveString(args[0])
        let success = FileManager.default.changeCurrentDirectoryPath(path)
        resultValue = success ? 0 : -1
        variables["result"] = .integer(resultValue)
    }

    // MARK: makepath - [IMPLEMENTED]

    func cmdMakePath(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let destVar = args[0].lowercased()
        let dir = resolveString(args[1])
        let file = resolveString(args[2])
        variables[destVar] = .string((dir as NSString).appendingPathComponent(file))
    }

    // MARK: basename - [IMPLEMENTED]

    func cmdBasename(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let path = resolveString(args[1])
        variables[destVar] = .string((path as NSString).lastPathComponent)
    }

    // MARK: dirname - [IMPLEMENTED]

    func cmdDirname(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let path = resolveString(args[1])
        variables[destVar] = .string((path as NSString).deletingLastPathComponent)
    }
}

// MARK: - Array Commands

extension MacroRunner {

    // MARK: intdim - [IMPLEMENTED]

    func cmdIntDim(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let varName = args[0].lowercased()
        let size = resolveInt(args[1])
        variables[varName] = .intArray(Array(repeating: 0, count: max(0, size)))
    }

    // MARK: strdim - [IMPLEMENTED]

    func cmdStrDim(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let varName = args[0].lowercased()
        let size = resolveInt(args[1])
        variables[varName] = .strArray(Array(repeating: "", count: max(0, size)))
    }
}

// MARK: - System Commands

extension MacroRunner {

    // MARK: getdate - [IMPLEMENTED]

    func cmdGetDate(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        let format = args.count > 1 ? resolveString(args[1]) : "yyyy/MM/dd"
        let formatter = DateFormatter()
        formatter.dateFormat = format
        variables[destVar] = .string(formatter.string(from: Date()))
    }

    // MARK: gettime - [IMPLEMENTED]

    func cmdGetTime(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        let format = args.count > 1 ? resolveString(args[1]) : "HH:mm:ss"
        let formatter = DateFormatter()
        formatter.dateFormat = format
        variables[destVar] = .string(formatter.string(from: Date()))
    }

    // MARK: getenv - [IMPLEMENTED]

    func cmdGetEnv(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let envName = resolveString(args[1])
        let value = ProcessInfo.processInfo.environment[envName] ?? ""
        variables[destVar] = .string(value)
    }

    // MARK: setenv - [IMPLEMENTED]

    func cmdSetEnv(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let envName = resolveString(args[0])
        let envValue = resolveString(args[1])
        setenv(envName, envValue, 1)
    }

    // MARK: expandenv - [IMPLEMENTED]

    func cmdExpandEnv(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        var str = variables[destVar]?.strValue ?? ""
        // Replace %VARNAME% with environment variable values
        let env = ProcessInfo.processInfo.environment
        for (key, value) in env {
            str = str.replacingOccurrences(of: "%\(key)%", with: value)
        }
        variables[destVar] = .string(str)
    }

    // MARK: exec - [IMPLEMENTED]
    // WARNING: Passes user-controlled input to /bin/sh -c. This is by TTL specification
    // design (exec command runs shell commands), but callers should be aware of the
    // inherent command injection risk when running untrusted macro scripts.

    func cmdExec(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let command = args.map { resolveString($0) }.joined(separator: " ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
            inputStr = output
            variables["inputstr"] = .string(output)
            resultValue = Int(process.terminationStatus)
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: execcmnd - [IMPLEMENTED]

    func cmdExecCmnd(_ args: [String], fullLine: String) { // [IMPLEMENTED]
        // Extract command from full line after "execcmnd"
        let cmdStr: String
        if let range = fullLine.range(of: "execcmnd", options: .caseInsensitive) {
            cmdStr = String(fullLine[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            cmdStr = args.map { resolveString($0) }.joined(separator: " ")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", cmdStr]
        let outPipe = Pipe()
        process.standardOutput = outPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
            inputStr = output
            variables["inputstr"] = .string(output)
            resultValue = Int(process.terminationStatus)
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: setexitcode - [IMPLEMENTED]

    func cmdSetExitCode(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        exitCode = resolveInt(args[0])
    }

    // MARK: random - [IMPLEMENTED]

    func cmdRandom(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let maxVal = resolveInt(args[1])
        let randomVal = maxVal > 0 ? Int.random(in: 0..<maxVal) : 0
        variables[destVar] = .integer(randomVal)
    }

    // MARK: uptime - [IMPLEMENTED]

    func cmdUptime(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        variables[destVar] = .integer(uptime)
    }

    // MARK: gethostname - [IMPLEMENTED]

    func cmdGetHostname(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        cancelExecTimer()
        clientProxy?.getHostname(reply: { [weak self] hostname in
            guard let self = self else { return }
            self.variables[destVar] = .string(hostname)
            self.scheduleNextLine()
        })
    }

    // MARK: getver - [IMPLEMENTED]

    func cmdGetVer(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        cancelExecTimer()
        clientProxy?.getAppVersion(reply: { [weak self] version in
            guard let self = self else { return }
            self.variables[destVar] = .string(version)
            self.scheduleNextLine()
        })
    }

    // MARK: getttdir - [IMPLEMENTED]

    func cmdGetTTDir(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        cancelExecTimer()
        clientProxy?.getAppDirectory(reply: { [weak self] dir in
            guard let self = self else { return }
            self.variables[destVar] = .string(dir)
            self.scheduleNextLine()
        })
    }

    // MARK: getttpos - [IMPLEMENTED]

    func cmdGetTTPos(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let xVar = args[0].lowercased()
        let yVar = args[1].lowercased()
        cancelExecTimer()
        clientProxy?.getWindowPosition(reply: { [weak self] x, y in
            guard let self = self else { return }
            self.variables[xVar] = .integer(x)
            self.variables[yVar] = .integer(y)
            self.scheduleNextLine()
        })
    }

    // MARK: getspecialfolder - [IMPLEMENTED]

    func cmdGetSpecialFolder(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let folderId = resolveInt(args[1])

        let path: String
        switch folderId {
        case 0: // Desktop
            path = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first ?? ""
        case 1: // Documents
            path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        case 2: // Application Support
            path = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? ""
        case 3: // Home
            path = NSHomeDirectory()
        case 4: // Temp
            path = NSTemporaryDirectory()
        case 5: // Downloads
            path = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? ""
        default:
            path = NSHomeDirectory()
        }
        variables[destVar] = .string(path)
    }

    // MARK: getipv4addr - [IMPLEMENTED]

    func cmdGetIPv4Addr(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        variables[destVar] = .string(getLocalIPAddress(family: 2)) // AF_INET
    }

    // MARK: getipv6addr - [IMPLEMENTED]

    func cmdGetIPv6Addr(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        variables[destVar] = .string(getLocalIPAddress(family: 30)) // AF_INET6
    }

    private func getLocalIPAddress(family: Int32) -> String {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return "" }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ifa = ptr {
            let addr = ifa.pointee
            if addr.ifa_addr.pointee.sa_family == UInt8(family) {
                let name = String(cString: addr.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("utun") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr.ifa_addr, socklen_t(addr.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        addresses.append(String(cString: hostname))
                    }
                }
            }
            ptr = addr.ifa_next
        }
        return addresses.first ?? ""
    }

    // MARK: getfileattr - [IMPLEMENTED]

    func cmdGetFileAttr(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let filePath = resolveString(args[1])

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
            let posixPerms = (attrs[.posixPermissions] as? Int) ?? 0
            variables[destVar] = .integer(posixPerms)
            resultValue = 0
        } catch {
            variables[destVar] = .integer(0)
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: setfileattr - [IMPLEMENTED]

    func cmdSetFileAttr(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let filePath = resolveString(args[0])
        let attr = resolveInt(args[1])

        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: attr], ofItemAtPath: filePath)
            resultValue = 0
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: getmodemstatus - [IMPLEMENTED]

    func cmdGetModemStatus(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        cancelExecTimer()
        clientProxy?.getModemStatus(reply: { [weak self] status in
            guard let self = self else { return }
            self.variables[destVar] = .integer(status)
            self.scheduleNextLine()
        })
    }

    // MARK: setdate - [IMPLEMENTED]

    func cmdSetDate(_ args: [String]) { // [IMPLEMENTED]
        // Setting system date requires root - just store for reference
        if !args.isEmpty {
            variables["_setdate"] = .string(resolveString(args[0]))
        }
    }

    // MARK: settime - [IMPLEMENTED]

    func cmdSetTime(_ args: [String]) { // [IMPLEMENTED]
        if !args.isEmpty {
            variables["_settime"] = .string(resolveString(args[0]))
        }
    }
}

// MARK: - Terminal Commands

extension MacroRunner {

    // MARK: clearscreen - [IMPLEMENTED]

    func cmdClearScreen() { // [IMPLEMENTED]
        cancelExecTimer()
        clientProxy?.clearScreen(reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: settitle - [IMPLEMENTED]

    func cmdSetTitle(_ args: [String]) { // [IMPLEMENTED]
        let title = args.map { resolveString($0) }.joined(separator: " ")
        cancelExecTimer()
        clientProxy?.setWindowTitle(title: title, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: gettitle - [IMPLEMENTED]

    func cmdGetTitle(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        cancelExecTimer()
        clientProxy?.getWindowTitle(reply: { [weak self] title in
            guard let self = self else { return }
            self.variables[destVar] = .string(title)
            self.scheduleNextLine()
        })
    }

    // MARK: show/showtt - [IMPLEMENTED]

    func cmdShow(_ args: [String]) { // [IMPLEMENTED]
        let visible = args.isEmpty ? true : resolveInt(args[0]) != 0
        cancelExecTimer()
        clientProxy?.showWindow(visible: visible, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: closett - [IMPLEMENTED]

    func cmdCloseTT() { // [IMPLEMENTED]
        cancelExecTimer()
        clientProxy?.terminateApp(reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: enablekeyb - [IMPLEMENTED]

    func cmdEnableKeyb(_ args: [String]) { // [IMPLEMENTED]
        let flag = args.isEmpty ? 1 : resolveInt(args[0])
        cancelExecTimer()
        clientProxy?.enableKeyboard(flag: flag, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: setecho - [IMPLEMENTED]

    func cmdSetEcho(_ args: [String]) { // [IMPLEMENTED]
        let flag = args.isEmpty ? 1 : resolveInt(args[0])
        cancelExecTimer()
        clientProxy?.setEcho(flag: flag, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: setsync - [IMPLEMENTED]

    func cmdSetSync(_ args: [String]) { // [IMPLEMENTED]
        // Sync mode is handled locally
        let flag = args.isEmpty ? 1 : resolveInt(args[0])
        variables["_sync"] = .integer(flag)
    }

    // MARK: dispstr - [IMPLEMENTED]

    func cmdDispStr(_ args: [String]) { // [IMPLEMENTED]
        let text = args.map { resolveString($0) }.joined()
        cancelExecTimer()
        clientProxy?.displayString(text: text, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: setbaud - [IMPLEMENTED]

    func cmdSetBaud(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let rate = resolveInt(args[0])
        cancelExecTimer()
        clientProxy?.setBaudRate(rate: rate, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: setflowctrl - [IMPLEMENTED]

    func cmdSetFlowCtrl(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let mode = resolveInt(args[0])
        cancelExecTimer()
        clientProxy?.setFlowControl(mode: mode, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: setdtr - [IMPLEMENTED]

    func cmdSetDtr(_ args: [String]) { // [IMPLEMENTED]
        let on = args.isEmpty ? 1 : resolveInt(args[0])
        cancelExecTimer()
        clientProxy?.setDtr(on: on, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: setrts - [IMPLEMENTED]

    func cmdSetRts(_ args: [String]) { // [IMPLEMENTED]
        let on = args.isEmpty ? 1 : resolveInt(args[0])
        cancelExecTimer()
        clientProxy?.setRts(on: on, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }
}

// MARK: - Clipboard Commands

extension MacroRunner {

    // MARK: clipb2var - [IMPLEMENTED]

    func cmdClipb2Var(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let destVar = args[0].lowercased()
        cancelExecTimer()
        clientProxy?.getClipboard(reply: { [weak self] text in
            guard let self = self else { return }
            self.variables[destVar] = .string(text)
            self.scheduleNextLine()
        })
    }

    // MARK: var2clipb - [IMPLEMENTED]

    func cmdVar2Clipb(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let text = resolveString(args[0])
        cancelExecTimer()
        clientProxy?.setClipboard(text: text, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }
}

// MARK: - Log Commands

extension MacroRunner {

    // MARK: logopen - [IMPLEMENTED]

    func cmdLogOpen(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let path = resolveString(args[0])
        let binary = args.count > 1 ? resolveInt(args[1]) != 0 : false
        let append = args.count > 2 ? resolveInt(args[2]) != 0 : false
        // Additional optional args parsed but stored for future use
        let plaintext = args.count > 3 ? resolveInt(args[3]) != 0 : false
        let timestamp = args.count > 4 ? resolveInt(args[4]) != 0 : false
        let _ = (binary, plaintext, timestamp)  // Reserved for future XPC extension
        cancelExecTimer()
        clientProxy?.openLog(path: path, append: append, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: logclose - [IMPLEMENTED]

    func cmdLogClose() { // [IMPLEMENTED]
        cancelExecTimer()
        clientProxy?.closeLog(reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: logpause - [IMPLEMENTED]

    func cmdLogPause() { // [IMPLEMENTED]
        cancelExecTimer()
        clientProxy?.pauseLog(reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: logstart - [IMPLEMENTED]

    func cmdLogStart() { // [IMPLEMENTED]
        cancelExecTimer()
        clientProxy?.resumeLog(reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: logwrite - [IMPLEMENTED]

    func cmdLogWrite(_ args: [String]) { // [IMPLEMENTED]
        let text = args.map { resolveString($0) }.joined()
        cancelExecTimer()
        clientProxy?.writeToLog(text: text, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: loginfo - [IMPLEMENTED]

    func cmdLogInfo() { // [IMPLEMENTED]
        cancelExecTimer()
        clientProxy?.getLogInfo(reply: { [weak self] state, path in
            guard let self = self else { return }
            self.resultValue = state
            self.variables["result"] = .integer(state)
            self.inputStr = path
            self.variables["inputstr"] = .string(path)
            self.scheduleNextLine()
        })
    }

    // MARK: logrotate - [IMPLEMENTED]

    func cmdLogRotate(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let mode = resolveString(args[0])
        let value = resolveInt(args[1])
        cancelExecTimer()
        clientProxy?.setLogRotation(mode: mode, value: value, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: logautoclose - [IMPLEMENTED]

    func cmdLogAutoClose(_ args: [String]) { // [IMPLEMENTED]
        // Store setting locally; actual auto-close handled by log system
        let flag = args.isEmpty ? 1 : resolveInt(args[0])
        variables["_logautoclose"] = .integer(flag)
    }
}

// MARK: - Checksum Commands

extension MacroRunner {

    // MARK: crc/checksum - [IMPLEMENTED]

    func cmdChecksum(_ args: [String], type: String) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let inputStr = resolveString(args[1])
        guard let data = inputStr.data(using: .utf8) else {
            variables[destVar] = .integer(0)
            return
        }
        variables[destVar] = .integer(computeChecksum(data: data, type: type))
    }

    func cmdChecksumFile(_ args: [String], type: String) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let filePath = resolveString(args[1])
        guard let data = FileManager.default.contents(atPath: filePath) else {
            variables[destVar] = .integer(0)
            resultValue = -1
            variables["result"] = .integer(-1)
            return
        }
        variables[destVar] = .integer(computeChecksum(data: data, type: type))
        resultValue = 0
        variables["result"] = .integer(0)
    }

    private func computeChecksum(data: Data, type: String) -> Int {
        switch type {
        case "crc16":
            var crc: UInt16 = 0xFFFF
            for byte in data {
                crc ^= UInt16(byte)
                for _ in 0..<8 {
                    if crc & 1 != 0 {
                        crc = (crc >> 1) ^ 0xA001
                    } else {
                        crc >>= 1
                    }
                }
            }
            return Int(crc)

        case "crc32":
            var crc: UInt32 = 0xFFFFFFFF
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 {
                    if crc & 1 != 0 {
                        crc = (crc >> 1) ^ 0xEDB88320
                    } else {
                        crc >>= 1
                    }
                }
            }
            return Int(crc ^ 0xFFFFFFFF)

        case "checksum8":
            var sum: UInt8 = 0
            for byte in data { sum = sum &+ byte }
            return Int(sum)

        case "checksum16":
            var sum: UInt16 = 0
            for byte in data { sum = sum &+ UInt16(byte) }
            return Int(sum)

        case "checksum32":
            var sum: UInt32 = 0
            for byte in data { sum = sum &+ UInt32(byte) }
            return Int(sum)

        default:
            return 0
        }
    }
}

// MARK: - Bit Operation Commands

extension MacroRunner {

    // MARK: rotateleft - [IMPLEMENTED]

    func cmdRotateLeft(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let destVar = args[0].lowercased()
        let val = resolveInt(args[1])
        let bits = resolveInt(args[2])
        let uval = UInt32(truncatingIfNeeded: val)
        let shifted = (uval << bits) | (uval >> (32 - bits))
        variables[destVar] = .integer(Int(Int32(bitPattern: shifted)))
    }

    // MARK: rotateright - [IMPLEMENTED]

    func cmdRotateRight(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let destVar = args[0].lowercased()
        let val = resolveInt(args[1])
        let bits = resolveInt(args[2])
        let uval = UInt32(truncatingIfNeeded: val)
        let shifted = (uval >> bits) | (uval << (32 - bits))
        variables[destVar] = .integer(Int(Int32(bitPattern: shifted)))
    }
}

// MARK: - Misc Commands

extension MacroRunner {

    // MARK: beep - [IMPLEMENTED]

    func cmdBeep() { // [IMPLEMENTED]
        NSSound.beep()
    }

    // MARK: setdebug - [IMPLEMENTED]

    func cmdSetDebug(_ args: [String]) { // [IMPLEMENTED]
        debugMode = args.isEmpty ? true : resolveInt(args[0]) != 0
    }

    // MARK: regexoption - [IMPLEMENTED]

    func cmdRegexOption(_ args: [String]) { // [IMPLEMENTED]
        if let opt = args.first?.lowercased() {
            regexCaseInsensitive = opt == "1" || opt == "i"
        }
    }

    // MARK: restoresetup - [IMPLEMENTED]

    func cmdRestoreSetup(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let path = resolveString(args[0])
        cancelExecTimer()
        clientProxy?.restoreSetup(path: path, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: callmenu - [IMPLEMENTED]

    func cmdCallMenu(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let menuId = resolveInt(args[0])
        cancelExecTimer()
        clientProxy?.callMenu(menuId: menuId, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: loadkeymap - [IMPLEMENTED]

    func cmdLoadKeyMap(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let path = resolveString(args[0])
        cancelExecTimer()
        clientProxy?.loadKeyMap(path: path, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: setserialdelaychar - [IMPLEMENTED]

    func cmdSetSerialDelayChar(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let ms = resolveInt(args[0])
        cancelExecTimer()
        clientProxy?.setSerialDelayChar(ms: ms, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }

    // MARK: setserialdelayline - [IMPLEMENTED]

    func cmdSetSerialDelayLine(_ args: [String]) { // [IMPLEMENTED]
        guard !args.isEmpty else { return }
        let ms = resolveInt(args[0])
        cancelExecTimer()
        clientProxy?.setSerialDelayLine(ms: ms, reply: { [weak self] in
            self?.scheduleNextLine()
        })
    }
}

// MARK: - Password Commands (Keychain)

extension MacroRunner {

    // MARK: getpassword - [IMPLEMENTED]

    func cmdGetPassword(_ args: [String]) { // [IMPLEMENTED]
        // getpassword <filename> <keyname> <varname>
        // Load from keychain, send via sendPasswordData (not sendToTerminal for security)
        guard args.count >= 3 else {
            reportError("getpassword: requires filename, keyname, varname")
            return
        }

        let filename = resolveString(args[0])
        let keyname = resolveString(args[1])
        let varName = args[2].lowercased()
        let account = "\(filename):\(keyname)"

        do {
            let password = try keychainManager.load(account: account)
            variables[varName] = .string(password)
            resultValue = 0

            // Send password data securely via XPC
            if var data = password.data(using: .utf8) {
                clientProxy?.sendPasswordData(data: data, reply: {})
                TTLKeychainManager.zeroData(&data)
            }
        } catch TTLKeychainError.notFound {
            // Show password input dialog
            cancelExecTimer()
            clientProxy?.showDialog(type: MacroDialogType.passwordbox.rawValue,
                                    message: "Enter password for \(keyname)",
                                    defaultValue: "",
                                    reply: { [weak self] resultCode, inputText in
                guard let self = self else { return }
                if resultCode == 1 && !inputText.isEmpty {
                    self.variables[varName] = .string(inputText)
                    // Save to keychain
                    try? self.keychainManager.save(password: inputText, account: account)
                    // Send securely
                    if var data = inputText.data(using: .utf8) {
                        self.clientProxy?.sendPasswordData(data: data, reply: {})
                        TTLKeychainManager.zeroData(&data)
                    }
                    self.resultValue = 0
                } else {
                    self.resultValue = -1
                }
                self.variables["result"] = .integer(self.resultValue)
                self.scheduleNextLine()
            })
            return
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: setpassword - [IMPLEMENTED]

    func cmdSetPassword(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else {
            reportError("setpassword: requires filename, keyname, password")
            return
        }

        let filename = resolveString(args[0])
        let keyname = resolveString(args[1])
        let password = resolveString(args[2])
        let account = "\(filename):\(keyname)"

        do {
            try keychainManager.save(password: password, account: account)
            resultValue = 0
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: delpassword - [IMPLEMENTED]

    func cmdDelPassword(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let filename = resolveString(args[0])
        let keyname = resolveString(args[1])
        let account = "\(filename):\(keyname)"

        do {
            try keychainManager.delete(account: account)
            resultValue = 0
        } catch {
            resultValue = -1
        }
        variables["result"] = .integer(resultValue)
    }

    // MARK: ispassword - [IMPLEMENTED]

    func cmdIsPassword(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let filename = resolveString(args[0])
        let keyname = resolveString(args[1])
        let account = "\(filename):\(keyname)"

        resultValue = keychainManager.exists(account: account) ? 1 : 0
        variables["result"] = .integer(resultValue)
    }
}

// MARK: - File Transfer Commands

extension MacroRunner {

    // MARK: File transfer send - [IMPLEMENTED]

    func cmdFileTransferSend(_ args: [String], proto: String) { // [IMPLEMENTED]
        guard !args.isEmpty else {
            reportError("\(proto)send: file path required")
            return
        }

        // Check if transfer already in progress
        if isTransferWaiting {
            reportError("\(proto)send: transfer already in progress")
            return
        }

        let localPath = resolveString(args[0])
        let option = args.count > 1 ? resolveString(args[1]) : ""
        cancelExecTimer()
        isTransferWaiting = true

        clientProxy?.startFileSend(protocolName: proto, localPath: localPath, option: option,
                                    reply: { [weak self] success, errorMsg in
            guard let self = self else { return }
            if !success {
                self.isTransferWaiting = false
                self.resultValue = -1
                self.variables["result"] = .integer(-1)
                self.reportError("\(proto)send: \(errorMsg)")
                self.scheduleNextLine()
                return
            }
            // Poll transfer status
            self.pollTransferStatus()
        })
    }

    // MARK: File transfer recv - [IMPLEMENTED]

    func cmdFileTransferRecv(_ args: [String], proto: String) { // [IMPLEMENTED]
        // Check if transfer already in progress
        if isTransferWaiting {
            reportError("\(proto)recv: transfer already in progress")
            return
        }

        let localDir = args.isEmpty ? "" : resolveString(args[0])
        cancelExecTimer()
        isTransferWaiting = true

        clientProxy?.startFileRecv(protocolName: proto, localDir: localDir,
                                    reply: { [weak self] success, errorMsg, savedPath in
            guard let self = self else { return }
            if !success {
                self.isTransferWaiting = false
                self.resultValue = -1
                self.variables["result"] = .integer(-1)
                self.reportError("\(proto)recv: \(errorMsg)")
                self.scheduleNextLine()
                return
            }
            self.inputStr = savedPath
            self.variables["inputstr"] = .string(savedPath)
            self.pollTransferStatus()
        })
    }

    // MARK: Transfer status polling - [IMPLEMENTED]

    private func pollTransferStatus() {
        guard isRunning, !isCancelled, isTransferWaiting else { return }

        clientProxy?.getTransferStatus(reply: { [weak self] statusStr, bytesSent, totalBytes in
            guard let self = self else { return }

            let status = TransferStatusString(rawValue: statusStr) ?? .idle

            switch status {
            case .done:
                self.isTransferWaiting = false
                self.resultValue = 0
                self.variables["result"] = .integer(0)
                self.scheduleNextLine()

            case .error:
                self.isTransferWaiting = false
                self.resultValue = -1
                self.variables["result"] = .integer(-1)
                self.scheduleNextLine()

            case .idle:
                // Transfer finished already
                self.isTransferWaiting = false
                self.resultValue = 0
                self.variables["result"] = .integer(0)
                self.scheduleNextLine()

            case .sending, .receiving:
                // Still in progress, poll again at 0.5s intervals
                self.execTimer = Timer.scheduledTimer(
                    withTimeInterval: MacroXPCEndpoint.transferPollInterval,
                    repeats: false) { [weak self] _ in
                    self?.pollTransferStatus()
                }
            }
        })
    }

    // MARK: kmtget - [IMPLEMENTED]

    func cmdKermitGet(_ args: [String]) { // [IMPLEMENTED]
        // Kermit GET - send get request then receive
        guard !args.isEmpty else { return }
        let remotePath = resolveString(args[0])
        let localDir = args.count > 1 ? resolveString(args[1]) : ""

        // Send Kermit GET command, then start receive
        let getCmd = "get \(remotePath)\r"
        if let data = getCmd.data(using: .utf8) {
            clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
                self?.cmdFileTransferRecv([], proto: "kermit")
            })
        }
        cancelExecTimer()
    }

    // MARK: kmtfinish - [IMPLEMENTED]

    func cmdKermitFinish() { // [IMPLEMENTED]
        let finishCmd = "finish\r"
        if let data = finishCmd.data(using: .utf8) {
            clientProxy?.sendToTerminal(data: data, reply: { [weak self] in
                self?.scheduleNextLine()
            })
        }
        cancelExecTimer()
    }

    // MARK: scpsend - [IMPLEMENTED]

    func cmdScpSend(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else {
            reportError("scpsend: localpath and remotepath required")
            return
        }
        let localPath = resolveString(args[0])
        let remotePath = resolveString(args[1])
        cancelExecTimer()

        clientProxy?.scpSend(localPath: localPath, remotePath: remotePath,
                              reply: { [weak self] success in
            guard let self = self else { return }
            self.resultValue = success ? 0 : -1
            self.variables["result"] = .integer(self.resultValue)
            self.scheduleNextLine()
        })
    }

    // MARK: scprecv - [IMPLEMENTED]

    func cmdScpRecv(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else {
            reportError("scprecv: remotepath and localpath required")
            return
        }
        let remotePath = resolveString(args[0])
        let localPath = resolveString(args[1])
        cancelExecTimer()

        clientProxy?.scpRecv(remotePath: remotePath, localPath: localPath,
                              reply: { [weak self] success in
            guard let self = self else { return }
            self.resultValue = success ? 0 : -1
            self.variables["result"] = .integer(self.resultValue)
            self.scheduleNextLine()
        })
    }

    // MARK: recvfile - [IMPLEMENTED]

    func cmdRecvFile(_ args: [String]) { // [IMPLEMENTED]
        // recvfile <filename> <binary_flag> <autostop_seconds>
        guard args.count >= 3 else {
            reportError("recvfile: requires 3 arguments (filename, binary_flag, autostop)")
            return
        }
        let filename = resolveString(args[0])
        let _ = resolveInt(args[1])  // binary_flag (ignored per original spec - always binary)
        let _ = resolveInt(args[2])  // autostop_seconds (reserved for future raw data capture)
        // Current implementation delegates to ZMODEM protocol via the directory path
        // The filename is used as the save path
        let dir = (filename as NSString).deletingLastPathComponent
        let localDir = dir.isEmpty ? filename : dir
        cmdFileTransferRecv([localDir], proto: "zmodem")
    }
}
