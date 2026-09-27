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
        // LokiKit from shared-telemetry v0.1.0, pinned by full commit SHA (immutable; tag v0.1.0 also cross-checked by scripts/ci/fetch-external-deps.sh).
        // Dependency-source swap only, no API/behaviour change; all Packages/* must switch together because SwiftPM rejects a path and a remote LokiKit in one graph.
        .package(url: "https://github.com/LeePepe/shared-telemetry.git", revision: "5f4b4d97d7ad05adb849e0d8937c8745d9b6d15f"),
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
