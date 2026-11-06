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
        .package(path: "../VoxKit"),
        // LokiKit from the immutable shared-telemetry v0.2.0 release; tag integrity is checked by scripts/ci/fetch-external-deps.sh.
        .package(url: "https://github.com/LeePepe/shared-telemetry.git", exact: "0.2.0"),
    ],
    targets: [
        .target(
            name: "UIShared",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "TextHistory", package: "VoxDomain"),
                .product(name: "VoxKitBridge", package: "VoxInfrastructure"),
                .product(name: "VoxCore", package: "VoxKit"),
                .product(name: "VoxSpeech", package: "VoxKit"),
                .product(name: "VoxRefine", package: "VoxKit"),
                .product(name: "VoxLLM", package: "VoxKit"),
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
                .product(name: "VoxKitBridge", package: "VoxInfrastructure"),
                .product(name: "VoxCore", package: "VoxKit"),
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "PlatformAdapters", package: "VoxInfrastructure"),
                .product(name: "Preferences", package: "VoxInfrastructure"),
                .product(name: "VoxLLM", package: "VoxKit"),
                .product(name: "VoxRefine", package: "VoxKit"),
                .product(name: "VoxSpeech", package: "VoxKit"),
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
            dependencies: [
                "UIShared",
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "TextHistory", package: "VoxDomain"),
                .product(name: "UseCases", package: "VoxApplication"),
                .product(name: "PlatformAdapters", package: "VoxInfrastructure"),
                .product(name: "Preferences", package: "VoxInfrastructure"),
                .product(name: "VoxKitBridge", package: "VoxInfrastructure"),
                .product(name: "VoxCore", package: "VoxKit"),
                .product(name: "VoxSpeech", package: "VoxKit"),
                .product(name: "VoxLLM", package: "VoxKit"),
            ]
        ),
        .testTarget(
            name: "PlatformUITests",
            dependencies: [
                "PlatformUI",
                "UIShared",
                .product(name: "VoxKitBridge", package: "VoxInfrastructure"),
                .product(name: "UseCases", package: "VoxApplication"),
                .product(name: "PlatformAdapters", package: "VoxInfrastructure"),
                .product(name: "VoxSpeech", package: "VoxKit"),
                .product(name: "VoxCore", package: "VoxKit"),
                .product(name: "VoxLLM", package: "VoxKit"),
                .product(name: "VoxRefine", package: "VoxKit"),
                .product(name: "LokiKit", package: "shared-telemetry"),
            ]
        ),
        .testTarget(
            name: "WidgetUITests",
            dependencies: ["WidgetUI"]
        ),
    ]
)
