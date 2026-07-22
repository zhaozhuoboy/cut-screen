#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="CutScreen"
DISPLAY_NAME="轻截"
BUILD_DIR="${PROJECT_DIR}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

cd "${PROJECT_DIR}"
swift build -c "${CONFIGURATION}"
BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${CONTENTS_DIR}/MacOS/${APP_NAME}"
cp "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${CONTENTS_DIR}/Resources/AppIcon.icns"
cp -R "${PROJECT_DIR}/Resources/ToolbarIcons" "${CONTENTS_DIR}/Resources/ToolbarIcons"
chmod 755 "${CONTENTS_DIR}/MacOS/${APP_NAME}"

plutil -lint "${CONTENTS_DIR}/Info.plist"
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp=none \
  --entitlements "${PROJECT_DIR}/Resources/CutScreen.entitlements" \
  --sign "${SIGNING_IDENTITY}" \
  "${APP_DIR}"

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
echo "已生成 ${DISPLAY_NAME}: ${APP_DIR}"
