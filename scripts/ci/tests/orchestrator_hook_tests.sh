#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)
source "$SCRIPT_DIR/helpers.sh"

workflow_path="$SCRIPT_DIR/../../../.github/workflows/pr-comment-orchestrator.yml"
script_path="$SCRIPT_DIR/../../agents/run_orchestrator_for_pr_comment.sh"

# D-002 / RB-001: The duplicate PR-comment orchestrator workflow is retired and must remain absent.
[[ ! -e "$workflow_path" ]] || fail "retired dispatcher workflow must remain absent: $workflow_path"

assert_file_exists "$script_path"

script_content="$(cat "$script_path")"
assert_contains ".claude/agents/pr-comment-handler.md" "$script_content" "script should call pr-comment-handler prompt"
[[ "$script_content" != *".claude/agents/orchestrator.md"* ]] || fail "script should not reference obsolete orchestrator prompt"
assert_contains "gh pr comment" "$script_content" "script should publish handler output back to PR"
