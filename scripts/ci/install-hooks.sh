#!/bin/zsh

set -euo pipefail

print_install_command() {
  print -- "git config core.hooksPath .githooks"
}

main() {
  if [[ "${1:-}" == "--print-command" ]]; then
    print_install_command
    return 0
  fi

  eval "$(print_install_command)"
}

main "$@"
