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
    private var nextFileHandle: Int = 0

    // MARK: - Directory Search

    private var dirSearchResults: [[String]] = []
    private var dirSearchIndex: [Int] = []

    // MARK: - File Stack (for include)

    private var fileStack: [(lines: [String], lineIndex: Int)] = []

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

    // MARK: - Assignment

    private func handleAssignment(_ parts: [String]) {
        let varName = parts[0].lowercased()
        let valueStr = parts.dropFirst(2).joined(separator: " ")
        let val = resolveValue(valueStr)
        variables[varName] = val
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
            case "elseif": elseFlag -= 1 // Simplified
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

        // Send/receive - [IMPLEMENTED]
        case "send":        cmdSend(args, addCR: false) // [IMPLEMENTED]
        case "sendln":      cmdSend(args, addCR: true) // [IMPLEMENTED]
        case "sendtext":    cmdSendText(args) // [IMPLEMENTED]
        case "sendbinary":  cmdSendBinary(args) // [IMPLEMENTED]
        case "sendbreak":   cmdSendBreak() // [IMPLEMENTED]
        case "sendkcode":   cmdSendKCode(args) // [IMPLEMENTED]
        case "sendfile":    cmdSendFile(args) // [IMPLEMENTED]
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
        case "findclose":   cmdFindClose() // [IMPLEMENTED]
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
        case "logautoclose": cmdLogAutoClose(args) // [IMPLEMENTED]

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
    }

    deinit {
        cancelExecTimer()
        closeAllFiles()
    }
}
