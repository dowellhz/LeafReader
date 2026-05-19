#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <version> [release-notes-html-file]" >&2
  exit 1
fi

VERSION="$1"
NOTES_FILE="${2:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG="v$VERSION"
PKG_PATH="$ROOT_DIR/release/$VERSION/LeafReader-$VERSION.pkg"
RELEASE_URL="https://github.com/dowellhz/LeafReader/releases/tag/$TAG"
CHECK_SCRIPT="$ROOT_DIR/scripts/check.sh"

cd "$ROOT_DIR"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash current changes before publishing $VERSION." >&2
  git status --short
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag already exists locally: $TAG" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
  echo "Tag already exists on origin: $TAG" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
  exit 1
fi

"$CHECK_SCRIPT" --no-build
./scripts/bump_version.sh --check "$VERSION" 2>/dev/null || true
if [[ -n "$NOTES_FILE" ]]; then
  ./scripts/release_pkg.sh "$VERSION" "$NOTES_FILE"
else
  ./scripts/release_pkg.sh "$VERSION"
fi
./scripts/bump_version.sh --check "$VERSION"

if [[ ! -f "$PKG_PATH" ]]; then
  echo "Expected release package not found: $PKG_PATH" >&2
  exit 1
fi

SHA256="$(shasum -a 256 "$PKG_PATH" | awk '{print $1}')"

git add README.md docs/appcast.xml docs/index.html mac-app/Info.plist
git commit -m "Release $VERSION"
git tag "$TAG"
git push origin main
git push origin "$TAG"

RELEASE_NOTES="Leaf Reader $VERSION release.

SHA256: $SHA256"
gh release create "$TAG" "$PKG_PATH" --title "Leaf Reader $VERSION" --notes "$RELEASE_NOTES"

curl -I -L "https://github.com/dowellhz/LeafReader/releases/download/$TAG/LeafReader-$VERSION.pkg" >/dev/null

echo "Published $VERSION"
echo "Release: $RELEASE_URL"
echo "Package: $PKG_PATH"
echo "SHA256: $SHA256"
