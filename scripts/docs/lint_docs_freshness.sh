#!/bin/zsh

set -euo pipefail

summary_only=0
if [[ "${1:-}" == "--summary-only" ]]; then
  summary_only=1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

files=(
  "AGENTS.md:30"
  "docs/index.md:30"
  "docs/records/index.md:30"
  "docs/harness/metrics-baseline.md:14"
  "README.md:60"
)

failures=0
fresh_count=0
total_count=0

# Cross-platform date parser (BSD/macOS + GNU/Linux)
to_epoch() {
  local d="$1"
  if date -j -f "%Y-%m-%d" "$d" +%s >/dev/null 2>&1; then
    date -j -f "%Y-%m-%d" "$d" +%s
  else
    date -d "$d" +%s
  fi
}

now_epoch="$(date +%s)"

for item in "${files[@]}"; do
  file="${item%%:*}"
  sla_days="${item##*:}"
  total_count=$((total_count + 1))

  if [[ ! -f "$file" ]]; then
    [[ "$summary_only" -eq 1 ]] || print -u2 -- "[docs-freshness] missing file: $file"
    failures=$((failures + 1))
    continue
  fi

  if rg -q '^Freshness-Exempt: true$' "$file"; then
    fresh_count=$((fresh_count + 1))
    continue
  fi

  reviewed_line="$(rg -o '^Last-Reviewed: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$file" | head -n1 || true)"
  if [[ -z "$reviewed_line" ]]; then
    [[ "$summary_only" -eq 1 ]] || print -u2 -- "[docs-freshness] missing Last-Reviewed in $file"
    failures=$((failures + 1))
    continue
  fi

  reviewed_date="${reviewed_line#Last-Reviewed: }"
  reviewed_epoch="$(to_epoch "$reviewed_date" 2>/dev/null || true)"
  if [[ -z "$reviewed_epoch" ]]; then
    [[ "$summary_only" -eq 1 ]] || print -u2 -- "[docs-freshness] invalid Last-Reviewed date in $file: $reviewed_date"
    failures=$((failures + 1))
    continue
  fi

  age_days="$(( (now_epoch - reviewed_epoch) / 86400 ))"
  if [[ "$age_days" -gt "$sla_days" ]]; then
    [[ "$summary_only" -eq 1 ]] || print -u2 -- "[docs-freshness] stale doc: $file (age=$age_days days, sla=$sla_days)"
    failures=$((failures + 1))
    continue
  fi

  fresh_count=$((fresh_count + 1))
done

ratio="N/A"
if [[ "$total_count" -gt 0 ]]; then
  ratio="$(awk -v f="$fresh_count" -v t="$total_count" 'BEGIN { printf "%.6f", f/t }')"
fi

print -- "FRESH_COUNT=$fresh_count"
print -- "TOTAL_COUNT=$total_count"
print -- "FRESHNESS_RATIO=$ratio"

if [[ "$failures" -ne 0 ]]; then
  [[ "$summary_only" -eq 1 ]] || print -u2 -- "[docs-freshness] FAIL ($failures issues)"
  exit 1
fi

[[ "$summary_only" -eq 1 ]] || print -- "[docs-freshness] PASS"
