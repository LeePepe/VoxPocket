#!/usr/bin/env python3
"""Run repository test groups with fail-closed, sorted discovery and timeout enforcement."""
import argparse
import math
import os
from pathlib import Path
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TIMEOUT = 120.0


def parse_positive_timeout(value: str) -> float:
    """Validate and convert timeout argument to a finite positive float."""
    try:
        val = float(value)
    except (ValueError, TypeError) as exc:
        raise argparse.ArgumentTypeError(f"Timeout must be a positive finite number, got {value!r}") from exc

    if not math.isfinite(val) or val <= 0:
        raise argparse.ArgumentTypeError(f"Timeout must be a finite positive number (> 0), got {value!r}")

    return val


def discover_paths(pattern: str, base_dir: Path) -> list[Path]:
    """Find files matching pattern under base_dir, sorted deterministically."""
    if not base_dir.is_dir():
        return []
    matches = sorted(base_dir.glob(pattern))
    return [p for p in matches if p.is_file()]


def run_app_python(repo_root: Path, timeout: float = DEFAULT_TIMEOUT) -> int:
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
        try:
            proc = subprocess.run([sys.executable, str(path)], cwd=str(repo_root), timeout=timeout)
            if proc.returncode != 0:
                print(f"[run_repository_tests] Test failed with exit code {proc.returncode}: {rel}", file=sys.stderr)
                return proc.returncode
        except subprocess.TimeoutExpired:
            print(f"[run_repository_tests] Test timed out after {timeout}s: {rel}", file=sys.stderr)
            return 124
        except OSError as exc:
            print(f"[run_repository_tests] Failed to spawn {rel}: {exc}", file=sys.stderr)
            return 1

    return 0


def run_packaging_ruby(repo_root: Path, timeout: float = DEFAULT_TIMEOUT) -> int:
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
        try:
            proc = subprocess.run([ruby_bin, str(path)], cwd=str(repo_root), timeout=timeout)
            if proc.returncode != 0:
                print(f"[run_repository_tests] Test failed with exit code {proc.returncode}: {rel}", file=sys.stderr)
                return proc.returncode
        except subprocess.TimeoutExpired:
            print(f"[run_repository_tests] Test timed out after {timeout}s: {rel}", file=sys.stderr)
            return 124
        except OSError as exc:
            print(f"[run_repository_tests] Failed to spawn {rel}: {exc}", file=sys.stderr)
            return 1

    return 0


def run_icons_python(repo_root: Path, timeout: float = DEFAULT_TIMEOUT) -> int:
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
    try:
        proc = subprocess.run(
            [sys.executable, "-m", "unittest", "discover", "-s", str(icons_dir), "-p", "test_*.py"],
            cwd=str(icons_dir),
            timeout=timeout
        )
        if proc.returncode != 0:
            print(f"[run_repository_tests] Icon tests failed with exit code {proc.returncode}", file=sys.stderr)
            return proc.returncode
    except subprocess.TimeoutExpired:
        print(f"[run_repository_tests] Icon tests timed out after {timeout}s", file=sys.stderr)
        return 124
    except OSError as exc:
        print(f"[run_repository_tests] Failed to spawn unittest discovery: {exc}", file=sys.stderr)
        return 1

    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run repository test groups with fail-closed discovery.")
    parser.add_argument(
        "group",
        choices=["app-python", "packaging-ruby", "icons-python"],
        help="Test group to run"
    )
    parser.add_argument(
        "--timeout",
        type=parse_positive_timeout,
        default=DEFAULT_TIMEOUT,
        help=f"Per-test timeout in seconds (default: {DEFAULT_TIMEOUT})"
    )

    args = parser.parse_args(argv)

    if args.group == "app-python":
        return run_app_python(REPO_ROOT, timeout=args.timeout)
    elif args.group == "packaging-ruby":
        return run_packaging_ruby(REPO_ROOT, timeout=args.timeout)
    elif args.group == "icons-python":
        return run_icons_python(REPO_ROOT, timeout=args.timeout)
    else:
        print(f"Unknown group: {args.group}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
