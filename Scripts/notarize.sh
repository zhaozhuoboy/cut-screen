#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/Resources/Info.plist")"
DMG_PATH="${1:-${PROJECT_DIR}/build/CutScreen-${VERSION}.dmg}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "${NOTARY_PROFILE}" ]]; then
  echo "请设置 NOTARY_PROFILE，例如：NOTARY_PROFILE=cutscreen-notary Scripts/notarize.sh"
  exit 1
fi

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "未找到 DMG: ${DMG_PATH}"
  exit 1
fi

xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"
