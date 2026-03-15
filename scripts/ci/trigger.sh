#!/bin/zsh

set -euo pipefail

merge_source_from_subject() {
  local subject="$1"
  if [[ "$subject" =~ "Merge branch '([^']+)'" ]]; then
    print -- "${match[1]}"
    return 0
  fi

  return 1
}

release_bump_kind() {
  local branch="$1"
  local source="$2"

  if [[ "$branch" != "main" ]]; then
    return 1
  fi

  if [[ "$source" == "dev" ]]; then
    print -- "minor"
  elif [[ "$source" == hotfix/* ]]; then
    print -- "patch"
  else
    return 1
  fi
}

should_run_release() {
  local branch="$1"
  local source="$2"
  local worktree_state="$3"
  local event_kind="$4"

  [[ "$branch" == "main" ]] || { print -- "no"; return 0; }
  [[ "$event_kind" == "merge" ]] || { print -- "no"; return 0; }
  [[ "$worktree_state" == "clean" ]] || { print -- "no"; return 0; }

  if [[ "$source" == "dev" || "$source" == hotfix/* ]]; then
    print -- "yes"
  else
    print -- "no"
  fi
}
