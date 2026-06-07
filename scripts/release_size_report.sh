#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"

if [[ "${VERSION:-}" == "-h" || "${VERSION:-}" == "--help" ]]; then
  echo "Usage: $0 [version]" >&2
  exit 0
fi

APP_PATH="$ROOT_DIR/Leaf Reader.app"
if [[ -n "$VERSION" ]]; then
  PKG_PATH="$ROOT_DIR/release/$VERSION/LeafReader-$VERSION.pkg"
else
  PKG_PATH=""
fi

SPEECH_RUNTIMES="$APP_PATH/Contents/Resources/SpeechRuntimes"

echo "==> Release size report${VERSION:+ for $VERSION}"

if [[ -d "$APP_PATH" ]]; then
  echo "App bundle: $(du -sh "$APP_PATH" | awk '{print $1}')"
else
  echo "App bundle: missing ($APP_PATH)"
fi

if [[ -n "$PKG_PATH" ]]; then
  if [[ -f "$PKG_PATH" ]]; then
    echo "Signed pkg: $(du -h "$PKG_PATH" | awk '{print $1}')"
  else
    echo "Signed pkg: missing ($PKG_PATH)"
  fi
fi

if [[ ! -d "$SPEECH_RUNTIMES" ]]; then
  echo "Speech runtimes: missing ($SPEECH_RUNTIMES)"
  exit 0
fi

echo "Speech runtimes total: $(du -sh "$SPEECH_RUNTIMES" | awk '{print $1}')"
echo "Speech runtime directories:"
find "$SPEECH_RUNTIMES" -mindepth 1 -maxdepth 1 -type d -print \
  | sort \
  | while IFS= read -r runtime_dir; do
      echo " - $(basename "$runtime_dir"): $(du -sh "$runtime_dir" | awk '{print $1}')"
    done

signable_count="$(
  find "$SPEECH_RUNTIMES" -type f \( -perm -111 -o -name '*.dylib' \) -print | wc -l | tr -d ' '
)"
echo "Speech runtime signable files: $signable_count"

echo "Largest bundled speech runtime files:"
find "$SPEECH_RUNTIMES" -type f -print0 \
  | xargs -0 du -h \
  | sort -hr \
  | head -8 \
  | while read -r size path; do
      echo " - $size ${path#"$SPEECH_RUNTIMES/"}"
    done
