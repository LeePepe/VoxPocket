// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoxNotificationKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "VoxNotificationKit",
            targets: ["VoxNotificationKit"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "VoxNotificationKit",
            dependencies: []
        ),
        .testTarget(
            name: "VoxNotificationKitTests",
            dependencies: ["VoxNotificationKit"]
        )
    ]
)
