"""Exercise TestFlight schedule/manual admission and its gate without uploads."""
import ast
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("TestFlight workflow not found")
    ROOT = ROOT.parent
WORKFLOW = ROOT / ".github/workflows/testflight.yml"


def expression_value(expression, context):
    """只解释 workflow 使用的布尔、相等和属性表达式，保留短路与默认值语义。"""
    tree = ast.parse(expression.replace("&&", " and ").replace("||", " or "), mode="eval")

    def value(node):
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Name):
            return context[node.id]
        if isinstance(node, ast.Attribute):
            return value(node.value).get(node.attr)
        if isinstance(node, ast.Compare) and len(node.ops) == 1 and isinstance(node.ops[0], ast.Eq):
            return value(node.left) == value(node.comparators[0])
        if isinstance(node, ast.BoolOp):
            for child in node.values:
                result = value(child)
                if isinstance(node.op, ast.And) and not result:
                    return result
                if isinstance(node.op, ast.Or) and result:
                    return result
            return result
        raise AssertionError(f"Unsupported workflow expression: {ast.dump(node)}")

    return value(tree.body)


class TestFlightScheduleTests(unittest.TestCase):
    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.triggers = self.workflow.split("\non:\n", 1)[1].split("\nconcurrency:", 1)[0]
        self.release = self.workflow.split("\n  release:\n", 1)[1]
        self.guard, = re.findall(r"^    if: (.+)$", self.release, re.M)

    def context(self, event, ref="refs/heads/main", force=False, platform="macos", fork=False):
        return {
            "github": {
                "event_name": event, "ref": ref, "repository": "example/app",
                "event": {"pull_request": {
                    "head": {"repo": {"full_name": "example/fork"}}
                } if fork else None},
            },
            "inputs": {"force": force, "platform": platform},
            "null": None, "false": False,
        }

    def step(self, name):
        marker = "      - name: " + name + "\n"
        return self.release.split(marker, 1)[1].split("\n      - name:", 1)[0]

    def test_only_schedule_and_manual_dispatch_are_registered(self):
        events = re.findall(r"^  ([a-z_]+):", self.triggers, re.M)
        self.assertEqual(events, ["schedule", "workflow_dispatch"])
        self.assertEqual(re.findall(r"cron: '([^']+)'", self.triggers), ["17 5,17 * * *"])

    def test_actual_admission_accepts_schedule_and_manual_main(self):
        for event in ("schedule", "workflow_dispatch"):
            with self.subTest(event=event):
                self.assertTrue(expression_value(self.guard, self.context(event)))

    def test_actual_admission_rejects_other_events_refs_and_forks(self):
        for event in ("push", "workflow_run", "pull_request", "pull_request_target", "unknown"):
            with self.subTest(event=event):
                self.assertFalse(expression_value(self.guard, self.context(event)))
        for event in ("schedule", "workflow_dispatch"):
            for ref in ("refs/heads/example-feature", "refs/tags/example-tag"):
                with self.subTest(event=event, ref=ref):
                    self.assertFalse(expression_value(self.guard, self.context(event, ref=ref)))
            with self.subTest(event=event, fork=True):
                self.assertFalse(expression_value(self.guard, self.context(event, fork=True)))
        self.assertNotIn("needs: freshness", self.release)
        self.assertNotIn("  freshness:", self.workflow)

    def test_manual_force_and_no_new_commit_gate_are_preserved(self):
        force = self.triggers.split("      force:\n", 1)[1]
        self.assertIn("        type: boolean", force)
        self.assertIn("        default: false", force)
        self.assertIn('if [ "${FORCE:-false}" = "true" ] || [ "$LATEST" != "$RELEASED" ]; then', self.release)
        self.assertIn("steps.gate.outputs.release == 'true'", self.release)

    def test_release_still_uses_main_without_interrupting_uploads(self):
        checkout = self.step("Checkout VoxPocket")
        self.assertIn("          ref: main", checkout)
        self.assertIn("          fetch-depth: 0", checkout)
        self.assertIn("          fetch-tags: true", checkout)
        self.assertEqual(self.release.count("          ref: main"), 1)
        self.assertEqual(self.release.count('git rev-parse HEAD'), 1)
        self.assertIn("  group: testflight", self.workflow)
        self.assertRegex(self.workflow, r"(?m)^  cancel-in-progress: false(?: |$)")
        self.assertIn("    timeout-minutes: 60", self.release)
        self.assertIn("    runs-on: [self-hosted, macOS, ARM64]", self.release)
        self.assertIn("github.event.pull_request.head.repo.full_name == github.repository", self.guard)
        marker = self.step("Move last-released tag")
        self.assertIn("if: steps.gate.outputs.release == 'true'", marker)
        self.assertIn('SHA="${{ steps.gate.outputs.latest }}"', marker)
        self.assertIn('git tag -f testflight/macos-last-released "$SHA"', marker)
        self.assertLess(self.release.index("run: fastlane mac beta"), self.release.index("- name: Move last-released tag"))

    def test_only_macos_is_selectable_and_ios_lane_stays_disabled(self):
        platform = self.triggers.split("      platform:\n", 1)[1]
        self.assertIn("        type: choice", platform)
        self.assertEqual(re.findall(r"^          - (.+)$", platform, re.M), ["macos"])
        self.assertIn("        default: macos", platform)
        self.assertIn("        if: ${{ false }}", self.step("fastlane iOS beta"))
        self.assertIn("run: fastlane mac beta", self.step("fastlane macOS beta"))

    def run_gate(self, event, marker, force=False, platform="macos", omit_force=False):
        context = self.context(event, force=force, platform=platform)
        self.assertTrue(expression_value(self.guard, context))
        gate = self.step("Decide whether to release")
        script = textwrap.dedent(gate.split("        run: |\n", 1)[1])
        environment = {key: val for key, val in os.environ.items() if not key.startswith("GIT_")}
        environment.update(GIT_AUTHOR_NAME="Example", GIT_AUTHOR_EMAIL="example@example.invalid",
                           GIT_COMMITTER_NAME="Example", GIT_COMMITTER_EMAIL="example@example.invalid")
        for key in ("FORCE", "RELEASE_PLATFORM"):
            expression, = re.findall(r"^          " + key + r": \$\{\{ (.+) \}\}$", gate, re.M)
            result = expression_value(expression, context)
            environment[key] = str(result).lower() if isinstance(result, bool) else result
        if omit_force:
            environment.pop("FORCE", None)
        with tempfile.TemporaryDirectory(prefix="example-tf-gate-") as directory:
            def git(*args):
                return subprocess.run(["git", *args], cwd=directory, env=environment,
                                      check=True, capture_output=True, text=True, timeout=15).stdout.strip()

            git("init", "-q", "-b", "main")
            git("commit", "--allow-empty", "-m", "example baseline")
            if marker != "missing":
                git("tag", "testflight/macos-last-released")
            if marker == "older":
                git("commit", "--allow-empty", "-m", "example candidate")
            candidate = git("rev-parse", "HEAD")
            output = Path(directory) / "example-output"
            environment["GITHUB_OUTPUT"] = str(output)
            result = subprocess.run(["bash", "-c", script], cwd=directory, env=environment,
                                    capture_output=True, text=True, timeout=15)
            outputs = dict(line.split("=", 1) for line in output.read_text().splitlines()) if output.exists() else {}
        return result, outputs, candidate

    def test_actual_gate_skips_same_marker_without_force(self):
        for event in ("schedule", "workflow_dispatch"):
            with self.subTest(event=event):
                result, outputs, candidate = self.run_gate(event, "same")
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual({"latest": candidate, "release": "false"}, outputs)

    def test_actual_gate_releases_changed_or_first_candidate(self):
        for event in ("schedule", "workflow_dispatch"):
            for marker in ("older", "missing"):
                with self.subTest(event=event, marker=marker):
                    result, outputs, candidate = self.run_gate(event, marker)
                    self.assertEqual(0, result.returncode, result.stderr)
                    self.assertEqual({"latest": candidate, "release": "true"}, outputs)

    def test_actual_gate_honors_force_only_for_manual_dispatch(self):
        for event, expected in (("schedule", "false"), ("workflow_dispatch", "true")):
            with self.subTest(event=event):
                result, outputs, candidate = self.run_gate(event, "same", force=True)
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual({"latest": candidate, "release": expected}, outputs)

    def test_actual_gate_defaults_missing_force_to_false(self):
        for event in ("schedule", "workflow_dispatch"):
            for marker, expected in (("same", "false"), ("older", "true")):
                with self.subTest(event=event, marker=marker):
                    result, outputs, candidate = self.run_gate(event, marker, force=True, omit_force=True)
                    self.assertEqual(0, result.returncode, result.stderr)
                    self.assertEqual({"latest": candidate, "release": expected}, outputs)

    def test_actual_gate_defaults_schedule_to_macos_and_rejects_ios(self):
        result, outputs, candidate = self.run_gate("schedule", "older", platform=None)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual({"latest": candidate, "release": "true"}, outputs)
        result, outputs, _ = self.run_gate("workflow_dispatch", "older", force=True, platform="ios")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("only macos is allowed", result.stdout)
        self.assertEqual({}, outputs)


if __name__ == "__main__":
    unittest.main()
