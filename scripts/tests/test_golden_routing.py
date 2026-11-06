#!/usr/bin/env python3
"""Execute the production macOS routing matrix and compare the recorded golden."""
import json
from pathlib import Path
import subprocess
import tempfile

from test_realtime_config import main as run_realtime_harness


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    scratch_path = Path(tempfile.gettempdir()) / "voxpocket-routing-harness-build"
    with tempfile.TemporaryDirectory(prefix="vox-golden-routing-") as temporary:
        package = Path(temporary)
        sources = package / "Sources/VoxPocket"
        tests = package / "Tests/VoxPocketTests"
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        infrastructure = json.dumps(str(root / "Packages/VoxInfrastructure"))
        (package / "Package.swift").write_text(f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "GoldenRoutingRegression", platforms: [.macOS(.v26)],
    dependencies: [.package(path: {infrastructure}), .package(url: "https://github.com/LeePepe/VoxKit.git", exact: "0.1.0")],
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
            .product(name: "VoxSpeech", package: "VoxKit"),
            .product(name: "VoxKitBridge", package: "VoxInfrastructure"),
            .product(name: "VoxCore", package: "VoxKit"),
            .product(name: "VoxLLM", package: "VoxKit"),
            .product(name: "VoxRefine", package: "VoxKit"),
            .product(name: "VoxWorkflow", package: "VoxKit"),
            .product(name: "VoxWorkflowWhisperKit", package: "VoxKit"),
            .product(name: "Preferences", package: "VoxInfrastructure")],
            resources: [.copy("golden_b_macos.json")],
            swiftSettings: [.define("VOX_ROUTING_HARNESS")])
    ])
''')
        for name in ("StageModelRouting", "LLMAppConfig", "SDKHostConfiguration"):
            (sources / f"{name}.swift").symlink_to(root / f"VoxPocket/VoxPocket/{name}.swift")
        (tests / "GoldenRoutingTests.swift").symlink_to(root / "VoxPocket/VoxPocketTests/GoldenRoutingTests.swift")
        (tests / "golden_b_macos.json").symlink_to(root / "scripts/tests/golden/golden_b_macos.json")
        subprocess.run(
            [
                "swift",
                "test",
                "--package-path",
                str(package),
                "--scratch-path",
                str(scratch_path),
                "--explicit-target-dependency-import-check",
                "error",
            ],
            check=True,
            timeout=300,
        )
    run_realtime_harness(scratch_path)


if __name__ == "__main__":
    main()
