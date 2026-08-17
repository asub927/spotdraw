// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spotdraw",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Spotdraw",
            path: "Spotdraw",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "SpotdrawTests",
            path: "SpotdrawTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
