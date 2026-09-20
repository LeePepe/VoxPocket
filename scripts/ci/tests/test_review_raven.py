#!/usr/bin/env python3
"""Offline tests: Raven routing without credentials, network or GitHub writes."""
import importlib.util
import json
import os
from pathlib import Path
from unittest import mock
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
env_key = "RAVEN_API_KEY"
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
            {"RAVEN_API_KEY": "fixture-not-a-real-credential"} if env is None else env,
        )

    def test_imports_only_raven_connection_not_daily_model_or_capabilities(self):
        command = self.command()
        self.assertEqual(command[:2], ["/opt/homebrew/bin/codex", "exec"])
        text = " ".join(command)
        self.assertIn('model_provider="raven"', text)
        self.assertIn('base_url = "http://localhost:7024/v1"', text)
        self.assertIn('requires_openai_auth = false', text)
        self.assertIn('env_key = "RAVEN_API_KEY"', text)
        self.assertNotIn("fixture-not-a-real-credential", text)
        self.assertNotIn("daily-model", text)
        self.assertNotIn("hooks", text)
        self.assertEqual(command[-1], "synthetic prompt")

    def test_missing_environment_fails_before_codex_without_fallback(self):
        with self.assertRaisesRegex(ValueError, "RAVEN_API_KEY"):
            self.command({})

    def test_unrelated_ci_credentials_are_rejected_before_environment_lookup(self):
        class MockNoCredentialReads(dict):
            def get(self, key, default=None):
                raise AssertionError("Unrelated credential environment must not be inspected")

        for key in ("GH_TOKEN", "GITHUB_TOKEN", "ANTHROPIC_API_KEY", "AZURE_API_KEY"):
            with self.subTest(key=key):
                self.config.write_text(CONFIG.replace("RAVEN_API_KEY", key))
                with self.assertRaisesRegex(ValueError, "Unsupported Raven credential environment name"):
                    self.command(MockNoCredentialReads())

    def test_both_existing_raven_credential_names_remain_supported(self):
        for key in ("RAVEN_API_KEY", "OPENAI_API_KEY"):
            with self.subTest(key=key):
                self.config.write_text(CONFIG.replace("RAVEN_API_KEY", key))
                command = self.command({key: "fixture-not-a-real-credential"})
                self.assertIn(f'env_key = "{key}"', " ".join(command))
                self.assertNotIn("fixture-not-a-real-credential", " ".join(command))

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
        review_home = str(Path(self.directory.name) / "review-home")
        env = dict(os.environ, CODEX_RAVEN_CONFIG=str(self.config), RAVEN_API_KEY="fixture",
                   CODEX_HOME="daily-home-must-not-leak", CODEX_REVIEW_HOME=review_home)
        result = subprocess.run([sys.executable, str(HELPER), str(fake), "--skip-git-repo-check", "fixture"],
                                env=env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["args"][0], "exec")
        self.assertEqual(output["args"][-2:], ["--skip-git-repo-check", "fixture"])
        self.assertEqual(output["review_home"], str(Path(review_home).resolve()))

    def test_caller_keeps_isolation_and_uses_raven_launcher(self):
        source = (CI / "codex-review.sh").read_text()
        self.assertIn('python3 "$REPO_ROOT/scripts/ci/review-raven.py" "$CODEX_BIN"', source)
        self.assertIn('CODEX_HOME="${CODEX_REVIEW_HOME:-$HOME/.codex-review}"', source)
        self.assertLess(source.index('--check-setup'), source.index('if ! git fetch'))
        self.assertIn("-c sandbox_mode=read-only", source)
        self.assertIn("-c approval_policy=never", source)
        self.assertNotIn('"$CODEX_BIN" exec', source)

    def test_default_review_home_ignores_daily_home_and_does_not_mutate_environment(self):
        environment = {"CODEX_HOME": "daily-home-must-not-leak"}
        with mock.patch.object(raven.Path, "home", return_value=Path(self.directory.name)):
            actual = raven.review_environment(environment, self.config)
        self.assertEqual(actual["CODEX_HOME"], str((Path(self.directory.name) / ".codex-review").resolve()))
        self.assertEqual(environment, {"CODEX_HOME": "daily-home-must-not-leak"})

    def test_explicit_daily_home_and_symlink_alias_are_rejected(self):
        alias = Path(self.directory.name) / "daily-alias"
        alias.symlink_to(self.config.parent, target_is_directory=True)
        for home in (str(self.config.parent), str(alias), str(Path.home() / ".codex")):
            with self.subTest(home=home), self.assertRaisesRegex(ValueError, "separate"):
                raven.review_environment({"CODEX_REVIEW_HOME": home}, self.config)

    def setup_check(self, config=None, **overrides):
        if config is not None:
            self.config.write_text(config)
        env = {key: value for key, value in os.environ.items()
               if key not in {"OPENAI_API_KEY", "RAVEN_API_KEY"}}
        env.update(CODEX_RAVEN_CONFIG=str(self.config), RAVEN_API_KEY="fixture-private-key",
                   CODEX_REVIEW_HOME=str(Path(self.directory.name) / "review-home"))
        env.update(overrides)
        return subprocess.run([sys.executable, str(HELPER), "--check-setup", sys.executable],
                              env=env, capture_output=True, text=True, timeout=5)

    def test_setup_only_never_starts_binary_or_reads_auth_files(self):
        with mock.patch.dict(os.environ, {
            "CODEX_RAVEN_CONFIG": str(self.config), "RAVEN_API_KEY": "fixture-private-key",
            "CODEX_REVIEW_HOME": str(Path(self.directory.name) / "review-home"),
        }), mock.patch.object(sys, "argv", [str(HELPER), "--check-setup", sys.executable]), \
                mock.patch.object(raven.os, "execvpe") as execute, \
                mock.patch.object(Path, "read_text", autospec=True, return_value=CONFIG) as read, \
                mock.patch("builtins.print") as output:
            self.assertEqual(raven.main(), 0)
            execute.assert_not_called()
            self.assertEqual([call.args[0] for call in read.call_args_list], [self.config])
            text = str(output.call_args_list)
            self.assertIn("no model request", text)
            self.assertNotIn("fixture-private-key", text)

    def test_setup_subprocess_pass_is_not_review_pass(self):
        result = self.setup_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Raven setup PASS", result.stdout)
        self.assertIn("no model request, profile validation, verdict or merge verification", result.stdout)
        self.assertNotIn("fixture-private-key", result.stdout + result.stderr)

    def test_setup_errors_are_sanitized_and_fail_closed(self):
        for config in ('secret = "fixture-private-key',
                       'model_provider = "raven"\nmodel_providers = "fixture-private-key"',
                       'model_provider = "raven"\n[model_providers]\nraven = "fixture-private-key"',
                       CONFIG.replace("localhost:7024", "localhost:fixture-private-key")):
            with self.subTest(config=config):
                result = self.setup_check(config)
                self.assertEqual(result.returncode, 1)
                self.assertIn("Raven setup failed", result.stderr)
                self.assertNotIn("fixture-private-key", result.stdout + result.stderr)
                self.assertNotIn("Traceback", result.stderr)
        result = self.setup_check(CONFIG, RAVEN_API_KEY="")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Runner is missing Raven environment variable RAVEN_API_KEY", result.stderr)

    def test_missing_binary_is_sanitized(self):
        with mock.patch.dict(os.environ, {
            "CODEX_RAVEN_CONFIG": str(self.config), "RAVEN_API_KEY": "fixture-private-key",
            "CODEX_REVIEW_HOME": str(Path(self.directory.name) / "review-home"),
        }), mock.patch.object(sys, "argv", [str(HELPER), "--check-setup", "/fixture-private-key"]), \
                mock.patch("builtins.print") as output:
            self.assertEqual(raven.main(), 1)
            self.assertIn("Codex executable is unavailable", str(output.call_args_list))
            self.assertNotIn("fixture-private-key", str(output.call_args_list))

    def test_shell_setup_failure_stops_before_fetch_github_or_model(self):
        fake_bin = Path(self.directory.name) / "bin"
        fake_bin.mkdir()
        marker = Path(self.directory.name) / "unexpected-call"
        for name in ("git", "gh", "codex"):
            binary = fake_bin / name
            body = f'#!/bin/bash\nprintf unexpected > "{marker}"\nexit 91\n'
            if name == "git":
                body = (f'#!/bin/bash\nif [ "$1" = rev-parse ]; then\n'
                        f'  printf "%s\\n" "{CI.parents[1]}"\n  exit 0\nfi\n'
                        f'printf unexpected > "{marker}"\nexit 91\n')
            binary.write_text(body)
            binary.chmod(0o700)
        env = dict(os.environ, PATH=f"{fake_bin}:{os.environ['PATH']}",
                   CODEX_RAVEN_CONFIG=str(self.config), CODEX_BIN=str(fake_bin / "codex"),
                   CODEX_HOME="daily-must-not-leak", RAVEN_API_KEY="", OPENAI_API_KEY="",
                   CODEX_REVIEW_HOME=str(Path(self.directory.name) / "review-home"),
                   PR_NUMBER="51", BASE_SHA="fixture", HEAD_SHA="fixture", BASE_REPO="fixture")
        result = subprocess.run(["bash", str(CI / "codex-review.sh")], env=env,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("setup failed before review", result.stderr)
        self.assertFalse(marker.exists(), "setup failure must not fetch, post or invoke a model")


if __name__ == "__main__":
    unittest.main()
