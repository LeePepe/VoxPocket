#!/usr/bin/env python3
"""Probe the SwiftUI entry point and check iOS startup source structure (not XCTest)."""
from pathlib import Path
import re
import subprocess
import tempfile


def check_ios_startup_source_binding(root):
    """Supplemental source-structure evidence; App XCTest owns executable behavior."""
    startup = (root / "VoxPocket/VoxPocket/AppStartup.swift").read_text()
    shared = re.search(r"static let shared[^=]*=\s*\{(.*?)^    \}\(\)", startup, re.S | re.M)
    if shared is None:
        raise SystemExit("Source binding: shared AppStartup configuration is missing")
    ios = re.search(r"#if os\(iOS\)(.*?)#else(.*?)#endif", shared.group(1), re.S)
    if ios is None:
        raise SystemExit("Source binding: iOS-only shared startup completion is missing")
    binding = re.search(
        r"let (\w+) = ContinuousClock\.now\s+return AppStartup\(\s*"
        r"configurationReady:\s*\{\s*await ServiceContainer\.shared\."
        r"completeProductTelemetryStartup\(startedAt: \1\)\s*\},\s*"
        r"loadConfiguration: LLMAppConfig\.loadRuntimeConfiguration\s*\)",
        ios.group(1),
    )
    if binding is None:
        raise SystemExit("Source binding: iOS readiness must call the existing startup adapter")
    if "ServiceContainer" in ios.group(2) or "configurationReady:" in ios.group(2):
        raise SystemExit("Source binding: macOS must retain AppDelegate startup ownership")
    print("iOS shared-startup source-structure binding passed (not XCTest)", flush=True)


def main():
    root = Path(__file__).resolve().parents[2]
    check_ios_startup_source_binding(root)
    source = (root / "VoxPocket/VoxPocket/VoxPocketApp.swift").read_text()
    entry = re.search(r"@main\s+enum VoxPocketEntryPoint\s*\{.*?^\}", source, re.S | re.M)
    if entry is None:
        raise SystemExit("Entry point changed: update the runtime regression harness")
    with tempfile.TemporaryDirectory(prefix="vox-startup-test-") as temporary:
        directory = Path(temporary)
        entry_file = directory / "Entry.swift"
        entry_file.write_text("import SwiftUI\nimport Foundation\nimport OSLog\n" + entry.group())
        binary = directory / "startup-probe"
        subprocess.run([
            "swiftc", "-parse-as-library", "-swift-version", "6",
            str(entry_file), str(root / "scripts/tests/startup_interaction_probe.swift"),
            "-o", str(binary),
        ], check=True, timeout=60)
        result = subprocess.run([str(binary)], timeout=12)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
