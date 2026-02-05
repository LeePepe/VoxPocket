// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoxDomain",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "CoreModels",
            targets: ["CoreModels"]
        ),
        .library(
            name: "TextHistory",
            targets: ["TextHistory"]
        ),
    ],
    targets: [
        .target(
            name: "CoreModels",
            dependencies: []
        ),
        .target(
            name: "TextHistory",
            dependencies: ["CoreModels"]
        ),
        .testTarget(
            name: "CoreModelsTests",
            dependencies: ["CoreModels"]
        ),
        .testTarget(
            name: "TextHistoryTests",
            dependencies: ["TextHistory"]
        ),
    ]
)
