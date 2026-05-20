#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if ! grep -q 'href="manual/' "$ROOT_DIR/docs/index.html"; then
  echo "Visual check failed: website does not link to manual" >&2
  exit 1
fi

if ! grep -q 'stylesheets/leafreader.css' "$ROOT_DIR/docs/manual/index.html"; then
  echo "Visual check failed: manual page does not include Leaf Reader stylesheet" >&2
  exit 1
fi

echo "Docs visual checks passed."
