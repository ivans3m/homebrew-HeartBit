#!/usr/bin/env bash
#
# Bump version in project.yml, build release zip, update Homebrew cask, commit, tag, push,
# and create a GitHub release with auto-generated notes from git log.
#
# Prerequisites:
#   - Xcode + Xcode command-line tools, XcodeGen (brew install xcodegen)
#   - git with origin pointing at the repo (e.g. https://github.com/ivans3m/homebrew-HeartBit.git)
#   - gh auth login (for GitHub releases)
#   - brew (optional, for: brew tap … && brew audit --cask heartbit)
#
# Usage:
#   scripts/publish_release.sh [options] <version> [build_number]
#
# Examples:
#   scripts/publish_release.sh 1.3.5          # bumps CFBundleVersion by +1
#   scripts/publish_release.sh 1.3.5 12       # sets CFBundleVersion to 12
#   scripts/publish_release.sh --dry-run 1.3.5
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

DRY_RUN=0
NO_PUSH=0
NO_GITHUB=0
SKIP_BUILD=0
ALLOW_DIRTY=0
NOTES_OUT=""

usage() {
  cat <<'EOF'
Usage: scripts/publish_release.sh [options] <version> [build_number]

Bump project.yml, build Release/HeartBit-v<version>.zip, update Casks/heartbit.rb,
commit, tag v<version>, push, and create a GitHub release (unless disabled).

Options:
  --dry-run       Show what would happen; do not modify files, git, or GitHub.
  --no-push       Commit and tag locally; do not push.
  --no-github     Push commits and tag; do not run gh release create.
  --skip-build    Do not run scripts/heartbit-build.sh release; use existing Release/HeartBit-v<version>.zip.
  --allow-dirty   Allow a dirty working tree before starting (default: require clean).
  --notes-out PATH  Write release notes preview to PATH (dry-run, or when push/gh skipped).
  -h, --help      Show this help.

Examples:
  scripts/publish_release.sh 1.3.5
  scripts/publish_release.sh --dry-run 1.3.5
  scripts/publish_release.sh --no-push --notes-out ./release-notes.md 1.3.5
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --no-push) NO_PUSH=1; shift ;;
    --no-github) NO_GITHUB=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --notes-out)
      NOTES_OUT="${2:-}"
      if [[ -z "${NOTES_OUT}" ]]; then echo "error: --notes-out requires a path" >&2; exit 1; fi
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *) break ;;
  esac
done

VERSION="${1:-}"
BUILD_ARG="${2:-}"

if [[ -z "${VERSION}" ]]; then
  echo "error: version argument required (e.g. 1.3.5)" >&2
  usage >&2
  exit 1
fi

if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must look like MAJOR.MINOR.PATCH (digits)" >&2
  exit 1
fi

if [[ -n "${BUILD_ARG}" ]] && ! [[ "${BUILD_ARG}" =~ ^[0-9]+$ ]]; then
  echo "error: build number must be a non-negative integer" >&2
  exit 1
fi

if [[ ${ALLOW_DIRTY} -eq 0 ]] && [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is not clean (commit or stash, or use --allow-dirty)" >&2
  exit 1
fi

PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
NOTES_FILE="$(mktemp -t heartbit_release_notes)"

write_notes_file() {
  {
    echo "## Changes"
    echo
    if [[ -n "${PREV_TAG}" ]] && git rev-parse "${PREV_TAG}" &>/dev/null; then
      git log "${PREV_TAG}..HEAD" --pretty=format:'- %s (%h)' 2>/dev/null || true
    elif [[ -n "${PREV_TAG}" ]]; then
      echo "- (tag ${PREV_TAG} not found; showing recent commits)"
      git log -20 --pretty=format:'- %s (%h)' 2>/dev/null || true
    else
      git log -30 --pretty=format:'- %s (%h)' 2>/dev/null || true
    fi
    echo
    echo
    echo "## Install"
    echo
    echo "- **Homebrew:** \`brew tap ivans3m/heartbit\` then \`brew install --cask heartbit\`"
    echo "- **Zip:** download \`HeartBit-v${VERSION}.zip\` from release assets and drag \`HeartBit.app\` to \`/Applications\`."
    echo
    echo "Requires macOS 14 (Sonoma) or later."
  } > "${NOTES_FILE}"
}

write_notes_file

echo "---- Release notes preview ----"
cat "${NOTES_FILE}"
echo "-------------------------------"

# Read HeartBit-only keys (avoids picking up another target if project.yml grows).
read_heartbit_versions() {
  ruby -ryaml -e '
    h = YAML.load_file("project.yml")
    p = h.dig("targets", "HeartBit", "info", "properties")
    abort "missing HeartBit version keys" unless p
    print [p["CFBundleShortVersionString"], p["CFBundleVersion"]].join("\t")
  '
}

IFS=$'\t' read -r CURRENT_VER CURRENT_BUILD < <(read_heartbit_versions) || true

if [[ -z "${CURRENT_VER}" ]] || [[ -z "${CURRENT_BUILD}" ]]; then
  echo "error: could not read HeartBit version fields from project.yml" >&2
  rm -f "${NOTES_FILE}"
  exit 1
fi

if [[ -n "${BUILD_ARG}" ]]; then
  NEW_BUILD="${BUILD_ARG}"
else
  NEW_BUILD=$((10#${CURRENT_BUILD} + 1))
fi

if [[ ${DRY_RUN} -eq 1 ]]; then
  echo "[dry-run] would set CFBundleShortVersionString=${VERSION}, CFBundleVersion=${NEW_BUILD}"
  echo "[dry-run] would run: scripts/heartbit-build.sh release (unless --skip-build)"
  echo "[dry-run] would update Casks/heartbit.rb version + sha256"
  echo "[dry-run] would: git commit, git tag v${VERSION}, git push, gh release create"
  if [[ -n "${NOTES_OUT}" ]]; then
    cp "${NOTES_FILE}" "${NOTES_OUT}"
    echo "Wrote release notes preview to ${NOTES_OUT}"
  fi
  rm -f "${NOTES_FILE}"
  exit 0
fi

bump_project_yml() {
  sed -i '' "s/CFBundleShortVersionString: \"${CURRENT_VER}\"/CFBundleShortVersionString: \"${VERSION}\"/" project.yml
  sed -i '' "s/CFBundleVersion: \"${CURRENT_BUILD}\"/CFBundleVersion: \"${NEW_BUILD}\"/" project.yml
}

verify_project_yml_bump() {
  local got_ver got_build
  IFS=$'\t' read -r got_ver got_build < <(read_heartbit_versions) || true
  if [[ "${got_ver}" != "${VERSION}" ]] || [[ "${got_build}" != "${NEW_BUILD}" ]]; then
    echo "error: project.yml bump verification failed (expected ${VERSION} / ${NEW_BUILD}, got ${got_ver} / ${got_build})" >&2
    exit 1
  fi
}

update_cask() {
  local sha="$1"
  sed -i '' "s/^  version \".*\"/  version \"${VERSION}\"/" Casks/heartbit.rb
  sed -i '' "s/^  sha256 \".*\"/  sha256 \"${sha}\"/" Casks/heartbit.rb
}

bump_project_yml
verify_project_yml_bump

ZIP_PATH="${ROOT}/Release/HeartBit-v${VERSION}.zip"
if [[ ${SKIP_BUILD} -eq 1 ]]; then
  if [[ ! -f "${ZIP_PATH}" ]]; then
    echo "error: --skip-build requires existing ${ZIP_PATH}" >&2
    exit 1
  fi
  echo "Using existing zip (--skip-build)."
else
  "${ROOT}/scripts/heartbit-build.sh" release
fi

SHA256="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
echo "SHA256: ${SHA256}"

update_cask "${SHA256}"

if command -v brew &>/dev/null; then
  if [[ ! -d "$(brew --repository)/Library/Taps/ivans3m/homebrew-heartbit" ]]; then
    brew tap ivans3m/heartbit "${ROOT}" 2>/dev/null || true
  fi
  HOMEBREW_NO_AUTO_UPDATE=1 brew audit --cask --strict heartbit
else
  echo "warning: brew not in PATH; skipping brew audit" >&2
fi

COMMIT_MSG="Release v${VERSION}"

git add project.yml Casks/heartbit.rb
# Info.plist is regenerated from project.yml by xcodegen during the release build.
# Stage it only if it changed so existing release flows continue to work.
if ! git diff --quiet -- Info.plist; then
  git add Info.plist
fi
git commit -m "${COMMIT_MSG}"

TAG="v${VERSION}"
git tag -a "${TAG}" -m "${COMMIT_MSG}"

if [[ ${NO_PUSH} -eq 0 ]]; then
  git push origin HEAD
  git push origin "${TAG}"
else
  echo "(skipped: git push --no-push)"
fi

if [[ ${NO_GITHUB} -eq 1 ]] || [[ ${NO_PUSH} -eq 1 ]]; then
  echo "(skipped: gh release create)"
  if [[ -n "${NOTES_OUT}" ]]; then
    cp "${NOTES_FILE}" "${NOTES_OUT}"
    echo "Wrote release notes to ${NOTES_OUT}"
  elif [[ ${NO_GITHUB} -eq 0 ]] && [[ ${NO_PUSH} -eq 1 ]]; then
    echo "note: after pushing, run:" >&2
    echo "  gh release create ${TAG} ${ZIP_PATH} --title \"HeartBit v${VERSION}\" --notes-file <path-to-notes>" >&2
    echo "tip: re-run with --notes-out PATH to save notes to a file" >&2
  fi
  rm -f "${NOTES_FILE}"
  exit 0
fi

gh release create "${TAG}" "${ZIP_PATH}" --title "HeartBit v${VERSION}" --notes-file "${NOTES_FILE}"

rm -f "${NOTES_FILE}"
echo "Published ${TAG}"
