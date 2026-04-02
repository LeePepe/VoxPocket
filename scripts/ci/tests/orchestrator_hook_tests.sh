#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)
source "$SCRIPT_DIR/helpers.sh"

workflow_path="$SCRIPT_DIR/../../../.github/workflows/pr-comment-orchestrator.yml"
script_path="$SCRIPT_DIR/../../agents/run_orchestrator_for_pr_comment.sh"

assert_file_exists "$workflow_path"
assert_file_exists "$script_path"

workflow_content="$(cat "$workflow_path")"
assert_contains "issue_comment" "$workflow_content" "workflow should trigger on issue_comment"
assert_contains "pull-requests: write" "$workflow_content" "workflow should be able to post PR comments"
assert_contains "run_orchestrator_for_pr_comment.sh" "$workflow_content" "workflow should call orchestrator script"

script_content="$(cat "$script_path")"
assert_contains ".claude/agents/orchestrator.md" "$script_content" "script should call orchestrator prompt"
assert_contains "gh pr comment" "$script_content" "script should publish orchestrator output back to PR"
