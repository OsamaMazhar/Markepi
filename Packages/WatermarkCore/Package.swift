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
                .process("Resources/Fonts")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "WatermarkCoreTests",
            dependencies: ["WatermarkCore"],
            path: "Tests/WatermarkCoreTests"
        ),
    ]
)
