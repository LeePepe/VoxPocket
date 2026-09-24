#!/usr/bin/env python3
"""Block undeclared removal or weakening of tests (AGENTS.md: never weaken or skip tests).

Same design as shared-ci `scripts/quality/test_integrity.py` (G5/G6), so a later re-pin can
switch to it without changing behaviour. Against the merge base (VERIFY_BASE, default
origin/main), with no netting:

- every removed assertion line in a test file is a loss unless the same line
  (whitespace-normalized) is added somewhere in the diff (a move or re-indent);
- every test name present at the base but gone at the head is a loss (moves are fine);
- every added skip marker is a loss; a deleted test file loses all its assertions and tests.

Each affected test file must be covered by a line added in this change to the ledger
`.github/test-weakening.md`: `- <test file path>: <reason> (approved: @<owner>)`. The ledger
sits under a CODEOWNERS-owned path, so the ruleset's required code-owner review makes the
Owner approve every declared loss; the check fails closed if CODEOWNERS does not cover it.
On a pull request (PR_BODY, or the body in $GITHUB_EVENT_PATH) the "Removed or weakened
tests or policy" section must name each affected test file; with no losses it may say "none".
"""
from collections import Counter
import fnmatch
import json
import os
from pathlib import Path
import re
import subprocess
import sys

TEST_PATH = re.compile(r"(^|/)Tests/.*\.swift$|Tests\.swift$|(^|/)tests?/.*\.py$|(^|/)test_[^/]*\.py$")
ASSERTION = re.compile(
    r"#expect\b|#require\b|\bXCTAssert\w*\s*\(|\bXCTFail\s*\(|@Test\b|\bfunc\s+test\w*\s*\(|"
    r"\bself\.assert\w+\s*\(|^\s*assert\s")
SKIP = re.compile(r"\.disabled\b|\bXCTSkip\w*\s*\(|withKnownIssue\s*\(|@unittest\.skip|\bpytest\.mark\.skip|"
                  r"\bself\.skipTest\s*\(")
TEST_NAME = re.compile(r"@Test\b[^\n]*?\bfunc\s+(\w+)|\bfunc\s+(test\w*)\s*\(|\bdef\s+(test\w*)\s*\(")
SECTION = "## Removed or weakened tests or policy"
LEDGER = ".github/test-weakening.md"
LEDGER_LINE = re.compile(r"^\+-\s+(\S+?):\s+\S.*\(approved:\s*@\S+\)\s*$")


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


def assertion_losses(base):
    diff = git("diff", "--unified=0", "--no-color", "-M", base, "HEAD")
    removed, added, findings = [], Counter(), []
    old_path = new_path = None
    for line in diff.splitlines():
        if line.startswith("--- "):
            old_path = line[6:] if line.startswith("--- a/") and TEST_PATH.search(line[6:]) else None
        elif line.startswith("+++ "):
            new_path = line[6:] if line.startswith("+++ b/") and TEST_PATH.search(line[6:]) else None
        elif line.startswith("-") and old_path and ASSERTION.search(line[1:]):
            removed.append((old_path, normalized(line[1:])))
        elif line.startswith("+") and new_path:
            if ASSERTION.search(line[1:]):
                added[normalized(line[1:])] += 1
            if SKIP.search(line[1:]):
                findings.append((new_path, f"skip marker added: {line[1:].strip()[:120]}"))
    for path, text in removed:
        if added[text] > 0:
            added[text] -= 1  # moved or re-indented
        else:
            findings.append((path, f"assertion removed or changed: {text[:120]}"))
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
    findings = assertion_losses(base) + test_name_losses(base, rows)
    findings += [(old, "test file deleted") for status, old, _ in rows if status == "D"]
    return findings


def ledger_paths(base):
    """Test paths declared by lines added to the ledger in this change."""
    diff = git("diff", "--unified=0", "--no-color", base, "HEAD", "--", LEDGER)
    return {match.group(1) for match in map(LEDGER_LINE.match, diff.splitlines()) if match}


def ledger_owned(root):
    """True when a CODEOWNERS rule with an owner matches the ledger path (last match wins)."""
    codeowners = root / ".github" / "CODEOWNERS"
    if not codeowners.is_file():
        return False
    owned = False
    for raw in codeowners.read_text().splitlines():
        parts = raw.split("#", 1)[0].split()
        if not parts:
            continue
        pattern = parts[0].lstrip("/")
        hit = (pattern.endswith("/") and LEDGER.startswith(pattern)) or fnmatch.fnmatch(LEDGER, pattern) \
            or fnmatch.fnmatch(LEDGER, pattern.replace("**/", ""))
        if hit:
            owned = len(parts) >= 2
    return owned


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


def problems_for(findings, base, root, body):
    paths = sorted({path for path, _ in findings})
    problems = []
    if not ledger_owned(root):
        problems.append(f".github/CODEOWNERS does not cover {LEDGER}, so a declaration would not need Owner review")
    missing = [path for path in paths if path not in ledger_paths(base)]
    if missing:
        problems.append(f"no line added to {LEDGER} for: " + ", ".join(missing))
    if body is not None:
        section = body_section(body) or ""
        unnamed = [path for path in paths if path not in section]
        if unnamed:
            problems.append(f'PR body section "{SECTION[3:]}" does not name: ' + ", ".join(unnamed))
    return problems


def main():
    event_name = os.environ.get("GITHUB_EVENT_NAME")
    if event_name and not event_name.startswith("pull_request"):
        print(f"Test weakening guard: skipped ({event_name}; pull requests are checked before merge)")
        return
    base_ref = os.environ.get("VERIFY_BASE") or "origin/main"
    try:
        base = git("merge-base", base_ref, "HEAD").strip()
        findings = losses(base)
        root = Path(git("rev-parse", "--show-toplevel").strip())
        problems = problems_for(findings, base, root, pr_body()) if findings else []
    except subprocess.CalledProcessError as error:
        sys.exit(f"[test-weakening] git failed ({' '.join(error.cmd[1:3])}); cannot use merge base "
                 f"with {base_ref}; fetch it and retry")
    if not findings:
        print("Test weakening guard: passed")
        return
    if not problems:
        print("Test weakening guard: declared (Owner code-owner review required) -> "
              + "; ".join(f"{path}: {finding}" for path, finding in findings))
        return
    print("Blocked: tests were removed or weakened without an Owner-gated declaration "
          "(AGENTS.md: never weaken or skip tests):", file=sys.stderr)
    for path, finding in findings:
        print(f"  - {path}: {finding}", file=sys.stderr)
    for problem in problems:
        print(f"  ! {problem}", file=sys.stderr)
    print(f"Fix the code instead, or add `- <test file path>: <reason> (approved: @<owner>)` to {LEDGER} "
          "(CODEOWNERS makes the ruleset require Owner approval) and name each file in the PR template.",
          file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
