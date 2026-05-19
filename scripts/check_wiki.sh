#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WIKI_DIR="$ROOT_DIR/docs/wiki"
SYNC_SCRIPT="$ROOT_DIR/scripts/sync_github_wiki.sh"
FAILURES=0

fail() {
  echo "FAIL wiki: $*" >&2
  FAILURES=$((FAILURES + 1))
}

check_local_links() {
  local file link target resolved dir
  while IFS= read -r file; do
    dir="$(dirname "$file")"
    while IFS= read -r link; do
      [[ -z "$link" ]] && continue
      [[ "$link" =~ ^https?:// ]] && continue
      [[ "$link" =~ ^mailto: ]] && continue
      [[ "$link" =~ ^# ]] && continue
      target="${link%%#*}"
      [[ -z "$target" ]] && continue
      resolved="$dir/$target"
      if [[ ! -e "$resolved" ]]; then
        fail "$file links to missing path: $link"
      fi
    done < <(
      grep -Eo '\[[^]]+\]\([^)]+\)' "$file" \
        | sed -E 's/^.*\]\(([^)]+)\)$/\1/' \
        | grep -Ev '^(https?://|mailto:|#)' || true
    )
  done < <(find "$WIKI_DIR" -name '*.md' -print | sort)
}

wiki_target_for_source() {
  local source="$1"
  grep -E "copy_page \"$source\" " "$SYNC_SCRIPT" \
    | sed -E 's/^.*copy_page "[^"]+" "([^"]+)".*$/\1/' \
    | head -n 1
}

check_sync_registration() {
  local source basename target
  while IFS= read -r source; do
    basename="$(basename "$source")"
    [[ "$basename" == "index.md" ]] && continue
    target="$(wiki_target_for_source "$basename")"
    if [[ -z "$target" ]]; then
      fail "$basename is not registered in sync_github_wiki.sh copy_page list"
      continue
    fi
    if ! grep -qE "^[[:space:]]*$target$" "$SYNC_SCRIPT"; then
      fail "$target is copied but missing from WIKI_PAGES"
    fi
  done < <(find "$WIKI_DIR" -name '*.md' -print | sort)

  for required in Home.md _Sidebar.md _Footer.md; do
    if ! grep -qE "^[[:space:]]*$required$" "$SYNC_SCRIPT"; then
      fail "$required is missing from WIKI_PAGES"
    fi
  done
}

check_generated_files() {
  local temp_dir
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-wiki-check.XXXXXX")"
  trap 'rm -rf "$temp_dir"' RETURN

  WIKI_OUT_DIR="$temp_dir" "$ROOT_DIR/scripts/generate_code_wiki.sh" >/dev/null
  WIKI_OUT_DIR="$temp_dir" "$ROOT_DIR/scripts/generate_wiki_home.sh" >/dev/null

  for generated in code-map.md type-index.md index.md; do
    if ! diff -q "$temp_dir/$generated" "$WIKI_DIR/$generated" >/dev/null; then
      fail "$generated is stale; run ./scripts/update_wiki.sh"
    fi
  done
}

check_version_status() {
  local version
  version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/mac-app/Info.plist")"
  if ! grep -q "Current version: \`$version\`" "$WIKI_DIR/index.md"; then
    fail "docs/wiki/index.md current version does not match Info.plist ($version)"
  fi
  if ! grep -q "Git tag: \`v$version\`" "$WIKI_DIR/index.md"; then
    fail "docs/wiki/index.md Git tag does not match Info.plist ($version)"
  fi
}

check_scripts() {
  bash -n "$ROOT_DIR/scripts/generate_code_wiki.sh"
  bash -n "$ROOT_DIR/scripts/generate_wiki_home.sh"
  bash -n "$ROOT_DIR/scripts/sync_github_wiki.sh"
  bash -n "$ROOT_DIR/scripts/update_wiki.sh"
}

check_scripts
check_local_links
check_sync_registration
check_generated_files
check_version_status

if [[ "$FAILURES" -ne 0 ]]; then
  echo "Wiki checks failed: $FAILURES issue(s)." >&2
  exit 1
fi

echo "Wiki checks passed."
