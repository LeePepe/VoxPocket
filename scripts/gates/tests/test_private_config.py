import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("guard", Path(__file__).parents[1] / "check_private_config.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class PrivateConfigGuardTests(unittest.TestCase):
    def test_tracked_private_files_and_backups_are_rejected(self):
        for name in ["config.private.json", "nested/config.private.json", "config.private.json.backup", ".config.private.json.swp", "#config.private.json#"]:
            with self.subTest(name=name), patch("sys.argv", ["guard"]), patch("subprocess.check_output", return_value=(name + "\0").encode()):
                with self.assertRaises(SystemExit):
                    guard.main()

    def test_template_cannot_contain_a_key(self):
        template = json.dumps({"azure": {"apiKey": "fake-key", "endpoint": "https://example.invalid"}})
        with patch("sys.argv", ["guard"]), patch("subprocess.check_output", return_value=b""), patch.object(Path, "read_text", return_value=template):
            with self.assertRaises(SystemExit):
                guard.main()

    def test_app_bundle_cannot_contain_private_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary) / "Fixture.app"
            bundle.mkdir()
            (bundle / "config.private.json").write_text("synthetic fixture")
            with patch("sys.argv", ["guard", "--bundle", str(bundle)]), patch("subprocess.check_output", return_value=b""):
                with self.assertRaises(SystemExit):
                    guard.main()

    def test_clean_template_and_bundle_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary) / "Fixture.app"
            bundle.mkdir()
            with patch("sys.argv", ["guard", "--bundle", str(bundle)]), patch("subprocess.check_output", return_value=b"config.example.json\0"):
                guard.main()


if __name__ == "__main__":
    unittest.main()
