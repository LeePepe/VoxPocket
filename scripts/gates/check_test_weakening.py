#!/usr/bin/env python3
"""Block undeclared removal or weakening of tests (AGENTS.md: never weaken or skip tests).

Compares the committed diff against the merge base (VERIFY_BASE, default origin/main) and
counts, per test file, assertion/test-case lines removed versus added, deleted test files
and newly added skip markers. Any net loss must be declared:

- on a pull request (PR_BODY, or the body in $GITHUB_EVENT_PATH in Actions): the
  "Removed or weakened tests or policy" section must name the change (not "none");
- locally (no PR_BODY), a commit in the range must carry a `Test-Weakening: <reason>` trailer.

Moving assertions between test files in the same change is not a loss.
"""
import json
import os
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
TRAILER = re.compile(r"^Test-Weakening:\s*\S", re.IGNORECASE | re.MULTILINE)


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def losses(base):
    """Return human-readable findings for a net loss of assertions or added skips."""
    diff = git("diff", "--unified=0", "--no-color", "--diff-filter=ADMR", "-M", base, "HEAD")
    removed = added = 0
    findings, current = [], None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
            current = path if path and TEST_PATH.search(path) else None
        elif line.startswith("--- "):
            continue
        elif current and line.startswith("-") and ASSERTION.search(line[1:]):
            removed += 1
        elif current and line.startswith("+"):
            if ASSERTION.search(line[1:]):
                added += 1
            if SKIP.search(line[1:]):
                findings.append(f"skip marker added in {current}: {line[1:].strip()[:120]}")
    for path in git("diff", "--name-only", "--diff-filter=D", base, "HEAD").splitlines():
        if TEST_PATH.search(path):
            findings.append(f"test file deleted: {path}")
            removed += sum(1 for text in git("show", f"{base}:{path}").splitlines() if ASSERTION.search(text))
    if removed > added:
        findings.append(f"net {removed - added} assertion/test-case line(s) removed ({removed} removed, {added} added)")
    return findings


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
    body = pr_body()
    if body is not None:
        ok = declared_in_body(body)
        how = f'declare each item under "{SECTION[3:]}" in the PR body and add the owner-review label'
    else:
        ok = bool(TRAILER.search(git("log", f"{base}..HEAD", "--format=%B")))
        how = "add a `Test-Weakening: <reason and approver>` commit trailer and declare it in the PR template"
    if ok:
        print("Test weakening guard: declared -> " + "; ".join(findings))
        return
    print("Blocked: tests were removed or weakened without a declaration (AGENTS.md: never weaken or skip tests):",
          file=sys.stderr)
    for finding in findings:
        print(f"  - {finding}", file=sys.stderr)
    print(f"Fix the code instead, or {how}.", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
