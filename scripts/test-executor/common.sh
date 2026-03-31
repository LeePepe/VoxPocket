#!/bin/zsh

set -euo pipefail

executor_repo_root() {
  git rev-parse --show-toplevel
}

executor_artifact_root() {
  local repo_root="$1"
  print -- "$repo_root/artifacts"
}

executor_reports_dir() {
  local repo_root="$1"
  print -- "$(executor_artifact_root "$repo_root")/reports"
}

executor_suites_dir() {
  local repo_root="$1"
  print -- "$(executor_artifact_root "$repo_root")/suites"
}

executor_manifest_dir() {
  local repo_root="$1"
  print -- "$repo_root/tests/manifests"
}

executor_discover_manifests() {
  local repo_root="$1"
  setopt localoptions null_glob

  local -a manifests=("$repo_root"/tests/manifests/*.tests.manifest.json)
  if (( ${#manifests[@]} == 0 )); then
    print -u2 -- "[test-executor] ERROR: no manifests found under tests/manifests/"
    return 1
  fi

  printf '%s\n' "${manifests[@]}"
}

executor_suite_artifact_dir() {
  local repo_root="$1"
  local suite_id="$2"
  print -- "$(executor_suites_dir "$repo_root")/$suite_id"
}

executor_suite_log_file() {
  local repo_root="$1"
  local suite_id="$2"
  print -- "$(executor_suite_artifact_dir "$repo_root" "$suite_id")/logs/test.log"
}

executor_suite_result_file() {
  local repo_root="$1"
  local suite_id="$2"
  print -- "$(executor_reports_dir "$repo_root")/suites/$suite_id.json"
}

executor_ensure_dirs() {
  local repo_root="$1"
  mkdir -p \
    "$(executor_artifact_root "$repo_root")" \
    "$(executor_reports_dir "$repo_root")" \
    "$(executor_reports_dir "$repo_root")/suites" \
    "$(executor_suites_dir "$repo_root")"
}

executor_json_escape() {
  jq -Rrs '.'
}

executor_command_runner() {
  local timeout_seconds="$1"
  local command="$2"
  local log_file="$3"

  python3 - "$timeout_seconds" "$command" "$log_file" <<'PY'
import json
import os
import signal
import subprocess
import sys
import time

timeout = float(sys.argv[1])
command = sys.argv[2]
log_file = sys.argv[3]

os.makedirs(os.path.dirname(log_file), exist_ok=True)

start = time.monotonic()
timed_out = False
exit_code = 0

with open(log_file, "a", encoding="utf-8") as log:
    log.write(f"[test-executor] command: {command}\n")
    log.flush()
    proc = subprocess.Popen(
        ["/bin/zsh", "-lc", command],
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        exit_code = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            exit_code = proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            exit_code = proc.wait()

duration = time.monotonic() - start
print(json.dumps({
    "exitCode": 124 if timed_out else exit_code,
    "timedOut": timed_out,
    "durationSeconds": round(duration, 3),
}))
PY
}

executor_suite_summary_json() {
  local suite_id="$1"
  local label="$2"
  local manifest_file="$3"
  local command="$4"
  local timeout_seconds="$5"
  local attempts="$6"
  local exit_code="$7"
  local timed_out="$8"
  local duration_seconds="$9"
  local log_file="${10}"

  local suite_status="failed"
  if [[ "$exit_code" -eq 0 ]]; then
    suite_status="passed"
  fi

  jq -n \
    --arg suiteId "$suite_id" \
    --arg label "$label" \
    --arg manifestFile "$manifest_file" \
    --arg command "$command" \
    --argjson timeoutSeconds "$timeout_seconds" \
    --argjson attempts "$attempts" \
    --argjson exitCode "$exit_code" \
    --argjson timedOut "$timed_out" \
    --argjson durationSeconds "$duration_seconds" \
    --arg logFile "$log_file" \
    --arg status "$suite_status" \
    '{
      suiteId: $suiteId,
      label: $label,
      manifestFile: $manifestFile,
      command: $command,
      timeoutSeconds: $timeoutSeconds,
      attempts: $attempts,
      exitCode: $exitCode,
      timedOut: $timedOut,
      durationSeconds: $durationSeconds,
      logFile: $logFile,
      status: $status
    }'
}
