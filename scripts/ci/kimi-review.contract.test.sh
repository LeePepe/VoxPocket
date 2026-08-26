#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
KIMI_SH="$ROOT/scripts/ci/kimi-review.sh"
KIMI_AGENT="$ROOT/scripts/ci/kimi-review-agent.md"
KIMI_WORKFLOW="$ROOT/.github/workflows/kimi-review.yml"
CODEX_TARGET_WORKFLOW="$ROOT/.github/workflows/codex-review-target.yml"
CLAUDE_WORKFLOW="$ROOT/.github/workflows/claude-review.yml"

grep -q '^tools: \[\]$' "$KIMI_AGENT"
grep -q '^subagents: \[\]$' "$KIMI_AGENT"
grep -q -- '--agent-file "$SCRIPT_DIR/kimi-review-agent.md"' "$KIMI_SH"
grep -q -- '--output-format stream-json' "$KIMI_SH"
grep -q 'KIMI_REVIEW_MODEL:-kimi-code/k3' "$KIMI_SH"
! grep -Eq -- '(^|[[:space:]])(--yolo|--auto)([[:space:]]|$)' "$KIMI_SH"
grep -q 'Advisory only: this check and its findings are not required for merge' "$KIMI_SH"
grep -q '^  pull_request_target:$' "$KIMI_WORKFLOW"
grep -Fq 'ref: ${{ github.event.pull_request.base.sha }}' "$KIMI_WORKFLOW"
! grep -Fq 'ref: ${{ github.event.pull_request.head.sha }}' "$KIMI_WORKFLOW"
grep -q '^  pull_request_target:$' "$CODEX_TARGET_WORKFLOW"
grep -q '^  codex-review-target:$' "$CODEX_TARGET_WORKFLOW"
grep -Fq 'ref: ${{ github.event.pull_request.base.sha }}' "$CODEX_TARGET_WORKFLOW"
! grep -Fq 'ref: ${{ github.event.pull_request.head.sha }}' "$CODEX_TARGET_WORKFLOW"
grep -q '^  workflow_dispatch:$' "$CLAUDE_WORKFLOW"
! grep -q '^  pull_request:$' "$CLAUDE_WORKFLOW"

if [ -f "$ROOT/scripts/rulesets/main-protection.json" ]; then
    ! jq -e '.rules[]? | select(.type=="required_status_checks")
      | .parameters.required_status_checks[]? | select(.context=="kimi-review" or .context=="claude-review")' \
      "$ROOT/scripts/rulesets/main-protection.json" >/dev/null
    jq -e '.rules[]? | select(.type=="required_status_checks")
      | .parameters.required_status_checks[]? | select(.context=="codex-review")' \
      "$ROOT/scripts/rulesets/main-protection.json" >/dev/null
fi

echo "Kimi advisory / Claude pause contract passed."
