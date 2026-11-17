// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DzhmilKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DzhmilCore", targets: ["DzhmilCore"])
    ],
    targets: [
        .target(name: "DzhmilCore"),
        .testTarget(name: "DzhmilCoreTests", dependencies: ["DzhmilCore"])
    ]
)
