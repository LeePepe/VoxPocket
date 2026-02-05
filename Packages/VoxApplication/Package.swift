// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoxApplication",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "UseCases",
            targets: ["UseCases"]
        ),
    ],
    dependencies: [
        .package(path: "../VoxDomain"),
        .package(path: "../VoxInfrastructure"),
    ],
    targets: [
        .target(
            name: "UseCases",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "TextHistory", package: "VoxDomain"),
                .product(name: "TranscriptionKit", package: "VoxInfrastructure"),
                .product(name: "LLMKit", package: "VoxInfrastructure"),
                .product(name: "Persistence", package: "VoxInfrastructure"),
                .product(name: "Observability", package: "VoxInfrastructure"),
                .product(name: "PlatformAdapters", package: "VoxInfrastructure"),
            ]
        ),
        .testTarget(
            name: "UseCasesTests",
            dependencies: ["UseCases"]
        ),
    ]
)
