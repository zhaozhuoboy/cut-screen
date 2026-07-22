#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/Resources/Info.plist")"
DMG_PATH="${1:-${PROJECT_DIR}/build/CutScreen-${VERSION}.dmg}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "未找到 DMG: ${DMG_PATH}"
  exit 1
fi

typeset -a NOTARY_ARGUMENTS
if [[ -n "${NOTARY_PROFILE}" ]]; then
  NOTARY_ARGUMENTS=(--keychain-profile "${NOTARY_PROFILE}")
elif [[ -n "${APPLE_ID}" && -n "${APPLE_TEAM_ID}" && -n "${APPLE_APP_SPECIFIC_PASSWORD}" ]]; then
  NOTARY_ARGUMENTS=(
    --apple-id "${APPLE_ID}"
    --team-id "${APPLE_TEAM_ID}"
    --password "${APPLE_APP_SPECIFIC_PASSWORD}"
  )
else
  echo "请设置 NOTARY_PROFILE，或同时设置 APPLE_ID、APPLE_TEAM_ID 和 APPLE_APP_SPECIFIC_PASSWORD"
  exit 1
fi

xcrun notarytool submit "${DMG_PATH}" "${NOTARY_ARGUMENTS[@]}" --wait
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"
