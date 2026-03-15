#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)
source "$SCRIPT_DIR/helpers.sh"

hook_content="$(cat "$SCRIPT_DIR/../../../.githooks/post-merge")"
assert_contains "scripts/ci/release.sh" "$hook_content" "hook should invoke release entrypoint"
assert_contains "--auto" "$hook_content" "hook should invoke auto release mode"

installer_output="$(zsh "$SCRIPT_DIR/../install-hooks.sh" --print-command)"
assert_contains "git config core.hooksPath .githooks" "$installer_output" "installer should configure repo hooks"
