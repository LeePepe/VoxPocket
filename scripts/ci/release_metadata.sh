#!/bin/zsh

set -euo pipefail

stage_release_dir() {
  local root="$1"
  local version="$2"
  local staging_dir="$root/.release-staging/v$version"
  mkdir -p "$staging_dir/artifacts"
  print -- "$staging_dir"
}

install_release_artifact() {
  local artifact_source="$1"
  local release_dir="$2"
  mkdir -p "$release_dir/artifacts"
  cp -R "$artifact_source" "$release_dir/artifacts/"
}

write_release_metadata() {
  local release_dir="$1"
  local version="$2"
  local tag="$3"
  local commit="$4"
  local build_number="$5"
  local artifact_path="$6"

  cat >"$release_dir/release.json" <<EOF
{
  "version": "$version",
  "tag": "$tag",
  "commit": "$commit",
  "build": "$build_number",
  "artifact": "$artifact_path"
}
EOF
}

finalize_release_dir() {
  local staging_dir="$1"
  local final_dir="$2"
  mkdir -p "${final_dir:h}"
  rm -rf "$final_dir"
  mv "$staging_dir" "$final_dir"
}
