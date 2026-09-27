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
        environment = dict(self.env, PR_BODY=TEMPLATE.format(declaration="none"))
        environment.update(env)
        if environment["PR_BODY"] is None:
            del environment["PR_BODY"]
        return subprocess.run([sys.executable, str(SCRIPT)], cwd=self.repo, env=environment,
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

    def seed_multiline(self, statement, path=TEST_FILE):
        self.write(path, statement)
        self.commit("test: multiline baseline")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")

    def test_multiline_expect_argument_weakened_blocks(self):
        statement = "#expect(\n    a == b\n)\n"
        self.seed_multiline(statement)
        self.write(TEST_FILE, statement.replace("a == b", "true"))
        self.commit("test: weaken multiline expectation")
        self.assert_blocked("assertion removed or changed: #expect( a == b )",
                            PR_BODY=TEMPLATE.format(declaration="none"))

    def test_multiline_xctassert_argument_changed_blocks(self):
        statement = "XCTAssertEqual(\n    actual,\n    expected\n)\n"
        self.seed_multiline(statement)
        self.write(TEST_FILE, statement.replace("expected", "actual"))
        self.commit("test: weaken multiline XCTest assertion")
        self.assert_blocked("assertion removed or changed: XCTAssertEqual( actual, expected )",
                            PR_BODY=TEMPLATE.format(declaration="none"))

    def test_multiline_python_assert_argument_changed_blocks(self):
        path = "tests/test_fixture.py"
        statement = "self.assertEqual(\n    actual,\n    expected\n)\n"
        self.seed_multiline(statement, path)
        self.write(path, statement.replace("expected", "actual"))
        self.commit("test: weaken multiline Python assertion")
        result = self.assert_blocked("assertion removed or changed: self.assertEqual( actual, expected )",
                                     PR_BODY=TEMPLATE.format(declaration="none"))
        self.assertIn(path, result.stderr)

    def test_multiline_assertion_moved_verbatim_passes(self):
        statement = "#expect(\n    a == b\n)\n"
        self.seed_multiline(ORIGINAL + statement)
        self.write(TEST_FILE, ORIGINAL)
        self.write(OTHER_FILE, statement)
        self.commit("test: move multiline assertion")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed", result.stdout)

    def test_reindented_multiline_assertion_passes(self):
        statement = "#expect(\n    a == b\n)\n"
        self.seed_multiline(statement)
        self.write(TEST_FILE, "\n".join("\t  " + line for line in statement.splitlines()) + "\n")
        self.commit("test: reindent multiline assertion")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed", result.stdout)

    def test_multiline_unrelated_addition_does_not_offset_loss(self):
        statement = "#expect(\n    a == b\n)\n"
        self.seed_multiline(ORIGINAL + statement)
        self.write(TEST_FILE, ORIGINAL)
        self.write(OTHER_FILE, statement.replace("a == b", "c == d"))
        self.commit("test: replace multiline assertion with unrelated check")
        result = self.assert_blocked("assertion removed or changed: #expect( a == b )")
        self.assertIn(TEST_FILE, result.stderr)

    def test_duplicate_assertion_removal_is_not_offset_by_remaining_copy(self):
        statement = "#expect(\n    a == b\n)\n"
        self.seed_multiline(statement * 3)
        self.write(TEST_FILE, statement)
        self.commit("test: remove duplicate assertions")
        result = self.assert_blocked("assertion removed or changed")
        self.assertEqual(result.stderr.count("assertion removed or changed"), 2)

    def test_python_multiline_bracket_argument_changed_blocks(self):
        path = "tests/test_fixture.py"
        statement = "assert values == [\n    1,\n    2,\n]\n"
        self.seed_multiline(statement, path)
        self.write(path, statement.replace("2,", "3,"))
        self.commit("test: change bracketed assertion")
        self.assert_blocked("assertion removed or changed: assert values == [ 1, 2, ]")

    def test_simple_string_delimiters_do_not_extend_assertions(self):
        path = "tests/test_fixture.py"
        statement = 'self.assertEqual(\n    actual,\n    "(\\\"[",\n)\n'
        statement += "self.assertEqual(\n    actual,\n    '[',\n)\n"
        self.seed_multiline(statement + "metadata = 1\n", path)
        self.write(path, statement + "metadata = 2\n")
        self.commit("test: change code after assertions containing string delimiters")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed", result.stdout)

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

    # ---- PR body (G6) ----------------------------------------------------------

    def test_pr_body_none_blocks_undeclared_loss(self):
        self.remove_assertions()
        self.assert_blocked("does not name", PR_BODY=TEMPLATE.format(declaration="none"))
        self.assert_blocked("does not name", PR_BODY="no template at all")
        self.assert_blocked("does not name", PR_BODY="")

    def test_pr_body_naming_file_is_sufficient(self):
        self.remove_assertions()
        named = self.run_guard(PR_BODY=TEMPLATE.format(declaration=f"- `{TEST_FILE}`: validator removed"))
        self.assertEqual(named.returncode, 0, named.stderr)
        self.assertIn("declared", named.stdout)

    def test_pr_body_must_name_each_affected_file(self):
        self.write(OTHER_FILE, ORIGINAL)
        self.commit("test: second file baseline")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.remove_assertions()
        self.write(OTHER_FILE, ORIGINAL.replace('#expect(valid("a"))', '#expect(true)'))
        self.commit("test: weaken second file")
        self.assert_blocked(f"does not name: {OTHER_FILE}",
                            PR_BODY=TEMPLATE.format(declaration=f"- {TEST_FILE}"))
        result = self.run_guard(PR_BODY=TEMPLATE.format(declaration=f"- {TEST_FILE}\n- {OTHER_FILE}"))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_file_names_in_comments_or_other_sections_do_not_declare_loss(self):
        self.remove_assertions()
        body = TEMPLATE.format(declaration=f"<!-- {TEST_FILE} -->\nnone")
        self.assert_blocked("does not name", PR_BODY=body + f"\n- {TEST_FILE}\n")

    def test_no_pr_body_passes_with_notice(self):
        self.remove_assertions()
        result = self.run_guard(PR_BODY=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("Notice:", result.stdout)
        self.assertIn(TEST_FILE, result.stdout)
        self.assertIn("assertion removed or changed", result.stdout)
        self.assertIn('PR body section "Removed or weakened tests or policy"', result.stdout)

    def test_actions_event_payload_body_is_checked(self):
        self.remove_assertions()
        event = Path(self.temporary.name) / "event.json"
        event.write_text(json.dumps({"pull_request": {"body": TEMPLATE.format(declaration="none")}}))
        self.assert_blocked("does not name", PR_BODY=None,
                            GITHUB_EVENT_NAME="pull_request", GITHUB_EVENT_PATH=str(event))
        body = TEMPLATE.format(declaration=TEST_FILE)
        event.write_text(json.dumps({"pull_request": {"body": body}}))
        result = self.run_guard(PR_BODY=None, GITHUB_EVENT_NAME="pull_request", GITHUB_EVENT_PATH=str(event))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("declared", result.stdout)
        self.assert_blocked("does not name", GITHUB_EVENT_PATH=str(event))

    def test_null_pull_request_body_needs_declaration(self):
        self.remove_assertions()
        event = Path(self.temporary.name) / "event.json"
        event.write_text(json.dumps({"pull_request": {"body": None}}))
        self.assert_blocked("does not name", PR_BODY=None, GITHUB_EVENT_PATH=str(event))

    def test_push_event_without_pr_body_passes_with_notice(self):
        self.remove_assertions()
        event = Path(self.temporary.name) / "event.json"
        event.write_text(json.dumps({"ref": "refs/heads/main"}))
        result = self.run_guard(PR_BODY=None, GITHUB_EVENT_NAME="push", GITHUB_EVENT_PATH=str(event))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Notice:", result.stdout)
        self.assertIn(TEST_FILE, result.stdout)
        self.assert_blocked("does not name", GITHUB_EVENT_NAME="push", GITHUB_EVENT_PATH=str(event))

    def test_missing_base_fails_closed(self):
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        self.assert_blocked("merge base")


if __name__ == "__main__":
    unittest.main()
