#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/Leaf Reader.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

resource_path="$APP_PATH/Contents/Resources"
runtime_root="$resource_path/SpeechRuntimes"
executable="$APP_PATH/Contents/MacOS/Leaf Reader"

echo "Leaf Reader bundle audit"
echo "App: $APP_PATH"
if [[ -x "$executable" ]]; then
  echo "Architectures: $(lipo -archs "$executable" 2>/dev/null || echo unknown)"
fi
echo

echo "Top-level sizes"
du -sh "$APP_PATH" "$APP_PATH/Contents" "$resource_path" "$APP_PATH/Contents/Frameworks" 2>/dev/null || true
echo

echo "Speech runtimes"
if [[ -d "$runtime_root" ]]; then
  du -sh "$runtime_root" "$runtime_root"/* 2>/dev/null || true
  find "$runtime_root" -maxdepth 3 \( -type f -o -type l \) -print | while IFS= read -r item; do
    size="$(du -h "$item" 2>/dev/null | awk '{print $1}')"
    target=""
    if [[ -L "$item" ]]; then
      target=" -> $(readlink "$item")"
    fi
    echo "  ${size:-?}  ${item#$APP_PATH/}$target"
  done
else
  echo "  missing: $runtime_root"
fi
echo

echo "Largest bundled resources"
find "$resource_path" -type f -maxdepth 6 -print0 2>/dev/null \
  | xargs -0 du -h 2>/dev/null \
  | sort -hr \
  | head -30
