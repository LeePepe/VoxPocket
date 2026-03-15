#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/../version.sh"

assert_eq "1.4.0" "$(next_marketing_version 1.3.2 minor)" "minor releases should reset patch"
assert_eq "1.4.1" "$(next_marketing_version 1.4.0 patch)" "patch releases should increment patch"
assert_eq "2.0.0" "$(next_marketing_version 1.4.3 major)" "major releases should reset minor and patch"
assert_eq "42" "$(next_build_number 41)" "build number should increment"

tmpdir=$(make_temp_dir)
trap 'rm -rf "$tmpdir"' EXIT
fixture_project="$tmpdir/project.pbxproj"
make_fixture_project "$fixture_project"

assert_eq "1.0" "$(project_marketing_version "$fixture_project")" "should read marketing version"
assert_eq "1" "$(project_build_number "$fixture_project")" "should read build number"

set_project_versions "$fixture_project" "1.4.0" "42"

assert_eq "1.4.0" "$(project_marketing_version "$fixture_project")" "should update marketing version"
assert_eq "42" "$(project_build_number "$fixture_project")" "should update build number"
