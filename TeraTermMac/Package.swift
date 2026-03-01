// swift-tools-version: 5.9
// TeraTermMac - macOS port of Tera Term terminal emulator

import PackageDescription

let package = Package(
    name: "TeraTermMac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TeraTermMac",
            path: "Sources/TeraTermMac",
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
    ]
)
