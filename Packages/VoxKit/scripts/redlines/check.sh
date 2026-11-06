#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$root/scripts/redlines/module-map.py"
exec python3 "$root/scripts/redlines/redlines_check.py" "$root" "$@"
