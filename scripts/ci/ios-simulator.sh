#!/usr/bin/env bash
# iOS simulator lane (CI, non-required; plan Q13). Builds the multiplatform app for
# the iOS simulator and runs each SPM package's tests on an iOS simulator.
# Every step runs; the script fails if any step failed and prints a summary.
set -uo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"
logs="${IOS_LOG_DIR:-/tmp/ios-simulator}"
mkdir -p "$logs"

udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
runtimes = sorted((k for k in devices if "iOS" in k), reverse=True)
for runtime in runtimes:
    for device in devices[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"]); raise SystemExit
')"
[ -n "$udid" ] || { echo "::error::no available iPhone simulator"; exit 1; }
destination="platform=iOS Simulator,id=$udid"
echo "[ios] destination: $destination"

failures=()
run() {
    local name="$1"; shift
    echo "::group::$name"
    if "$@" >"$logs/$name.log" 2>&1; then echo "[ios] PASS $name"
    else echo "[ios] FAIL $name"; tail -40 "$logs/$name.log"; failures+=("$name"); fi
    echo "::endgroup::"
}

command -v xcodegen >/dev/null || brew install xcodegen >/dev/null
(cd VoxPocket && xcodegen generate --spec project.yml >/dev/null)
run app-build xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket \
    -destination "$destination" CODE_SIGNING_ALLOWED=NO build

# SwiftPM names the aggregate scheme `<Package>-Package` only when a package has several
# products; single-product packages (VoxApplication) use the package name. Pick what exists.
scheme_for() {
    local list
    list="$(cd "Packages/$1" && xcodebuild -list 2>/dev/null)"
    if printf '%s\n' "$list" | grep -qx "        $1-Package"; then echo "$1-Package"; else echo "$1"; fi
}

for package in VoxDomain VoxInfrastructure VoxApplication VoxPresentation VoxUITesting; do
    scheme="$(scheme_for "$package")"
    run "test-$package" bash -c "cd Packages/$package && xcodebuild -scheme '$scheme' \
        -destination '$destination' -skipMacroValidation CODE_SIGNING_ALLOWED=NO test"
done

if [ "${#failures[@]}" -gt 0 ]; then
    echo "::error::iOS simulator lane failed: ${failures[*]}"
    printf '%s\n' "${failures[@]}" >"$logs/failures.txt"
    exit 1
fi
echo "[ios] all iOS simulator steps passed"
