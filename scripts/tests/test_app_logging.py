#!/usr/bin/env python3
"""Run production log configuration tests without the signed App test host."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=["debug", "release", "both"], default="both")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="vox-logging-unit-") as temporary:
        package = Path(temporary)
        lokikit_sources = package / "Sources/LokiKit"
        sources = package / "Sources/VoxPocket"
        tests = package / "Tests/VoxPocketTests"
        lokikit_sources.mkdir(parents=True)
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LoggingRegression", platforms: [.macOS(.v26)],
    targets: [
        .target(name: "LokiKit"),
        .target(name: "VoxPocket", dependencies: ["LokiKit"]),
        .testTarget(name: "VoxPocketTests", dependencies: ["VoxPocket"])
    ])
''')
        (lokikit_sources / "LokiKitStub.swift").write_text('''import Foundation

public final class LokiLogSink: Sendable {
    public init(
        endpoint: URL,
        labels: [String: String],
        allowedMessages: Set<String>,
        allowedContextKeys: Set<String>,
        persistenceURL: URL?,
        token: String?
    ) {}

    public func start() -> Task<Void, Never> {
        Task { }
    }
}

public struct PrintLogger: Sendable {
    public init(subsystem: String) {}
    public static func configureRemoteSink(_ sink: LokiLogSink) {}
    public func info(_ message: String) {}
}
''')
        (sources / "VoxPocketLogging.swift").symlink_to(root / "VoxPocket/VoxPocket/VoxPocketLogging.swift")
        (tests / "VoxPocketLoggingTests.swift").symlink_to(root / "VoxPocket/VoxPocketTests/VoxPocketLoggingTests.swift")
        configurations = ["debug", "release"] if arguments.configuration == "both" else [arguments.configuration]
        for configuration in configurations:
            subprocess.run(
                ["swift", "test", "--package-path", str(package), "--configuration", configuration],
                check=True, timeout=60
            )


if __name__ == "__main__":
    main()
