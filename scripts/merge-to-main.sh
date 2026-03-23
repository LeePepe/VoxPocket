#!/usr/bin/env bash
# managed-by: local-review-skill
# local-review-skill version: 2.2.0

set -euo pipefail

source_branch="${1:-}"

if [[ -z "$source_branch" ]]; then
  echo "usage: scripts/merge-to-main.sh <source-branch> [git-merge-args...]" >&2
  exit 1
fi

shift

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
current_branch="$(git -C "$repo_root" branch --show-current)"

if [[ "$current_branch" != "main" ]]; then
  echo "[local-review] checkout main before running scripts/merge-to-main.sh" >&2
  exit 1
fi

skill_path="$(git -C "$repo_root" config local-review.skill-path 2>/dev/null || true)"
if [[ -z "$skill_path" || ! -f "$skill_path/assets/repo-scripts/review.sh" ]]; then
  echo "[local-review] error: skill path not found — re-run the installer" >&2
  exit 1
fi

"$skill_path/assets/repo-scripts/review.sh" merge_to_main

git -C "$repo_root" merge --no-ff "$source_branch" "$@"
