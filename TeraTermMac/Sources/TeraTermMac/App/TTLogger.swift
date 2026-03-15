/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Unified os.Logger instances for TeraTermMac.
 * Replaces scattered NSLog calls with structured, subsystem-based logging.
 */

import os

/// Centralized loggers for each subsystem.
/// Usage: `TTLog.config.info("message")` or `TTLog.snapshot.debug("message")`
enum TTLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.teraterm.mac"

    /// Configuration persistence (TERATERM.INI load/save)
    static let config = Logger(subsystem: subsystem, category: "ConfigPersistence")

    /// Debug snapshot / PNG generation
    static let snapshot = Logger(subsystem: subsystem, category: "DebugSnapshot")

    /// Terminal settings save/load
    static let settings = Logger(subsystem: subsystem, category: "TerminalSettings")

    /// Keyboard / key mapping
    static let keymap = Logger(subsystem: subsystem, category: "KeyMap")

    /// TCP connection
    static let tcp = Logger(subsystem: subsystem, category: "TCPConnection")

    /// Localization (TTL) resolution
    static let localization = Logger(subsystem: subsystem, category: "TTL")

    /// Snapshot generator (dialog validation)
    static let snapshotGen = Logger(subsystem: subsystem, category: "SnapshotGenerator")

    /// Multilingual snapshot tests
    static let snapshotTest = Logger(subsystem: subsystem, category: "MultilingualSnapshot")

    /// XPC service handler (TTLMacro)
    static let xpc = Logger(subsystem: subsystem, category: "XPC")
}
