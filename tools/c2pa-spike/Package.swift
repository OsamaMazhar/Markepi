// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "c2pa-spike",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/contentauth/c2pa-swift.git", from: "0.0.12"),
    ],
    targets: [
        .executableTarget(
            name: "c2pa-spike",
            dependencies: [.product(name: "C2PA", package: "c2pa-swift")]
        ),
    ]
)
