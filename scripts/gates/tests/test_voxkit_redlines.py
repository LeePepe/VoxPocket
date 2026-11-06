import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("voxkit_redlines", ROOT / "Packages/VoxKit/scripts/redlines/redlines_check.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RedlineCoverageTests(unittest.TestCase):
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
            return {"dependencies": [{"url": url, "dependencies": dependencies or []}]}

        MODULE.validate_dependencies(graph("https://example.invalid/sdk.git"))
        for url in ("https://example.invalid/shared-telemetry.git", "../example-sdk", "/example-sdk"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                MODULE.validate_dependencies(graph("https://example.invalid/sdk.git", graph(url)["dependencies"]))

    def testDependencyResolutionFailureIsFailClosed(self):
        with patch.object(MODULE, "scan_rule", return_value=[]), \
                patch.object(MODULE.subprocess, "run") as run, \
                patch.object(MODULE, "check_minimal_consumer", return_value=True):
            run.return_value.returncode = 1
            self.assertEqual(MODULE.run_checks(ROOT / "Packages/VoxKit", []), 1)


if __name__ == "__main__":
    unittest.main()
