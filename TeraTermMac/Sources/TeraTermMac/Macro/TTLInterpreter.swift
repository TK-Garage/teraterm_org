/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of ttl.cpp to Swift/macOS
 * TTL (Tera Term Language) interpreter - main execution engine
 */

#if canImport(AppKit)
import AppKit

// MARK: - Interpreter Delegate Protocol

protocol TTLInterpreterDelegate: AnyObject {
    /// Send data to connected terminal
    func ttlSendData(_ data: Data)
    /// Send string to connected terminal
    func ttlSendString(_ text: String)
    /// Send string + CR to connected terminal
    func ttlSendLine(_ text: String)
    /// Check if terminal is connected
    func ttlIsConnected() -> Bool
    /// Get received data buffer (and optionally clear it)
    func ttlGetReceivedData(clear: Bool) -> String
    /// Flush receive buffer
    func ttlFlushReceiveBuffer()
    /// Disconnect from terminal
    func ttlDisconnect()
    /// Connect to terminal
    func ttlConnect(_ param: String)
    /// Set terminal window title
    func ttlSetTitle(_ title: String)
    /// Get terminal window title
    func ttlGetTitle() -> String
    /// Show/hide terminal window
    func ttlShowWindow(_ show: Bool)
    /// Clear terminal screen
    func ttlClearScreen()
    /// Send break signal
    func ttlSendBreak()
    /// Log operations
    func ttlLogOpen(_ path: String, append: Bool)
    func ttlLogClose()
    func ttlLogPause()
    func ttlLogStart()
    func ttlLogWrite(_ text: String)
    /// Display error message
    func ttlShowError(_ message: String, line: Int)
    /// Display status box
    func ttlShowStatusBox(_ message: String, title: String)
    func ttlCloseStatusBox()
    /// Get clipboard text
    func ttlGetClipboard() -> String
    /// Set clipboard text
    func ttlSetClipboard(_ text: String)
    /// Set baud rate
    func ttlSetBaud(_ baud: Int)
    /// Set flow control
    func ttlSetFlowCtrl(_ mode: Int)
    /// Set DTR signal
    func ttlSetDtr(_ on: Int)
    /// Set RTS signal
    func ttlSetRts(_ on: Int)
}

// MARK: - TTL Interpreter

class TTLInterpreter {
    let parser: TTLParser
    weak var delegate: TTLInterpreterDelegate?

    // Execution state
    private var parseAgain: Bool = false
    private var ifNest: Int = 0
    private var elseFlag: Int = 0
    private var endIfFlag: Int = 0
    private var endWhileFlag: Int = 0
    private var breakFlag: Int = 0
    private var continueFlag: Bool = false

    // File handles (up to 16 simultaneous files)
    private let maxFileHandles = 16
    private var fileHandles: [FileHandle?]
    private var filePointers: [Int64]
    private var filePaths: [String]

    // Directory search handles
    private let maxDirHandles = 8
    private var dirEnumerators: [FileManager.DirectoryEnumerator?]
    private var dirPatterns: [String]

    // Wait state
    private var waitStrings: [String] = []
    private var waitRegex: Bool = false
    private var waitLn: Bool = false
    private var receiveBuffer: String = ""
    private var timeLimit: TimeInterval = 0
    private var timeStart: Date?

    // Timer for async operations
    private var execTimer: Timer?
    private var pauseTimer: Timer?

    // Exit code
    var exitCode: Int = 0

    // Execution callback
    var onComplete: (() -> Void)?
    var onError: ((String, Int) -> Void)?

    // Regex options
    private var regexOptionCaseInsensitive: Bool = false

    // Dialog command provider (positioning, display mode, statusbox management)
    let dialogProvider = DialogCommandProvider()

    // MARK: - Initialization

    init() {
        parser = TTLParser()
        fileHandles = [FileHandle?](repeating: nil, count: maxFileHandles)
        filePointers = [Int64](repeating: 0, count: maxFileHandles)
        filePaths = [String](repeating: "", count: maxFileHandles)
        dirEnumerators = [FileManager.DirectoryEnumerator?](repeating: nil, count: maxDirHandles)
        dirPatterns = [String](repeating: "", count: maxDirHandles)
    }

    // MARK: - Script Loading

    func loadScript(_ source: String) {
        parser.loadScript(source)
        resetState()
    }

    func loadScript(from url: URL) throws {
        try parser.loadScript(from: url)
        resetState()
    }

    private func resetState() {
        parseAgain = false
        ifNest = 0
        elseFlag = 0
        endIfFlag = 0
        endWhileFlag = 0
        breakFlag = 0
        continueFlag = false
        exitCode = 0
        receiveBuffer = ""
        waitStrings.removeAll()

        for i in 0..<maxFileHandles {
            fileHandles[i] = nil
            filePointers[i] = 0
            filePaths[i] = ""
        }
        for i in 0..<maxDirHandles {
            dirEnumerators[i] = nil
            dirPatterns[i] = ""
        }
    }

    // MARK: - Execution Engine

    /// Start executing the loaded script
    func run() {
        parser.status = .run
        scheduleExec()
    }

    /// Stop execution
    func stop() {
        execTimer?.invalidate()
        execTimer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        parser.status = .end
        closeAllFiles()
        dialogProvider.cleanup()
    }

    private func scheduleExec() {
        execTimer?.invalidate()
        execTimer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { [weak self] _ in
            self?.execStep()
        }
    }

    private func execStep() {
        guard parser.status == .run else {
            handleNonRunState()
            return
        }

        // Get next line unless we need to re-parse
        if !parseAgain {
            if !parser.getNewLine() {
                parser.status = .end
                finish()
                return
            }
        }
        parseAgain = false

        // Scan for labels on first pass
        scanLabel()

        // Execute command
        do {
            try execCmnd()
        } catch let error as TTLError {
            dispError(error)
            return
        } catch {
            dispError(.syntax)
            return
        }

        // Continue execution if still running
        if parser.status == .run {
            scheduleExec()
        } else {
            handleNonRunState()
        }
    }

    private func handleNonRunState() {
        switch parser.status {
        case .end:
            finish()
        case .pause, .sleep:
            // Timer already set by pause/mpause command
            break
        case .wait, .waitLn, .waitNL, .wait2, .waitN, .wait4all:
            scheduleWaitCheck()
        default:
            break
        }
    }

    private func finish() {
        closeAllFiles()
        onComplete?()
    }

    private func dispError(_ error: TTLError) {
        let msg = "Error at line \(parser.currentLine): \(error.message)"
        delegate?.ttlShowError(msg, line: parser.currentLine)
        onError?(msg, parser.currentLine)
        stop()
    }

    // MARK: - Label Scanning

    func scanLabel() {
        let line = parser.lineBuffer.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix(":") {
            let labelName = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            if !labelName.isEmpty {
                if parser.checkVar(labelName) == nil {
                    parser.newLabVar(labelName, position: parser.currentLine - 1, level: parser.scopeLevel)
                }
            }
        }
    }

    // MARK: - Pre-scan all labels

    func prescanLabels() {
        let savedLine = parser.currentLine
        parser.currentLine = 0
        while parser.currentLine < parser.lines.count {
            let line = parser.lines[parser.currentLine].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(":") {
                let labelName = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces).first ?? ""
                if !labelName.isEmpty && parser.checkVar(labelName) == nil {
                    parser.newLabVar(labelName, position: parser.currentLine, level: 0)
                }
            }
            parser.currentLine += 1
        }
        parser.currentLine = savedLine
    }

    // MARK: - Command Dispatch (port of ExecCmnd)

    func execCmnd() throws {
        let line = parser.lineBuffer

        // Skip empty lines and comments
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix(";") { return }

        // Handle label definitions (lines starting with ":")
        if trimmed.hasPrefix(":") { return }

        // Reset line pointer for parsing
        parser.linePtr = 0

        // Handle endwhile skipping
        if endWhileFlag > 0 {
            if let cmd = parser.getReservedWord() {
                switch cmd {
                case .while_, .until, .do_:
                    endWhileFlag += 1
                case .endWhile, .endUntil, .loop:
                    endWhileFlag -= 1
                default: break
                }
            }
            return
        }

        // Handle break skipping
        if breakFlag > 0 {
            if let cmd = parser.getReservedWord() {
                switch cmd {
                case .if_:
                    if try checkThen() { ifNest += 1 }
                case .endIf:
                    // break/continueの呼び出し元ifのendifは無視（ifNest==0の場合）
                    if ifNest > 0 { ifNest -= 1 }
                case .for_, .while_, .until, .do_:
                    breakFlag += 1
                case .next, .endWhile, .endUntil, .loop:
                    breakFlag -= 1
                    // breakの場合はループフレームを除去
                    if breakFlag == 0 && !continueFlag {
                        if !parser.loopStack.isEmpty {
                            parser.loopStack.removeLast()
                        }
                    }
                default: break
                }
            }
            if breakFlag > 0 || !continueFlag { return }
            continueFlag = false
            // continueの場合はlinePtr をリセットしてループ終端コマンド（next/endwhile/loop）を再実行
            parser.linePtr = 0
        }

        // Handle endif skipping
        if endIfFlag > 0 {
            if let cmd = parser.getReservedWord() {
                if try cmd == .if_ && checkThen() {
                    endIfFlag += 1
                } else if cmd == .endIf {
                    endIfFlag -= 1
                }
            }
            return
        }

        // Handle else skipping
        if elseFlag > 0 {
            if let cmd = parser.getReservedWord() {
                switch cmd {
                case .if_:
                    if try checkThen() { endIfFlag += 1 }
                case .else_:
                    elseFlag -= 1
                case .elseIf:
                    if try checkElseIf() != 0 { elseFlag -= 1 }
                case .endIf:
                    elseFlag -= 1
                    if elseFlag == 0 { ifNest -= 1 }
                default: break
                }
            }
            return
        }

        // Try to parse as a reserved command word
        if let cmd = parser.getReservedWord() {
            try dispatchCommand(cmd)
            return
        }

        // Try variable assignment: identifier = expression
        parser.linePtr = 0
        if let name = parser.getIdentifier() {
            // Check for array index
            var arrayIndex: Int? = nil
            let idxSaved = parser.linePtr
            if parser.getFirstChar() == "[" {
                parser.linePtr -= 1 // back up
                arrayIndex = try? parser.getIndex()
            } else {
                parser.linePtr = idxSaved
            }

            guard parser.getFirstChar() == "=" else {
                throw TTLError.notSupported
            }

            // Try string value first
            if let strResult = parser.getString() {
                switch strResult {
                case .success(let s):
                    try assignStringValue(name: name, value: s, arrayIndex: arrayIndex)
                case .failure(let e):
                    throw e
                }
            } else {
                // Try expression
                let result = try parser.getExpression()
                switch result {
                case .integer(let v):
                    try assignIntValue(name: name, value: v, arrayIndex: arrayIndex)
                case .string(let id):
                    let s = parser.getStrVal(id: id)
                    try assignStringValue(name: name, value: s, arrayIndex: arrayIndex)
                default:
                    throw TTLError.syntax
                }
            }
            return
        }

        throw TTLError.syntax
    }

    private func assignIntValue(name: String, value: Int, arrayIndex: Int?) throws {
        if let (type, id) = parser.checkVar(name) {
            if let idx = arrayIndex {
                guard type == .intArray else { throw TTLError.syntax }
                let arrId = parser.getIntVarFromArray(varId: id, index: idx)
                parser.setIntVal(id: arrId, value: value)
            } else {
                guard type == .integer else { throw TTLError.typeMismatch }
                parser.setIntVal(id: id, value: value)
            }
        } else {
            if arrayIndex != nil { throw TTLError.syntax }
            parser.newIntVar(name, value: value)
        }
    }

    private func assignStringValue(name: String, value: String, arrayIndex: Int?) throws {
        if let (type, id) = parser.checkVar(name) {
            if let idx = arrayIndex {
                guard type == .strArray else { throw TTLError.syntax }
                let arrId = parser.getStrVarFromArray(varId: id, index: idx)
                parser.setStrVal(id: arrId, value: value)
            } else {
                guard type == .string else { throw TTLError.typeMismatch }
                parser.setStrVal(id: id, value: value)
            }
        } else {
            if arrayIndex != nil { throw TTLError.syntax }
            parser.newStrVar(name, value: value)
        }
    }

    // MARK: - Command Dispatcher

    private func dispatchCommand(_ cmd: TTLCommand) throws {
        switch cmd {
        // Control flow
        case .if_:          try ttlIf()
        case .else_:        try ttlElse()
        case .elseIf:       try ttlElseIf()
        case .endIf:        try ttlEndIf()
        case .goto_:        try ttlGoto()
        case .call:         try ttlCall()
        case .return:       try ttlReturn()
        case .include:      try ttlInclude()
        case .end:          try ttlEnd()
        case .exit:         try ttlExit()
        case .for_:         try ttlFor()
        case .next:         try ttlNext()
        case .while_:       try ttlWhile(mode: true)
        case .endWhile:     try ttlEndWhile(mode: true)
        case .until:        try ttlWhile(mode: false)
        case .endUntil:     try ttlEndWhile(mode: false)
        case .do_:          try ttlDo()
        case .loop:         try ttlLoop()
        case .break_:       try ttlBreak()
        case .continue_:    try ttlContinue()
        case .ifDefined:    try ttlIfDefined()

        // Send/receive
        case .send:         try ttlSend()
        case .sendLn:       try ttlSendLn()
        case .sendText:     try ttlSendText()
        case .sendBinary:   try ttlSendBinary()
        case .sendBreak:    try ttlSendBreak()
        case .sendKCode:    try ttlSendKCode()
        case .sendFile:     try ttlSendFile()
        case .recvLn:       try ttlRecvLn()
        case .flushRecv:    try ttlFlushRecv()

        // Wait
        case .wait:         try ttlWait(ln: false)
        case .waitLn:       try ttlWait(ln: true)
        case .waitRegex:    try ttlWaitRegex()
        case .waitN:        try ttlWaitN()
        case .waitRecv:     try ttlWaitRecv()
        case .wait4all:     try ttlWait4All()
        case .waitEvent:    try ttlWaitEvent()

        // Pause
        case .pause:        try ttlPause()
        case .milliPause:   try ttlMilliPause()

        // String operations
        case .strLen:       try ttlStrLen()
        case .strConcat:    try ttlStrConcat()
        case .strCopy:      try ttlStrCopy()
        case .strCompare:   try ttlStrCompare()
        case .strScan:      try ttlStrScan()
        case .strMatch:     try ttlStrMatch()
        case .str2Int:      try ttlStr2Int()
        case .int2Str:      try ttlInt2Str()
        case .str2Code:     try ttlStr2Code()
        case .code2Str:     try ttlCode2Str()
        case .strInsert:    try ttlStrInsert()
        case .strRemove:    try ttlStrRemove()
        case .strReplace:   try ttlStrReplace()
        case .strSpecial:   try ttlStrSpecial()
        case .strTrim:      try ttlStrTrim()
        case .strSplit:     try ttlStrSplit()
        case .strJoin:      try ttlStrJoin()
        case .toLower:      try ttlToLower()
        case .toUpper:      try ttlToUpper()
        case .sprintf:      try ttlSprintf(mode: 0)
        case .sprintf2:     try ttlSprintf(mode: 1)

        // File I/O
        case .fileOpen:     try ttlFileOpen()
        case .fileClose:    try ttlFileClose()
        case .fileReadln:   try ttlFileReadln()
        case .fileRead:     try ttlFileRead()
        case .fileWrite:    try ttlFileWrite(addCRLF: false)
        case .fileWriteLn:  try ttlFileWrite(addCRLF: true)
        case .fileCreate:   try ttlFileCreate()
        case .fileDelete:   try ttlFileDelete()
        case .fileCopy:     try ttlFileCopy()
        case .fileRename:   try ttlFileRename()
        case .fileConcat:   try ttlFileConcat()
        case .fileSearch:   try ttlFileSearch()
        case .fileSeek:     try ttlFileSeek()
        case .fileSeekBack: try ttlFileSeekBack()
        case .fileMarkPtr:  try ttlFileMarkPtr()
        case .fileStat:     try ttlFileStat()
        case .fileTruncate: try ttlFileTruncate()
        case .fileStrSeek:  try ttlFileStrSeek()
        case .fileStrSeek2: try ttlFileStrSeek2()
        case .fileLock:     try ttlFileLock()
        case .fileUnLock:   try ttlFileUnLock()

        // Directory
        case .findFirst:    try ttlFindFirst()
        case .findNext:     try ttlFindNext()
        case .findClose:    try ttlFindClose()
        case .folderCreate: try ttlFolderCreate()
        case .folderDelete: try ttlFolderDelete()
        case .folderSearch: try ttlFolderSearch()

        // Array
        case .intDim:       try ttlDim(isInt: true)
        case .strDim:       try ttlDim(isInt: false)

        // Dialog boxes
        case .inputBox:     try ttlInputBox(password: false)
        case .passwordBox:  try ttlInputBox(password: true)
        case .messageBox:   try ttlMessageBox()
        case .yesNoBox:     try ttlYesNoBox()
        case .statusBox:    try ttlStatusBox()
        case .closeSBox:    try ttlCloseSBox()
        case .listBox:      try ttlListBox()
        case .filenameBox:  try ttlFilenameBox()
        case .dirnameBox:   try ttlDirnameBox()
        case .bringupBox:   try ttlBringupBox()

        // System/environment
        case .getDate:      try ttlGetTime(isDate: true)
        case .getTime:      try ttlGetTime(isDate: false)
        case .getDir:       try ttlGetDir()
        case .setDir:       try ttlSetDir()
        case .getEnv:       try ttlGetEnv()
        case .setEnv:       try ttlSetEnv()
        case .expandEnv:    try ttlExpandEnv()
        case .getTitle:     try ttlGetTitle()
        case .getVer:       try ttlGetVer()
        case .getHostname:  try ttlGetHostname()
        case .getTTDir:     try ttlGetTTDir()
        case .getSpecialFolder: try ttlGetSpecialFolder()
        case .getIPv4Addr:  try ttlGetIPv4Addr()
        case .getIPv6Addr:  try ttlGetIPv6Addr()
        case .getFileAttr:  try ttlGetFileAttr()
        case .setFileAttr:  try ttlSetFileAttr()
        case .getModemStatus: try ttlGetModemStatus()
        case .getTTPos:     try ttlGetTTPos()
        case .uptime:       try ttlUptime()
        case .random:       try ttlRandom()

        // Terminal operations
        case .connect:      try ttlConnect()
        case .disconnect:   try ttlDisconnect()
        case .testLink:     try ttlTestLink()
        case .clearScreen:  try ttlClearScreen()
        case .dispStr:      try ttlDispStr()
        case .setTitle:     try ttlSetTitle()
        case .setEcho:      try ttlSetEcho()
        case .setSync:      try ttlSetSync()
        case .show:         try ttlShow()
        case .showTT:       try ttlShowTT()
        case .closeTT:      try ttlCloseTT()
        case .enableKeyb:   try ttlEnableKeyb()
        case .setBaud:      try ttlSetBaud()
        case .setFlowCtrl:  try ttlSetFlowCtrl()
        case .setDtr:       try ttlSetDtr()
        case .setRts:       try ttlSetRts()

        // Clipboard
        case .clipb2Var:    try ttlClipb2Var()
        case .var2Clipb:    try ttlVar2Clipb()

        // Path operations
        case .makePath:     try ttlMakePath()
        case .basename:     try ttlBasename()
        case .dirname:      try ttlDirname()
        case .changeDir:    try ttlChangeDir()

        // Logging
        case .logOpen:      try ttlLogOpen()
        case .logClose:     try ttlLogClose()
        case .logPause:     try ttlLogPause()
        case .logStart:     try ttlLogStart()
        case .logWrite:     try ttlLogWrite()
        case .logInfo:      try ttlLogInfo()
        case .logRotate:    try ttlLogRotate()
        case .logAutoClose: try ttlLogAutoClose()

        // Exec
        case .exec:         try ttlExec()
        case .execCmnd:     try ttlExecCmnd()
        case .setExitCode:  try ttlSetExitCode()

        // Bit operations
        case .rotateL:      try ttlRotateLeft()
        case .rotateR:      try ttlRotateRight()

        // Checksum/CRC
        case .crc16:        try ttlDoChecksum(type: .crc16)
        case .crc16File:    try ttlDoChecksumFile(type: .crc16)
        case .crc32:        try ttlDoChecksum(type: .crc32)
        case .crc32File:    try ttlDoChecksumFile(type: .crc32)
        case .checksum8:    try ttlDoChecksum(type: .checksum8)
        case .checksum8File: try ttlDoChecksumFile(type: .checksum8)
        case .checksum16:   try ttlDoChecksum(type: .checksum16)
        case .checksum16File: try ttlDoChecksumFile(type: .checksum16)
        case .checksum32:   try ttlDoChecksum(type: .checksum32)
        case .checksum32File: try ttlDoChecksumFile(type: .checksum32)

        // Misc
        case .beep:         try ttlBeep()
        case .setDate:      try ttlSetDate()
        case .setTime:      try ttlSetTime()
        case .setDlgPos:    try ttlSetDlgPos()
        case .setDebug:     try ttlSetDebug()
        case .regexOption:  try ttlRegexOption()

        // Password (stub - macOS Keychain)
        case .getPassword:  try ttlGetPassword()
        case .setPassword:  try ttlSetPassword()
        case .delPassword:  try ttlDelPassword()
        case .isPassword:   try ttlIsPassword()
        case .getPassword2: try ttlGetPassword2()
        case .setPassword2: try ttlSetPassword2()
        case .delPassword2: try ttlDelPassword2()
        case .isPassword2:  try ttlIsPassword2()

        // Broadcast/multicast (stub)
        case .sendBroadcast:     try ttlSendBroadcast(crlf: false)
        case .sendlnBroadcast:   try ttlSendBroadcast(crlf: true)
        case .sendMulticast:     try ttlSendMulticast(crlf: false)
        case .sendlnMulticast:   try ttlSendMulticast(crlf: true)
        case .setMulticastName:  try ttlSetMulticastName()

        // File transfer (stubs)
        case .xmodemRecv, .xmodemSend, .ymodemRecv, .ymodemSend,
             .zmodemRecv, .zmodemSend, .bplusRecv, .bplusSend,
             .kmtFinish, .kmtGet, .kmtRecv, .kmtSend,
             .quickVANRecv, .quickVANSend, .scpRecv, .scpSend,
             .recvFile:
            throw TTLError.notSupported

        // Others
        case .then:         break  // handled by if
        case .loadKeyMap, .restoreSetup, .cygConnect,
             .callMenu, .setSerialDelayChar, .setSerialDelayLine:
            throw TTLError.notSupported

        default:
            throw TTLError.notSupported
        }
    }

    // MARK: - Control Flow Commands

    private func checkThen() throws -> Bool {
        let saved = parser.linePtr
        if let cmd = parser.getReservedWord(), cmd == .then {
            return true
        }
        parser.linePtr = saved
        return false
    }

    private func checkElseIf() throws -> Int {
        let val = try parser.getIntExpression()
        guard try checkThen() else { throw TTLError.syntax }
        return val
    }

    private func ttlIf() throws {
        let val = try parser.getIntExpression()

        // Check for "then" (block form)
        if try checkThen() {
            ifNest += 1
            if val == 0 {
                elseFlag = 1
            }
        } else {
            // Single-line if: execute rest of line if true
            if val != 0 {
                parseAgain = true
                // The rest of the line will be parsed as the next command
            }
        }
    }

    private func ttlElse() throws {
        guard ifNest >= 1 else { throw TTLError.invalidCtl }
        ifNest -= 1
        endIfFlag = 1
    }

    private func ttlElseIf() throws {
        guard ifNest >= 1 else { throw TTLError.invalidCtl }
        let val = try parser.getIntExpression()
        guard try checkThen() else { throw TTLError.syntax }
        if val != 0 {
            ifNest -= 1
            // Continue executing
        } else {
            // Keep skipping with elseFlag
        }
    }

    private func ttlEndIf() throws {
        guard ifNest >= 1 else { throw TTLError.invalidCtl }
        ifNest -= 1
    }

    private func ttlGoto() throws {
        guard let labName = parser.getLabelName() else { throw TTLError.labelReq }
        guard let (type, id) = parser.checkVar(labName), type == .label else {
            // Try scanning forward for the label
            let savedLine = parser.currentLine
            let savedPtr = parser.linePtr
            var found = false
            for i in 0..<parser.lines.count {
                let line = parser.lines[i].trimmingCharacters(in: .whitespaces)
                if line.hasPrefix(":") {
                    let lbl = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: .whitespaces).first ?? ""
                    if lbl.caseInsensitiveCompare(labName) == .orderedSame {
                        if parser.checkVar(lbl) == nil {
                            parser.newLabVar(lbl, position: i, level: parser.scopeLevel)
                        }
                        parser.currentLine = i + 1
                        found = true
                        break
                    }
                }
            }
            if !found {
                parser.currentLine = savedLine
                parser.linePtr = savedPtr
                throw TTLError.labelReq
            }
            return
        }
        let label = parser.variables[id].label
        parser.currentLine = label.position + 1
    }

    private func ttlCall() throws {
        guard let labName = parser.getLabelName() else { throw TTLError.labelReq }

        // Find label (search if needed)
        var labelId: Int = -1
        if let (type, id) = parser.checkVar(labName), type == .label {
            labelId = id
        } else {
            // Scan for label
            for i in 0..<parser.lines.count {
                let line = parser.lines[i].trimmingCharacters(in: .whitespaces)
                if line.hasPrefix(":") {
                    let lbl = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: .whitespaces).first ?? ""
                    if lbl.caseInsensitiveCompare(labName) == .orderedSame {
                        labelId = parser.newLabVar(lbl, position: i, level: parser.scopeLevel)
                        break
                    }
                }
            }
        }

        guard labelId >= 0 else { throw TTLError.labelReq }

        // Push return address
        let frame = TTLCallFrame(
            lineIndex: parser.currentLine,
            level: parser.scopeLevel,
            fileIndex: 0
        )
        parser.callStack.append(frame)
        parser.scopeLevel += 1

        // Jump to label
        let label = parser.variables[labelId].label
        parser.currentLine = label.position + 1
    }

    private func ttlReturn() throws {
        guard !parser.callStack.isEmpty else { throw TTLError.invalidCtl }
        let frame = parser.callStack.removeLast()
        parser.currentLine = frame.lineIndex
        parser.scopeLevel = frame.level
        parser.delLabVar(level: parser.scopeLevel + 1)
    }

    private func ttlInclude() throws {
        let filename = try parser.getStrExpression()
        let url: URL
        if filename.hasPrefix("/") {
            url = URL(fileURLWithPath: filename)
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            url = URL(fileURLWithPath: currentDir).appendingPathComponent(filename)
        }

        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw TTLError.cantOpen
        }

        // Push current file state
        parser.fileStack.append((lines: parser.lines, lineIndex: parser.currentLine))
        parser.lines = source.components(separatedBy: .newlines)
        parser.currentLine = 0

        // Pre-scan labels in included file
        prescanLabels()
    }

    private func ttlEnd() throws {
        parser.status = .end
    }

    private func ttlExit() throws {
        // If in included file, return to parent
        if !parser.fileStack.isEmpty {
            let state = parser.fileStack.removeLast()
            parser.lines = state.lines
            parser.currentLine = state.lineIndex
        } else {
            parser.status = .end
        }
    }

    private func ttlFor() throws {
        let varId = try parser.getIntVar()
        let start = try parser.getIntExpression()
        let end = try parser.getIntExpression()

        // Check if this is first entry or loop-back from next
        if let lastLoop = parser.loopStack.last,
           lastLoop.type == .for_ && lastLoop.lineIndex == parser.currentLine - 1 {
            // Loop-back iteration
            var val = parser.getIntVal(id: varId)
            if start <= end {
                val += lastLoop.step
            } else {
                val -= lastLoop.step
            }
            parser.setIntVal(id: varId, value: val)

            if (start <= end && val > end) || (start > end && val < end) {
                // End of for loop
                parser.loopStack.removeLast()
            }
        } else {
            // First entry
            parser.setIntVal(id: varId, value: start)
            let frame = TTLLoopFrame(
                type: .for_,
                lineIndex: parser.currentLine - 1,
                varId: varId,
                limit: end,
                step: 1
            )
            parser.loopStack.append(frame)

            if start == end {
                // Single iteration, will end on next
            }
        }
    }

    private func ttlNext() throws {
        guard !parser.loopStack.isEmpty else { throw TTLError.invalidCtl }
        guard let loop = parser.loopStack.last, loop.type == .for_ else {
            throw TTLError.invalidCtl
        }

        let val = parser.getIntVal(id: loop.varId)
        let atEnd: Bool
        if loop.limit >= parser.getIntVal(id: loop.varId) {
            // Count up: check against limit using current + step
            atEnd = (val + loop.step) > loop.limit
        } else {
            atEnd = (val - loop.step) < loop.limit
        }

        if atEnd {
            parser.loopStack.removeLast()
        } else {
            // Increment/decrement and loop back
            let newVal: Int
            if loop.limit >= val {
                newVal = val + loop.step
            } else {
                newVal = val - loop.step
            }
            parser.setIntVal(id: loop.varId, value: newVal)
            parser.currentLine = loop.lineIndex + 1
        }
    }

    private func ttlWhile(mode: Bool) throws {
        var val = 1
        if parser.checkParameterGiven() {
            val = try parser.getIntExpression()
        }

        let conditionMet = (val != 0) == mode
        let loopType: TTLLoopType = mode ? .while_ : .until

        // endwhileからループバックした場合は既にフレームがあるので追加しない
        if let lastLoop = parser.loopStack.last,
           lastLoop.type == loopType && lastLoop.lineIndex == parser.currentLine - 1 {
            // ループバック: 条件を再評価し、偽ならフレームを除去してスキップ
            if !conditionMet {
                parser.loopStack.removeLast()
                endWhileFlag = 1
            }
        } else {
            // 初回: 条件が真ならフレームをプッシュ、偽ならスキップ
            if conditionMet {
                let frame = TTLLoopFrame(
                    type: loopType,
                    lineIndex: parser.currentLine - 1,
                    varId: 0, limit: 0, step: 0
                )
                parser.loopStack.append(frame)
            } else {
                endWhileFlag = 1
            }
        }
    }

    private func ttlEndWhile(mode: Bool) throws {
        guard !parser.loopStack.isEmpty else { throw TTLError.invalidCtl }

        // whileの先頭にジャンプバックし、条件再評価はttlWhileで行う
        // lineIndex はwhile行自体を指すので、そこに戻す（getNewLineがcurrentLine行を読んで+1する）
        let loop = parser.loopStack.last!
        parser.currentLine = loop.lineIndex
    }

    private func ttlDo() throws {
        let frame = TTLLoopFrame(
            type: .do_,
            lineIndex: parser.currentLine - 1,
            varId: 0, limit: 0, step: 0
        )
        parser.loopStack.append(frame)
    }

    private func ttlLoop() throws {
        guard !parser.loopStack.isEmpty else { throw TTLError.invalidCtl }

        var shouldLoop = true

        // Check for optional while/until condition
        if let cmd = parser.getReservedWord() {
            if cmd == .while_ {
                let val = try parser.getIntExpression()
                shouldLoop = val != 0
            } else if cmd == .until {
                let val = try parser.getIntExpression()
                shouldLoop = val == 0
            }
        }

        if shouldLoop {
            let loop = parser.loopStack.last!
            parser.currentLine = loop.lineIndex + 1
        } else {
            parser.loopStack.removeLast()
        }
    }

    private func ttlBreak() throws {
        guard !parser.loopStack.isEmpty else { throw TTLError.invalidCtl }
        breakFlag = 1
    }

    private func ttlContinue() throws {
        guard !parser.loopStack.isEmpty else { throw TTLError.invalidCtl }
        breakFlag = 1
        continueFlag = true
    }

    private func ttlIfDefined() throws {
        guard let name = parser.getIdentifier() else { throw TTLError.syntax }
        let result = parser.checkVar(name) != nil ? 1 : 0
        parser.setResult(result)
    }

    // MARK: - Send/Receive Commands

    private func ttlSend() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }
        var text = ""
        while parser.checkParameterGiven() {
            if let strResult = parser.getString() {
                switch strResult {
                case .success(let s): text += s
                case .failure(let e): throw e
                }
            } else {
                let result = try parser.getExpression()
                switch result {
                case .integer(let v):
                    text += String(UnicodeScalar(UInt8(v & 0xFF)))
                case .string(let id):
                    text += parser.getStrVal(id: id)
                default: throw TTLError.typeMismatch
                }
            }
        }
        delegate?.ttlSendString(text)
    }

    private func ttlSendLn() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }
        var text = ""
        while parser.checkParameterGiven() {
            if let strResult = parser.getString() {
                switch strResult {
                case .success(let s): text += s
                case .failure(let e): throw e
                }
            } else {
                let result = try parser.getExpression()
                switch result {
                case .integer(let v):
                    text += String(UnicodeScalar(UInt8(v & 0xFF)))
                case .string(let id):
                    text += parser.getStrVal(id: id)
                default: throw TTLError.typeMismatch
                }
            }
        }
        delegate?.ttlSendLine(text)
    }

    private func ttlSendText() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }
        let text = try parser.getStrExpression()
        delegate?.ttlSendString(text)
    }

    private func ttlSendBinary() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }
        let text = try parser.getStrExpression()
        var data = Data()
        // Parse hex string: pairs of hex chars
        var i = text.startIndex
        while i < text.endIndex {
            let next = text.index(after: i)
            if next < text.endIndex {
                let hexPair = String(text[i...next])
                if let byte = UInt8(hexPair, radix: 16) {
                    data.append(byte)
                }
                i = text.index(after: next)
            } else {
                break
            }
        }
        delegate?.ttlSendData(data)
    }

    private func ttlSendBreak() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }
        delegate?.ttlSendBreak()
    }

    private func ttlSendKCode() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }
        let code = try parser.getIntExpression()
        let data = Data([UInt8(code & 0xFF)])
        delegate?.ttlSendData(data)
    }

    private func ttlSendFile() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }
        let filename = try parser.getStrExpression()
        guard let data = FileManager.default.contents(atPath: filename) else {
            throw TTLError.cantOpen
        }
        delegate?.ttlSendData(data)
    }

    private func ttlRecvLn() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }
        let buf = delegate?.ttlGetReceivedData(clear: false) ?? ""

        if let nlRange = buf.rangeOfCharacter(from: CharacterSet.newlines) {
            let line = String(buf[buf.startIndex..<nlRange.lowerBound])
            parser.setInputStr(line)
            // Clear consumed data
            _ = delegate?.ttlGetReceivedData(clear: true)
            parser.setResult(0)
        } else {
            parser.setResult(1)  // No complete line yet
        }
    }

    private func ttlFlushRecv() throws {
        delegate?.ttlFlushReceiveBuffer()
        receiveBuffer = ""
    }

    // MARK: - Wait Commands

    private func ttlWait(ln: Bool) throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }

        waitStrings.removeAll()
        waitRegex = false
        waitLn = ln

        // Parse up to 10 wait patterns
        for _ in 0..<10 {
            guard parser.checkParameterGiven() else { break }
            let s = try parser.getStrExpression()
            waitStrings.append(s)
        }

        guard !waitStrings.isEmpty else { throw TTLError.syntax }

        // Get timeout from system variables
        let timeout = parser.getIntVal(id: parser.timeoutVarId)
        let mtimeout = parser.getIntVal(id: parser.mtimeoutVarId)
        timeLimit = Double(timeout) + Double(mtimeout) / 1000.0
        timeStart = Date()
        receiveBuffer = ""

        parser.status = ln ? .waitLn : .wait
        parser.setResult(0)  // Will be set when matched
    }

    private func ttlWaitRegex() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }

        waitStrings.removeAll()
        waitRegex = true
        waitLn = false

        for _ in 0..<10 {
            guard parser.checkParameterGiven() else { break }
            let s = try parser.getStrExpression()
            waitStrings.append(s)
        }

        guard !waitStrings.isEmpty else { throw TTLError.syntax }

        let timeout = parser.getIntVal(id: parser.timeoutVarId)
        let mtimeout = parser.getIntVal(id: parser.mtimeoutVarId)
        timeLimit = Double(timeout) + Double(mtimeout) / 1000.0
        timeStart = Date()
        receiveBuffer = ""

        parser.status = .wait
        parser.setResult(0)
    }

    private func ttlWaitN() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }
        let n = try parser.getIntExpression()
        guard n > 0 else { throw TTLError.syntax }

        waitStrings = [String(n)]  // Store count as string
        waitRegex = false
        waitLn = false

        let timeout = parser.getIntVal(id: parser.timeoutVarId)
        let mtimeout = parser.getIntVal(id: parser.mtimeoutVarId)
        timeLimit = Double(timeout) + Double(mtimeout) / 1000.0
        timeStart = Date()
        receiveBuffer = ""

        parser.status = .waitN
        parser.setResult(0)
    }

    private func ttlWaitRecv() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }
        let pattern = try parser.getStrExpression()
        _ = try parser.getIntExpression()
        let timeout = try parser.getIntExpression()

        waitStrings = [pattern]
        waitRegex = false
        waitLn = false
        timeLimit = Double(timeout)
        timeStart = Date()
        receiveBuffer = ""

        parser.status = .wait
        parser.setResult(0)
    }

    private func ttlWait4All() throws {
        guard delegate?.ttlIsConnected() == true else { throw TTLError.linkFirst }

        waitStrings.removeAll()
        waitRegex = false
        waitLn = false

        for _ in 0..<10 {
            guard parser.checkParameterGiven() else { break }
            let s = try parser.getStrExpression()
            waitStrings.append(s)
        }

        guard !waitStrings.isEmpty else { throw TTLError.syntax }

        let timeout = parser.getIntVal(id: parser.timeoutVarId)
        let mtimeout = parser.getIntVal(id: parser.mtimeoutVarId)
        timeLimit = Double(timeout) + Double(mtimeout) / 1000.0
        timeStart = Date()
        receiveBuffer = ""

        parser.status = .wait4all
        parser.setResult(0)
    }

    private func ttlWaitEvent() throws {
        let timeout = parser.getIntVal(id: parser.timeoutVarId)
        let mtimeout = parser.getIntVal(id: parser.mtimeoutVarId)
        timeLimit = Double(timeout) + Double(mtimeout) / 1000.0
        timeStart = Date()

        parser.status = .wait
        parser.setResult(0)
    }

    // Wait state checking (called on timer)
    private func scheduleWaitCheck() {
        execTimer?.invalidate()
        execTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            self?.checkWaitState()
        }
    }

    private func checkWaitState() {
        // Check timeout
        if let start = timeStart, timeLimit > 0 {
            if Date().timeIntervalSince(start) >= timeLimit {
                parser.setResult(0)  // Timeout
                parser.status = .run
                scheduleExec()
                return
            }
        }

        // Get new data
        let newData = delegate?.ttlGetReceivedData(clear: true) ?? ""
        if !newData.isEmpty {
            receiveBuffer += newData
        }

        switch parser.status {
        case .wait, .waitLn:
            checkWaitMatch()
        case .waitN:
            checkWaitN()
        case .wait4all:
            checkWait4All()
        default:
            break
        }

        if parser.status != .run {
            scheduleWaitCheck()
        }
    }

    private func checkWaitMatch() {
        for (i, pattern) in waitStrings.enumerated() {
            if waitRegex {
                let options: NSRegularExpression.Options = regexOptionCaseInsensitive ? [.caseInsensitive] : []
                if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                    let range = NSRange(receiveBuffer.startIndex..., in: receiveBuffer)
                    if let match = regex.firstMatch(in: receiveBuffer, range: range) {
                        let matchedStr = String(receiveBuffer[Range(match.range, in: receiveBuffer)!])
                        parser.setMatchStr(matchedStr)

                        // Set group matches
                        for g in 1..<match.numberOfRanges {
                            if let gRange = Range(match.range(at: g), in: receiveBuffer) {
                                let groupStr = String(receiveBuffer[gRange])
                                let varName = "groupmatchstr\(g)"
                                if let (_, gid) = parser.checkVar(varName) {
                                    parser.setStrVal(id: gid, value: groupStr)
                                } else {
                                    parser.newStrVar(varName, value: groupStr)
                                }
                            }
                        }

                        parser.setInputStr(receiveBuffer)
                        parser.setResult(i + 1)
                        parser.status = .run
                        receiveBuffer = ""
                        scheduleExec()
                        return
                    }
                }
            } else {
                if receiveBuffer.contains(pattern) {
                    parser.setInputStr(receiveBuffer)
                    parser.setResult(i + 1)
                    parser.status = .run
                    receiveBuffer = ""
                    scheduleExec()
                    return
                }
            }
        }
    }

    private func checkWaitN() {
        guard let countStr = waitStrings.first, let count = Int(countStr) else { return }
        if receiveBuffer.count >= count {
            parser.setInputStr(String(receiveBuffer.prefix(count)))
            parser.setResult(1)
            parser.status = .run
            receiveBuffer = String(receiveBuffer.dropFirst(count))
            scheduleExec()
        }
    }

    private func checkWait4All() {
        var allFound = true
        for pattern in waitStrings {
            if !receiveBuffer.contains(pattern) {
                allFound = false
                break
            }
        }
        if allFound {
            parser.setInputStr(receiveBuffer)
            parser.setResult(1)
            parser.status = .run
            receiveBuffer = ""
            scheduleExec()
        }
    }

    // MARK: - Pause Commands

    private func ttlPause() throws {
        let seconds = try parser.getIntExpression()
        guard seconds > 0 else { return }

        parser.status = .pause
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: Double(seconds), repeats: false) { [weak self] _ in
            self?.parser.status = .run
            self?.scheduleExec()
        }
    }

    private func ttlMilliPause() throws {
        let ms = try parser.getIntExpression()
        guard ms > 0 else { return }

        parser.status = .pause
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: Double(ms) / 1000.0, repeats: false) { [weak self] _ in
            self?.parser.status = .run
            self?.scheduleExec()
        }
    }

    // MARK: - String Operation Commands

    private func ttlStrLen() throws {
        let s = try parser.getStrExpression()
        parser.setResult(s.count)
    }

    private func ttlStrConcat() throws {
        let varId = try parser.getStrVar()
        let s2 = try parser.getStrExpression()
        let s1 = parser.getStrVal(id: varId)
        parser.setStrVal(id: varId, value: s1 + s2)
    }

    private func ttlStrCopy() throws {
        let src = try parser.getStrExpression()
        let start = try parser.getIntExpression()
        let len = try parser.getIntExpression()
        let varId = try parser.getStrVar()

        let startIdx = max(0, start - 1) // TTL uses 1-based indexing
        let s = src
        if startIdx < s.count {
            let from = s.index(s.startIndex, offsetBy: startIdx)
            let to = s.index(from, offsetBy: min(len, s.count - startIdx))
            parser.setStrVal(id: varId, value: String(s[from..<to]))
        } else {
            parser.setStrVal(id: varId, value: "")
        }
    }

    private func ttlStrCompare() throws {
        let s1 = try parser.getStrExpression()
        let s2 = try parser.getStrExpression()
        let cmp = s1.compare(s2)
        switch cmp {
        case .orderedAscending:  parser.setResult(-1)
        case .orderedSame:       parser.setResult(0)
        case .orderedDescending: parser.setResult(1)
        }
    }

    private func ttlStrScan() throws {
        let haystack = try parser.getStrExpression()
        let needle = try parser.getStrExpression()
        if let range = haystack.range(of: needle) {
            let pos = haystack.distance(from: haystack.startIndex, to: range.lowerBound) + 1
            parser.setResult(pos)
        } else {
            parser.setResult(0)
        }
    }

    private func ttlStrMatch() throws {
        let s = try parser.getStrExpression()
        let pattern = try parser.getStrExpression()

        let options: NSRegularExpression.Options = regexOptionCaseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            parser.setResult(-1)
            return
        }

        let range = NSRange(s.startIndex..., in: s)
        if let match = regex.firstMatch(in: s, range: range) {
            let pos = match.range.location + 1
            parser.setResult(pos)

            if let matchRange = Range(match.range, in: s) {
                parser.setMatchStr(String(s[matchRange]))
            }

            for g in 1..<match.numberOfRanges {
                let varName = "groupmatchstr\(g)"
                if let gRange = Range(match.range(at: g), in: s) {
                    let groupStr = String(s[gRange])
                    if let (_, gid) = parser.checkVar(varName) {
                        parser.setStrVal(id: gid, value: groupStr)
                    } else {
                        parser.newStrVar(varName, value: groupStr)
                    }
                }
            }
        } else {
            parser.setResult(0)
        }
    }

    private func ttlStr2Int() throws {
        let s = try parser.getStrExpression()
        let varId = try parser.getIntVar()

        let trimmed = s.trimmingCharacters(in: .whitespaces)
        var val: Int? = nil
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            val = Int(trimmed.dropFirst(2), radix: 16)
        } else if trimmed.hasPrefix("$") {
            val = Int(trimmed.dropFirst(), radix: 16)
        } else {
            val = Int(trimmed)
        }

        if let v = val {
            parser.setIntVal(id: varId, value: v)
            parser.setResult(1)
        } else {
            parser.setResult(0)
        }
    }

    private func ttlInt2Str() throws {
        let varId = try parser.getStrVar()
        let val = try parser.getIntExpression()
        parser.setStrVal(id: varId, value: String(val))
    }

    private func ttlStr2Code() throws {
        let s = try parser.getStrExpression()
        let varId = try parser.getIntVar()
        var code: Int = 0
        for (i, ch) in s.utf8.prefix(4).enumerated() {
            code = code | (Int(ch) << ((3 - i) * 8))
        }
        parser.setIntVal(id: varId, value: code)
    }

    private func ttlCode2Str() throws {
        let code = try parser.getIntExpression()
        let varId = try parser.getStrVar()
        var s = ""
        for i in stride(from: 24, through: 0, by: -8) {
            let byte = UInt8((code >> i) & 0xFF)
            if byte > 0 { s.append(Character(UnicodeScalar(byte))) }
        }
        parser.setStrVal(id: varId, value: s)
    }

    private func ttlStrInsert() throws {
        let varId = try parser.getStrVar()
        let pos = try parser.getIntExpression()
        let insertStr = try parser.getStrExpression()
        var s = parser.getStrVal(id: varId)
        let idx = max(0, min(pos - 1, s.count))
        let insertIdx = s.index(s.startIndex, offsetBy: idx)
        s.insert(contentsOf: insertStr, at: insertIdx)
        parser.setStrVal(id: varId, value: s)
    }

    private func ttlStrRemove() throws {
        let varId = try parser.getStrVar()
        let pos = try parser.getIntExpression()
        let len = try parser.getIntExpression()
        var s = parser.getStrVal(id: varId)
        let startIdx = max(0, pos - 1)
        guard startIdx < s.count else { return }
        let from = s.index(s.startIndex, offsetBy: startIdx)
        let removeLen = min(len, s.count - startIdx)
        let to = s.index(from, offsetBy: removeLen)
        s.removeSubrange(from..<to)
        parser.setStrVal(id: varId, value: s)
    }

    private func ttlStrReplace() throws {
        let varId = try parser.getStrVar()
        let pattern = try parser.getStrExpression()
        let replacement = try parser.getStrExpression()

        let s = parser.getStrVal(id: varId)
        let options: NSRegularExpression.Options = regexOptionCaseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            parser.setResult(-1)
            return
        }

        let range = NSRange(s.startIndex..., in: s)
        if regex.firstMatch(in: s, range: range) != nil {
            let result = regex.stringByReplacingMatches(in: s, range: range, withTemplate: replacement)
            parser.setStrVal(id: varId, value: result)
            parser.setResult(1)
        } else {
            parser.setResult(0)
        }
    }

    private func ttlStrSpecial() throws {
        let varId = try parser.getStrVar()
        var s: String
        if parser.checkParameterGiven() {
            s = try parser.getStrExpression()
        } else {
            s = parser.getStrVal(id: varId)
        }
        // Restore escape sequences
        s = s.replacingOccurrences(of: "\\n", with: "\n")
        s = s.replacingOccurrences(of: "\\r", with: "\r")
        s = s.replacingOccurrences(of: "\\t", with: "\t")
        s = s.replacingOccurrences(of: "\\\\", with: "\\")
        s = s.replacingOccurrences(of: "\\\"", with: "\"")
        s = s.replacingOccurrences(of: "\\'", with: "'")
        parser.setStrVal(id: varId, value: s)
    }

    private func ttlStrTrim() throws {
        let varId = try parser.getStrVar()
        var trimType = 0 // 0=both, 1=left, 2=right
        var trimChars = " \t"
        if parser.checkParameterGiven() {
            trimChars = try parser.getStrExpression()
        }
        if parser.checkParameterGiven() {
            trimType = try parser.getIntExpression()
        }
        var s = parser.getStrVal(id: varId)
        let charSet = CharacterSet(charactersIn: trimChars)
        switch trimType {
        case 1: // left
            while let first = s.unicodeScalars.first, charSet.contains(first) {
                s.removeFirst()
            }
        case 2: // right
            while let last = s.unicodeScalars.last, charSet.contains(last) {
                s.removeLast()
            }
        default: // both
            while let first = s.unicodeScalars.first, charSet.contains(first) {
                s.removeFirst()
            }
            while let last = s.unicodeScalars.last, charSet.contains(last) {
                s.removeLast()
            }
        }
        parser.setStrVal(id: varId, value: s)
    }

    private func ttlStrSplit() throws {
        let src = try parser.getStrExpression()
        let delimiter = try parser.getStrExpression()

        let parts = src.components(separatedBy: delimiter)
        parser.setResult(parts.count)

        for (i, part) in parts.prefix(9).enumerated() {
            let varName = "groupmatchstr\(i + 1)"
            if let (_, gid) = parser.checkVar(varName) {
                parser.setStrVal(id: gid, value: part)
            } else {
                parser.newStrVar(varName, value: part)
            }
        }
    }

    private func ttlStrJoin() throws {
        let varId = try parser.getStrVar()
        let delimiter = try parser.getStrExpression()
        var parts: [String] = []
        while parser.checkParameterGiven() {
            let s = try parser.getStrExpression()
            parts.append(s)
        }
        parser.setStrVal(id: varId, value: parts.joined(separator: delimiter))
    }

    private func ttlToLower() throws {
        let varId = try parser.getStrVar()
        let s = parser.getStrVal(id: varId)
        parser.setStrVal(id: varId, value: s.lowercased())
    }

    private func ttlToUpper() throws {
        let varId = try parser.getStrVar()
        let s = parser.getStrVal(id: varId)
        parser.setStrVal(id: varId, value: s.uppercased())
    }

    private func ttlSprintf(mode: Int) throws {
        let varId: Int
        if mode == 1 {
            varId = try parser.getStrVar()
        } else {
            varId = parser.inputStrVarId
        }

        let fmt = try parser.getStrExpression()
        var args: [Any] = []
        while parser.checkParameterGiven() {
            if let strResult = parser.getString() {
                switch strResult {
                case .success(let s): args.append(s)
                case .failure(let e): throw e
                }
            } else {
                let result = try parser.getExpression()
                switch result {
                case .integer(let v): args.append(v)
                case .string(let id): args.append(parser.getStrVal(id: id))
                default: break
                }
            }
        }

        let result = formatString(fmt, args: args)
        parser.setStrVal(id: varId, value: result)
    }

    /// Simple sprintf implementation supporting %d, %s, %x, %o, %c, %%
    private func formatString(_ fmt: String, args: [Any]) -> String {
        var result = ""
        var argIdx = 0
        let chars = Array(fmt)
        var i = 0

        while i < chars.count {
            if chars[i] == "%" && i + 1 < chars.count {
                i += 1
                // Parse width/flags
                var width = 0
                var zeroPad = false
                var leftAlign = false

                if chars[i] == "-" { leftAlign = true; i += 1 }
                if i < chars.count && chars[i] == "0" { zeroPad = true; i += 1 }
                while i < chars.count && chars[i].isNumber {
                    width = width * 10 + Int(String(chars[i]))!
                    i += 1
                }

                guard i < chars.count else { break }
                let spec = chars[i]
                i += 1

                switch spec {
                case "d", "i":
                    let val = argIdx < args.count ? (args[argIdx] as? Int ?? 0) : 0
                    argIdx += 1
                    var s = String(val)
                    while s.count < width { s = (zeroPad ? "0" : " ") + s }
                    result += s
                case "s":
                    let val = argIdx < args.count ? "\(args[argIdx])" : ""
                    argIdx += 1
                    var s = val
                    if leftAlign { while s.count < width { s += " " } }
                    else { while s.count < width { s = " " + s } }
                    result += s
                case "x", "X":
                    let val = argIdx < args.count ? (args[argIdx] as? Int ?? 0) : 0
                    argIdx += 1
                    var s = spec == "X" ? String(val, radix: 16, uppercase: true)
                                        : String(val, radix: 16)
                    while s.count < width { s = (zeroPad ? "0" : " ") + s }
                    result += s
                case "o":
                    let val = argIdx < args.count ? (args[argIdx] as? Int ?? 0) : 0
                    argIdx += 1
                    var s = String(val, radix: 8)
                    while s.count < width { s = (zeroPad ? "0" : " ") + s }
                    result += s
                case "c":
                    let val = argIdx < args.count ? (args[argIdx] as? Int ?? 0) : 0
                    argIdx += 1
                    result += String(UnicodeScalar(val & 0xFF)!)
                case "%":
                    result += "%"
                default:
                    result += "%" + String(spec)
                }
            } else {
                result.append(chars[i])
                i += 1
            }
        }
        return result
    }

    // MARK: - File I/O Commands

    private func handlePut(_ fh: FileHandle) -> Int {
        for i in 0..<maxFileHandles {
            if fileHandles[i] == nil {
                fileHandles[i] = fh
                filePointers[i] = 0
                return i
            }
        }
        return -1
    }

    private func handleGet(_ index: Int) -> FileHandle? {
        guard index >= 0 && index < maxFileHandles else { return nil }
        return fileHandles[index]
    }

    private func handleFree(_ index: Int) {
        guard index >= 0 && index < maxFileHandles else { return }
        fileHandles[index] = nil
        filePointers[index] = 0
        filePaths[index] = ""
    }

    private func closeAllFiles() {
        for i in 0..<maxFileHandles {
            if let fh = fileHandles[i] {
                try? fh.close()
                fileHandles[i] = nil
            }
        }
    }

    private func ttlFileOpen() throws {
        let varId = try parser.getIntVar()
        let filename = try parser.getStrExpression()
        let appendMode = try parser.getIntExpression()
        var readOnly = false
        if parser.checkParameterGiven() {
            readOnly = try parser.getIntExpression() != 0
        }

        let path = resolvePath(filename)

        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            if readOnly {
                parser.setIntVal(id: varId, value: -1)
                parser.setResult(-1)
                return
            }
            // Create parent directories if needed
            let dir = (path as NSString).deletingLastPathComponent
            if !dir.isEmpty && !fm.fileExists(atPath: dir) {
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
            if !fm.createFile(atPath: path, contents: nil) {
                parser.setIntVal(id: varId, value: -1)
                parser.setResult(-1)
                return
            }
        }

        let fh: FileHandle?
        if readOnly {
            fh = FileHandle(forReadingAtPath: path)
        } else {
            fh = FileHandle(forUpdatingAtPath: path)
        }

        guard let fileHandle = fh else {
            parser.setIntVal(id: varId, value: -1)
            parser.setResult(-1)
            return
        }

        if !readOnly {
            if appendMode != 0 {
                fileHandle.seekToEndOfFile()
            } else {
                // Truncate file for write mode (non-append)
                fileHandle.truncateFile(atOffset: 0)
            }
        }

        let idx = handlePut(fileHandle)
        if idx < 0 {
            try? fileHandle.close()
            parser.setIntVal(id: varId, value: -1)
            return
        }
        filePaths[idx] = path
        parser.setIntVal(id: varId, value: idx)
        parser.setResult(0)
    }

    private func ttlFileClose() throws {
        let fhi = try parser.getIntExpression()
        guard let fh = handleGet(fhi) else { return }
        try? fh.close()
        handleFree(fhi)
    }

    private func ttlFileReadln() throws {
        let fhi = try parser.getIntExpression()
        let varId = try parser.getStrVar()

        guard let fh = handleGet(fhi) else { throw TTLError.syntax }

        var line = ""
        var eof = false

        while true {
            let data = fh.readData(ofLength: 1)
            if data.isEmpty {
                eof = true
                break
            }
            let byte = data[0]
            if byte == 0x0A { // LF
                break
            } else if byte == 0x0D { // CR
                // Check for CRLF
                let next = fh.readData(ofLength: 1)
                if !next.isEmpty && next[0] != 0x0A {
                    // Not CRLF, seek back
                    fh.seek(toFileOffset: fh.offsetInFile - 1)
                }
                break
            } else {
                line.append(Character(UnicodeScalar(byte)))
            }
        }

        parser.setStrVal(id: varId, value: line)
        parser.setResult(eof && line.isEmpty ? 1 : 0)
    }

    private func ttlFileRead() throws {
        let fhi = try parser.getIntExpression()
        let varId = try parser.getStrVar()
        let readLen = try parser.getIntExpression()

        guard let fh = handleGet(fhi) else { throw TTLError.syntax }

        let data = fh.readData(ofLength: readLen)
        let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
        parser.setStrVal(id: varId, value: s)
        parser.setResult(data.isEmpty ? 1 : 0)
    }

    private func ttlFileWrite(addCRLF: Bool) throws {
        let fhi = try parser.getIntExpression()

        guard let fh = handleGet(fhi) else { throw TTLError.syntax }

        // Try string first
        if let strResult = parser.getString() {
            switch strResult {
            case .success(let s):
                fh.write(Data(s.utf8))
            case .failure(let e):
                throw e
            }
        } else {
            let result = try parser.getExpression()
            switch result {
            case .string(let id):
                fh.write(Data(parser.getStrVal(id: id).utf8))
            case .integer(let v):
                fh.write(Data([UInt8(v & 0xFF)]))
            default:
                throw TTLError.typeMismatch
            }
        }

        if addCRLF {
            fh.write(Data([0x0D, 0x0A]))
        }
    }

    private func ttlFileCreate() throws {
        let filename = try parser.getStrExpression()
        let path = resolvePath(filename)
        FileManager.default.createFile(atPath: path, contents: nil)
        parser.setResult(FileManager.default.fileExists(atPath: path) ? 0 : -1)
    }

    private func ttlFileDelete() throws {
        let filename = try parser.getStrExpression()
        let path = resolvePath(filename)
        do {
            try FileManager.default.removeItem(atPath: path)
            parser.setResult(0)
        } catch {
            parser.setResult(-1)
        }
    }

    private func ttlFileCopy() throws {
        let src = try parser.getStrExpression()
        let dst = try parser.getStrExpression()
        do {
            try FileManager.default.copyItem(atPath: resolvePath(src), toPath: resolvePath(dst))
            parser.setResult(0)
        } catch {
            parser.setResult(-1)
        }
    }

    private func ttlFileRename() throws {
        let src = try parser.getStrExpression()
        let dst = try parser.getStrExpression()
        do {
            try FileManager.default.moveItem(atPath: resolvePath(src), toPath: resolvePath(dst))
            parser.setResult(0)
        } catch {
            parser.setResult(-1)
        }
    }

    private func ttlFileConcat() throws {
        let dstPath = try parser.getStrExpression()
        let srcPath = try parser.getStrExpression()
        let dst = resolvePath(dstPath)
        let src = resolvePath(srcPath)
        guard let srcData = FileManager.default.contents(atPath: src) else {
            parser.setResult(-1)
            return
        }
        if let fh = FileHandle(forWritingAtPath: dst) {
            fh.seekToEndOfFile()
            fh.write(srcData)
            try? fh.close()
            parser.setResult(0)
        } else {
            parser.setResult(-1)
        }
    }

    private func ttlFileSearch() throws {
        let filename = try parser.getStrExpression()
        let path = resolvePath(filename)
        parser.setResult(FileManager.default.fileExists(atPath: path) ? 1 : 0)
    }

    private func ttlFileSeek() throws {
        let fhi = try parser.getIntExpression()
        let offset = try parser.getIntExpression()
        var origin = 0
        if parser.checkParameterGiven() {
            origin = try parser.getIntExpression()
        }
        guard let fh = handleGet(fhi) else { throw TTLError.syntax }
        switch origin {
        case 1: // Current
            fh.seek(toFileOffset: UInt64(Int64(fh.offsetInFile) + Int64(offset)))
        case 2: // End
            fh.seekToEndOfFile()
            if offset < 0 {
                fh.seek(toFileOffset: UInt64(Int64(fh.offsetInFile) + Int64(offset)))
            }
        default: // Beginning
            fh.seek(toFileOffset: UInt64(max(0, offset)))
        }
        parser.setResult(0)
    }

    private func ttlFileSeekBack() throws {
        let fhi = try parser.getIntExpression()
        guard let fh = handleGet(fhi) else { throw TTLError.syntax }
        guard fhi >= 0 && fhi < maxFileHandles else { throw TTLError.syntax }
        fh.seek(toFileOffset: UInt64(filePointers[fhi]))
        parser.setResult(0)
    }

    private func ttlFileMarkPtr() throws {
        let fhi = try parser.getIntExpression()
        guard let fh = handleGet(fhi) else { throw TTLError.syntax }
        guard fhi >= 0 && fhi < maxFileHandles else { throw TTLError.syntax }
        filePointers[fhi] = Int64(fh.offsetInFile)
    }

    private func ttlFileStat() throws {
        let filename = try parser.getStrExpression()
        let varId = try parser.getIntVar()
        let path = resolvePath(filename)
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs[.size] as? Int) ?? 0
            parser.setIntVal(id: varId, value: size)
            parser.setResult(0)
        } catch {
            parser.setIntVal(id: varId, value: -1)
            parser.setResult(-1)
        }
    }

    private func ttlFileTruncate() throws {
        let fhi = try parser.getIntExpression()
        guard let fh = handleGet(fhi) else { throw TTLError.syntax }
        fh.truncateFile(atOffset: fh.offsetInFile)
        parser.setResult(0)
    }

    private func ttlFileStrSeek() throws {
        let fhi = try parser.getIntExpression()
        let searchStr = try parser.getStrExpression()
        guard let fh = handleGet(fhi) else { throw TTLError.syntax }

        // Read from current position to end
        let data = fh.readDataToEndOfFile()
        let content = String(data: data, encoding: .utf8) ?? ""
        if let range = content.range(of: searchStr) {
            let offset = content.distance(from: content.startIndex, to: range.lowerBound)
            let currentPos = fh.offsetInFile - UInt64(data.count)
            fh.seek(toFileOffset: currentPos + UInt64(offset))
            parser.setResult(1)
        } else {
            // Reset position
            fh.seek(toFileOffset: fh.offsetInFile - UInt64(data.count))
            parser.setResult(0)
        }
    }

    private func ttlFileStrSeek2() throws {
        let fhi = try parser.getIntExpression()
        let searchStr = try parser.getStrExpression()
        guard let fh = handleGet(fhi) else { throw TTLError.syntax }

        let startPos = fh.offsetInFile
        fh.seek(toFileOffset: 0)
        let data = fh.readDataToEndOfFile()
        let content = String(data: data, encoding: .utf8) ?? ""

        if let range = content.range(of: searchStr, options: .backwards) {
            let offset = content.distance(from: content.startIndex, to: range.lowerBound)
            fh.seek(toFileOffset: UInt64(offset))
            parser.setResult(1)
        } else {
            fh.seek(toFileOffset: startPos)
            parser.setResult(0)
        }
    }

    private func ttlFileLock() throws {
        let fhi = try parser.getIntExpression()
        // File locking: no-op on macOS (different semantics)
        guard handleGet(fhi) != nil else { throw TTLError.syntax }
        parser.setResult(0)
    }

    private func ttlFileUnLock() throws {
        let fhi = try parser.getIntExpression()
        guard handleGet(fhi) != nil else { throw TTLError.syntax }
        parser.setResult(0)
    }

    // MARK: - Directory Commands

    private func ttlFindFirst() throws {
        let varId = try parser.getStrVar()
        let pattern = try parser.getStrExpression()
        let path = resolvePath(pattern)
        let dir = (path as NSString).deletingLastPathComponent
        let filePattern = (path as NSString).lastPathComponent

        var handleIdx = -1
        for i in 0..<maxDirHandles {
            if dirEnumerators[i] == nil {
                handleIdx = i
                break
            }
        }
        guard handleIdx >= 0 else { throw TTLError.fewMemory }

        dirPatterns[handleIdx] = filePattern
        dirEnumerators[handleIdx] = FileManager.default.enumerator(atPath: dir)

        // Find first match
        if let name = findNextMatch(handle: handleIdx, dir: dir) {
            parser.setStrVal(id: varId, value: name)
            parser.setResult(0)
        } else {
            parser.setResult(-1)
            dirEnumerators[handleIdx] = nil
        }
    }

    private func ttlFindNext() throws {
        let varId = try parser.getStrVar()
        let handleIdx = try parser.getIntExpression()
        guard handleIdx >= 0 && handleIdx < maxDirHandles,
              dirEnumerators[handleIdx] != nil else {
            parser.setResult(-1)
            return
        }
        if let name = findNextMatch(handle: handleIdx, dir: "") {
            parser.setStrVal(id: varId, value: name)
            parser.setResult(0)
        } else {
            parser.setResult(-1)
        }
    }

    private func findNextMatch(handle: Int, dir: String) -> String? {
        guard let enumerator = dirEnumerators[handle] else { return nil }
        let pattern = dirPatterns[handle]

        while let name = enumerator.nextObject() as? String {
            let fileName = (name as NSString).lastPathComponent
            if matchWildcard(fileName, pattern: pattern) {
                return fileName
            }
        }
        return nil
    }

    private func matchWildcard(_ name: String, pattern: String) -> Bool {
        let pred = NSPredicate(format: "SELF LIKE[c] %@", pattern)
        return pred.evaluate(with: name)
    }

    private func ttlFindClose() throws {
        let handleIdx = try parser.getIntExpression()
        guard handleIdx >= 0 && handleIdx < maxDirHandles else { return }
        dirEnumerators[handleIdx] = nil
        dirPatterns[handleIdx] = ""
    }

    private func ttlFolderCreate() throws {
        let path = try parser.getStrExpression()
        do {
            try FileManager.default.createDirectory(atPath: resolvePath(path),
                                                     withIntermediateDirectories: true)
            parser.setResult(0)
        } catch {
            parser.setResult(-1)
        }
    }

    private func ttlFolderDelete() throws {
        let path = try parser.getStrExpression()
        do {
            try FileManager.default.removeItem(atPath: resolvePath(path))
            parser.setResult(0)
        } catch {
            parser.setResult(-1)
        }
    }

    private func ttlFolderSearch() throws {
        let path = try parser.getStrExpression()
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resolvePath(path), isDirectory: &isDir)
        parser.setResult(exists && isDir.boolValue ? 1 : 0)
    }

    // MARK: - Array Commands

    private func ttlDim(isInt: Bool) throws {
        guard let name = parser.getIdentifier() else { throw TTLError.syntax }
        let size = try parser.getIntExpression()
        guard size > 0 else { throw TTLError.outOfRange }

        if isInt {
            parser.newIntArrayVar(name, size: size)
        } else {
            parser.newStrArrayVar(name, size: size)
        }
    }

    // MARK: - Dialog Box Commands (delegated to DialogCommandProvider)

    private func ttlInputBox(password: Bool) throws {
        let prompt = try parser.getStrExpression()
        var title = "Tera Term"
        if parser.checkParameterGiven() {
            title = try parser.getStrExpression()
        }
        var defaultVal = ""
        if parser.checkParameterGiven() && !password {
            defaultVal = try parser.getStrExpression()
        }

        parser.status = .pause
        dialogProvider.showInputBox(prompt: prompt, title: title, defaultValue: defaultVal, isPassword: password) { [weak self] result, inputStr in
            guard let self = self else { return }
            self.parser.setResult(result)
            self.parser.setInputStr(inputStr)
            self.parser.status = .run
            self.scheduleExec()
        }
    }

    private func ttlMessageBox() throws {
        let msg = try parser.getStrExpression()
        var title = "Tera Term"
        if parser.checkParameterGiven() {
            title = try parser.getStrExpression()
        }

        parser.status = .pause
        dialogProvider.showMessageBox(message: msg, title: title) { [weak self] result in
            guard let self = self else { return }
            self.parser.setResult(result)
            self.parser.status = .run
            self.scheduleExec()
        }
    }

    private func ttlYesNoBox() throws {
        let msg = try parser.getStrExpression()
        var title = "Tera Term"
        if parser.checkParameterGiven() {
            title = try parser.getStrExpression()
        }

        parser.status = .pause
        dialogProvider.showYesNoBox(message: msg, title: title) { [weak self] result in
            guard let self = self else { return }
            self.parser.setResult(result)
            self.parser.status = .run
            self.scheduleExec()
        }
    }

    private func ttlStatusBox() throws {
        let msg = try parser.getStrExpression()
        var title = "Tera Term"
        if parser.checkParameterGiven() {
            title = try parser.getStrExpression()
        }
        dialogProvider.showStatusBox(message: msg, title: title)
        delegate?.ttlShowStatusBox(msg, title: title)
    }

    private func ttlCloseSBox() throws {
        dialogProvider.closeStatusBox()
        delegate?.ttlCloseStatusBox()
    }

    private func ttlListBox() throws {
        let msg = try parser.getStrExpression()
        var title = "Tera Term"
        if parser.checkParameterGiven() {
            title = try parser.getStrExpression()
        }

        let items = msg.components(separatedBy: "\n")

        parser.status = .pause
        dialogProvider.showListBox(items: items, title: title) { [weak self] result, inputStr in
            guard let self = self else { return }
            self.parser.setResult(result)
            self.parser.setInputStr(inputStr)
            self.parser.status = .run
            self.scheduleExec()
        }
    }

    private func ttlFilenameBox() throws {
        let varId = try parser.getStrVar()
        var title = "Select File"
        if parser.checkParameterGiven() {
            title = try parser.getStrExpression()
        }
        var save = false
        if parser.checkParameterGiven() {
            save = try parser.getIntExpression() != 0
        }

        parser.status = .pause
        dialogProvider.showFilenameBox(title: title, isSave: save) { [weak self] result, path in
            guard let self = self else { return }
            if result == 1 {
                self.parser.setStrVal(id: varId, value: path)
            }
            self.parser.setResult(result)
            self.parser.status = .run
            self.scheduleExec()
        }
    }

    private func ttlDirnameBox() throws {
        let varId = try parser.getStrVar()
        var title = "Select Folder"
        if parser.checkParameterGiven() {
            title = try parser.getStrExpression()
        }

        parser.status = .pause
        dialogProvider.showDirnameBox(title: title) { [weak self] result, path in
            guard let self = self else { return }
            if result == 1 {
                self.parser.setStrVal(id: varId, value: path)
            }
            self.parser.setResult(result)
            self.parser.status = .run
            self.scheduleExec()
        }
    }

    private func ttlBringupBox() throws {
        dialogProvider.bringupBox()
    }

    // MARK: - System/Environment Commands

    private func ttlGetTime(isDate: Bool) throws {
        let varId = try parser.getStrVar()
        let formatter = DateFormatter()
        if isDate {
            formatter.dateFormat = "yyyy/MM/dd"
        } else {
            formatter.dateFormat = "HH:mm:ss"
        }
        parser.setStrVal(id: varId, value: formatter.string(from: Date()))
    }

    private func ttlGetDir() throws {
        let varId = try parser.getStrVar()
        parser.setStrVal(id: varId, value: FileManager.default.currentDirectoryPath)
    }

    private func ttlSetDir() throws {
        let dir = try parser.getStrExpression()
        let success = FileManager.default.changeCurrentDirectoryPath(resolvePath(dir))
        parser.setResult(success ? 0 : -1)
    }

    private func ttlGetEnv() throws {
        let envName = try parser.getStrExpression()
        let varId = try parser.getStrVar()
        let value = ProcessInfo.processInfo.environment[envName] ?? ""
        parser.setStrVal(id: varId, value: value)
    }

    private func ttlSetEnv() throws {
        let envName = try parser.getStrExpression()
        let value = try parser.getStrExpression()
        setenv(envName, value, 1)
    }

    private func ttlExpandEnv() throws {
        let varId = try parser.getStrVar()
        let s = parser.getStrVal(id: varId)
        // Expand %VAR% references
        var result = s
        let pattern = try NSRegularExpression(pattern: "%([^%]+)%")
        let matches = pattern.matches(in: s, range: NSRange(s.startIndex..., in: s))
        for match in matches.reversed() {
            if let varRange = Range(match.range(at: 1), in: s),
               let fullRange = Range(match.range, in: s) {
                let envName = String(s[varRange])
                let value = ProcessInfo.processInfo.environment[envName] ?? ""
                result = result.replacingCharacters(in: fullRange, with: value)
            }
        }
        parser.setStrVal(id: varId, value: result)
    }

    private func ttlGetTitle() throws {
        let varId = try parser.getStrVar()
        let title = delegate?.ttlGetTitle() ?? ""
        parser.setStrVal(id: varId, value: title)
    }

    private func ttlGetVer() throws {
        let varId = try parser.getIntVar()
        // Return version as integer: major*10000 + minor*100 + patch
        parser.setIntVal(id: varId, value: 50000)  // 5.0.0
    }

    private func ttlGetHostname() throws {
        let varId = try parser.getStrVar()
        parser.setStrVal(id: varId, value: Host.current().localizedName ?? "localhost")
    }

    private func ttlGetTTDir() throws {
        let varId = try parser.getStrVar()
        let path = Bundle.main.bundlePath
        parser.setStrVal(id: varId, value: (path as NSString).deletingLastPathComponent)
    }

    private func ttlGetSpecialFolder() throws {
        let varId = try parser.getStrVar()
        let folderType = try parser.getIntExpression()

        let searchPath: FileManager.SearchPathDirectory
        switch folderType {
        case 0: searchPath = .desktopDirectory
        case 1: searchPath = .applicationSupportDirectory
        case 2: searchPath = .documentDirectory
        case 3: searchPath = .downloadsDirectory
        default: searchPath = .userDirectory
        }

        let paths = NSSearchPathForDirectoriesInDomains(searchPath, .userDomainMask, true)
        parser.setStrVal(id: varId, value: paths.first ?? "")
    }

    private func ttlGetIPv4Addr() throws {
        let varId = try parser.getStrVar()
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while let addr = ptr {
                if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    let addrStr = String(cString: hostname)
                    if addrStr != "127.0.0.1" {
                        addresses.append(addrStr)
                    }
                }
                ptr = addr.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        parser.setStrVal(id: varId, value: addresses.first ?? "127.0.0.1")
    }

    private func ttlGetIPv6Addr() throws {
        let varId = try parser.getStrVar()
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while let addr = ptr {
                if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET6) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    let addrStr = String(cString: hostname)
                    if !addrStr.hasPrefix("::1") && !addrStr.hasPrefix("fe80") {
                        addresses.append(addrStr)
                    }
                }
                ptr = addr.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        parser.setStrVal(id: varId, value: addresses.first ?? "::1")
    }

    private func ttlGetFileAttr() throws {
        let filename = try parser.getStrExpression()
        let varId = try parser.getIntVar()
        let path = resolvePath(filename)
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            var result = 0
            if let type = attrs[.type] as? FileAttributeType {
                if type == .typeDirectory { result |= 0x10 }
            }
            if let perms = attrs[.posixPermissions] as? Int {
                if perms & 0o200 == 0 { result |= 0x01 } // Read-only
            }
            parser.setIntVal(id: varId, value: result)
            parser.setResult(0)
        } catch {
            parser.setResult(-1)
        }
    }

    private func ttlSetFileAttr() throws {
        let filename = try parser.getStrExpression()
        let attr = try parser.getIntExpression()
        let path = resolvePath(filename)
        do {
            var perms: Int = 0o644
            if attr & 0x01 != 0 { perms = 0o444 } // Read-only
            try FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: path)
            parser.setResult(0)
        } catch {
            parser.setResult(-1)
        }
    }

    private func ttlGetModemStatus() throws {
        let varId = try parser.getIntVar()
        // Stub: modem status not directly accessible on macOS
        parser.setIntVal(id: varId, value: 0)
        parser.setResult(0)
    }

    private func ttlGetTTPos() throws {
        let xVar = try parser.getIntVar()
        let yVar = try parser.getIntVar()
        // Return 0,0 - actual position would come from delegate
        parser.setIntVal(id: xVar, value: 0)
        parser.setIntVal(id: yVar, value: 0)
    }

    private func ttlUptime() throws {
        let varId = try parser.getIntVar()
        let uptime = Int(ProcessInfo.processInfo.systemUptime)
        parser.setIntVal(id: varId, value: uptime)
    }

    private func ttlRandom() throws {
        let varId = try parser.getIntVar()
        let max = try parser.getIntExpression()
        guard max > 0 else {
            parser.setIntVal(id: varId, value: 0)
            return
        }
        parser.setIntVal(id: varId, value: Int.random(in: 0..<max))
    }

    // MARK: - Terminal Operation Commands

    private func ttlConnect() throws {
        let param = try parser.getStrExpression()
        delegate?.ttlConnect(param)
        parser.setResult(delegate?.ttlIsConnected() == true ? 1 : 0)
    }

    private func ttlDisconnect() throws {
        delegate?.ttlDisconnect()
    }

    private func ttlTestLink() throws {
        parser.setResult(delegate?.ttlIsConnected() == true ? 2 : 0)
    }

    private func ttlClearScreen() throws {
        delegate?.ttlClearScreen()
    }

    private func ttlDispStr() throws {
        let s = try parser.getStrExpression()
        delegate?.ttlSendString(s)
    }

    private func ttlSetTitle() throws {
        let title = try parser.getStrExpression()
        delegate?.ttlSetTitle(title)
    }

    private func ttlSetEcho() throws {
        _ = try parser.getIntExpression()
        // Echo setting handled by terminal
    }

    private func ttlSetSync() throws {
        _ = try parser.getIntExpression()
        // Sync setting
    }

    private func ttlShow() throws {
        let mode = try parser.getIntExpression()
        delegate?.ttlShowWindow(mode != 0)
    }

    private func ttlShowTT() throws {
        let mode = try parser.getIntExpression()
        delegate?.ttlShowWindow(mode != 0)
    }

    private func ttlCloseTT() throws {
        delegate?.ttlDisconnect()
    }

    private func ttlEnableKeyb() throws {
        _ = try parser.getIntExpression()
        // Keyboard enable/disable
    }

    private func ttlSetBaud() throws {
        let baud = try parser.getIntExpression()
        delegate?.ttlSetBaud(baud)
    }

    private func ttlSetFlowCtrl() throws {
        let mode = try parser.getIntExpression()
        delegate?.ttlSetFlowCtrl(mode)
    }

    private func ttlSetDtr() throws {
        let on = try parser.getIntExpression()
        delegate?.ttlSetDtr(on)
    }

    private func ttlSetRts() throws {
        let on = try parser.getIntExpression()
        delegate?.ttlSetRts(on)
    }

    // MARK: - Clipboard Commands

    private func ttlClipb2Var() throws {
        let varId = try parser.getStrVar()
        let text = delegate?.ttlGetClipboard() ?? ""
        parser.setStrVal(id: varId, value: text)
    }

    private func ttlVar2Clipb() throws {
        let s = try parser.getStrExpression()
        delegate?.ttlSetClipboard(s)
    }

    // MARK: - Path Commands

    private func ttlMakePath() throws {
        let varId = try parser.getStrVar()
        let dir = try parser.getStrExpression()
        let file = try parser.getStrExpression()
        let path = (dir as NSString).appendingPathComponent(file)
        parser.setStrVal(id: varId, value: path)
    }

    private func ttlBasename() throws {
        let varId = try parser.getStrVar()
        let path = try parser.getStrExpression()
        parser.setStrVal(id: varId, value: (path as NSString).lastPathComponent)
    }

    private func ttlDirname() throws {
        let varId = try parser.getStrVar()
        let path = try parser.getStrExpression()
        parser.setStrVal(id: varId, value: (path as NSString).deletingLastPathComponent)
    }

    private func ttlChangeDir() throws {
        let dir = try parser.getStrExpression()
        FileManager.default.changeCurrentDirectoryPath(resolvePath(dir))
    }

    // MARK: - Log Commands

    private func ttlLogOpen() throws {
        let filename = try parser.getStrExpression()
        var append = false
        if parser.checkParameterGiven() {
            append = try parser.getIntExpression() != 0
        }
        delegate?.ttlLogOpen(resolvePath(filename), append: append)
    }

    private func ttlLogClose() throws {
        delegate?.ttlLogClose()
    }

    private func ttlLogPause() throws {
        delegate?.ttlLogPause()
    }

    private func ttlLogStart() throws {
        delegate?.ttlLogStart()
    }

    private func ttlLogWrite() throws {
        let text = try parser.getStrExpression()
        delegate?.ttlLogWrite(text)
    }

    private func ttlLogInfo() throws {
        // Log info - stub
        parser.setResult(0)
    }

    private func ttlLogRotate() throws {
        // Log rotate - stub
        parser.setResult(0)
    }

    private func ttlLogAutoClose() throws {
        _ = try parser.getIntExpression()
        // Auto close mode
    }

    // MARK: - Exec Commands

    private func ttlExec() throws {
        let cmd = try parser.getStrExpression()
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", cmd]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            parser.setInputStr(output.trimmingCharacters(in: .whitespacesAndNewlines))
            parser.setResult(Int(task.terminationStatus))
        } catch {
            throw TTLError.cantExec
        }
    }

    private func ttlExecCmnd() throws {
        // Execute TTL command from string
        let cmdStr = try parser.getStrExpression()
        let savedLine = parser.lineBuffer
        let savedPtr = parser.linePtr
        parser.lineBuffer = cmdStr
        parser.linePtr = 0
        try execCmnd()
        parser.lineBuffer = savedLine
        parser.linePtr = savedPtr
    }

    private func ttlSetExitCode() throws {
        exitCode = try parser.getIntExpression()
    }

    // MARK: - Bit Operation Commands

    private func ttlRotateLeft() throws {
        let varId = try parser.getIntVar()
        let bits = try parser.getIntExpression()
        let val = parser.getIntVal(id: varId)
        let rotated = (val << bits) | (val >> (Int.bitWidth - bits))
        parser.setIntVal(id: varId, value: rotated)
    }

    private func ttlRotateRight() throws {
        let varId = try parser.getIntVar()
        let bits = try parser.getIntExpression()
        let val = parser.getIntVal(id: varId)
        let rotated = (val >> bits) | (val << (Int.bitWidth - bits))
        parser.setIntVal(id: varId, value: rotated)
    }

    // MARK: - Checksum/CRC Commands

    enum ChecksumType {
        case checksum8, checksum16, checksum32, crc16, crc32
    }

    private func ttlDoChecksum(type: ChecksumType) throws {
        let varId = try parser.getIntVar()
        let s = try parser.getStrExpression()
        let data = Data(s.utf8)
        let result = computeChecksum(data: data, type: type)
        parser.setIntVal(id: varId, value: result)
    }

    private func ttlDoChecksumFile(type: ChecksumType) throws {
        let varId = try parser.getIntVar()
        let filename = try parser.getStrExpression()
        guard let data = FileManager.default.contents(atPath: resolvePath(filename)) else {
            throw TTLError.cantOpen
        }
        let result = computeChecksum(data: data, type: type)
        parser.setIntVal(id: varId, value: result)
    }

    private func computeChecksum(data: Data, type: ChecksumType) -> Int {
        switch type {
        case .checksum8:
            var sum: UInt8 = 0
            for byte in data { sum = sum &+ byte }
            return Int(sum)
        case .checksum16:
            var sum: UInt16 = 0
            for byte in data { sum = sum &+ UInt16(byte) }
            return Int(sum)
        case .checksum32:
            var sum: UInt32 = 0
            for byte in data { sum = sum &+ UInt32(byte) }
            return Int(sum)
        case .crc16:
            var crc: UInt16 = 0xFFFF
            for byte in data {
                crc ^= UInt16(byte)
                for _ in 0..<8 {
                    if crc & 1 != 0 { crc = (crc >> 1) ^ 0xA001 }
                    else { crc >>= 1 }
                }
            }
            return Int(crc)
        case .crc32:
            var crc: UInt32 = 0xFFFFFFFF
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 {
                    if crc & 1 != 0 { crc = (crc >> 1) ^ 0xEDB88320 }
                    else { crc >>= 1 }
                }
            }
            return Int(crc ^ 0xFFFFFFFF)
        }
    }

    // MARK: - Miscellaneous Commands

    private func ttlBeep() throws {
        NSSound.beep()
    }

    private func ttlSetDate() throws {
        // Setting system date requires privileges - stub
        _ = try parser.getStrExpression()
        parser.setResult(-1)
    }

    private func ttlSetTime() throws {
        // Setting system time requires privileges - stub
        _ = try parser.getStrExpression()
        parser.setResult(-1)
    }

    private func ttlSetDlgPos() throws {
        dialogProvider.posX = try parser.getIntExpression()
        dialogProvider.posY = try parser.getIntExpression()
    }

    private func ttlSetDebug() throws {
        _ = try parser.getIntExpression()
        // Debug mode
    }

    private func ttlRegexOption() throws {
        let opt = try parser.getIntExpression()
        regexOptionCaseInsensitive = (opt & 1) != 0
    }

    // MARK: - Password Commands (Keychain stubs)

    private func ttlGetPassword() throws {
        // Prompt for password
        let varId = try parser.getStrVar()
        let prompt = try parser.getStrExpression()

        parser.status = .pause
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let alert = NSAlert()
            alert.messageText = "Password"
            alert.informativeText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            alert.accessoryView = input
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.parser.setStrVal(id: varId, value: input.stringValue)
                self.parser.setResult(1)
            } else {
                self.parser.setResult(0)
            }
            self.parser.status = .run
            self.scheduleExec()
        }
    }

    private func ttlSetPassword() throws {
        _ = try parser.getStrExpression()
        _ = try parser.getStrExpression()
        parser.setResult(0)
    }

    private func ttlDelPassword() throws {
        _ = try parser.getStrExpression()
        parser.setResult(0)
    }

    private func ttlIsPassword() throws {
        _ = try parser.getStrExpression()
        parser.setResult(0)
    }

    private func ttlGetPassword2() throws {
        try ttlGetPassword()
    }

    private func ttlSetPassword2() throws {
        try ttlSetPassword()
    }

    private func ttlDelPassword2() throws {
        try ttlDelPassword()
    }

    private func ttlIsPassword2() throws {
        try ttlIsPassword()
    }

    // MARK: - Broadcast/Multicast (stubs)

    private func ttlSendBroadcast(crlf: Bool) throws {
        var text = try parser.getStrExpression()
        if crlf { text += "\r" }
        delegate?.ttlSendString(text)
    }

    private func ttlSendMulticast(crlf: Bool) throws {
        var text = try parser.getStrExpression()
        if crlf { text += "\r" }
        delegate?.ttlSendString(text)
    }

    private func ttlSetMulticastName() throws {
        _ = try parser.getStrExpression()
    }

    // MARK: - Helper Methods

    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") || path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return FileManager.default.currentDirectoryPath + "/" + path
    }
}
#endif
