#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
ROOT_DIR=${SCRIPT_DIR:h:h}
ARTIFACT_ROOT="$ROOT_DIR/artifacts/performance"
REPORT_DIR="$ROOT_DIR/artifacts/reports"
RAW_METRICS_FILE="$ARTIFACT_ROOT/raw-metrics.json"
HISTORY_DIR="$ARTIFACT_ROOT/history"

PROJECT_PATH="VoxPocket/VoxPocket.xcodeproj"
SCHEME_NAME="VoxPocket"
DESTINATION="platform=macOS"

MODE=""
DRY_RUN=0

typeset -a XCODEBUILD_CMD

usage() {
  cat <<'EOF'
Usage: zsh scripts/perf/run_perf_suite.sh smoke|full [--dry-run]
EOF
}

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

log() {
  print -- "$*"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_tooling() {
  command_exists jq || fail "jq is required but not installed"
}

ensure_directories() {
  mkdir -p "$ARTIFACT_ROOT" "$REPORT_DIR"
}

join_quoted() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

metric_from_file() {
  local file="$1"
  local expression="$2"

  jq -er "$expression" "$file" 2>/dev/null | head -n 1
}

metric_value() {
  local file="$1"
  local primary="$2"
  local value

  value=$(metric_from_file "$file" "$primary" || true)
  print -r -- "${value:-}"
}

resolve_xcodebuild_command() {
  local test_bundle
  local test_smoke_id
  local test_full_id

  if rg -q "VoxPocketPerformanceTests" "$ROOT_DIR/$PROJECT_PATH"; then
    test_bundle="VoxPocketPerformanceTests"
    test_smoke_id="VoxPocketUITests/${test_bundle}/testLaunchPerformance"
    test_full_id="VoxPocketUITests/${test_bundle}"
  else
    test_bundle="VoxPocketUITests"
    test_smoke_id="VoxPocketUITests/${test_bundle}/testLaunchPerformance"
    test_full_id="VoxPocketUITests/${test_bundle}"
  fi

  if [[ "$MODE" == "smoke" ]]; then
    XCODEBUILD_CMD=(
      xcodebuild test
      -project "$PROJECT_PATH"
      -scheme "$SCHEME_NAME"
      -destination "$DESTINATION"
      -only-testing:"$test_smoke_id"
    )
  else
    XCODEBUILD_CMD=(
      xcodebuild test
      -project "$PROJECT_PATH"
      -scheme "$SCHEME_NAME"
      -destination "$DESTINATION"
      -only-testing:"$test_full_id"
    )
  fi
}

print_thresholds() {
  if [[ "$MODE" == "smoke" ]]; then
    log "Thresholds:"
    log "  startup_p95_seconds <= 4.0"
    log "  first_text_p95_seconds <= 6.0"
  else
    log "Thresholds:"
    log "  startup_p95_seconds <= 3.0"
    log "  first_text_p95_seconds <= 4.5"
    log "  full_transcription_p95_seconds <= 12.0"
    log "  peak_memory_mb <= 1200"
    log "  nightly baseline regression <= 15%"
  fi
}

print_resolved_command() {
  log "Resolved xcodebuild command:"
  join_quoted "${XCODEBUILD_CMD[@]}"
}

read_metrics() {
  [[ -f "$RAW_METRICS_FILE" ]] || fail "missing raw metrics file: $RAW_METRICS_FILE"

  local startup_p95
  local first_text_p95
  local full_transcription_p95
  local peak_memory_mb

  startup_p95=$(metric_value "$RAW_METRICS_FILE" '.startupP95Seconds // .startup_p95_seconds // .startup.p95Seconds // .startup.p95_seconds // .metrics.startupP95Seconds // .metrics.startup_p95_seconds // .metrics.startup.p95Seconds // .metrics.startup.p95_seconds')
  first_text_p95=$(metric_value "$RAW_METRICS_FILE" '.firstTextP95Seconds // .first_text_p95_seconds // .firstText.p95Seconds // .first_text.p95_seconds // .metrics.firstTextP95Seconds // .metrics.first_text_p95_seconds // .metrics.firstText.p95Seconds // .metrics.first_text.p95_seconds')
  full_transcription_p95=$(metric_value "$RAW_METRICS_FILE" '.fullTranscriptionP95Seconds // .full_transcription_p95_seconds // .fullTranscription.p95Seconds // .full_transcription.p95_seconds // .metrics.fullTranscriptionP95Seconds // .metrics.full_transcription_p95_seconds // .metrics.fullTranscription.p95Seconds // .metrics.full_transcription.p95_seconds')
  peak_memory_mb=$(metric_value "$RAW_METRICS_FILE" '.peakMemoryMB // .peak_memory_mb // .peakMemory.mb // .metrics.peakMemoryMB // .metrics.peak_memory_mb // .metrics.peakMemory.mb')

  [[ -n "$startup_p95" ]] || fail "raw metrics missing startup p95 value"
  [[ -n "$first_text_p95" ]] || fail "raw metrics missing first text p95 value"

  if [[ "$MODE" == "full" ]]; then
    [[ -n "$full_transcription_p95" ]] || fail "raw metrics missing full transcription p95 value"
    [[ -n "$peak_memory_mb" ]] || fail "raw metrics missing peak memory value"
  fi

  print -r -- "$startup_p95|$first_text_p95|$full_transcription_p95|$peak_memory_mb"
}

compute_median() {
  local -a sorted
  sorted=("$@")
  sorted=("${(@on)sorted}")

  local count=${#sorted}
  (( count > 0 )) || return 1

  if (( count % 2 == 1 )); then
    print -r -- "${sorted[$(((count + 1) / 2))]}"
  else
    local lower=$((count / 2))
    local upper=$((lower + 1))
    awk -v a="${sorted[$lower]}" -v b="${sorted[$upper]}" 'BEGIN { print (a + b) / 2 }'
  fi
}

median_from_history() {
  local metric_expression="$1"
  local -a samples
  local file

  samples=()
  for file in "$HISTORY_DIR"/*.json(N); do
    [[ -f "$file" ]] || continue
    local value
    value=$(metric_from_file "$file" "$metric_expression" || true)
    [[ -n "$value" ]] && samples+=("$value")
  done

  [[ ${#samples[@]} -gt 0 ]] || return 1
  compute_median "${samples[@]}"
}

evaluate_thresholds() {
  local startup_p95="$1"
  local first_text_p95="$2"
  local full_transcription_p95="$3"
  local peak_memory_mb="$4"

  local failed=0
  local startup_threshold
  local first_text_threshold
  local full_transcription_threshold
  local peak_memory_threshold

  if [[ "$MODE" == "smoke" ]]; then
    startup_threshold=4.0
    first_text_threshold=6.0
    if awk -v v="$startup_p95" -v t="$startup_threshold" 'BEGIN { exit !(v <= t) }'; then :; else failed=1; fi
    if awk -v v="$first_text_p95" -v t="$first_text_threshold" 'BEGIN { exit !(v <= t) }'; then :; else failed=1; fi
  else
    startup_threshold=3.0
    first_text_threshold=4.5
    full_transcription_threshold=12.0
    peak_memory_threshold=1200
    if awk -v v="$startup_p95" -v t="$startup_threshold" 'BEGIN { exit !(v <= t) }'; then :; else failed=1; fi
    if awk -v v="$first_text_p95" -v t="$first_text_threshold" 'BEGIN { exit !(v <= t) }'; then :; else failed=1; fi
    if awk -v v="$full_transcription_p95" -v t="$full_transcription_threshold" 'BEGIN { exit !(v <= t) }'; then :; else failed=1; fi
    if awk -v v="$peak_memory_mb" -v t="$peak_memory_threshold" 'BEGIN { exit !(v <= t) }'; then :; else failed=1; fi
  fi

  local threshold_result="$ARTIFACT_ROOT/perf-threshold-result.json"
  local threshold_summary="$ARTIFACT_ROOT/perf-threshold-summary.txt"

  jq -n \
    --arg mode "$MODE" \
    --arg command "$(join_quoted "${XCODEBUILD_CMD[@]}")" \
    --argjson passed "$(( failed == 0 ))" \
    --arg startup_p95 "$startup_p95" \
    --arg first_text_p95 "$first_text_p95" \
    --arg full_transcription_p95 "$full_transcription_p95" \
    --arg peak_memory_mb "$peak_memory_mb" \
    --argjson startup_threshold "${startup_threshold:-4.0}" \
    --argjson first_text_threshold "${first_text_threshold:-6.0}" \
    --argjson full_transcription_threshold "${full_transcription_threshold:-null}" \
    --argjson peak_memory_threshold "${peak_memory_threshold:-null}" \
    '{
      mode: $mode,
      command: $command,
      passed: $passed,
      metrics: {
        startupP95Seconds: ($startup_p95 | tonumber),
        firstTextP95Seconds: ($first_text_p95 | tonumber),
        fullTranscriptionP95Seconds: (if $full_transcription_p95 == "" then null else ($full_transcription_p95 | tonumber) end),
        peakMemoryMB: (if $peak_memory_mb == "" then null else ($peak_memory_mb | tonumber) end)
      },
      thresholds: {
        startupP95Seconds: $startup_threshold,
        firstTextP95Seconds: $first_text_threshold,
        fullTranscriptionP95Seconds: $full_transcription_threshold,
        peakMemoryMB: $peak_memory_threshold
      }
    }' >"$threshold_result"

  cat >"$threshold_summary" <<EOF
Mode: $MODE
Passed: $(( failed == 0 ))
Startup p95: $startup_p95
First text p95: $first_text_p95
EOF
  if [[ "$MODE" == "full" ]]; then
    cat >>"$threshold_summary" <<EOF
Full transcription p95: $full_transcription_p95
Peak memory MB: $peak_memory_mb
EOF
  fi

  return "$failed"
}

evaluate_baseline() {
  local startup_p95="$1"
  local first_text_p95="$2"
  local full_transcription_p95="$3"
  local peak_memory_mb="$4"

  local baseline_status="no-baseline"
  local baseline_startup=""
  local baseline_first_text=""
  local baseline_full_transcription=""
  local baseline_peak_memory=""
  local diff_failed=0

  local -a history_files
  history_files=("$HISTORY_DIR"/*.json(N))

  if (( ${#history_files[@]} > 0 )); then
    baseline_startup=$(median_from_history '.startupP95Seconds // .startup_p95_seconds // .startup.p95Seconds // .startup.p95_seconds // .metrics.startupP95Seconds // .metrics.startup_p95_seconds // .metrics.startup.p95Seconds // .metrics.startup.p95_seconds' || true)
    baseline_first_text=$(median_from_history '.firstTextP95Seconds // .first_text_p95_seconds // .firstText.p95Seconds // .first_text.p95_seconds // .metrics.firstTextP95Seconds // .metrics.first_text_p95_seconds // .metrics.firstText.p95Seconds // .metrics.firstText.p95_seconds' || true)
    baseline_full_transcription=$(median_from_history '.fullTranscriptionP95Seconds // .full_transcription_p95_seconds // .fullTranscription.p95Seconds // .full_transcription.p95_seconds // .metrics.fullTranscriptionP95Seconds // .metrics.full_transcription_p95_seconds // .metrics.fullTranscription.p95Seconds // .metrics.fullTranscription.p95_seconds' || true)
    baseline_peak_memory=$(median_from_history '.peakMemoryMB // .peak_memory_mb // .peakMemory.mb // .metrics.peakMemoryMB // .metrics.peak_memory_mb // .metrics.peakMemory.mb' || true)
    baseline_status="has-baseline"

    local degrade_pct
    degrade_pct=$(awk -v current="$startup_p95" -v baseline="$baseline_startup" 'BEGIN { if (baseline == 0) { print 0 } else { print ((current - baseline) / baseline) * 100 } }')
    if awk -v v="$degrade_pct" 'BEGIN { exit !(v <= 15) }'; then :; else diff_failed=1; fi

    degrade_pct=$(awk -v current="$first_text_p95" -v baseline="$baseline_first_text" 'BEGIN { if (baseline == 0) { print 0 } else { print ((current - baseline) / baseline) * 100 } }')
    if awk -v v="$degrade_pct" 'BEGIN { exit !(v <= 15) }'; then :; else diff_failed=1; fi

    if [[ "$MODE" == "full" ]]; then
      degrade_pct=$(awk -v current="$full_transcription_p95" -v baseline="$baseline_full_transcription" 'BEGIN { if (baseline == 0) { print 0 } else { print ((current - baseline) / baseline) * 100 } }')
      if awk -v v="$degrade_pct" 'BEGIN { exit !(v <= 15) }'; then :; else diff_failed=1; fi

      degrade_pct=$(awk -v current="$peak_memory_mb" -v baseline="$baseline_peak_memory" 'BEGIN { if (baseline == 0) { print 0 } else { print ((current - baseline) / baseline) * 100 } }')
      if awk -v v="$degrade_pct" 'BEGIN { exit !(v <= 15) }'; then :; else diff_failed=1; fi
    fi
  fi

  jq -n \
    --arg mode "$MODE" \
    --arg baselineStatus "$baseline_status" \
    --arg startup_p95 "$startup_p95" \
    --arg first_text_p95 "$first_text_p95" \
    --arg full_transcription_p95 "$full_transcription_p95" \
    --arg peak_memory_mb "$peak_memory_mb" \
    --arg baseline_startup "$baseline_startup" \
    --arg baseline_first_text "$baseline_first_text" \
    --arg baseline_full_transcription "$baseline_full_transcription" \
    --arg baseline_peak_memory "$baseline_peak_memory" \
    --argjson passed "$(( diff_failed == 0 ))" \
    '{
      mode: $mode,
      baselineStatus: $baselineStatus,
      passed: $passed,
      metrics: {
        startupP95Seconds: ($startup_p95 | tonumber),
        firstTextP95Seconds: ($first_text_p95 | tonumber),
        fullTranscriptionP95Seconds: (if $full_transcription_p95 == "" then null else ($full_transcription_p95 | tonumber) end),
        peakMemoryMB: (if $peak_memory_mb == "" then null else ($peak_memory_mb | tonumber) end)
      },
      baseline: {
        startupP95Seconds: (if $baseline_startup == "" then null else ($baseline_startup | tonumber) end),
        firstTextP95Seconds: (if $baseline_first_text == "" then null else ($baseline_first_text | tonumber) end),
        fullTranscriptionP95Seconds: (if $baseline_full_transcription == "" then null else ($baseline_full_transcription | tonumber) end),
        peakMemoryMB: (if $baseline_peak_memory == "" then null else ($baseline_peak_memory | tonumber) end)
      }
    }' >"$ARTIFACT_ROOT/perf-baseline-diff.json"

  cat >"$ARTIFACT_ROOT/perf-baseline-summary.txt" <<EOF
Mode: $MODE
Baseline status: $baseline_status
Passed: $(( diff_failed == 0 ))
EOF

  return "$diff_failed"
}

main() {
  ensure_tooling

  [[ $# -ge 1 ]] || { usage; fail "missing mode"; }

  MODE="$1"
  shift

  case "$MODE" in
    smoke|full) ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "invalid mode: $MODE" ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown argument: $1"
        ;;
    esac
    shift
  done

  resolve_xcodebuild_command

  log "Performance runner mode: $MODE"
  print_resolved_command
  print_thresholds

  if [[ "$DRY_RUN" -eq 1 ]]; then
    exit 0
  fi

  ensure_directories

  local metrics
  metrics=$(read_metrics)

  local startup_p95
  local first_text_p95
  local full_transcription_p95
  local peak_memory_mb

  IFS='|' read -r startup_p95 first_text_p95 full_transcription_p95 peak_memory_mb <<<"$metrics"

  local threshold_failed=0
  if evaluate_thresholds "$startup_p95" "$first_text_p95" "$full_transcription_p95" "$peak_memory_mb"; then
    threshold_failed=0
  else
    threshold_failed=1
  fi

  local baseline_failed=0
  if [[ "$MODE" == "full" ]]; then
    if evaluate_baseline "$startup_p95" "$first_text_p95" "$full_transcription_p95" "$peak_memory_mb"; then
      baseline_failed=0
    else
      baseline_failed=1
    fi
  fi

  if [[ "$threshold_failed" -ne 0 || "$baseline_failed" -ne 0 ]]; then
    fail "performance gate failed (threshold_failed=$threshold_failed baseline_failed=$baseline_failed)"
  fi

  log "Performance gate passed"
}

main "$@"
