// swift-tools-version: 6.0
import PackageDescription

// The Testing framework lives in the CLT Developer Frameworks directory.
// When running tests on CLT-only machines (no Xcode), pass:
//   swift test -Xswiftc -F -Xswiftc $TESTING_FW_PATH -Xlinker -F -Xlinker $TESTING_FW_PATH
let testingFrameworkPath = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let testingLibPath = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "Spotdraw",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/x-sheep/swift-property-based", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SpotdrawCore",
            path: "Sources/SpotdrawCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore")
            ]
        ),
        .executableTarget(
            name: "Spotdraw",
            dependencies: ["SpotdrawCore"],
            path: "Sources/Spotdraw",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .executableTarget(
            name: "SpotdrawTests",
            dependencies: ["SpotdrawCore"],
            path: "Tests/SpotdrawTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "SpotdrawPropertyTests",
            dependencies: [
                "SpotdrawCore",
                .product(name: "PropertyBased", package: "swift-property-based")
            ],
            path: "Tests/SpotdrawPropertyTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-F", testingFrameworkPath])
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Testing"),
                .unsafeFlags(["-F", testingFrameworkPath, "-L", testingLibPath, "-l_TestingInterop"])
            ]
        )
    ]
)
