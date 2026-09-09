#!/usr/bin/env python3
"""Reject tracked or bundled private model configuration without reading secrets."""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    if any("config.private" in Path(name).name for name in tracked if name):
        sys.exit("Private model configuration must not be tracked.")
    template = json.loads((root / "config.example.json").read_text())
    if template["azure"]["apiKey"] != "" or template["azure"]["endpoint"] != "https://example.invalid":
        sys.exit("Model configuration template must contain placeholders only.")
    if args.bundle:
        if not args.bundle.is_dir() or args.bundle.suffix != ".app":
            sys.exit("Expected an existing .app bundle.")
        if any(args.bundle.rglob("*config.private*")):
            sys.exit("Private model configuration found in app bundle.")
    print("Private model config guard: passed")


if __name__ == "__main__":
    main()
