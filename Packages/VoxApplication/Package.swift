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
        // LokiKit: shared-telemetry 0.1.0 (tag v0.1.0 = 5f4b4d9, guarded by scripts/ci/fetch-external-deps.sh).
        // Dependency-source swap only, no API/behaviour change; all Packages/* must switch together because SwiftPM rejects a path and a remote LokiKit in one graph.
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
