// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoxInfrastructure",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "TranscriptionKit",
            targets: ["TranscriptionKit"]
        ),
        .library(
            name: "LLMKit",
            targets: ["LLMKit"]
        ),
        .library(
            name: "Persistence",
            targets: ["Persistence"]
        ),
        .library(
            name: "Observability",
            targets: ["Observability"]
        ),
        .library(
            name: "PlatformAdapters",
            targets: ["PlatformAdapters"]
        ),
        .library(
            name: "Preferences",
            targets: ["Preferences"]
        ),
    ],
    dependencies: [
        .package(path: "../VoxDomain"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "TranscriptionKit",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                "Observability",
            ]
        ),
        .target(
            name: "LLMKit",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                "TranscriptionKit",
                "Observability",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "TextHistory", package: "VoxDomain"),
            ]
        ),
        .target(
            name: "Observability",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
            ]
        ),
        .target(
            name: "PlatformAdapters",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                "Observability",
            ]
        ),
        .target(
            name: "Preferences",
            dependencies: []
        ),
        .testTarget(
            name: "TranscriptionKitTests",
            dependencies: ["TranscriptionKit"]
        ),
        .testTarget(
            name: "LLMKitTests",
            dependencies: ["LLMKit"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"]
        ),
    ]
)
