// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkepiCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),  // Needed for states(updateInterval:) and export(to:as:) APIs
    ],
    products: [
        .library(
            name: "MarkepiCore",
            targets: ["MarkepiCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/contentauth/c2pa-swift.git", from: "0.0.12"),
    ],
    targets: [
        .target(
            name: "MarkepiCore",
            dependencies: [
                .product(name: "C2PA", package: "c2pa-swift"),
            ],
            path: "Sources/MarkepiCore",
            resources: [
                .process("Resources/Fonts"),
                .process("Resources/Media.xcassets"),
                // Copied, not processed: the marks stay in a `Logos/`
                // subdirectory so they can be enumerated at runtime, and the
                // README rides along instead of tripping the unhandled-file
                // warning `.process` would raise.
                .copy("Resources/Logos"),
                // Same reasoning as Logos: copied so the boundary file keeps
                // its `Geo/` subdirectory and a fixed name at runtime.
                .copy("Resources/Geo")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Command-line front end (macOS only). Not part of any product, so the
        // Xcode app/extension builds never see it — `swift run markepi` only.
        .executableTarget(
            name: "markepi",
            dependencies: ["MarkepiCore"],
            path: "Sources/markepi"
        ),
        .testTarget(
            name: "MarkepiCoreTests",
            dependencies: ["MarkepiCore"],
            path: "Tests/MarkepiCoreTests"
        ),
    ]
)
