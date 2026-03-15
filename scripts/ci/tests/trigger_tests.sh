#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/../trigger.sh"

assert_eq "yes" "$(should_run_release main dev clean merge)" "main receiving dev merge should trigger"
assert_eq "no" "$(should_run_release dev feature/foo clean merge)" "dev branch should not trigger"
assert_eq "no" "$(should_run_release main dev dirty merge)" "dirty worktree should not trigger"
assert_eq "patch" "$(release_bump_kind main hotfix/audio)" "hotfix merges should map to patch"
assert_eq "minor" "$(release_bump_kind main dev)" "dev merges should map to minor"
assert_eq "dev" "$(merge_source_from_subject "Merge branch 'dev'")" "should detect dev source"
assert_eq "hotfix/audio" "$(merge_source_from_subject "Merge branch 'hotfix/audio'")" "should detect hotfix source"
