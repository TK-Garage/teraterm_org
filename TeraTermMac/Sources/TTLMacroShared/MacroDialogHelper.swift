/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Common dialog helpers for TTLMacro.
 */

#if canImport(AppKit)
import AppKit

// MARK: - Dialog Helper

public enum MacroDialogHelper {

    /// Show a message box dialog.
    /// - Returns: (result: 1 = OK, message: "")
    public static func showMessageBox(message: String, title: String,
                                      completion: @escaping (Int, String) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: L("dialog.ok"))
            alert.runModal()
            completion(1, "")
        }
    }

    /// Show a Yes/No dialog.
    /// - Returns: (result: 1 = Yes, 0 = No, message: "")
    public static func showYesNoBox(message: String, title: String,
                                    completion: @escaping (Int, String) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: L("dialog.yes"))
            alert.addButton(withTitle: L("dialog.no"))
            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn ? 1 : 0, "")
        }
    }

    /// Show an input box dialog.
    /// - Returns: (result: 1 = OK / 0 = Cancel, inputString)
    public static func showInputBox(prompt: String, title: String,
                                    defaultValue: String, isPassword: Bool,
                                    completion: @escaping (Int, String) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = prompt
            alert.alertStyle = .informational
            alert.addButton(withTitle: L("dialog.ok"))
            alert.addButton(withTitle: L("dialog.cancel"))

            let field: NSTextField
            if isPassword {
                field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            } else {
                field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            }
            field.stringValue = defaultValue
            alert.accessoryView = field
            alert.window.initialFirstResponder = field

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                completion(1, field.stringValue)
            } else {
                completion(0, "")
            }
        }
    }

    /// Show a dialog based on dialog type string.
    public static func showDialog(type: String, message: String, defaultValue: String,
                                  completion: @escaping (Int, String) -> Void) {
        guard let dialogType = MacroDialogType(rawValue: type) else {
            completion(0, "")
            return
        }

        switch dialogType {
        case .messagebox:
            showMessageBox(message: message, title: "", completion: completion)
        case .yesnobox:
            showYesNoBox(message: message, title: "", completion: completion)
        case .inputbox:
            showInputBox(prompt: message, title: "", defaultValue: defaultValue,
                        isPassword: false, completion: completion)
        case .passwordbox:
            showInputBox(prompt: message, title: "", defaultValue: "",
                        isPassword: true, completion: completion)
        default:
            completion(0, "")
        }
    }

    /// Show the stop confirmation alert.
    /// - Returns: true if the user chose to stop.
    public static func showStopConfirmation() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("macro.stop.confirm.title")
        alert.informativeText = L("macro.stop.confirm.message")
        alert.addButton(withTitle: L("macro.stop.confirm.stop"))
        alert.addButton(withTitle: L("macro.stop.confirm.cancel"))
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }
}

#endif
