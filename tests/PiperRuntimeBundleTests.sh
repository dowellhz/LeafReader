#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/Leaf Reader.app}"
PIPER_BIN="$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime/piper/piper"
EXPECTED_RPATH="@executable_path/../piper-phonemize/lib"

if [[ ! -x "$PIPER_BIN" ]]; then
  echo "Piper runtime executable missing: $PIPER_BIN" >&2
  exit 1
fi

if ! otool -l "$PIPER_BIN" | grep -Fq "path $EXPECTED_RPATH"; then
  echo "Piper runtime is missing required LC_RPATH: $EXPECTED_RPATH" >&2
  otool -l "$PIPER_BIN" | grep -A2 LC_RPATH >&2 || true
  exit 1
fi

echo "Piper runtime bundle checks passed."
