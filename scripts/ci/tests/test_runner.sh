#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)

zsh "$SCRIPT_DIR/version_tests.sh"
zsh "$SCRIPT_DIR/changelog_tests.sh"
zsh "$SCRIPT_DIR/trigger_tests.sh"
zsh "$SCRIPT_DIR/release_output_tests.sh"
zsh "$SCRIPT_DIR/release_tests.sh"
zsh "$SCRIPT_DIR/hook_tests.sh"
zsh "$SCRIPT_DIR/orchestrator_hook_tests.sh"
