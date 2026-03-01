/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Tera Term Mac - macOS port entry point
 */

#if canImport(AppKit)
import AppKit

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
#else
import Foundation
print("Tera Term Mac requires macOS with AppKit.")
print("Please build and run on macOS 13.0 or later.")
Foundation.exit(1)
#endif
