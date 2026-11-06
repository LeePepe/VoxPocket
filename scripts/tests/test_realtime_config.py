#!/usr/bin/env python3
"""Compile the production ASR configuration mapper without building a delivery App."""
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="vox-realtime-config-") as temporary:
        package = Path(temporary)
        sources = package / "Sources/VoxPocket"
        tests = package / "Tests/VoxPocketTests"
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        infrastructure = root / "Packages/VoxInfrastructure"
        (package / "Package.swift").write_text(f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "RealtimeConfigRegression", platforms: [.macOS(.v26)],
    dependencies: [.package(path: {json.dumps(str(infrastructure))}), .package(url: "https://github.com/LeePepe/VoxKit.git", exact: "0.1.0")],
    targets: [
        .target(name: "VoxPocket", dependencies: [
            .product(name: "VoxSpeech", package: "VoxKit"),
            .product(name: "VoxKitBridge", package: "VoxInfrastructure"),
            .product(name: "VoxCore", package: "VoxKit"),
            .product(name: "VoxLLM", package: "VoxKit"),
            .product(name: "VoxRefine", package: "VoxKit"),
            .product(name: "VoxWorkflow", package: "VoxKit"),
            .product(name: "VoxWorkflowWhisperKit", package: "VoxKit"),
            .product(name: "Preferences", package: "VoxInfrastructure")]),
        .testTarget(name: "VoxPocketTests", dependencies: ["VoxPocket",
            .product(name: "VoxCore", package: "VoxKit"),
            .product(name: "VoxSpeech", package: "VoxKit"),
            .product(name: "VoxRefine", package: "VoxKit"),
            .product(name: "VoxLLM", package: "VoxKit"),
            .product(name: "VoxKitBridge", package: "VoxInfrastructure"),
            .product(name: "VoxWorkflow", package: "VoxKit"),
            .product(name: "VoxWorkflowWhisperKit", package: "VoxKit")])
    ])
''')
        (sources / "LLMAppConfig.swift").symlink_to(root / "VoxPocket/VoxPocket/LLMAppConfig.swift")
        (sources / "StageModelRouting.swift").symlink_to(root / "VoxPocket/VoxPocket/StageModelRouting.swift")
        (sources / "SDKHostConfiguration.swift").symlink_to(root / "VoxPocket/VoxPocket/SDKHostConfiguration.swift")
        (tests / "RealtimeTranscriberConfigurationTests.swift").symlink_to(
            root / "VoxPocket/VoxPocketTests/RealtimeTranscriberConfigurationTests.swift"
        )
        subprocess.run(["swift", "test", "--package-path", str(package)], check=True, timeout=300)


if __name__ == "__main__":
    main()
