// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoxPresentation",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "UIShared",
            targets: ["UIShared"]
        ),
        .library(
            name: "PlatformUI",
            targets: ["PlatformUI"]
        ),
        .library(
            name: "WidgetUI",
            type: .dynamic,
            targets: ["WidgetUI"]
        ),
    ],
    dependencies: [
        .package(path: "../VoxDomain"),
        .package(path: "../VoxInfrastructure"),
        .package(path: "../VoxApplication"),
        // LokiKit: shared-telemetry 0.1.0 (tag v0.1.0 = 5f4b4d9, guarded by scripts/ci/fetch-external-deps.sh).
        // Dependency-source swap only, no API/behaviour change; all Packages/* must switch together because SwiftPM rejects a path and a remote LokiKit in one graph.
        .package(url: "https://github.com/LeePepe/shared-telemetry.git", exact: "0.1.0"),
    ],
    targets: [
        .target(
            name: "UIShared",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "TextHistory", package: "VoxDomain"),
                .product(name: "LLMKit", package: "VoxInfrastructure"),
                .product(name: "TranscriptionKit", package: "VoxInfrastructure"),
                .product(name: "PlatformAdapters", package: "VoxInfrastructure"),
                .product(name: "Preferences", package: "VoxInfrastructure"),
                .product(name: "LokiKit", package: "shared-telemetry"),
                .product(name: "UseCases", package: "VoxApplication"),
            ]
        ),
        .target(
            name: "PlatformUI",
            dependencies: [
                "UIShared",
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "PlatformAdapters", package: "VoxInfrastructure"),
                .product(name: "Preferences", package: "VoxInfrastructure"),
                .product(name: "LLMKit", package: "VoxInfrastructure"),
                .product(name: "TranscriptionKit", package: "VoxInfrastructure"),
                .product(name: "LokiKit", package: "shared-telemetry"),
                .product(name: "UseCases", package: "VoxApplication"),
            ]
        ),
        .target(
            name: "WidgetUI",
            dependencies: []
        ),
        .testTarget(
            name: "UISharedTests",
            dependencies: ["UIShared"]
        ),
        .testTarget(
            name: "PlatformUITests",
            dependencies: [
                "PlatformUI",
                .product(name: "UseCases", package: "VoxApplication"),
                .product(name: "PlatformAdapters", package: "VoxInfrastructure"),
                .product(name: "TranscriptionKit", package: "VoxInfrastructure"),
                .product(name: "LokiKit", package: "shared-telemetry"),
            ]
        ),
        .testTarget(
            name: "WidgetUITests",
            dependencies: ["WidgetUI"]
        ),
    ]
)
