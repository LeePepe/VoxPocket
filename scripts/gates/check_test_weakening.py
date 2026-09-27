#!/usr/bin/env python3
"""Automatically detect test removal or weakening and check PR-body declarations.

Against the merge base (VERIFY_BASE, default origin/main), with no netting:

- every base assertion statement missing from the head of the changed test files is
  a loss (whitespace-normalized moves and re-indents are fine, with counts preserved);
- every test name present at the base but gone at the head is a loss (moves are fine);
- every added skip marker is a loss; a deleted test file loses all its assertions and tests.
  Swift Testing .enabled(if:) counts only with literal false, optionally with a comment argument.

On a pull request (PR_BODY, or the body in $GITHUB_EVENT_PATH) the "Removed or weakened
tests or policy" section must name each affected test file with a reason on the same line,
after stripping HTML comments. Several files may share a reason: removing their paths,
list markers, backticks and punctuation must leave at least three alphanumeric characters
of free text, excluding "none". With no losses the section may say "none".
Without a PR body, findings are notices only, reminding the author to name each file with
a reason in the PR body. This is an automatic declaration check, not an approval requirement.
"""
from collections import Counter
import json
import os
import re
import subprocess
import sys

TEST_PATH = re.compile(r"(^|/)Tests/.*\.swift$|Tests\.swift$|(^|/)tests?/.*\.py$|(^|/)test_[^/]*\.py$")
ASSERTION = re.compile(
    r"#expect\b|#require\b|\bXCTAssert\w*\s*\(|\bXCTFail\s*\(|\bXCTUnwrap\s*\(|"
    r"\bself\.assert\w+\s*\(|^\s*assert(?=\s|\()|\bpytest\.raises\s*\(")
# Test declarations are tracked by name (TEST_NAME), not as assertion statements.
SKIP = re.compile(r"\.disabled\b|\.enabled\s*\(\s*if\s*:\s*false\s*(?=[,)])|\bXCTSkip\w*\s*\(|withKnownIssue\s*\(|@unittest\.skip|\bpytest\.mark\.skip|"
                  r"\bself\.skipTest\s*\(")
TEST_NAME = re.compile(r"@Test\b[\s\S]{0,600}?\bfunc\s+(\w+)|\bfunc\s+(test\w*)\s*\(|\bdef\s+(test\w*)\s*\(")
SECTION = "## Removed or weakened tests or policy"
SIMPLE_STRING = re.compile(r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*' ''', re.VERBOSE)
LINE_STRING = re.compile(r'"""(?:\\.|[^\\])*?"""|' + r"'''(?:\\.|[^\\])*?'''|" + SIMPLE_STRING.pattern,
                         re.VERBOSE)


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def normalized(line):
    return re.sub(r"\s+", " ", line.strip())


def test_names(text):
    return Counter(next(group for group in match.groups() if group) for match in TEST_NAME.finditer(text))


def changed_test_files(base):
    """(status, old_path, new_path) for test files touched between base and HEAD."""
    rows = []
    for line in git("diff", "--name-status", "-M", base, "HEAD").splitlines():
        parts = line.split("\t")
        status, old, new = parts[0][0], parts[1], parts[-1]
        if TEST_PATH.search(old) or TEST_PATH.search(new):
            rows.append((status, old, new))
    return rows


def assertion_statements(text):
    """Collect assertions through balanced parentheses/brackets, at most 40 lines."""
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        if not ASSERTION.search(lines[index]):
            index += 1
            continue
        statement, depth = [], 0
        for _ in range(40):
            line = lines[index]
            statement.append(line)
            delimiters = SIMPLE_STRING.sub("", line)
            depth += sum(delimiters.count(char) for char in "([")
            depth -= sum(delimiters.count(char) for char in ")]")
            index += 1
            if depth <= 0 or index == len(lines):
                break
        yield normalized(" ".join(statement))


def assertion_losses(base, rows):
    before, after, findings = [], Counter(), []
    for status, old, new in rows:
        if status != "A" and TEST_PATH.search(old):
            before.extend((old, text) for text in assertion_statements(git("show", f"{base}:{old}")))
        if status != "D" and TEST_PATH.search(new):
            after.update(assertion_statements(git("show", f"HEAD:{new}")))
    for path, text in before:
        if after[text] > 0:
            after[text] -= 1  # moved or re-indented
        else:
            findings.append((path, f"assertion removed or changed: {text[:120]}"))
    return findings


def code_lines(text, path):
    """Strip line-local strings/comments, retaining Swift block-comment state."""
    swift = path.endswith(".swift")
    comment = "//" if swift else "#"
    block_depth = 0
    for line in text.splitlines():
        code, index = [], 0
        while index < len(line):
            if block_depth:
                if line.startswith("/*", index):
                    block_depth += 1
                    index += 2
                elif line.startswith("*/", index):
                    block_depth -= 1
                    index += 2
                else:
                    index += 1
                continue
            string = LINE_STRING.match(line, index)
            if string:
                code.append(" ")
                index = string.end()
            elif line.startswith(comment, index):
                break
            elif swift and line.startswith("/*", index):
                code.append(" ")
                block_depth = 1
                index += 2
            else:
                code.append(line[index])
                index += 1
        yield "".join(code)


def skip_marker_additions(base):
    diff = git("diff", "--unified=0", "--no-color", "-M", base, "HEAD")
    findings = []
    new_path = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            new_path = line[6:] if line.startswith("+++ b/") and TEST_PATH.search(line[6:]) else None
            if new_path:
                lines = list(code_lines(git("show", f"HEAD:{new_path}"), new_path))
        elif line.startswith("@@ ") and new_path:
            hunk = re.search(r"\+(\d+)(?:,(\d+))?", line)
            new_line = int(hunk.group(1)) - 1
            count = int(hunk.group(2)) if hunk.group(2) is not None else 1
            # Zero-context hunks contain only additions; retain line breaks to spot split traits.
            added = "\n".join(lines[new_line:new_line + count])
            for match in SKIP.finditer(added):
                if "\n" in match.group():  # Single-line matches are reported below, once per line.
                    findings.append((new_path, f"skip marker added: {normalized(match.group())[:120]}"))
        elif line.startswith("+") and new_path:
            if SKIP.search(lines[new_line]):
                findings.append((new_path, f"skip marker added: {line[1:].strip()[:120]}"))
            new_line += 1
        elif line.startswith(" ") and new_path:
            new_line += 1
    return findings


def test_name_losses(base, rows):
    before, after, where = Counter(), Counter(), {}
    for status, old, new in rows:
        if status != "A" and TEST_PATH.search(old):
            names = test_names(git("show", f"{base}:{old}"))
            before.update(names)
            where.update({name: old for name in names})
        if status != "D" and TEST_PATH.search(new):
            after.update(test_names(git("show", f"HEAD:{new}")))
    return [(where[name], f"test removed: {name}") for name in sorted(before) if before[name] > after[name]]


def losses(base):
    rows = changed_test_files(base)
    findings = assertion_losses(base, rows) + skip_marker_additions(base) + test_name_losses(base, rows)
    findings += [(old, "test file deleted") for status, old, _ in rows if status == "D"]
    return findings


def body_section(body):
    if SECTION not in body:
        return None
    text = body.split(SECTION, 1)[1].split("\n## ", 1)[0]
    return re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL).strip()


def pr_body():
    """PR body from PR_BODY or the Actions event payload; None outside a pull request."""
    if "PR_BODY" in os.environ:
        return os.environ["PR_BODY"]
    event = os.environ.get("GITHUB_EVENT_PATH")
    if event and os.path.isfile(event):
        with open(event, encoding="utf-8") as handle:
            pull_request = json.load(handle).get("pull_request")
        if pull_request is not None:
            return pull_request.get("body") or ""
    return None


def problems_for(findings, body):
    paths = sorted({path for path, _ in findings})
    problems = []
    if body is not None:
        section = body_section(body) or ""
        declared = set()
        for line in section.splitlines():
            named = {path for path in paths if path in line}
            reason = line
            for path in sorted(named, key=len, reverse=True):
                reason = reason.replace(path, "")
            reason = re.sub(r"^\s*(?:[-+*]|\d+[.)])\s*(?:\[[ xX]\]\s*)?", "", reason)
            words = re.findall(r"[^\W_]+", reason)
            if sum(len(word) for word in words if word.casefold() != "none") >= 3:
                declared.update(named)
        unnamed = [path for path in paths if path not in declared]
        if unnamed:
            problems.append(f'PR body section "{SECTION[3:]}" does not name each file with a reason: '
                            + ", ".join(unnamed))
    return problems


def main():
    base_ref = os.environ.get("VERIFY_BASE") or "origin/main"
    try:
        base = git("merge-base", base_ref, "HEAD").strip()
        findings = losses(base)
        body = pr_body()
        problems = problems_for(findings, body)
    except subprocess.CalledProcessError as error:
        sys.exit(f"[test-weakening] git failed ({' '.join(error.cmd[1:3])}); cannot use merge base "
                 f"with {base_ref}; fetch it and retry")
    if not findings:
        print("Test weakening declaration check: passed")
        return
    if not problems:
        if body is None:
            print(f'Notice: no PR body available; name each affected test file with a reason on the same line '
                  f'in the PR body section "{SECTION[3:]}".')
        print("Test weakening declaration check: " + ("notice" if body is None else "declared") + " -> "
              + "; ".join(f"{path}: {finding}" for path, finding in findings))
        return
    print("Blocked: tests were removed or weakened without a PR-body declaration:", file=sys.stderr)
    for path, finding in findings:
        print(f"  - {path}: {finding}", file=sys.stderr)
    for problem in problems:
        print(f"  ! {problem}", file=sys.stderr)
    print(f'Name each affected test file with a reason on the same line in the PR body section "{SECTION[3:]}".',
          file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
