#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -s "$ROOT_DIR/docs/assets/docs-manual-preview.png" ]]; then
  echo "Visual check failed: missing docs manual preview image" >&2
  exit 1
fi

if ! grep -q 'href="manual/"' "$ROOT_DIR/docs/index.html"; then
  echo "Visual check failed: website does not link to manual" >&2
  exit 1
fi

if ! grep -q 'docs-manual-preview.png' "$ROOT_DIR/docs/index.html"; then
  echo "Visual check failed: website does not reference docs preview image" >&2
  exit 1
fi

if ! grep -q 'stylesheets/leafreader.css' "$ROOT_DIR/docs/manual/index.html"; then
  echo "Visual check failed: manual page does not include Leaf Reader stylesheet" >&2
  exit 1
fi

if ! sips -g pixelWidth -g pixelHeight "$ROOT_DIR/docs/assets/docs-manual-preview.png" >/dev/null; then
  echo "Visual check failed: docs preview image is not readable" >&2
  exit 1
fi

echo "Docs visual checks passed."
