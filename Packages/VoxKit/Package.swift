// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoxKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "VoxCore", targets: ["VoxCore"])],
    targets: [
        .target(name: "VoxCore"),
        .testTarget(name: "VoxCoreTests", dependencies: ["VoxCore"])
    ],
    swiftLanguageModes: [.v6]
)
