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
    dependencies: [.package(path: {json.dumps(str(infrastructure))})],
    targets: [
        .target(name: "VoxPocket", dependencies: [
            .product(name: "TranscriptionKit", package: "VoxInfrastructure"),
            .product(name: "LLMKit", package: "VoxInfrastructure"),
            .product(name: "Preferences", package: "VoxInfrastructure")]),
        .testTarget(name: "VoxPocketTests", dependencies: ["VoxPocket"])
    ])
''')
        (sources / "LLMAppConfig.swift").symlink_to(root / "VoxPocket/VoxPocket/LLMAppConfig.swift")
        (sources / "StageModelRouting.swift").symlink_to(root / "VoxPocket/VoxPocket/StageModelRouting.swift")
        (tests / "RealtimeTranscriberConfigurationTests.swift").symlink_to(
            root / "VoxPocket/VoxPocketTests/RealtimeTranscriberConfigurationTests.swift"
        )
        subprocess.run(["swift", "test", "--package-path", str(package)], check=True, timeout=300)


if __name__ == "__main__":
    main()
