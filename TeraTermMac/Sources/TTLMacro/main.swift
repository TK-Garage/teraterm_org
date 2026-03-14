/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * TTLMacro.app - Macro execution application for TeraTermMac
 * Equivalent to TTPMACRO.EXE in original Tera Term.
 *
 * Entry point for the TTLMacro application.
 */

import AppKit
import TTLMacroShared

let app = NSApplication.shared
let delegate = TTLMacroAppDelegate()
app.delegate = delegate
app.run()
