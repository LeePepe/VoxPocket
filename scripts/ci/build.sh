#!/bin/zsh

set -euo pipefail

build_command() {
  local repo_root="$1"
  local derived_data="$2"
  print -- "xcodebuild -project $repo_root/VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket -derivedDataPath $derived_data build"
}

run_build() {
  local repo_root="$1"
  local derived_data="$2"
  local log_file="$3"
  eval "$(build_command "$repo_root" "$derived_data")" >"$log_file" 2>&1
}

collect_app_artifact() {
  local derived_data="$1"
  local destination_dir="$2"
  local app_path="$derived_data/Build/Products/Debug/VoxPocket.app"

  mkdir -p "$destination_dir"
  cp -R "$app_path" "$destination_dir/"
}
