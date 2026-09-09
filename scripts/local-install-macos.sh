#!/usr/bin/env bash
# 本地归档 VoxPocket(macOS)并安装到固定位置,绕开 TestFlight 上传。
#
# 发布用 Release=Manual 签名(App Store profile),会卡在 exportArchive/IPA 上传;
# 本地自用只需 Automatic 签名的 .app —— 归档成功后直接从 .xcarchive 取出 .app 拷走。
#
# 用法:
#   scripts/local-install-macos.sh              # 装到 /Applications
#   INSTALL_DIR=~/Applications scripts/local-install-macos.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/VoxPocket/VoxPocket.xcodeproj"
SCHEME="VoxPocket"
TEAM="4Z8GG667QD"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
ARCHIVE="$REPO_ROOT/build/VoxPocket-macOS.xcarchive"

echo "==> 归档(Debug 配置 = Automatic 签名,天然避开 Release 的 App Store manual profile)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  clean archive

APP_IN_ARCHIVE="$(/usr/bin/find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
if [[ -z "$APP_IN_ARCHIVE" ]]; then
  echo "!! 归档里没找到 .app" >&2
  exit 1
fi

APP_NAME="$(basename "$APP_IN_ARCHIVE")"
DEST="$INSTALL_DIR/$APP_NAME"
echo "==> 安装到 $DEST"
rm -rf "$DEST"
cp -R "$APP_IN_ARCHIVE" "$DEST"

echo "==> 完成。双击运行或:  open \"$DEST\""
