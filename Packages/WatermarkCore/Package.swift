// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatermarkCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v11),  // Needed for UTType availability when running tests on macOS
    ],
    products: [
        .library(
            name: "WatermarkCore",
            targets: ["WatermarkCore"]
        ),
    ],
    targets: [
        .target(
            name: "WatermarkCore",
            path: "Sources/WatermarkCore",
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
