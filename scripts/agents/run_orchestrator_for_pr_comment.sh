#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

require_env() {
  local name="$1"
  if [[ -z "${(P)name:-}" ]]; then
    print -u2 -- "missing required environment variable: $name"
    exit 1
  fi
}

require_env "GH_TOKEN"
require_env "PR_NUMBER"
require_env "COMMENT_BODY"
require_env "COMMENT_AUTHOR"
require_env "COMMENT_ID"

CODEX_BIN="${CODEX_BIN:-$HOME/.superset/bin/codex}"
ORCHESTRATOR_PROMPT_PATH="${ORCHESTRATOR_PROMPT_PATH:-$REPO_ROOT/.claude/agents/orchestrator.md}"

if [[ ! -x "$CODEX_BIN" ]]; then
  print -u2 -- "codex binary is not executable: $CODEX_BIN"
  exit 1
fi

if [[ ! -f "$ORCHESTRATOR_PROMPT_PATH" ]]; then
  print -u2 -- "orchestrator prompt not found: $ORCHESTRATOR_PROMPT_PATH"
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/vox-orchestrator.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

pr_desc_raw="$tmp_dir/pr_desc_raw.txt"
pr_desc="$tmp_dir/pr_desc.txt"
pr_diff_raw="$tmp_dir/pr_diff_raw.txt"
pr_diff="$tmp_dir/pr_diff.txt"
pr_comments_raw="$tmp_dir/pr_comments_raw.txt"
pr_comments="$tmp_dir/pr_comments.txt"
prompt_file="$tmp_dir/orchestrator_prompt.txt"
orchestrator_output="$tmp_dir/orchestrator_output.txt"
orchestrator_error="$tmp_dir/orchestrator_error.txt"
comment_body_file="$tmp_dir/comment_body.md"

gh pr view "$PR_NUMBER" --json title,body \
  -q '"Title: " + .title + "\n\nBody:\n" + (.body // "")' > "$pr_desc_raw"
head -c 12000 "$pr_desc_raw" > "$pr_desc"

gh pr diff "$PR_NUMBER" > "$pr_diff_raw"
head -c 12000 "$pr_diff_raw" > "$pr_diff"

gh pr view "$PR_NUMBER" --json comments \
  -q '.comments | map("[@" + .author.login + "]: " + (.body // "")) | join("\n---\n")' > "$pr_comments_raw"
head -c 12000 "$pr_comments_raw" > "$pr_comments"

{
  echo "VoxPocket PR comment received. You are required to orchestrate specialist task dispatch."
  echo
  echo "Trigger:"
  echo "- PR: #$PR_NUMBER"
  echo "- Comment ID: $COMMENT_ID"
  echo "- Author: @$COMMENT_AUTHOR"
  echo "- Body:"
  echo "$COMMENT_BODY"
  echo
  echo "Context:"
  echo "== PR Description (truncated) =="
  cat "$pr_desc"
  echo
  echo "== PR Diff (truncated) =="
  cat "$pr_diff"
  echo
  echo "== Existing PR Comments (truncated) =="
  cat "$pr_comments"
  echo
  echo "Task:"
  echo "1) Classify this feedback/request."
  echo "2) Produce task dispatch to relevant specialists."
  echo "3) State which work can run in parallel and which is sequential."
  echo "4) Provide concrete file paths and acceptance checks."
  echo "5) Keep response concise and actionable for engineers."
} > "$prompt_file"

set +e
"$CODEX_BIN" -p "$ORCHESTRATOR_PROMPT_PATH" "$(cat "$prompt_file")" >"$orchestrator_output" 2>"$orchestrator_error"
codex_exit="$?"
set -e

if [[ "$codex_exit" -ne 0 ]]; then
  {
    echo "## Orchestrator Dispatch Failed"
    echo
    echo "Triggered by comment #$COMMENT_ID from @$COMMENT_AUTHOR on PR #$PR_NUMBER."
    echo
    echo "Codex exited with code: $codex_exit"
    echo
    echo "Error excerpt:"
    echo '```text'
    tail -n 40 "$orchestrator_error"
    echo '```'
  } > "$comment_body_file"

  gh pr comment "$PR_NUMBER" --body-file "$comment_body_file"
  exit "$codex_exit"
fi

{
  echo "## Orchestrator Task Dispatch"
  echo
  echo "Triggered by comment #$COMMENT_ID from @$COMMENT_AUTHOR on PR #$PR_NUMBER."
  echo
  echo "Original comment:"
  echo '```text'
  echo "$COMMENT_BODY"
  echo '```'
  echo
  echo "---"
  echo
  cat "$orchestrator_output"
} > "$comment_body_file"

if [[ "$(wc -c < "$comment_body_file")" -gt 60000 ]]; then
  {
    echo "## Orchestrator Task Dispatch (Truncated)"
    echo
    head -c 59000 "$comment_body_file"
    echo
    echo
    echo "[truncated]"
  } > "$comment_body_file.truncated"
  mv "$comment_body_file.truncated" "$comment_body_file"
fi

gh pr comment "$PR_NUMBER" --body-file "$comment_body_file"
