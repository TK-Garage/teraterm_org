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

// UI言語の設定: デフォルトは日本語（Tera Term の主要言語）。
// "Auto" ならシステム言語に従い、明示的に指定されていればそれを優先する。
// AppleLanguages を設定しない場合、macOS は自動的にシステム言語に基づいて
// en.lproj / ja.lproj から適切なローカライズリソースを選択する。
let savedLanguage = UserDefaults.standard.string(forKey: "TeraTermUILanguage") ?? "Japanese"
switch savedLanguage {
case "Auto":
    // システム言語に従う — AppleLanguages を設定しない
    break
default:
    let langCode: String
    switch savedLanguage {
    case "Japanese": langCode = "ja"
    case "English":  langCode = "en"
    default:         langCode = "ja"
    }
    UserDefaults.standard.set([langCode, "en"], forKey: "AppleLanguages")
    UserDefaults.standard.synchronize()
}

// Transform the process into a foreground (GUI) application.
// Without this, SPM executables run as background processes
// and won't show a Dock icon or menu bar.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

// OS標準の外観モード（ライト/ダーク）に追従する
// app.appearance を設定しないことでシステム設定を尊重する

// アプリアイコンをプログラムで設定する。
// ・SwiftPM: Info.plist が埋め込まれないため CFBundleIconFile が効かない。
//   リソースは Bundle.module に配置される。
// ・Xcode:  Info.plist + Asset Catalog で設定されるが、念のため同じ処理を行う。
//   リソースは Bundle.main に配置される。
do {
    #if SWIFT_PACKAGE
    let resourceBundle = Bundle.module
    #else
    let resourceBundle = Bundle.main
    #endif
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
#else
import Foundation
print("Tera Term Mac requires macOS with AppKit. Please build and run on macOS 14.0 or later.")
Foundation.exit(1)
#endif
