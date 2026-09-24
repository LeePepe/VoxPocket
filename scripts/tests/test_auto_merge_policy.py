"""Guard the auto-merge policy: owner-review/draft PRs never get auto-merge, and
preserve-history PRs use a merge commit instead of squash."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/auto-merge.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("auto-merge workflow not found")
    ROOT = ROOT.parent
WORKFLOW = ROOT / ".github/workflows/auto-merge.yml"


class AutoMergePolicyTests(unittest.TestCase):
    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.triggers = self.workflow.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
        self.script = self.workflow.split("        run: |\n", 1)[1]

    def test_label_and_draft_transitions_retrigger_the_policy(self):
        types = re.search(r"types: \[([^\]]+)\]", self.triggers).group(1)
        events = {t.strip() for t in types.split(",")}
        for event in ("opened", "reopened", "ready_for_review", "synchronize",
                      "labeled", "unlabeled", "converted_to_draft"):
            self.assertIn(event, events)

    def test_runs_trusted_base_only_and_never_checks_out_pr_code(self):
        self.assertIn("  pull_request_target:", self.triggers)
        self.assertNotIn("actions/checkout", self.workflow)
        self.assertNotIn("github.event.pull_request.head.sha", self.workflow)

    def test_owner_review_and_draft_disable_auto_merge(self):
        self.assertIn('LABELS: ${{ toJSON(github.event.pull_request.labels.*.name) }}', self.workflow)
        self.assertIn('DRAFT: ${{ github.event.pull_request.draft }}', self.workflow)
        self.assertRegex(self.script, r'has_label owner-review')
        self.assertRegex(self.script, r'"\$DRAFT" = "true"')
        disable = self.script.index("--disable-auto")
        enable = self.script.index("--auto\n")
        self.assertLess(disable, enable, "skip branch must come before enabling")

    def test_preserve_history_uses_merge_commit_otherwise_squash(self):
        self.assertRegex(self.script, r'has_label preserve-history')
        self.assertIn("method=--merge", self.script)
        self.assertIn("method=--squash", self.script)
        self.assertIn('gh pr merge "$PR_URL" "$method" --auto', self.script)

    def test_label_names_are_matched_exactly_not_as_substrings(self):
        self.assertIn("jq -e --arg l", self.script)
        self.assertIn("index($l)", self.script)


if __name__ == "__main__":
    unittest.main()
