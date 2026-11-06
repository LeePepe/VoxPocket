// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MinimalConsumer",
    platforms: [.macOS(.v26), .iOS(.v26)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "MinimalConsumer", dependencies: [
            .product(name: "VoxCore", package: "VoxKit"),
            .product(name: "VoxSpeech", package: "VoxKit"),
            .product(name: "VoxRefine", package: "VoxKit"),
            .product(name: "VoxLLM", package: "VoxKit"),
        ])
    ],
    swiftLanguageModes: [.v6]
)
