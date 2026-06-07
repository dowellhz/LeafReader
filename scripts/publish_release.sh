#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version> [release-notes-html-file] [--with-speech-models] [--push-wiki] [--cleanup-releases[=N]]" >&2
  exit 1
fi

VERSION="$1"
shift
NOTES_FILE=""
UPLOAD_SPEECH_MODELS=0
PUSH_WIKI=0
CLEANUP_RELEASES=0
CLEANUP_KEEP=8

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-speech-models)
      UPLOAD_SPEECH_MODELS=1
      shift
      ;;
    --push-wiki)
      PUSH_WIKI=1
      shift
      ;;
    --cleanup-releases)
      CLEANUP_RELEASES=1
      shift
      ;;
    --cleanup-releases=*)
      CLEANUP_RELEASES=1
      CLEANUP_KEEP="${1#*=}"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 <version> [release-notes-html-file] [--with-speech-models] [--push-wiki] [--cleanup-releases[=N]]" >&2
      exit 1
      ;;
    *)
      if [[ -n "$NOTES_FILE" ]]; then
        echo "Unexpected extra argument: $1" >&2
        echo "Usage: $0 <version> [release-notes-html-file] [--with-speech-models] [--push-wiki] [--cleanup-releases[=N]]" >&2
        exit 1
      fi
      NOTES_FILE="$1"
      shift
      ;;
  esac
done
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG="v$VERSION"
PKG_PATH="$ROOT_DIR/release/$VERSION/LeafReader-$VERSION.pkg"
RELEASE_URL="https://github.com/dowellhz/LeafReader/releases/tag/$TAG"
CHECK_SCRIPT="$ROOT_DIR/scripts/check.sh"
SPEECH_MODEL_ASSETS=(
  "$ROOT_DIR/docs/tts/kokoro-coreml-macos-arm64.tar.gz"
  "$ROOT_DIR/docs/tts/kitten-tts-rs-macos-arm64.tar.gz"
  "$ROOT_DIR/docs/tts/piper-tts-macos-arm64.tar.gz"
  "$ROOT_DIR/docs/tts/supertonic-coreml-macos-arm64.tar.gz"
  "$ROOT_DIR/docs/tts/speech-models-manifest.json"
)

cd "$ROOT_DIR"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 1
fi
if [[ ! "$CLEANUP_KEEP" =~ ^[0-9]+$ || "$CLEANUP_KEEP" -lt 1 ]]; then
  echo "--cleanup-releases keep count must be a positive integer" >&2
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

if ! gh api user >/dev/null 2>&1; then
  echo "GitHub CLI cannot access GitHub API. Run: gh auth login -h github.com" >&2
  exit 1
fi

if ! grep -q "## What's New in $VERSION" README.md; then
  echo "README.md must include release notes section: ## What's New in $VERSION" >&2
  exit 1
fi

RUNTIME_ASSETS_RELEASE_TAG="$(sed -n 's/.*static let runtimeAssetsReleaseTag = "\([^"]*\)".*/\1/p' mac-app/SpeechRuntimeModel.swift | head -1)"
if [[ -z "$RUNTIME_ASSETS_RELEASE_TAG" ]]; then
  echo "Unable to read SpeechRuntimeModel.runtimeAssetsReleaseTag" >&2
  exit 1
fi
# Speech models are not uploaded for normal app releases; their download tag is
# intentionally allowed to lag behind the app version until model archives change.
if [[ "$RUNTIME_ASSETS_RELEASE_TAG" == "$TAG" && "$UPLOAD_SPEECH_MODELS" -ne 1 ]]; then
  echo "SpeechRuntimeModel.runtimeAssetsReleaseTag points at $TAG, but --with-speech-models was not provided." >&2
  echo "Either publish the changed model archives with --with-speech-models, or keep runtimeAssetsReleaseTag pointed at the existing model asset release." >&2
  exit 1
fi
if [[ "$UPLOAD_SPEECH_MODELS" -eq 1 && "$RUNTIME_ASSETS_RELEASE_TAG" != "$TAG" ]]; then
  echo "Refusing to upload speech model assets to $TAG because SpeechRuntimeModel.runtimeAssetsReleaseTag is $RUNTIME_ASSETS_RELEASE_TAG." >&2
  echo "Update runtimeAssetsReleaseTag to $TAG when publishing changed model archives." >&2
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

./scripts/smoke_release_pkg.sh "$VERSION"
./scripts/release_size_report.sh "$VERSION"

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

if [[ "$UPLOAD_SPEECH_MODELS" -eq 1 ]]; then
  for asset in "${SPEECH_MODEL_ASSETS[@]}"; do
    if [[ ! -f "$asset" ]]; then
      echo "Missing speech model asset: $asset" >&2
      exit 1
    fi
    gh release upload "$TAG" "$asset" --clobber
    curl -I -L "https://github.com/dowellhz/LeafReader/releases/download/$TAG/$(basename "$asset")" >/dev/null
  done
else
  echo "Skipping speech model assets; app code points to $RUNTIME_ASSETS_RELEASE_TAG."
  echo "Use --with-speech-models only when model archives changed and SpeechRuntimeModel.runtimeAssetsReleaseTag was updated."
fi

if [[ "$PUSH_WIKI" -eq 1 ]]; then
  ./scripts/update_wiki.sh --push
else
  echo "Skipping GitHub Wiki push. Use --push-wiki to sync docs/wiki after publishing."
fi

if [[ "$CLEANUP_RELEASES" -eq 1 ]]; then
  ./scripts/cleanup_releases.sh --keep "$CLEANUP_KEEP" --apply
else
  ./scripts/cleanup_releases.sh --keep "$CLEANUP_KEEP"
fi

echo "Published $VERSION"
echo "Release: $RELEASE_URL"
echo "Package: $PKG_PATH"
echo "SHA256: $SHA256"
