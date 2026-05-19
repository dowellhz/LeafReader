#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUSH=0
COMMIT_SOURCE=1

usage() {
  cat <<'EOF'
Usage: ./scripts/update_wiki.sh [--push] [--no-source-commit]

Regenerate the local wiki source files and sync them to the GitHub Wiki.

Default mode:
  - regenerates docs/wiki/code-map.md
  - syncs docs/wiki into a local GitHub Wiki checkout
  - shows diffs only; does not push

With --push:
  - commits and pushes GitHub Wiki changes
  - commits and pushes changed docs/wiki source files in this repository

Options:
  --push              Push GitHub Wiki and source wiki updates
  --no-source-commit  With --push, leave changed docs/wiki files uncommitted

Environment:
  WIKI_REMOTE         GitHub Wiki git remote
  WIKI_WORKTREE       Local wiki checkout path
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      PUSH=1
      shift
      ;;
    --no-source-commit)
      COMMIT_SOURCE=0
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

cd "$ROOT_DIR"

SOURCE_BEFORE="$(git rev-parse HEAD)"
WIKI_BEFORE=""
if [[ -d "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}/.git" ]]; then
  WIKI_BEFORE="$(git -C "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}" rev-parse HEAD 2>/dev/null || true)"
fi

if [[ -n "$(git status --porcelain -- docs/wiki)" ]]; then
  echo "Existing local wiki source changes will be included:"
  git status --short -- docs/wiki
fi

./scripts/generate_code_wiki.sh
./scripts/generate_wiki_home.sh

if [[ -n "$(git status --porcelain -- docs/wiki)" ]]; then
  echo "Local wiki source changes:"
  git status --short -- docs/wiki
  git diff --stat -- docs/wiki
else
  echo "Local wiki source is already up to date."
fi

if [[ "$PUSH" -eq 1 ]]; then
  ./scripts/sync_github_wiki.sh --push
else
  ./scripts/sync_github_wiki.sh
  exit 0
fi

if [[ "$COMMIT_SOURCE" -ne 1 ]]; then
  echo "Leaving local docs/wiki changes uncommitted because --no-source-commit was set."
  echo "Wiki update summary:"
  echo "- Source commit: unchanged ($(git rev-parse --short HEAD))"
  if [[ -d "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}/.git" ]]; then
    echo "- Wiki commit: $(git -C "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}" rev-parse --short HEAD)"
  fi
  exit 0
fi

if [[ -z "$(git status --porcelain -- docs/wiki)" ]]; then
  echo "No local wiki source changes to commit."
  echo "Wiki update summary:"
  echo "- Source commit: unchanged ($(git rev-parse --short HEAD))"
  if [[ -d "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}/.git" ]]; then
    echo "- Wiki commit: $(git -C "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}" rev-parse --short HEAD)"
  fi
  exit 0
fi

echo "Source wiki files changed:"
git status --short -- docs/wiki
git add docs/wiki
git commit -m "Update generated code wiki"
git push origin "$(git branch --show-current)"

echo "Wiki update summary:"
echo "- Source commit: $(git rev-parse --short "$SOURCE_BEFORE") -> $(git rev-parse --short HEAD)"
if [[ -d "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}/.git" ]]; then
  WIKI_AFTER="$(git -C "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}" rev-parse HEAD)"
  if [[ -n "$WIKI_BEFORE" ]]; then
    echo "- Wiki commit: $(git -C "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}" rev-parse --short "$WIKI_BEFORE") -> $(git -C "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}" rev-parse --short "$WIKI_AFTER")"
  else
    echo "- Wiki commit: $(git -C "${WIKI_WORKTREE:-/private/tmp/leafreader-wiki-sync}" rev-parse --short "$WIKI_AFTER")"
  fi
fi
