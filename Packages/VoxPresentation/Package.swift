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
    ],
    dependencies: [
        .package(path: "../VoxDomain"),
        .package(path: "../VoxInfrastructure"),
        .package(path: "../VoxApplication"),
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
                .product(name: "UseCases", package: "VoxApplication"),
            ]
        ),
        .testTarget(
            name: "UISharedTests",
            dependencies: ["UIShared"]
        ),
    ]
)
