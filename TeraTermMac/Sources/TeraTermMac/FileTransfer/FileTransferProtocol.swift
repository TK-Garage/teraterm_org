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

// MARK: - ZMODEM Protocol (port of zmodem.c)

class ZMODEMProtocol: FileTransferProtocol {
    // ZMODEM frame types
    private static let ZRQINIT: UInt8 = 0
    private static let ZRINIT: UInt8 = 1
    private static let ZSINIT: UInt8 = 2
    private static let ZACK: UInt8 = 3
    private static let ZFILE: UInt8 = 4
    private static let ZSKIP: UInt8 = 5
    private static let ZDATA: UInt8 = 10
    private static let ZEOF: UInt8 = 11
    private static let ZFIN: UInt8 = 8
    private static let ZDLE: UInt8 = 0x18
    private static let ZPAD: UInt8 = 0x2A  // '*'
    private static let ZBIN: UInt8 = 0x41  // 'A'
    private static let ZHEX: UInt8 = 0x42  // 'B'
    private static let ZBIN32: UInt8 = 0x43  // 'C'
    private static let ZCRCW: UInt8 = 0x68  // 'h'
    private static let ZCRCG: UInt8 = 0x69  // 'i'
    private static let ZCRCQ: UInt8 = 0x6A  // 'j'
    private static let ZCRCE: UInt8 = 0x6B  // 'k'

    private var receiveBuffer = Data()
    private var fileData = Data()
    private var bytesTransferred: Int64 = 0
    private var totalFileSize: Int64 = 0
    private var currentFileName: String = ""
    private var zState: ZState = .idle

    enum ZState {
        case idle
        case waitForZRINIT
        case waitForZFILE
        case receivingData
        case waitForZFIN
        case sendingData
        case complete
    }

    override func start() {
        if direction == .receive {
            startReceive()
        } else {
            startSend()
        }
    }

    private func startReceive() {
        zState = .waitForZFILE
        updateState(.starting)
        receiveBuffer = Data()

        // Send ZRINIT
        sendZRINIT()
    }

    private func startSend() {
        guard let path = filePath else {
            updateState(.failed(error: "No file specified"))
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            updateState(.failed(error: "File not found"))
            return
        }

        zState = .waitForZRINIT
        updateState(.starting)

        // Send ZRQINIT
        sendHexHeader(ZMODEMProtocol.ZRQINIT, flags: [0, 0, 0, 0])
    }

    override func processData(_ data: Data) {
        receiveBuffer.append(data)
        processBuffer()
    }

    private func processBuffer() {
        // Simple ZMODEM state machine
        // Full implementation would be much more complex
        while receiveBuffer.count > 0 {
            // Look for ZPAD
            guard let padIndex = receiveBuffer.firstIndex(of: ZMODEMProtocol.ZPAD) else {
                receiveBuffer.removeAll()
                return
            }

            receiveBuffer = Data(receiveBuffer[padIndex...])

            // Need at least header
            guard receiveBuffer.count >= 4 else { return }

            // Parse based on state
            switch zState {
            case .waitForZRINIT:
                // We sent ZRQINIT, waiting for ZRINIT from receiver
                if parseFrame() == ZMODEMProtocol.ZRINIT {
                    sendFileHeader()
                    zState = .sendingData
                }

            case .waitForZFILE:
                let frameType = parseFrame()
                if frameType == ZMODEMProtocol.ZFILE {
                    parseFileInfo()
                    sendZRINIT() // ACK the file header
                    zState = .receivingData
                } else if frameType == ZMODEMProtocol.ZFIN {
                    zState = .complete
                    updateState(.completed(fileName: currentFileName, bytes: bytesTransferred))
                }

            case .receivingData:
                // Receive file data
                processFileData()

            case .sendingData:
                let frameType = parseFrame()
                if frameType == ZMODEMProtocol.ZACK {
                    sendNextDataBlock()
                }

            default:
                receiveBuffer.removeAll()
                return
            }
        }
    }

    private func parseFrame() -> UInt8? {
        guard receiveBuffer.count >= 7 else { return nil }
        // Simplified frame parsing
        // Real ZMODEM is significantly more complex
        for i in 0..<receiveBuffer.count - 1 {
            if receiveBuffer[i] == ZMODEMProtocol.ZPAD {
                if i + 2 < receiveBuffer.count {
                    if receiveBuffer[i + 1] == ZMODEMProtocol.ZPAD ||
                       receiveBuffer[i + 1] == ZMODEMProtocol.ZDLE {
                        // Found potential header
                        let offset = (receiveBuffer[i + 1] == ZMODEMProtocol.ZPAD) ? i + 2 : i + 1
                        if offset < receiveBuffer.count {
                            let encoding = receiveBuffer[offset]
                            if encoding == ZMODEMProtocol.ZHEX && offset + 1 < receiveBuffer.count {
                                let frameType = receiveBuffer[offset + 1]
                                receiveBuffer = Data(receiveBuffer[(offset + 2)...])
                                return frameType
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    private func parseFileInfo() {
        // Extract filename and size from ZFILE data
        // Simplified version
    }

    private func processFileData() {
        // Process incoming file data blocks
        // Simplified version
        fileData.append(receiveBuffer)
        bytesTransferred += Int64(receiveBuffer.count)
        receiveBuffer.removeAll()
        updateState(.inProgress(bytesTransferred: bytesTransferred, totalBytes: totalFileSize > 0 ? totalFileSize : nil, fileName: currentFileName))
    }

    private func sendZRINIT() {
        sendHexHeader(ZMODEMProtocol.ZRINIT, flags: [0x23, 0, 0, 0]) // CANFDX | CANOVIO | CANFC32
    }

    private func sendFileHeader() {
        guard let path = filePath else { return }
        let fileName = (path as NSString).lastPathComponent
        sendHexHeader(ZMODEMProtocol.ZFILE, flags: [0, 0, 0, 0])
        // Send file name + size as data subpacket
        var fileInfo = Data(fileName.utf8)
        fileInfo.append(0) // NUL terminator
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            fileInfo.append(Data("\(size)".utf8))
        }
        fileInfo.append(0)
        sendData(fileInfo)
    }

    private func sendNextDataBlock() {
        guard let handle = fileHandle else { return }
        let data = handle.readData(ofLength: 1024)
        if data.isEmpty {
            sendHexHeader(ZMODEMProtocol.ZEOF, flags: [0, 0, 0, 0])
            return
        }
        sendData(data)
        bytesTransferred += Int64(data.count)
    }

    private func sendHexHeader(_ frameType: UInt8, flags: [UInt8]) {
        var header = Data()
        header.append(ZMODEMProtocol.ZPAD)
        header.append(ZMODEMProtocol.ZPAD)
        header.append(ZMODEMProtocol.ZDLE)
        header.append(ZMODEMProtocol.ZHEX)
        header.append(hexByte(frameType))
        for flag in flags.prefix(4) {
            header.append(hexByte(flag))
        }
        // CRC
        let crcVal = crc16(Data([frameType] + flags.prefix(4)))
        header.append(hexByte(UInt8(crcVal >> 8)))
        header.append(hexByte(UInt8(crcVal & 0xFF)))
        header.append(0x0D) // CR
        header.append(0x0A) // LF
        sendData(header)
    }

    private func hexByte(_ byte: UInt8) -> UInt8 {
        return byte // Simplified - real implementation would encode as hex
    }

    override func cancel() {
        // Send CAN sequence
        sendData(Data(repeating: CAN, count: 8))
        super.cancel()
    }
}

// MARK: - Kermit Protocol (port of kermit.c)

class KermitProtocol: FileTransferProtocol {
    private static let SOH: UInt8 = 0x01
    private static let MARK: UInt8 = 0x01

    private var receiveBuffer = Data()
    private var sequence: Int = 0
    private var bytesTransferred: Int64 = 0
    private var maxPacketLen: Int = 94
    private var currentFileName: String = ""

    enum KermitState {
        case idle
        case sendInit
        case sendFile
        case sendData
        case receiveInit
        case receiveFile
        case receiveData
        case complete
    }

    private var kState: KermitState = .idle

    override func start() {
        sequence = 0
        bytesTransferred = 0
        receiveBuffer = Data()

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

    private func processPackets() {
        while let packet = extractPacket() {
            processPacket(packet)
        }
    }

    private func extractPacket() -> Data? {
        guard let markIndex = receiveBuffer.firstIndex(of: KermitProtocol.MARK) else { return nil }
        let remaining = Data(receiveBuffer[markIndex...])
        guard remaining.count >= 4 else { return nil }

        let len = Int(remaining[1]) - 32
        guard remaining.count >= len + 2 else { return nil }

        let packet = Data(remaining.prefix(len + 2))
        receiveBuffer = Data(remaining[(len + 2)...])
        return packet
    }

    private func processPacket(_ packet: Data) {
        guard packet.count >= 4 else { return }
        let type = packet[3]

        switch Character(UnicodeScalar(type)) {
        case "S": // Send-Init
            handleSendInit(packet)
        case "F": // File Header
            handleFileHeader(packet)
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
            let errorMsg = packet.count > 4 ? String(data: Data(packet[4...]), encoding: .ascii) ?? "Unknown" : "Unknown"
            updateState(.failed(error: "Kermit error: \(errorMsg)"))
        default:
            break
        }
    }

    private func handleSendInit(_ packet: Data) {
        // Parse sender's capabilities
        sendACK(sequence: 0, data: buildInitData())
        kState = .receiveFile
    }

    private func handleFileHeader(_ packet: Data) {
        if packet.count > 4 {
            currentFileName = String(data: Data(packet[4...]), encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "unknown"
        }
        sendACK(sequence: Int(packet[2]) - 32)
        kState = .receiveData
        updateState(.inProgress(bytesTransferred: 0, totalBytes: nil, fileName: currentFileName))
    }

    private func handleData(_ packet: Data) {
        if packet.count > 4 {
            let decodedData = decodeKermitData(Data(packet[4...]))
            bytesTransferred += Int64(decodedData.count)
            // Write to file
            if let handle = fileHandle {
                handle.write(decodedData)
            }
        }
        sendACK(sequence: Int(packet[2]) - 32)
        updateState(.inProgress(bytesTransferred: bytesTransferred, totalBytes: nil, fileName: currentFileName))
    }

    private func handleEOF(_ packet: Data) {
        sendACK(sequence: Int(packet[2]) - 32)
        fileHandle?.closeFile()
        kState = .receiveFile
    }

    private func handleBreak(_ packet: Data) {
        sendACK(sequence: Int(packet[2]) - 32)
        kState = .complete
        updateState(.completed(fileName: currentFileName, bytes: bytesTransferred))
        delegate?.transferDidComplete(fileName: currentFileName, bytes: bytesTransferred)
    }

    private func handleACK(_ packet: Data) {
        sequence = (sequence + 1) % 64
        // Continue sending based on state
    }

    private func handleNAK(_ packet: Data) {
        // Resend last packet
    }

    private func sendInitPacket() {
        var packet = Data()
        packet.append(KermitProtocol.MARK)
        let initData = buildInitData()
        packet.append(UInt8(initData.count + 3 + 32)) // LEN
        packet.append(UInt8(sequence + 32))             // SEQ
        packet.append(UInt8(Character("S").asciiValue!))  // TYPE
        packet.append(initData)
        // Checksum
        let checksum = packet[1...].reduce(0) { ($0 + Int($1)) } % 256
        packet.append(UInt8((checksum + (checksum >> 6)) & 0x3F + 32))
        packet.append(0x0D) // CR
        sendData(packet)
    }

    private func sendACK(sequence: Int, data: Data = Data()) {
        var packet = Data()
        packet.append(KermitProtocol.MARK)
        packet.append(UInt8(data.count + 3 + 32))
        packet.append(UInt8(sequence + 32))
        packet.append(UInt8(Character("Y").asciiValue!))
        packet.append(data)
        let checksum = packet[1...].reduce(0) { ($0 + Int($1)) } % 256
        packet.append(UInt8((checksum + (checksum >> 6)) & 0x3F + 32))
        packet.append(0x0D)
        sendData(packet)
    }

    private func buildInitData() -> Data {
        var data = Data()
        data.append(UInt8(94 + 32))   // MAXL
        data.append(UInt8(5 + 32))    // TIME
        data.append(UInt8(0 + 32))    // NPAD
        data.append(UInt8(0))         // PADC
        data.append(UInt8(13 + 32))   // EOL
        data.append(UInt8(Character("#").asciiValue!))  // QCTL
        data.append(UInt8(Character("N").asciiValue!))  // QBIN
        data.append(UInt8(Character("1").asciiValue!))  // CHKT
        data.append(UInt8(Character(" ").asciiValue!))  // REPT
        return data
    }

    private func decodeKermitData(_ data: Data) -> Data {
        var result = Data()
        var i = 0
        while i < data.count {
            var byte = data[i]
            if byte == 0x23 { // '#' control prefix
                i += 1
                if i < data.count {
                    byte = data[i] ^ 0x40
                }
            }
            result.append(byte)
            i += 1
        }
        return result
    }

    override func cancel() {
        // Send Error packet
        var packet = Data()
        packet.append(KermitProtocol.MARK)
        let msg = Data("Cancelled".utf8)
        packet.append(UInt8(msg.count + 3 + 32))
        packet.append(UInt8(sequence + 32))
        packet.append(UInt8(Character("E").asciiValue!))
        packet.append(msg)
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
        case .ymodem, .ymodemG:
            // YMODEM uses XMODEM with file info block
            let xm = XMODEMProtocol()
            xm.mode = .oneK
            transfer = xm
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

    func processIncomingData(_ data: Data) {
        activeTransfer?.processData(data)
    }

    func cancelTransfer() {
        activeTransfer?.cancel()
        activeTransfer = nil
    }
}
