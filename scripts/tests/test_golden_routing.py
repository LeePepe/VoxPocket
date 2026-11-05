#!/usr/bin/env python3
"""Validate the golden-trace/v1 routing fixture contract."""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))
from test_realtime_config import main as run_realtime_harness


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    fixture_dir = root / "scripts" / "tests" / "golden"
    for name in ("golden_b_macos.json", "golden_b_ios.json"):
        fixture = fixture_dir / name
        payload = json.loads(fixture.read_text())
        assert payload.get("schema") == "golden-trace/v1", fixture
        traces = payload.get("traces")
        assert isinstance(traces, list) and traces, fixture
        expected = {"intent": "azureFoundry", "tone": "azureFoundry", "entities": "azureFoundry", "tags": "azureFoundry", "params": "azureFoundry"}
        assert all(row.get("routing") == expected for row in traces), fixture
    run_realtime_harness()


if __name__ == "__main__":
    main()
