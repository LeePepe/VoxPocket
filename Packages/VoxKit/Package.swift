// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoxKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "VoxCore", targets: ["VoxCore"]),
        .library(name: "VoxSpeech", targets: ["VoxSpeech"]),
        .library(name: "VoxSpeechWhisperKit", targets: ["VoxSpeechWhisperKit"]),
        .library(name: "VoxRefine", targets: ["VoxRefine"]),
        .library(name: "VoxLLM", targets: ["VoxLLM"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.12.0"),
    ],
    targets: [
        .target(name: "VoxCore"),
        .target(
            name: "VoxSpeech",
            dependencies: [
                "VoxCore",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),
        .target(
            name: "VoxSpeechWhisperKit",
            dependencies: [
                "VoxSpeech",
                "VoxCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .target(name: "VoxRefine", dependencies: ["VoxCore"]),
        .target(
            name: "VoxLLM",
            dependencies: [
                "VoxCore",
                "VoxRefine",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),
        .testTarget(name: "VoxCoreTests", dependencies: ["VoxCore"]),
        .testTarget(name: "VoxRefineTests", dependencies: ["VoxRefine", "VoxCore"]),
    ],
    swiftLanguageModes: [.v6]
)
