#!/usr/bin/env python3
"""Verify app golden traces against the pinned VoxKit 0.1.0 trace contract."""
from __future__ import annotations

import copy
import hashlib
import io
import json
import tarfile
import urllib.error
import urllib.request
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
VOXKIT_VERSION = "0.1.0"
VOXKIT_SHA = "5190fe56ece8a56ecb2bfb08885b1f2c544cecbc"
FIXTURES = (
    "Tests/GoldenTraceTests/Fixtures/golden_a_llm.json",
    "Tests/GoldenTraceTests/Fixtures/golden_c_speech.json",
)
TRACKED = (
    ROOT / "Packages/VoxInfrastructure/Package.resolved",
    ROOT / "Packages/VoxApplication/Package.resolved",
    ROOT / "Packages/VoxPresentation/Package.resolved",
    ROOT / "VoxPocket/VoxPocket.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
)
APP_GOLDENS = (
    (ROOT / "scripts/tests/golden/golden_b_macos.json", 192,
     "edf27b458c5bc410565c200d4bd4b2a91af4d65c04caf1039e84a51a28564b16"),
    (ROOT / "scripts/tests/golden/golden_b_ios.json", 232,
     "13d336020efd97526ef7358b8f512e88901db330a2755efaadfdf6a93316e95f"),
)
FIXTURE_DIGESTS = {
    "golden_a_llm.json": (35, "aac4d42dd13d2f4b85c6419b970d2f2fd2cec07feb09c2ca2b7917c18f89006c"),
    "golden_c_speech.json": (12, "f0ee0813382dd2fdc3036207a1535cb466104ad24ee1996b88c66f7d6b65f62a"),
}


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise AssertionError(f"{path} is not a JSON object")
    return value


def expand(value: dict) -> dict:
    if value.get("encoding") != "interned-values/v1":
        return value
    values = value.get("values")
    root = value.get("root")
    if not isinstance(values, list) or not isinstance(root, int) or not 0 <= root < len(values):
        raise ValueError("malformed interned-values/v1 envelope")
    expanded: list[object] = []
    for node in values:
        if isinstance(node, dict):
            if not all(isinstance(index, int) and 0 <= index < len(expanded) for index in node.values()):
                raise ValueError("forward or invalid intern reference")
            expanded.append({key: expanded[index] for key, index in node.items()})
        elif isinstance(node, list):
            if not all(isinstance(index, int) and 0 <= index < len(expanded) for index in node):
                raise ValueError("forward or invalid intern reference")
            expanded.append([expanded[index] for index in node])
        else:
            expanded.append(node)
    payload = expanded[root]
    if not isinstance(payload, dict) or payload.get("schema") != "golden-trace/v1":
        raise ValueError("golden trace has an invalid schema")
    return payload


def canonical_digest(payload: dict) -> str:
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def load_remote_fixtures() -> dict[str, dict]:
    url = f"https://github.com/LeePepe/VoxKit/archive/{VOXKIT_SHA}.tar.gz"
    with urllib.request.urlopen(url, timeout=30) as response:
        archive = tarfile.open(fileobj=io.BytesIO(response.read()), mode="r:gz")
        result = {}
        for relative in FIXTURES:
            member = next((item for item in archive.getmembers() if item.name.endswith(relative)), None)
            if member is None or archive.extractfile(member) is None:
                raise AssertionError(f"remote VoxKit fixture missing: {relative}")
            result[Path(relative).name] = expand(json.load(archive.extractfile(member)))
        return result


def verify_pipeline_descriptors(payload: dict) -> None:
    traces = payload.get("traces")
    if not isinstance(traces, list):
        raise AssertionError("app golden payload has no trace rows")
    providers = {"appleIntelligence", "azureFoundry", "skipped"}
    speech_graphs = {
        ("capture.microphone", "speech.apple"),
        ("capture.microphone", "speech.apple", "speech.azure.batch"),
        ("capture.microphone", "speech.apple", "speech.azure.realtime", "speech.azure.batch"),
    }
    for trace in traces:
        pipeline = trace.get("pipeline") if isinstance(trace, dict) else None
        if pipeline is None:
            continue
        keys = set(pipeline)
        if keys not in (
            {"analysis", "configFailure", "merger", "realtime", "refine", "speech"},
            {"merger", "realtime", "speech"},
        ):
            raise AssertionError("pipeline descriptor shape drifted")
        if tuple(pipeline["speech"]) not in speech_graphs:
            raise AssertionError("unknown speech pipeline graph")
        if not isinstance(pipeline["merger"], bool) or not isinstance(pipeline["realtime"], bool):
            raise AssertionError("pipeline boolean descriptor drifted")
        if "analysis" in pipeline:
            analysis = pipeline["analysis"]
            if set(analysis) != {"entities", "intent", "params", "tags", "tone"}:
                raise AssertionError("analysis node graph drifted")
            if any(provider not in providers for provider in analysis.values()) or pipeline["refine"] not in providers:
                raise AssertionError("pipeline provider routing drifted")


def verify_payload(payload: dict, *, expected_rows: int | None = None, expected_digest: str | None = None) -> None:
    if payload.get("schema") != "golden-trace/v1" or payload.get("kind") not in {"llm", "speech", "routing"}:
        raise ValueError("trace payload schema/kind drifted")
    traces = payload.get("traces")
    if not isinstance(traces, list):
        raise ValueError("trace payload has no traces")
    if expected_rows is not None and len(traces) != expected_rows:
        raise ValueError(f"expected {expected_rows} trace rows, got {len(traces)}")
    if expected_digest is not None and canonical_digest(payload) != expected_digest:
        raise ValueError("canonical golden trace digest drifted")


def verify_negative_mutation_rejected() -> None:
    payload = expand(load_json(APP_GOLDENS[0][0]))
    mutated = copy.deepcopy(payload)
    mutated["schema"] = "golden-trace/v1"
    mutated["traces"][0]["pipeline"]["refine"] = "mutatedProvider"
    try:
        verify_payload(mutated, expected_rows=192, expected_digest=APP_GOLDENS[0][2])
    except (ValueError, AssertionError):
        return
    raise AssertionError("mutated golden payload was accepted")


def run_checks() -> None:
    for path in TRACKED:
        resolved = load_json(path)
        pin = next((item for item in resolved.get("pins", []) if item.get("identity") == "voxkit"), None)
        if not pin or pin.get("state", {}).get("version") != VOXKIT_VERSION or pin["state"].get("revision") != VOXKIT_SHA:
            raise AssertionError(f"{path}: voxkit is not pinned to {VOXKIT_VERSION}/{VOXKIT_SHA}")

    remote = load_remote_fixtures()
    for name, (rows, digest) in FIXTURE_DIGESTS.items():
        verify_payload(remote[name], expected_rows=rows, expected_digest=digest)

    for path, rows, digest in APP_GOLDENS:
        payload = expand(load_json(path))
        verify_payload(payload, expected_rows=rows, expected_digest=digest)
        verify_pipeline_descriptors(payload)
    verify_negative_mutation_rejected()


class GoldenDriftTests(unittest.TestCase):
    def test_negative_mutation_is_rejected(self) -> None:
        verify_negative_mutation_rejected()


def main() -> int:
    try:
        run_checks()
    except (OSError, ValueError, AssertionError, KeyError, TypeError, urllib.error.URLError) as error:
        print(f"❌ golden drift: {error}")
        return 1
    print("✅ golden traces match pinned VoxKit 0.1.0 payloads, hashes, rows, and pipeline graphs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
