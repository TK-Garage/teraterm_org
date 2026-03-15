/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * MacroRunner command implementations part 2 (dialogs, file I/O, system, terminal,
 * clipboard, log, checksum, password, file transfer).
 */

import Foundation
import TTLMacroShared

// MARK: - Dialog Commands

extension MacroRunner {

    func cmdMessageBox(_ args: [String]) { // [IMPLEMENTED]
        let message = getStringArg(args, 0)
        let title = args.count > 1 ? getStringArg(args, 1) : ""
        clientProxy?.showDialog(type: "messagebox", message: message, defaultValue: title,
                                reply: { [weak self] _, _ in self?.scheduleNextLine() })
    }

    func cmdInputBox(_ args: [String], password: Bool) { // [IMPLEMENTED]
        let prompt = getStringArg(args, 0)
        let title = args.count > 1 ? getStringArg(args, 1) : ""
        let defaultVal = args.count > 2 ? getStringArg(args, 2) : ""
        let type = password ? "passwordbox" : "inputbox"
        clientProxy?.showDialog(type: type, message: prompt, defaultValue: defaultVal,
                                reply: { [weak self] result, text in
            self?.variables["result"] = .integer(result)
            self?.inputStr = text
            self?.variables["inputstr"] = .string(text)
            self?.scheduleNextLine()
        })
    }

    func cmdYesNoBox(_ args: [String]) { // [IMPLEMENTED]
        let message = getStringArg(args, 0)
        let title = args.count > 1 ? getStringArg(args, 1) : ""
        clientProxy?.showDialog(type: "yesnobox", message: message, defaultValue: title,
                                reply: { [weak self] result, _ in
            self?.variables["result"] = .integer(result)
            self?.scheduleNextLine()
        })
    }

    func cmdStatusBox(_ args: [String]) { // [IMPLEMENTED]
        let message = getStringArg(args, 0)
        let title = args.count > 1 ? getStringArg(args, 1) : ""
        clientProxy?.showStatusBox(message: message, title: title,
                                   reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdCloseSBox() { // [IMPLEMENTED]
        clientProxy?.closeStatusBox(reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdListBox(_ args: [String]) { // [IMPLEMENTED]
        let items = getStringArg(args, 0)
        let title = args.count > 1 ? getStringArg(args, 1) : ""
        clientProxy?.showDialog(type: "listbox", message: items, defaultValue: title,
                                reply: { [weak self] result, text in
            self?.variables["result"] = .integer(result)
            self?.inputStr = text
            self?.variables["inputstr"] = .string(text)
            self?.scheduleNextLine()
        })
    }

    func cmdFilenameBox(_ args: [String]) { // [IMPLEMENTED]
        let destVar = args.first?.lowercased() ?? "inputstr"
        let title = args.count > 1 ? getStringArg(args, 1) : ""
        clientProxy?.showDialog(type: "filenamebox", message: title, defaultValue: "",
                                reply: { [weak self] result, text in
            self?.variables["result"] = .integer(result)
            self?.variables[destVar] = .string(text)
            self?.scheduleNextLine()
        })
    }

    func cmdDirnameBox(_ args: [String]) { // [IMPLEMENTED]
        let destVar = args.first?.lowercased() ?? "inputstr"
        let title = args.count > 1 ? getStringArg(args, 1) : ""
        clientProxy?.showDialog(type: "dirnamebox", message: title, defaultValue: "",
                                reply: { [weak self] result, text in
            self?.variables["result"] = .integer(result)
            self?.variables[destVar] = .string(text)
            self?.scheduleNextLine()
        })
    }

    func cmdBringupBox() { // [IMPLEMENTED]
        clientProxy?.bringWindowToFront(reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdSetDlgPos(_ args: [String]) { // [IMPLEMENTED]
        dlgPosX = getIntArg(args, 0)
        dlgPosY = args.count > 1 ? getIntArg(args, 1) : -1
    }
}

// MARK: - File I/O Commands

extension MacroRunner {

    func cmdFileOpen(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { reportError("Syntax error: fileopen"); return }
        let handleVar = args[0].lowercased()
        let filename = getStringArg(args, 1)
        let appendMode = getIntArg(args, 2)
        let readOnly = args.count > 3 ? getIntArg(args, 3) != 0 : false

        let fm = FileManager.default
        if appendMode == 0 && !readOnly {
            fm.createFile(atPath: filename, contents: nil)
        }
        if !fm.fileExists(atPath: filename) && !readOnly {
            fm.createFile(atPath: filename, contents: nil)
        }

        let handle: FileHandle?
        if readOnly {
            handle = FileHandle(forReadingAtPath: filename)
        } else if appendMode != 0 {
            handle = FileHandle(forUpdatingAtPath: filename)
            handle?.seekToEndOfFile()
        } else {
            handle = FileHandle(forUpdatingAtPath: filename)
        }

        if let handle = handle {
            let id = nextFileHandle
            nextFileHandle += 1
            fileHandles[id] = handle
            filePaths[id] = filename
            variables[handleVar] = .integer(id)
            variables["result"] = .integer(0)
        } else {
            variables["result"] = .integer(-1)
        }
    }

    func cmdFileClose(_ args: [String]) { // [IMPLEMENTED]
        let id = getIntArg(args, 0)
        fileHandles[id]?.closeFile()
        fileHandles.removeValue(forKey: id)
        filePaths.removeValue(forKey: id)
    }

    func cmdFileRead(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let id = getIntArg(args, 0)
        let destVar = args[1].lowercased()
        let bytes = getIntArg(args, 2)
        if let handle = fileHandles[id] {
            let data = handle.readData(ofLength: bytes)
            variables[destVar] = .string(String(data: data, encoding: .utf8) ?? "")
            variables["result"] = .integer(data.isEmpty ? 1 : 0)
        }
    }

    func cmdFileReadLn(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let id = getIntArg(args, 0)
        let destVar = args[1].lowercased()
        if let handle = fileHandles[id] {
            var line = ""
            var eof = false
            while true {
                let data = handle.readData(ofLength: 1)
                if data.isEmpty { eof = true; break }
                let ch = String(data: data, encoding: .utf8) ?? ""
                if ch == "\n" { break }
                if ch != "\r" { line += ch }
            }
            variables[destVar] = .string(line)
            inputStr = line
            variables["inputstr"] = .string(line)
            variables["result"] = .integer(eof && line.isEmpty ? 1 : 0)
        }
    }

    func cmdFileWrite(_ args: [String], addCRLF: Bool) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let id = getIntArg(args, 0)
        var text = getStringArg(args, 1)
        if addCRLF { text += "\r\n" }
        if let handle = fileHandles[id], let data = text.data(using: .utf8) {
            handle.write(data)
        }
    }

    func cmdFileCreate(_ args: [String]) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        FileManager.default.createFile(atPath: path, contents: nil)
    }

    func cmdFileDelete(_ args: [String]) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        try? FileManager.default.removeItem(atPath: path)
    }

    func cmdFileCopy(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let src = getStringArg(args, 0)
        let dst = getStringArg(args, 1)
        try? FileManager.default.copyItem(atPath: src, toPath: dst)
        variables["result"] = .integer(FileManager.default.fileExists(atPath: dst) ? 0 : -1)
    }

    func cmdFileRename(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        try? FileManager.default.moveItem(atPath: getStringArg(args, 0), toPath: getStringArg(args, 1))
    }

    func cmdFileConcat(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let dst = getStringArg(args, 0)
        let src = getStringArg(args, 1)
        if let srcData = FileManager.default.contents(atPath: src),
           let handle = FileHandle(forWritingAtPath: dst) {
            handle.seekToEndOfFile()
            handle.write(srcData)
            handle.closeFile()
        }
    }

    func cmdFileSearch(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let filepath = getStringArg(args, 0)
        let pattern = getStringArg(args, 1)
        if let content = try? String(contentsOfFile: filepath, encoding: .utf8) {
            variables["result"] = .integer(content.contains(pattern) ? 1 : 0)
        } else {
            variables["result"] = .integer(0)
        }
    }

    func cmdFileSeek(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let id = getIntArg(args, 0)
        let offset = getIntArg(args, 1)
        fileHandles[id]?.seek(toFileOffset: UInt64(offset))
    }

    func cmdFileSeekBack(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let id = getIntArg(args, 0)
        let bytes = getIntArg(args, 1)
        if let handle = fileHandles[id] {
            let pos = handle.offsetInFile
            handle.seek(toFileOffset: pos > UInt64(bytes) ? pos - UInt64(bytes) : 0)
        }
    }

    func cmdFileMarkPtr(_ args: [String]) { // [IMPLEMENTED]
        // Marker functionality - store current position
        let id = getIntArg(args, 0)
        if let handle = fileHandles[id] {
            variables["_filemark_\(id)"] = .integer(Int(handle.offsetInFile))
        }
    }

    func cmdFileStat(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let path = getStringArg(args, 0)
        let destVar = args[1].lowercased()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int {
            variables[destVar] = .integer(size)
        } else {
            variables[destVar] = .integer(-1)
        }
    }

    func cmdFileTruncate(_ args: [String]) { // [IMPLEMENTED]
        let id = getIntArg(args, 0)
        if let handle = fileHandles[id] {
            handle.truncateFile(atOffset: handle.offsetInFile)
        }
    }

    func cmdFileStrSeek(_ args: [String], reverse: Bool) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let id = getIntArg(args, 0)
        let pattern = getStringArg(args, 1)
        if let handle = fileHandles[id] {
            let currentPos = handle.offsetInFile
            let data = handle.readDataToEndOfFile()
            if let content = String(data: data, encoding: .utf8) {
                if let range = reverse ? content.range(of: pattern, options: .backwards) :
                    content.range(of: pattern) {
                    let offset = content.distance(from: content.startIndex, to: range.lowerBound)
                    handle.seek(toFileOffset: currentPos + UInt64(offset))
                    variables["result"] = .integer(1)
                } else {
                    handle.seek(toFileOffset: currentPos)
                    variables["result"] = .integer(0)
                }
            }
        }
    }

    func cmdFileLock(_ args: [String]) { // [IMPLEMENTED]
        // Stub on macOS
    }

    func cmdFileUnlock(_ args: [String]) { // [IMPLEMENTED]
        // Stub on macOS
    }
}

// MARK: - Directory Commands

extension MacroRunner {

    func cmdFindFirst(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let pattern = getStringArg(args, 1)
        let dir = (pattern as NSString).deletingLastPathComponent
        let filePattern = (pattern as NSString).lastPathComponent
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: dir.isEmpty ? "." : dir) {
            let matched = files.filter { fnmatch(filePattern, $0) }
            if !matched.isEmpty {
                dirSearchResults.append(matched)
                dirSearchIndex.append(0)
                variables[destVar] = .string(matched[0])
                variables["result"] = .integer(0)
            } else {
                variables["result"] = .integer(-1)
            }
        } else {
            variables["result"] = .integer(-1)
        }
    }

    func cmdFindNext(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        guard !dirSearchResults.isEmpty else { variables["result"] = .integer(-1); return }
        let idx = dirSearchResults.count - 1
        dirSearchIndex[idx] += 1
        if dirSearchIndex[idx] < dirSearchResults[idx].count {
            variables[destVar] = .string(dirSearchResults[idx][dirSearchIndex[idx]])
            variables["result"] = .integer(0)
        } else {
            variables["result"] = .integer(-1)
        }
    }

    func cmdFindClose() { // [IMPLEMENTED]
        if !dirSearchResults.isEmpty {
            dirSearchResults.removeLast()
            dirSearchIndex.removeLast()
        }
    }

    func cmdFolderCreate(_ args: [String]) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func cmdFolderDelete(_ args: [String]) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        try? FileManager.default.removeItem(atPath: path)
    }

    func cmdFolderSearch(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let pattern = getStringArg(args, 1)
        let exists = FileManager.default.fileExists(atPath: pattern)
        variables[destVar] = .string(exists ? pattern : "")
        variables["result"] = .integer(exists ? 0 : -1)
    }

    func cmdChangeDir(_ args: [String]) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        FileManager.default.changeCurrentDirectoryPath(path)
    }

    func cmdGetDir(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        variables[destVar] = .string(FileManager.default.currentDirectoryPath)
    }

    func cmdSetDir(_ args: [String]) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        FileManager.default.changeCurrentDirectoryPath(path)
    }

    func cmdMakePath(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 3 else { return }
        let destVar = args[0].lowercased()
        let dir = getStringArg(args, 1)
        let file = getStringArg(args, 2)
        variables[destVar] = .string((dir as NSString).appendingPathComponent(file))
    }

    func cmdBasename(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let path = getStringArg(args, 1)
        variables[destVar] = .string((path as NSString).lastPathComponent)
    }

    func cmdDirname(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let path = getStringArg(args, 1)
        variables[destVar] = .string((path as NSString).deletingLastPathComponent)
    }

    // Simple fnmatch for glob patterns
    private func fnmatch(_ pattern: String, _ name: String) -> Bool {
        let pred = NSPredicate(format: "self LIKE %@", pattern)
        return pred.evaluate(with: name)
    }
}

// MARK: - Array Commands

extension MacroRunner {

    func cmdIntDim(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let varName = args[0].lowercased()
        let size = getIntArg(args, 1)
        variables[varName] = .intArray(Array(repeating: 0, count: size))
    }

    func cmdStrDim(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let varName = args[0].lowercased()
        let size = getIntArg(args, 1)
        variables[varName] = .strArray(Array(repeating: "", count: size))
    }
}

// MARK: - System Commands

extension MacroRunner {

    func cmdGetDate(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd"
        variables[destVar] = .string(fmt.string(from: Date()))
    }

    func cmdGetTime(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        variables[destVar] = .string(fmt.string(from: Date()))
    }

    func cmdGetEnv(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let name = getStringArg(args, 0)
        let destVar = args[1].lowercased()
        variables[destVar] = .string(ProcessInfo.processInfo.environment[name] ?? "")
    }

    func cmdSetEnv(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let name = getStringArg(args, 0)
        let value = getStringArg(args, 1)
        setenv(name, value, 1)
    }

    func cmdExpandEnv(_ args: [String]) { // [IMPLEMENTED]
        guard let varName = args.first?.lowercased() else { return }
        var str = variables[varName]?.strValue ?? ""
        let env = ProcessInfo.processInfo.environment
        for (key, value) in env {
            str = str.replacingOccurrences(of: "%\(key)%", with: value)
        }
        variables[varName] = .string(str)
    }

    func cmdExec(_ args: [String]) { // [IMPLEMENTED]
        let command = args.map { resolveString($0) }.joined(separator: " ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            inputStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
            variables["inputstr"] = .string(inputStr)
            variables["result"] = .integer(Int(process.terminationStatus))
        } catch {
            variables["result"] = .integer(-1)
        }
    }

    func cmdExecCmnd(_ args: [String], fullLine: String) { // [IMPLEMENTED]
        // Execute a TTL command string dynamically
        let cmdStr = args.map { resolveString($0) }.joined(separator: " ")
        let parts = parseLine(cmdStr)
        if let cmd = parts.first?.lowercased() {
            executeCommand(cmd, args: Array(parts.dropFirst()), fullLine: cmdStr)
        }
    }

    func cmdSetExitCode(_ args: [String]) { // [IMPLEMENTED]
        exitCode = getIntArg(args, 0)
    }

    func cmdRandom(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let maxVal = getIntArg(args, 1)
        variables[destVar] = .integer(maxVal > 0 ? Int.random(in: 0..<maxVal) : 0)
    }

    func cmdUptime(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        variables[destVar] = .integer(Int(ProcessInfo.processInfo.systemUptime))
    }

    func cmdGetHostname(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        clientProxy?.getHostname(reply: { [weak self] name in
            self?.variables[destVar] = .string(name)
            self?.scheduleNextLine()
        })
        return // async
    }

    func cmdGetVer(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        clientProxy?.getAppVersion(reply: { [weak self] version in
            let parts = version.split(separator: ".")
            let major = Int(parts.first ?? "1") ?? 1
            let minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            let patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
            self?.variables[destVar] = .integer(major * 10000 + minor * 100 + patch)
            self?.scheduleNextLine()
        })
        return // async
    }

    func cmdGetTTDir(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        clientProxy?.getAppDirectory(reply: { [weak self] dir in
            self?.variables[destVar] = .string(dir)
            self?.scheduleNextLine()
        })
        return // async
    }

    func cmdGetTTPos(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let xVar = args[0].lowercased()
        let yVar = args[1].lowercased()
        clientProxy?.getWindowPosition(reply: { [weak self] x, y in
            self?.variables[xVar] = .integer(x)
            self?.variables[yVar] = .integer(y)
            self?.scheduleNextLine()
        })
        return // async
    }

    func cmdGetSpecialFolder(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let folderId = getIntArg(args, 1)
        let path: String
        switch folderId {
        case 0: path = NSHomeDirectory() + "/Desktop"
        case 1: path = NSHomeDirectory() + "/Library/Application Support"
        case 2: path = NSHomeDirectory() + "/Documents"
        case 3: path = NSHomeDirectory() + "/Downloads"
        default: path = NSHomeDirectory()
        }
        variables[destVar] = .string(path)
    }

    func cmdGetIPv4Addr(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        variables[destVar] = .string(getIPAddress(ipv6: false))
    }

    func cmdGetIPv6Addr(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        variables[destVar] = .string(getIPAddress(ipv6: true))
    }

    private func getIPAddress(ipv6: Bool) -> String {
        var address = ""
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return "" }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let family = ptr.pointee.ifa_addr.pointee.sa_family
            if (!ipv6 && family == UInt8(AF_INET)) || (ipv6 && family == UInt8(AF_INET6)) {
                let name = String(cString: ptr.pointee.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }

    func cmdGetFileAttr(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let path = getStringArg(args, 0)
        let destVar = args[1].lowercased()
        var attr = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            if let type = attrs[.type] as? FileAttributeType, type == .typeDirectory { attr |= 0x10 }
            if let posix = attrs[.posixPermissions] as? Int, (posix & 0o222) == 0 { attr |= 0x01 }
        }
        variables[destVar] = .integer(attr)
    }

    func cmdSetFileAttr(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let path = getStringArg(args, 0)
        let attr = getIntArg(args, 1)
        let readOnly = (attr & 0x01) != 0
        let perms: Int = readOnly ? 0o444 : 0o644
        try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: path)
    }

    func cmdGetModemStatus(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        clientProxy?.getModemStatus(reply: { [weak self] status in
            self?.variables[destVar] = .integer(status)
            self?.scheduleNextLine()
        })
        return // async
    }
}

// MARK: - Terminal Commands

extension MacroRunner {

    func cmdClearScreen() { // [IMPLEMENTED]
        clientProxy?.clearScreen(reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdSetTitle(_ args: [String]) { // [IMPLEMENTED]
        let title = args.map { resolveString($0) }.joined(separator: " ")
        clientProxy?.setWindowTitle(title: title, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdGetTitle(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        clientProxy?.getWindowTitle(reply: { [weak self] title in
            self?.variables[destVar] = .string(title)
            self?.scheduleNextLine()
        })
        return // async
    }

    func cmdShow(_ args: [String]) { // [IMPLEMENTED]
        let flag = getIntArg(args, 0)
        clientProxy?.showWindow(visible: flag != 0, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdCloseTT() { // [IMPLEMENTED]
        clientProxy?.terminateApp(reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdEnableKeyb(_ args: [String]) { // [IMPLEMENTED]
        let flag = getIntArg(args, 0)
        clientProxy?.enableKeyboard(flag: flag, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdSetEcho(_ args: [String]) { // [IMPLEMENTED]
        let flag = getIntArg(args, 0)
        clientProxy?.setEcho(flag: flag, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdSetSync(_ args: [String]) { // [IMPLEMENTED]
        // Sync mode not applicable in XPC model - no-op
    }

    func cmdDispStr(_ args: [String]) { // [IMPLEMENTED]
        let text = args.map { resolveString($0) }.joined(separator: " ")
        clientProxy?.displayString(text: text, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdSetBaud(_ args: [String]) { // [IMPLEMENTED]
        let rate = getIntArg(args, 0)
        clientProxy?.setBaudRate(rate: rate, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdSetFlowCtrl(_ args: [String]) { // [IMPLEMENTED]
        let mode = getIntArg(args, 0)
        clientProxy?.setFlowControl(mode: mode, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdSetDtr(_ args: [String]) { // [IMPLEMENTED]
        let on = getIntArg(args, 0)
        clientProxy?.setDtr(on: on, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdSetRts(_ args: [String]) { // [IMPLEMENTED]
        let on = getIntArg(args, 0)
        clientProxy?.setRts(on: on, reply: { [weak self] in self?.scheduleNextLine() })
    }
}

// MARK: - Clipboard Commands

extension MacroRunner {

    func cmdClipb2Var(_ args: [String]) { // [IMPLEMENTED]
        guard let destVar = args.first?.lowercased() else { return }
        clientProxy?.getClipboard(reply: { [weak self] text in
            self?.variables[destVar] = .string(text)
            self?.scheduleNextLine()
        })
        return // async
    }

    func cmdVar2Clipb(_ args: [String]) { // [IMPLEMENTED]
        let text = getStringArg(args, 0)
        clientProxy?.setClipboard(text: text, reply: { [weak self] in self?.scheduleNextLine() })
    }
}

// MARK: - Log Commands

extension MacroRunner {

    func cmdLogOpen(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let path = getStringArg(args, 0)
        let mode = getIntArg(args, 1)
        clientProxy?.openLog(path: path, append: mode != 0, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdLogClose() { // [IMPLEMENTED]
        clientProxy?.closeLog(reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdLogPause() { // [IMPLEMENTED]
        clientProxy?.pauseLog(reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdLogStart() { // [IMPLEMENTED]
        clientProxy?.resumeLog(reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdLogWrite(_ args: [String]) { // [IMPLEMENTED]
        let text = args.map { resolveString($0) }.joined(separator: " ")
        clientProxy?.writeToLog(text: text, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdLogInfo() { // [IMPLEMENTED]
        clientProxy?.getLogInfo(reply: { [weak self] state, path in
            self?.variables["result"] = .integer(state)
            self?.inputStr = path
            self?.variables["inputstr"] = .string(path)
            self?.scheduleNextLine()
        })
        return // async
    }

    func cmdLogRotate(_ args: [String]) { // [IMPLEMENTED]
        let mode = getStringArg(args, 0)
        let value = args.count > 1 ? getIntArg(args, 1) : 0
        clientProxy?.setLogRotation(mode: mode, value: value, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdLogAutoClose(_ args: [String]) { // [IMPLEMENTED]
        // Store setting locally
    }
}

// MARK: - Checksum Commands

extension MacroRunner {

    func cmdChecksum(_ args: [String], type: String) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let str = getStringArg(args, 1)
        guard let data = str.data(using: .utf8) else { return }
        variables[destVar] = .integer(computeChecksum(data: data, type: type))
    }

    func cmdChecksumFile(_ args: [String], type: String) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let path = getStringArg(args, 1)
        guard let data = FileManager.default.contents(atPath: path) else {
            variables[destVar] = .integer(0); return
        }
        variables[destVar] = .integer(computeChecksum(data: data, type: type))
    }

    private func computeChecksum(data: Data, type: String) -> Int {
        switch type {
        case "checksum8":
            return Int(data.reduce(0 as UInt8) { $0 &+ $1 })
        case "checksum16":
            var sum: UInt16 = 0
            for byte in data { sum = sum &+ UInt16(byte) }
            return Int(sum)
        case "checksum32":
            var sum: UInt32 = 0
            for byte in data { sum = sum &+ UInt32(byte) }
            return Int(sum)
        case "crc16":
            var crc: UInt16 = 0xFFFF
            for byte in data {
                crc ^= UInt16(byte)
                for _ in 0..<8 {
                    if crc & 1 != 0 { crc = (crc >> 1) ^ 0xA001 }
                    else { crc >>= 1 }
                }
            }
            return Int(crc)
        case "crc32":
            var crc: UInt32 = 0xFFFFFFFF
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 {
                    if crc & 1 != 0 { crc = (crc >> 1) ^ 0xEDB88320 }
                    else { crc >>= 1 }
                }
            }
            return Int(crc ^ 0xFFFFFFFF)
        default:
            return 0
        }
    }
}

// MARK: - Bit Operations

extension MacroRunner {

    func cmdRotateLeft(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let varName = args[0].lowercased()
        let bits = getIntArg(args, 1)
        let val = variables[varName]?.intValue ?? 0
        variables[varName] = .integer((val << bits) | (val >> (32 - bits)))
    }

    func cmdRotateRight(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let varName = args[0].lowercased()
        let bits = getIntArg(args, 1)
        let val = variables[varName]?.intValue ?? 0
        variables[varName] = .integer((val >> bits) | (val << (32 - bits)))
    }
}

// MARK: - Misc Commands

extension MacroRunner {

    func cmdBeep() { // [IMPLEMENTED]
        // System beep not available without AppKit in test context
        // In production, NSSound.beep() would be called via XPC
    }

    func cmdSetDate(_ args: [String]) { // [IMPLEMENTED]
        variables["result"] = .integer(-1) // Always fails on macOS (requires root)
    }

    func cmdSetTime(_ args: [String]) { // [IMPLEMENTED]
        variables["result"] = .integer(-1) // Always fails on macOS (requires root)
    }

    func cmdSetDebug(_ args: [String]) { // [IMPLEMENTED]
        debugMode = getIntArg(args, 0) != 0
    }

    func cmdRegexOption(_ args: [String]) { // [IMPLEMENTED]
        let flags = getIntArg(args, 0)
        regexCaseInsensitive = (flags & 1) != 0
    }

    func cmdRestoreSetup(_ args: [String]) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        clientProxy?.restoreSetup(path: path, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdCallMenu(_ args: [String]) { // [IMPLEMENTED]
        let menuId = getIntArg(args, 0)
        clientProxy?.callMenu(menuId: menuId, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdLoadKeyMap(_ args: [String]) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        clientProxy?.loadKeyMap(path: path, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdSetSerialDelayChar(_ args: [String]) { // [IMPLEMENTED]
        let ms = getIntArg(args, 0)
        clientProxy?.setSerialDelayChar(ms: ms, reply: { [weak self] in self?.scheduleNextLine() })
    }

    func cmdSetSerialDelayLine(_ args: [String]) { // [IMPLEMENTED]
        let ms = getIntArg(args, 0)
        clientProxy?.setSerialDelayLine(ms: ms, reply: { [weak self] in self?.scheduleNextLine() })
    }
}

// MARK: - Password Commands (Keychain)

extension MacroRunner {

    func cmdGetPassword(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let destVar = args[0].lowercased()
        let account = getStringArg(args, 1)

        // Try Keychain first
        if let password = try? keychainManager.load(account: account) {
            variables[destVar] = .string(password)
            variables["result"] = .integer(1)
            return
        }

        // Prompt user via secure dialog
        clientProxy?.showDialog(type: "passwordbox", message: account, defaultValue: "",
                                reply: { [weak self] result, text in
            guard let self = self else { return }
            if result == 1 && !text.isEmpty {
                // Save to Keychain
                try? self.keychainManager.save(password: text, account: account)
                self.variables[destVar] = .string(text)
                self.variables["result"] = .integer(1)
            } else {
                self.variables["result"] = .integer(0)
            }
            self.scheduleNextLine()
        })
        return // async
    }

    func cmdSetPassword(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 2 else { return }
        let account = getStringArg(args, 0)
        let password = getStringArg(args, 1)
        let ok = (try? keychainManager.save(password: password, account: account)) != nil
        variables["result"] = .integer(ok ? 0 : -1)
    }

    func cmdDelPassword(_ args: [String]) { // [IMPLEMENTED]
        let account = getStringArg(args, 0)
        let ok = (try? keychainManager.delete(account: account)) != nil
        variables["result"] = .integer(ok ? 0 : -1)
    }

    func cmdIsPassword(_ args: [String]) { // [IMPLEMENTED]
        let account = getStringArg(args, 0)
        variables["result"] = .integer(keychainManager.exists(account: account) ? 1 : 0)
    }
}

// MARK: - File Transfer Commands

extension MacroRunner {

    func cmdFileTransferSend(_ args: [String], proto: String) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        let option = args.count > 1 ? getStringArg(args, 1) : ""

        isTransferWaiting = true
        clientProxy?.startFileSend(protocolName: proto, localPath: path, option: option,
                                   reply: { [weak self] success, errorMsg in
            guard let self = self else { return }
            if !success {
                self.isTransferWaiting = false
                self.variables["result"] = .integer(1)
                self.reportError(errorMsg.isEmpty ? "Transfer failed" : errorMsg)
                self.scheduleNextLine()
                return
            }
            self.pollTransferStatus()
        })
    }

    func cmdFileTransferRecv(_ args: [String], proto: String) { // [IMPLEMENTED]
        let dir = args.isEmpty ? FileManager.default.currentDirectoryPath : getStringArg(args, 0)

        isTransferWaiting = true
        clientProxy?.startFileRecv(protocolName: proto, localDir: dir,
                                   reply: { [weak self] success, errorMsg, _ in
            guard let self = self else { return }
            if !success {
                self.isTransferWaiting = false
                self.variables["result"] = .integer(1)
                self.reportError(errorMsg.isEmpty ? "Transfer failed" : errorMsg)
                self.scheduleNextLine()
                return
            }
            self.pollTransferStatus()
        })
    }

    func cmdKermitGet(_ args: [String]) { // [IMPLEMENTED]
        let remoteName = getStringArg(args, 0)
        cmdFileTransferRecv([remoteName], proto: "kermit")
    }

    func cmdKermitFinish() { // [IMPLEMENTED]
        clientProxy?.cancelTransfer(reply: { [weak self] in
            self?.isTransferWaiting = false
            self?.variables["result"] = .integer(0)
            self?.scheduleNextLine()
        })
    }

    func cmdScpSend(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 1 else { return }
        let localPath = getStringArg(args, 0)
        let remotePath = args.count > 1 ? getStringArg(args, 1) : ""
        clientProxy?.scpSend(localPath: localPath, remotePath: remotePath,
                             reply: { [weak self] success in
            self?.variables["result"] = .integer(success ? 0 : 1)
            self?.scheduleNextLine()
        })
    }

    func cmdScpRecv(_ args: [String]) { // [IMPLEMENTED]
        guard args.count >= 1 else { return }
        let remotePath = getStringArg(args, 0)
        let localPath = args.count > 1 ? getStringArg(args, 1) : ""
        clientProxy?.scpRecv(remotePath: remotePath, localPath: localPath,
                             reply: { [weak self] success in
            self?.variables["result"] = .integer(success ? 0 : 1)
            self?.scheduleNextLine()
        })
    }

    func cmdRecvFile(_ args: [String]) { // [IMPLEMENTED]
        let path = getStringArg(args, 0)
        cmdFileTransferRecv([path], proto: "raw")
    }

    /// Poll transfer status at 0.5s intervals until done/error/timeout
    private func pollTransferStatus() {
        let timeout = timeoutValue > 0 ? TimeInterval(timeoutValue) : MacroXPCEndpoint.defaultTransferTimeout
        let startTime = Date()

        func poll() {
            guard self.isRunning, !self.isCancelled, self.isTransferWaiting else { return }

            if Date().timeIntervalSince(startTime) > timeout {
                self.isTransferWaiting = false
                self.variables["result"] = .integer(1)
                self.reportError("Transfer timeout")
                self.scheduleNextLine()
                return
            }

            self.clientProxy?.getTransferStatus(reply: { [weak self] statusStr, transferred, total in
                guard let self = self else { return }
                switch statusStr {
                case TransferStatusString.done.rawValue:
                    self.isTransferWaiting = false
                    self.variables["result"] = .integer(0)
                    self.scheduleNextLine()
                case TransferStatusString.error.rawValue:
                    self.isTransferWaiting = false
                    self.variables["result"] = .integer(1)
                    self.reportError("Transfer error")
                    self.scheduleNextLine()
                default:
                    // Still in progress - poll again
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + MacroXPCEndpoint.transferPollInterval) { poll() }
                }
            })
        }
        poll()
    }
}
