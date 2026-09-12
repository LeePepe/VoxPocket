#!/usr/bin/env python3
"""Run production log configuration tests without the signed App test host."""
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    lokikit = root.parent / "LokiKit"
    with tempfile.TemporaryDirectory(prefix="vox-logging-unit-") as temporary:
        package = Path(temporary)
        sources = package / "Sources/VoxPocket"
        tests = package / "Tests/VoxPocketTests"
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        (package / "Package.swift").write_text(f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LoggingRegression", platforms: [.macOS(.v26)],
    dependencies: [.package(path: {json.dumps(str(lokikit))})],
    targets: [
        .target(name: "VoxPocket", dependencies: [.product(name: "LokiKit", package: "LokiKit")]),
        .testTarget(name: "VoxPocketTests", dependencies: ["VoxPocket"])
    ])
''')
        (sources / "VoxPocketLogging.swift").symlink_to(root / "VoxPocket/VoxPocket/VoxPocketLogging.swift")
        (tests / "VoxPocketLoggingTests.swift").symlink_to(root / "VoxPocket/VoxPocketTests/VoxPocketLoggingTests.swift")
        subprocess.run(["swift", "test", "--package-path", str(package)], check=True, timeout=180)


if __name__ == "__main__":
    main()
