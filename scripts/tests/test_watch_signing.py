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
  def self.important(*); end
  def self.success(*); end
  def self.user_error!(message); raise message; end
end
module Spaceship
  class ConnectAPI
    def self.token; @token; end
    def self.token=(value); @token = value; end
    class Token
      def self.from(hash: nil, **)
        hash
      end
    end
    class BundleId
      def self.registered
        @registered ||= {}
      end
      def self.created_calls
        @created_calls ||= []
      end
      def self.find(identifier, **)
        registered[identifier]
      end
      def self.create(name:, platform:, identifier:, **)
        entry = { "name" => name, "platform" => platform, "identifier" => identifier }
        registered[identifier] = entry
        created_calls << entry
        entry
      end
    end
  end
end
def default_platform(*); end
def desc(*); end
def platform(name); yield if name == :ios; end
def lane(*); yield; end
def app_store_connect_api_key(**)
  token = { key_id: "example-key", issuer_id: "example-issuer", key: "example-key-content" }
  Spaceship::ConnectAPI.token = token
  if ENV["SIMULATE_EXISTING_WATCH_BUNDLE_ID"] == "1"
    Spaceship::ConnectAPI::BundleId.registered["com.leepepe.voxpocket.watchkitapp"] = { "identifier" => "com.leepepe.voxpocket.watchkitapp" }
  end
  token
end
def latest_testflight_build_number(**); 3; end
def sh(*); end
def lane_context; @context ||= {}; end
def get_provisioning_profile(**options)
  if ENV["SIMULATE_MISSING_WATCH_PROFILE"] == options[:app_identifier]
    lane_context[SharedValues::SIGH_NAME] = ""
  else
    lane_context[SharedValues::SIGH_NAME] = options[:app_identifier] + ".example-profile"
  end
end
def build_app(**options)
  puts JSON.generate(options.merge(created_bundle_ids: Spaceship::ConnectAPI::BundleId.created_calls))
end
def upload_to_testflight(**); end
load ARGV.fetch(0)
'''


class WatchSigningTests(unittest.TestCase):
    def run_lane(self, watch, complication, missing_identifier="", existing_watch_bundle_id="0"):
        env = {"PATH": os.environ["PATH"], "ASC_KEY_ID": "example-key", "ASC_ISSUER_ID": "example-issuer",
               "ASC_KEY_P8_BASE64": "example-fixture", "VOXPOCKET_WATCH_PROFILE_SPECIFIER": watch,
               "VOXPOCKET_WATCH_COMPLICATION_PROFILE_SPECIFIER": complication,
               "SIMULATE_MISSING_WATCH_PROFILE": missing_identifier,
               "SIMULATE_EXISTING_WATCH_BUNDLE_ID": existing_watch_bundle_id}
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
        self.assertEqual(build["created_bundle_ids"], [])

    def test_auto_registers_missing_watch_bundle_ids_idempotently_when_env_specifiers_omitted(self):
        result = self.run_lane("", "", existing_watch_bundle_id="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        build = json.loads(result.stdout)
        self.assertEqual(
            build["created_bundle_ids"],
            [
                {
                    "name": "VoxPocket Watch Complication",
                    "platform": "IOS",
                    "identifier": "com.leepepe.voxpocket.watchkitapp.complication",
                }
            ],
        )

    def test_missing_owner_watch_profile_fails_before_archive(self):
        for missing_id in ["com.leepepe.voxpocket.watchkitapp", "com.leepepe.voxpocket.watchkitapp.complication"]:
            with self.subTest(missing_id=missing_id):
                result = self.run_lane("", "", missing_id)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("Owner-provisioned Watch", result.stderr)


if __name__ == "__main__":
    unittest.main()
