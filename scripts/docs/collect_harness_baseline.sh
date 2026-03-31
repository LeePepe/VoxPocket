#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  zsh scripts/docs/collect_harness_baseline.sh --window-start YYYY-MM-DD --window-end YYYY-MM-DD [--dry-run]
USAGE
}

window_start=""
window_end=""
dry_run=0

while (( $# > 0 )); do
  case "$1" in
    --window-start)
      window_start="${2:-}"
      shift 2
      ;;
    --window-end)
      window_end="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print -u2 -- "[harness-baseline] unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$window_start" || -z "$window_end" ]]; then
  print -u2 -- "[harness-baseline] --window-start and --window-end are required"
  usage
  exit 1
fi

if ! [[ "$window_start" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' && "$window_end" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ]]; then
  print -u2 -- "[harness-baseline] invalid date format, expected YYYY-MM-DD"
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
snapshot_date="$(date +%Y-%m-%d)"
out_file="$repo_root/artifacts/harness/metrics/${snapshot_date}.snapshot.json"

rerun_value="null"
rerun_reason="no_test_report_found"

report_file="$repo_root/artifacts/reports/test-report.json"
if [[ -f "$report_file" ]]; then
  total_suites="$(jq -r '.suites | length' "$report_file" 2>/dev/null || print "0")"
  retried="$(jq -r '.totals.retried // 0' "$report_file" 2>/dev/null || print "0")"
  if [[ "$total_suites" =~ '^[0-9]+$' && "$retried" =~ '^[0-9]+$' && "$total_suites" -gt 0 ]]; then
    rerun_value="$(awk -v r="$retried" -v t="$total_suites" 'BEGIN { printf "%.6f", r/t }')"
    rerun_reason="null"
  else
    rerun_reason="test_report_missing_fields"
  fi
fi

doc_freshness_value="null"
doc_freshness_reason="freshness_lint_not_run"
if [[ -x "$repo_root/scripts/docs/lint_docs_freshness.sh" ]]; then
  freshness_output="$(zsh "$repo_root/scripts/docs/lint_docs_freshness.sh" --summary-only || true)"
  freshness_ratio="$(print -- "$freshness_output" | awk -F'=' '/^FRESHNESS_RATIO=/{print $2}' | tail -n1)"
  if [[ -n "$freshness_ratio" && "$freshness_ratio" != "N/A" ]]; then
    doc_freshness_value="$freshness_ratio"
    doc_freshness_reason="null"
  fi
fi

snapshot_json="$(jq -n \
  --arg generatedAt "$generated_at" \
  --arg ws "$window_start" \
  --arg we "$window_end" \
  --argjson rerunValue "$rerun_value" \
  --arg rerunReason "$rerun_reason" \
  --argjson docFreshnessValue "$doc_freshness_value" \
  --arg docFreshnessReason "$doc_freshness_reason" \
  '{
    generatedAt: $generatedAt,
    window: { start: $ws, end: $we },
    metrics: {
      prCycleHours: {
        value: null,
        source: "github.pull_requests",
        reason: "not_collected_in_local_scaffold"
      },
      rerunRate: {
        value: $rerunValue,
        source: "artifacts/reports/test-report.json",
        reason: (if $rerunReason == "null" then null else $rerunReason end)
      },
      docFreshness: {
        value: $docFreshnessValue,
        source: "scripts/docs/lint_docs_freshness.sh",
        reason: (if $docFreshnessReason == "null" then null else $docFreshnessReason end)
      },
      archViolationCount: {
        value: null,
        source: "artifacts/harness/architecture/latest.json",
        reason: "phase_2_structure_lint_not_available"
      }
    },
    notes: [
      "Phase 0 scaffold snapshot",
      "null values are expected until upstream collection is wired"
    ]
  }')"

if [[ "$dry_run" -eq 1 ]]; then
  print -- "$snapshot_json"
  print -- "[harness-baseline] dry-run: no file written"
  exit 0
fi

mkdir -p "$(dirname "$out_file")"
print -- "$snapshot_json" > "$out_file"
print -- "[harness-baseline] snapshot written: $out_file"
