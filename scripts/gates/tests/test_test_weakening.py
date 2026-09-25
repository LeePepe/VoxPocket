"""check_test_weakening.py against disposable Git repositories."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check_test_weakening.py"
TEST_FILE = "Packages/Fixture/Tests/FixtureTests/FixtureTests.swift"
OTHER_FILE = "Packages/Fixture/Tests/FixtureTests/OtherTests.swift"
LEDGER = ".github/test-weakening.md"
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
# Built from pieces so this fixture file does not itself add a skip marker.
DISABLED = "." + 'disabled("slow")'
ENABLED_IF_FALSE = "." + "enabled(if: false)"


class TestWeakeningGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="weakening ")
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name) / "repo"
        self.repo.mkdir()
        self.env = {key: value for key, value in os.environ.items()
                    if key not in ("PR_BODY", "VERIFY_BASE", "GITHUB_EVENT_PATH", "GITHUB_EVENT_NAME",
                                   "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Guard Test")
        self.git("config", "user.email", "guard@example.invalid")
        self.write(TEST_FILE, ORIGINAL)
        self.write(".github/CODEOWNERS", "/.github/  @owner\n")
        self.write(LEDGER, "# Test weakening ledger\n\n## Entries\n")
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

    def assert_blocked(self, needle, **env):
        result = self.run_guard(**env)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(needle, result.stderr)
        return result

    def remove_assertions(self, message="test: drop assertion"):
        self.write(TEST_FILE, ORIGINAL.replace('    #expect(!valid("../secret"))\n', "")
                                        .replace('    #expect(!valid("bad\\n"))\n', ""))
        self.commit(message)

    def declare(self, *paths, line="- {path}: validator removed in #99 (approved: @owner)\n"):
        text = (self.repo / LEDGER).read_text()
        self.write(LEDGER, text + "".join(line.format(path=path) for path in (paths or (TEST_FILE,))))
        self.commit("docs: declare test weakening")

    # ---- losses ----------------------------------------------------------------

    def test_added_assertions_pass(self):
        self.write(TEST_FILE, ORIGINAL + '\n@Test func more() {\n    #expect(valid("b"))\n}\n')
        self.commit("test: more")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed", result.stdout)

    def test_removed_assertions_block_each_one(self):
        self.remove_assertions()
        result = self.assert_blocked("assertion removed or changed")
        self.assertEqual(result.stderr.count("assertion removed or changed"), 2)

    def test_removal_offset_by_unrelated_addition_still_blocks(self):
        # codex-review #65: repo-wide totals let one removal hide behind an unrelated addition.
        self.write(TEST_FILE, ORIGINAL.replace('    #expect(!valid("../secret"))\n', ""))
        self.write(OTHER_FILE, 'import Testing\n\n@Test func unrelated() {\n    #expect(valid("zzz"))\n}\n')
        self.commit("test: swap a check")
        self.assert_blocked('valid("../secret")')

    def test_weakened_assertion_in_place_blocks(self):
        self.write(TEST_FILE, ORIGINAL.replace('#expect(!valid("../secret"))', "#expect(true)"))
        self.commit("test: weaken")
        self.assert_blocked("assertion removed or changed")

    def test_removed_test_function_blocks(self):
        self.write(TEST_FILE, ORIGINAL.replace('@Test func accepts() {\n    #expect(valid("a"))\n}\n', ""))
        self.write(OTHER_FILE, 'import Testing\n\n@Test func replacement() {\n    #expect(valid("a"))\n}\n')
        self.commit("test: rename away")
        self.assert_blocked("test removed: accepts")

    def test_retagging_a_test_declaration_is_not_a_loss(self):
        self.write(TEST_FILE, ORIGINAL.replace("@Test func accepts", '@Test(.tags(.fast)) func accepts'))
        self.commit("test: tag")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_moving_tests_between_files_passes(self):
        moved = 'import Testing\n\n@Test func rejects() {\n    #expect(!valid("../secret"))\n    #expect(!valid("bad\\n"))\n}\n'
        self.write(TEST_FILE, ORIGINAL.split("@Test func rejects")[0])
        self.write(OTHER_FILE, moved)
        self.commit("test: split file")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_deleted_test_file_blocks(self):
        (self.repo / TEST_FILE).unlink()
        self.commit("test: delete")
        result = self.assert_blocked("test file deleted")
        self.assertIn("test removed: rejects", result.stderr)

    def test_added_skip_marker_blocks(self):
        self.write(TEST_FILE, ORIGINAL.replace("@Test func rejects", f"@Test({DISABLED}) func rejects"))
        self.commit("test: skip")
        self.assert_blocked("skip marker")

    def test_multiline_enabled_if_false_trait_blocks(self):
        # codex-review #65 round 2: a multiline @Test trait that disables the test (ENABLED_IF_FALSE).
        self.write(TEST_FILE, ORIGINAL.replace("@Test func rejects()",
                                               f"@Test(\n    {ENABLED_IF_FALSE}\n)\nfunc rejects()"))
        self.commit("test: disable")
        self.assert_blocked("skip marker")

    def test_removed_multiline_test_declaration_blocks(self):
        # codex-review #65 round 3: @Test(...) and func on separate lines, body without assertions.
        base = ORIGINAL + '\n@Test(\n    "smoke"\n)\nfunc smoke() {\n    _ = valid("x")\n}\n'
        self.write(TEST_FILE, base)
        self.commit("test: add smoke")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.write(TEST_FILE, ORIGINAL)
        self.commit("test: drop smoke")
        self.assert_blocked("test removed: smoke")

    def test_non_test_sources_are_ignored(self):
        self.write("Packages/Fixture/Sources/Fixture/Fixture.swift", "func f() { assert(true) }\n")
        self.commit("feat")
        self.write("Packages/Fixture/Sources/Fixture/Fixture.swift", "func f() {}\n")
        self.commit("refactor")
        self.assertEqual(self.run_guard().returncode, 0)

    # ---- Owner-gated ledger ----------------------------------------------------

    def test_ledger_line_allows_removal(self):
        self.remove_assertions()
        self.declare()
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Owner code-owner review required", result.stdout)

    def test_commit_trailer_or_pr_body_alone_is_not_a_declaration(self):
        self.remove_assertions("test: drop\n\nTest-Weakening: approved by Owner")
        self.assert_blocked(f"no line added to {LEDGER}")
        self.assert_blocked(f"no line added to {LEDGER}", PR_BODY=TEMPLATE.format(declaration=f"- {TEST_FILE}"))

    def test_ledger_must_cover_every_affected_file(self):
        self.remove_assertions()
        self.declare("Packages/Other/Tests/OtherTests.swift")
        self.assert_blocked(TEST_FILE)

    def test_ledger_line_needs_reason_and_approver(self):
        self.remove_assertions()
        self.declare(line="- {path}: because\n")
        self.assert_blocked(f"no line added to {LEDGER}")

    def test_preexisting_ledger_line_does_not_cover_a_new_loss(self):
        self.write(LEDGER, (self.repo / LEDGER).read_text() + f"- {TEST_FILE}: old (approved: @owner)\n")
        self.commit("old declaration")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.remove_assertions()
        self.assert_blocked(f"no line added to {LEDGER}")

    def test_ledger_not_codeowned_fails_closed(self):
        self.remove_assertions()
        self.write(".github/CODEOWNERS", "/docs/  @owner\n")
        self.commit("drop owner entry")
        self.declare()
        self.assert_blocked("does not cover")

    def test_later_codeowners_rule_without_owner_fails_closed(self):
        self.remove_assertions()
        self.write(".github/CODEOWNERS", "/.github/  @owner\n/.github/test-weakening.md\n")
        self.commit("unown ledger")
        self.declare()
        self.assert_blocked("does not cover")

    # ---- PR body (G6) ----------------------------------------------------------

    def test_pr_body_must_name_each_affected_file(self):
        self.remove_assertions()
        self.declare()
        self.assert_blocked("does not name", PR_BODY=TEMPLATE.format(declaration="none"))
        self.assert_blocked("does not name", PR_BODY="no template at all")
        named = self.run_guard(PR_BODY=TEMPLATE.format(declaration=f"- `{TEST_FILE}`: validator removed"))
        self.assertEqual(named.returncode, 0, named.stderr)

    def test_actions_event_payload_is_read_and_push_events_skip(self):
        self.remove_assertions()
        self.declare()
        event = Path(self.temporary.name) / "event.json"
        event.write_text(json.dumps({"pull_request": {"body": TEMPLATE.format(declaration="none")}}))
        self.assert_blocked("does not name", GITHUB_EVENT_NAME="pull_request", GITHUB_EVENT_PATH=str(event))
        skipped = self.run_guard(GITHUB_EVENT_NAME="push", GITHUB_EVENT_PATH=str(event))
        self.assertEqual(skipped.returncode, 0)
        self.assertIn("skipped", skipped.stdout)

    def test_missing_base_fails_closed(self):
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        self.assert_blocked("merge base")


if __name__ == "__main__":
    unittest.main()
