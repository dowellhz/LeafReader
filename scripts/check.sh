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

echo "==> Checking whitespace"
git diff --check

echo "==> Running tests"
./tests/run.sh

if [[ "$RUN_BUILD" -eq 1 ]]; then
  echo "==> Building app"
  ./scripts/build_app.sh
else
  echo "==> Skipping app build"
fi

echo "All checks passed."
