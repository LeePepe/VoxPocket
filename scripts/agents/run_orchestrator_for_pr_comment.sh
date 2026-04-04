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

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || true)}"
HANDLER_PROMPT_PATH="${HANDLER_PROMPT_PATH:-$REPO_ROOT/.claude/agents/pr-comment-handler.md}"

if [[ ! -x "$CLAUDE_BIN" ]]; then
  print -u2 -- "claude binary not found or not executable: $CLAUDE_BIN"
  exit 1
fi

if [[ ! -f "$HANDLER_PROMPT_PATH" ]]; then
  print -u2 -- "pr-comment-handler prompt not found: $HANDLER_PROMPT_PATH"
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/vox-pr-handler.XXXXXX")"
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
prompt_file="$tmp_dir/handler_prompt.txt"
handler_output="$tmp_dir/handler_output.txt"
handler_error="$tmp_dir/handler_error.txt"
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
  echo "You are the VoxPocket pr-comment-handler. A new PR comment has arrived."
  echo "Follow your agent definition exactly: classify → plan → Codex review loop → fix → build → commit → resolve."
  echo
  echo "== Inputs =="
  echo "PR_NUMBER: $PR_NUMBER"
  echo "COMMENT_ID: $COMMENT_ID"
  echo "COMMENT_AUTHOR: @$COMMENT_AUTHOR"
  echo
  echo "== Comment Body =="
  echo "$COMMENT_BODY"
  echo
  echo "== PR Description (truncated at 12k) =="
  cat "$pr_desc"
  echo
  echo "== PR Diff (truncated at 12k) =="
  cat "$pr_diff"
  echo
  echo "== Existing PR Comments (truncated at 12k) =="
  cat "$pr_comments"
} > "$prompt_file"

set +e
"$CLAUDE_BIN" \
  --system-prompt "$HANDLER_PROMPT_PATH" \
  --dangerously-skip-permissions \
  --print \
  "$(cat "$prompt_file")" \
  >"$handler_output" 2>"$handler_error"
claude_exit="$?"
set -e

if [[ "$claude_exit" -ne 0 ]]; then
  {
    echo "## PR Comment Handler Failed"
    echo
    echo "Triggered by comment #$COMMENT_ID from @$COMMENT_AUTHOR on PR #$PR_NUMBER."
    echo
    echo "Claude exited with code: $claude_exit"
    echo
    echo "Error excerpt:"
    echo '```text'
    tail -n 40 "$handler_error"
    echo '```'
  } > "$comment_body_file"

  gh pr comment "$PR_NUMBER" --body-file "$comment_body_file"
  exit "$claude_exit"
fi

# Handler may have already posted comments and resolved threads as part of its tool use.
# Only post a summary comment if the handler produced substantial output.
if [[ "$(wc -c < "$handler_output")" -gt 100 ]]; then
  {
    echo "## PR Comment Handler Summary"
    echo
    echo "Triggered by comment #$COMMENT_ID from @$COMMENT_AUTHOR on PR #$PR_NUMBER."
    echo
    cat "$handler_output"
  } > "$comment_body_file"

  if [[ "$(wc -c < "$comment_body_file")" -gt 60000 ]]; then
    {
      head -c 59000 "$comment_body_file"
      echo
      echo "[truncated]"
    } > "$comment_body_file.truncated"
    mv "$comment_body_file.truncated" "$comment_body_file"
  fi

  gh pr comment "$PR_NUMBER" --body-file "$comment_body_file"
fi
