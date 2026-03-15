/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Shared constants for TTLMacro.
 */

import Foundation

public enum MacroConstants {
    /// Maximum XPC reconnection attempts
    public static let maxReconnectAttempts = 3

    /// Delay between reconnection attempts in seconds
    public static let reconnectInterval: TimeInterval = 2.0

    /// XPC connection timeout in seconds
    public static let xpcTimeout: TimeInterval = 30.0

    /// TTL file extension
    public static let ttlFileExtension = "ttl"

    /// Bundle identifier for TTLMacro.app
    public static let ttlMacroBundleId = "com.yourapp.TeraTermMac.TTLMacro"

    /// Bundle identifier for TeraTermMac.app
    public static let teraTermMacBundleId = "com.yourapp.TeraTermMac"

    /// Launch argument for XPC mode
    public static let xpcModeArgument = "--xpc-mode"

    /// Status bar animation interval
    public static let animationInterval: TimeInterval = 0.3

    /// Menu update interval when menu is visible
    public static let menuVisibleUpdateInterval: TimeInterval = 0.1

    /// Menu update interval when menu is hidden
    public static let menuHiddenUpdateInterval: TimeInterval = 1.0
}
