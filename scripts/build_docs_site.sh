#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/generate_code_wiki.sh
./scripts/generate_wiki_home.sh
MKDOCS_BIN="${MKDOCS_BIN:-$ROOT_DIR/.venv-docs/bin/mkdocs}"
if [[ ! -x "$MKDOCS_BIN" ]]; then
  MKDOCS_BIN="mkdocs"
fi
"$MKDOCS_BIN" build --strict

echo "Built documentation site: $ROOT_DIR/docs/manual"
