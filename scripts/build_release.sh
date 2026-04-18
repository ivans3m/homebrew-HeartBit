#!/usr/bin/env bash
# Thin wrapper — implementation lives in scripts/build.sh release.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${ROOT}/scripts/build.sh" release
