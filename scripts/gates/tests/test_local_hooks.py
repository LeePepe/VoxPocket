"""Hook wiring regressions using disposable Git repositories and fake toolchains."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[3]
ZERO = "0" * 40


class LocalHookTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="voxpocket hook tests ")
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name) / "repo with spaces"
        self.repo.mkdir()
        self.log = Path(self.temporary.name) / "calls.log"
        self.bin = Path(self.temporary.name) / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
                        HOOK_TEST_LOG=str(self.log), PATH=f"{self.bin}:{os.environ['PATH']}")
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "RUN_HEAVY"):
            self.env.pop(key, None)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Hook Test")
        self.git("config", "user.email", "hooks@example.invalid")
        self.write("seed.txt", "fixture\n")
        self.commit("seed")
        self.base = self.git("rev-parse", "HEAD").stdout.strip()
        self.git("update-ref", "refs/remotes/origin/main", self.base)
        for name in ("pre-commit", "pre-push"):
            self.copy(f".githooks/{name}")
        self.copy("scripts/verify")
        self.fake_shared_ci()
        for name in ("codex", "claude", "kimi", "copilot", "xcodebuild"):
            self.tool(name, 'echo "UNEXPECTED_AI_OR_HEAVY" >> "$HOOK_TEST_LOG"\nexit 99\n')

    def tearDown(self):
        self.assertNotIn("UNEXPECTED_AI_OR_HEAVY", self.calls())

    def fake_shared_ci(self):
        """Offline shared-ci stand-in at the SHA pinned in AGENTS.md: audit/lint pass, no layers."""
        shared = Path(self.temporary.name) / "shared-ci"
        (shared / "scripts/context").mkdir(parents=True)
        (shared / "scripts/lint").mkdir(parents=True)
        (shared / "scripts/context/_context.py").write_text(
            "import sys, os\n"
            "open(os.environ['HOOK_TEST_LOG'], 'a').write('context:' + ' '.join(sys.argv[1:]) + '\\n')\n"
            "sys.exit(int(os.environ.get('TEST_CONTEXT_STATUS', '0')))\n")
        (shared / "scripts/lint/workflows.py").write_text("")
        subprocess.run(["git", "init", "-q", str(shared)], check=True, env=self.env)
        subprocess.run(["git", "-C", str(shared), "-c", "user.name=t", "-c", "user.email=t@example.invalid",
                        "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "pin"],
                       check=True, env=self.env)
        subprocess.run(["git", "-C", str(shared), "add", "."], check=True, env=self.env)
        subprocess.run(["git", "-C", str(shared), "-c", "user.name=t", "-c", "user.email=t@example.invalid",
                        "-c", "commit.gpgsign=false", "commit", "-q", "-m", "fake engines"],
                       check=True, env=self.env)
        pin = subprocess.run(["git", "-C", str(shared), "rev-parse", "HEAD"], check=True, env=self.env,
                             capture_output=True, text=True).stdout.strip()
        self.write("AGENTS.md", f"Follow `LeePepe/shared-ci@{pin}/ai/agent-protocol.md`\n")
        self.env["SHARED_CI"] = str(shared)

    def write(self, relative, content):
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def copy(self, relative):
        target = self.repo / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO / relative, target)

    def tool(self, name, body):
        target = self.bin / name
        target.write_text("#!/bin/bash\n" + body)
        target.chmod(0o755)

    def git(self, *args):
        return subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-c",
                               "commit.gpgsign=false", *args], cwd=self.repo,
                              env=self.env, text=True, capture_output=True, check=True)

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "-m", message)

    def calls(self):
        return self.log.read_text() if self.log.exists() else ""

    def hook(self, name, push_input="", cwd=None):
        return subprocess.run(["bash", str(self.repo / ".githooks" / name)],
                              cwd=cwd or self.repo, input=push_input, text=True,
                              capture_output=True, env=self.env)

    def push_input(self, sha=None, local_ref="refs/heads/main", remote_ref="refs/heads/main"):
        sha = sha or self.git("rev-parse", "HEAD").stdout.strip()
        return f"{local_ref} {sha} {remote_ref} {self.base}\n"

    def stub_commit_commands(self, failing=None):
        for relative, label in (("scripts/gates/gate-precommit.sh", "layer"),
                                ("scripts/docs/lint_docs_map.sh", "map"),
                                ("scripts/docs/lint_docs_freshness.sh", "freshness")):
            self.write(relative, f'echo "{label}:$PWD" >> "$HOOK_TEST_LOG"\n'
                       f'exit {23 if label == failing else 0}\n')

    def actual_gate_tools(self):
        for name in ("gate-precommit.sh", "gate-prepush.sh"):
            self.copy(f"scripts/gates/{name}")
        self.tool("python3", 'echo "python3:$*" >> "$HOOK_TEST_LOG"\n'
                  'exit "${TEST_PYTHON_STATUS:-0}"\n')
        self.tool("swift", 'echo "swift:$*" >> "$HOOK_TEST_LOG"\n'
                  'exit "${TEST_SWIFT_STATUS:-0}"\n')
        self.stub_commit_commands()
        self.copy("scripts/gates/gate-precommit.sh")

    def test_commit_runs_all_three_checks_from_subdirectory_with_spaces(self):
        self.stub_commit_commands()
        nested = self.repo / "nested directory"
        nested.mkdir()
        result = self.hook("pre-commit", cwd=nested)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls().splitlines(),
                         [f"{label}:{self.repo}" for label in ("layer", "map", "freshness")])

    def test_each_commit_failure_propagates_and_stops_later_checks(self):
        for label, count in (("layer", 1), ("map", 2), ("freshness", 3)):
            with self.subTest(label=label):
                self.log.write_text("")
                self.stub_commit_commands(failing=label)
                result = self.hook("pre-commit")
                self.assertEqual(result.returncode, 23)
                self.assertEqual(len(self.calls().splitlines()), count)

    def test_push_gate_failure_propagates_from_non_root(self):
        self.write("scripts/gates/gate-prepush.sh", 'echo "push:$PWD" >> "$HOOK_TEST_LOG"\nexit 31\n')
        result = self.hook("pre-push", self.push_input(), cwd=self.repo / "scripts")
        self.assertEqual(result.returncode, 31)
        self.assertEqual(self.calls(), f"context:audit\npush:{self.repo.resolve()}\n")

    def test_actual_commit_gate_runs_build_test_and_docs(self):
        self.actual_gate_tools()
        self.write("Packages/Fixture/Sources/File.swift", "// synthetic\n")
        self.git("add", "Packages")
        result = self.hook("pre-commit")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for call in ("check_private_config.py", "swift:build --package-path Packages/Fixture",
                     "swift:test --package-path Packages/Fixture", "map:", "freshness:"):
            self.assertIn(call, self.calls())

    def test_clean_committed_push_runs_actual_gate(self):
        self.actual_gate_tools()
        self.write("Packages/Fixture/Sources/File.swift", "// synthetic\n")
        self.write("Packages/Fixture/Tests/FileTests.swift", "// synthetic\n")
        self.commit("source with tests")
        self.assertEqual(self.git("status", "--porcelain").stdout, "")
        result = self.hook("pre-push", self.push_input())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for call in ("check_private_config.py", "check_frontmatter.py",
                     "swift:test --package-path Packages/Fixture"):
            self.assertIn(call, self.calls())

    def test_changed_source_without_tests_still_blocks(self):
        self.actual_gate_tools()
        self.write("Packages/Fixture/Sources/File.swift", "// synthetic\n")
        self.commit("source without tests")
        result = self.hook("pre-push", self.push_input())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("无测试改动", result.stdout)

    def test_existing_allow_no_tests_rule_is_preserved(self):
        self.actual_gate_tools()
        self.write("Packages/Fixture/Sources/File.swift", "// synthetic\n")
        self.commit("source\n\nAllow-No-Tests: synthetic fixture")
        result = self.hook("pre-push", self.push_input())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("swift:test", self.calls())

    def test_actual_gate_check_failures_block(self):
        self.actual_gate_tools()
        self.write("Packages/Fixture/Tests/FileTests.swift", "// synthetic\n")
        self.commit("fixture")
        for variable in ("TEST_PYTHON_STATUS", "TEST_SWIFT_STATUS"):
            with self.subTest(variable=variable):
                self.env[variable] = "7"
                result = self.hook("pre-push", self.push_input())
                self.assertNotEqual(result.returncode, 0)
                self.env.pop(variable)

    def test_missing_baseline_fails_closed(self):
        self.actual_gate_tools()
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        result = self.hook("pre-push", self.push_input())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("无法确定", result.stderr)
        self.assertNotIn("无改动", result.stdout)

    def test_other_candidate_tag_or_malformed_input_fails_closed(self):
        for text in (self.push_input("1" * 40), self.push_input(remote_ref="refs/tags/v1"),
                     "malformed\n"):
            with self.subTest(text=text):
                result = self.hook("pre-push", text)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("[pre-push]", result.stderr)

    def test_reference_deletion_has_no_new_candidate(self):
        result = self.hook("pre-push", self.push_input(ZERO, "(delete)"))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.calls(), "")

    def test_multiple_head_ref_updates_run_gate_once(self):
        self.write("scripts/gates/gate-prepush.sh", 'echo "push" >> "$HOOK_TEST_LOG"\n')
        result = self.hook("pre-push", self.push_input() + self.push_input())
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.calls(), "context:audit\npush\n")

    def test_push_runs_shared_verify_entry_and_contract_failure_blocks(self):
        self.write("scripts/gates/gate-prepush.sh", 'echo "push" >> "$HOOK_TEST_LOG"\n')
        self.env["TEST_CONTEXT_STATUS"] = "1"
        result = self.hook("pre-push", self.push_input())
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), "context:audit\n")
        self.assertIn("scripts/verify", (REPO / ".githooks/pre-push").read_text())

    def test_hook_git_environment_never_touches_the_caller_repository(self):
        # Regression: with GIT_DIR exported by git, fetching shared-ci reinitialised
        # the caller repository as bare and added a shallow graft.
        source = Path(self.env["SHARED_CI"])
        self.env["SHARED_CI_URL"] = str(source)
        self.env["SHARED_CI"] = str(Path(self.temporary.name) / "fresh-shared-ci")
        subprocess.run(["git", "-C", str(source), "config", "uploadpack.allowAnySHA1InWant", "true"],
                       check=True, env=self.env)
        self.write("scripts/gates/gate-prepush.sh", 'echo "push" >> "$HOOK_TEST_LOG"\n')
        git_dir = self.git("rev-parse", "--absolute-git-dir").stdout.strip()
        env = dict(self.env, GIT_DIR=git_dir)
        result = subprocess.run(["bash", str(self.repo / ".githooks/pre-push")], cwd=self.repo,
                                input=self.push_input(), text=True, capture_output=True, env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git("config", "--bool", "core.bare").stdout.strip(), "false")
        self.assertFalse((Path(git_dir) / "shallow").exists())
        self.assertTrue((Path(self.env["SHARED_CI"]) / ".git").is_dir())

    def test_explicit_head_to_branch_is_supported(self):
        self.write("scripts/gates/gate-prepush.sh", 'echo "push" >> "$HOOK_TEST_LOG"\n')
        result = self.hook("pre-push", self.push_input(local_ref="HEAD"))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.calls(), "context:audit\npush\n")


if __name__ == "__main__":
    unittest.main()
