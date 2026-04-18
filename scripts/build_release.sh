#!/usr/bin/env bash
# Build a release zip: Release/HeartBit-v<version>.zip
# Version is read from project.yml (CFBundleShortVersionString on the HeartBit target).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/^[[:space:]]*CFBundleShortVersionString: "\([^"]*\)".*/\1/p' project.yml | head -n1)"
if [[ -z "${VERSION}" ]]; then
  echo "error: could not read CFBundleShortVersionString from project.yml" >&2
  exit 1
fi

ZIP_NAME="HeartBit-v${VERSION}.zip"
OUT_DIR="${ROOT}/Release"
DERIVED="${ROOT}/build/DerivedData"
mkdir -p "${OUT_DIR}"

if command -v xcodegen &>/dev/null; then
  XCODEGEN=(xcodegen)
elif [[ -x "${ROOT}/xcodegen/bin/xcodegen" ]]; then
  XCODEGEN=("${ROOT}/xcodegen/bin/xcodegen")
else
  echo "error: xcodegen not found (install via Homebrew or vendor xcodegen under ./xcodegen)" >&2
  exit 1
fi

"${XCODEGEN[@]}" generate

rm -rf "${DERIVED}"
xcodebuild \
  -scheme HeartBit \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  -destination "platform=macOS" \
  build

APP_PATH="${DERIVED}/Build/Products/Release/HeartBit.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: expected app at ${APP_PATH}" >&2
  exit 1
fi

ZIP_PATH="${OUT_DIR}/${ZIP_NAME}"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "Built ${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}"
