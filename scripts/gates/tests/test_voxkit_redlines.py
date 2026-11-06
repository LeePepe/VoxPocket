import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("voxkit_redlines", ROOT / "Packages/VoxKit/scripts/redlines/redlines_check.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RedlineCoverageTests(unittest.TestCase):
    def testR5CoversGoldenJSONFixtures(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture = root / "golden.json"
            fixture.write_text('{"product": "VoxPocket"}')
            self.assertEqual(len(MODULE.scan_rule("R5", [root])), 1)
            fixture.write_text('{"product": "example-sdk"}')
            self.assertEqual(MODULE.scan_rule("R5", [root]), [])

    def testGeneratedBuildCheckoutsAreNotSDKCode(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / ".build/checkouts/example").mkdir(parents=True)
            (root / ".build/checkouts/example/Vendor.swift").write_text("import Combine\n")
            (root / "Consumer.swift").write_text("import VoxSpeech\n")
            self.assertEqual(list(MODULE.swift_files([root])), [root / "Consumer.swift"])

    def testAllSourcesAndR5TestsExamplesAreScanned(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for directory in ("Sources/VoxSpeech", "Tests/VoxSpeechTests", "Examples/MinimalConsumer"):
                (root / directory).mkdir(parents=True)
                (root / directory / "Synthetic.swift").write_text("import Combine\nlet product = \"VoxPocket\"\n")
            visited = {}

            def record(rule, paths):
                visited[rule] = {file.relative_to(root).parts[0] for file in MODULE.swift_files(paths)}
                return []

            with patch.object(MODULE, "scan_rule", side_effect=record), \
                    patch.object(MODULE, "check_sendable_invariants", return_value=[]), \
                    patch.object(MODULE, "validate_manifest_and_resolved"), \
                    patch.object(MODULE.subprocess, "run") as run, \
                    patch.object(MODULE, "check_minimal_consumer", return_value=True):
                run.return_value.returncode = 0
                run.return_value.stdout = '{"dependencies": []}'
                self.assertEqual(MODULE.run_checks(root, [root / "Sources", root / "Tests", root / "Examples"]), 0)
            self.assertEqual(visited["R5"], {"Sources", "Tests", "Examples"})
            for rule in ("R1", "R2", "R3b", "R4a", "R4b"):
                self.assertEqual(visited[rule], {"Sources"})

    def testDependencyClosureRejectsNestedTelemetryAndLocalPaths(self):
        def graph(url, dependencies=None):
            return {"dependencies": [{"identity": "swift-async-algorithms", "version": "1.1.7",
                                      "url": url, "dependencies": dependencies or []}]}

        approved = "https://github.com/apple/swift-async-algorithms"
        MODULE.validate_dependencies(graph(approved))
        for url in ("https://example.invalid/shared-telemetry.git", "../example-sdk", "/example-sdk"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                MODULE.validate_dependencies(graph(approved, graph(url)["dependencies"]))

    def testUnapprovedRemoteIsRejected(self):
        with self.assertRaises(ValueError):
            MODULE.validate_dependencies({"dependencies": [{"identity": "pkg", "url": "https://example.com/evil/pkg.git"}]})

    def testResolvedRevisionAndManifestAreAllowlisted(self):
        snapshot = {"pins": [{"identity": name, "location": pin[0], "kind": "remoteSourceControl",
                             "state": {"version": pin[1], "revision": pin[2]}}
                            for name, pin in MODULE.APPROVED_DEPENDENCIES.items()]}
        for manifest, revision in (("", None), ("", "0" * 40), ('.package(url: "https://example.com/evil/pkg.git")', None)):
            snapshot["pins"][0]["state"]["revision"] = revision or next(iter(MODULE.APPROVED_DEPENDENCIES.values()))[2]
            with patch.object(Path, "read_text", side_effect=[manifest, json.dumps(snapshot)]):
                if not manifest and not revision: MODULE.validate_manifest_and_resolved(ROOT); continue
                with self.assertRaises(ValueError): MODULE.validate_manifest_and_resolved(ROOT)

    def testSendableInlineRationaleAndBudget(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Sources/VoxSpeech").mkdir(parents=True)
            (root / "scripts/redlines").mkdir(parents=True)
            (root / "scripts/redlines/pre-migration-baseline.json").write_text(
                '{"sendable_baseline":{"VoxSpeech":{"target_count_after_T110":1}}}')
            source = root / "Sources/VoxSpeech/Boundary.swift"
            for declaration in ("struct Boundary: @unchecked Sendable {}", "nonisolated(unsafe) let boundary = 0"):
                for comment in ("", " // Sendable: Combine bridge", " // Sendable: Apple callback guarded by Mutex"):
                    source.write_text("// Sendable: preceding comment\n" + declaration + comment)
                    self.assertEqual(bool(MODULE.check_sendable_invariants(root)), "Mutex" not in comment)
                source.write_text(source.read_text() * 2)
                self.assertTrue(MODULE.check_sendable_invariants(root))

    def testDependencyResolutionFailureIsFailClosed(self):
        with patch.object(MODULE, "scan_rule", return_value=[]), \
                patch.object(MODULE.subprocess, "run") as run, \
                patch.object(MODULE, "check_minimal_consumer", return_value=True):
            run.return_value.returncode = 1
            self.assertEqual(MODULE.run_checks(ROOT / "Packages/VoxKit", []), 1)


if __name__ == "__main__":
    unittest.main()
