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
        .package(url: "https://github.com/LeePepe/shared-telemetry.git", exact: "0.1.0"),
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
                .product(name: "LokiKit", package: "shared-telemetry"),
                .product(name: "PlatformAdapters", package: "VoxInfrastructure"),
            ]
        ),
        .testTarget(
            name: "UseCasesTests",
            dependencies: ["UseCases"]
        ),
    ]
)
