/*
 * main.swift
 * Entry point for Keycode.app
 *
 * Launches the NSApplication with AppDelegate.
 */

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
