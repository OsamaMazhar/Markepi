// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatermarkCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),  // Needed for states(updateInterval:) and export(to:as:) APIs
    ],
    products: [
        .library(
            name: "WatermarkCore",
            targets: ["WatermarkCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/contentauth/c2pa-swift.git", from: "0.0.12"),
    ],
    targets: [
        .target(
            name: "WatermarkCore",
            dependencies: [
                .product(name: "C2PA", package: "c2pa-swift"),
            ],
            path: "Sources/WatermarkCore",
            resources: [
                .process("Resources/Fonts"),
                .process("Resources/Media.xcassets"),
                // Copied, not processed: the marks stay in a `Logos/`
                // subdirectory so they can be enumerated at runtime, and the
                // README rides along instead of tripping the unhandled-file
                // warning `.process` would raise.
                .copy("Resources/Logos")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Command-line front end (macOS only). Not part of any product, so the
        // Xcode app/extension builds never see it — `swift run markepi` only.
        .executableTarget(
            name: "markepi",
            dependencies: ["WatermarkCore"],
            path: "Sources/markepi"
        ),
        .testTarget(
            name: "WatermarkCoreTests",
            dependencies: ["WatermarkCore"],
            path: "Tests/WatermarkCoreTests"
        ),
    ]
)
