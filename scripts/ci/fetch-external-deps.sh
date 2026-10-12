#!/usr/bin/env bash
# Check out AppleUITesting at its pinned full SHA next to the repository root
# (project.yml references ../../AppleUITesting). Used by CI; locally it only fills
# missing directories. LokiKit is resolved by SwiftPM from shared-telemetry pinned to
# commit 5f4b4d97d7ad05adb849e0d8937c8745d9b6d15f (v0.1.0).
#   scripts/ci/fetch-external-deps.sh [DEST]   (default: parent of the repository)
set -euo pipefail

LOKIKIT_REPO="LeePepe/shared-telemetry"
LOKIKIT_TAG="v0.1.0"
LOKIKIT_SHA="5f4b4d97d7ad05adb849e0d8937c8745d9b6d15f"

APPLE_UI_TESTING_REPO="LeePepe/AppleUITesting"
APPLE_UI_TESTING_SHA="e6be2fcdf83341a9f3000a4cc489237655461a07"

root="$(git rev-parse --show-toplevel)"
# Never let an inherited GIT_DIR (hooks) redirect the dependency checkouts into this repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX
dest="${1:-$(cd "$root/.." && pwd)}"

# Manifests pin the full commit SHA; this guard fails if the tag is ever retargeted.
# Package.resolved is gitignored per repo policy.
verify_lokikit_tag() {
    local refs sha ref peeled="" plain="" actual
    if ! refs="$(git ls-remote "https://github.com/$LOKIKIT_REPO.git" "refs/tags/$LOKIKIT_TAG^{}" "refs/tags/$LOKIKIT_TAG")"; then
        refs=""
    fi
    while read -r sha ref; do
        case "$ref" in
            "refs/tags/$LOKIKIT_TAG^{}") peeled="$sha" ;;
            "refs/tags/$LOKIKIT_TAG") plain="$sha" ;;
        esac
    done <<< "$refs"
    actual="${peeled:-$plain}"
    if [ -z "$actual" ]; then
        if [ -n "${CI+x}" ]; then
            echo "[deps] error: cannot verify LokiKit $LOKIKIT_TAG from $LOKIKIT_REPO" >&2
            exit 1
        fi
        echo "[deps] warning: cannot verify LokiKit $LOKIKIT_TAG from $LOKIKIT_REPO; continuing locally" >&2
        return 0
    fi
    if [ "$actual" != "$LOKIKIT_SHA" ]; then
        echo "[deps] error: LokiKit $LOKIKIT_TAG is $actual, expected $LOKIKIT_SHA" >&2
        exit 1
    fi
    echo "[deps] LokiKit $LOKIKIT_TAG -> $LOKIKIT_SHA"
}

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

verify_lokikit_tag
fetch "$APPLE_UI_TESTING_REPO" "$APPLE_UI_TESTING_SHA" AppleUITesting
