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
        .package(path: "../VoxKit"),
        // LokiKit from the immutable shared-telemetry v0.2.0 release; tag integrity is checked by scripts/ci/fetch-external-deps.sh.
        .package(url: "https://github.com/LeePepe/shared-telemetry.git", exact: "0.2.0"),
    ],
    targets: [
        .target(
            name: "UseCases",
            dependencies: [
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "TextHistory", package: "VoxDomain"),
                .product(name: "VoxKitBridge", package: "VoxInfrastructure"),
                .product(name: "VoxCore", package: "VoxKit"),
                .product(name: "VoxSpeech", package: "VoxKit"),
                .product(name: "VoxRefine", package: "VoxKit"),
                .product(name: "VoxLLM", package: "VoxKit"),
                .product(name: "Persistence", package: "VoxInfrastructure"),
                .product(name: "LokiKit", package: "shared-telemetry"),
                .product(name: "PlatformAdapters", package: "VoxInfrastructure"),
            ]
        ),
        .testTarget(
            name: "UseCasesTests",
            dependencies: [
                "UseCases",
                .product(name: "CoreModels", package: "VoxDomain"),
                .product(name: "LokiKit", package: "shared-telemetry"),
                .product(name: "VoxKitBridge", package: "VoxInfrastructure"),
                .product(name: "VoxCore", package: "VoxKit"),
                .product(name: "VoxSpeech", package: "VoxKit"),
                .product(name: "VoxRefine", package: "VoxKit"),
                .product(name: "VoxLLM", package: "VoxKit"),
            ]
        ),
    ]
)
