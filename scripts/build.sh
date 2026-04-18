#!/usr/bin/env bash
# HeartBit build helper: dev (Debug, open app) or release (zip for Homebrew).
# Version for release zip comes from project.yml (CFBundleShortVersionString).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: scripts/build.sh <command>

  dev      Generate Xcode project, build Debug, open HeartBit.app for testing.
  release  Build Release, create Release/HeartBit-v<version>.zip, print SHA-256.

Requires XcodeGen (brew install xcodegen) or ./xcodegen/bin/xcodegen.
EOF
}

find_xcodegen() {
  if command -v xcodegen &>/dev/null; then
    echo "xcodegen"
  elif [[ -x "${ROOT}/xcodegen/bin/xcodegen" ]]; then
    echo "${ROOT}/xcodegen/bin/xcodegen"
  else
    echo "error: xcodegen not found (install via Homebrew or vendor under ./xcodegen)" >&2
    exit 1
  fi
}

read_version() {
  local v
  v="$(sed -n 's/^[[:space:]]*CFBundleShortVersionString: "\([^"]*\)".*/\1/p' project.yml | head -n1)"
  if [[ -z "${v}" ]]; then
    echo "error: could not read CFBundleShortVersionString from project.yml" >&2
    exit 1
  fi
  echo "${v}"
}

run_dev() {
  local xcodegen_bin derived app
  xcodegen_bin="$(find_xcodegen)"
  derived="${ROOT}/build/DerivedData-dev"
  "${xcodegen_bin}" generate
  rm -rf "${derived}"
  xcodebuild \
    -scheme HeartBit \
    -configuration Debug \
    -derivedDataPath "${derived}" \
    -destination "platform=macOS" \
    build
  app="${derived}/Build/Products/Debug/HeartBit.app"
  if [[ ! -d "${app}" ]]; then
    echo "error: expected app at ${app}" >&2
    exit 1
  fi
  echo "Opening ${app}"
  open "${app}"
}

run_release() {
  local xcodegen_bin version zip_name out_dir derived zip_path app_path
  xcodegen_bin="$(find_xcodegen)"
  version="$(read_version)"
  zip_name="HeartBit-v${version}.zip"
  out_dir="${ROOT}/Release"
  derived="${ROOT}/build/DerivedData"
  mkdir -p "${out_dir}"

  "${xcodegen_bin}" generate
  rm -rf "${derived}"
  xcodebuild \
    -scheme HeartBit \
    -configuration Release \
    -derivedDataPath "${derived}" \
    -destination "platform=macOS" \
    build

  app_path="${derived}/Build/Products/Release/HeartBit.app"
  if [[ ! -d "${app_path}" ]]; then
    echo "error: expected app at ${app_path}" >&2
    exit 1
  fi

  zip_path="${out_dir}/${zip_name}"
  rm -f "${zip_path}"
  ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${zip_path}"

  echo "Built ${zip_path}"
  shasum -a 256 "${zip_path}"
}

cmd="${1:-}"
case "${cmd}" in
  dev|test) run_dev ;;
  release) run_release ;;
  -h|--help|help|'') usage; exit 0 ;;
  *) echo "error: unknown command: ${cmd}" >&2; usage >&2; exit 1 ;;
esac
