#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/../release_metadata.sh"
source "$SCRIPT_DIR/../build.sh"

tmpdir=$(make_temp_dir)
trap 'rm -rf "$tmpdir"' EXIT

staging_dir="$(stage_release_dir "$tmpdir" "1.4.0")"
mkdir -p "$tmpdir/fake-app/VoxPocket.app/Contents/MacOS"
touch "$tmpdir/fake-app/VoxPocket.app/Contents/MacOS/VoxPocket"

install_release_artifact "$tmpdir/fake-app/VoxPocket.app" "$staging_dir"
write_release_metadata "$staging_dir" "1.4.0" "v1.4.0" "deadbeef" "42" "artifacts/VoxPocket.app"
print -- "notes" >"$staging_dir/CHANGELOG.md"
finalize_release_dir "$staging_dir" "$tmpdir/releases/v1.4.0"

assert_file_exists "$tmpdir/releases/v1.4.0/CHANGELOG.md"
assert_file_exists "$tmpdir/releases/v1.4.0/release.json"
assert_file_exists "$tmpdir/releases/v1.4.0/artifacts/VoxPocket.app"

build_cmd="$(build_command "/tmp/repo" "/tmp/derived")"
assert_contains "-project /tmp/repo/VoxPocket/VoxPocket.xcodeproj" "$build_cmd" "should target the app project"
assert_contains "-scheme VoxPocket" "$build_cmd" "should use VoxPocket scheme"
