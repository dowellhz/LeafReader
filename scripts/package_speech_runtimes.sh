#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "scripts/package_speech_runtimes.sh is deprecated; use scripts/package_speech_models.sh" >&2
exec "$ROOT_DIR/scripts/package_speech_models.sh" "$@"
