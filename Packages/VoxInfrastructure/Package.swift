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
            name: "VoxKitBridge",
            targets: ["VoxKitBridge"]
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
        .package(path: "../VoxKit"),
        // LokiKit from the immutable shared-telemetry v0.2.0 release; tag integrity is checked by scripts/ci/fetch-external-deps.sh.
        .package(url: "https://github.com/LeePepe/shared-telemetry.git", exact: "0.2.0"),
    ],
    targets: [
        .target(
            name: "VoxKitBridge",
            dependencies: [
                .product(name: "VoxCore", package: "VoxKit"),
                .product(name: "VoxSpeech", package: "VoxKit"),
                .product(name: "LokiKit", package: "shared-telemetry"),
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
            dependencies: [
                "Preferences",
                .product(name: "VoxCore", package: "VoxKit"),
                .product(name: "VoxSpeech", package: "VoxKit"),
                .product(name: "VoxSpeechWhisperKit", package: "VoxKit"),
                .product(name: "VoxLLM", package: "VoxKit"),
                .product(name: "VoxRefine", package: "VoxKit"),
                .product(name: "LokiKit", package: "shared-telemetry"),
            ],
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "VoxKitBridgeTests",
            dependencies: [
                "VoxKitBridge",
                .product(name: "VoxCore", package: "VoxKit"),
                .product(name: "VoxSpeech", package: "VoxKit"),
                .product(name: "VoxSpeechWhisperKit", package: "VoxKit"),
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
