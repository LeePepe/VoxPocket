#!/usr/bin/env python3
"""Run repository test groups with fail-closed, sorted discovery."""
import argparse
import os
from pathlib import Path
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]


def discover_paths(pattern: str, base_dir: Path) -> list[Path]:
    """Find files matching pattern under base_dir, sorted deterministically."""
    if not base_dir.is_dir():
        return []
    matches = sorted(base_dir.glob(pattern))
    return [p for p in matches if p.is_file()]


def run_app_python(repo_root: Path) -> int:
    """Execute every scripts/tests/test_*.py directly with sys.executable."""
    tests_dir = repo_root / "scripts" / "tests"
    paths = discover_paths("test_*.py", tests_dir)
    if not paths:
        print("[run_repository_tests] Error: no matching python tests found in scripts/tests", file=sys.stderr)
        return 1

    print(f"[run_repository_tests] Discovered {len(paths)} python test(s) under scripts/tests:")
    for path in paths:
        try:
            rel = path.relative_to(repo_root)
        except ValueError:
            rel = path
        print(f"  - {rel}")

    for path in paths:
        try:
            rel = path.relative_to(repo_root)
        except ValueError:
            rel = path
        print(f"\n[run_repository_tests] Running {rel} ...")
        proc = subprocess.run([sys.executable, str(path)], cwd=str(repo_root))
        if proc.returncode != 0:
            print(f"[run_repository_tests] Test failed with exit code {proc.returncode}: {rel}", file=sys.stderr)
            return proc.returncode

    return 0


def run_packaging_ruby(repo_root: Path) -> int:
    """Execute every scripts/tests/test_*.rb with caller-provided Ruby environment."""
    tests_dir = repo_root / "scripts" / "tests"
    paths = discover_paths("test_*.rb", tests_dir)
    if not paths:
        print("[run_repository_tests] Error: no matching ruby tests found in scripts/tests", file=sys.stderr)
        return 1

    ruby_bin = os.environ.get("RUBY", "ruby")

    print(f"[run_repository_tests] Discovered {len(paths)} ruby test(s) under scripts/tests:")
    for path in paths:
        try:
            rel = path.relative_to(repo_root)
        except ValueError:
            rel = path
        print(f"  - {rel}")

    for path in paths:
        try:
            rel = path.relative_to(repo_root)
        except ValueError:
            rel = path
        print(f"\n[run_repository_tests] Running {rel} ...")
        proc = subprocess.run([ruby_bin, str(path)], cwd=str(repo_root))
        if proc.returncode != 0:
            print(f"[run_repository_tests] Test failed with exit code {proc.returncode}: {rel}", file=sys.stderr)
            return proc.returncode

    return 0


def run_icons_python(repo_root: Path) -> int:
    """Execute icon unittest suite via python3 -m unittest discover."""
    icons_dir = repo_root / "scripts" / "icons"
    paths = discover_paths("test_*.py", icons_dir)
    if not paths:
        print("[run_repository_tests] Error: no matching python tests found in scripts/icons", file=sys.stderr)
        return 1

    print(f"[run_repository_tests] Discovered {len(paths)} icon test(s) under scripts/icons:")
    for path in paths:
        try:
            rel = path.relative_to(repo_root)
        except ValueError:
            rel = path
        print(f"  - {rel}")

    print("\n[run_repository_tests] Running unittest discovery for scripts/icons ...")
    proc = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", str(icons_dir), "-p", "test_*.py"],
        cwd=str(icons_dir)
    )
    if proc.returncode != 0:
        print(f"[run_repository_tests] Icon tests failed with exit code {proc.returncode}", file=sys.stderr)
        return proc.returncode

    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run repository test groups with fail-closed discovery.")
    parser.add_argument(
        "group",
        choices=["app-python", "packaging-ruby", "icons-python"],
        help="Test group to run"
    )

    args = parser.parse_args(argv)

    if args.group == "app-python":
        return run_app_python(REPO_ROOT)
    elif args.group == "packaging-ruby":
        return run_packaging_ruby(REPO_ROOT)
    elif args.group == "icons-python":
        return run_icons_python(REPO_ROOT)
    else:
        print(f"Unknown group: {args.group}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
