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
        // MARK: - Shared Module (TTLMacroShared)
        .target(
            name: "TTLMacroShared",
            path: "Sources/TTLMacroShared",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),

        // MARK: - TeraTermMac (existing terminal app)
        .executableTarget(
            name: "TeraTermMac",
            dependencies: ["TTLMacroShared"],
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

        // MARK: - Keycode (existing utility app)
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

        // MARK: - TTLMacro (new macro execution app)
        .executableTarget(
            name: "TTLMacro",
            dependencies: ["TTLMacroShared"],
            path: "Sources/TTLMacro",
            exclude: [
                "Info.plist",
                "TTLMacro.entitlements",
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
            name: "TTLMacroTests",
            dependencies: ["TTLMacro", "TTLMacroShared"],
            path: "Tests/TTLMacroTests"
        ),
    ]
)
