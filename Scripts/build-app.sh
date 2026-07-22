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
BUILD_ARCHS="${BUILD_ARCHS:-native}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"

cd "${PROJECT_DIR}"

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"

if [[ "${BUILD_ARCHS}" == "universal" ]]; then
  typeset -a ARCH_BINARIES
  for ARCH in arm64 x86_64; do
    SCRATCH_PATH="${PROJECT_DIR}/.build/${CONFIGURATION}-${ARCH}"
    TARGET_TRIPLE="${ARCH}-apple-macosx${MACOS_DEPLOYMENT_TARGET}"
    swift build \
      --scratch-path "${SCRATCH_PATH}" \
      -c "${CONFIGURATION}" \
      --triple "${TARGET_TRIPLE}"
    BIN_DIR="$(swift build \
      --scratch-path "${SCRATCH_PATH}" \
      -c "${CONFIGURATION}" \
      --triple "${TARGET_TRIPLE}" \
      --show-bin-path)"
    ARCH_BINARIES+=("${BIN_DIR}/${APP_NAME}")
  done
  lipo -create "${ARCH_BINARIES[@]}" -output "${CONTENTS_DIR}/MacOS/${APP_NAME}"
elif [[ "${BUILD_ARCHS}" == "native" ]]; then
  swift build -c "${CONFIGURATION}"
  BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"
  cp "${BIN_DIR}/${APP_NAME}" "${CONTENTS_DIR}/MacOS/${APP_NAME}"
else
  echo "不支持的 BUILD_ARCHS=${BUILD_ARCHS}，请使用 native 或 universal"
  exit 1
fi

cp "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${CONTENTS_DIR}/Resources/AppIcon.icns"
cp -R "${PROJECT_DIR}/Resources/ToolbarIcons" "${CONTENTS_DIR}/Resources/ToolbarIcons"
chmod 755 "${CONTENTS_DIR}/MacOS/${APP_NAME}"

plutil -lint "${CONTENTS_DIR}/Info.plist"
typeset -a TIMESTAMP_ARGUMENT
if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  TIMESTAMP_ARGUMENT=(--timestamp=none)
else
  TIMESTAMP_ARGUMENT=(--timestamp)
fi
codesign \
  --force \
  --deep \
  --options runtime \
  "${TIMESTAMP_ARGUMENT[@]}" \
  --entitlements "${PROJECT_DIR}/Resources/CutScreen.entitlements" \
  --sign "${SIGNING_IDENTITY}" \
  "${APP_DIR}"

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
echo "已生成 ${DISPLAY_NAME}: ${APP_DIR}"
