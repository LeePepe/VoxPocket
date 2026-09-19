#!/usr/bin/env python3
"""Offline tests: Raven routing without credentials, network or GitHub writes."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CI = Path(__file__).resolve().parents[1]
HELPER = CI / "review-raven.py"
spec = importlib.util.spec_from_file_location("review_raven", HELPER)
raven = importlib.util.module_from_spec(spec)
spec.loader.exec_module(raven)

CONFIG = '''model_provider = "raven"
model = "daily-model-must-not-leak"
approval_policy = "never"
[features]
hooks = true
[model_providers.raven]
name = "raven"
base_url = "http://localhost:7024/v1"
wire_api = "responses"
env_key = "RAVEN_TEST_KEY"
'''


class RavenRoutingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name) / "config.toml"
        self.config.write_text(CONFIG)

    def command(self, env=None):
        return raven.build_command(
            self.config, "/opt/homebrew/bin/codex",
            ["--output-schema", "schema.json", "-o", "out.json", "synthetic prompt"],
            {"RAVEN_TEST_KEY": "fixture-not-a-real-credential"} if env is None else env,
        )

    def test_imports_only_raven_connection_not_daily_model_or_capabilities(self):
        command = self.command()
        self.assertEqual(command[:2], ["/opt/homebrew/bin/codex", "exec"])
        text = " ".join(command)
        self.assertIn('model_provider="raven"', text)
        self.assertIn('base_url = "http://localhost:7024/v1"', text)
        self.assertIn('requires_openai_auth = false', text)
        self.assertIn('env_key = "RAVEN_TEST_KEY"', text)
        self.assertNotIn("fixture-not-a-real-credential", text)
        self.assertNotIn("daily-model", text)
        self.assertNotIn("hooks", text)
        self.assertEqual(command[-1], "synthetic prompt")

    def test_missing_environment_fails_before_codex_without_fallback(self):
        with self.assertRaisesRegex(ValueError, "RAVEN_TEST_KEY"):
            self.command({})

    def test_missing_or_malformed_config_is_sanitized(self):
        self.config.write_text('secret = "fixture-sensitive-invalid')
        with self.assertRaises(ValueError) as error:
            self.command()
        self.assertNotIn("fixture-sensitive", str(error.exception))
        self.config.unlink()
        with self.assertRaises(ValueError):
            self.command()

    def test_wrong_provider_does_not_silently_use_openai(self):
        self.config.write_text(CONFIG.replace('model_provider = "raven"', 'model_provider = "openai"'))
        with self.assertRaises(ValueError):
            self.command()

    def test_remote_or_credential_bearing_endpoint_is_rejected(self):
        for endpoint in ("https://example.com/v1", "http://user:secret@localhost:7024/v1",
                         "http://localhost:7024/v1?key=secret", "http://localhost:7024/v1#secret"):
            with self.subTest(endpoint=endpoint):
                self.config.write_text(CONFIG.replace("http://localhost:7024/v1", endpoint))
                with self.assertRaises(ValueError) as error:
                    self.command()
                self.assertNotIn("secret", str(error.exception))

    def test_chatgpt_auth_or_nonresponses_provider_is_rejected(self):
        for config in (CONFIG + "requires_openai_auth = true\n",
                       CONFIG.replace('wire_api = "responses"', 'wire_api = "chat"')):
            self.config.write_text(config)
            with self.assertRaises(ValueError):
                self.command()

    def test_configuration_is_not_shell_evaluated(self):
        marker = Path(self.directory.name) / "must-not-exist"
        self.config.write_text(CONFIG.replace('name = "raven"', f'name = "$(touch {marker})"'))
        self.command()
        self.assertFalse(marker.exists())

    def test_real_launcher_preserves_exec_arguments_and_review_home(self):
        fake = Path(self.directory.name) / "codex"
        fake.write_text(
            '#!' + sys.executable + '\nimport json,os,sys\n'
            'print(json.dumps({"args":sys.argv[1:],"review_home":os.environ.get("CODEX_HOME")}))\n'
        )
        fake.chmod(0o700)
        env = dict(os.environ, CODEX_RAVEN_CONFIG=str(self.config), RAVEN_TEST_KEY="fixture")
        result = subprocess.run([sys.executable, str(HELPER), str(fake), "--skip-git-repo-check", "fixture"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["args"][0], "exec")
        self.assertEqual(output["args"][-2:], ["--skip-git-repo-check", "fixture"])
        self.assertEqual(output["review_home"], os.environ.get("CODEX_HOME"))

    def test_caller_keeps_isolation_and_uses_raven_launcher(self):
        source = (CI / "codex-review.sh").read_text()
        self.assertIn('python3 "$REPO_ROOT/scripts/ci/review-raven.py" "$CODEX_BIN"', source)
        self.assertIn('CODEX_HOME="${CODEX_HOME:-$HOME/.codex-review}"', source)
        self.assertIn("-c sandbox_mode=read-only", source)
        self.assertIn("-c approval_policy=never", source)
        self.assertNotIn('"$CODEX_BIN" exec', source)


if __name__ == "__main__":
    unittest.main()
