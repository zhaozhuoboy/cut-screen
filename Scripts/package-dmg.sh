#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_PATH="${PROJECT_DIR}/build/CutScreen.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
WORK_DIR="$(mktemp -d)"
STAGING_DIR="${WORK_DIR}/staging"
RW_DMG_PATH="${WORK_DIR}/CutScreen-rw.dmg"
MOUNT_POINT="${WORK_DIR}/mount"
ATTACHED_DEVICE=""

cleanup() {
  if [[ -n "${ATTACHED_DEVICE}" ]]; then
    hdiutil detach "${ATTACHED_DEVICE}" -force >/dev/null 2>&1 || true
  fi
  if [[ -d "${WORK_DIR}" ]]; then
    rm -rf "${WORK_DIR}"
  fi
}
trap cleanup EXIT

if [[ ! -d "${APP_PATH}" ]]; then
  echo "未找到 ${APP_PATH}，请先运行 Scripts/build-app.sh"
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
DMG_PATH="${PROJECT_DIR}/build/CutScreen-${VERSION}.dmg"
VOLUME_NAME="轻截"

mkdir -p "${STAGING_DIR}/.background" "${MOUNT_POINT}"
cp -R "${APP_PATH}" "${STAGING_DIR}/CutScreen.app"
ln -s /Applications "${STAGING_DIR}/Applications"
touch "${STAGING_DIR}/.metadata_never_index"
xcrun swift \
  "${PROJECT_DIR}/Scripts/generate-dmg-background.swift" \
  "${STAGING_DIR}/.background/background.png" \
  "${PROJECT_DIR}/Resources/AppIcon-1024.png"

STAGING_SIZE_KB="$(du -sk "${STAGING_DIR}" | awk '{print $1}')"
DMG_SIZE_MB="$((STAGING_SIZE_KB / 1024 + 24))"
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -fs HFS+ \
  -size "${DMG_SIZE_MB}m" \
  -ov \
  -format UDRW \
  "${RW_DMG_PATH}"

ATTACH_OUTPUT="$(hdiutil attach \
  "${RW_DMG_PATH}" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "${MOUNT_POINT}")"
ATTACHED_DEVICE="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk '/Apple_HFS/ {print $1; exit}')"
if [[ -z "${ATTACHED_DEVICE}" ]]; then
  echo "无法挂载临时 DMG"
  exit 1
fi

osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to folder (POSIX file "${MOUNT_POINT}" as alias)
  open dmgFolder
  set dmgWindow to container window of dmgFolder
  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set pathbar visible of dmgWindow to false
  set bounds of dmgWindow to {100, 100, 820, 562}

  set viewOptions to icon view options of dmgWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 96
  set text size of viewOptions to 13
  set label position of viewOptions to bottom
  set background picture of viewOptions to file ".background:background.png" of dmgFolder

  set position of item "CutScreen.app" of dmgFolder to {190, 226}
  set position of item "Applications" of dmgFolder to {530, 226}
  update dmgFolder without registering applications
  delay 2
  close dmgWindow
end tell
APPLESCRIPT

sync
hdiutil detach "${ATTACHED_DEVICE}"
ATTACHED_DEVICE=""

hdiutil convert \
  "${RW_DMG_PATH}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "${DMG_PATH}"

if [[ "${SIGNING_IDENTITY}" != "-" ]]; then
  codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
  codesign --verify --verbose=2 "${DMG_PATH}"
fi

echo "已生成安装镜像: ${DMG_PATH}"
