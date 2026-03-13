/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Tera Term Mac - macOS port entry point
 * Sets up process as a foreground GUI application and launches NSApplication.
 */

#if canImport(AppKit)
import AppKit

// Transform the process into a foreground (GUI) application.
// Without this, SPM executables run as background processes
// and won't show a Dock icon or menu bar.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

// OS標準の外観モード（ライト/ダーク）に追従する
// app.appearance を設定しないことでシステム設定を尊重する

let delegate = AppDelegate()
app.delegate = delegate

// Activate the app and bring it to front
app.activate(ignoringOtherApps: true)

app.run()
#else
import Foundation
print("Tera Term Mac requires macOS with AppKit.")
print("Please build and run on macOS 14.0 or later.")
Foundation.exit(1)
#endif
