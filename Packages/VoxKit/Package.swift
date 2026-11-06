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
        .library(name: "VoxWorkflow", targets: ["VoxWorkflow"]),
        .library(name: "VoxWorkflowWhisperKit", targets: ["VoxWorkflowWhisperKit"]),
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
        .target(
            name: "VoxWorkflow",
            dependencies: ["VoxCore", "VoxSpeech", "VoxRefine", "VoxLLM"]
        ),
        .target(
            name: "VoxWorkflowWhisperKit",
            dependencies: ["VoxWorkflow", "VoxSpeechWhisperKit", "VoxSpeech", "VoxCore"]
        ),
        .testTarget(name: "VoxCoreTests", dependencies: ["VoxCore"]),
        .testTarget(name: "VoxSpeechTests", dependencies: ["VoxSpeech", "VoxCore"]),
        .testTarget(name: "VoxSpeechWhisperKitTests", dependencies: ["VoxSpeechWhisperKit", "VoxSpeech", "VoxCore"]),
        .testTarget(name: "VoxRefineTests", dependencies: ["VoxRefine", "VoxCore"]),
        .testTarget(name: "VoxLLMTests", dependencies: ["VoxLLM", "VoxRefine", "VoxCore"]),
        .testTarget(name: "VoxWorkflowTests", dependencies: ["VoxWorkflow", "VoxCore", "VoxRefine", "VoxLLM", "VoxSpeech"]),
        .testTarget(name: "CanaryTests", dependencies: ["VoxWorkflow", "VoxWorkflowWhisperKit", "VoxCore", "VoxRefine", "VoxLLM", "VoxSpeech"]),
    ],
    swiftLanguageModes: [.v6]
)
