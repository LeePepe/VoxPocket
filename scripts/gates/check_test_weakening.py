#!/usr/bin/env python3
"""Block undeclared removal or weakening of tests (AGENTS.md: never weaken or skip tests).

Against the merge base (VERIFY_BASE, default origin/main), every removed or changed
assertion/test-case line, deleted test file and added skip marker is a loss, whatever else
the change adds. A line re-added verbatim in a test file of the same change counts as moved.

A loss passes only when the change adds or edits docs/test-weakening/<name>.md naming each
affected test path and the reason. .github/CODEOWNERS owns that directory, so the ruleset's
required code-owner review makes the Owner approve every declared weakening; this script
fails closed if that CODEOWNERS entry is missing. On a pull request (PR_BODY, or the body in
$GITHUB_EVENT_PATH) the "Removed or weakened tests or policy" section must also not be "none".
"""
from collections import Counter
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
SECTION = "## Removed or weakened tests or policy"
DECLARATIONS = "docs/test-weakening"


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def normalized(line):
    return re.sub(r"\s+", " ", line.strip())


def losses(base):
    """Return (path, finding) pairs for every removed assertion/test case, deleted test file
    or added skip marker. A removed line only counts as moved (not lost) when the identical
    line is added back in some test file of the same change; unrelated additions never
    offset a removal."""
    diff = git("diff", "--unified=0", "--no-color", "--diff-filter=ADMR", "-M", base, "HEAD")
    removed, added, findings = [], Counter(), []
    current_old = current_new = None
    for line in diff.splitlines():
        if line.startswith("--- "):
            path = line[6:] if line.startswith("--- a/") else None
            current_old = path if path and TEST_PATH.search(path) else None
        elif line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
            current_new = path if path and TEST_PATH.search(path) else None
        elif line.startswith("-") and current_old and ASSERTION.search(line[1:]):
            removed.append((current_old, normalized(line[1:])))
        elif line.startswith("+") and current_new:
            if ASSERTION.search(line[1:]):
                added[normalized(line[1:])] += 1
            if SKIP.search(line[1:]):
                findings.append((current_new, f"skip marker added in {current_new}: {line[1:].strip()[:120]}"))
    for path in git("diff", "--name-only", "--diff-filter=D", "-M", base, "HEAD").splitlines():
        if TEST_PATH.search(path):
            findings.append((path, f"test file deleted: {path}"))
    for path, text in removed:
        if added[text] > 0:
            added[text] -= 1  # the same assertion moved or was re-indented
            continue
        findings.append((path, f"assertion/test case removed or changed in {path}: {text[:120]}"))
    return findings


def owned_by_codeowners(root):
    """True when .github/CODEOWNERS assigns an owner to the declaration directory."""
    codeowners = root / ".github" / "CODEOWNERS"
    if not codeowners.is_file():
        return False
    for raw in codeowners.read_text().splitlines():
        parts = raw.split("#", 1)[0].split()
        if len(parts) >= 2 and parts[0].rstrip("*").rstrip("/") in (f"/{DECLARATIONS}", DECLARATIONS):
            return True
    return False


def declarations(base):
    """Text of declaration files added or changed in this range (README excluded)."""
    changed = git("diff", "--name-only", "--diff-filter=AM", base, "HEAD", "--", DECLARATIONS).splitlines()
    return "\n".join(git("show", f"HEAD:{path}") for path in changed
                     if path.endswith(".md") and not path.endswith("/README.md"))


def declared_in_body(body):
    """True when the PR template section names something other than 'none'."""
    if SECTION not in body:
        return False
    text = body.split(SECTION, 1)[1].split("\n## ", 1)[0]
    text = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL).strip().strip("-* ").strip()
    return bool(text) and text.rstrip(".").lower() not in {"none", "n/a", "no"}


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


def main():
    event_name = os.environ.get("GITHUB_EVENT_NAME")
    if event_name and not event_name.startswith("pull_request"):
        print(f"Test weakening guard: skipped ({event_name}; pull requests are checked before merge)")
        return
    base_ref = os.environ.get("VERIFY_BASE") or "origin/main"
    try:
        base = git("merge-base", base_ref, "HEAD").strip()
    except subprocess.CalledProcessError:
        sys.exit(f"[test-weakening] cannot find the merge base with {base_ref}; fetch it and retry")
    findings = losses(base)
    if not findings:
        print("Test weakening guard: passed")
        return
    root = Path(git("rev-parse", "--show-toplevel").strip())
    problems = []
    if not owned_by_codeowners(root):
        problems.append(f".github/CODEOWNERS does not own /{DECLARATIONS}/, so a declaration would not need "
                        "Owner review")
    declared = declarations(base)
    undeclared = sorted({path for path, _ in findings if path not in declared})
    if undeclared:
        problems.append(f"no {DECLARATIONS}/<name>.md added in this change names: " + ", ".join(undeclared))
    body = pr_body()
    if body is not None and not declared_in_body(body):
        problems.append(f'the PR body says "none" (or lacks) "{SECTION[3:]}"')
    if not problems:
        print("Test weakening guard: declared (Owner code-owner review required) -> "
              + "; ".join(finding for _, finding in findings))
        return
    print("Blocked: tests were removed or weakened without an Owner-gated declaration "
          "(AGENTS.md: never weaken or skip tests):", file=sys.stderr)
    for _, finding in findings:
        print(f"  - {finding}", file=sys.stderr)
    for problem in problems:
        print(f"  ! {problem}", file=sys.stderr)
    print(f"Fix the code instead, or add {DECLARATIONS}/<name>.md naming each test path with the reason "
          "(CODEOWNERS makes the ruleset require Owner approval) and list it in the PR template.",
          file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
