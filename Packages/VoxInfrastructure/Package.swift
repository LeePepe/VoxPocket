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
        .package(url: "https://github.com/LeePepe/shared-telemetry.git", exact: "0.1.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "TranscriptionKit",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "LokiKit", package: "shared-telemetry"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .target(
            name: "LLMKit",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                "TranscriptionKit",
                .product(name: "LokiKit", package: "shared-telemetry"),
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
            name: "PlatformAdapters",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "LokiKit", package: "shared-telemetry"),
            ]
        ),
        .target(
            name: "Preferences",
            dependencies: []
        ),
        .testTarget(
            name: "PrivateTranscriptionBenchmarkTests",
            dependencies: ["TranscriptionKit", "LLMKit", "Preferences", .product(name: "LokiKit", package: "shared-telemetry")],
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "TranscriptionKitTests",
            dependencies: [
                "TranscriptionKit",
                .product(name: "LokiKit", package: "shared-telemetry"),
            ]
        ),
        .testTarget(
            name: "LLMKitTests",
            dependencies: [
                "LLMKit",
                .product(name: "LokiKit", package: "shared-telemetry"),
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"]
        ),
        .testTarget(
            name: "PreferencesTests",
            dependencies: ["Preferences"]
        ),
    ]
)
