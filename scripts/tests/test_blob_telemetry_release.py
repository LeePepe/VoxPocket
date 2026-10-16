#!/usr/bin/env python3
"""Black-box tests for the unsigned synthetic telemetry Release verifier."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
VERIFIER = ROOT / "scripts/ci/verify_telemetry_release.sh"
SYNTHETIC_ENDPOINT = "https://telemetry.example.invalid/container"
SYNTHETIC_SAS = (
    "sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake%2Bonly%2F%3D"
)


class BlobTelemetryReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="voxpocket release verifier ")
        self.addCleanup(self.temporary.cleanup)
        self.fixture = Path(self.temporary.name) / "repo with spaces"
        verifier = self.fixture / "scripts/ci/verify_telemetry_release.sh"
        verifier.parent.mkdir(parents=True)
        shutil.copy2(VERIFIER, verifier)
        (self.fixture / "VoxPocket").mkdir()
        (self.fixture / "VoxPocket/project.yml").write_text("name: VoxPocket\n")

        self.bin = Path(self.temporary.name) / "bin"
        self.bin.mkdir()
        self.calls = Path(self.temporary.name) / "calls.log"
        self.make_tool(
            "xcodegen",
            """#!/bin/bash
set -eu
printf 'xcodegen|%s|%s\n' "$PWD" "$*" >> "$VERIFIER_TEST_CALLS"
test "$1" = generate
test "$2" = --spec
test "$3" = project.yml
mkdir -p VoxPocket.xcodeproj
""",
        )
        self.make_tool(
            "xcodebuild",
            f"""#!/usr/bin/env python3
import os
from pathlib import Path
import plistlib
import stat
import sys

args = sys.argv[1:]
with open(os.environ["VERIFIER_TEST_CALLS"], "a") as log:
    log.write("xcodebuild|" + "|".join(args) + "\\n")

required = {{
    "-configuration", "Release",
    "-destination", "platform=macOS",
    "-scheme", "VoxPocket",
    "-xcconfig",
    "CODE_SIGN_IDENTITY=",
    "CODE_SIGNING_REQUIRED=NO",
    "CODE_SIGNING_ALLOWED=NO",
    "build",
}}
if not required.issubset(set(args)):
    sys.exit(91)
if not args[args.index("-project") + 1].endswith("/VoxPocket/VoxPocket.xcodeproj"):
    sys.exit(91)
if any(value in args for value in ("archive", "-exportArchive", "upload")):
    sys.exit(92)
if any("{SYNTHETIC_ENDPOINT}" in value or "{SYNTHETIC_SAS}" in value for value in args):
    sys.exit(93)

xcconfig = Path(args[args.index("-xcconfig") + 1])
if stat.S_IMODE(xcconfig.stat().st_mode) != 0o600:
    sys.exit(94)
if xcconfig.read_text().splitlines() != [
    "TELEMETRY_BLOB_ENDPOINT = https:/$()/telemetry.example.invalid/container",
    "TELEMETRY_BLOB_SAS = {SYNTHETIC_SAS}",
]:
    sys.exit(95)

derived = Path(args[args.index("-derivedDataPath") + 1])
plist = derived / "Build/Products/Release/VoxPocket.app/Contents/Info.plist"
plist.parent.mkdir(parents=True)
mode = os.environ.get("VERIFIER_TEST_PLIST_MODE", "valid")
values = {{
    "LokiKitBlobEndpoint": "{SYNTHETIC_ENDPOINT}",
    "LokiKitBlobSAS": "{SYNTHETIC_SAS}",
}}
if mode == "mismatch":
    values["LokiKitBlobEndpoint"] = "https://wrong.example.invalid/container"
elif mode == "unresolved":
    values["LokiKitBlobSAS"] = "$(TELEMETRY_BLOB_SAS)"
elif mode == "missing":
    del values["LokiKitBlobSAS"]
with plist.open("wb") as output:
    plistlib.dump(values, output)
""",
        )
        for name in ("az", "curl", "fastlane", "gh"):
            self.make_tool(
                name,
                "#!/bin/bash\n"
                f"printf 'forbidden:{name}\\n' >> \"$VERIFIER_TEST_CALLS\"\n"
                "exit 93\n",
            )
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}",
            VERIFIER_TEST_CALLS=str(self.calls),
        )

    def make_tool(self, name, content):
        tool = self.bin / name
        tool.write_text(textwrap.dedent(content))
        tool.chmod(0o755)

    def run_verifier(self, mode="valid"):
        env = dict(self.env, VERIFIER_TEST_PLIST_MODE=mode)
        return subprocess.run(
            ["bash", "scripts/ci/verify_telemetry_release.sh"],
            cwd=self.fixture,
            env=env,
            text=True,
            capture_output=True,
        )

    def test_builds_unsigned_release_and_accepts_exact_processed_values(self):
        result = self.run_verifier()

        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text()
        self.assertIn("xcodegen|", calls)
        self.assertIn("|generate --spec project.yml", calls)
        self.assertIn("xcodebuild|", calls)
        self.assertIn("|-xcconfig|", calls)
        build_args = next(line for line in calls.splitlines() if line.startswith("xcodebuild|")).split("|")
        xcconfig = Path(build_args[build_args.index("-xcconfig") + 1])
        self.assertFalse(xcconfig.exists())
        self.assertNotIn("forbidden:", calls)
        self.assertNotIn(SYNTHETIC_ENDPOINT, calls)
        self.assertNotIn(SYNTHETIC_SAS, calls)
        self.assertNotIn(SYNTHETIC_ENDPOINT, result.stdout + result.stderr)
        self.assertNotIn(SYNTHETIC_SAS, result.stdout + result.stderr)

    def test_rejects_a_mismatched_processed_value(self):
        result = self.run_verifier("mismatch")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LokiKitBlobEndpoint", result.stderr)

    def test_rejects_an_unresolved_build_setting(self):
        result = self.run_verifier("unresolved")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unresolved build setting", result.stderr)

    def test_rejects_a_missing_processed_key(self):
        result = self.run_verifier("missing")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LokiKitBlobSAS", result.stderr)


if __name__ == "__main__":
    unittest.main()
