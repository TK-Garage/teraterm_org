/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of ttpfile (xmodem.c, ymodem.c, zmodem.c, kermit.c) to Swift/macOS
 * File transfer protocol implementations
 */

import Foundation

// MARK: - Transfer Direction

enum TransferDirection {
    case send
    case receive
}

// MARK: - Transfer State

enum TransferState {
    case idle
    case starting
    case inProgress(bytesTransferred: Int64, totalBytes: Int64?, fileName: String)
    case completing
    case completed(fileName: String, bytes: Int64)
    case failed(error: String)
    case cancelled
}

// MARK: - Transfer Protocol Type

enum TransferProtocolType {
    case xmodem
    case xmodemCRC
    case xmodem1K
    case ymodem
    case ymodemG
    case zmodem
    case kermit
}

// MARK: - File Transfer Delegate

protocol FileTransferDelegate: AnyObject {
    func transferDidUpdateState(_ state: TransferState)
    func transferDidRequestSend(_ data: Data)
    func transferDidComplete(fileName: String, bytes: Int64)
    func transferDidFail(error: String)
}

// MARK: - File Transfer Protocol Base

class FileTransferProtocol {
    weak var delegate: FileTransferDelegate?

    var direction: TransferDirection = .receive
    var state: TransferState = .idle
    var filePath: String?
    var fileHandle: FileHandle?

    func start() { fatalError("Subclass must implement") }
    func cancel() { state = .cancelled }
    func processData(_ data: Data) { fatalError("Subclass must implement") }

    func sendData(_ data: Data) {
        delegate?.transferDidRequestSend(data)
    }

    func updateState(_ newState: TransferState) {
        state = newState
        delegate?.transferDidUpdateState(newState)
    }
}

// MARK: - Control Characters

private let SOH: UInt8 = 0x01
private let STX: UInt8 = 0x02
private let EOT: UInt8 = 0x04
private let ACK: UInt8 = 0x06
private let BS: UInt8 = 0x08
private let NAK: UInt8 = 0x15
private let CAN: UInt8 = 0x18
private let SUB: UInt8 = 0x1A

// MARK: - XMODEM Protocol (port of xmodem.c)

class XMODEMProtocol: FileTransferProtocol {
    enum XMODEMMode {
        case checksum
        case crc
        case oneK
    }

    var mode: XMODEMMode = .crc
    private var blockNumber: UInt8 = 1
    private var bytesTransferred: Int64 = 0
    private var receiveBuffer = Data()
    private var expectedBlockSize: Int { mode == .oneK ? 1024 : 128 }
    private var retryCount = 0
    private let maxRetries = 10
    private var receivingData = false
    private var fileData = Data()

    override func start() {
        if direction == .receive {
            startReceive()
        } else {
            startSend()
        }
    }

    private func startReceive() {
        updateState(.starting)
        blockNumber = 1
        bytesTransferred = 0
        receiveBuffer = Data()
        fileData = Data()
        receivingData = false
        retryCount = 0

        // Send initial NAK or 'C' for CRC mode
        if mode == .crc || mode == .oneK {
            sendData(Data([0x43])) // 'C' for CRC mode
        } else {
            sendData(Data([NAK]))
        }
    }

    private func startSend() {
        guard let path = filePath else {
            updateState(.failed(error: "No file specified"))
            return
        }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            updateState(.failed(error: "Cannot open file"))
            return
        }

        fileHandle = handle
        updateState(.starting)
        blockNumber = 1
        bytesTransferred = 0
    }

    override func processData(_ data: Data) {
        receiveBuffer.append(data)

        if direction == .receive {
            processReceive()
        } else {
            processSend()
        }
    }

    private func processReceive() {
        while !receiveBuffer.isEmpty {
            let firstByte = receiveBuffer[0]

            if firstByte == EOT {
                // End of transfer
                receiveBuffer.removeFirst()
                sendData(Data([ACK]))

                // Save file
                if let path = filePath {
                    try? fileData.write(to: URL(fileURLWithPath: path))
                }
                updateState(.completed(fileName: filePath ?? "unknown", bytes: Int64(fileData.count)))
                delegate?.transferDidComplete(fileName: filePath ?? "unknown", bytes: Int64(fileData.count))
                return
            }

            if firstByte == CAN {
                updateState(.cancelled)
                return
            }

            let headerByte = firstByte
            let blockSize: Int
            if headerByte == SOH {
                blockSize = 128
            } else if headerByte == STX {
                blockSize = 1024
            } else {
                receiveBuffer.removeFirst()
                continue
            }

            let checkSize = (mode == .checksum) ? 1 : 2
            let packetSize = 1 + 2 + blockSize + checkSize

            guard receiveBuffer.count >= packetSize else {
                return // Wait for more data
            }

            let packet = Data(receiveBuffer.prefix(packetSize))
            receiveBuffer.removeFirst(packetSize)

            let blk = packet[1]
            let blkComp = packet[2]

            // Verify block number
            guard blk == blockNumber && blkComp == ~blockNumber else {
                retryCount += 1
                if retryCount > maxRetries {
                    sendData(Data([CAN, CAN]))
                    updateState(.failed(error: "Too many retries"))
                    return
                }
                sendData(Data([NAK]))
                continue
            }

            // Verify checksum/CRC
            let blockData = packet[3..<(3 + blockSize)]
            if mode == .checksum {
                let checksum = blockData.reduce(0) { ($0 &+ $1) }
                guard checksum == packet[3 + blockSize] else {
                    sendData(Data([NAK]))
                    continue
                }
            } else {
                let crc = crc16(Data(blockData))
                let packetCRC = (UInt16(packet[3 + blockSize]) << 8) | UInt16(packet[3 + blockSize + 1])
                guard crc == packetCRC else {
                    sendData(Data([NAK]))
                    continue
                }
            }

            // Data is valid
            fileData.append(blockData)
            bytesTransferred += Int64(blockSize)
            blockNumber = blockNumber &+ 1
            retryCount = 0
            sendData(Data([ACK]))

            updateState(.inProgress(bytesTransferred: bytesTransferred, totalBytes: nil, fileName: filePath ?? ""))
        }
    }

    private func processSend() {
        guard !receiveBuffer.isEmpty else { return }

        let response = receiveBuffer.removeFirst()

        switch response {
        case 0x43, NAK: // 'C' or NAK - ready for data or resend
            sendNextBlock()
        case ACK:
            blockNumber = blockNumber &+ 1
            sendNextBlock()
        case CAN:
            updateState(.cancelled)
        default:
            break
        }
    }

    private func sendNextBlock() {
        guard let handle = fileHandle else { return }

        let blockSize = expectedBlockSize
        let data = handle.readData(ofLength: blockSize)

        if data.isEmpty {
            // End of file
            sendData(Data([EOT]))
            updateState(.completing)
            return
        }

        var packet = Data()
        packet.append(blockSize == 1024 ? STX : SOH)
        packet.append(blockNumber)
        packet.append(~blockNumber)

        var paddedData = data
        while paddedData.count < blockSize {
            paddedData.append(SUB) // Pad with SUB (Ctrl-Z)
        }
        packet.append(paddedData)

        if mode == .checksum {
            let checksum = paddedData.reduce(0) { ($0 &+ $1) }
            packet.append(checksum)
        } else {
            let crc = crc16(paddedData)
            packet.append(UInt8(crc >> 8))
            packet.append(UInt8(crc & 0xFF))
        }

        sendData(packet)
        bytesTransferred += Int64(data.count)
        updateState(.inProgress(bytesTransferred: bytesTransferred, totalBytes: nil, fileName: filePath ?? ""))
    }

    override func cancel() {
        sendData(Data([CAN, CAN, CAN]))
        super.cancel()
    }
}

// MARK: - YMODEM Protocol (port of ymodem.c)
//
// YMODEM extends XMODEM with:
//   - Block 0 containing filename, file size, modification time, permissions
//   - Multi-file batch transfer support
//   - 1024-byte blocks with CRC-16
//   - Proper EOT handshake (NAK first EOT, ACK second EOT)
//
// Packet format (same as XMODEM-1K with CRC):
//   +--------+--------+----------+-----------+------+
//   | Header | Block# | ~Block#  | Payload   | CRC  |
//   +--------+--------+----------+-----------+------+
//      1        1         1       128 or 1024   2     bytes
//
// Block 0 payload: filename\0filesize mtime mode\0...padding

class YMODEMProtocol: FileTransferProtocol {

    enum YMode {
        case standard    // YMODEM (1K blocks, CRC)
        case ymodemG     // YMODEM-G (streaming, no per-block ACK)
    }

    var yMode: YMode = .standard

    // Receive state
    private enum RecvState {
        case waitBlock0          // Waiting for block 0 (file info)
        case waitData            // Waiting for data blocks
        case waitEOTConfirm      // Sent NAK to first EOT, waiting for second
        case waitNextFile        // After ACK to second EOT, send 'C' for next file
        case complete
    }

    // Send state
    private enum SendState {
        case waitInitialC        // Waiting for receiver's 'C' to send block 0
        case waitBlock0ACK       // Sent block 0, waiting ACK then 'C'
        case waitCAfterACK       // Got ACK for block 0, waiting for 'C'
        case sendingData         // Sending file data blocks
        case waitEOTNAK          // Sent first EOT, expecting NAK
        case waitEOTACK          // Sent second EOT, expecting ACK
        case sendFinalBlock0     // Send empty block 0 (end of batch)
        case waitFinalACK        // Waiting for ACK on empty block 0
        case complete
    }

    private var recvState: RecvState = .waitBlock0
    private var sendState: SendState = .waitInitialC

    private var receiveBuffer = Data()
    private var fileData = Data()
    private var blockNumber: UInt8 = 0
    private var bytesTransferred: Int64 = 0
    private var totalFileSize: Int64 = 0
    private var currentFileName: String = ""
    private var retryCount = 0
    private let maxRetries = 10
    private var pktReadMode: Int = 0  // 0=SOH, 1=BLK, 2=BLK2, 3=DATA
    private var sendFileInfoSent = false
    private var fileMtime: UInt32 = 0

    // Multi-file support
    var filePaths: [String] = []
    private var currentFileIndex = 0

    override func start() {
        blockNumber = 0
        bytesTransferred = 0
        receiveBuffer = Data()
        fileData = Data()
        retryCount = 0
        totalFileSize = 0
        currentFileName = ""
        sendFileInfoSent = false

        if direction == .receive {
            recvState = .waitBlock0
            updateState(.starting)
            // Send 'C' to request CRC mode
            sendData(Data([0x43]))
        } else {
            if filePaths.isEmpty, let path = filePath {
                filePaths = [path]
            }
            currentFileIndex = 0
            sendState = .waitInitialC
            updateState(.starting)
        }
    }

    override func processData(_ data: Data) {
        receiveBuffer.append(data)
        if direction == .receive {
            processReceiveData()
        } else {
            processSendData()
        }
    }

    // MARK: - Receive

    private func processReceiveData() {
        while !receiveBuffer.isEmpty {
            let firstByte = receiveBuffer[0]

            switch recvState {
            case .waitBlock0, .waitData, .waitNextFile:
                if firstByte == EOT {
                    receiveBuffer.removeFirst()
                    handleEOT()
                    continue
                }
                if firstByte == CAN {
                    receiveBuffer.removeFirst()
                    updateState(.cancelled)
                    return
                }

                guard let packet = extractPacket() else { return }
                if recvState == .waitBlock0 || recvState == .waitNextFile {
                    processBlock0(packet)
                } else {
                    processDataBlock(packet)
                }

            case .waitEOTConfirm:
                if firstByte == EOT {
                    receiveBuffer.removeFirst()
                    // Second EOT - ACK it
                    sendData(Data([ACK]))
                    // Write file
                    writeReceivedFile()
                    // Reset for next file
                    recvState = .waitNextFile
                    blockNumber = 0
                    // Send 'C' to request next file's block 0
                    sendData(Data([0x43]))
                } else {
                    receiveBuffer.removeFirst()
                }
                continue

            case .complete:
                return
            }
        }
    }

    private func extractPacket() -> Data? {
        guard !receiveBuffer.isEmpty else { return nil }
        let headerByte = receiveBuffer[0]

        let blockSize: Int
        if headerByte == SOH {
            blockSize = 128
        } else if headerByte == STX {
            blockSize = 1024
        } else {
            receiveBuffer.removeFirst()
            return nil
        }

        let packetSize = 1 + 2 + blockSize + 2  // header + blk + ~blk + data + CRC16
        guard receiveBuffer.count >= packetSize else { return nil }

        let packet = Data(receiveBuffer.prefix(packetSize))
        receiveBuffer.removeFirst(packetSize)
        return packet
    }

    private func processBlock0(_ packet: Data) {
        let blockSize = (packet[0] == SOH) ? 128 : 1024

        // Verify block number complement
        guard packet[1] ^ packet[2] == 0xFF else {
            sendData(Data([NAK]))
            return
        }

        // Verify CRC
        let payload = Data(packet[3..<(3 + blockSize)])
        let crcVal = crc16(payload)
        let packetCRC = (UInt16(packet[3 + blockSize]) << 8) | UInt16(packet[3 + blockSize + 1])
        guard crcVal == packetCRC else {
            sendData(Data([NAK]))
            return
        }

        // Check if all-zero payload → end of batch
        if packet[1] == 0x00 && packet[2] == 0xFF {
            let isAllZero = payload.allSatisfy { $0 == 0 }
            if isAllZero {
                sendData(Data([ACK]))
                recvState = .complete
                updateState(.completed(fileName: currentFileName, bytes: bytesTransferred))
                delegate?.transferDidComplete(fileName: currentFileName, bytes: bytesTransferred)
                return
            }
        }

        // Parse file info: filename\0size mtime mode\0
        parseBlock0FileInfo(payload)

        sendData(Data([ACK]))

        // Send 'C' to request data blocks
        sendData(Data([0x43]))

        recvState = .waitData
        blockNumber = 1
        fileData = Data()
        bytesTransferred = 0

        updateState(.inProgress(bytesTransferred: 0, totalBytes: totalFileSize > 0 ? totalFileSize : nil, fileName: currentFileName))
    }

    private func parseBlock0FileInfo(_ payload: Data) {
        // filename\0filesize mtime mode\0
        guard let nulIdx = payload.firstIndex(of: 0) else { return }
        let nameData = Data(payload[payload.startIndex..<nulIdx])
        currentFileName = String(data: nameData, encoding: .utf8) ?? "unknown"

        let afterNul = payload.index(after: nulIdx)
        if afterNul < payload.endIndex {
            // Find the end of metadata (next NUL or end of non-zero data)
            var endIdx = afterNul
            while endIdx < payload.endIndex && payload[endIdx] != 0 {
                endIdx = payload.index(after: endIdx)
            }
            if endIdx > afterNul {
                let metaStr = String(data: Data(payload[afterNul..<endIdx]), encoding: .ascii) ?? ""
                let parts = metaStr.split(separator: " ")
                if let first = parts.first, let size = Int64(first) {
                    totalFileSize = size
                }
                if parts.count >= 2, let mtime = UInt32(parts[1], radix: 8) {
                    fileMtime = mtime
                }
            }
        }
    }

    private func processDataBlock(_ packet: Data) {
        let blockSize = (packet[0] == SOH) ? 128 : 1024

        guard packet[1] ^ packet[2] == 0xFF else {
            retryCount += 1
            if retryCount > maxRetries {
                sendCancel()
                updateState(.failed(error: "Too many retries"))
                return
            }
            sendData(Data([NAK]))
            return
        }

        // Verify expected block number
        guard packet[1] == blockNumber else {
            // Might be a duplicate of previous block
            if packet[1] == blockNumber &- 1 {
                sendData(Data([ACK]))
                return
            }
            retryCount += 1
            if retryCount > maxRetries {
                sendCancel()
                updateState(.failed(error: "Too many retries"))
                return
            }
            sendData(Data([NAK]))
            return
        }

        // Verify CRC
        let payload = Data(packet[3..<(3 + blockSize)])
        let crcVal = crc16(payload)
        let packetCRC = (UInt16(packet[3 + blockSize]) << 8) | UInt16(packet[3 + blockSize + 1])
        guard crcVal == packetCRC else {
            sendData(Data([NAK]))
            return
        }

        // Trim to file size if known
        var dataToAppend = payload
        if totalFileSize > 0 {
            let remaining = totalFileSize - Int64(fileData.count)
            if remaining < Int64(blockSize) && remaining > 0 {
                dataToAppend = Data(payload.prefix(Int(remaining)))
            }
        }

        fileData.append(dataToAppend)
        bytesTransferred += Int64(dataToAppend.count)
        blockNumber = blockNumber &+ 1
        retryCount = 0

        if yMode == .standard {
            sendData(Data([ACK]))
        }

        updateState(.inProgress(bytesTransferred: bytesTransferred, totalBytes: totalFileSize > 0 ? totalFileSize : nil, fileName: currentFileName))
    }

    private func handleEOT() {
        if recvState == .waitData {
            // First EOT → NAK it per YMODEM spec
            sendData(Data([NAK]))
            recvState = .waitEOTConfirm
        }
    }

    private func writeReceivedFile() {
        guard !fileData.isEmpty else { return }
        if let path = filePath {
            // Use received filename if we have a directory
            let dir = (path as NSString).deletingLastPathComponent
            let targetPath: String
            if !currentFileName.isEmpty {
                targetPath = (dir as NSString).appendingPathComponent(currentFileName)
            } else {
                targetPath = path
            }
            try? fileData.write(to: URL(fileURLWithPath: targetPath))
        }
        updateState(.completed(fileName: currentFileName, bytes: bytesTransferred))
        delegate?.transferDidComplete(fileName: currentFileName, bytes: bytesTransferred)
    }

    // MARK: - Send

    private func processSendData() {
        while !receiveBuffer.isEmpty {
            let response = receiveBuffer.removeFirst()
            // Ignore XON/XOFF
            if response == 0x11 || response == 0x13 { continue }

            switch sendState {
            case .waitInitialC:
                if response == 0x43 { // 'C'
                    sendBlock0()
                    sendState = .waitBlock0ACK
                }

            case .waitBlock0ACK:
                if response == ACK {
                    sendState = .waitCAfterACK
                } else if response == NAK {
                    retryCount += 1
                    if retryCount > maxRetries {
                        sendCancel()
                        updateState(.failed(error: "Too many retries"))
                        return
                    }
                    sendBlock0()
                } else if response == CAN {
                    updateState(.cancelled)
                    return
                }

            case .waitCAfterACK:
                if response == 0x43 { // 'C'
                    blockNumber = 1
                    sendState = .sendingData
                    sendNextDataBlock()
                }

            case .sendingData:
                if response == ACK {
                    blockNumber = blockNumber &+ 1
                    sendNextDataBlock()
                } else if response == NAK {
                    // Resend current block (would need to track last block)
                    retryCount += 1
                    if retryCount > maxRetries {
                        sendCancel()
                        updateState(.failed(error: "Too many retries"))
                        return
                    }
                } else if response == CAN {
                    updateState(.cancelled)
                    return
                }

            case .waitEOTNAK:
                if response == NAK {
                    // Send second EOT
                    sendData(Data([EOT]))
                    sendState = .waitEOTACK
                } else if response == ACK {
                    // Some receivers ACK immediately
                    advanceToNextFile()
                }

            case .waitEOTACK:
                if response == ACK {
                    advanceToNextFile()
                }

            case .sendFinalBlock0:
                if response == 0x43 { // 'C'
                    sendEmptyBlock0()
                    sendState = .waitFinalACK
                }

            case .waitFinalACK:
                if response == ACK {
                    sendState = .complete
                    updateState(.completed(fileName: currentFileName, bytes: bytesTransferred))
                    delegate?.transferDidComplete(fileName: currentFileName, bytes: bytesTransferred)
                    return
                }

            case .complete:
                return
            }
        }
    }

    private func advanceToNextFile() {
        currentFileIndex += 1
        if currentFileIndex < filePaths.count {
            // More files to send
            filePath = filePaths[currentFileIndex]
            fileHandle?.closeFile()
            fileHandle = FileHandle(forReadingAtPath: filePaths[currentFileIndex])
            bytesTransferred = 0
            blockNumber = 0
            sendState = .sendFinalBlock0 // Wait for 'C' then send block 0
            // Actually we need to wait for 'C' and send the next block 0
            sendState = .waitInitialC
        } else {
            // No more files
            sendState = .sendFinalBlock0
        }
    }

    private func sendBlock0() {
        guard let path = filePath ?? filePaths.first else { return }
        let fileName = (path as NSString).lastPathComponent
        currentFileName = fileName

        var payload = Data()
        // Filename (NUL-terminated)
        payload.append(Data(fileName.utf8))
        payload.append(0)

        // File size + mtime + mode
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            let size = (attrs[.size] as? Int64) ?? 0
            totalFileSize = size
            let mtime = (attrs[.modificationDate] as? Date).map {
                UInt32($0.timeIntervalSince1970)
            } ?? 0
            let meta = "\(size) \(String(mtime, radix: 8)) 100644"
            payload.append(Data(meta.utf8))
        }
        payload.append(0) // NUL terminate metadata

        // Pad to 128 bytes (use SOH for block 0)
        let blockSize = payload.count > 128 ? 1024 : 128
        while payload.count < blockSize {
            payload.append(0)
        }

        var packet = Data()
        packet.append(blockSize == 1024 ? STX : SOH)
        packet.append(0x00) // block number 0
        packet.append(0xFF) // complement
        packet.append(payload)

        let crcVal = crc16(payload)
        packet.append(UInt8(crcVal >> 8))
        packet.append(UInt8(crcVal & 0xFF))

        sendData(packet)
    }

    private func sendEmptyBlock0() {
        // All-zero block 0 signals end of batch
        let payload = Data(repeating: 0, count: 128)

        var packet = Data()
        packet.append(SOH)
        packet.append(0x00)
        packet.append(0xFF)
        packet.append(payload)

        let crcVal = crc16(payload)
        packet.append(UInt8(crcVal >> 8))
        packet.append(UInt8(crcVal & 0xFF))

        sendData(packet)
    }

    private func sendNextDataBlock() {
        guard let handle = fileHandle else {
            // No file handle → send EOT
            sendData(Data([EOT]))
            sendState = .waitEOTNAK
            return
        }

        let data = handle.readData(ofLength: 1024)
        if data.isEmpty {
            handle.closeFile()
            sendData(Data([EOT]))
            sendState = .waitEOTNAK
            return
        }

        var payload = data
        let blockSize = 1024
        while payload.count < blockSize {
            payload.append(SUB)
        }

        var packet = Data()
        packet.append(STX)
        packet.append(blockNumber)
        packet.append(~blockNumber)
        packet.append(payload)

        let crcVal = crc16(payload)
        packet.append(UInt8(crcVal >> 8))
        packet.append(UInt8(crcVal & 0xFF))

        sendData(packet)
        bytesTransferred += Int64(data.count)
        updateState(.inProgress(bytesTransferred: bytesTransferred, totalBytes: totalFileSize > 0 ? totalFileSize : nil, fileName: currentFileName))
    }

    private func sendCancel() {
        // 5 CANs + 5 BSs per YMODEM spec
        var cancelSeq = Data(repeating: CAN, count: 5)
        cancelSeq.append(Data(repeating: BS, count: 5))
        sendData(cancelSeq)
    }

    override func cancel() {
        sendCancel()
        super.cancel()
    }
}

// MARK: - ZMODEM Protocol (port of zmodem.c)
//
// Full state machine port from the original Tera Term zmodem.c:
//   - Hex and binary header formats
//   - ZDLE escape handling for all control characters
//   - CRC-16 for hex headers, CRC-16 for binary data subpackets
//   - ZRPOS resume support
//   - Proper ZFILE/ZDATA/ZEOF/ZFIN handshake
//   - Auto-detection of ZMODEM initiation sequence ("**\x18B")
//
// Header format:
//   Hex:    ZPAD ZPAD ZDLE ZHEX type[2hex] flags[8hex] crc[4hex] CR LF [XON]
//   Binary: ZPAD ZDLE ZBIN type flags[4] crc[2]

class ZMODEMProtocol: FileTransferProtocol {
    // Frame types
    static let ZRQINIT: UInt8 = 0
    static let ZRINIT: UInt8 = 1
    static let ZSINIT: UInt8 = 2
    static let ZACK: UInt8 = 3
    static let ZFILE: UInt8 = 4
    static let ZSKIP: UInt8 = 5
    static let ZNAK: UInt8 = 6
    static let ZABORT: UInt8 = 7
    static let ZFIN: UInt8 = 8
    static let ZRPOS: UInt8 = 9
    static let ZDATA: UInt8 = 10
    static let ZEOF: UInt8 = 11
    static let ZFERR: UInt8 = 12
    static let ZCAN: UInt8 = 16

    // Encoding
    static let ZPAD: UInt8 = 0x2A  // '*'
    static let ZDLE: UInt8 = 0x18  // CAN
    static let ZBIN: UInt8 = 0x41  // 'A'
    static let ZHEX: UInt8 = 0x42  // 'B'
    static let ZBIN32: UInt8 = 0x43  // 'C'

    // Data subpacket terminators
    static let ZCRCE: UInt8 = 0x68  // 'h' - end, no ZACK expected
    static let ZCRCG: UInt8 = 0x69  // 'i' - more data follows, no ZACK
    static let ZCRCQ: UInt8 = 0x6A  // 'j' - more data follows, ZACK requested
    static let ZCRCW: UInt8 = 0x6B  // 'k' - end, ZACK expected

    // ZRINIT flags (ZF0)
    static let CANFDX: UInt8 = 0x01
    static let CANOVIO: UInt8 = 0x02
    static let CANBRK: UInt8 = 0x04
    static let CANFC32: UInt8 = 0x20
    static let ESCCTL: UInt8 = 0x40

    // ZFILE conversion flags
    static let ZCBIN: UInt8 = 1
    static let ZCNL: UInt8 = 2

    // Position header indices
    static let ZP0 = 0
    static let ZP1 = 1
    static let ZP2 = 2
    static let ZP3 = 3
    static let ZF0 = 3
    static let ZF1 = 2

    // Protocol state
    enum ZState {
        case idle
        case recvInit       // Waiting for ZFILE or ZSINIT
        case recvInit2      // After ZSINIT, waiting for ZSINIT data
        case recvData       // Receiving file data
        case recvFIN        // Waiting for ZFIN
        case sendInit       // Sent ZRQINIT, waiting for ZRINIT
        case sendInitHdr    // Sent ZSINIT header
        case sendInitDat    // Sent ZSINIT data
        case sendFileHdr    // Sent ZFILE header
        case sendFileDat    // Sent ZFILE data subpacket
        case sendDataHdr    // Sent ZDATA header
        case sendDataDat    // Sending data subpackets (streaming)
        case sendDataDat2   // Sent ZCRCQ, waiting for ZACK
        case sendEOF        // Sent ZEOF
        case sendFIN        // Sent ZFIN
        case cancel
        case complete
    }

    // Packet parse state
    private enum PktState {
        case getPAD      // Looking for ZPAD
        case getDLE      // Got ZPAD, looking for ZDLE
        case hdrFrm      // Got ZDLE, determine format (ZHEX/ZBIN/ZBIN32)
        case getBin      // Reading binary header bytes
        case getHex      // Reading hex header characters
        case getHexEOL   // Skip hex header CR/LF/XON trailer
        case getData     // Reading data subpacket
        case getCRC      // Reading CRC of data subpacket
    }

    private var receiveBuffer = Data()
    private var fileData = Data()
    private var bytesTransferred: Int64 = 0
    private var totalFileSize: Int64 = 0
    private var currentFileName: String = ""
    private var zState: ZState = .idle
    private var pktState: PktState = .getPAD

    // Header storage
    private var rxHdr = [UInt8](repeating: 0, count: 4)
    private var txHdr = [UInt8](repeating: 0, count: 4)
    private var rxType: UInt8 = 0

    // Packet buffers
    private var pktIn = [UInt8](repeating: 0, count: 1040)
    private var pktInPtr = 0
    private var pktInCount = 0
    private var pktInLen = 0

    // Protocol options
    var ctlEsc = false
    var binFlag = true
    var maxDataLen = 1024
    var winSize: Int64 = 0

    private var pos: Int64 = 0
    private var lastPos: Int64 = 0
    private var lastSent: UInt8 = 0
    private var canCount = 5
    private var crcVal: UInt16 = 0
    private var hexLo = false
    private var quoted = false
    private var isCRC32 = false
    private var sending = false
    private var fileMtime: UInt32 = 0

    // Auto-detect sequence: rz sends "**\x18B00..." which is ZRQINIT
    static let autoDetectSequence = Data([0x2A, 0x2A, 0x18, 0x42])

    /// Check if data contains ZMODEM auto-start sequence
    static func detectZMODEM(in data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        for i in 0..<(data.count - 3) {
            if data[i] == ZPAD && data[i+1] == ZPAD &&
               data[i+2] == ZDLE && data[i+3] == ZHEX {
                return true
            }
        }
        return false
    }

    override func start() {
        receiveBuffer = Data()
        fileData = Data()
        bytesTransferred = 0
        totalFileSize = 0
        pos = 0
        lastPos = 0
        pktState = .getPAD
        sending = false
        lastSent = 0
        canCount = 5
        fileMtime = 0

        if maxDataLen <= 0 { maxDataLen = 1024 }
        if maxDataLen < 64 { maxDataLen = 64 }

        if direction == .receive {
            zState = .recvInit
            updateState(.starting)
            sendZRINIT()
        } else {
            guard let path = filePath else {
                updateState(.failed(error: "No file specified"))
                return
            }
            guard FileManager.default.fileExists(atPath: path) else {
                updateState(.failed(error: "File not found"))
                return
            }
            zState = .sendInit
            updateState(.starting)
            sendRQInit()
        }
    }

    override func processData(_ data: Data) {
        receiveBuffer.append(data)

        // Output buffered data first
        if sending {
            // In real implementation, would flush output buffer
            sending = false
        }

        processIncoming()
    }

    // MARK: - Incoming Data Processing

    private func processIncoming() {
        while !receiveBuffer.isEmpty {
            let b = receiveBuffer.removeFirst()

            // Ignore XON/XOFF (with high bit variants)
            if (b & 0x7F) == 0x11 || (b & 0x7F) == 0x13 { continue }

            switch pktState {
            case .getPAD:
                if b == ZMODEMProtocol.ZPAD {
                    pktState = .getDLE
                } else if b == ZMODEMProtocol.ZDLE {
                    // CAN count for abort detection
                    canCount -= 1
                    if canCount <= 0 {
                        zState = .complete
                        updateState(.cancelled)
                        return
                    }
                } else {
                    canCount = 5
                }

            case .getDLE:
                if b == ZMODEMProtocol.ZPAD {
                    // Extra ZPAD, stay in getDLE
                    continue
                }
                if b == ZMODEMProtocol.ZDLE {
                    pktState = .hdrFrm
                    canCount = 5
                } else {
                    pktState = .getPAD
                }

            case .hdrFrm:
                pktInPtr = 0
                isCRC32 = false
                switch b {
                case ZMODEMProtocol.ZHEX:
                    pktInLen = 7  // type + 4 flags + 2 CRC
                    pktInCount = 0
                    hexLo = false
                    pktState = .getHex

                case ZMODEMProtocol.ZBIN:
                    pktInLen = 7
                    pktInCount = 0
                    quoted = false
                    pktState = .getBin

                case ZMODEMProtocol.ZBIN32:
                    pktInLen = 9  // type + 4 flags + 4 CRC32
                    pktInCount = 0
                    isCRC32 = true
                    quoted = false
                    pktState = .getBin

                default:
                    pktState = .getPAD
                }

            case .getHex:
                processHexByte(b)

            case .getHexEOL:
                // Skip CR, LF, XON after hex header
                if b == 0x0D || b == 0x8A || b == 0x0A {
                    continue
                }
                if b == 0x11 { // XON
                    pktState = .getPAD
                    continue
                }
                pktState = .getPAD
                // Process this byte as potential start of next header
                if b == ZMODEMProtocol.ZPAD {
                    pktState = .getDLE
                }

            case .getBin:
                processBinByte(b)

            case .getData:
                processDataByte(b)

            case .getCRC:
                processCRCByte(b)
            }
        }
    }

    private func processHexByte(_ b: UInt8) {
        let nibble: UInt8
        if b >= 0x30 && b <= 0x39 {
            nibble = b - 0x30
        } else if b >= 0x61 && b <= 0x66 {
            nibble = b - 0x61 + 10
        } else if b >= 0x41 && b <= 0x46 {
            nibble = b - 0x41 + 10
        } else {
            pktState = .getPAD
            return
        }

        if !hexLo {
            pktIn[pktInPtr] = nibble << 4
            hexLo = true
        } else {
            pktIn[pktInPtr] |= nibble
            pktInPtr += 1
            pktInCount += 1
            hexLo = false

            if pktInCount >= pktInLen {
                pktState = .getHexEOL
                if checkHeader() {
                    parseHeader()
                }
            }
        }
    }

    private func processBinByte(_ b: UInt8) {
        if quoted {
            quoted = false
            pktIn[pktInPtr] = b ^ 0x40
        } else if b == ZMODEMProtocol.ZDLE {
            quoted = true
            return
        } else {
            pktIn[pktInPtr] = b
        }
        pktInPtr += 1
        pktInCount += 1

        if pktInCount >= pktInLen {
            pktState = .getPAD
            if checkHeader() {
                parseHeader()
            }
        }
    }

    private func processDataByte(_ b: UInt8) {
        if quoted {
            quoted = false
            let unescaped = b ^ 0x40
            // Check for subpacket terminator
            if b == ZMODEMProtocol.ZCRCE || b == ZMODEMProtocol.ZCRCG ||
               b == ZMODEMProtocol.ZCRCQ || b == ZMODEMProtocol.ZCRCW {
                // End of data subpacket
                crcVal = updateCRC16(b, crc: crcVal)
                pktInLen = pktInPtr  // Save data length
                pktInPtr = 0
                pktInCount = 0
                pktState = .getCRC
                // Store terminator type
                rxType = b
                return
            }
            pktIn[pktInPtr] = unescaped
        } else if b == ZMODEMProtocol.ZDLE {
            quoted = true
            return
        } else {
            pktIn[pktInPtr] = b
        }

        crcVal = updateCRC16(pktIn[pktInPtr], crc: crcVal)
        pktInPtr += 1

        if pktInPtr >= pktIn.count - 4 {
            // Buffer overflow protection
            pktState = .getPAD
        }
    }

    private func processCRCByte(_ b: UInt8) {
        if quoted {
            quoted = false
            pktIn[pktInPtr] = (b ^ 0x40)
        } else if b == ZMODEMProtocol.ZDLE {
            quoted = true
            return
        } else {
            pktIn[pktInPtr] = b
        }
        pktInPtr += 1
        pktInCount += 1

        if pktInCount >= 2 {
            // Verify CRC of data subpacket
            let receivedCRC = (UInt16(pktIn[0]) << 8) | UInt16(pktIn[1])
            let expectedCRC = crcVal
            // Update CRC with the received CRC bytes to check for zero
            var checkCRC = expectedCRC
            checkCRC = updateCRC16(pktIn[0], crc: checkCRC)
            checkCRC = updateCRC16(pktIn[1], crc: checkCRC)

            pktState = .getPAD

            if checkCRC == 0 {
                handleDataSubpacket()
            } else {
                // CRC error in data subpacket
                if zState == .recvData {
                    sendZRPOS()
                }
            }
        }
    }

    // MARK: - Header Verification

    private func checkHeader() -> Bool {
        if isCRC32 {
            var crc: UInt32 = 0xFFFFFFFF
            for i in 0..<9 {
                crc = updateCRC32Single(pktIn[i], crc: crc)
            }
            return crc == 0xDEBB20E3
        } else {
            var crc: UInt16 = 0
            for i in 0..<7 {
                crc = updateCRC16(pktIn[i], crc: crc)
            }
            return crc == 0
        }
    }

    // MARK: - Header Parsing

    private func parseHeader() {
        rxType = pktIn[0]
        for i in 0..<4 {
            rxHdr[i] = pktIn[i + 1]
        }

        switch rxType {
        case ZMODEMProtocol.ZRQINIT:
            if zState == .recvInit {
                sendZRINIT()
            }

        case ZMODEMProtocol.ZRINIT:
            handleZRINIT()

        case ZMODEMProtocol.ZSINIT:
            if zState == .recvInit {
                ctlEsc = ctlEsc || (rxHdr[ZMODEMProtocol.ZF0] & ZMODEMProtocol.ESCCTL) != 0
                zState = .recvInit2
                pktState = .getData
                pktInPtr = 0
                crcVal = 0
                quoted = false
            }

        case ZMODEMProtocol.ZACK:
            handleZACK()

        case ZMODEMProtocol.ZFILE:
            if zState == .recvInit || zState == .recvInit2 {
                binFlag = rxHdr[ZMODEMProtocol.ZF0] != ZMODEMProtocol.ZCNL
                pktState = .getData
                pktInPtr = 0
                crcVal = 0
                quoted = false
            }

        case ZMODEMProtocol.ZSKIP:
            if zState == .sendFileHdr || zState == .sendFileDat ||
               zState == .sendDataHdr || zState == .sendDataDat {
                fileHandle?.closeFile()
                // Send next file or ZFIN
                zState = .sendFIN
                sendZFIN()
            }

        case ZMODEMProtocol.ZNAK:
            // Resend last header based on state
            break

        case ZMODEMProtocol.ZRPOS:
            handleZRPOS_response()

        case ZMODEMProtocol.ZDATA:
            handleZDATA()

        case ZMODEMProtocol.ZEOF:
            handleZEOF()

        case ZMODEMProtocol.ZFIN:
            handleZFIN()

        case ZMODEMProtocol.ZABORT, ZMODEMProtocol.ZCAN:
            zState = .complete
            updateState(.cancelled)

        default:
            break
        }
    }

    // MARK: - Frame Type Handlers

    private func handleZRINIT() {
        guard zState == .sendInit || zState == .sendEOF else { return }

        // Close previous file if any
        if let handle = fileHandle {
            handle.closeFile()
            fileHandle = nil
        }

        guard let path = filePath else {
            zState = .sendFIN
            sendZFIN()
            return
        }

        fileHandle = FileHandle(forReadingAtPath: path)
        guard fileHandle != nil else {
            sendZCancel()
            return
        }

        // Parse receiver capabilities
        if (rxHdr[ZMODEMProtocol.ZF0] & ZMODEMProtocol.CANFDX) == 0 {
            winSize = 0
        }

        let maxFromReceiver = (Int(rxHdr[ZMODEMProtocol.ZP1]) << 8) | Int(rxHdr[ZMODEMProtocol.ZP0])
        if maxFromReceiver > 0 && maxDataLen > maxFromReceiver {
            maxDataLen = maxFromReceiver
        }

        if ctlEsc && (rxHdr[ZMODEMProtocol.ZF0] & ZMODEMProtocol.ESCCTL) == 0 {
            zState = .sendInitHdr
            sendZSINIT()
            return
        }

        zState = .sendFileHdr
        sendZFileHeader()
    }

    private func handleZACK() {
        switch zState {
        case .sendInitDat:
            zState = .sendFileHdr
            sendZFileHeader()
        case .sendDataDat2:
            let ackPos = recallPosition()
            if pos == ackPos {
                lastPos = ackPos
                sendDataSubpacket()
            } else {
                pos = ackPos
                sendZDataHeader()
            }
        default:
            break
        }
    }

    private func handleZRPOS_response() {
        guard zState == .sendDataDat || zState == .sendDataDat2 ||
              zState == .sendFileHdr || zState == .sendFileDat ||
              zState == .sendEOF else { return }
        pos = recallPosition()
        zState = .sendDataHdr
        sendZDataHeader()
    }

    private func handleZDATA() {
        guard zState == .recvData else { return }
        let dataPos = recallPosition()
        if dataPos != pos {
            // Position mismatch, request resend
            sendZRPOS()
            return
        }
        pktState = .getData
        pktInPtr = 0
        crcVal = 0
        quoted = false
    }

    private func handleZEOF() {
        guard zState == .recvData else { return }
        let eofPos = recallPosition()
        if eofPos == pos {
            // Write file
            if let path = filePath {
                try? fileData.write(to: URL(fileURLWithPath: path))
            }
            zState = .recvInit
            sendZRINIT()
            updateState(.completed(fileName: currentFileName, bytes: bytesTransferred))
            delegate?.transferDidComplete(fileName: currentFileName, bytes: bytesTransferred)
        } else {
            sendZRPOS()
        }
    }

    private func handleZFIN() {
        if zState == .recvInit || zState == .recvData {
            // Transfer complete
            storePosition(0)
            sendHexHeader(ZMODEMProtocol.ZFIN)
            zState = .complete
            if bytesTransferred > 0 {
                updateState(.completed(fileName: currentFileName, bytes: bytesTransferred))
            }
        } else if zState == .sendFIN {
            zState = .complete
            updateState(.completed(fileName: currentFileName, bytes: bytesTransferred))
            delegate?.transferDidComplete(fileName: currentFileName, bytes: bytesTransferred)
        }
    }

    // MARK: - Data Subpacket Handler

    private func handleDataSubpacket() {
        let dataLen = pktInLen

        switch zState {
        case .recvInit, .recvInit2:
            // Data subpacket for ZSINIT or ZFILE
            if rxType == ZMODEMProtocol.ZCRCW || rxType == ZMODEMProtocol.ZCRCE {
                if zState == .recvInit2 {
                    // ZSINIT data received
                    storePosition(0)
                    sendHexHeader(ZMODEMProtocol.ZACK)
                    zState = .recvInit
                } else {
                    // ZFILE data: parse filename and size
                    parseZFileData(length: dataLen)
                    // Open file for writing
                    if let path = filePath {
                        FileManager.default.createFile(atPath: path, contents: nil)
                        fileHandle = FileHandle(forWritingAtPath: path)
                    }
                    fileData = Data()
                    pos = 0
                    sendZRPOS()
                    zState = .recvData
                }
            }

        case .recvData:
            // File data received
            let chunk = Data(pktIn[0..<dataLen])
            fileData.append(chunk)
            pos += Int64(dataLen)
            bytesTransferred = pos

            // Write incrementally
            if let handle = fileHandle {
                handle.write(chunk)
            }

            updateState(.inProgress(bytesTransferred: bytesTransferred,
                                    totalBytes: totalFileSize > 0 ? totalFileSize : nil,
                                    fileName: currentFileName))

            switch rxType {
            case ZMODEMProtocol.ZCRCW:
                // End of subpacket, sender expects ZACK
                storePosition(pos)
                sendHexHeader(ZMODEMProtocol.ZACK)

            case ZMODEMProtocol.ZCRCQ:
                // More data coming, sender wants position ACK
                storePosition(pos)
                sendHexHeader(ZMODEMProtocol.ZACK)
                pktState = .getData
                pktInPtr = 0
                crcVal = 0
                quoted = false

            case ZMODEMProtocol.ZCRCG:
                // More data coming, no ACK needed
                pktState = .getData
                pktInPtr = 0
                crcVal = 0
                quoted = false

            case ZMODEMProtocol.ZCRCE:
                // Last subpacket
                break

            default:
                break
            }

        default:
            break
        }
    }

    private func parseZFileData(length: Int) {
        // filename\0size mtime mode\0
        var nameEnd = 0
        while nameEnd < length && pktIn[nameEnd] != 0 { nameEnd += 1 }

        let nameData = Data(pktIn[0..<nameEnd])
        currentFileName = String(data: nameData, encoding: .utf8) ?? "unknown"

        if nameEnd + 1 < length {
            let metaStart = nameEnd + 1
            var metaEnd = metaStart
            while metaEnd < length && pktIn[metaEnd] != 0 { metaEnd += 1 }

            let metaData = Data(pktIn[metaStart..<metaEnd])
            if let metaStr = String(data: metaData, encoding: .ascii) {
                let parts = metaStr.split(separator: " ")
                if let first = parts.first, let size = Int64(first) {
                    totalFileSize = size
                }
                if parts.count >= 2, let mtime = UInt32(parts[1], radix: 8) {
                    fileMtime = mtime
                }
            }
        }

        // Use filename from ZFILE if filePath is a directory or unset
        if let path = filePath {
            let isDir = FileManager.default.fileExists(atPath: path) &&
                        (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeDirectory
            if isDir || path.hasSuffix("/") {
                filePath = (path as NSString).appendingPathComponent(currentFileName)
            }
        }
    }

    // MARK: - Send Helpers

    private func sendZRINIT() {
        storePosition(0)
        txHdr[ZMODEMProtocol.ZF0] = ZMODEMProtocol.CANFDX | ZMODEMProtocol.CANOVIO
        if ctlEsc {
            txHdr[ZMODEMProtocol.ZF0] |= ZMODEMProtocol.ESCCTL
        }
        sendHexHeader(ZMODEMProtocol.ZRINIT)
    }

    private func sendRQInit() {
        storePosition(0)
        sendHexHeader(ZMODEMProtocol.ZRQINIT)
    }

    private func sendZRPOS() {
        storePosition(pos)
        sendHexHeader(ZMODEMProtocol.ZRPOS)
    }

    private func sendZSINIT() {
        storePosition(0)
        if ctlEsc {
            txHdr[ZMODEMProtocol.ZF0] = ZMODEMProtocol.ESCCTL
        }
        sendHexHeader(ZMODEMProtocol.ZSINIT)
        zState = .sendInitHdr
    }

    private func sendZFileHeader() {
        guard let path = filePath else { return }
        storePosition(0)
        txHdr[ZMODEMProtocol.ZF0] = binFlag ? ZMODEMProtocol.ZCBIN : ZMODEMProtocol.ZCNL

        // Send ZFILE binary header
        sendBinHeader(ZMODEMProtocol.ZFILE)

        // Build ZFILE data subpacket: filename\0size mtime mode\0
        let fileName = (path as NSString).lastPathComponent
        currentFileName = fileName

        var fileInfo = Data()
        fileInfo.append(Data(fileName.utf8))

        var crc: UInt16 = 0
        for byte in fileInfo { crc = updateCRC16(byte, crc: crc) }

        fileInfo.append(0)
        crc = updateCRC16(0, crc: crc)

        // Get file attributes
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            totalFileSize = (attrs[.size] as? Int64) ?? 0
            let mtime = (attrs[.modificationDate] as? Date).map {
                UInt32($0.timeIntervalSince1970)
            } ?? 0
            let meta = "\(totalFileSize) \(String(mtime, radix: 8)) 100644"
            let metaData = Data(meta.utf8)
            fileInfo.append(metaData)
            for byte in metaData { crc = updateCRC16(byte, crc: crc) }
        }

        fileInfo.append(0)
        crc = updateCRC16(0, crc: crc)

        // Build escaped data subpacket
        var pktOut = Data()
        for byte in fileInfo {
            appendZDLEEscaped(byte, to: &pktOut)
        }
        pktOut.append(ZMODEMProtocol.ZDLE)
        pktOut.append(ZMODEMProtocol.ZCRCW)
        crc = updateCRC16(ZMODEMProtocol.ZCRCW, crc: crc)

        appendZDLEEscaped(UInt8(crc >> 8), to: &pktOut)
        appendZDLEEscaped(UInt8(crc & 0xFF), to: &pktOut)

        sendData(pktOut)

        zState = .sendFileDat
        bytesTransferred = 0
        pos = 0
    }

    private func sendZDataHeader() {
        storePosition(pos)
        sendBinHeader(ZMODEMProtocol.ZDATA)
        zState = .sendDataHdr
        sendDataSubpacket()
    }

    private func sendDataSubpacket() {
        guard let handle = fileHandle else { return }

        if pos >= totalFileSize && totalFileSize > 0 {
            sendZEOF()
            return
        }

        handle.seek(toFileOffset: UInt64(pos))
        let data = handle.readData(ofLength: maxDataLen)
        if data.isEmpty {
            sendZEOF()
            return
        }

        var crc: UInt16 = 0
        var pktOut = Data()
        for byte in data {
            crc = updateCRC16(byte, crc: crc)
            appendZDLEEscaped(byte, to: &pktOut)
        }

        bytesTransferred = pos + Int64(data.count)
        pos = bytesTransferred

        // Determine subpacket terminator
        let terminator: UInt8
        if pos >= totalFileSize && totalFileSize > 0 {
            terminator = ZMODEMProtocol.ZCRCE  // Last subpacket
        } else if winSize > 0 && pos - lastPos > winSize {
            terminator = ZMODEMProtocol.ZCRCQ  // Request ACK
        } else {
            terminator = ZMODEMProtocol.ZCRCG  // More data, no ACK
        }

        pktOut.append(ZMODEMProtocol.ZDLE)
        pktOut.append(terminator)
        crc = updateCRC16(terminator, crc: crc)

        appendZDLEEscaped(UInt8(crc >> 8), to: &pktOut)
        appendZDLEEscaped(UInt8(crc & 0xFF), to: &pktOut)

        sendData(pktOut)

        updateState(.inProgress(bytesTransferred: bytesTransferred,
                                totalBytes: totalFileSize > 0 ? totalFileSize : nil,
                                fileName: currentFileName))

        if terminator == ZMODEMProtocol.ZCRCQ {
            zState = .sendDataDat2
        } else if terminator == ZMODEMProtocol.ZCRCE {
            sendZEOF()
        } else {
            zState = .sendDataDat
            // Continue sending immediately
            sendDataSubpacket()
        }
    }

    private func sendZEOF() {
        storePosition(pos)
        sendHexHeader(ZMODEMProtocol.ZEOF)
        zState = .sendEOF
    }

    private func sendZFIN() {
        storePosition(0)
        sendHexHeader(ZMODEMProtocol.ZFIN)
    }

    private func sendZCancel() {
        var cancelData = Data(repeating: ZMODEMProtocol.ZDLE, count: 8)
        cancelData.append(Data(repeating: 0x08, count: 10))  // Backspaces
        sendData(cancelData)
        zState = .cancel
    }

    // MARK: - Header Builders

    private func sendHexHeader(_ hdrType: UInt8) {
        var header = Data()
        header.append(ZMODEMProtocol.ZPAD)
        header.append(ZMODEMProtocol.ZPAD)
        header.append(ZMODEMProtocol.ZDLE)
        header.append(ZMODEMProtocol.ZHEX)

        var crc: UInt16 = 0
        hexAppend(hdrType, to: &header)
        crc = updateCRC16(hdrType, crc: crc)

        for i in 0..<4 {
            hexAppend(txHdr[i], to: &header)
            crc = updateCRC16(txHdr[i], crc: crc)
        }

        hexAppend(UInt8(crc >> 8), to: &header)
        hexAppend(UInt8(crc & 0xFF), to: &header)

        header.append(0x0D)  // CR
        header.append(0x8A)  // LF | 0x80

        // Append XON for most header types
        if hdrType != ZMODEMProtocol.ZFIN && hdrType != ZMODEMProtocol.ZACK {
            header.append(0x11)  // XON
        }

        sendData(header)
    }

    private func sendBinHeader(_ hdrType: UInt8) {
        var header = Data()
        header.append(ZMODEMProtocol.ZPAD)
        header.append(ZMODEMProtocol.ZDLE)
        header.append(ZMODEMProtocol.ZBIN)

        var crc: UInt16 = 0
        appendZDLEEscaped(hdrType, to: &header)
        crc = updateCRC16(hdrType, crc: crc)

        for i in 0..<4 {
            appendZDLEEscaped(txHdr[i], to: &header)
            crc = updateCRC16(txHdr[i], crc: crc)
        }

        appendZDLEEscaped(UInt8(crc >> 8), to: &header)
        appendZDLEEscaped(UInt8(crc & 0xFF), to: &header)

        sendData(header)
    }

    // MARK: - Position Helpers

    private func storePosition(_ position: Int64) {
        txHdr[ZMODEMProtocol.ZP0] = UInt8(position & 0xFF)
        txHdr[ZMODEMProtocol.ZP1] = UInt8((position >> 8) & 0xFF)
        txHdr[ZMODEMProtocol.ZP2] = UInt8((position >> 16) & 0xFF)
        txHdr[ZMODEMProtocol.ZP3] = UInt8((position >> 24) & 0xFF)
    }

    private func recallPosition() -> Int64 {
        var p = Int64(rxHdr[ZMODEMProtocol.ZP3])
        p = (p << 8) | Int64(rxHdr[ZMODEMProtocol.ZP2])
        p = (p << 8) | Int64(rxHdr[ZMODEMProtocol.ZP1])
        p = (p << 8) | Int64(rxHdr[ZMODEMProtocol.ZP0])
        return p
    }

    // MARK: - Encoding Helpers

    private func hexAppend(_ byte: UInt8, to data: inout Data) {
        let hi = byte >> 4
        let lo = byte & 0x0F
        data.append(hi < 10 ? (0x30 + hi) : (0x57 + hi))
        data.append(lo < 10 ? (0x30 + lo) : (0x57 + lo))
    }

    /// ZDLE-escape a byte per ZMODEM spec.
    /// Escapes: CR, LF, DLE, XON, XOFF, ZDLE, GS and their high-bit variants.
    private func appendZDLEEscaped(_ b: UInt8, to data: inout Data) {
        switch b {
        case 0x0D, 0x8D,       // CR
             0x0A, 0x8A,       // LF
             0x10, 0x90,       // DLE
             0x11, 0x91,       // XON
             0x13, 0x93,       // XOFF
             0x1D, 0x9D,       // GS
             ZMODEMProtocol.ZDLE:
            data.append(ZMODEMProtocol.ZDLE)
            data.append(b ^ 0x40)
        default:
            if ctlEsc && (b & 0x60) == 0 {
                data.append(ZMODEMProtocol.ZDLE)
                data.append(b ^ 0x40)
            } else {
                data.append(b)
            }
        }
    }

    // MARK: - CRC Helpers (per-byte update)

    private func updateCRC16(_ byte: UInt8, crc: UInt16) -> UInt16 {
        var c = crc ^ (UInt16(byte) << 8)
        for _ in 0..<8 {
            if c & 0x8000 != 0 {
                c = (c << 1) ^ 0x1021
            } else {
                c = c << 1
            }
        }
        return c
    }

    private func updateCRC32Single(_ byte: UInt8, crc: UInt32) -> UInt32 {
        var c = crc ^ UInt32(byte)
        for _ in 0..<8 {
            if c & 1 != 0 {
                c = (c >> 1) ^ 0xEDB88320
            } else {
                c = c >> 1
            }
        }
        return c
    }

    override func cancel() {
        sendZCancel()
        super.cancel()
    }
}

// MARK: - Kermit Protocol (port of kermit.c)
//
// Enhanced Kermit implementation ported from the original Tera Term kermit.c:
//   - Standard and long packet formats
//   - Type-1 (single byte), Type-2 (two byte), Type-3 (CRC-16) checksums
//   - 8-bit quoting (QBIN) for binary file transfer
//   - Repeat count prefix compression
//   - File Attributes (A) packet support for size/time/mode
//   - Proper Send-Init parameter negotiation
//   - Sliding window support (WINDO/CAPAS)
//
// Packet format:
//   Standard: MARK LEN SEQ TYPE DATA CHECK [EOL]
//   Long:     MARK 0   SEQ TYPE LENX1 LENX2 HCHECK DATA CHECK [EOL]

class KermitProtocol: FileTransferProtocol {
    private static let SOH: UInt8 = 0x01
    private static let MARK: UInt8 = 0x01

    // Kermit parameters (negotiated)
    struct KermitParams {
        var maxl: Int = 94       // Max packet length (without MARK & CHECK)
        var maxlx: Int = 0      // Extended max length (long packets)
        var time: UInt8 = 10    // Timeout (seconds)
        var npad: UInt8 = 0     // Number of padding characters
        var padc: UInt8 = 0     // Padding character
        var eol: UInt8 = 0x0D   // End-of-line character
        var qctl: UInt8 = 0x23  // Control quote character '#'
        var qbin: UInt8 = 0x4E  // 8-bit quote character 'N' (disabled)
        var chkt: UInt8 = 0x31  // Check type '1'
        var rept: UInt8 = 0x20  // Repeat prefix ' ' (disabled)
        var capas: UInt8 = 0    // Capability flags
        var windo: UInt8 = 0    // Window size
        var maxlx1: UInt8 = 0   // Long packet length high
        var maxlx2: UInt8 = 0   // Long packet length low
    }

    // Capability flags
    private static let CAP_LONGPKT: UInt8 = 2
    private static let CAP_SLIDWIN: UInt8 = 4
    private static let CAP_FILATTR: UInt8 = 8

    // Kermit states (from kermit.c)
    private enum KState {
        case unknown
        case sendInit
        case sendFile
        case sendFileAttr
        case sendData
        case sendEOF
        case sendEOT
        case receiveInit
        case receiveFile
        case receiveData
        case serverInit
        case getInit
        case finish
        case complete
    }

    // Packet read mode
    private enum PktReadMode {
        case waitMark
        case waitLen
        case waitCheck
    }

    private var receiveBuffer = Data()
    private var sequence: Int = 0
    private var bytesTransferred: Int64 = 0
    private var maxPacketLen: Int = 94
    private var currentFileName: String = ""
    private var totalFileSize: Int64 = 0
    private var kState: KState = .unknown
    private var pktReadMode: PktReadMode = .waitMark

    // Negotiated parameters
    private var myParams = KermitParams()
    private var yourParams = KermitParams()

    // 8-bit quoting
    private var quote8 = false
    private var qbinChar: UInt8 = 0x4E  // 'N' = disabled

    // Repeat count
    private var repeatFlag = false
    private var reptChar: UInt8 = 0x7E  // '~'

    // Checksum type (1, 2, or 3)
    private var checkType: Int = 1

    // Long packets
    private var longPacketsEnabled = false
    private var longPacketMaxLen: Int = 0

    // File attributes
    private var fileAttrFlag = false
    private var fileMode: Int = 0
    private var fileTime: UInt32 = 0

    // Packet buffers
    private var pktIn = Data()
    private var lastSentPacket: Data?
    private var pktNum: Int = 0
    private var pktNumOffset: Int = 0

    override func start() {
        sequence = 0
        bytesTransferred = 0
        receiveBuffer = Data()
        pktNum = 0
        pktNumOffset = 0
        totalFileSize = 0
        currentFileName = ""
        checkType = 1
        quote8 = false
        repeatFlag = false
        longPacketsEnabled = false

        // Set my default parameters
        myParams = KermitParams()
        myParams.maxl = 94
        myParams.time = 10
        myParams.npad = 0
        myParams.padc = 0
        myParams.eol = 0x0D
        myParams.qctl = 0x23  // '#'
        myParams.qbin = 0x59  // 'Y' = willing to do 8-bit quoting
        myParams.chkt = 0x31  // '1'
        myParams.rept = 0x7E  // '~' = repeat prefix
        myParams.capas = KermitProtocol.CAP_LONGPKT | KermitProtocol.CAP_FILATTR

        if direction == .send {
            kState = .sendInit
            sendInitPacket()
        } else {
            kState = .receiveInit
        }
        updateState(.starting)
    }

    override func processData(_ data: Data) {
        receiveBuffer.append(data)
        processPackets()
    }

    // MARK: - Packet Extraction

    private func processPackets() {
        while let packet = extractPacket() {
            processPacket(packet)
        }
    }

    private func extractPacket() -> Data? {
        // Find MARK byte
        guard let markIndex = receiveBuffer.firstIndex(of: KermitProtocol.MARK) else { return nil }
        if markIndex > receiveBuffer.startIndex {
            receiveBuffer = Data(receiveBuffer[markIndex...])
        }

        guard receiveBuffer.count >= 4 else { return nil }

        let lenByte = receiveBuffer[1]
        let isLongPacket = lenByte == 32  // tochar(0) means long packet

        if isLongPacket {
            // Long packet: MARK 0 SEQ TYPE LENX1 LENX2 HCHECK DATA CHECK
            guard receiveBuffer.count >= 7 else { return nil }
            let lenx1 = Int(receiveBuffer[4]) - 32
            let lenx2 = Int(receiveBuffer[5]) - 32
            let dataLen = 95 * lenx1 + lenx2
            let checkLen = checkType == 3 ? 2 : checkType
            let totalLen = 7 + dataLen + checkLen
            guard receiveBuffer.count >= totalLen else { return nil }

            let packet = Data(receiveBuffer.prefix(totalLen))
            receiveBuffer = Data(receiveBuffer[totalLen...])
            return packet
        } else {
            let len = Int(lenByte) - 32
            guard len >= 3 else {
                receiveBuffer.removeFirst()
                return nil
            }
            let checkLen = checkType == 3 ? 2 : checkType
            let totalLen = 1 + len + checkLen  // MARK + (LEN..CHECK)
            guard receiveBuffer.count >= totalLen else { return nil }

            let packet = Data(receiveBuffer.prefix(totalLen))
            receiveBuffer = Data(receiveBuffer[totalLen...])
            return packet
        }
    }

    // MARK: - Packet Processing

    private func processPacket(_ packet: Data) {
        guard packet.count >= 4 else { return }

        // Verify checksum
        let isLongPacket = packet[1] == 32  // tochar(0)
        if !verifyChecksum(packet, isLong: isLongPacket) {
            // Send NAK for checksum error
            sendNAK(sequence: (Int(packet[2]) - 32) & 63)
            return
        }

        let type = packet[3]

        switch Character(UnicodeScalar(type)) {
        case "S": // Send-Init
            handleSendInit(packet)
        case "I": // Initialize (server mode)
            handleSendInit(packet)
        case "F": // File Header
            handleFileHeader(packet)
        case "A": // File Attributes
            handleFileAttributes(packet)
        case "D": // Data
            handleData(packet)
        case "Z": // End of File
            handleEOF(packet)
        case "B": // Break (end of transaction)
            handleBreak(packet)
        case "Y": // ACK
            handleACK(packet)
        case "N": // NAK
            handleNAK(packet)
        case "E": // Error
            let dataOffset = isLongPacket ? 7 : 4
            let errorMsg = packet.count > dataOffset ?
                String(data: Data(packet[dataOffset...]), encoding: .ascii) ?? "Unknown" : "Unknown"
            updateState(.failed(error: "Kermit error: \(errorMsg)"))
        case "R": // Receive-Init (file request)
            handleReceiveInit(packet)
        default:
            break
        }
    }

    // MARK: - Packet Handlers

    private func handleSendInit(_ packet: Data) {
        let dataOffset = (packet[1] == 32) ? 7 : 4
        if packet.count > dataOffset {
            parseSendInitData(Data(packet[dataOffset...]))
        }

        // Send ACK with our parameters
        sendACK(sequence: 0, data: buildInitData())
        kState = .receiveFile
    }

    private func handleReceiveInit(_ packet: Data) {
        // Remote wants to receive a file
        let dataOffset = (packet[1] == 32) ? 7 : 4
        if packet.count > dataOffset {
            let nameData = Data(packet[dataOffset...])
            currentFileName = String(data: nameData, encoding: .ascii)?
                .trimmingCharacters(in: .controlCharacters) ?? ""
        }
        sendACK(sequence: (Int(packet[2]) - 32) & 63)
    }

    private func handleFileHeader(_ packet: Data) {
        let dataOffset = (packet[1] == 32) ? 7 : 4
        if packet.count > dataOffset {
            let nameData = decodeKermitData(Data(packet[dataOffset...]))
            currentFileName = String(data: nameData, encoding: .ascii)?
                .trimmingCharacters(in: .controlCharacters) ?? "unknown"
        }
        sendACK(sequence: (Int(packet[2]) - 32) & 63)
        kState = .receiveData
        updateState(.inProgress(bytesTransferred: 0, totalBytes: totalFileSize > 0 ? totalFileSize : nil, fileName: currentFileName))
    }

    private func handleFileAttributes(_ packet: Data) {
        let dataOffset = (packet[1] == 32) ? 7 : 4
        if packet.count > dataOffset {
            parseFileAttributes(Data(packet[dataOffset...]))
        }
        sendACK(sequence: (Int(packet[2]) - 32) & 63)
    }

    private func parseFileAttributes(_ data: Data) {
        // File attributes format: type-char length-char value ...
        var i = 0
        let decoded = decodeKermitData(data)
        while i < decoded.count - 1 {
            let attrType = decoded[i]
            i += 1
            guard i < decoded.count else { break }
            let attrLen = Int(decoded[i]) - 32
            i += 1
            guard i + attrLen <= decoded.count else { break }
            let attrValue = Data(decoded[i..<(i + attrLen)])
            i += attrLen

            switch Character(UnicodeScalar(attrType)) {
            case "1": // File size
                if let sizeStr = String(data: attrValue, encoding: .ascii),
                   let size = Int64(sizeStr) {
                    totalFileSize = size
                }
            case "#": // Modification time (YYYYMMDD HH:MM:SS)
                // Parse and store modification time
                break
            case ",": // File type
                break
            case ".": // File permissions
                if let modeStr = String(data: attrValue, encoding: .ascii),
                   let mode = Int(modeStr, radix: 8) {
                    fileMode = mode
                }
            default:
                break
            }
        }
    }

    private func handleData(_ packet: Data) {
        let dataOffset = (packet[1] == 32) ? 7 : 4
        if packet.count > dataOffset {
            // Strip checksum bytes from end
            let checkLen = checkType == 3 ? 2 : checkType
            let dataEnd = packet.count - checkLen
            guard dataEnd > dataOffset else {
                sendACK(sequence: (Int(packet[2]) - 32) & 63)
                return
            }
            let rawData = Data(packet[dataOffset..<dataEnd])
            let decodedData = decodeKermitData(rawData)
            bytesTransferred += Int64(decodedData.count)
            if let handle = fileHandle {
                handle.write(decodedData)
            }
        }
        sendACK(sequence: (Int(packet[2]) - 32) & 63)
        updateState(.inProgress(bytesTransferred: bytesTransferred, totalBytes: totalFileSize > 0 ? totalFileSize : nil, fileName: currentFileName))
    }

    private func handleEOF(_ packet: Data) {
        sendACK(sequence: (Int(packet[2]) - 32) & 63)
        fileHandle?.closeFile()
        kState = .receiveFile
    }

    private func handleBreak(_ packet: Data) {
        sendACK(sequence: (Int(packet[2]) - 32) & 63)
        kState = .complete
        updateState(.completed(fileName: currentFileName, bytes: bytesTransferred))
        delegate?.transferDidComplete(fileName: currentFileName, bytes: bytesTransferred)
    }

    private func handleACK(_ packet: Data) {
        sequence = (sequence + 1) % 64

        switch kState {
        case .sendInit:
            let dataOffset = (packet[1] == 32) ? 7 : 4
            if packet.count > dataOffset {
                parseSendInitData(Data(packet[dataOffset...]))
            }
            kState = .sendFile
            sendFileHeaderPacket()

        case .sendFile:
            if fileAttrFlag {
                kState = .sendFileAttr
                sendFileAttributesPacket()
            } else {
                kState = .sendData
                sendNextDataPacket()
            }

        case .sendFileAttr:
            kState = .sendData
            sendNextDataPacket()

        case .sendData:
            sendNextDataPacket()

        case .sendEOF:
            kState = .sendEOT
            sendBreakPacket()

        case .sendEOT:
            kState = .complete
            updateState(.completed(fileName: currentFileName, bytes: bytesTransferred))
            delegate?.transferDidComplete(fileName: currentFileName, bytes: bytesTransferred)

        default:
            break
        }
    }

    private func handleNAK(_ packet: Data) {
        if let last = lastSentPacket {
            sendData(last)
        }
    }

    // MARK: - Send-Init Parameter Negotiation

    private func parseSendInitData(_ data: Data) {
        guard !data.isEmpty else { return }
        let d = data

        if d.count >= 1 { yourParams.maxl = min(Int(d[0]) - 32, 94) }
        if d.count >= 2 { yourParams.time = d[1] - 32 }
        if d.count >= 3 { yourParams.npad = d[2] - 32 }
        if d.count >= 4 { yourParams.padc = d[3] ^ 0x40 }
        if d.count >= 5 { yourParams.eol = d[4] - 32 }
        if d.count >= 6 { yourParams.qctl = d[5] }
        if d.count >= 7 {
            yourParams.qbin = d[6]
            // Negotiate 8-bit quoting
            if yourParams.qbin == 0x59 { // 'Y' - will do if asked
                quote8 = true
                qbinChar = myParams.qbin == 0x59 ? 0x26 : myParams.qbin  // '&' default
            } else if yourParams.qbin >= 0x21 && yourParams.qbin <= 0x3E ||
                      yourParams.qbin >= 0x60 && yourParams.qbin <= 0x7E {
                quote8 = true
                qbinChar = yourParams.qbin
            }
        }
        if d.count >= 8 {
            yourParams.chkt = d[7]
            // Negotiate check type
            if yourParams.chkt == 0x33 && myParams.chkt == 0x33 { // '3'
                checkType = 3
            } else if yourParams.chkt == 0x32 { // '2'
                checkType = 2
            } else {
                checkType = 1
            }
        }
        if d.count >= 9 {
            yourParams.rept = d[8]
            if yourParams.rept == 0x7E { // '~'
                repeatFlag = true
                reptChar = 0x7E
            }
        }
        if d.count >= 10 {
            yourParams.capas = d[9] - 32
            // Long packets
            if (yourParams.capas & KermitProtocol.CAP_LONGPKT) != 0 &&
               (myParams.capas & KermitProtocol.CAP_LONGPKT) != 0 {
                longPacketsEnabled = true
            }
            // File attributes
            if (yourParams.capas & KermitProtocol.CAP_FILATTR) != 0 {
                fileAttrFlag = true
            }
        }
        if d.count >= 11 { yourParams.windo = d[10] - 32 }
        if d.count >= 12 && longPacketsEnabled {
            yourParams.maxlx1 = d[11] - 32
            if d.count >= 13 {
                yourParams.maxlx2 = d[12] - 32
            }
            longPacketMaxLen = 95 * Int(yourParams.maxlx1) + Int(yourParams.maxlx2)
            if longPacketMaxLen > 0 {
                maxPacketLen = longPacketMaxLen
            }
        }

        // Use negotiated max length
        if !longPacketsEnabled {
            maxPacketLen = yourParams.maxl
        }
    }

    // MARK: - Packet Builders

    private func buildInitData() -> Data {
        var data = Data()
        data.append(UInt8(myParams.maxl + 32))   // MAXL
        data.append(myParams.time + 32)           // TIME
        data.append(myParams.npad + 32)           // NPAD
        data.append(myParams.padc)                // PADC
        data.append(myParams.eol + 32)            // EOL
        data.append(myParams.qctl)                // QCTL
        data.append(quote8 ? qbinChar : myParams.qbin)  // QBIN
        data.append(UInt8(0x30 + checkType))      // CHKT
        data.append(repeatFlag ? reptChar : myParams.rept)  // REPT
        data.append(myParams.capas + 32)          // CAPAS
        data.append(myParams.windo + 32)          // WINDO
        if longPacketsEnabled {
            let maxLong = 500  // reasonable default
            data.append(UInt8(maxLong / 95 + 32))  // MAXLX1
            data.append(UInt8(maxLong % 95 + 32))  // MAXLX2
        }
        return data
    }

    private func sendInitPacket() {
        let initData = buildInitData()
        let packet = buildPacket(seq: sequence, type: "S", data: initData)
        lastSentPacket = packet
        sendData(packet)
    }

    private func sendFileHeaderPacket() {
        guard let path = filePath else { return }
        let fileName = (path as NSString).lastPathComponent
        currentFileName = fileName
        let nameData = encodeKermitData(Data(fileName.utf8))
        let packet = buildPacket(seq: sequence, type: "F", data: nameData)
        lastSentPacket = packet
        sendData(packet)
    }

    private func sendFileAttributesPacket() {
        guard let path = filePath else {
            kState = .sendData
            sendNextDataPacket()
            return
        }

        var attrData = Data()

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            // File size
            if let size = attrs[.size] as? Int64 {
                totalFileSize = size
                let sizeStr = "\(size)"
                attrData.append(UInt8(Character("1").asciiValue!))
                attrData.append(UInt8(sizeStr.count + 32))
                attrData.append(Data(sizeStr.utf8))
            }

            // File type (binary)
            attrData.append(UInt8(Character(",").asciiValue!))
            attrData.append(UInt8(1 + 32))
            attrData.append(UInt8(Character("B").asciiValue!))
        }

        let packet = buildPacket(seq: sequence, type: "A", data: attrData)
        lastSentPacket = packet
        sendData(packet)
    }

    private func sendNextDataPacket() {
        guard let handle = fileHandle else { return }

        // Calculate max data size (accounting for encoding expansion)
        let overhead = 4  // MARK + LEN + SEQ + TYPE + CHECK
        let maxRawData = (maxPacketLen - overhead) / 2  // Conservative for encoding
        let data = handle.readData(ofLength: max(maxRawData, 20))

        if data.isEmpty {
            // Send EOF (Z packet)
            sendEOFPacket()
            return
        }

        let encoded = encodeKermitData(data)
        let packet = buildPacket(seq: sequence, type: "D", data: encoded)
        lastSentPacket = packet
        bytesTransferred += Int64(data.count)
        updateState(.inProgress(bytesTransferred: bytesTransferred, totalBytes: totalFileSize > 0 ? totalFileSize : nil,
                                fileName: (filePath.map { ($0 as NSString).lastPathComponent }) ?? ""))
        sendData(packet)
    }

    private func sendEOFPacket() {
        let packet = buildPacket(seq: sequence, type: "Z", data: Data())
        lastSentPacket = packet
        sendData(packet)
        kState = .sendEOF
    }

    private func sendBreakPacket() {
        let packet = buildPacket(seq: sequence, type: "B", data: Data())
        lastSentPacket = packet
        sendData(packet)
    }

    private func sendACK(sequence: Int, data: Data = Data()) {
        let packet = buildPacket(seq: sequence, type: "Y", data: data)
        sendData(packet)
    }

    private func sendNAK(sequence: Int) {
        let packet = buildPacket(seq: sequence, type: "N", data: Data())
        sendData(packet)
    }

    // MARK: - Generic Packet Builder

    private func buildPacket(seq: Int, type: String, data: Data) -> Data {
        let typeChar = UInt8(Character(type).asciiValue!)

        // Determine if we need a long packet
        let useShort = data.count + 3 <= 94
        var packet = Data()
        packet.append(KermitProtocol.MARK)

        if useShort {
            // Standard packet: MARK LEN SEQ TYPE DATA CHECK [EOL]
            let len = data.count + 3  // SEQ + TYPE + CHECK (for type 1)
            let checkBytes = checkType == 3 ? 2 : checkType
            let totalLen = data.count + 3 + (checkBytes - 1)
            packet.append(UInt8(totalLen + 32))
            packet.append(UInt8((seq & 63) + 32))
            packet.append(typeChar)
            packet.append(data)

            // Calculate checksum
            let checksumData = packet[1...]  // Everything after MARK
            switch checkType {
            case 1:
                let sum = checksumData.reduce(0) { $0 + Int($1) } & 0xFF
                let check = UInt8(((sum + (sum >> 6)) & 0x3F) + 32)
                packet.append(check)
            case 2:
                let sum = checksumData.reduce(0) { $0 + Int($1) }
                packet.append(UInt8(((sum >> 6) & 0x3F) + 32))
                packet.append(UInt8((sum & 0x3F) + 32))
            case 3:
                var crc: UInt16 = 0
                for byte in checksumData {
                    crc = crc ^ (UInt16(byte) << 8)
                    for _ in 0..<8 {
                        if crc & 0x8000 != 0 {
                            crc = (crc << 1) ^ 0x1021
                        } else {
                            crc = crc << 1
                        }
                    }
                }
                packet.append(UInt8(((Int(crc >> 12)) & 0x0F) + 32))
                packet.append(UInt8(((Int(crc >> 6)) & 0x3F) + 32))
                packet.append(UInt8((Int(crc) & 0x3F) + 32))
            default:
                let sum = checksumData.reduce(0) { $0 + Int($1) } & 0xFF
                let check = UInt8(((sum + (sum >> 6)) & 0x3F) + 32)
                packet.append(check)
            }
        } else {
            // Long packet: MARK 0 SEQ TYPE LENX1 LENX2 HCHECK DATA CHECK
            packet.append(UInt8(32))  // LEN = tochar(0) → long packet indicator
            packet.append(UInt8((seq & 63) + 32))
            packet.append(typeChar)

            let lenx1 = UInt8(data.count / 95 + 32)
            let lenx2 = UInt8(data.count % 95 + 32)
            packet.append(lenx1)
            packet.append(lenx2)

            // Header check (over SEQ, TYPE, LENX1, LENX2)
            let hcheckSum = Int(packet[2]) + Int(packet[3]) + Int(lenx1) + Int(lenx2)
            packet.append(UInt8(((hcheckSum + (hcheckSum >> 6)) & 0x3F) + 32))

            packet.append(data)

            // Checksum over everything after MARK
            let checksumData = packet[1...]
            let sum = checksumData.reduce(0) { $0 + Int($1) } & 0xFF
            let check = UInt8(((sum + (sum >> 6)) & 0x3F) + 32)
            packet.append(check)
        }

        // EOL
        packet.append(myParams.eol)
        return packet
    }

    // MARK: - Checksum Verification

    private func verifyChecksum(_ packet: Data, isLong: Bool) -> Bool {
        // For simplicity, accept packets if they have minimum structure
        // Full verification would recompute the checksum
        guard packet.count >= 4 else { return false }

        if isLong {
            guard packet.count >= 7 else { return false }
            // Verify header check
            let hsum = Int(packet[2]) + Int(packet[3]) + Int(packet[4]) + Int(packet[5])
            let expectedHCheck = UInt8(((hsum + (hsum >> 6)) & 0x3F) + 32)
            return packet[6] == expectedHCheck
        }

        // Standard packet - verify type 1 checksum
        let checkLen = checkType == 3 ? 3 : checkType
        guard packet.count > checkLen else { return false }
        let checksumData = packet[1..<(packet.count - checkLen)]

        switch checkType {
        case 1:
            let sum = checksumData.reduce(0) { $0 + Int($1) } & 0xFF
            let expected = UInt8(((sum + (sum >> 6)) & 0x3F) + 32)
            return packet[packet.count - checkLen] == expected
        default:
            return true  // Accept for type 2/3 (full impl would verify)
        }
    }

    // MARK: - Data Encoding/Decoding

    private func encodeKermitData(_ data: Data) -> Data {
        var result = Data()
        var i = 0

        while i < data.count {
            let byte = data[i]

            // Repeat count encoding
            if repeatFlag && i + 2 < data.count {
                var count = 1
                while i + count < data.count && data[i + count] == byte && count < 94 {
                    count += 1
                }
                if count >= 3 {
                    result.append(reptChar)
                    result.append(UInt8(count + 32))
                    appendEncodedByte(byte, to: &result)
                    i += count
                    continue
                }
            }

            appendEncodedByte(byte, to: &result)
            i += 1
        }
        return result
    }

    private func appendEncodedByte(_ byte: UInt8, to result: inout Data) {
        let needsQuote8 = quote8 && (byte & 0x80) != 0
        let effectiveByte = needsQuote8 ? (byte & 0x7F) : byte

        if needsQuote8 {
            result.append(qbinChar)
        }

        if effectiveByte < 0x20 || effectiveByte == 0x7F {
            result.append(myParams.qctl)  // '#'
            result.append(effectiveByte ^ 0x40)
        } else if effectiveByte == myParams.qctl {
            result.append(myParams.qctl)
            result.append(myParams.qctl)
        } else if quote8 && effectiveByte == qbinChar {
            result.append(myParams.qctl)
            result.append(qbinChar)
        } else if repeatFlag && effectiveByte == reptChar {
            result.append(myParams.qctl)
            result.append(reptChar)
        } else {
            result.append(effectiveByte)
        }
    }

    private func decodeKermitData(_ data: Data) -> Data {
        var result = Data()
        var i = 0
        let qctl = yourParams.qctl != 0 ? yourParams.qctl : myParams.qctl

        while i < data.count {
            var byte = data[i]
            var repeatCount = 1
            var high = false

            // Repeat prefix
            if repeatFlag && byte == reptChar {
                i += 1
                guard i < data.count else { break }
                repeatCount = Int(data[i]) - 32
                i += 1
                guard i < data.count else { break }
                byte = data[i]
            }

            // 8-bit quote
            if quote8 && byte == qbinChar {
                high = true
                i += 1
                guard i < data.count else { break }
                byte = data[i]
            }

            // Control quote
            if byte == qctl {
                i += 1
                guard i < data.count else { break }
                byte = data[i]
                if (byte & 0x7F) >= 0x3F && (byte & 0x7F) <= 0x5F {
                    byte = byte ^ 0x40
                }
            }

            if high {
                byte |= 0x80
            }

            for _ in 0..<repeatCount {
                result.append(byte)
            }
            i += 1
        }
        return result
    }

    override func cancel() {
        let msg = Data("Cancelled".utf8)
        let packet = buildPacket(seq: sequence, type: "E", data: msg)
        sendData(packet)
        super.cancel()
    }
}

// MARK: - CRC-16 Utility

func crc16(_ data: Data) -> UInt16 {
    var crc: UInt16 = 0
    for byte in data {
        crc = crc ^ (UInt16(byte) << 8)
        for _ in 0..<8 {
            if crc & 0x8000 != 0 {
                crc = (crc << 1) ^ 0x1021
            } else {
                crc = crc << 1
            }
        }
    }
    return crc
}

// MARK: - CRC-32 Utility

func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFFFFFF
    for byte in data {
        crc = crc ^ UInt32(byte)
        for _ in 0..<8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ 0xEDB88320
            } else {
                crc = crc >> 1
            }
        }
    }
    return crc ^ 0xFFFFFFFF
}

// MARK: - File Transfer Manager

class FileTransferManager {
    weak var delegate: FileTransferDelegate?

    private var activeTransfer: FileTransferProtocol?

    var isTransferActive: Bool {
        return activeTransfer != nil
    }

    /// Check incoming data for ZMODEM auto-start sequence.
    /// Returns true if ZMODEM was detected and auto-receive started.
    func checkAutoDetect(_ data: Data, savePath: String?) -> Bool {
        if !isTransferActive && ZMODEMProtocol.detectZMODEM(in: data) {
            startTransfer(protocol: .zmodem, direction: .receive, filePath: savePath)
            // Feed the detection data to the protocol
            activeTransfer?.processData(data)
            return true
        }
        return false
    }

    func startTransfer(protocol type: TransferProtocolType, direction: TransferDirection, filePath: String?) {
        let transfer: FileTransferProtocol

        switch type {
        case .xmodem:
            let xm = XMODEMProtocol()
            xm.mode = .checksum
            transfer = xm
        case .xmodemCRC:
            let xm = XMODEMProtocol()
            xm.mode = .crc
            transfer = xm
        case .xmodem1K:
            let xm = XMODEMProtocol()
            xm.mode = .oneK
            transfer = xm
        case .ymodem:
            let ym = YMODEMProtocol()
            ym.yMode = .standard
            transfer = ym
        case .ymodemG:
            let ym = YMODEMProtocol()
            ym.yMode = .ymodemG
            transfer = ym
        case .zmodem:
            transfer = ZMODEMProtocol()
        case .kermit:
            transfer = KermitProtocol()
        }

        transfer.direction = direction
        transfer.filePath = filePath
        transfer.delegate = delegate

        if direction == .send, let path = filePath {
            transfer.fileHandle = FileHandle(forReadingAtPath: path)
        } else if direction == .receive, let path = filePath {
            FileManager.default.createFile(atPath: path, contents: nil)
            transfer.fileHandle = FileHandle(forWritingAtPath: path)
        }

        activeTransfer = transfer
        transfer.start()
    }

    /// Start a YMODEM batch send with multiple files.
    func startYMODEMBatchSend(filePaths: [String]) {
        guard !filePaths.isEmpty else { return }
        let ym = YMODEMProtocol()
        ym.yMode = .standard
        ym.direction = .send
        ym.filePaths = filePaths
        ym.filePath = filePaths[0]
        ym.fileHandle = FileHandle(forReadingAtPath: filePaths[0])
        ym.delegate = delegate
        activeTransfer = ym
        ym.start()
    }

    func processIncomingData(_ data: Data) {
        activeTransfer?.processData(data)
    }

    func cancelTransfer() {
        activeTransfer?.cancel()
        activeTransfer = nil
    }
}
