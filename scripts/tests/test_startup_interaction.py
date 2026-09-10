#!/usr/bin/env python3
"""Run the production SwiftUI entry point with delayed, credential-free fixtures."""
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
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
