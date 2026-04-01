// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoxUITesting",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "VoxFunctionalTest",
            targets: ["VoxFunctionalTest"]
        ),
        .library(
            name: "VoxAgentEval",
            targets: ["VoxAgentEval"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            from: "1.17.0"
        ),
    ],
    targets: [
        // MARK: - VoxFunctionalTest
        .target(
            name: "VoxFunctionalTest",
            dependencies: [
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // MARK: - VoxAgentEval
        .target(
            name: "VoxAgentEval",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // MARK: - Test Targets
        .testTarget(
            name: "VoxFunctionalTestTests",
            dependencies: [
                "VoxFunctionalTest",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
        .testTarget(
            name: "VoxAgentEvalTests",
            dependencies: ["VoxAgentEval"]
        ),
    ]
)
