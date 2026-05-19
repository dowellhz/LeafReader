#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/docs/wiki"
WIKI_REMOTE="${WIKI_REMOTE:-git@github.com:dowellhz/LeafReader.wiki.git}"
WIKI_WORKTREE="${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}"
PUSH=0
WIKI_PAGES=(
  Home.md
  Architecture.md
  Document-Loading.md
  AI-Chat.md
  AI-Analysis-Cache.md
  Word-Highlights.md
  Release-Process.md
  Release-Checklist.md
  Security.md
  Troubleshooting.md
  Code-Map.md
  _Sidebar.md
)

usage() {
  cat <<'EOF'
Usage: ./scripts/sync_github_wiki.sh [--push]

Sync docs/wiki into the GitHub Wiki repository.

Default mode:
  - clones or updates the local wiki worktree
  - writes converted wiki pages
  - shows the wiki diff
  - does not commit or push

With --push:
  - commits the wiki changes when there is a diff
  - pushes to the wiki remote

Environment:
  WIKI_REMOTE     GitHub Wiki git remote
  WIKI_WORKTREE   local wiki checkout path
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      PUSH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Missing source wiki directory: $SOURCE_DIR" >&2
  exit 1
fi

if [[ ! -d "$WIKI_WORKTREE/.git" ]]; then
  rm -rf "$WIKI_WORKTREE"
  git clone "$WIKI_REMOTE" "$WIKI_WORKTREE"
else
  git -C "$WIKI_WORKTREE" fetch origin
  git -C "$WIKI_WORKTREE" checkout master
  if [[ -z "$(git -C "$WIKI_WORKTREE" status --porcelain)" ]]; then
    git -C "$WIKI_WORKTREE" pull --ff-only origin master
  fi
fi

unexpected_dirty_files() {
  git -C "$WIKI_WORKTREE" status --porcelain | while read -r _ path; do
    local allowed=0
    for page in "${WIKI_PAGES[@]}"; do
      if [[ "$path" == "$page" ]]; then
        allowed=1
        break
      fi
    done
    if [[ "$allowed" -ne 1 ]]; then
      echo "$path"
    fi
  done
}

if [[ -n "$(unexpected_dirty_files)" ]]; then
  echo "Wiki worktree has uncommitted changes: $WIKI_WORKTREE" >&2
  git -C "$WIKI_WORKTREE" status --short >&2
  exit 1
fi

copy_page() {
  local source="$1"
  local target="$2"
  cp "$SOURCE_DIR/$source" "$WIKI_WORKTREE/$target"
}

copy_page "architecture.md" "Architecture.md"
copy_page "document-loading.md" "Document-Loading.md"
copy_page "ai-chat.md" "AI-Chat.md"
copy_page "ai-analysis-cache.md" "AI-Analysis-Cache.md"
copy_page "word-highlights.md" "Word-Highlights.md"
copy_page "release-process.md" "Release-Process.md"
copy_page "release-checklist.md" "Release-Checklist.md"
copy_page "security.md" "Security.md"
copy_page "troubleshooting.md" "Troubleshooting.md"
copy_page "code-map.md" "Code-Map.md"

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/mac-app/Info.plist")"

cat > "$WIKI_WORKTREE/Home.md" <<EOF
# Leaf Reader Code Wiki

This wiki explains the codebase structure and stable engineering workflows for Leaf Reader.

## Current Version Status

- Current version: \`$CURRENT_VERSION\`
- Git tag: \`v$CURRENT_VERSION\`
- Website: [leafreader.space](https://leafreader.space)
- Appcast: [docs/appcast.xml](https://dowellhz.github.io/LeafReader/appcast.xml)
- Latest installer: [LeafReader-$CURRENT_VERSION.pkg](https://github.com/dowellhz/LeafReader/releases/download/v$CURRENT_VERSION/LeafReader-$CURRENT_VERSION.pkg)

## Common Commands

~~~sh
./scripts/check.sh
./scripts/release_pkg.sh <version>
./scripts/publish_release.sh <version>
./scripts/update_wiki.sh --push
~~~

## Pages

- [Architecture](Architecture)
- [Document Loading](Document-Loading)
- [AI Chat](AI-Chat)
- [AI Analysis Cache](AI-Analysis-Cache)
- [Word Highlights](Word-Highlights)
- [Release Process](Release-Process)
- [Release Checklist](Release-Checklist)
- [Security](Security)
- [Troubleshooting](Troubleshooting)
- [Code Map](Code-Map)

## Maintenance

- Keep durable architecture notes in these pages.
- Regenerate [Code Map](Code-Map) after large refactors:

~~~sh
./scripts/update_wiki.sh
~~~

- Prefer short flow descriptions and source file links over copied code.
EOF

cat > "$WIKI_WORKTREE/_Sidebar.md" <<'EOF'
## Leaf Reader Wiki

- [Home](Home)
- [Architecture](Architecture)
- [Document Loading](Document-Loading)
- [AI Chat](AI-Chat)
- [AI Analysis Cache](AI-Analysis-Cache)
- [Word Highlights](Word-Highlights)
- [Release Process](Release-Process)
- [Release Checklist](Release-Checklist)
- [Security](Security)
- [Troubleshooting](Troubleshooting)
- [Code Map](Code-Map)
EOF

echo "Wiki worktree: $WIKI_WORKTREE"
git -C "$WIKI_WORKTREE" status --short

if [[ -z "$(git -C "$WIKI_WORKTREE" status --porcelain)" ]]; then
  echo "GitHub Wiki is already up to date."
  exit 0
fi

git -C "$WIKI_WORKTREE" diff --stat

if [[ "$PUSH" -ne 1 ]]; then
  echo "Dry run complete. Re-run with --push to commit and push wiki changes."
  exit 0
fi

git -C "$WIKI_WORKTREE" add "${WIKI_PAGES[@]}"
git -C "$WIKI_WORKTREE" commit -m "Sync code wiki"
git -C "$WIKI_WORKTREE" push origin master
