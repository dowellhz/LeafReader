#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_BUILD=1

if [[ $# -gt 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [--no-build]" >&2
  exit 1
fi

if [[ "${1:-}" == "--no-build" ]]; then
  RUN_BUILD=0
elif [[ $# -eq 1 ]]; then
  echo "Unknown option: $1" >&2
  echo "Usage: $0 [--no-build]" >&2
  exit 1
fi

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/leafreader-clang-cache}"

echo "==> Checking source line limits"
./scripts/check_source_line_limits.sh

echo "==> Checking whitespace"
git diff --check

echo "==> Checking wiki"
./scripts/check_wiki.sh

echo "==> Checking UI theme coverage"
./scripts/check_ui_theme.sh

echo "==> Running tests"
./tests/run.sh

if [[ "$RUN_BUILD" -eq 1 ]]; then
  echo "==> Building docs site"
  DOCS_SITE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-docs-check.XXXXXX")"
  LEAFREADER_DOCS_SITE_DIR="$DOCS_SITE_DIR" ./scripts/build_docs_site.sh
  LEAFREADER_DOCS_SITE_DIR="$DOCS_SITE_DIR" ./scripts/check_docs_visual.sh

  echo "==> Building app"
  REQUIRE_BUNDLED_SPEECH_RUNTIMES=1 ./scripts/build_app.sh

  echo "==> Checking app bundle"
  ./tests/PiperRuntimeBundleTests.sh "Leaf Reader.app"
else
  echo "==> Skipping app build"
fi

echo "All checks passed."
