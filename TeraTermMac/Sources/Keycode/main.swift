/*
 * main.swift
 * Entry point for Keycode.app
 *
 * Launches the NSApplication with AppDelegate.
 * Sets up as a foreground GUI application with Dock icon and menu bar.
 */

import AppKit

// Transform the process into a foreground (GUI) application.
// Without this, SPM executables run as background processes
// and won't show a Dock icon or menu bar, and key events may not be delivered.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

// アプリアイコンをプログラムで設定する。
// SwiftPM では Info.plist が埋め込まれないため CFBundleIconFile が効かない。
do {
    let resourceBundle = Bundle.module
    if let iconURL = resourceBundle.url(forResource: "AppIcon", withExtension: "icns"),
       let icon = NSImage(contentsOf: iconURL) {
        app.applicationIconImage = icon
    }
}

let delegate = AppDelegate()
app.delegate = delegate

// Activate the app and bring it to front
app.activate(ignoringOtherApps: true)

app.run()
