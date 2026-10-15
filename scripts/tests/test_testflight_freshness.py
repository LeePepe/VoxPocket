"""Guard TestFlight signing freshness, XcodeGen mapping, and installer portability without credentials."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("VoxPocket repository root not found")
    ROOT = ROOT.parent

WORKFLOW_PATH = ROOT / ".github/workflows/testflight.yml"
PROJECT_YML_PATH = ROOT / "VoxPocket/project.yml"
FASTFILE_PATH = ROOT / "fastlane/Fastfile"
DOCS_PATH = ROOT / "docs/testflight-release.md"


class TestFlightFreshnessTests(unittest.TestCase):
    def setUp(self):
        self.workflow_text = WORKFLOW_PATH.read_text(encoding="utf-8")
        self.project_text = PROJECT_YML_PATH.read_text(encoding="utf-8")
        self.fastfile_text = FASTFILE_PATH.read_text(encoding="utf-8")
        self.docs_text = DOCS_PATH.read_text(encoding="utf-8")

    def test_project_specifier_uses_custom_mac_setting_and_preserves_ios(self):
        # Must not contain hardcoded fixed macOS profile name
        self.assertNotIn(
            "VoxPocket Mac App Store",
            self.project_text,
            "project.yml must not hardcode 'VoxPocket Mac App Store'",
        )

        # macOS specifier must consume VOXPOCKET_MAC_PROFILE_SPECIFIER
        self.assertRegex(
            self.project_text,
            r'["\']?PROVISIONING_PROFILE_SPECIFIER\[sdk=macosx\*\]["\']?:\s*(?:\$\(VOXPOCKET_MAC_PROFILE_SPECIFIER\)|"\$\(VOXPOCKET_MAC_PROFILE_SPECIFIER\)")',
            "macOS Release specifier must be $(VOXPOCKET_MAC_PROFILE_SPECIFIER)",
        )

        # iOS specifier preserved
        self.assertRegex(
            self.project_text,
            r'["\']?PROVISIONING_PROFILE_SPECIFIER\[sdk=iphoneos\*\]["\']?:\s*VoxPocket App Store',
            "iOS Release specifier must remain 'VoxPocket App Store'",
        )

        # Release signing style is Manual with Apple Distribution
        self.assertIn("CODE_SIGN_STYLE: Manual", self.project_text)
        self.assertIn("CODE_SIGN_IDENTITY: Apple Distribution", self.project_text)

    def test_fastfile_mac_lane_requests_forced_installed_profile_without_fixed_name(self):
        self.assertNotIn(
            "VoxPocket Mac App Store",
            self.fastfile_text,
            "Fastfile must not hardcode 'VoxPocket Mac App Store'",
        )

        # Extract mac lane definition
        mac_lane_match = re.search(r"platform :mac do\s+desc .*?\s+lane :beta do\s+(.*?)\n  end\nend", self.fastfile_text, re.S)
        self.assertTrue(mac_lane_match, "mac beta lane must exist")
        mac_lane_body = mac_lane_match.group(1)

        # Must call get_provisioning_profile with platform: "macos", force: true, skip_install: false
        self.assertIn('platform: "macos"', mac_lane_body)
        self.assertRegex(mac_lane_body, r"force:\s*true")
        self.assertRegex(mac_lane_body, r"skip_install:\s*false")
        self.assertNotRegex(mac_lane_body, r"provisioning_name:")

    def test_fastfile_mac_lane_uses_canonical_output_and_rejects_missing_profile(self):
        mac_lane_match = re.search(r"platform :mac do\s+desc .*?\s+lane :beta do\s+(.*?)\n  end\nend", self.fastfile_text, re.S)
        self.assertTrue(mac_lane_match, "mac beta lane must exist")
        mac_lane_body = mac_lane_match.group(1)

        # Must read lane_context[SharedValues::SIGH_NAME]
        self.assertIn("lane_context[SharedValues::SIGH_NAME]", mac_lane_body)

        # Must reject empty/blank before build_app (UI.user_error! or raise)
        self.assertRegex(
            mac_lane_body,
            r"(?:empty\?|blank\?)[\s\S]*?UI\.user_error![\s\S]*?build_app\(",
            "mac lane must validate canonical profile name is non-empty before build_app",
        )

        # Must not fallback to app_profile return or fabricated environment keys
        self.assertNotRegex(
            mac_lane_body,
            r"sigh_.*_appstore_profile-name",
            "mac lane must not use fabricated environment key",
        )
        self.assertNotRegex(
            mac_lane_body,
            r"ENV\.fetch\(.*?, app_profile\)",
            "mac lane must not fallback to action return value",
        )

    def test_fastfile_mac_lane_injects_shell_safe_specifier_and_reuses_for_export(self):
        mac_lane_match = re.search(r"platform :mac do\s+desc .*?\s+lane :beta do\s+(.*?)\n  end\nend", self.fastfile_text, re.S)
        self.assertTrue(mac_lane_match, "mac beta lane must exist")
        mac_lane_body = mac_lane_match.group(1)

        self.assertIn("VOXPOCKET_MAC_PROFILE_SPECIFIER=", mac_lane_body)
        self.assertIn("Shellwords.escape", mac_lane_body)

    def test_fastfile_installer_signing_certificate_uses_generic_selector_without_personal_subject(self):
        # Must not contain hardcoded personal certificate subjects (contains colon or parentheses after installer)
        self.assertNotRegex(
            self.fastfile_text,
            r"installerSigningCertificate:\s*\"[^\"]+:\s*[^\"]+\"",
            "Fastfile installerSigningCertificate must not specify a personal certificate subject",
        )

        # Must use generic Mac Installer Distribution selector
        self.assertIn('installerSigningCertificate: "Mac Installer Distribution"', self.fastfile_text)

    def test_workflow_preserves_manual_and_platform_guards(self):
        self.assertIn("workflow_dispatch:", self.workflow_text)
        self.assertIn(
            "ref: ${{ github.event.workflow_run.head_sha || 'main' }}",
            self.workflow_text,
        )
        self.assertIn("steps.gate.outputs.release == 'true'", self.workflow_text)
        self.assertIn("refs/tags/testflight/macos-last-released", self.workflow_text)


if __name__ == "__main__":
    unittest.main()
