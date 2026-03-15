#!/bin/zsh

set -euo pipefail

latest_release_tag() {
  local repo_root="$1"
  git -C "$repo_root" describe --tags --abbrev=0 2>/dev/null || true
}

changelog_from_git_range() {
  local repo_root="$1"
  local from_ref="$2"
  local to_ref="$3"
  git -C "$repo_root" log --pretty=%s "${from_ref}..${to_ref}"
}

render_section() {
  local title="$1"
  local lines="$2"
  [[ -n "$lines" ]] || return 0

  print -- "## $title"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    print -- "- $line"
  done <<<"$lines"
  print
}

render_changelog() {
  local commits="$1"
  local features=""
  local fixes=""
  local maintenance=""
  local line=""

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      feat:\ *) features+="${line#feat: }"$'\n' ;;
      fix:\ *) fixes+="${line#fix: }"$'\n' ;;
      *) maintenance+="${line#*: }"$'\n' ;;
    esac
  done <<<"$commits"

  {
    render_section "Features" "$features"
    render_section "Fixes" "$fixes"
    render_section "Maintenance" "$maintenance"
  }
}

write_changelog_file() {
  local content="$1"
  local output_file="$2"
  print -- "$content" >"$output_file"
}
