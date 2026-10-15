"""Focused unit tests for the production TestFlight relevance classifier.

Replaces obsolete static manual-only assertions (RB-002/RB-004) with direct
fixtures exercising absent-marker bootstrap, marker equality, valid/invalid
ancestry status, exact relevant/irrelevant/mixed path inputs, accumulated
relevant changes, malformed input failing closed, and manual force bypassing
relevance only.
"""
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("VoxPocket root not found")
    ROOT = ROOT.parent

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.ci.testflight_relevance import (
    InvalidMarkerStatusError,
    REASON_ALREADY_RELEASED,
    REASON_APP_RELEVANT_CHANGE,
    REASON_FIRST_RELEASE,
    REASON_FORCED_RELEVANCE,
    REASON_NO_APP_RELEVANT_CHANGE,
    TestFlightRelevanceError,
    classify_relevance,
    filter_relevant_paths,
    is_relevant_path,
    main as classifier_main,
)


class TestRelevantPathRules(unittest.TestCase):
    def test_relevant_prefixes(self):
        self.assertTrue(is_relevant_path("Packages/VoxDomain/Package.swift"))
        self.assertTrue(is_relevant_path("Packages/VoxInfrastructure/Sources/LLMKit/Merger.swift"))
        self.assertTrue(is_relevant_path("VoxPocket/VoxPocket/ContentView.swift"))
        self.assertTrue(is_relevant_path("VoxPocket/project.yml"))
        self.assertTrue(is_relevant_path("VoxPocketWidget/Widget.swift"))
        self.assertTrue(is_relevant_path("fastlane/Fastfile"))
        self.assertTrue(is_relevant_path("fastlane/Appfile"))

    def test_relevant_exact_files(self):
        self.assertTrue(is_relevant_path(".github/workflows/testflight.yml"))
        self.assertTrue(is_relevant_path("scripts/ci/fetch-external-deps.sh"))

    def test_irrelevant_paths(self):
        irrelevant = [
            "docs/testflight-release.md",
            "docs/index.md",
            "specs/011-testflight-auto-release/spec.md",
            ".github/workflows/ci.yml",
            ".github/pull_request_template.md",
            ".github/CODEOWNERS",
            "scripts/tests/test_testflight_schedule.py",
            "scripts/ci/testflight_relevance.py",
            "scripts/verify",
            "AGENTS.md",
            "CLAUDE.md",
            "README.md",
            "LICENSE",
            "Config.xcconfig",
            ".gitignore",
        ]
        for path in irrelevant:
            self.assertFalse(is_relevant_path(path), f"Expected irrelevant: {path}")

    def test_filter_relevant_paths_order_and_types(self):
        paths = [
            "docs/index.md",
            "Packages/VoxDomain/Package.swift",
            "scripts/ci/testflight_relevance.py",
            "fastlane/Fastfile",
            ".github/workflows/ci.yml",
            ".github/workflows/testflight.yml",
        ]
        expected = [
            "Packages/VoxDomain/Package.swift",
            "fastlane/Fastfile",
            ".github/workflows/testflight.yml",
        ]
        self.assertEqual(filter_relevant_paths(paths), expected)
        self.assertEqual(filter_relevant_paths([]), [])
        self.assertEqual(filter_relevant_paths(None), [])

    def test_path_type_error(self):
        with self.assertRaises(TypeError):
            is_relevant_path(123)  # type: ignore[arg-type]
        with self.assertRaises(TypeError):
            filter_relevant_paths(["valid/path", 456])  # type: ignore[list-item]


class TestAbsentMarkerBootstrap(unittest.TestCase):
    def test_absent_marker_bootstrap_releases(self):
        decision = classify_relevance(
            candidate_sha="abc1234",
            marker_status="absent",
            marker_sha=None,
            changed_paths=None,
            force=False,
        )
        self.assertTrue(decision.release)
        self.assertEqual(decision.reason, REASON_FIRST_RELEASE)
        self.assertEqual(decision.relevant_paths, ())

    def test_absent_marker_ignores_paths_and_force(self):
        decision = classify_relevance(
            candidate_sha="abc1234",
            marker_status="absent",
            changed_paths=["docs/index.md"],
            force=True,
        )
        self.assertTrue(decision.release)
        self.assertEqual(decision.reason, REASON_FIRST_RELEASE)
        self.assertEqual(decision.relevant_paths, ())


class TestMarkerEquality(unittest.TestCase):
    def test_equal_marker_status_skips(self):
        decision = classify_relevance(
            candidate_sha="abc1234",
            marker_status="equal",
            marker_sha="abc1234",
            changed_paths=["Packages/VoxDomain/Package.swift"],
            force=False,
        )
        self.assertFalse(decision.release)
        self.assertEqual(decision.reason, REASON_ALREADY_RELEASED)
        self.assertEqual(decision.relevant_paths, ())

    def test_same_sha_skips_even_if_status_valid_ancestor(self):
        decision = classify_relevance(
            candidate_sha="abc1234",
            marker_status="valid-ancestor",
            marker_sha="abc1234",
            changed_paths=["Packages/VoxDomain/Package.swift"],
            force=False,
        )
        self.assertFalse(decision.release)
        self.assertEqual(decision.reason, REASON_ALREADY_RELEASED)

    def test_force_cannot_bypass_marker_equality(self):
        decision = classify_relevance(
            candidate_sha="abc1234",
            marker_status="equal",
            marker_sha="abc1234",
            changed_paths=["Packages/VoxDomain/Package.swift"],
            force=True,
        )
        self.assertFalse(decision.release)
        self.assertEqual(decision.reason, REASON_ALREADY_RELEASED)


class TestInvalidMarkerStatusFailsClosed(unittest.TestCase):
    def test_invalid_marker_statuses_raise(self):
        invalid_statuses = ["invalid", "non-ancestor", "corrupt", "", "unknown", None]
        for status in invalid_statuses:
            with self.assertRaises((InvalidMarkerStatusError, TestFlightRelevanceError)):
                classify_relevance(
                    candidate_sha="abc1234",
                    marker_status=status,  # type: ignore[arg-type]
                    marker_sha="def5678",
                    changed_paths=["Packages/VoxDomain/Package.swift"],
                )

    def test_force_cannot_bypass_invalid_marker(self):
        with self.assertRaises(InvalidMarkerStatusError):
            classify_relevance(
                candidate_sha="abc1234",
                marker_status="non-ancestor",
                marker_sha="def5678",
                changed_paths=["Packages/VoxDomain/Package.swift"],
                force=True,
            )


class TestValidAncestorPathClassification(unittest.TestCase):
    def test_relevant_single_path_releases(self):
        relevant_cases = [
            ("Packages/VoxDomain/Package.swift", "Packages/VoxDomain/Package.swift"),
            ("VoxPocket/ContentView.swift", "VoxPocket/ContentView.swift"),
            ("VoxPocketWidget/Widget.swift", "VoxPocketWidget/Widget.swift"),
            ("fastlane/Fastfile", "fastlane/Fastfile"),
            (".github/workflows/testflight.yml", ".github/workflows/testflight.yml"),
            ("scripts/ci/fetch-external-deps.sh", "scripts/ci/fetch-external-deps.sh"),
        ]
        for input_path, expected_match in relevant_cases:
            decision = classify_relevance(
                candidate_sha="candidate_sha_123",
                marker_status="valid-ancestor",
                marker_sha="marker_sha_456",
                changed_paths=[input_path],
                force=False,
            )
            self.assertTrue(decision.release, f"Expected release for {input_path}")
            self.assertEqual(decision.reason, REASON_APP_RELEVANT_CHANGE)
            self.assertEqual(decision.relevant_paths, (expected_match,))

    def test_irrelevant_paths_skip(self):
        decision = classify_relevance(
            candidate_sha="candidate_sha_123",
            marker_status="valid-ancestor",
            marker_sha="marker_sha_456",
            changed_paths=["docs/index.md", "specs/spec.md", "README.md"],
            force=False,
        )
        self.assertFalse(decision.release)
        self.assertEqual(decision.reason, REASON_NO_APP_RELEVANT_CHANGE)
        self.assertEqual(decision.relevant_paths, ())

    def test_empty_paths_skip(self):
        decision = classify_relevance(
            candidate_sha="candidate_sha_123",
            marker_status="valid-ancestor",
            marker_sha="marker_sha_456",
            changed_paths=[],
            force=False,
        )
        self.assertFalse(decision.release)
        self.assertEqual(decision.reason, REASON_NO_APP_RELEVANT_CHANGE)
        self.assertEqual(decision.relevant_paths, ())

    def test_mixed_paths_release_with_matching_subset(self):
        decision = classify_relevance(
            candidate_sha="candidate_sha_123",
            marker_status="valid-ancestor",
            marker_sha="marker_sha_456",
            changed_paths=[
                "docs/index.md",
                "Packages/VoxDomain/Package.swift",
                "specs/spec.md",
                "fastlane/Fastfile",
                "README.md",
            ],
            force=False,
        )
        self.assertTrue(decision.release)
        self.assertEqual(decision.reason, REASON_APP_RELEVANT_CHANGE)
        self.assertEqual(
            decision.relevant_paths,
            ("Packages/VoxDomain/Package.swift", "fastlane/Fastfile"),
        )

    def test_accumulated_relevant_changes(self):
        all_relevant = [
            "Packages/VoxApplication/Package.swift",
            "VoxPocket/Info.plist",
            "VoxPocketWidget/Info.plist",
            "fastlane/Appfile",
            ".github/workflows/testflight.yml",
            "scripts/ci/fetch-external-deps.sh",
        ]
        decision = classify_relevance(
            candidate_sha="candidate_sha_123",
            marker_status="valid-ancestor",
            marker_sha="marker_sha_456",
            changed_paths=all_relevant,
            force=False,
        )
        self.assertTrue(decision.release)
        self.assertEqual(decision.reason, REASON_APP_RELEVANT_CHANGE)
        self.assertEqual(decision.relevant_paths, tuple(all_relevant))


class TestManualForceBypass(unittest.TestCase):
    def test_force_bypasses_irrelevant_paths(self):
        decision = classify_relevance(
            candidate_sha="candidate_sha_123",
            marker_status="valid-ancestor",
            marker_sha="marker_sha_456",
            changed_paths=["docs/index.md", "README.md"],
            force=True,
        )
        self.assertTrue(decision.release)
        self.assertEqual(decision.reason, REASON_FORCED_RELEVANCE)
        self.assertEqual(decision.relevant_paths, ())

    def test_force_bypasses_empty_paths(self):
        decision = classify_relevance(
            candidate_sha="candidate_sha_123",
            marker_status="valid-ancestor",
            marker_sha="marker_sha_456",
            changed_paths=[],
            force=True,
        )
        self.assertTrue(decision.release)
        self.assertEqual(decision.reason, REASON_FORCED_RELEVANCE)
        self.assertEqual(decision.relevant_paths, ())

    def test_force_with_relevant_paths_reports_app_relevant_change(self):
        decision = classify_relevance(
            candidate_sha="candidate_sha_123",
            marker_status="valid-ancestor",
            marker_sha="marker_sha_456",
            changed_paths=["Packages/VoxDomain/Package.swift"],
            force=True,
        )
        self.assertTrue(decision.release)
        self.assertEqual(decision.reason, REASON_APP_RELEVANT_CHANGE)
        self.assertEqual(decision.relevant_paths, ("Packages/VoxDomain/Package.swift",))


class TestMalformedInputHandling(unittest.TestCase):
    def test_empty_or_whitespace_candidate_sha_raises(self):
        for bad_candidate in ["", "  ", None]:
            with self.assertRaises(TestFlightRelevanceError):
                classify_relevance(
                    candidate_sha=bad_candidate,  # type: ignore[arg-type]
                    marker_status="absent",
                )

    def test_malformed_changed_paths_raises(self):
        with self.assertRaises(TypeError):
            classify_relevance(
                candidate_sha="candidate_sha_123",
                marker_status="valid-ancestor",
                changed_paths=["valid/path", 123],  # type: ignore[list-item]
            )

        with self.assertRaises(TestFlightRelevanceError):
            classify_relevance(
                candidate_sha="candidate_sha_123",
                marker_status="valid-ancestor",
                changed_paths=123,  # type: ignore[arg-type]
            )


class TestCLIExecution(unittest.TestCase):
    def test_cli_absent_bootstrap(self):
        stdout = io.StringIO()
        stderr = io.StringIO()
        old_stdout, old_stderr = sys.stdout, sys.stderr
        try:
            sys.stdout, sys.stderr = stdout, stderr
            rc = classifier_main(["--candidate-sha", "abc1234", "--marker-status", "absent"])
        finally:
            sys.stdout, sys.stderr = old_stdout, old_stderr

        self.assertEqual(rc, 0)
        output = stdout.getvalue()
        self.assertIn("release=true", output)
        self.assertIn("reason=first-release", output)

    def test_cli_valid_ancestor_relevant_json(self):
        stdout = io.StringIO()
        stderr = io.StringIO()
        old_stdout, old_stderr = sys.stdout, sys.stderr
        try:
            sys.stdout, sys.stderr = stdout, stderr
            rc = classifier_main([
                "--candidate-sha", "abc1234",
                "--marker-status", "valid-ancestor",
                "--marker-sha", "def5678",
                "--paths", "docs/index.md", "fastlane/Fastfile",
                "--json",
            ])
        finally:
            sys.stdout, sys.stderr = old_stdout, old_stderr

        self.assertEqual(rc, 0)
        data = json.loads(stdout.getvalue())
        self.assertTrue(data["release"])
        self.assertEqual(data["reason"], REASON_APP_RELEVANT_CHANGE)
        self.assertEqual(data["relevant_paths"], ["fastlane/Fastfile"])

    def test_cli_github_output(self):
        with tempfile.NamedTemporaryFile(mode="w+", delete=False) as tf:
            out_file = Path(tf.name)

        try:
            stdout = io.StringIO()
            stderr = io.StringIO()
            old_stdout, old_stderr = sys.stdout, sys.stderr
            try:
                sys.stdout, sys.stderr = stdout, stderr
                rc = classifier_main([
                    "--candidate-sha", "abc1234",
                    "--marker-status", "valid-ancestor",
                    "--marker-sha", "def5678",
                    "--paths", "docs/index.md",
                    "--github-output", str(out_file),
                ])
            finally:
                sys.stdout, sys.stderr = old_stdout, old_stderr

            self.assertEqual(rc, 0)
            content = out_file.read_text(encoding="utf-8")
            self.assertIn("release=false\n", content)
            self.assertIn("reason=no-app-relevant-change\n", content)
            self.assertIn("relevant_count=0\n", content)
        finally:
            out_file.unlink(missing_ok=True)

    def test_cli_invalid_marker_status_fails_closed(self):
        stdout = io.StringIO()
        stderr = io.StringIO()
        old_stdout, old_stderr = sys.stdout, sys.stderr
        try:
            sys.stdout, sys.stderr = stdout, stderr
            rc = classifier_main([
                "--candidate-sha", "abc1234",
                "--marker-status", "invalid",
            ])
        finally:
            sys.stdout, sys.stderr = old_stdout, old_stderr

        self.assertNotEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()

