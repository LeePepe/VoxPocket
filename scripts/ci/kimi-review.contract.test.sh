#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
KIMI_SH="$ROOT/scripts/ci/kimi-review.sh"
KIMI_AGENT="$ROOT/scripts/ci/kimi-review-agent.md"
KIMI_WORKFLOW="$ROOT/.github/workflows/kimi-review.yml"
CODEX_TARGET_WORKFLOW="$ROOT/.github/workflows/codex-review-target.yml"
CODEX_LEGACY_WORKFLOW="$ROOT/.github/workflows/codex-review.yml"
CLAUDE_WORKFLOW="$ROOT/.github/workflows/claude-review.yml"
SHARED_CI_PIN='LeePepe/shared-ci/.github/workflows/'

grep -q '^tools: \[\]$' "$KIMI_AGENT"
grep -q '^subagents: \[\]$' "$KIMI_AGENT"
grep -q -- '--agent-file "$SCRIPT_DIR/kimi-review-agent.md"' "$KIMI_SH"
grep -q -- '--output-format stream-json' "$KIMI_SH"
grep -q 'KIMI_REVIEW_MODEL:-kimi-code/k3' "$KIMI_SH"
! grep -Eq -- '(^|[[:space:]])(--yolo|--auto)([[:space:]]|$)' "$KIMI_SH"
grep -q 'Advisory only: this check and its findings are not required for merge' "$KIMI_SH"
begin_line="$(grep -n '===== BEGIN UNTRUSTED PR DIFF' "$KIMI_SH" | head -1 | cut -d: -f1)"
paths_line="$(grep -n '^Changed paths:$' "$KIMI_SH" | head -1 | cut -d: -f1)"
end_line="$(grep -n '===== END UNTRUSTED PR DIFF' "$KIMI_SH" | head -1 | cut -d: -f1)"
[ "$begin_line" -lt "$paths_line" ] && [ "$paths_line" -lt "$end_line" ]
# Kimi: advisory, trusted-base pull_request_target caller of shared-ci (full SHA, no PR head checkout).
grep -q '^  pull_request_target:$' "$KIMI_WORKFLOW"
grep -Fq '    branches: [main]' "$KIMI_WORKFLOW"
grep -Eq "uses: ${SHARED_CI_PIN}kimi-review\.yml@[0-9a-f]{40}$" "$KIMI_WORKFLOW"
! grep -Fq 'github.event.pull_request.head.sha' "$KIMI_WORKFLOW"
# Codex: required, trusted-base caller that keeps the `codex-review-target` check context.
grep -q '^  pull_request_target:$' "$CODEX_TARGET_WORKFLOW"
grep -q '^  codex-review-target:$' "$CODEX_TARGET_WORKFLOW"
grep -q '^    name: codex-review-target$' "$CODEX_TARGET_WORKFLOW"
grep -Fq '    branches: [main]' "$CODEX_TARGET_WORKFLOW"
grep -Eq "uses: ${SHARED_CI_PIN}codex-review\.yml@[0-9a-f]{40}$" "$CODEX_TARGET_WORKFLOW"
grep -Fq 'codex-launcher: python3 scripts/ci/review-raven.py' "$CODEX_TARGET_WORKFLOW"
! grep -Fq 'github.event.pull_request.head.sha' "$CODEX_TARGET_WORKFLOW"
grep -q '^  workflow_dispatch:$' "$CODEX_LEGACY_WORKFLOW"
! grep -q '^  pull_request:$' "$CODEX_LEGACY_WORKFLOW"
# Claude review is removed (plan Q19).
[ ! -e "$CLAUDE_WORKFLOW" ]

if [ -f "$ROOT/scripts/rulesets/main-protection.json" ]; then
    ! jq -e '.rules[]? | select(.type=="required_status_checks")
      | .parameters.required_status_checks[]? | select(.context=="kimi-review" or .context=="claude-review")' \
      "$ROOT/scripts/rulesets/main-protection.json" >/dev/null
    jq -e '.rules[]? | select(.type=="required_status_checks")
      | .parameters.required_status_checks[]? | select(.context=="codex-review-target")' \
      "$ROOT/scripts/rulesets/main-protection.json" >/dev/null
fi

echo "Kimi advisory / Codex required / Claude removed contract passed."
