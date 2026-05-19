#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Checking whitespace"
git diff --check

echo "==> Running tests"
./tests/run.sh

echo "==> Building app"
./scripts/build_app.sh

echo "All checks passed."
