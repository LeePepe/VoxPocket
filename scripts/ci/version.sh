#!/bin/zsh

set -euo pipefail

next_marketing_version() {
  local current="$1"
  local bump="$2"
  local major minor patch
  IFS=. read -r major minor patch <<<"$current"

  case "$bump" in
    major) print -- "$((major + 1)).0.0" ;;
    minor) print -- "$major.$((minor + 1)).0" ;;
    patch) print -- "$major.$minor.$((patch + 1))" ;;
    *) print -u2 -- "unsupported bump kind: $bump"; return 1 ;;
  esac
}

next_build_number() {
  print -- "$(($1 + 1))"
}

project_marketing_version() {
  local project_file="$1"
  sed -n 's/.*MARKETING_VERSION = \([0-9][0-9.]*\);/\1/p' "$project_file" | head -n 1
}

project_build_number() {
  local project_file="$1"
  sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\);/\1/p' "$project_file" | head -n 1
}

set_project_versions() {
  local project_file="$1"
  local marketing_version="$2"
  local build_number="$3"

  perl -0pi -e "s/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = $marketing_version;/g; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $build_number;/g" "$project_file"
}
