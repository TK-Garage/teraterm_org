/*
 * AppDelegate.swift
 * Application delegate for Keycode.app
 *
 * Creates the main window, menu bar, and sets up the key code display view.
 * Port of KEYCODE.EXE's WinMain / CreateWindow.
 */

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

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

    // MARK: - Menu Bar

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // Application menu (Keycode)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let appName = L("keycode.window.title")
        appMenu.addItem(
            withTitle: L("keycode.menu.about", appName),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: L("keycode.menu.hide", appName),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthersItem = appMenu.addItem(
            withTitle: L("keycode.menu.hideOthers"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: L("keycode.menu.showAll"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: L("keycode.menu.quit", appName),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: L("keycode.menu.window"))
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(
            withTitle: L("keycode.menu.minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: L("keycode.menu.close"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
