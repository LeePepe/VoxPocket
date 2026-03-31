#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/common.sh"

zsh "$SCRIPT_DIR/validate_manifests.sh"
zsh "$SCRIPT_DIR/run_by_label.sh" pr

