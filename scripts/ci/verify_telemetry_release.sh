#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/voxpocket-telemetry-release.XXXXXX")"
trap 'rm -rf "$DERIVED_DATA"' EXIT

SYNTHETIC_ENDPOINT="https://telemetry.example.invalid/container"
SYNTHETIC_SAS="sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake%2Bonly%2F%3D"

fail() {
  printf 'Synthetic telemetry Release verification failed: %s\n' "$1" >&2
  exit 1
}

(
  cd "$REPO_ROOT/VoxPocket"
  xcodegen generate --spec project.yml
)

xcodebuild \
  -project "$REPO_ROOT/VoxPocket/VoxPocket.xcodeproj" \
  -scheme VoxPocket \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  "TELEMETRY_BLOB_ENDPOINT=$SYNTHETIC_ENDPOINT" \
  "TELEMETRY_BLOB_SAS=$SYNTHETIC_SAS" \
  build

PROCESSED_PLIST="$DERIVED_DATA/Build/Products/Release/VoxPocket.app/Contents/Info.plist"
[[ -f "$PROCESSED_PLIST" ]] || fail "processed Info.plist is missing"

endpoint=$(/usr/libexec/PlistBuddy -c "Print :LokiKitBlobEndpoint" "$PROCESSED_PLIST" 2>/dev/null) ||
  fail "LokiKitBlobEndpoint is missing from the processed plist"
sas=$(/usr/libexec/PlistBuddy -c "Print :LokiKitBlobSAS" "$PROCESSED_PLIST" 2>/dev/null) ||
  fail "LokiKitBlobSAS is missing from the processed plist"

PROCESSED_XML="$DERIVED_DATA/processed-info.plist"
plutil -convert xml1 -o "$PROCESSED_XML" "$PROCESSED_PLIST"
if grep -Fq '$(' "$PROCESSED_XML"; then
  fail "processed plist contains an unresolved build setting"
fi

[[ "$endpoint" == "$SYNTHETIC_ENDPOINT" ]] ||
  fail "LokiKitBlobEndpoint does not match the synthetic setting"
[[ "$sas" == "$SYNTHETIC_SAS" ]] ||
  fail "LokiKitBlobSAS does not match the synthetic setting"

printf 'Synthetic telemetry Release plist verified.\n'
