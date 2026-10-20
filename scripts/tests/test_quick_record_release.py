#!/usr/bin/env python3
"""Run production Fn handlers with a suspended recorder, without an App or microphone."""
from pathlib import Path
import subprocess
import tempfile


def method(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def main():
    root = Path(__file__).resolve().parents[2]
    delegate = (root / "VoxPocket/VoxPocket/AppDelegate.swift").read_text()
    window = (root / "VoxPocket/VoxPocket/WindowManager.swift").read_text()
    fixture = (root / "scripts/tests/quick_record_release_probe.swift").read_text()
    handlers = delegate.split("// QUICK_RECORD_HANDLERS_BEGIN", 1)[1].split(
        "// QUICK_RECORD_HANDLERS_END", 1)[0]
    lifecycle = (root / "Packages/VoxPresentation/Sources/PlatformUI/"
                 "QuickRecordingReleaseLifecycle.swift").read_text()
    fixture = fixture.replace("// PRODUCTION_RELEASE_LIFECYCLE", lifecycle)
    fixture = fixture.replace("// PRODUCTION_HANDLERS", handlers)
    fixture = fixture.replace("// PRODUCTION_SESSION", method(
        delegate, "private struct QuickRecordingSession"))
    catalog = (root / "Packages/VoxInfrastructure/Sources/TranscriptionKit/"
               "VoxPocketTelemetryEventName.swift").read_text()
    fixture = fixture.replace("// PRODUCTION_EVENT_NAMES", method(
        catalog, "public enum VoxPocketTelemetryEventName"))
    fixture = fixture.replace("// PRODUCTION_WINDOW_START", method(
        window, "public func showQuickRecordingAndStart() async"))
    with tempfile.TemporaryDirectory(prefix="vox-fn-release-") as temporary:
        source = Path(temporary) / "probe.swift"
        binary = Path(temporary) / "probe"
        source.write_text(fixture)
        for mode, flags in [("Release", []), ("Debug", ["-D", "DEBUG"])]:
            print(f"Production quick-record handler probe: {mode}", flush=True)
            subprocess.run(["swiftc", "-parse-as-library", "-swift-version", "6", *flags,
                            str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=15)


if __name__ == "__main__":
    main()
