"""Published review caller/context regressions; no model, credentials or network.

The launchers and renderer are the unmodified, pinned shared-ci implementation.
Only network Git fetch, GitHub comments, the model CLI and Raven routing are stubs.
Synthetic base/head commits model the post-merge trusted-base checkout.
"""

from pathlib import Path
import fnmatch
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SHARED = ROOT / ".shared-ci"
POLICY = "docs/repository-policy.md"
CALLERS = {"codex": ("codex-review-target.yml", "codex-review-target"),
           "kimi": ("kimi-review.yml", "kimi-review")}
PROTECTED = (POLICY, "docs/local-gates.md", "docs/plans/README.md", "docs/testflight-release.md")
GIT = shutil.which("git")


def command(*args, cwd=ROOT, env=None):
    return subprocess.run(args, cwd=cwd, env=env, check=True, capture_output=True,
                          text=True, timeout=30).stdout.strip()


def yaml(path):
    spec = importlib.util.spec_from_file_location("review_test_yaml", SHARED / "scripts/context/_frontmatter.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.parse(path.read_text())


def owners(path):
    """Match the anchored directory/file and glob forms used by this CODEOWNERS."""
    result = []
    for line in (ROOT / ".github/CODEOWNERS").read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        pattern, *assigned = line.split()
        pattern = pattern.lstrip("/")
        if (pattern.endswith("/") and path.startswith(pattern)) or fnmatch.fnmatchcase(path, pattern):
            result = assigned
    return result


class ReviewContextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pin = re.search(r"shared-ci@([0-9a-f]{40})/ai/agent-protocol", (ROOT / "AGENTS.md").read_text())[1]
        if not SHARED.is_dir():
            raise AssertionError("Run scripts/verify first to populate the exact pinned shared-ci cache")
        assert command(GIT, "-C", str(SHARED), "rev-parse", "HEAD") == cls.pin
        command(GIT, "-C", str(SHARED), "diff", "--exit-code", "HEAD", "--", "scripts/review", "scripts/context", ".github/workflows")
        cls.policy = (ROOT / POLICY).read_text()

    def test_actual_callers_use_existing_published_rules_file_input(self):
        for tool, (filename, job) in CALLERS.items():
            with self.subTest(tool=tool):
                caller = yaml(ROOT / ".github/workflows" / filename)
                self.assertIn("pull_request_target", caller["on"])
                config = caller["jobs"][job]
                self.assertEqual(config["uses"], f"LeePepe/shared-ci/.github/workflows/{tool}-review.yml@{self.pin}")
                self.assertEqual(config["with"]["rules-file"], POLICY)
                provider = yaml(SHARED / ".github/workflows" / f"{tool}-review.yml")
                self.assertIn("rules-file", provider["on"]["workflow_call"]["inputs"])
                steps = provider["jobs"][f"{tool}-review"]["steps"]
                self.assertEqual(steps[0]["with"]["ref"], "${{ github.event.pull_request.base.sha }}")
                self.assertEqual(steps[-1]["env"]["REVIEW_RULES_FILE"], "${{ inputs.rules-file }}")
                self.assertIn(f".shared-ci/scripts/review/{tool}-review.sh", steps[-1]["run"])
        codex = yaml(ROOT / ".github/workflows/codex-review-target.yml")["jobs"]["codex-review-target"]
        self.assertEqual(codex["with"]["codex-launcher"], "python3 scripts/ci/review-raven.py")

    def test_policy_is_complete_under_limit_and_destinations_are_protected(self):
        self.assertLess(len(self.policy.encode()), 24000)
        self.assertTrue(owners("AGENTS.md"))
        for path in PROTECTED:
            with self.subTest(path=path):
                self.assertEqual(command(GIT, "ls-files", "--", path), path)
                self.assertEqual(owners(path), owners("AGENTS.md"))
        for path in ("Packages/VoxDomain/Tests/CoreModelsTests/TextRangeTests.swift",
                     "VoxPocket/VoxPocketTests/OrdinaryTests.swift"):
            self.assertEqual(owners(path), [], path)
        regression_paths = set(command(GIT, "ls-files", "--", "scripts/gates/tests/",
                                       "scripts/ci/tests/").splitlines())
        self.assertTrue({"scripts/gates/tests/test_local_hooks.py",
                         "scripts/gates/tests/test_review_context.py",
                         "scripts/ci/tests/test_review_prompt.py",
                         "scripts/ci/tests/test_review_raven.py"}.issubset(regression_paths))
        for path in sorted(regression_paths):
            with self.subTest(regression=path):
                self.assertEqual(owners(path), [], path)
        for path in ("scripts/verify", "scripts/gates/check_private_config.py",
                     "scripts/gates/check_frontmatter.py", "scripts/gates/gate-precommit.sh",
                     "scripts/gates/gate-prepush.sh", "scripts/ci/kimi-review.contract.test.sh",
                     "scripts/ci/review-raven.py", "scripts/ci/fetch-external-deps.sh",
                     ".github/workflows/codex-review-target.yml", ".github/workflows/kimi-review.yml",
                     ".githooks/pre-commit", ".githooks/pre-push",
                     "schemas/example.schema.json", "policy/example.json"):
            with self.subTest(implementation=path):
                self.assertEqual(owners(path), owners("AGENTS.md"), path)

    def test_test_execution_permission_retains_independent_ai_and_policy_review(self):
        for phrase in ("ordinary in-scope test-code edits or deletions require no\nOwner approval",
                       "ordinary in-scope test maintenance proceeds without an Owner\n   execution hold",
                       "Every implementation plan, spec or plan change still follows independent AI Plan-Review",
                       "The reviewer re-reviews without waiting to be asked",
                       "Policy, gate, schema, ruleset, permission",
                       "other protected changes still need Owner review"):
            self.assertIn(phrase, self.policy)
        self.assertNotIn("Only then present the plan to the Owner", (ROOT / "docs/plans/README.md").read_text())
        self.assertIn("repository-policy.md#review-and-execution-boundaries", (ROOT / "docs/plans/README.md").read_text())
        self.assertNotIn("policy-enforcing tests", " ".join(self.policy.split()))

    def fixture(self, temporary):
        fixture = Path(temporary)
        repo = fixture / "base-checkout"
        repo.mkdir()
        bin_dir = fixture / "bin"
        bin_dir.mkdir()
        empty_template = fixture / "empty-template"
        empty_template.mkdir()
        env = {"PATH": f"{bin_dir}:{Path(sys.executable).parent}:/usr/bin:/bin",
               "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
               "GIT_TEMPLATE_DIR": str(empty_template), "LC_ALL": "C",
               "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
               "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"}
        command(GIT, "init", "-q", "-b", "main", cwd=repo, env=env)
        self.write(repo / POLICY, self.policy)
        self.write(repo / "AGENTS.md", "# INDEX_ONLY_FALLBACK_CANARY\n")
        for path in [ROOT / "docs/architecture/tech-context.md", *ROOT.glob("Packages/*/tech-context.md"), ROOT / "VoxPocket/tech-context.md"]:
            self.write(repo / path.relative_to(ROOT), path.read_text())
        command(GIT, "add", ".", cwd=repo, env=env)
        command(GIT, "commit", "-qm", "synthetic trusted base", cwd=repo, env=env)
        base = command(GIT, "rev-parse", "HEAD", cwd=repo, env=env)
        self.write(repo / POLICY, "# HEAD_POLICY_CANARY\n")
        self.write(repo / "head-only.sh", "#!/bin/sh\ntouch head-code-ran\n")
        command(GIT, "add", ".", cwd=repo, env=env)
        command(GIT, "commit", "-qm", "synthetic untrusted head", cwd=repo, env=env)
        head = command(GIT, "rev-parse", "HEAD", cwd=repo, env=env)
        command(GIT, "switch", "--detach", base, cwd=repo, env=env)
        env.update(PR_NUMBER="1", BASE_SHA=base, HEAD_SHA=head, BASE_REPO="example-owner/example-repo",
                   SHARED_CI_DIR=str(SHARED), REVIEW_RULES_FILE=POLICY,
                   CODEX_REVIEW_HOME=str(fixture / "review-home"),
                   CAPTURE_DIR=str(fixture), REAL_GIT=GIT)
        self.install_capture_tools(bin_dir)
        return repo, env

    @staticmethod
    def write(path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def install_capture_tools(self, bin_dir):
        # A closed dispatch: no stub can invoke real gh/model binaries or fetch a remote.
        source = r'''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
out = pathlib.Path(os.environ["CAPTURE_DIR"])
with (out / "calls.jsonl").open("a") as log:
    log.write(json.dumps([name, *args]) + "\n")
if name == "git":
    if args[0] == "fetch":
        assert args == ["fetch", "--no-tags", "--depth=200", "origin", os.environ["BASE_SHA"], os.environ["HEAD_SHA"]]
        sys.exit(0)
    assert args[0] in {"cat-file", "diff", "rev-parse", "ls-files", "check-ignore"}, args
    os.execv(os.environ["REAL_GIT"], [os.environ["REAL_GIT"], *args])
elif name == "gh":
    assert args[0] == "api", args
    assert args[1].startswith("repos/example-owner/example-repo/") or args[1:3] == ["-X", "POST"], args
    print("null")
elif name == "offline-router":
    os.execv(args[0], [args[0], "exec", *args[1:]])
elif name in {"codex", "kimi"}:
    prompt = args[-1] if name == "codex" else args[args.index("-p") + 1]
    (out / (name + "-prompt.txt")).write_text(prompt)
    verdict = {"verdict": "pass", "summary": "synthetic capture, not a model review", "blockers": [], "notes": []}
    if name == "codex":
        assert args[0] == "exec"
        pathlib.Path(args[args.index("-o") + 1]).write_text(json.dumps(verdict))
    else:
        print(json.dumps({"role": "assistant", "content": json.dumps(verdict)}))
else:
    raise AssertionError(name)
'''
        for name in ("git", "gh", "codex", "kimi", "offline-router"):
            path = bin_dir / name
            path.write_text(f"#!{sys.executable}\n" + source)
            path.chmod(0o755)

    def capture(self, tool):
        with tempfile.TemporaryDirectory(prefix="review-context-") as temporary:
            repo, env = self.fixture(temporary)
            fixture = Path(temporary)
            env.update(CODEX_BIN=str(fixture / "bin/codex"),
                       CODEX_LAUNCHER=str(fixture / "bin/offline-router"),
                       KIMI_BIN=str(fixture / "bin/kimi"))
            # Exercise the actual configured input, not an independently chosen test path.
            filename, job = CALLERS[tool]
            env["REVIEW_RULES_FILE"] = yaml(ROOT / ".github/workflows" / filename)["jobs"][job]["with"]["rules-file"]
            self.assertEqual(env["REVIEW_RULES_FILE"], POLICY)
            result = command("bash", str(SHARED / f"scripts/review/{tool}-review.sh"), cwd=repo, env=env)
            prompt = (fixture / f"{tool}-prompt.txt").read_text()
            rules = prompt.split("## Trusted repository rules\n\n", 1)[1].split("\n\n## Trusted architecture facts", 1)[0]
            self.assertEqual(rules, self.policy.rstrip("\n"))
            self.assertNotIn("HEAD_POLICY_CANARY", rules)
            self.assertNotIn("INDEX_ONLY_FALLBACK_CANARY", rules)
            diff = prompt.split("======== UNTRUSTED DATA BELOW", 1)[1]
            self.assertIn("HEAD_POLICY_CANARY", diff)
            self.assertIn("head-only.sh", diff)
            self.assertFalse((repo / "head-code-ran").exists())
            self.assertEqual(command(GIT, "rev-parse", "HEAD", cwd=repo, env=env), env["BASE_SHA"])
            calls = [json.loads(line) for line in (fixture / "calls.jsonl").read_text().splitlines()]
            self.assertTrue(any(call[:2] == ["git", "fetch"] for call in calls))
            self.assertTrue(any(call[0] == "gh" for call in calls))
            self.assertTrue(any(call[0] == tool for call in calls))
            self.assertNotIn("unavailable", result)
            self.save_evidence(tool, prompt, rules, result, calls)

    def save_evidence(self, tool, prompt, rules, result, calls):
        destination = os.environ.get("REVIEW_CONTEXT_EVIDENCE_DIR")
        if not destination:
            return
        target = Path(destination)
        target.mkdir(parents=True, exist_ok=True)
        (target / f"{tool}-prompt.txt").write_text(prompt)
        metadata = {"tool": tool, "provider_pin": self.pin,
                    "policy_bytes": len(self.policy.encode()),
                    "rules_sha256": hashlib.sha256(rules.encode()).hexdigest(),
                    "whole_policy_received": True, "base_rules_head_diff_separate": True,
                    "no_model_or_network": True, "launcher_output": result,
                    "intercepted_commands": [call[:2] for call in calls]}
        (target / f"{tool}-evidence.json").write_text(json.dumps(metadata, indent=2) + "\n")

    def test_codex_receives_complete_policy_from_trusted_base(self):
        self.capture("codex")

    def test_kimi_receives_complete_policy_from_trusted_base(self):
        self.capture("kimi")


if __name__ == "__main__":
    unittest.main()
