// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoxPocketKit",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26), .visionOS(.v26)],
    products: [.library(name: "VoxPocketKit", targets: ["VoxPocketKit"])],
    dependencies: [.package(path: "../VoxDomain")],
    targets: [
        .target(name: "VoxPocketKit", dependencies: [.product(name: "CoreModels", package: "VoxDomain")]),
        .testTarget(name: "VoxPocketKitTests", dependencies: ["VoxPocketKit", .product(name: "CoreModels", package: "VoxDomain")])
    ]
)
