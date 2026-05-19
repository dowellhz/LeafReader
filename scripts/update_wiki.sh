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
  exit 0
fi

if [[ -z "$(git status --porcelain -- docs/wiki)" ]]; then
  echo "No local wiki source changes to commit."
  exit 0
fi

git add docs/wiki
git commit -m "Update generated code wiki"
git push origin "$(git branch --show-current)"
