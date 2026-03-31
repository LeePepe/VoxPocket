#!/bin/zsh

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

failures=0

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    print -u2 -- "[docs-map] missing file: $path"
    failures=$((failures + 1))
  fi
}

require_link() {
  local file="$1"
  local pattern="$2"
  if ! rg -q --fixed-strings "$pattern" "$file"; then
    print -u2 -- "[docs-map] missing link in $file: $pattern"
    failures=$((failures + 1))
  fi
}

require_file "AGENTS.md"
require_file "docs/index.md"
require_file "docs/records/index.md"
require_file "docs/harness/metrics-baseline.md"
require_file "docs/records/doc-freshness-policy.md"

if [[ -f "AGENTS.md" ]]; then
  max_lines=140
  lines="$(wc -l < AGENTS.md | tr -d ' ')"
  if [[ "$lines" -gt "$max_lines" ]]; then
    print -u2 -- "[docs-map] AGENTS.md too long: $lines lines (max $max_lines)"
    failures=$((failures + 1))
  fi
fi

if [[ -f "AGENTS.md" ]]; then
  require_link "AGENTS.md" "docs/index.md"
  require_link "AGENTS.md" "docs/records/index.md"
fi

if [[ -f "docs/index.md" ]]; then
  require_link "docs/index.md" "docs/records/index.md"
  require_link "docs/index.md" "AGENTS.md"
fi

if [[ -f "docs/records/index.md" ]]; then
  require_link "docs/records/index.md" "AGENTS.md"
  require_link "docs/records/index.md" "docs/index.md"
  require_link "docs/records/index.md" "docs/harness/metrics-baseline.md"
  require_link "docs/records/index.md" "docs/records/doc-freshness-policy.md"
fi

if [[ "$failures" -ne 0 ]]; then
  print -u2 -- "[docs-map] FAIL ($failures issues)"
  exit 1
fi

print -- "[docs-map] PASS"
