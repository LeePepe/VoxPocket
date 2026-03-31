#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/common.sh"

repo_root="$(executor_repo_root)"
manifests=("${(@f)$(executor_discover_manifests "$repo_root")}")

typeset -A seen_suite_ids

for manifest in "${manifests[@]}"; do
  suite_id="$(jq -r '.suiteId' "$manifest")"
  labels_length="$(jq -r '.labels | length' "$manifest")"
  label_value="$(jq -r '.labels[0] // empty' "$manifest")"
  allow_retry="$(jq -r '.flakyPolicy.allowRetry' "$manifest")"
  max_retries="$(jq -r '.flakyPolicy.maxRetries' "$manifest")"

  if [[ -z "$suite_id" || "$suite_id" == "null" ]]; then
    print -u2 -- "[test-executor] ERROR: missing suiteId in $manifest"
    exit 1
  fi

  if [[ -n "${seen_suite_ids[$suite_id]:-}" ]]; then
    print -u2 -- "[test-executor] ERROR: duplicate suiteId '$suite_id' in $manifest and ${seen_suite_ids[$suite_id]}"
    exit 1
  fi
  seen_suite_ids[$suite_id]="$manifest"

  if [[ "$labels_length" -ne 1 ]]; then
    print -u2 -- "[test-executor] ERROR: $manifest must declare exactly one label"
    exit 1
  fi

  if [[ "$label_value" != "pr" && "$label_value" != "nightly" ]]; then
    print -u2 -- "[test-executor] ERROR: $manifest label must be pr or nightly, got '$label_value'"
    exit 1
  fi

  if [[ "$allow_retry" == "false" && "$max_retries" -ne 0 ]]; then
    print -u2 -- "[test-executor] ERROR: $manifest has allowRetry=false but maxRetries=$max_retries"
    exit 1
  fi
done

print -- "[test-executor] validated ${#manifests[@]} manifests"

