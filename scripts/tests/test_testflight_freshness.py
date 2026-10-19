"""Guard TestFlight signing freshness, XcodeGen mapping, and installer portability without credentials."""
from pathlib import Path
import os
import re
import shlex
import stat
import subprocess
import tempfile
import textwrap
import unittest
from urllib.parse import quote, quote_plus, unquote


ROOT = Path(__file__).resolve()
while not (ROOT / ".github/workflows/testflight.yml").is_file():
    if ROOT == ROOT.parent:
        raise RuntimeError("VoxPocket repository root not found")
    ROOT = ROOT.parent

WORKFLOW_PATH = ROOT / ".github/workflows/testflight.yml"
PROJECT_YML_PATH = ROOT / "VoxPocket/project.yml"
FASTFILE_PATH = ROOT / "fastlane/Fastfile"
DOCS_PATH = ROOT / "docs/testflight-release.md"

SYNTHETIC_ENDPOINT = "https://example-pr09-log-sentinel.invalid/example-container"
SYNTHETIC_SAS = "sv=2023-11-03&sr=c&si=example-pr09-create-only&spr=https&sig=FAKE%2BPR09%2Fsentinel%3D"


def workflow_step(name):
    text = WORKFLOW_PATH.read_text(encoding="utf-8")
    match = re.search(r"^      - name: " + re.escape(name) + r"\n(.*?)(?=^      - name: |\Z)", text, re.M | re.S)
    if not match:
        raise AssertionError("Workflow step not found: " + name)
    return match.group(1)


def step_script(name):
    return textwrap.dedent(workflow_step(name).split("        run: |\n", 1)[1])


def sentinel_forms(value):
    return {value, shlex.quote(value), quote(value, safe=""), quote_plus(value), unquote(value),
            re.sub(r"([^A-Za-z0-9_.,:/@+\n-])", r"\\\1", value)}


class TestFlightSecretInjectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="example-pr09-")
        self.addCleanup(self.directory.cleanup)
        self.temp = Path(self.directory.name).resolve()
        self.path = self.temp / "example-telemetry.xcconfig"
        self.environment = {
            **os.environ,
            "RUNNER_TEMP": str(self.temp),
            "GITHUB_WORKSPACE": str(ROOT.parent),
            "TELEMETRY_XCCONFIG_PATH": str(self.path),
            "TELEMETRY_BLOB_ENDPOINT": SYNTHETIC_ENDPOINT,
            "TELEMETRY_BLOB_SAS": SYNTHETIC_SAS,
        }

    def run_step(self, name, environment=None):
        return subprocess.run(["bash", "-c", step_script(name)], env=environment or self.environment,
                              capture_output=True, text=True, cwd=ROOT, timeout=15)

    def assert_clean_logs(self, logs):
        for value in (SYNTHETIC_ENDPOINT, SYNTHETIC_SAS):
            for form in sentinel_forms(value):
                self.assertNotIn(form, logs)

    def test_workflow_writes_only_two_settings_with_mode_0600_without_logging_values(self):
        result = self.run_step("Prepare telemetry xcconfig")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assert_clean_logs(result.stdout + result.stderr)
        self.assertEqual(0o600, stat.S_IMODE(self.path.stat().st_mode))
        self.assertEqual(self.temp, self.path.parent)
        self.assertFalse(self.path.is_symlink())
        self.assertEqual(
            "TELEMETRY_BLOB_ENDPOINT = " + SYNTHETIC_ENDPOINT.replace("//", "/$()/") + "\n"
            "TELEMETRY_BLOB_SAS = " + SYNTHETIC_SAS + "\n", self.path.read_text())
        tracked = subprocess.run(["git", "ls-files", "--error-unmatch", str(self.path)], cwd=ROOT,
                                 capture_output=True, text=True, timeout=15)
        self.assertNotEqual(0, tracked.returncode)

    def test_missing_or_unsafe_input_fails_before_creating_file_without_value_logs(self):
        for key in ("TELEMETRY_BLOB_ENDPOINT", "TELEMETRY_BLOB_SAS"):
            for value in (None, "", "   ", "example\nINJECTED = value", "$(example)", "example/*comment*/"):
                with self.subTest(key=key, value=value):
                    environment = dict(self.environment)
                    if value is None:
                        environment.pop(key)
                    else:
                        environment[key] = value
                    result = self.run_step("Prepare telemetry xcconfig", environment)
                    self.assertNotEqual(0, result.returncode)
                    self.assertIn("Telemetry settings are missing or unsafe for xcconfig", result.stderr)
                    self.assertFalse(self.path.exists())
                    self.assert_clean_logs(result.stdout + result.stderr)

    def test_prepare_refuses_existing_file_symlink_and_checkout_location(self):
        self.path.write_text("example-existing-file")
        result = self.run_step("Prepare telemetry xcconfig")
        self.assertNotEqual(0, result.returncode)
        self.assertEqual("example-existing-file", self.path.read_text())
        self.path.unlink()
        target = self.temp / "example-target"
        target.write_text("example-untouched")
        self.path.symlink_to(target)
        result = self.run_step("Prepare telemetry xcconfig")
        self.assertNotEqual(0, result.returncode)
        self.assertEqual("example-untouched", target.read_text())
        self.path.unlink()
        result = self.run_step("Prepare telemetry xcconfig", {**self.environment, "GITHUB_WORKSPACE": str(self.temp)})
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(self.path.exists())
        self.assert_clean_logs(result.stdout + result.stderr)

    def test_workflow_always_cleanup_after_success_failure_and_cancellation(self):
        self.assertIn("        if: always()", workflow_step("Remove telemetry xcconfig"))
        for terminal in ("success", "failure", "cancelled"):
            with self.subTest(terminal=terminal):
                prepared = self.run_step("Prepare telemetry xcconfig")
                self.assertEqual(0, prepared.returncode, prepared.stderr)
                # 仅模拟终态；always() 的调度由 Actions 负责，不运行发布 workflow。
                terminal_script = {"success": "exit 0", "failure": "exit 1", "cancelled": "kill -TERM $$"}[terminal]
                ended = subprocess.run(["bash", "-c", terminal_script], capture_output=True, text=True, timeout=15)
                self.assertEqual({"success": 0, "failure": 1, "cancelled": -15}[terminal], ended.returncode)
                cleaned = self.run_step("Remove telemetry xcconfig")
                self.assertEqual(0, cleaned.returncode, cleaned.stderr)
                self.assertFalse(self.path.exists())
                self.assert_clean_logs(prepared.stdout + prepared.stderr + cleaned.stdout + cleaned.stderr)
                self.assertEqual(0, self.run_step("Remove telemetry xcconfig").returncode)

    def test_cleanup_finds_file_after_partial_preparation_failure(self):
        # 独占创建后、写入内容/确认权限前注入失败。
        injection = self.temp / "example-python-startup"
        injection.mkdir()
        (injection / "sitecustomize.py").write_text(
            "import os\n"
            "def example_failure(*args):\n"
            "    raise OSError('example synthetic preparation failure')\n"
            "os.fchmod = example_failure\n")
        prepared = self.run_step("Prepare telemetry xcconfig", {**self.environment, "PYTHONPATH": str(injection)})
        self.assertNotEqual(0, prepared.returncode)
        self.assertIn("Telemetry xcconfig preparation failed", prepared.stderr)
        self.assertTrue(self.path.is_file())
        self.assertEqual(0o600, stat.S_IMODE(self.path.stat().st_mode))
        # 清理步骤独立定义路径，不依赖准备步骤导出成功。
        cleaned = self.run_step("Remove telemetry xcconfig")
        self.assertEqual(0, cleaned.returncode, cleaned.stderr)
        self.assertFalse(self.path.exists())
        self.assert_clean_logs(prepared.stdout + prepared.stderr + cleaned.stdout + cleaned.stderr)

    def test_secrets_are_scoped_to_prepare_step_and_only_path_reaches_fastlane(self):
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        prepare = workflow_step("Prepare telemetry xcconfig")
        mac = workflow_step("fastlane macOS beta")
        for key in ("TELEMETRY_BLOB_ENDPOINT", "TELEMETRY_BLOB_SAS"):
            self.assertIn(key + ": ${{ secrets." + key + " }}", prepare)
            self.assertEqual(1, workflow.count("${{ secrets." + key + " }}"))
            self.assertNotIn(key, mac)
        self.assertIn("steps.gate.outputs.release == 'true'", prepare)
        path_env = "TELEMETRY_XCCONFIG_PATH: ${{ runner.temp }}/voxpocket-telemetry-${{ github.run_id }}-${{ github.run_attempt }}.xcconfig"
        for name in ("Prepare telemetry xcconfig", "fastlane macOS beta", "Remove telemetry xcconfig"):
            self.assertIn(path_env, workflow_step(name))
        self.assertNotIn("${{ runner.", workflow.split("    steps:", 1)[0])
        self.assertLess(workflow.index("- name: Remove telemetry xcconfig"), workflow.index("- name: Move last-released tag"))
        self.assertIn("run: fastlane mac beta", mac)
        fastfile = FASTFILE_PATH.read_text(encoding="utf-8")
        self.assertIn("-xcconfig #{Shellwords.escape(telemetry_xcconfig)}", fastfile)
        self.assertNotIn("xcconfig: telemetry_xcconfig", fastfile)
        self.assertIn("> /dev/null 2>&1", fastfile)


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
        self.assertIn("ref: main", self.workflow_text)
        self.assertIn("steps.gate.outputs.release == 'true'", self.workflow_text)
        self.assertIn("refs/tags/testflight/macos-last-released", self.workflow_text)


if __name__ == "__main__":
    unittest.main()
