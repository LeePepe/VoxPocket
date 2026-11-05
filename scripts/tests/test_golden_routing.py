#!/usr/bin/env python3
"""Validate the golden-trace/v1 routing fixture contract."""
import json
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    fixture_dir = root / "scripts" / "tests" / "golden"
    for name in ("golden_b_macos.json", "golden_b_ios.json"):
        fixture = fixture_dir / name
        payload = json.loads(fixture.read_text())
        assert payload.get("schema") == "golden-trace/v1", fixture
        assert isinstance(payload.get("traces"), list), fixture


if __name__ == "__main__":
    main()
