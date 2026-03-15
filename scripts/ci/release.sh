#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${${(%):-%x}:A:h}" && pwd)
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/version.sh"
source "$SCRIPT_DIR/trigger.sh"
source "$SCRIPT_DIR/changelog.sh"
source "$SCRIPT_DIR/build.sh"
source "$SCRIPT_DIR/release_metadata.sh"

default_bump_for_source() {
  local source="$1"
  if [[ "$source" == "dev" ]]; then
    print -- "minor"
  elif [[ "$source" == hotfix/* ]]; then
    print -- "patch"
  else
    print -u2 -- "unsupported release source: $source"
    return 1
  fi
}

release_tag_for() {
  print -- "v$1"
}

project_file_for_repo() {
  print -- "$1/VoxPocket/VoxPocket.xcodeproj/project.pbxproj"
}

release_pipeline() {
  local repo_root="$1"
  local branch="$2"
  local source="$3"
  local bump_kind="${4:-$(default_bump_for_source "$source")}"
  local worktree_state="dirty"
  local release_root="$repo_root/releases"
  local staging_dir=""
  local final_dir=""
  local project_file=""
  local backup_file=""
  local tag=""

  if is_worktree_clean "$repo_root"; then
    worktree_state="clean"
  fi

  [[ "$(should_run_release "$branch" "$source" "$worktree_state" "merge")" == "yes" ]] || die "release conditions not met"

  project_file="$(project_file_for_repo "$repo_root")"
  backup_file="$project_file.local-ci.bak"
  cp "$project_file" "$backup_file"

  cleanup_release_failure() {
    local exit_code="$?"

    if [[ "$exit_code" -ne 0 ]]; then
      [[ -f "$backup_file" ]] && mv "$backup_file" "$project_file"
      [[ -n "$staging_dir" ]] && rm -rf "$staging_dir"
      [[ -n "$final_dir" ]] && rm -rf "$final_dir"
    else
      rm -f "$backup_file"
    fi

    return "$exit_code"
  }

  trap cleanup_release_failure EXIT

  local current_marketing current_build next_marketing next_build previous_tag commit_subjects rendered_changelog
  current_marketing="$(project_marketing_version "$project_file")"
  current_build="$(project_build_number "$project_file")"
  next_marketing="$(next_marketing_version "$current_marketing" "$bump_kind")"
  next_build="$(next_build_number "$current_build")"
  tag="$(release_tag_for "$next_marketing")"
  previous_tag="$(latest_release_tag "$repo_root")"

  set_project_versions "$project_file" "$next_marketing" "$next_build"

  if [[ -n "$previous_tag" ]]; then
    commit_subjects="$(changelog_from_git_range "$repo_root" "$previous_tag" "HEAD")"
  else
    commit_subjects="$(git -C "$repo_root" log --pretty=%s)"
  fi
  rendered_changelog="$(render_changelog "$commit_subjects")"

  staging_dir="$(stage_release_dir "$repo_root" "$next_marketing")"
  final_dir="$release_root/$tag"
  local changelog_file build_log derived_data
  changelog_file="$staging_dir/CHANGELOG.md"
  build_log="$staging_dir/build.log"
  derived_data="$repo_root/.build/local-ci/$tag"

  write_changelog_file "$rendered_changelog" "$changelog_file"
  run_build "$repo_root" "$derived_data" "$build_log"
  install_release_artifact "$derived_data/Build/Products/Debug/VoxPocket.app" "$staging_dir"
  write_release_metadata "$staging_dir" "$next_marketing" "$tag" "$(git -C "$repo_root" rev-parse HEAD)" "$next_build" "artifacts/VoxPocket.app"
  finalize_release_dir "$staging_dir" "$final_dir"

  git -C "$repo_root" add "$project_file"
  git -C "$repo_root" commit -m "chore: release $tag" >/dev/null
  git -C "$repo_root" tag "$tag"
  trap - EXIT
  rm -f "$backup_file"
}

auto_release() {
  local repo_root branch subject source
  repo_root="$(git rev-parse --show-toplevel)"
  branch="$(current_branch_name "$repo_root")"
  subject="$(head_subject "$repo_root")"
  source="$(merge_source_from_subject "$subject" || true)"
  [[ -n "$source" ]] || return 0
  default_bump_for_source "$source" >/dev/null 2>&1 || return 0
  release_pipeline "$repo_root" "$branch" "$source"
}

main() {
  if [[ "${1:-}" == "--auto" ]]; then
    auto_release
    return 0
  fi

  local repo_root branch source
  repo_root="$(git rev-parse --show-toplevel)"
  branch="${1:-$(current_branch_name "$repo_root")}"
  source="${2:-dev}"
  release_pipeline "$repo_root" "$branch" "$source"
}

if [[ "${VOX_CI_SOURCE_ONLY:-0}" != "1" && "${${(%):-%x}:A}" == "${0:A}" ]]; then
  main "$@"
fi
