/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of telnet.c to Swift/macOS
 * Telnet protocol implementation (RFC 854, 855, 857, 858, 1091, 1143, etc.)
 */

import Foundation

// MARK: - Telnet Commands (RFC 854)

enum TelnetCommand: UInt8 {
    case se   = 240  // 0xF0 - Sub-negotiation End
    case nop  = 241  // 0xF1 - No Operation
    case dm   = 242  // 0xF2 - Data Mark
    case brk  = 243  // 0xF3 - Break
    case ip   = 244  // 0xF4 - Interrupt Process
    case ao   = 245  // 0xF5 - Abort Output
    case ayt  = 246  // 0xF6 - Are You There
    case ec   = 247  // 0xF7 - Erase Character
    case el   = 248  // 0xF8 - Erase Line
    case ga   = 249  // 0xF9 - Go Ahead
    case sb   = 250  // 0xFA - Sub-negotiation Begin
    case will = 251  // 0xFB
    case wont = 252  // 0xFC
    case `do` = 253  // 0xFD
    case dont = 254  // 0xFE
    case iac  = 255  // 0xFF - Interpret As Command
}

// MARK: - Telnet Options

enum TelnetOption: UInt8 {
    case binaryTransmission = 0
    case echo = 1
    case reconnection = 2
    case suppressGoAhead = 3
    case approxMessageSizeNeg = 4
    case status = 5
    case timingMark = 6
    case remoteControlledTransAndEcho = 7
    case terminalType = 24
    case endOfRecord = 25
    case windowSize = 31     // NAWS (RFC 1073)
    case terminalSpeed = 32
    case remoteFlowControl = 33
    case lineMode = 34
    case environmentOption = 36
    case newEnvironmentOption = 39
}

// MARK: - Telnet Option State

struct TelnetOptionState {
    var localEnabled: Bool = false
    var remoteEnabled: Bool = false
    var localNegotiating: Bool = false
    var remoteNegotiating: Bool = false
}

// MARK: - Telnet Protocol Delegate

protocol TelnetProtocolDelegate: AnyObject {
    func telnetDidReceiveData(_ data: Data)
    func telnetDidRequestSend(_ data: Data)
    func telnetDidChangeTerminalSize(width: Int, height: Int)
}

// MARK: - Telnet Protocol Handler (port of telnet.c)

class TelnetProtocol {
    weak var delegate: TelnetProtocolDelegate?

    var terminalType: String = "xterm-256color"
    var windowWidth: Int = 80
    var windowHeight: Int = 24

    private var optionStates: [UInt8: TelnetOptionState] = [:]
    private var iacState: IACState = .normal
    private var currentCommand: UInt8 = 0
    private var subNegBuffer = Data()
    private var subNegOption: UInt8 = 0
    private var outputBuffer = Data()

    // Thread safety: protects binaryMode/echoMode/suppressGA which are read
    // by escapeData() on sendQueue while mutated by processIncoming() on main.
    private let stateLock = NSLock()

    // Telnet state — access via stateLock when crossing thread boundaries
    private var _binaryMode: Bool = false
    private var _echoMode: Bool = false
    private var _suppressGA: Bool = false

    var binaryMode: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _binaryMode }
        set { stateLock.lock(); _binaryMode = newValue; stateLock.unlock() }
    }
    var echoMode: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _echoMode }
        set { stateLock.lock(); _echoMode = newValue; stateLock.unlock() }
    }
    var suppressGA: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _suppressGA }
        set { stateLock.lock(); _suppressGA = newValue; stateLock.unlock() }
    }

    enum IACState {
        case normal
        case iac
        case will
        case wont
        case `do`
        case dont
        case sb
        case sbData
        case sbIAC
    }

    init() {}

    // MARK: - Process Incoming Data

    func processIncoming(_ data: Data) -> Data {
        var terminalData = Data()

        for byte in data {
            switch iacState {
            case .normal:
                if byte == TelnetCommand.iac.rawValue {
                    iacState = .iac
                } else {
                    terminalData.append(byte)
                }

            case .iac:
                switch byte {
                case TelnetCommand.iac.rawValue:
                    // Escaped 0xFF
                    terminalData.append(byte)
                    iacState = .normal

                case TelnetCommand.will.rawValue:
                    iacState = .will
                case TelnetCommand.wont.rawValue:
                    iacState = .wont
                case TelnetCommand.`do`.rawValue:
                    iacState = .do
                case TelnetCommand.dont.rawValue:
                    iacState = .dont

                case TelnetCommand.sb.rawValue:
                    iacState = .sb
                    subNegBuffer = Data()

                case TelnetCommand.nop.rawValue,
                     TelnetCommand.dm.rawValue,
                     TelnetCommand.ga.rawValue:
                    iacState = .normal

                case TelnetCommand.ayt.rawValue:
                    // Respond to "Are You There"
                    sendRaw(Data("[Yes]\r\n".utf8))
                    iacState = .normal

                case TelnetCommand.brk.rawValue,
                     TelnetCommand.ip.rawValue,
                     TelnetCommand.ao.rawValue,
                     TelnetCommand.ec.rawValue,
                     TelnetCommand.el.rawValue:
                    iacState = .normal

                default:
                    iacState = .normal
                }

            case .will:
                handleWill(option: byte)
                iacState = .normal

            case .wont:
                handleWont(option: byte)
                iacState = .normal

            case .do:
                handleDo(option: byte)
                iacState = .normal

            case .dont:
                handleDont(option: byte)
                iacState = .normal

            case .sb:
                subNegOption = byte
                subNegBuffer = Data()
                iacState = .sbData

            case .sbData:
                if byte == TelnetCommand.iac.rawValue {
                    iacState = .sbIAC
                } else {
                    subNegBuffer.append(byte)
                }

            case .sbIAC:
                if byte == TelnetCommand.se.rawValue {
                    handleSubNegotiation(option: subNegOption, data: subNegBuffer)
                    iacState = .normal
                } else if byte == TelnetCommand.iac.rawValue {
                    subNegBuffer.append(byte)
                    iacState = .sbData
                } else {
                    iacState = .normal
                }
            }
        }

        return terminalData
    }

    // MARK: - Option Negotiation

    private func handleWill(option: UInt8) {
        var state = optionStates[option] ?? TelnetOptionState()

        switch option {
        case TelnetOption.echo.rawValue:
            echoMode = true
            if !state.remoteEnabled {
                state.remoteEnabled = true
                sendCommand(.`do`, option: option)
            }

        case TelnetOption.suppressGoAhead.rawValue:
            suppressGA = true
            if !state.remoteEnabled {
                state.remoteEnabled = true
                sendCommand(.`do`, option: option)
            }

        case TelnetOption.binaryTransmission.rawValue:
            binaryMode = true
            if !state.remoteEnabled {
                state.remoteEnabled = true
                sendCommand(.`do`, option: option)
            }

        default:
            // Refuse unknown options
            sendCommand(.dont, option: option)
        }

        optionStates[option] = state
    }

    private func handleWont(option: UInt8) {
        var state = optionStates[option] ?? TelnetOptionState()
        state.remoteEnabled = false

        switch option {
        case TelnetOption.echo.rawValue:
            echoMode = false
        case TelnetOption.suppressGoAhead.rawValue:
            suppressGA = false
        case TelnetOption.binaryTransmission.rawValue:
            binaryMode = false
        default:
            break
        }

        optionStates[option] = state
    }

    private func handleDo(option: UInt8) {
        var state = optionStates[option] ?? TelnetOptionState()

        switch option {
        case TelnetOption.terminalType.rawValue:
            if !state.localEnabled {
                state.localEnabled = true
                sendCommand(.will, option: option)
            }

        case TelnetOption.windowSize.rawValue:
            if !state.localEnabled {
                state.localEnabled = true
                sendCommand(.will, option: option)
            }
            // Send NAWS immediately
            sendNAWS()

        case TelnetOption.terminalSpeed.rawValue:
            if !state.localEnabled {
                state.localEnabled = true
                sendCommand(.will, option: option)
            }

        case TelnetOption.suppressGoAhead.rawValue:
            if !state.localEnabled {
                state.localEnabled = true
                sendCommand(.will, option: option)
            }

        case TelnetOption.binaryTransmission.rawValue:
            binaryMode = true
            if !state.localEnabled {
                state.localEnabled = true
                sendCommand(.will, option: option)
            }

        case TelnetOption.newEnvironmentOption.rawValue:
            if !state.localEnabled {
                state.localEnabled = true
                sendCommand(.will, option: option)
            }

        default:
            sendCommand(.wont, option: option)
        }

        optionStates[option] = state
    }

    private func handleDont(option: UInt8) {
        var state = optionStates[option] ?? TelnetOptionState()
        state.localEnabled = false
        optionStates[option] = state
        sendCommand(.wont, option: option)
    }

    // MARK: - Sub-negotiation

    private func handleSubNegotiation(option: UInt8, data: Data) {
        switch option {
        case TelnetOption.terminalType.rawValue:
            if !data.isEmpty && data[0] == 1 { // SEND
                sendTerminalType()
            }

        case TelnetOption.terminalSpeed.rawValue:
            if !data.isEmpty && data[0] == 1 { // SEND
                sendTerminalSpeed()
            }

        case TelnetOption.newEnvironmentOption.rawValue:
            if !data.isEmpty && data[0] == 1 { // SEND
                sendEnvironment(requestData: data)
            }

        default:
            break
        }
    }

    // MARK: - Send Commands

    func sendCommand(_ command: TelnetCommand, option: UInt8) {
        let data = Data([TelnetCommand.iac.rawValue, command.rawValue, option])
        sendRaw(data)
    }

    func sendNAWS() {
        var data = Data()
        data.append(TelnetCommand.iac.rawValue)
        data.append(TelnetCommand.sb.rawValue)
        data.append(TelnetOption.windowSize.rawValue)

        // Width (2 bytes, big-endian)
        let w = UInt16(windowWidth)
        data.append(UInt8(w >> 8))
        if UInt8(w >> 8) == 0xFF { data.append(0xFF) } // Escape IAC
        data.append(UInt8(w & 0xFF))
        if UInt8(w & 0xFF) == 0xFF { data.append(0xFF) }

        // Height (2 bytes, big-endian)
        let h = UInt16(windowHeight)
        data.append(UInt8(h >> 8))
        if UInt8(h >> 8) == 0xFF { data.append(0xFF) }
        data.append(UInt8(h & 0xFF))
        if UInt8(h & 0xFF) == 0xFF { data.append(0xFF) }

        data.append(TelnetCommand.iac.rawValue)
        data.append(TelnetCommand.se.rawValue)

        sendRaw(data)
    }

    private func sendTerminalType() {
        var data = Data()
        data.append(TelnetCommand.iac.rawValue)
        data.append(TelnetCommand.sb.rawValue)
        data.append(TelnetOption.terminalType.rawValue)
        data.append(0) // IS
        data.append(contentsOf: terminalType.utf8)
        data.append(TelnetCommand.iac.rawValue)
        data.append(TelnetCommand.se.rawValue)
        sendRaw(data)
    }

    private func sendTerminalSpeed() {
        var data = Data()
        data.append(TelnetCommand.iac.rawValue)
        data.append(TelnetCommand.sb.rawValue)
        data.append(TelnetOption.terminalSpeed.rawValue)
        data.append(0) // IS
        data.append(contentsOf: "38400,38400".utf8)
        data.append(TelnetCommand.iac.rawValue)
        data.append(TelnetCommand.se.rawValue)
        sendRaw(data)
    }

    private func sendEnvironment(requestData: Data) {
        var data = Data()
        data.append(TelnetCommand.iac.rawValue)
        data.append(TelnetCommand.sb.rawValue)
        data.append(TelnetOption.newEnvironmentOption.rawValue)
        data.append(0) // IS
        // Send empty environment
        data.append(TelnetCommand.iac.rawValue)
        data.append(TelnetCommand.se.rawValue)
        sendRaw(data)
    }

    private func sendRaw(_ data: Data) {
        delegate?.telnetDidRequestSend(data)
    }

    // MARK: - Send Data (escape IAC in outgoing data)

    func escapeData(_ data: Data) -> Data {
        if binaryMode {
            var escaped = Data()
            for byte in data {
                if byte == TelnetCommand.iac.rawValue {
                    escaped.append(TelnetCommand.iac.rawValue)
                }
                escaped.append(byte)
            }
            return escaped
        }
        return data
    }

    // MARK: - Window Size Change

    func updateWindowSize(width: Int, height: Int) {
        windowWidth = width
        windowHeight = height
        let state = optionStates[TelnetOption.windowSize.rawValue] ?? TelnetOptionState()
        if state.localEnabled {
            sendNAWS()
        }
    }

    // MARK: - Send Break

    func sendBreak() {
        let data = Data([TelnetCommand.iac.rawValue, TelnetCommand.brk.rawValue])
        sendRaw(data)
    }

    // MARK: - Send AYT

    func sendAreYouThere() {
        let data = Data([TelnetCommand.iac.rawValue, TelnetCommand.ayt.rawValue])
        sendRaw(data)
    }

    // MARK: - Reset

    func reset() {
        iacState = .normal
        optionStates = [:]
        subNegBuffer = Data()
        binaryMode = false
        echoMode = false
        suppressGA = false
    }
}
