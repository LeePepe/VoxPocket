#!/usr/bin/env bash
# Build a Release macOS VoxPocket.app from main and install it to /Applications/VoxPocket.app,
# then relaunch the app so merges to main are immediately live on the local Mac.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

APP_DST="${VOXPOCKET_INSTALL_PATH:-/Applications/VoxPocket.app}"
BUNDLE_ID="com.leepepe.voxpocket"
TMP_DD="$(mktemp -d "${TMPDIR:-/tmp}/voxpocket-fixed-build.XXXXXX")"
ENTITLEMENTS_TMP="$(mktemp "${TMPDIR:-/tmp}/voxpocket-fixed-entitlements.XXXXXX.plist")"
PRODUCTS="$TMP_DD/Build/Products/Release"

PBXPROJ_PATH="$REPO_ROOT/VoxPocket/VoxPocket.xcodeproj/project.pbxproj"
PBXPROJ_BACKUP="$(mktemp "${TMPDIR:-/tmp}/voxpocket-pbxproj-backup.XXXXXX")"
HAD_PBXPROJ=0
if [ -f "$PBXPROJ_PATH" ]; then
  HAD_PBXPROJ=1
  cp -p "$PBXPROJ_PATH" "$PBXPROJ_BACKUP"
fi

cleanup() {
  if [ "$HAD_PBXPROJ" -eq 1 ] && [ -f "$PBXPROJ_BACKUP" ]; then
    cp -p "$PBXPROJ_BACKUP" "$PBXPROJ_PATH" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DD" "$ENTITLEMENTS_TMP" "$PBXPROJ_BACKUP"
}
trap cleanup EXIT

if [ -x "$REPO_ROOT/scripts/ci/fetch-external-deps.sh" ]; then
  "$REPO_ROOT/scripts/ci/fetch-external-deps.sh"
fi

echo "[install-fixed] generating VoxPocket.xcodeproj via XcodeGen"
(cd "$REPO_ROOT/VoxPocket" && xcodegen generate --spec project.yml)

echo "[install-fixed] building Release macOS VoxPocket.app → $TMP_DD"
xcodebuild \
  -project "$REPO_ROOT/VoxPocket/VoxPocket.xcodeproj" \
  -scheme VoxPocket \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$TMP_DD" \
  OBJROOT="$TMP_DD/Build/Intermediates.noindex" \
  SYMROOT="$TMP_DD/Build/Products" \
  CONFIGURATION_BUILD_DIR="$PRODUCTS" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_SRC="$PRODUCTS/VoxPocket.app"
if [ ! -d "$APP_SRC" ]; then
  echo "[install-fixed] ERROR: built app bundle not found at $APP_SRC" >&2
  exit 1
fi

python3 "$REPO_ROOT/scripts/gates/check_private_config.py" --bundle "$APP_SRC"

cat > "$ENTITLEMENTS_TMP" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.automation.apple-events</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
</dict>
</plist>
PLIST

echo "[install-fixed] signing VoxPocket.app (inside-out ad-hoc with sandbox + audio entitlements)"
p1_list="$(mktemp)"
find "$APP_SRC/Contents" -type f \( -perm +111 -o -name "*.dylib" \) \
  ! -path "$APP_SRC/Contents/MacOS/VoxPocket" \
  -print0 > "$p1_list"

while IFS= read -r -d '' leaf; do
  filetype="$(/usr/bin/file -b "$leaf")"
  case "$filetype" in
    *Mach-O*)
      codesign --force --sign - --entitlements "$ENTITLEMENTS_TMP" "$leaf"
      ;;
  esac
done < "$p1_list"
rm -f "$p1_list"

p2_list="$(mktemp)"
find "$APP_SRC/Contents" -depth -type d \
  \( -name "*.xpc" -o -name "*.appex" -o -name "*.app" -o -name "*.framework" \) \
  -print0 > "$p2_list"

while IFS= read -r -d '' bundle; do
  codesign --force --sign - --entitlements "$ENTITLEMENTS_TMP" "$bundle"
done < "$p2_list"
rm -f "$p2_list"

codesign --force --sign - --entitlements "$ENTITLEMENTS_TMP" "$APP_SRC"
codesign --verify --deep --strict "$APP_SRC"

if [ "${VOXPOCKET_BUILD_ONLY:-0}" = "1" ]; then
  echo "[install-fixed] VOXPOCKET_BUILD_ONLY=1 set; verified bundle at $APP_SRC"
  exit 0
fi

echo "[install-fixed] stopping existing $BUNDLE_ID instance (if running)"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5; do
  pids="$(pgrep -x VoxPocket || true)"
  [ -z "$pids" ] && break
  sleep 0.4
done
for pid in $(pgrep -x VoxPocket || true); do
  kill "$pid" >/dev/null 2>&1 || true
done

echo "[install-fixed] installing to $APP_DST"
STAGE_DST="${APP_DST}.staging.$$"
rm -rf "$STAGE_DST"
ditto "$APP_SRC" "$STAGE_DST"
rm -rf "$APP_DST"
mv "$STAGE_DST" "$APP_DST"

if [ "${VOXPOCKET_NO_RELAUNCH:-0}" != "1" ]; then
  echo "[install-fixed] launching $APP_DST"
  open -a "$APP_DST" || true
fi

echo "[install-fixed] ✅ installed $APP_DST"
