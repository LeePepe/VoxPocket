#!/usr/bin/env python3
"""Run production log configuration tests without the signed App test host."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile


LOKIKIT_URL = "https://github.com/LeePepe/shared-telemetry.git"
LOKIKIT_VERSION = "0.2.0"
PACKAGE_MANIFESTS = (
    "Packages/VoxInfrastructure/Package.swift",
    "Packages/VoxApplication/Package.swift",
    "Packages/VoxPresentation/Package.swift",
)


def assert_dependency_contract(root: Path):
    selector = f'.package(url: "{LOKIKIT_URL}", exact: "{LOKIKIT_VERSION}")'
    for relative_path in PACKAGE_MANIFESTS:
        content = (root / relative_path).read_text()
        assert content.count(selector) == 1, f"{relative_path} must select exact {LOKIKIT_VERSION}"
        dependency_lines = [
            line for line in content.splitlines()
            if LOKIKIT_URL in line and ".package(" in line
        ]
        assert dependency_lines == [f"        {selector},"], (
            f"{relative_path} contains an unsupported shared-telemetry selector"
        )

    production_roots = (root / "VoxPocket/VoxPocket", root / "Packages")
    provider_constructions = []
    max_disk_overrides = []
    for production_root in production_roots:
        for source in production_root.rglob("*.swift"):
            if "Tests" in source.parts or ".build" in source.parts:
                continue
            content = source.read_text()
            if re.search(r"\bLokiTelemetryService\s*\(", content):
                provider_constructions.append(source.relative_to(root).as_posix())
            if "maxDiskBytes:" in content:
                max_disk_overrides.append(source.relative_to(root).as_posix())

    assert provider_constructions == ["VoxPocket/VoxPocket/ServiceContainer.swift"], (
        "raw LokiTelemetryService construction must exist only in the app composition seam"
    )
    service_container = (root / provider_constructions[0]).read_text()
    assert "return TelemetryLifecycleCoordinator {" in service_container
    assert not max_disk_overrides, (
        f"production consumers must use provider-default capacity: {max_disk_overrides}"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=["debug", "release", "both"], default="both")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    assert_dependency_contract(root)
    with tempfile.TemporaryDirectory(prefix="vox-logging-unit-") as temporary:
        package = Path(temporary)
        sources = package / "Sources/VoxPocket"
        tests = package / "Tests/VoxPocketTests"
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        (package / "Package.swift").write_text(f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LoggingRegression", platforms: [.macOS(.v26)],
    dependencies: [.package(url: {json.dumps(LOKIKIT_URL)}, exact: {json.dumps(LOKIKIT_VERSION)})],
    targets: [
        .target(name: "VoxPocket", dependencies: [.product(name: "LokiKit", package: "shared-telemetry")]),
        .testTarget(name: "VoxPocketTests", dependencies: ["VoxPocket"])
    ])
''')
        (sources / "VoxPocketLogging.swift").symlink_to(root / "VoxPocket/VoxPocket/VoxPocketLogging.swift")
        (sources / "TelemetryLifecycleCoordinator.swift").symlink_to(
            root / "VoxPocket/VoxPocket/TelemetryLifecycleCoordinator.swift"
        )
        for source_name in (
            "VoxPocketBlobTelemetry.swift",
            "BlobTelemetryConfiguration.swift",
            "BlobTelemetryHostEligibility.swift",
        ):
            (sources / source_name).symlink_to(root / "VoxPocket/VoxPocket" / source_name)
        (tests / "VoxPocketLoggingTests.swift").symlink_to(root / "VoxPocket/VoxPocketTests/VoxPocketLoggingTests.swift")
        (tests / "TelemetryLifecycleCoordinatorTests.swift").symlink_to(
            root / "VoxPocket/VoxPocketTests/TelemetryLifecycleCoordinatorTests.swift"
        )
        configurations = ["debug", "release"] if arguments.configuration == "both" else [arguments.configuration]
        for configuration in configurations:
            subprocess.run(
                ["swift", "test", "--package-path", str(package), "--configuration", configuration],
                check=True, timeout=240
            )


if __name__ == "__main__":
    main()
