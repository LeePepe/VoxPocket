#!/usr/bin/env python3
"""Run the real app startup unit tests without a launchable/signed app test host."""
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="vox-startup-unit-") as temporary:
        package = Path(temporary)
        sources = package / "Sources/VoxPocket"
        tests = package / "Tests/VoxPocketTests"
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "StartupRegression", platforms: [.macOS(.v15)], targets: [
    .target(name: "VoxPocket"),
    .testTarget(name: "VoxPocketTests", dependencies: ["VoxPocket"])
])
''')
        (sources / "AppStartup.swift").symlink_to(root / "VoxPocket/VoxPocket/AppStartup.swift")
        (sources / "AppStartupView.swift").symlink_to(root / "VoxPocket/VoxPocket/AppStartupView.swift")
        (sources / "FakeLLMAppConfig.swift").write_text('''
@MainActor enum LLMAppConfig {
    static func loadRuntimeConfiguration() async throws {
        preconditionFailure("Startup tests must inject their configuration loader")
    }
}
''')
        (tests / "AppStartupTests.swift").symlink_to(root / "VoxPocket/VoxPocketTests/AppStartupTests.swift")
        subprocess.run(["swift", "test", "--package-path", str(package)], check=True, timeout=120)


if __name__ == "__main__":
    main()
