/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * TransferErrorDetail.swift
 * Protocol-specific file transfer error detail model and dialog.
 */

import Foundation

// MARK: - Transfer Error Detail

public struct TransferErrorDetail {
    public let protocolName: String    // e.g. "xmodem", "zmodem", "kermit"
    public let direction: String       // "send" or "recv"
    public let filePath: String
    public let bytesTransferred: Int
    public let totalBytes: Int
    public let lineNumber: Int

    public init(protocolName: String, direction: String, filePath: String,
                bytesTransferred: Int, totalBytes: Int, lineNumber: Int) {
        self.protocolName = protocolName
        self.direction = direction
        self.filePath = filePath
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.lineNumber = lineNumber
    }

    /// Human-readable protocol display name.
    public var protocolDisplayName: String {
        switch protocolName.lowercased() {
        case "xmodem":   return "XMODEM"
        case "ymodem":   return "YMODEM"
        case "zmodem":   return "ZMODEM"
        case "kermit":   return "Kermit"
        case "bplus":    return "B-Plus"
        case "quickvan": return "Quick-VAN"
        default:         return protocolName.uppercased()
        }
    }

    /// Direction display text.
    public var directionText: String {
        return direction == "send" ? "Send" : "Receive"
    }

    /// Protocol-specific troubleshooting hint.
    public var troubleshootingHint: String {
        switch protocolName.lowercased() {
        case "xmodem":
            return direction == "send"
                ? "Ensure the remote side is ready to receive (e.g. 'rx' command)."
                : "Ensure the remote side is sending. XMODEM requires pre-agreement on file name."
        case "ymodem":
            return "YMODEM batch transfer may fail if the remote side does not support batch mode."
        case "zmodem":
            return direction == "send"
                ? "Check that the remote side supports ZMODEM auto-start or run 'rz'."
                : "Ensure the remote side initiated ZMODEM send ('sz <file>')."
        case "kermit":
            return "Kermit requires both sides to use compatible settings (packet size, encoding)."
        case "bplus":
            return "B-Plus requires a CompuServe-compatible host."
        case "quickvan":
            return "Quick-VAN is specific to certain Japanese BBS systems."
        default:
            return "Check that both sides are using the same protocol and settings."
        }
    }

    /// Formatted progress text for display.
    public var progressText: String {
        if totalBytes > 0 {
            let percent = min(100, bytesTransferred * 100 / max(totalBytes, 1))
            return "\(formatBytes(bytesTransferred)) / \(formatBytes(totalBytes)) (\(percent)%)"
        } else if bytesTransferred > 0 {
            return "\(formatBytes(bytesTransferred))"
        }
        return "0 B"
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }
}

// MARK: - Transfer Error Dialog

#if canImport(AppKit)
import AppKit

public enum TransferErrorDialog {
    /// Show a protocol-specific file transfer error dialog.
    public static func show(_ detail: TransferErrorDetail) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "\(detail.protocolDisplayName) \(detail.directionText) Failed"

            var info = ""
            if !detail.filePath.isEmpty {
                info += "File: \(detail.filePath)\n"
            }
            info += "Progress: \(detail.progressText)\n"
            info += "Line: \(detail.lineNumber)\n"
            info += "\n\(detail.troubleshootingHint)"

            alert.informativeText = info
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
#endif
