#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/common.sh"

label="${1:-}"
if [[ -z "$label" ]]; then
  print -u2 -- "usage: run_by_label.sh <pr|nightly>"
  exit 1
fi

if [[ "$label" != "pr" && "$label" != "nightly" ]]; then
  print -u2 -- "[test-executor] ERROR: invalid label '$label' (expected pr or nightly)"
  exit 1
fi

repo_root="$(executor_repo_root)"
executor_ensure_dirs "$repo_root"
zsh "$SCRIPT_DIR/validate_manifests.sh" >/dev/null

manifests=("${(@f)$(executor_discover_manifests "$repo_root")}")
filtered_manifests=()

for manifest in "${manifests[@]}"; do
  if jq -e --arg label "$label" '.labels | index($label) != null' "$manifest" >/dev/null; then
    filtered_manifests+=("$manifest")
  fi
done

if (( ${#filtered_manifests[@]} == 0 )); then
  print -u2 -- "[test-executor] ERROR: no manifests found for label '$label'"
  exit 1
fi

result_files=()
overall_failed=0

for manifest in "${filtered_manifests[@]}"; do
  suite_id="$(jq -r '.suiteId' "$manifest")"
  suite_label="$label"
  command="$(jq -r '.entry.command' "$manifest")"
  timeout_seconds="$(jq -r '.entry.timeoutSeconds' "$manifest")"
  allow_retry="$(jq -r '.flakyPolicy.allowRetry' "$manifest")"
  max_retries="$(jq -r '.flakyPolicy.maxRetries' "$manifest")"
  retries_allowed=0
  if [[ "$allow_retry" == "true" ]]; then
    retries_allowed="$max_retries"
  fi

  log_file="$(executor_suite_log_file "$repo_root" "$suite_id")"
  result_file="$(executor_suite_result_file "$repo_root" "$suite_id")"
  mkdir -p "$(dirname "$log_file")" "$(dirname "$result_file")"
  : > "$log_file"

  attempts=0
  exit_code=1
  timed_out=false
  duration_seconds=0

  while (( attempts <= retries_allowed )); do
    attempts=$((attempts + 1))
    attempt_json="$(executor_command_runner "$timeout_seconds" "$command" "$log_file")"
    exit_code="$(jq -r '.exitCode' <<<"$attempt_json")"
    timed_out="$(jq -r '.timedOut' <<<"$attempt_json")"
    duration_seconds="$(jq -r '.durationSeconds' <<<"$attempt_json")"

    if [[ "$exit_code" -eq 0 ]]; then
      break
    fi

    if (( attempts <= retries_allowed )); then
      print -- "[test-executor] retrying $suite_id (attempt $attempts/$((retries_allowed + 1)))"
      print -- "--- retry $attempts ---" >>"$log_file"
    fi
  done

  # Validate required artifacts declared by manifest contract.
  suite_artifact_root="$(executor_suite_artifact_dir "$repo_root" "$suite_id")"
  missing_required=0
  while IFS= read -r required_path; do
    [[ -n "$required_path" ]] || continue
    if [[ ! -f "$suite_artifact_root/$required_path" ]]; then
      print -- "[test-executor] missing required artifact: $suite_id -> $required_path" >>"$log_file"
      missing_required=1
    fi
  done < <(jq -r '.artifactsContract.required[]? // empty' "$manifest")

  if [[ "$missing_required" -eq 1 ]]; then
    exit_code=2
  fi

  summary_json="$(executor_suite_summary_json \
    "$suite_id" \
    "$suite_label" \
    "$manifest" \
    "$command" \
    "$timeout_seconds" \
    "$attempts" \
    "$exit_code" \
    "$timed_out" \
    "$duration_seconds" \
    "$log_file")"

  print -r -- "$summary_json" > "$result_file"
  result_files+=("$result_file")

  if [[ "$exit_code" -ne 0 ]]; then
    overall_failed=1
  fi
done

report_file="$(executor_reports_dir "$repo_root")/test-report.json"
jq -s \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    generatedAt: $generatedAt,
    suites: .,
    totals: {
      passed: (map(select(.status == "passed")) | length),
      failed: (map(select(.status == "failed")) | length),
      retried: (map(select(.attempts > 1)) | length)
    }
  }' "${result_files[@]}" > "$report_file"

print -- "[test-executor] report written to $report_file"

if [[ "$overall_failed" -ne 0 ]]; then
  exit 1
fi
