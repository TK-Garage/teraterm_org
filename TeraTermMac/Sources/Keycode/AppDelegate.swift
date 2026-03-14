/*
 * AppDelegate.swift
 * Application delegate for Keycode.app
 *
 * Creates the main window and sets up the key code display view.
 * Port of KEYCODE.EXE's WinMain / CreateWindow.
 */

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create window (fixed size, not resizable)
        let windowRect = NSRect(x: 0, y: 0, width: 480, height: 320)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]

        window = NSWindow(
            contentRect: windowRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        window.title = L("keycode.window.title")
        window.center()
        window.isReleasedWhenClosed = false

        // Set up the keycode view
        let keycodeView = KeycodeView(frame: windowRect)
        window.contentView = keycodeView

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(keycodeView)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
