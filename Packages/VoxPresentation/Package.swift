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
        .package(path: "../../../LokiKit"),
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
                .product(name: "LokiKit", package: "LokiKit"),
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
                .product(name: "LokiKit", package: "LokiKit"),
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
                .product(name: "LokiKit", package: "LokiKit"),
            ]
        ),
        .testTarget(
            name: "WidgetUITests",
            dependencies: ["WidgetUI"]
        ),
    ]
)
