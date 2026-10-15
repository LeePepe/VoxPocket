#!/usr/bin/env python3
"""Production TestFlight relevance classifier for VoxPocket.

Pure classifier that decides TestFlight release eligibility based on:
1. Resolved marker status (absent, equal, valid-ancestor, or invalid).
2. Changed paths between marker and candidate commit.
3. Manual force flag (bypasses relevance only for unreleased candidate).

This module performs no Git/GitHub operations, builds, uploads, or state mutations.
"""
from dataclasses import dataclass
import json
from pathlib import Path
import sys
from typing import Iterable, Optional, Sequence, Tuple


class TestFlightRelevanceError(ValueError):
    """Base error for testflight relevance classifier."""
    pass


class InvalidMarkerStatusError(TestFlightRelevanceError):
    """Raised when marker status is invalid, corrupt, or non-ancestor."""
    pass


VALID_MARKER_STATUSES = frozenset({
    "absent",
    "equal",
    "valid-ancestor",
})

RELEVANT_PREFIXES = (
    "Packages/",
    "VoxPocket/",
    "VoxPocketWidget/",
    "fastlane/",
)

RELEVANT_EXACT_FILES = frozenset({
    ".github/workflows/testflight.yml",
    "scripts/ci/fetch-external-deps.sh",
})

REASON_FIRST_RELEASE = "first-release"
REASON_APP_RELEVANT_CHANGE = "app-relevant-change"
REASON_FORCED_RELEVANCE = "forced-relevance"
REASON_ALREADY_RELEASED = "already-released"
REASON_NO_APP_RELEVANT_CHANGE = "no-app-relevant-change"


@dataclass(frozen=True)
class RelevanceDecision:
    release: bool
    reason: str
    relevant_paths: Tuple[str, ...]

    def to_dict(self) -> dict:
        return {
            "release": self.release,
            "reason": self.reason,
            "relevant_paths": list(self.relevant_paths),
        }


def is_relevant_path(path: str) -> bool:
    """Return True if path matches any of the TestFlight release relevance rules."""
    if not isinstance(path, str):
        raise TypeError(f"path must be a string, got {type(path).__name__}")
    p = path.strip()
    if not p:
        return False
    if p.startswith("./"):
        p = p[2:]
    if any(p.startswith(prefix) for prefix in RELEVANT_PREFIXES):
        return True
    if p in RELEVANT_EXACT_FILES:
        return True
    return False


def filter_relevant_paths(paths: Iterable[str]) -> list[str]:
    """Filter changed paths returning only those relevant to TestFlight release in stable order."""
    if paths is None:
        return []
    result = []
    for path in paths:
        if not isinstance(path, str):
            raise TypeError(f"path entries must be strings, got {type(path).__name__}")
        if is_relevant_path(path):
            result.append(path)
    return result


def classify_relevance(
    candidate_sha: str,
    marker_status: str,
    marker_sha: Optional[str] = None,
    changed_paths: Optional[Sequence[str]] = None,
    force: bool = False,
) -> RelevanceDecision:
    """Classify TestFlight release eligibility according to the active specification.

    Decision table order:
    1. Marker status validation: If marker_status is not in {"absent", "equal", "valid-ancestor"} -> fail closed.
    2. Marker equality: If marker_status == "equal" or candidate_sha == marker_sha -> skip ("already-released"); force is ignored.
    3. Absent marker: If marker_status == "absent" -> release ("first-release"); relevance is not evaluated.
    4. Valid ancestor marker:
       - If changed_paths contains at least one relevant path -> release ("app-relevant-change")
       - If no relevant path and force is True -> release ("forced-relevance")
       - If no relevant path and force is False -> skip ("no-app-relevant-change")
    """
    if not isinstance(candidate_sha, str) or not candidate_sha.strip():
        raise TestFlightRelevanceError("candidate_sha must be a non-empty string")

    if not isinstance(marker_status, str) or marker_status not in VALID_MARKER_STATUSES:
        raise InvalidMarkerStatusError(
            f"Invalid marker status: {marker_status!r}. Must be one of {sorted(VALID_MARKER_STATUSES)}"
        )

    # 2. Marker equality check
    if marker_status == "equal" or (
        marker_sha is not None
        and isinstance(marker_sha, str)
        and marker_sha.strip()
        and candidate_sha.strip() == marker_sha.strip()
    ):
        return RelevanceDecision(
            release=False,
            reason=REASON_ALREADY_RELEASED,
            relevant_paths=(),
        )

    # 3. Absent marker (bootstrap first-release)
    if marker_status == "absent":
        return RelevanceDecision(
            release=True,
            reason=REASON_FIRST_RELEASE,
            relevant_paths=(),
        )

    # 4. Valid ancestor marker
    if marker_status == "valid-ancestor":
        if changed_paths is None:
            raw_paths: Sequence[str] = ()
        elif isinstance(changed_paths, (list, tuple, set, frozenset)):
            raw_paths = tuple(changed_paths)
        else:
            raise TestFlightRelevanceError(
                f"changed_paths must be a sequence of strings, got {type(changed_paths).__name__}"
            )

        matching = filter_relevant_paths(raw_paths)
        if matching:
            return RelevanceDecision(
                release=True,
                reason=REASON_APP_RELEVANT_CHANGE,
                relevant_paths=tuple(matching),
            )
        if bool(force):
            return RelevanceDecision(
                release=True,
                reason=REASON_FORCED_RELEVANCE,
                relevant_paths=(),
            )
        return RelevanceDecision(
            release=False,
            reason=REASON_NO_APP_RELEVANT_CHANGE,
            relevant_paths=(),
        )

    raise InvalidMarkerStatusError(f"Unhandled marker status: {marker_status!r}")


def parse_args(argv: Optional[Sequence[str]] = None):
    import argparse

    parser = argparse.ArgumentParser(
        description="Classify app relevance and eligibility for TestFlight release."
    )
    parser.add_argument("--candidate-sha", required=True, help="Candidate commit SHA")
    parser.add_argument(
        "--marker-status",
        required=True,
        choices=sorted(VALID_MARKER_STATUSES),
        help="Resolved status of testflight/macos-last-released tag",
    )
    parser.add_argument("--marker-sha", default=None, help="Last released marker SHA if resolved")
    parser.add_argument(
        "--force",
        action="store_true",
        default=False,
        help="Manual force boolean (bypasses relevance only for unreleased candidate)",
    )
    parser.add_argument(
        "--paths",
        nargs="*",
        default=None,
        help="Changed paths from git diff --name-only marker..candidate",
    )
    parser.add_argument(
        "--paths-file",
        default=None,
        help="File containing newline-separated changed paths",
    )
    parser.add_argument(
        "--paths-from-stdin",
        action="store_true",
        default=False,
        help="Read changed paths from standard input",
    )
    parser.add_argument(
        "--github-output",
        default=None,
        help="Path to GITHUB_OUTPUT file for writing release and reason variables",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        default=False,
        help="Output JSON summary",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    try:
        try:
            args = parse_args(argv)
        except SystemExit as err:
            return err.code if isinstance(err.code, int) else 1
        changed_paths = []
        if args.paths_from_stdin:
            changed_paths.extend([line.strip() for line in sys.stdin if line.strip()])
        elif args.paths_file:
            path_file = Path(args.paths_file)
            if not path_file.is_file():
                print(f"Error: paths file not found: {args.paths_file}", file=sys.stderr)
                return 1
            changed_paths.extend([
                line.strip()
                for line in path_file.read_text(encoding="utf-8").splitlines()
                if line.strip()
            ])
        elif args.paths is not None:
            changed_paths.extend(args.paths)

        decision = classify_relevance(
            candidate_sha=args.candidate_sha,
            marker_status=args.marker_status,
            marker_sha=args.marker_sha,
            changed_paths=changed_paths,
            force=args.force,
        )

        if args.github_output:
            out_path = Path(args.github_output)
            with out_path.open("a", encoding="utf-8") as f:
                f.write(f"release={'true' if decision.release else 'false'}\n")
                f.write(f"reason={decision.reason}\n")
                f.write(f"relevant_count={len(decision.relevant_paths)}\n")

        if args.json:
            print(json.dumps(decision.to_dict(), indent=2))
        else:
            print(f"release={'true' if decision.release else 'false'}")
            print(f"reason={decision.reason}")
            if decision.relevant_paths:
                print(f"relevant_paths={','.join(decision.relevant_paths)}")
        return 0
    except (TestFlightRelevanceError, ValueError, TypeError) as err:
        print(f"testflight_relevance error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
