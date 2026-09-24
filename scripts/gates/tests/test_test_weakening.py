"""check_test_weakening.py against disposable Git repositories."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check_test_weakening.py"
TEST_FILE = "Packages/Fixture/Tests/FixtureTests/FixtureTests.swift"
ORIGINAL = """import Testing

@Test func accepts() {
    #expect(valid("a"))
}

@Test func rejects() {
    #expect(!valid("../secret"))
    #expect(!valid("bad\\n"))
}
"""
TEMPLATE = """## Existing behaviour

x

## Removed or weakened tests or policy

<!-- Every removed/skipped/weakened test ... Write "none" if none. -->
{declaration}

## Test evidence

- Command: scripts/verify
"""


class TestWeakeningGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="weakening ")
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.env = {key: value for key, value in os.environ.items()
                    if key not in ("PR_BODY", "VERIFY_BASE", "GITHUB_EVENT_PATH", "GITHUB_EVENT_NAME", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Guard Test")
        self.git("config", "user.email", "guard@example.invalid")
        self.write(TEST_FILE, ORIGINAL)
        self.write(".github/CODEOWNERS", "/docs/test-weakening/  @owner\n")
        self.commit("seed")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.git("checkout", "-q", "-b", "task")

    def git(self, *args):
        return subprocess.run(["git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *args],
                              cwd=self.repo, env=self.env, check=True, capture_output=True, text=True)

    def write(self, relative, content):
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def run_guard(self, **env):
        return subprocess.run([sys.executable, str(SCRIPT)], cwd=self.repo, env=dict(self.env, **env),
                              capture_output=True, text=True)

    def remove_assertions(self, message="test: drop assertion"):
        self.write(TEST_FILE, ORIGINAL.replace('    #expect(!valid("../secret"))\n', "")
                                        .replace('    #expect(!valid("bad\\n"))\n', ""))
        self.commit(message)

    def declare(self, paths=(TEST_FILE,), name="drop-rejects.md"):
        self.write(f"docs/test-weakening/{name}", "Reason: validator removed in #99.\n"
                   + "".join(f"- `{path}`\n" for path in paths))
        self.commit("docs: declare test weakening")

    def test_added_assertions_pass(self):
        self.write(TEST_FILE, ORIGINAL + '\n@Test func more() {\n    #expect(valid("b"))\n}\n')
        self.commit("test: more")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed", result.stdout)

    def test_removed_assertion_blocks_locally_without_trailer(self):
        self.remove_assertions()
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr.count("removed or changed"), 2)

    def test_codeowned_declaration_file_allows_removal(self):
        self.remove_assertions()
        self.declare()
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Owner code-owner review required", result.stdout)

    def test_commit_trailer_alone_is_not_a_declaration(self):
        self.remove_assertions("test: drop assertion\n\nTest-Weakening: approved by Owner")
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docs/test-weakening", result.stderr)

    def test_declaration_must_name_every_affected_test_file(self):
        self.remove_assertions()
        self.declare(paths=("Packages/Other/Tests/OtherTests.swift",))
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(TEST_FILE, result.stderr)

    def test_declaration_without_codeowners_entry_fails_closed(self):
        self.remove_assertions()
        self.write(".github/CODEOWNERS", "/docs/architecture/  @owner\n")
        self.commit("drop owner entry")
        self.declare()
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CODEOWNERS does not own", result.stderr)

    def test_readme_is_not_a_declaration(self):
        self.remove_assertions()
        self.write("docs/test-weakening/README.md", f"- `{TEST_FILE}`\n")
        self.commit("docs")
        self.assertNotEqual(self.run_guard().returncode, 0)

    def test_removal_offset_by_unrelated_addition_still_blocks(self):
        # codex-review #65: repo-wide totals let one removal hide behind an unrelated addition.
        self.write(TEST_FILE, ORIGINAL.replace('    #expect(!valid("../secret"))\n', ""))
        self.write("Packages/Fixture/Tests/FixtureTests/OtherTests.swift",
                   'import Testing\n\n@Test func unrelated() {\n    #expect(valid("zzz"))\n}\n')
        self.commit("test: swap a check")
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('valid("../secret")', result.stderr)

    def test_weakened_assertion_in_place_blocks(self):
        self.write(TEST_FILE, ORIGINAL.replace('#expect(!valid("../secret"))', "#expect(true)"))
        self.commit("test: weaken")
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("removed or changed", result.stderr)

    def test_pr_body_none_blocks_and_declaration_passes(self):
        self.remove_assertions()
        blocked = self.run_guard(PR_BODY=TEMPLATE.format(declaration="none"))
        self.assertNotEqual(blocked.returncode, 0)
        self.assertIn("PR body", blocked.stderr)
        self.assertNotEqual(self.run_guard(PR_BODY="no template at all").returncode, 0)
        body_only = self.run_guard(PR_BODY=TEMPLATE.format(declaration="- Removed two rejects() cases"))
        self.assertNotEqual(body_only.returncode, 0)  # the PR body alone is not Owner-gated
        self.declare()
        declared = self.run_guard(PR_BODY=TEMPLATE.format(
            declaration="- Removed two rejects() cases, see docs/test-weakening/drop-rejects.md"))
        self.assertEqual(declared.returncode, 0, declared.stderr)
        self.assertNotEqual(self.run_guard(PR_BODY=TEMPLATE.format(declaration="none")).returncode, 0)

    def test_actions_event_payload_is_read_and_push_events_skip(self):
        self.remove_assertions()
        event = self.repo.parent / "event.json"
        event.write_text('{"pull_request": {"body": "## Removed or weakened tests or policy\\n\\nnone\\n"}}')
        blocked = self.run_guard(GITHUB_EVENT_NAME="pull_request", GITHUB_EVENT_PATH=str(event))
        self.assertNotEqual(blocked.returncode, 0)
        self.assertIn("PR body", blocked.stderr)
        skipped = self.run_guard(GITHUB_EVENT_NAME="push", GITHUB_EVENT_PATH=str(event))
        self.assertEqual(skipped.returncode, 0)
        self.assertIn("skipped", skipped.stdout)

    def test_deleted_test_file_blocks(self):
        (self.repo / TEST_FILE).unlink()
        self.commit("test: delete")
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("test file deleted", result.stderr)

    def test_added_skip_marker_blocks(self):
        self.write(TEST_FILE, ORIGINAL.replace("@Test func rejects", "@Test(." + 'disabled("slow")) func rejects'))
        self.commit("test: skip")
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("skip marker", result.stderr)

    def test_moving_assertions_between_test_files_passes(self):
        moved = 'import Testing\n\n@Test func rejects() {\n    #expect(!valid("../secret"))\n    #expect(!valid("bad\\n"))\n}\n'
        self.write(TEST_FILE, ORIGINAL.split("@Test func rejects")[0])
        self.write("Packages/Fixture/Tests/FixtureTests/RejectTests.swift", moved)
        self.commit("test: split file")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_non_test_sources_are_ignored(self):
        self.write("Packages/Fixture/Sources/Fixture/Fixture.swift", "func f() { assert(true) }\n")
        self.commit("feat")
        self.write("Packages/Fixture/Sources/Fixture/Fixture.swift", "func f() {}\n")
        self.commit("refactor")
        self.assertEqual(self.run_guard().returncode, 0)

    def test_missing_base_fails_closed(self):
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        result = self.run_guard()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("merge base", result.stderr)


if __name__ == "__main__":
    unittest.main()
