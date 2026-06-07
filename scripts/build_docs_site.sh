#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
SITE_DIR="${LEAFREADER_DOCS_SITE_DIR:-$ROOT_DIR/docs/manual}"

./scripts/generate_code_wiki.sh
./scripts/generate_wiki_home.sh
MKDOCS_BIN="${MKDOCS_BIN:-$ROOT_DIR/.venv-docs/bin/mkdocs}"
if [[ ! -x "$MKDOCS_BIN" ]]; then
  MKDOCS_BIN="mkdocs"
fi
"$MKDOCS_BIN" build --strict --site-dir "$SITE_DIR"
find "$SITE_DIR" -type f \( -name '*.html' -o -name '*.xml' \) -exec perl -pi -e 's/[ \t]+$//' {} +

echo "Built documentation site: $SITE_DIR"
