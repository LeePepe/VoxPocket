#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
sources="$root/Sources"
all="${root}/Sources ${root}/Tests"
fail=0

scan() {
  local rule="$1"; shift
  local pattern="$1"; shift
  local paths=("$@")
  local hits
  hits="$(grep -RInE --include='*.swift' "$pattern" "${paths[@]}" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    echo "R${rule} violation:"; echo "$hits"; fail=1
  fi
}

run_checks() {
  fail=0
  scan 1 '(ProcessInfo|(^|[^A-Za-z])getenv\(|setenv\(|UserDefaults|@AppStorage|CFPreferences|NSUbiquitousKeyValueStore|Bundle\.main|Bundle\(for:|infoDictionary|SecItem|Data\(contentsOf:|String\(contentsOf:|contentsOfFile|NSDictionary\(contentsOf:|FileHandle\(forReading|InputStream\(|\.urls?\(for:|contents\(atPath:|contentsOfDirectory|applicationSupportDirectory|cachesDirectory|documentDirectory|homeDirectory|NSHomeDirectory|NSTemporaryDirectory|temporaryDirectory|CommandLine|environ\b|URL\(fileURLWithPath:)' "$sources"
  scan 2 'import[[:space:]]+(LokiKit|SharedTelemetry|[A-Za-z]*Telemetry[A-Za-z]*)' "$sources"
  scan 3 '(^|[^A-Za-z])(print|debugPrint|dump)\(|NSLog|os_log|import[[:space:]]+OSLog|Logger\(subsystem' "$sources"
  scan 4 'import[[:space:]]+Combine|\b(Publisher|Subject|Cancellable)\b' "$sources"
  scan 4 'public[[:space:]]+(func|var|init)[^\n]*->|public[[:space:]]+(func|var|init)[^\n]*\([^\n]*\)[^\n]*\([^\n]*\)[[:space:]]*->' "$sources"
  scan 5 'VoxPocket|MY-[0-9]+|https?://[^[:space:]]*\.(services\.ai|openai|cognitiveservices)\.azure\.com' "$all"
  if swift package --package-path "$root" show-dependencies --format json 2>/dev/null | grep -Eiq 'LokiKit|SharedTelemetry'; then
    echo "R2 dependency closure contains forbidden telemetry package"; fail=1
  fi
  if grep -nE '\.package\(path:' "$root/Package.swift" 2>/dev/null | grep -v 'Packages/VoxKit' >/dev/null; then
    echo "R2 Package.swift contains an external path dependency"; fail=1
  fi
  return "$fail"
}

self_test() {
  local rules=(R1 R2 R3a R3b R4a R4b R5)
  for rule in "${rules[@]}"; do
    local negative="$root/scripts/redlines/fixtures/violations/$rule/violation.swift"
    local positive="$root/scripts/redlines/fixtures/ok/$rule/ok.swift"
    [[ -f "$negative" && -f "$positive" ]] || { echo "missing fixture $rule"; return 1; }
    case "$rule" in
      R1) grep -Eq 'UserDefaults' "$negative" && ! grep -Eq 'UserDefaults' "$positive" ;;
      R2) grep -Eq 'import LokiKit' "$negative" && ! grep -Eq 'import LokiKit' "$positive" ;;
      R3a) grep -Eq ': String' "$negative" && ! grep -Eq ': String' "$positive" ;;
      R3b) grep -Eq 'print\(' "$negative" && ! grep -Eq 'print\(' "$positive" ;;
      R4a) grep -Eq 'import Combine' "$negative" && ! grep -Eq 'import Combine' "$positive" ;;
      R4b) grep -Eq 'completion: \(\) -> Void' "$negative" && ! grep -Eq 'completion: \(\) -> Void' "$positive" ;;
      R5) grep -Eq 'VoxPocket|MY-[0-9]+' "$negative" && ! grep -Eq 'VoxPocket|MY-[0-9]+' "$positive" ;;
    esac || { echo "fixture self-test failed: $rule"; return 1; }
    echo "self-test $rule: pass"
  done
  run_checks
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; else run_checks; fi
if [[ "$fail" -ne 0 ]]; then exit 1; fi
echo "VoxKit redlines R1-R5: PASS"
