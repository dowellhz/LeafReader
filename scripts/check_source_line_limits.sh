#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAX_SOURCE_LINES=500
failures=0

while IFS= read -r source; do
  case "$source" in
    *.min.js|*.generated.*|*/Generated/*|*/Vendor/*|*/vendor/*)
      continue
      ;;
  esac

  line_count="$(wc -l < "$source" | tr -d ' ')"
  if (( line_count > MAX_SOURCE_LINES )); then
    relative_path="${source#"$ROOT_DIR"/}"
    echo "FAIL source line limit: $relative_path has $line_count lines (max $MAX_SOURCE_LINES)" >&2
    failures=$((failures + 1))
  fi
done < <(
  find "$ROOT_DIR/mac-app" "$ROOT_DIR/tests" "$ROOT_DIR/scripts" \
    -type f \( -name '*.swift' -o -name '*.js' -o -name '*.sh' -o -name '*.py' \) \
    | sort
)

if (( failures > 0 )); then
  echo "Source line-limit checks failed: $failures file(s)." >&2
  exit 1
fi

echo "Source line-limit checks passed."
