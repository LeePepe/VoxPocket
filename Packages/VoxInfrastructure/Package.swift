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
        .library(name: "VoxKitBridge", targets: ["VoxKitBridge"]),
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
        .package(path: "../VoxKit"),
        // LokiKit from the immutable shared-telemetry v0.2.0 release; tag integrity is checked by scripts/ci/fetch-external-deps.sh.
        .package(url: "https://github.com/LeePepe/shared-telemetry.git", exact: "0.2.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "TranscriptionKit",
            dependencies: [
                "VoxKitBridge",
                .product(name: "VoxCore", package: "VoxKit"),
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "LokiKit", package: "shared-telemetry"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .target(
            name: "LLMKit",
            dependencies: [
                .product(name: "VoxCore", package: "VoxKit"),
                "TranscriptionKit",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),
        .target(name: "VoxKitBridge", dependencies: [.product(name: "VoxCore", package: "VoxKit"), .product(name: "LokiKit", package: "shared-telemetry")]),
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
            dependencies: ["TranscriptionKit", "LLMKit", "Preferences", .product(name: "VoxCore", package: "VoxKit"), .product(name: "LokiKit", package: "shared-telemetry")],
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "TranscriptionKitTests",
            dependencies: [
                .product(name: "VoxCore", package: "VoxKit"),
                "TranscriptionKit",
                .product(name: "LokiKit", package: "shared-telemetry"),
            ]
        ),
        .testTarget(name: "VoxKitBridgeTests", dependencies: ["VoxKitBridge", .product(name: "VoxCore", package: "VoxKit"), .product(name: "LokiKit", package: "shared-telemetry")]),
        .testTarget(
            name: "LLMKitTests",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "VoxCore", package: "VoxKit"),
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
        .testTarget(
            name: "GoldenTraceTests",
            dependencies: [
                .product(name: "VoxCore", package: "VoxKit"),
                "TranscriptionKit",
                "LLMKit",
                "Preferences",
                .product(name: "LokiKit", package: "shared-telemetry"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
