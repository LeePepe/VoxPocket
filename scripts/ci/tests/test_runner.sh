#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)

# Pattern-discover sorted *_tests.sh suites, excluding helpers and test_runner.sh itself
typeset -a test_suites
for suite in "$SCRIPT_DIR"/*_tests.sh(N.on); do
  suite_name="${suite:t}"
  if [[ "$suite_name" == "helpers.sh" || "$suite_name" == "test_runner.sh" ]]; then
    continue
  fi
  test_suites+=("$suite")
done

if (( ${#test_suites[@]} == 0 )); then
  print -u2 -- "ERROR: No test suites matching *_tests.sh found in $SCRIPT_DIR"
  exit 1
fi

print -- "Discovered ${#test_suites[@]} test suites:"
for suite in "${test_suites[@]}"; do
  print -- "  $suite"
done

for suite in "${test_suites[@]}"; do
  print -- "Running suite: $suite"
  zsh "$suite"
done
