#!/usr/bin/env python3
"""Exercise the real iOS Fastlane export mapping without provisioning or upload."""
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUBY_HOST = r'''
require "json"
module SharedValues; SIGH_NAME = :profile; end
module UI
  def self.message(*); end
  def self.user_error!(message); raise message; end
end
def default_platform(*); end
def desc(*); end
def platform(name); yield if name == :ios; end
def lane(*); yield; end
def app_store_connect_api_key(**); {}; end
def latest_testflight_build_number(**); 3; end
def sh(*); end
def lane_context; @context ||= {}; end
def get_provisioning_profile(**options)
  lane_context[SharedValues::SIGH_NAME] = options[:app_identifier] + ".example-profile"
end
def build_app(**options); puts JSON.generate(options); end
def upload_to_testflight(**); end
load ARGV.fetch(0)
'''


class WatchSigningTests(unittest.TestCase):
    def run_lane(self, watch, complication):
        env = {"PATH": os.environ["PATH"], "ASC_KEY_ID": "example-key", "ASC_ISSUER_ID": "example-issuer",
               "ASC_KEY_P8_BASE64": "example-fixture", "VOXPOCKET_WATCH_PROFILE_SPECIFIER": watch,
               "VOXPOCKET_WATCH_COMPLICATION_PROFILE_SPECIFIER": complication}
        return subprocess.run(["ruby", "-e", RUBY_HOST, str(ROOT / "fastlane/Fastfile")],
                              env=env, text=True, capture_output=True, timeout=15)

    def test_preserves_app_widget_mapping_and_adds_both_owner_profiles(self):
        result = self.run_lane("example watch profile", "example complication profile")
        self.assertEqual(result.returncode, 0, result.stderr)
        build = json.loads(result.stdout)
        profiles = build["export_options"]["provisioningProfiles"]
        self.assertEqual(profiles["com.leepepe.voxpocket"], "com.leepepe.voxpocket.example-profile")
        self.assertEqual(profiles["com.leepepe.voxpocket.widget"], "com.leepepe.voxpocket.widget.example-profile")
        self.assertEqual(profiles["com.leepepe.voxpocket.watchkitapp"], "example watch profile")
        self.assertEqual(profiles["com.leepepe.voxpocket.watchkitapp.complication"], "example complication profile")
        self.assertIn(r"VOXPOCKET_WATCH_PROFILE_SPECIFIER=example\ watch\ profile", build["xcargs"])
        self.assertEqual(build["export_options"]["signingStyle"], "manual")

    def test_missing_owner_watch_profile_fails_before_archive(self):
        for watch, complication in [("", "example-profile"), ("example-profile", "")]:
            with self.subTest(watch=watch, complication=complication):
                result = self.run_lane(watch, complication)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("Owner-provisioned Watch", result.stderr)


if __name__ == "__main__":
    unittest.main()
