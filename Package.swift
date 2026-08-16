// swift-tools-version: 5.9
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
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
