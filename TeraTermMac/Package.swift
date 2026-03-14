// swift-tools-version: 5.9
// TeraTermMac - macOS port of Tera Term terminal emulator

import PackageDescription

let package = Package(
    name: "TeraTermMac",
    defaultLocalization: "ja",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TeraTermMac",
            path: "Sources/TeraTermMac",
            exclude: [
                "Info.plist",
            ],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreText"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "TeraTermMacTests",
            dependencies: ["TeraTermMac"],
            path: "Tests/TeraTermMacTests"
        ),
        .executableTarget(
            name: "Keycode",
            path: "Sources/Keycode",
            exclude: [
                "Info.plist",
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .define("ENABLE_HARDENED_RUNTIME"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "KeycodeTests",
            dependencies: ["Keycode"],
            path: "Tests/KeycodeTests"
        ),
    ]
)
