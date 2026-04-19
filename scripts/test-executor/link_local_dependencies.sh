#!/bin/zsh

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
workspace_root="$(cd "$repo_root/.." && pwd -P)"
local_deps_root="${LOCAL_DEPS_ROOT:-/Users/tianpli/Development}"

link_dependency() {
  local name="$1"
  local source_dir="$local_deps_root/$name"
  local target_path="$workspace_root/$name"

  if [[ ! -d "$source_dir" ]]; then
    print -u2 -- "[local-deps] missing source directory: $source_dir"
    exit 1
  fi

  local source_real
  source_real="$(cd "$source_dir" && pwd -P)"

  if [[ -e "$target_path" && ! -L "$target_path" ]]; then
    local target_real
    target_real="$(cd "$target_path" && pwd -P 2>/dev/null || true)"
    if [[ "$target_real" == "$source_real" ]]; then
      print -- "[local-deps] $name already available at $target_path"
      return 0
    fi

    local package_name=""
    if [[ -f "$target_path/Package.swift" ]]; then
      package_name="$(python3 - "$target_path/Package.swift" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(errors='ignore')
m = re.search(r'name:\s*"([^"]+)"', text)
print(m.group(1) if m else '')
PY
)"
    fi

    if [[ "$package_name" == "$name" ]]; then
      rm -rf "$target_path"
      print -- "[local-deps] replaced existing $name checkout at $target_path"
    else
      print -u2 -- "[local-deps] target exists and is not a matching symlink or package checkout: $target_path"
      exit 1
    fi
  fi

  ln -sfn "$source_dir" "$target_path"
  print -- "[local-deps] linked $target_path -> $source_dir"
}

link_dependency "AppleUITesting"
link_dependency "LokiKit"
