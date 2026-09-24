#!/usr/bin/env bash
# Check out VoxPocket's external local packages at pinned full SHAs, next to the
# repository root (Packages/* reference ../../../LokiKit; project.yml references
# ../../AppleUITesting). Used by CI; locally it only fills missing directories.
#   scripts/ci/fetch-external-deps.sh [DEST]   (default: parent of the repository)
set -euo pipefail

# LokiKit is published by LeePepe/shared-telemetry (no tag yet; pin = main head).
LOKIKIT_REPO="LeePepe/shared-telemetry"
LOKIKIT_SHA="eff9c1712cd648ed0717e41183ad8bd7bf39cbea"
APPLE_UI_TESTING_REPO="LeePepe/AppleUITesting"
APPLE_UI_TESTING_SHA="e6be2fcdf83341a9f3000a4cc489237655461a07"

root="$(git rev-parse --show-toplevel)"
dest="${1:-$(cd "$root/.." && pwd)}"

fetch() {
    local repo="$1" sha="$2" dir="$dest/$3"
    if [ -e "$dir" ]; then
        local have
        have="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
        if [ "$have" = "$sha" ]; then echo "[deps] $3 at $sha"; return 0; fi
        if [ -n "${CI:-}" ]; then echo "[deps] $dir exists at ${have:-unknown}, expected $sha" >&2; exit 1; fi
        echo "[deps] keeping existing local $3 (${have:-not a git checkout}); CI uses $sha"
        return 0
    fi
    git init -q "$dir"
    git -C "$dir" fetch -q --depth=1 "https://github.com/$repo.git" "$sha"
    git -C "$dir" checkout -q --detach FETCH_HEAD
    [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ] || { echo "[deps] $3 is not $sha" >&2; exit 1; }
    echo "[deps] $3 <- $repo@$sha"
}

fetch "$LOKIKIT_REPO" "$LOKIKIT_SHA" LokiKit
fetch "$APPLE_UI_TESTING_REPO" "$APPLE_UI_TESTING_SHA" AppleUITesting
