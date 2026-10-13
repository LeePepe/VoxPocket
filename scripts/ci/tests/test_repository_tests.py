#!/usr/bin/env python3
"""Unit tests for repository test discovery CLI."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CI = Path(__file__).resolve().parents[1]
CLI = CI / "run_repository_tests.py"

spec = importlib.util.spec_from_file_location("run_repository_tests", CLI)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RepositoryTestsDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)

    def test_discover_paths_returns_sorted_files(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        (scripts_tests / "test_z.py").write_text("# z")
        (scripts_tests / "test_a.py").write_text("# a")
        (scripts_tests / "test_m.py").write_text("# m")
        (scripts_tests / "not_a_test.py").write_text("# ignore")

        paths = runner.discover_paths("test_*.py", scripts_tests)
        names = [p.name for p in paths]
        self.assertEqual(names, ["test_a.py", "test_m.py", "test_z.py"])

    def test_discover_paths_nonexistent_dir_returns_empty(self):
        paths = runner.discover_paths("test_*.py", self.root / "nonexistent")
        self.assertEqual(paths, [])

    def test_app_python_discovers_and_runs_all_tests_directly(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        (scripts_tests / "test_01.py").write_text(
            "import sys\nsys.exit(0)\n"
        )
        (scripts_tests / "test_02.py").write_text(
            "import sys\nsys.exit(0)\n"
        )

        code = runner.run_app_python(self.root)
        self.assertEqual(code, 0)

    def test_app_python_empty_fails_closed(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        code = runner.run_app_python(self.root)
        self.assertEqual(code, 1)

    def test_app_python_child_failure_propagates(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        (scripts_tests / "test_ok.py").write_text("import sys\nsys.exit(0)\n")
        (scripts_tests / "test_fail.py").write_text("import sys\nsys.exit(42)\n")

        code = runner.run_app_python(self.root)
        self.assertEqual(code, 42)

    def test_packaging_ruby_passes_environment_and_runs_tests(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        (scripts_tests / "test_pkg.rb").write_text("exit(0)")

        mock_ruby = self.root / "mock_ruby.py"
        mock_ruby.write_text(
            "import sys\n"
            "sys.exit(0)\n"
        )
        old_ruby = os.environ.get("RUBY")
        try:
            wrapper = self.root / "ruby_wrapper.sh"
            wrapper.write_text(f"#!/bin/sh\n{sys.executable} {mock_ruby} \"$@\"\n")
            wrapper.chmod(0o755)
            os.environ["RUBY"] = str(wrapper)

            code = runner.run_packaging_ruby(self.root)
            self.assertEqual(code, 0)
        finally:
            if old_ruby is not None:
                os.environ["RUBY"] = old_ruby
            else:
                os.environ.pop("RUBY", None)

    def test_packaging_ruby_empty_fails_closed(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        code = runner.run_packaging_ruby(self.root)
        self.assertEqual(code, 1)

    def test_icons_python_discovers_and_runs_unittest(self):
        scripts_icons = self.root / "scripts" / "icons"
        scripts_icons.mkdir(parents=True)
        (scripts_icons / "test_icon_feature.py").write_text(
            "import unittest\n"
            "class IconTest(unittest.TestCase):\n"
            "    def test_something(self):\n"
            "        self.assertTrue(True)\n"
        )

        code = runner.run_icons_python(self.root)
        self.assertEqual(code, 0)

    def test_icons_python_empty_fails_closed(self):
        scripts_icons = self.root / "scripts" / "icons"
        scripts_icons.mkdir(parents=True)
        code = runner.run_icons_python(self.root)
        self.assertEqual(code, 1)

    def test_cli_invocation_invalid_group_fails(self):
        proc = subprocess.run(
            [sys.executable, str(CLI), "invalid-group"],
            capture_output=True,
            text=True
        )
        self.assertNotEqual(proc.returncode, 0)


if __name__ == "__main__":
    unittest.main()
