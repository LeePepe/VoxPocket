#!/bin/zsh

set -euo pipefail

ci_script_dir() {
  cd -- "${0:A:h}" >/dev/null 2>&1 || return 1
  pwd
}

log_info() {
  print -- "[local-ci] $*"
}

die() {
  print -u2 -- "[local-ci] ERROR: $*"
  return 1
}

is_worktree_clean() {
  local repo_root="$1"
  [[ -z "$(git -C "$repo_root" status --porcelain)" ]]
}

current_branch_name() {
  local repo_root="$1"
  git -C "$repo_root" rev-parse --abbrev-ref HEAD
}

head_subject() {
  local repo_root="$1"
  git -C "$repo_root" log -1 --pretty=%s
}
