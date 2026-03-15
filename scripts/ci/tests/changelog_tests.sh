#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/../changelog.sh"

commits_fixture=$'feat: add local release version management\nfix: stop duplicate release trigger\ndocs: update local workflow'
rendered="$(render_changelog "$commits_fixture")"

assert_contains "## Features" "$rendered" "should create a features section"
assert_contains "- add local release version management" "$rendered" "feat commits should be included"
assert_contains "## Fixes" "$rendered" "fix commits should be grouped"
assert_contains "## Maintenance" "$rendered" "docs commits should be grouped as maintenance"

tmpdir=$(make_temp_dir)
trap 'rm -rf "$tmpdir"' EXIT
repo_fixture="$tmpdir/repo"
mkdir -p "$repo_fixture"
init_fixture_repo "$repo_fixture"

git_rendered="$(changelog_from_git_range "$repo_fixture" "v1.0.0" "HEAD")"
assert_contains "feat: sample feature" "$git_rendered" "should read commits from git"
assert_eq "v1.0.0" "$(latest_release_tag "$repo_fixture")" "should detect latest release tag"
