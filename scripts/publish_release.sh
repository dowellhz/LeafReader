#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <version> [release-notes-html-file] [--with-speech-models] [--push-wiki] [--cleanup-releases[=N]]" >&2
}

if [[ $# -lt 1 ]]; then
  usage
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
      usage
      exit 1
      ;;
    *)
      if [[ -n "$NOTES_FILE" ]]; then
        echo "Unexpected extra argument: $1" >&2
        usage
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
DOWNLOAD_URL="https://github.com/dowellhz/LeafReader/releases/download/$TAG/LeafReader-$VERSION.pkg"
CHECK_SCRIPT="$ROOT_DIR/scripts/check.sh"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/leafreader-release-verify.XXXXXX")"
REMOTE_TAG_PUSHED=0
RELEASE_PUBLISHED=0
PUBLISH_DRY_RUN="${LEAFREADER_PUBLISH_DRY_RUN:-0}"
PUBLISH_TEST_LOG="${LEAFREADER_PUBLISH_TEST_LOG:-}"
SPEECH_MODEL_ASSETS=(
  "$ROOT_DIR/docs/tts/kokoro-coreml-macos-arm64.tar.gz"
  "$ROOT_DIR/docs/tts/piper-tts-macos-arm64.tar.gz"
  "$ROOT_DIR/docs/tts/supertonic-coreml-macos-arm64.tar.gz"
  "$ROOT_DIR/docs/tts/speech-models-manifest.json"
)

cleanup_publish_attempt() {
  local status=$?
  trap - EXIT
  rm -rf "$VERIFY_DIR"
  if [[ "$status" -ne 0 && "$RELEASE_PUBLISHED" -eq 0 ]]; then
    echo "Release failed before publication; removing staged GitHub state." >&2
    if [[ "$PUBLISH_DRY_RUN" -eq 1 ]]; then
      record_publish_event "cleanup-release"
      record_publish_event "cleanup-tag"
    elif gh release view "$TAG" >/dev/null 2>&1; then
      gh release delete "$TAG" --yes --cleanup-tag || true
    elif [[ "$REMOTE_TAG_PUSHED" -eq 1 ]]; then
      git push origin ":refs/tags/$TAG" || true
    fi
  fi
  exit "$status"
}
trap cleanup_publish_attempt EXIT

record_publish_event() {
  local event="$1"
  if [[ -n "$PUBLISH_TEST_LOG" ]]; then
    printf '%s\n' "$event" >> "$PUBLISH_TEST_LOG"
  fi
}

inject_publish_failure_if_requested() {
  local stage="$1"
  if [[ "${LEAFREADER_PUBLISH_INJECT_FAILURE:-}" == "$stage" ]]; then
    record_publish_event "failure:$stage"
    return 97
  fi
}

verify_release_asset() {
  local source_path="$1"
  local asset_name
  local expected_sha
  local actual_sha
  if [[ "$PUBLISH_DRY_RUN" -eq 1 ]]; then
    record_publish_event "asset-verified"
    return
  fi
  asset_name="$(basename "$source_path")"
  expected_sha="$(shasum -a 256 "$source_path" | awk '{print $1}')"
  rm -f "$VERIFY_DIR/$asset_name"
  gh release download "$TAG" --pattern "$asset_name" --dir "$VERIFY_DIR" --clobber
  actual_sha="$(shasum -a 256 "$VERIFY_DIR/$asset_name" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "Release asset checksum mismatch: $asset_name" >&2
    exit 1
  fi
}

verify_public_package() {
  local expected_sha="$1"
  local public_path="$VERIFY_DIR/LeafReader-$VERSION-public.pkg"
  local actual_sha
  if [[ "$PUBLISH_DRY_RUN" -eq 1 ]]; then
    record_publish_event "public-package-verified"
    return
  fi
  curl --fail --location --retry 5 --retry-delay 2 --retry-all-errors "$DOWNLOAD_URL" --output "$public_path"
  actual_sha="$(shasum -a 256 "$public_path" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "Public release package checksum mismatch." >&2
    exit 1
  fi
}

push_release_tag() {
  if [[ "$PUBLISH_DRY_RUN" -eq 1 ]]; then
    record_publish_event "tag-pushed"
  else
    git push origin "$TAG"
  fi
  REMOTE_TAG_PUSHED=1
}

create_draft_release() {
  local release_notes="$1"
  if [[ "$PUBLISH_DRY_RUN" -eq 1 ]]; then
    record_publish_event "draft-created"
    record_publish_event "package-uploaded"
  else
    gh release create "$TAG" "$PKG_PATH" --draft --title "Leaf Reader $VERSION" --notes "$release_notes"
  fi
}

upload_optional_release_asset() {
  local asset="$1"
  if [[ "$PUBLISH_DRY_RUN" -eq 1 ]]; then
    record_publish_event "optional-asset-uploaded:$(basename "$asset")"
  else
    gh release upload "$TAG" "$asset" --clobber
  fi
}

publish_draft_release() {
  if [[ "$PUBLISH_DRY_RUN" -eq 1 ]]; then
    record_publish_event "release-published"
  else
    gh release edit "$TAG" --draft=false
  fi
}

push_release_commit() {
  if [[ "$PUBLISH_DRY_RUN" -eq 1 ]]; then
    record_publish_event "main-pushed"
  else
    git push origin main
  fi
}

publish_release_transaction() {
  local release_notes="Leaf Reader $VERSION release.

SHA256: $SHA256"
  push_release_tag
  inject_publish_failure_if_requested "release-creation"
  create_draft_release "$release_notes"
  inject_publish_failure_if_requested "package-upload"
  inject_publish_failure_if_requested "asset-verification"
  verify_release_asset "$PKG_PATH"

  if [[ "$UPLOAD_SPEECH_MODELS" -eq 1 ]]; then
    for asset in "${SPEECH_MODEL_ASSETS[@]}"; do
      if [[ "$PUBLISH_DRY_RUN" -ne 1 && ! -f "$asset" ]]; then
        echo "Missing speech model asset: $asset" >&2
        exit 1
      fi
      upload_optional_release_asset "$asset"
      verify_release_asset "$asset"
    done
  else
    echo "Skipping speech model assets; app code points to $RUNTIME_ASSETS_RELEASE_TAG."
  fi

  inject_publish_failure_if_requested "final-publish"
  publish_draft_release
  inject_publish_failure_if_requested "public-verification"
  verify_public_package "$SHA256"
  RELEASE_PUBLISHED=1
  inject_publish_failure_if_requested "main-push"
  push_release_commit
}

if [[ "$PUBLISH_DRY_RUN" -eq 1 ]]; then
  RUNTIME_ASSETS_RELEASE_TAG="test-assets"
  SHA256="dry-run-sha256"
  publish_release_transaction
  exit 0
fi

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
if git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
  echo "Tag already exists on origin: $TAG" >&2
  echo "If the release is already public, recover by pushing main instead of rerunning publication." >&2
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
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release already exists: $TAG" >&2
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
if [[ "$RUNTIME_ASSETS_RELEASE_TAG" == "$TAG" && "$UPLOAD_SPEECH_MODELS" -ne 1 ]]; then
  echo "SpeechRuntimeModel.runtimeAssetsReleaseTag points at $TAG, but --with-speech-models was not provided." >&2
  exit 1
fi
if [[ "$UPLOAD_SPEECH_MODELS" -eq 1 && "$RUNTIME_ASSETS_RELEASE_TAG" != "$TAG" ]]; then
  echo "Refusing to upload speech model assets to $TAG because runtimeAssetsReleaseTag is $RUNTIME_ASSETS_RELEASE_TAG." >&2
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
if git diff --cached --quiet; then
  if [[ "$(git show -s --format=%s HEAD)" != "Release $VERSION" ]]; then
    echo "No release changes to commit and HEAD is not the expected release commit." >&2
    exit 1
  fi
else
  git commit -m "Release $VERSION"
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  if [[ "$(git rev-parse "$TAG^{commit}")" != "$(git rev-parse HEAD)" ]]; then
    echo "Local tag $TAG does not point at the release commit." >&2
    exit 1
  fi
else
  git tag "$TAG"
fi

# The appcast is already in the release commit. The transaction exposes it on
# main only after release assets and the public package have been verified.
publish_release_transaction

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
