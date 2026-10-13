#!/usr/bin/env python3
"""Unit tests for repository test discovery CLI."""
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

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

    def test_app_python_sorted_logging_and_direct_execution(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        trace_file = self.root / "app_python_trace.log"

        for name in ("test_z_last.py", "test_a_first.py", "test_m_middle.py"):
            (scripts_tests / name).write_text(
                f"import sys\n"
                f"with open(r'{trace_file}', 'a') as f:\n"
                f"    f.write('{name}\\n')\n"
                f"sys.exit(0)\n"
            )

        stdout_buf = io.StringIO()
        with patch("sys.stdout", stdout_buf):
            code = runner.run_app_python(self.root)

        self.assertEqual(code, 0)
        output = stdout_buf.getvalue()

        # Assert sorted discovery logging
        lines = output.splitlines()
        discovered_indices = [
            i for i, line in enumerate(lines) if "scripts/tests/test_" in line and "-" in line
        ]
        self.assertEqual(len(discovered_indices), 3)
        self.assertIn("test_a_first.py", lines[discovered_indices[0]])
        self.assertIn("test_m_middle.py", lines[discovered_indices[1]])
        self.assertIn("test_z_last.py", lines[discovered_indices[2]])

        # Assert direct execution in sorted order
        executed = trace_file.read_text().splitlines()
        self.assertEqual(executed, ["test_a_first.py", "test_m_middle.py", "test_z_last.py"])

    def test_app_python_empty_fails_closed(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        stderr_buf = io.StringIO()
        with patch("sys.stderr", stderr_buf):
            code = runner.run_app_python(self.root)
        self.assertEqual(code, 1)
        self.assertIn("no matching python tests found", stderr_buf.getvalue())

    def test_app_python_child_failure_propagates(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        (scripts_tests / "test_01_ok.py").write_text("import sys\nsys.exit(0)\n")
        (scripts_tests / "test_02_fail.py").write_text("import sys\nsys.exit(42)\n")

        stderr_buf = io.StringIO()
        with patch("sys.stderr", stderr_buf):
            code = runner.run_app_python(self.root)
        self.assertEqual(code, 42)
        self.assertIn("Test failed with exit code 42", stderr_buf.getvalue())

    def test_app_python_timeout_fails_closed(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        (scripts_tests / "test_hung.py").write_text("import time\ntime.sleep(5)\n")

        stderr_buf = io.StringIO()
        with patch("sys.stderr", stderr_buf):
            code = runner.run_app_python(self.root, timeout=0.1)
        self.assertEqual(code, 124)
        self.assertIn("Test timed out after 0.1s", stderr_buf.getvalue())

    def test_packaging_ruby_sorted_logging_and_environment_handoff(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        trace_file = self.root / "ruby_trace.log"

        (scripts_tests / "test_z_pkg.rb").write_text("# ruby z")
        (scripts_tests / "test_a_pkg.rb").write_text("# ruby a")

        mock_ruby = self.root / "mock_ruby.py"
        mock_ruby.write_text(
            "import os, sys\n"
            "gem_path = os.environ.get('GEM_PATH')\n"
            "sentinel = os.environ.get('FASTLANE_SENTINEL')\n"
            "if gem_path != 'test_gem_path' or sentinel != 'sentinel_123':\n"
            "    sys.stderr.write('Missing or invalid GEM_PATH / FASTLANE_SENTINEL\\n')\n"
            "    sys.exit(99)\n"
            "arg = sys.argv[1] if len(sys.argv) > 1 else ''\n"
            f"with open(r'{trace_file}', 'a') as f:\n"
            "    f.write(f'{arg}|{gem_path}|{sentinel}\\n')\n"
            "sys.exit(0)\n"
        )

        wrapper = self.root / "ruby_wrapper.sh"
        wrapper.write_text(f"#!/bin/sh\n{sys.executable} {mock_ruby} \"$@\"\n")
        wrapper.chmod(0o755)

        old_env = dict(os.environ)
        os.environ["RUBY"] = str(wrapper)
        os.environ["GEM_PATH"] = "test_gem_path"
        os.environ["FASTLANE_SENTINEL"] = "sentinel_123"

        try:
            stdout_buf = io.StringIO()
            with patch("sys.stdout", stdout_buf):
                code = runner.run_packaging_ruby(self.root)
            self.assertEqual(code, 0)
        finally:
            os.environ.clear()
            os.environ.update(old_env)

        output = stdout_buf.getvalue()
        lines = output.splitlines()
        discovered_indices = [
            i for i, line in enumerate(lines) if "scripts/tests/test_" in line and "-" in line
        ]
        self.assertEqual(len(discovered_indices), 2)
        self.assertIn("test_a_pkg.rb", lines[discovered_indices[0]])
        self.assertIn("test_z_pkg.rb", lines[discovered_indices[1]])

        executed = trace_file.read_text().splitlines()
        self.assertEqual(len(executed), 2)
        self.assertTrue(executed[0].startswith(str(scripts_tests / "test_a_pkg.rb")))
        self.assertTrue(executed[1].startswith(str(scripts_tests / "test_z_pkg.rb")))
        self.assertIn("test_gem_path|sentinel_123", executed[0])
        self.assertIn("test_gem_path|sentinel_123", executed[1])

    def test_packaging_ruby_empty_fails_closed(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        stderr_buf = io.StringIO()
        with patch("sys.stderr", stderr_buf):
            code = runner.run_packaging_ruby(self.root)
        self.assertEqual(code, 1)
        self.assertIn("no matching ruby tests found", stderr_buf.getvalue())

    def test_packaging_ruby_child_failure_propagates(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        (scripts_tests / "test_pkg.rb").write_text("# ruby")

        mock_ruby = self.root / "mock_ruby_fail.py"
        mock_ruby.write_text("import sys\nsys.exit(37)\n")

        wrapper = self.root / "ruby_wrapper_fail.sh"
        wrapper.write_text(f"#!/bin/sh\n{sys.executable} {mock_ruby} \"$@\"\n")
        wrapper.chmod(0o755)

        old_ruby = os.environ.get("RUBY")
        os.environ["RUBY"] = str(wrapper)
        try:
            stderr_buf = io.StringIO()
            with patch("sys.stderr", stderr_buf):
                code = runner.run_packaging_ruby(self.root)
            self.assertEqual(code, 37)
            self.assertIn("Test failed with exit code 37", stderr_buf.getvalue())
        finally:
            if old_ruby is not None:
                os.environ["RUBY"] = old_ruby
            else:
                os.environ.pop("RUBY", None)

    def test_packaging_ruby_timeout_fails_closed(self):
        scripts_tests = self.root / "scripts" / "tests"
        scripts_tests.mkdir(parents=True)
        (scripts_tests / "test_pkg.rb").write_text("# ruby")

        mock_ruby = self.root / "mock_ruby_hang.py"
        mock_ruby.write_text("import time\ntime.sleep(5)\n")

        wrapper = self.root / "ruby_wrapper_hang.sh"
        wrapper.write_text(f"#!/bin/sh\n{sys.executable} {mock_ruby} \"$@\"\n")
        wrapper.chmod(0o755)

        old_ruby = os.environ.get("RUBY")
        os.environ["RUBY"] = str(wrapper)
        try:
            stderr_buf = io.StringIO()
            with patch("sys.stderr", stderr_buf):
                code = runner.run_packaging_ruby(self.root, timeout=0.1)
            self.assertEqual(code, 124)
            self.assertIn("Test timed out after 0.1s", stderr_buf.getvalue())
        finally:
            if old_ruby is not None:
                os.environ["RUBY"] = old_ruby
            else:
                os.environ.pop("RUBY", None)

    def test_icons_python_discovery_dispatch_observable(self):
        scripts_icons = self.root / "scripts" / "icons"
        scripts_icons.mkdir(parents=True)
        marker_file = self.root / "icon_executed.marker"

        (scripts_icons / "test_icon_feature.py").write_text(
            f"import unittest\n"
            f"class IconTest(unittest.TestCase):\n"
            f"    def test_observable_execution(self):\n"
            f"        with open(r'{marker_file}', 'w') as f:\n"
            f"            f.write('ICON_EXECUTED_OK')\n"
            f"        self.assertTrue(True)\n"
        )

        stdout_buf = io.StringIO()
        with patch("sys.stdout", stdout_buf):
            code = runner.run_icons_python(self.root)

        self.assertEqual(code, 0)
        self.assertIn("scripts/icons/test_icon_feature.py", stdout_buf.getvalue())
        self.assertTrue(marker_file.is_file())
        self.assertEqual(marker_file.read_text(), "ICON_EXECUTED_OK")

    def test_icons_python_empty_fails_closed(self):
        scripts_icons = self.root / "scripts" / "icons"
        scripts_icons.mkdir(parents=True)
        stderr_buf = io.StringIO()
        with patch("sys.stderr", stderr_buf):
            code = runner.run_icons_python(self.root)
        self.assertEqual(code, 1)
        self.assertIn("no matching python tests found", stderr_buf.getvalue())

    def test_icons_python_child_failure_propagates(self):
        scripts_icons = self.root / "scripts" / "icons"
        scripts_icons.mkdir(parents=True)
        (scripts_icons / "test_icon_fail.py").write_text(
            "import unittest\n"
            "class IconFailTest(unittest.TestCase):\n"
            "    def test_fails(self):\n"
            "        self.fail('intended failure')\n"
        )

        stderr_buf = io.StringIO()
        with patch("sys.stderr", stderr_buf):
            code = runner.run_icons_python(self.root)
        self.assertNotEqual(code, 0)
        self.assertIn("Icon tests failed with exit code", stderr_buf.getvalue())

    def test_icons_python_timeout_fails_closed(self):
        scripts_icons = self.root / "scripts" / "icons"
        scripts_icons.mkdir(parents=True)
        (scripts_icons / "test_icon_hang.py").write_text(
            "import time, unittest\n"
            "class IconHangTest(unittest.TestCase):\n"
            "    def test_hangs(self):\n"
            "        time.sleep(5)\n"
        )

        stderr_buf = io.StringIO()
        with patch("sys.stderr", stderr_buf):
            code = runner.run_icons_python(self.root, timeout=0.1)
        self.assertEqual(code, 124)
        self.assertIn("Icon tests timed out after 0.1s", stderr_buf.getvalue())

    def test_cli_invocation_invalid_group_fails(self):
        proc = subprocess.run(
            [sys.executable, str(CLI), "invalid-group"],
            capture_output=True,
            text=True
        )
        self.assertNotEqual(proc.returncode, 0)

    def test_cli_invocation_help_works(self):
        proc = subprocess.run(
            [sys.executable, str(CLI), "--help"],
            capture_output=True,
            text=True
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("app-python", proc.stdout)
        self.assertIn("packaging-ruby", proc.stdout)
        self.assertIn("icons-python", proc.stdout)


if __name__ == "__main__":
    unittest.main()
