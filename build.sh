#!/usr/bin/env bash
# Convenience wrapper at repo root — forwards to the canonical build script.
# Prefer: ./scripts/heartbit-build.sh <dev|release>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${ROOT}/scripts/heartbit-build.sh" "$@"
