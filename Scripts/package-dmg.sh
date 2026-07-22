#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_PATH="${PROJECT_DIR}/build/CutScreen.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGING_DIR}"' EXIT

if [[ ! -d "${APP_PATH}" ]]; then
  echo "未找到 ${APP_PATH}，请先运行 Scripts/build-app.sh"
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
DMG_PATH="${PROJECT_DIR}/build/CutScreen-${VERSION}.dmg"

cp -R "${APP_PATH}" "${STAGING_DIR}/CutScreen.app"
ln -s /Applications "${STAGING_DIR}/Applications"
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "轻截" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

if [[ "${SIGNING_IDENTITY}" != "-" ]]; then
  codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
  codesign --verify --verbose=2 "${DMG_PATH}"
fi

echo "已生成安装镜像: ${DMG_PATH}"
