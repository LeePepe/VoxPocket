#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)
source "$SCRIPT_DIR/helpers.sh"
export VOX_CI_SOURCE_ONLY=1
source "$SCRIPT_DIR/../release.sh"

assert_eq "minor" "$(default_bump_for_source dev)" "dev merges should default to minor"
assert_eq "patch" "$(default_bump_for_source hotfix/audio)" "hotfix merges should default to patch"
assert_eq "v1.4.0" "$(release_tag_for 1.4.0)" "tag generation should prepend v"

tmpdir=$(make_temp_dir)
trap 'rm -rf "$tmpdir"' EXIT
repo_fixture="$tmpdir/repo"
mkdir -p "$repo_fixture"
make_release_fixture_repo "$repo_fixture"

fake_run_build() {
  local repo_root="$1"
  local derived_data="$2"
  local log_file="$3"
  mkdir -p "$derived_data/Build/Products/Debug/VoxPocket.app/Contents/MacOS"
  touch "$derived_data/Build/Products/Debug/VoxPocket.app/Contents/MacOS/VoxPocket"
  print -- "build ok" >"$log_file"
}

run_build() {
  fake_run_build "$@"
}

release_pipeline "$repo_fixture" "main" "dev"

assert_eq "1.4.0" "$(project_marketing_version "$repo_fixture/VoxPocket/VoxPocket.xcodeproj/project.pbxproj")" "release should bump marketing version"
assert_eq "42" "$(project_build_number "$repo_fixture/VoxPocket/VoxPocket.xcodeproj/project.pbxproj")" "release should bump build number"
assert_file_exists "$repo_fixture/releases/v1.4.0/CHANGELOG.md"
assert_file_exists "$repo_fixture/releases/v1.4.0/release.json"
assert_eq "v1.4.0" "$(git -C "$repo_fixture" describe --tags --exact-match HEAD)" "release should create a tag"
