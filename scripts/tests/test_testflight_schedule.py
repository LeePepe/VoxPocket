"""Guard TestFlight's manual-only entry point without building or uploading."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("TestFlight workflow not found")
    ROOT = ROOT.parent
WORKFLOW = ROOT / ".github/workflows/testflight.yml"


class TestFlightManualOnlyTests(unittest.TestCase):
    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.triggers = self.workflow.split("\non:\n", 1)[1].split("\nconcurrency:", 1)[0]
        self.release = self.workflow.split("\n  release:\n", 1)[1]

    def test_only_explicit_manual_dispatch_is_registered(self):
        events = re.findall(r"^  ([a-z_]+):", self.triggers, re.M)
        self.assertEqual(events, ["workflow_dispatch"])

    def test_release_rejects_non_manual_events(self):
        guards = re.findall(r"^    if: (.+)$", self.release, re.M)
        self.assertEqual(len(guards), 1)
        self.assertTrue(guards[0].startswith("github.event_name == 'workflow_dispatch' && ("), guards)
        self.assertNotIn("needs: freshness", self.release)
        self.assertNotIn("  freshness:", self.workflow)

    def test_manual_force_and_no_new_commit_gate_are_preserved(self):
        force = self.triggers.split("      force:\n", 1)[1]
        self.assertIn("        type: boolean", force)
        self.assertIn("        default: false", force)
        self.assertIn('if [ "$FORCE" = "true" ] || [ "$LATEST" != "$RELEASED" ]; then', self.release)
        self.assertIn("steps.gate.outputs.release == 'true'", self.release)

    def test_release_still_uses_main_without_interrupting_uploads(self):
        self.assertIn("          ref: main", self.release)
        self.assertRegex(self.workflow, r"(?m)^  cancel-in-progress: false(?: |$)")


if __name__ == "__main__":
    unittest.main()
