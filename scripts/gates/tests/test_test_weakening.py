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
ENABLED_IF_TRUE = "." + "enabled(if: true)"
ENABLED_IF_RUNTIME = "." + 'enabled(if: ProcessInfo.processInfo.environment["CI"] != nil)'
XCT_SKIP = "XCT" + "Skip"
PYTHON_SKIP = "self." + "skipTest"
PYTEST_SKIP = "pytest." + "skip"
PYTEST_MARK_SKIP = "pytest.mark." + "skip"


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

    def test_multiline_expect_trailing_closure_body_changed_blocks(self):
        for header in ("#expect(throws: SomeError.self)", "#expect(\n    throws: SomeError.self\n)"):
            with self.subTest(header=header):
                statement = header + " {\n    try operation()\n}\n"
                self.seed_multiline(statement)
                self.write(TEST_FILE, statement.replace("operation()", "otherOperation()"))
                self.commit("test: change throwing expectation body")
                expected = " ".join(statement.split())
                result = self.assert_blocked(f"assertion removed or changed: {expected}")
                self.assertEqual(result.stderr.count("assertion removed or changed"), 1)

    def test_xctassert_throws_error_trailing_closure_body_changed_blocks(self):
        statement = "XCTAssertThrowsError(try f()) { error in\n    XCTAssertEqual(error as? E, .x)\n}\n"
        self.seed_multiline(statement)
        self.write(TEST_FILE, statement.replace(".x)", ".y)"))
        self.commit("test: change XCTest error validation")
        expected = " ".join(statement.split())
        result = self.assert_blocked(f"assertion removed or changed: {expected}")
        self.assertEqual(result.stderr.count("assertion removed or changed"), 1)

    def test_trailing_closure_assertion_moved_verbatim_passes(self):
        statements = (
            "#expect(throws: SomeError.self) {\n    try operation()\n}\n",
            "XCTAssertThrowsError(try f()) { error in\n    XCTAssertEqual(error as? E, .x)\n}\n",
        )
        for statement in statements:
            with self.subTest(statement=statement):
                self.write(OTHER_FILE, "")
                self.seed_multiline(ORIGINAL + statement)
                self.write(TEST_FILE, ORIGINAL)
                self.write(OTHER_FILE, statement)
                self.commit("test: move trailing closure assertion")
                result = self.run_guard()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("passed", result.stdout)

    def test_single_line_trailing_closure_body_changed_blocks(self):
        statement = "#expect(throws: SomeError.self) { try operation() }\n"
        self.seed_multiline(statement)
        self.write(TEST_FILE, statement.replace("operation()", "otherOperation()"))
        self.commit("test: change single-line throwing expectation body")
        self.assert_blocked(f"assertion removed or changed: {statement.strip()}")

    def test_single_line_trailing_closures_do_not_swallow_following_code(self):
        statement = "#expect(throws: SomeError.self) { try operation() }\n"
        statement += "XCTAssertThrowsError(try f()) { error in XCTAssertEqual(error as? E, .x) }\n"
        self.seed_multiline(statement + "metadata = 1\n")
        self.write(TEST_FILE, statement + "metadata = 2\n")
        self.commit("test: edit code after single-line trailing closures")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed", result.stdout)

    def test_nested_trailing_closure_body_changed_blocks(self):
        statement = "#expect(throws: E.self) {\n    if x {\n        prepare()\n    }\n    try operation()\n}\n"
        self.seed_multiline(statement)
        self.write(TEST_FILE, statement.replace("operation()", "otherOperation()"))
        self.commit("test: change closure body after nested block")
        expected = " ".join(statement.split())
        self.assert_blocked(f"assertion removed or changed: {expected}")

    def test_simple_string_braces_do_not_change_trailing_closure_extent(self):
        for literal in ('"{"', '"}"', r'"escaped \"{"', "'{'", "'}'"):
            with self.subTest(literal=literal):
                statement = f"#expect(throws: E.self) {{\n    log({literal})\n    try operation()\n}}\n"
                self.seed_multiline(statement + "metadata = 1\n")
                self.write(TEST_FILE, statement + "metadata = 2\n")
                self.commit("test: edit code after closure with quoted brace")
                result = self.run_guard()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("passed", result.stdout)
                self.write(TEST_FILE, statement.replace("operation()", "otherOperation()") + "metadata = 2\n")
                self.commit("test: edit closure body after quoted brace")
                expected = " ".join(statement.split())
                self.assert_blocked(f"assertion removed or changed: {expected}")

    def test_unrelated_block_after_assertion_is_not_swallowed(self):
        statement = "#expect(\n    ready\n)\n\nif x {\n    prepare()\n    #expect(valid)\n}\n"
        self.seed_multiline(statement)
        self.write(TEST_FILE, statement.replace("prepare()", "otherPreparation()"))
        self.commit("test: edit unrelated block after assertion")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed", result.stdout)

    def test_assertion_inside_unrelated_later_block_is_still_checked(self):
        statement = "#expect(ready)\n\nif x {\n    #expect(valid)\n}\n"
        self.seed_multiline(statement)
        self.write(TEST_FILE, statement.replace("#expect(valid)", "#expect(true)"))
        self.commit("test: weaken assertion in unrelated block")
        result = self.assert_blocked("assertion removed or changed: #expect(valid)")
        self.assertEqual(result.stderr.count("assertion removed or changed"), 1)

    def test_trailing_closure_collection_caps_total_lines_at_40(self):
        prefix = "#expect(\n    throws: SomeError.self\n) {\n" + "    prepare()\n" * 36
        statement = prefix + "    line40()\n    line41()\n}\n"
        self.seed_multiline(statement)
        self.write(TEST_FILE, statement.replace("line41()", "changed41()"))
        self.commit("test: change closure beyond collection limit")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed", result.stdout)
        self.write(TEST_FILE, statement.replace("line40()", "changed40()"))
        self.commit("test: change closure at collection limit")
        self.assert_blocked("assertion removed or changed")

    def test_commented_assertion_edits_pass(self):
        cases = (
            ("// #expect(foo)\n", ""),
            ("// #expect(foo)\n", "// #expect(bar)\n"),
            ("/* #expect(foo)\n   XCTAssertEqual(a, b) */\n", "/* rewritten note */\n"),
            ("#expect(ready) // TODO: #expect(foo)\n", "#expect(ready) // TODO: done\n"),
        )
        for before, after in cases:
            with self.subTest(before=before, after=after):
                self.seed_multiline(before)
                self.write(TEST_FILE, after)
                self.commit("test: edit commented assertion")
                result = self.run_guard()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("passed", result.stdout)

    def test_python_commented_assertion_edit_passes(self):
        path = "tests/test_fixture.py"
        self.seed_multiline("# self.assertEqual(a, b)\n", path=path)
        self.write(path, "# note\n")
        self.commit("test: edit python comment")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_assertion_string_literal_change_still_blocks(self):
        self.seed_multiline('#expect(name == "a // b")\n')
        self.write(TEST_FILE, '#expect(name == "c // d")\n')
        self.commit("test: change asserted string")
        self.assert_blocked('assertion removed or changed: #expect(name == "a // b")')

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

    def test_python_parenthesized_assert_removed_blocks(self):
        path = "tests/test_fixture.py"
        self.seed_multiline("def test_value():\n    assert(value)\n", path)
        self.write(path, "def test_value():\n    pass\n")
        self.commit("test: remove parenthesized Python assertion")
        self.assert_blocked("assertion removed or changed: assert(value)")

    def test_python_parenthesized_assert_weakened_blocks(self):
        path = "tests/test_fixture.py"
        self.seed_multiline("def test_value():\n    assert(value)\n", path)
        self.write(path, "def test_value():\n    assert(True)\n")
        self.commit("test: weaken parenthesized Python assertion")
        self.assert_blocked("assertion removed or changed: assert(value)")

    def test_python_assert_prefix_identifiers_are_not_assertions(self):
        path = "tests/test_fixture.py"
        statement = "def test_value():\n    assertion = 1\n    assertion_count = 1\n    asserted = 1\n"
        self.seed_multiline(statement, path)
        self.write(path, "def test_value():\n    pass\n")
        self.commit("test: remove assertion metadata")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed", result.stdout)

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
        for trait in (DISABLED, DISABLED.split("(")[0]):
            with self.subTest(trait=trait):
                self.write(TEST_FILE, ORIGINAL.replace("@Test func rejects", f"@Test({trait}) func rejects"))
                self.commit("test: skip")
                self.assert_blocked("skip marker")

    def test_swift_skip_markers_in_comments_and_strings_pass(self):
        lines = (
            f"// {DISABLED.split('(')[0]} is not used here",
            f'let message = "{XCT_SKIP}"',
            f'let message = "{XCT_SKIP}If(true)"',
            f'let message = "escaped \\"{XCT_SKIP}If(true)\\""',
            f'let message = """text "{XCT_SKIP}If(true)" text"""',
            f"/* {XCT_SKIP}If(true) */",
            f"/* documentation\n * {XCT_SKIP}If(true)\n */",
            f"/* documentation\n{XCT_SKIP}If(true)\n*/",
            f"// {ENABLED_IF_RUNTIME}",
            f'let message = "{ENABLED_IF_FALSE}"',
            f"/* documentation\n{ENABLED_IF_RUNTIME}\n*/",
        )
        for line in lines:
            with self.subTest(line=line):
                self.write(TEST_FILE, ORIGINAL + line + "\n")
                self.commit("test: document Swift skip markers")
                result = self.run_guard()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("passed", result.stdout)

    def test_python_skip_markers_in_comments_and_strings_pass(self):
        path = "tests/test_fixture.py"
        lines = (
            f"# {PYTHON_SKIP} later",
            f"# {PYTHON_SKIP}('x') later",
            f'message = "{PYTHON_SKIP}(\'x\')"',
            f"message = '{PYTHON_SKIP}(\"x\")'",
            f'message = """text "{PYTHON_SKIP}(\'x\')" text"""',
            f"message = '''text '{PYTHON_SKIP}(\"x\")' text'''",
            f"# {PYTEST_SKIP}('x')",
            f'message = "{PYTEST_SKIP}(\'x\')"',
            f"# raise {PYTEST_SKIP}.Exception('x')",
            f'message = "{PYTEST_SKIP}.Exception"',
            f"# @{PYTEST_MARK_SKIP}if(True)",
            f'message = "{PYTEST_MARK_SKIP}if(True)"',
        )
        for line in lines:
            with self.subTest(line=line):
                self.write(path, line + "\n")
                self.commit("test: document Python skip markers")
                result = self.run_guard()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("passed", result.stdout)

    def test_swift_skip_in_existing_block_comment_passes(self):
        statement = ORIGINAL + "/* documentation\nplaceholder\n*/\n"
        self.seed_multiline(statement)
        self.write(TEST_FILE, statement.replace("placeholder", f"{XCT_SKIP}If(true)"))
        self.commit("test: edit existing block comment")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("passed", result.stdout)

    def test_added_swift_conditional_skip_blocks(self):
        self.write(TEST_FILE, ORIGINAL + f"try {XCT_SKIP}If(true)\n")
        self.commit("test: conditionally skip")
        self.assert_blocked("skip marker")

    def test_added_python_skip_call_blocks(self):
        self.write("tests/test_fixture.py", f'{PYTHON_SKIP}("x")\n')
        self.commit("test: skip Python test")
        self.assert_blocked("skip marker")

    def test_added_pytest_skip_call_blocks(self):
        self.write("tests/test_fixture.py", f"{PYTEST_SKIP}('x')\n")
        self.commit("test: skip with pytest")
        result = self.assert_blocked("skip marker added")
        self.assertEqual(result.stderr.count("skip marker added"), 1)

    def test_added_pytest_skip_exception_blocks(self):
        self.write("tests/test_fixture.py", f"raise {PYTEST_SKIP}.Exception('x')\n")
        self.commit("test: raise pytest skip exception")
        self.assert_blocked("skip marker added")

    def test_added_pytest_skip_marks_block(self):
        for marker in (PYTEST_MARK_SKIP, PYTEST_MARK_SKIP + "if"):
            with self.subTest(marker=marker):
                self.write("tests/test_fixture.py", f"@{marker}(True)\ndef test_fixture():\n    pass\n")
                self.commit("test: mark pytest test skipped")
                self.assert_blocked("skip marker added")

    def test_swift_comment_delimiters_in_strings_preserve_real_skips(self):
        for delimiter in ("//", "/*", "*/"):
            with self.subTest(delimiter=delimiter):
                self.write(TEST_FILE, ORIGINAL + f'let text = "{delimiter}"; try {XCT_SKIP}If(true)\n')
                self.commit("test: add Swift skip after string")
                self.assert_blocked("skip marker")

    def test_python_comment_delimiter_in_string_preserves_real_skip(self):
        self.write("tests/test_fixture.py", f'message = "#"; {PYTHON_SKIP}("x")\n')
        self.commit("test: add Python skip after string")
        self.assert_blocked("skip marker")

    def test_multiline_enabled_if_false_trait_blocks(self):
        # codex-review #65 round 2: a multiline @Test trait that disables the test (ENABLED_IF_FALSE).
        self.write(TEST_FILE, ORIGINAL.replace("@Test func rejects()",
                                               f"@Test(\n    {ENABLED_IF_FALSE}\n)\nfunc rejects()"))
        self.commit("test: disable")
        self.assert_blocked("skip marker")

    def test_added_enabled_if_false_trait_blocks(self):
        traits = (
            ENABLED_IF_FALSE,
            ENABLED_IF_FALSE.replace("false)", 'false, "reason")'),
            "." + 'enabled ( if :\tfalse , "reason" )',
        )
        for trait in traits:
            with self.subTest(trait=trait):
                self.write(TEST_FILE, ORIGINAL.replace("@Test func rejects", f"@Test({trait}) func rejects"))
                self.commit("test: disable with literal false")
                result = self.assert_blocked("skip marker")
                self.assertEqual(result.stderr.count("skip marker added"), 1)

    def test_multiline_enabled_if_false_argument_blocks(self):
        trait = ENABLED_IF_FALSE.replace("(", "(\n  ").replace(")", "\n)")
        self.write(TEST_FILE, ORIGINAL.replace("@Test func rejects", f"@Test({trait}) func rejects"))
        self.commit("test: disable with multiline condition")
        result = self.assert_blocked("skip marker")
        self.assertEqual(result.stderr.count("skip marker added"), 1)

    def test_added_enabled_if_true_trait_passes(self):
        traits = (
            ENABLED_IF_TRUE,
            ENABLED_IF_TRUE.replace("true)", 'true, "reason")'),
            "." + 'enabled ( if :\ttrue , "reason" )',
            ENABLED_IF_TRUE.replace("(", "(\n  ").replace(": ", ":\n    ").replace(")", "\n)"),
            ENABLED_IF_TRUE.replace("true)", '/* always */ true,\n "reason")'),
        )
        for trait in traits:
            with self.subTest(trait=trait):
                self.write(TEST_FILE, ORIGINAL.replace("@Test func rejects", f"@Test({trait}) func rejects"))
                self.commit("test: enable with literal true")
                result = self.run_guard()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("passed", result.stdout)

    def test_added_enabled_if_runtime_condition_trait_blocks(self):
        traits = (
            ENABLED_IF_RUNTIME,
            "." + "enabled(if: !isCI)",
            "." + "enabled(if: true && isCI)",
            "." + "enabled(if: trueValue)",
        )
        for trait in traits:
            with self.subTest(trait=trait):
                self.write(TEST_FILE, ORIGINAL.replace("@Test func rejects", f"@Test({trait}) func rejects"))
                self.commit("test: enable with runtime condition")
                result = self.assert_blocked("conditional enablement; declare if it can skip:")
                self.assertEqual(result.stderr.count("conditional enablement"), 1)
                self.assertIn(trait, result.stderr)

    def test_multiline_enabled_if_runtime_condition_blocks(self):
        trait = "." + "enabled(\n    if:\n        !isCI\n)"
        self.write(TEST_FILE, ORIGINAL.replace("@Test func rejects", f"@Test({trait}) func rejects"))
        self.commit("test: enable with multiline runtime condition")
        result = self.assert_blocked("conditional enablement; declare if it can skip:")
        self.assertEqual(result.stderr.count("conditional enablement"), 1)
        self.assertIn("!isCI", result.stderr)

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

    def test_pr_body_bare_file_name_fails(self):
        self.remove_assertions()
        for declaration in (TEST_FILE, f"- {TEST_FILE}", f"{TEST_FILE}:",
                            f"- `{TEST_FILE}`: ...", f"123. `{TEST_FILE}`:",
                            f"- [x] `{TEST_FILE}`: __", f"- `{TEST_FILE}`: ab",
                            f"- `{TEST_FILE}`: none", f"- `{TEST_FILE}`: **NONE**"):
            with self.subTest(declaration=declaration):
                self.assert_blocked("with a reason", PR_BODY=TEMPLATE.format(declaration=declaration))

    def test_pr_body_file_name_with_reason_passes(self):
        self.remove_assertions()
        named = self.run_guard(PR_BODY=TEMPLATE.format(declaration=f"- `{TEST_FILE}`: validator removed"))
        self.assertEqual(named.returncode, 0, named.stderr)
        self.assertIn("declared", named.stdout)

    def test_pr_body_reason_on_different_line_fails(self):
        self.remove_assertions()
        for declaration in (f"- {TEST_FILE}\n  assertion moved into helper",
                            f"assertion moved into helper\n- {TEST_FILE}"):
            with self.subTest(declaration=declaration):
                self.assert_blocked("with a reason", PR_BODY=TEMPLATE.format(declaration=declaration))

    def test_pr_body_reason_in_comment_fails(self):
        self.remove_assertions()
        declaration = f"- {TEST_FILE}: <!-- assertion moved into helper -->"
        self.assert_blocked("with a reason", PR_BODY=TEMPLATE.format(declaration=declaration))

    def test_pr_body_three_character_reason_passes(self):
        self.remove_assertions()
        result = self.run_guard(PR_BODY=TEMPLATE.format(declaration=f"- {TEST_FILE}: abc"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("declared", result.stdout)

    def test_pr_body_must_name_each_affected_file(self):
        other_original = ORIGINAL.replace("valid(", "otherValid(")
        self.write(OTHER_FILE, other_original)
        self.commit("test: second file baseline")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.remove_assertions()
        self.write(OTHER_FILE, other_original.replace('#expect(otherValid("a"))', '#expect(true)'))
        self.commit("test: weaken second file")
        declaration = f"- {TEST_FILE}: assertion moved into helper"
        self.assert_blocked(f"does not name each file with a reason: {OTHER_FILE}",
                            PR_BODY=TEMPLATE.format(declaration=declaration))
        self.assert_blocked(f"does not name each file with a reason: {OTHER_FILE}",
                            PR_BODY=TEMPLATE.format(declaration=f"{declaration}\n- {OTHER_FILE}"))
        for incomplete in (f"- {TEST_FILE}, {OTHER_FILE}",
                           f"- {TEST_FILE}, {OTHER_FILE}: none"):
            with self.subTest(declaration=incomplete):
                self.assert_blocked(f"with a reason: {TEST_FILE}, {OTHER_FILE}",
                                    PR_BODY=TEMPLATE.format(declaration=incomplete))
        for complete in (f"{declaration}\n- {OTHER_FILE}: duplicate coverage removed",
                         f"- `{TEST_FILE}`, `{OTHER_FILE}`: assertion moved into helper"):
            with self.subTest(declaration=complete):
                result = self.run_guard(PR_BODY=TEMPLATE.format(declaration=complete))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("declared", result.stdout)

    def test_file_names_in_comments_or_other_sections_do_not_declare_loss(self):
        self.remove_assertions()
        declaration = f"- {TEST_FILE}: assertion moved into helper"
        body = TEMPLATE.format(declaration=f"<!-- {declaration} -->\nnone")
        self.assert_blocked("does not name", PR_BODY=body + f"\n{declaration}\n")

    def test_no_pr_body_passes_with_notice(self):
        self.remove_assertions()
        result = self.run_guard(PR_BODY=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("Notice:", result.stdout)
        self.assertIn(TEST_FILE, result.stdout)
        self.assertIn("assertion removed or changed", result.stdout)
        self.assertIn('PR body section "Removed or weakened tests or policy"', result.stdout)
        self.assertIn("with a reason", result.stdout)

    def test_actions_event_payload_body_is_checked(self):
        self.remove_assertions()
        event = Path(self.temporary.name) / "event.json"
        event.write_text(json.dumps({"pull_request": {"body": TEMPLATE.format(declaration="none")}}))
        self.assert_blocked("does not name", PR_BODY=None,
                            GITHUB_EVENT_NAME="pull_request", GITHUB_EVENT_PATH=str(event))
        body = TEMPLATE.format(declaration=TEST_FILE)
        event.write_text(json.dumps({"pull_request": {"body": body}}))
        self.assert_blocked("with a reason", PR_BODY=None,
                            GITHUB_EVENT_NAME="pull_request", GITHUB_EVENT_PATH=str(event))
        body = TEMPLATE.format(declaration=f"{TEST_FILE}: assertion moved into helper")
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
