#!/usr/bin/env bash
set -euo pipefail

MODE="write"

if [[ $# -eq 2 && "$1" == "--check" ]]; then
  MODE="check"
  VERSION="$2"
elif [[ $# -eq 1 ]]; then
  VERSION="$1"
else
  echo "Usage: $0 [--check] <version>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOWNLOAD_URL="https://github.com/dowellhz/LeafReader/releases/download/v$VERSION/LeafReader-$VERSION.pkg"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 1
fi

expect_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "Version check failed: $file does not contain: $needle" >&2
    return 1
  fi
}

check_version_references() {
  local failures=0
  local short_version
  local bundle_version
  short_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/mac-app/Info.plist")"
  bundle_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ROOT_DIR/mac-app/Info.plist")"

  if [[ "$short_version" != "$VERSION" ]]; then
    echo "Version check failed: Info.plist CFBundleShortVersionString is $short_version, expected $VERSION" >&2
    failures=$((failures + 1))
  fi
  if [[ "$bundle_version" != "$VERSION" ]]; then
    echo "Version check failed: Info.plist CFBundleVersion is $bundle_version, expected $VERSION" >&2
    failures=$((failures + 1))
  fi

  expect_contains "$ROOT_DIR/README.md" "[Leaf Reader $VERSION pkg installer]($DOWNLOAD_URL)" || failures=$((failures + 1))
  expect_contains "$ROOT_DIR/README.md" 'Current version: `'"$VERSION"'`' || failures=$((failures + 1))
  expect_contains "$ROOT_DIR/README.md" 'Git tag: `v'"$VERSION"'`' || failures=$((failures + 1))
  expect_contains "$ROOT_DIR/README.md" "[Leaf Reader-$VERSION.pkg]($DOWNLOAD_URL)" || failures=$((failures + 1))
  expect_contains "$ROOT_DIR/README.md" "release/$VERSION/" || failures=$((failures + 1))
  expect_contains "$ROOT_DIR/README.md" "release_pkg.sh $VERSION" || failures=$((failures + 1))

  expect_contains "$ROOT_DIR/docs/index.html" "<title>Leaf Reader $VERSION</title>" || failures=$((failures + 1))
  expect_contains "$ROOT_DIR/docs/index.html" "Leaf Reader $VERSION is a native macOS reader" || failures=$((failures + 1))
  expect_contains "$ROOT_DIR/docs/index.html" "$DOWNLOAD_URL" || failures=$((failures + 1))
  expect_contains "$ROOT_DIR/docs/index.html" "下载 $VERSION" || failures=$((failures + 1))
  expect_contains "$ROOT_DIR/docs/index.html" "当前版本 $VERSION" || failures=$((failures + 1))
  expect_contains "$ROOT_DIR/docs/index.html" "<h2>Leaf Reader $VERSION</h2>" || failures=$((failures + 1))

  if [[ "$failures" -gt 0 ]]; then
    return 1
  fi
  echo "Version references are consistent for $VERSION"
}

if [[ "$MODE" == "check" ]]; then
  check_version_references
  exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$ROOT_DIR/mac-app/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$ROOT_DIR/mac-app/Info.plist"

perl -0pi -e 's#\[Leaf Reader [0-9.]+ pkg installer\]\(https://github\.com/dowellhz/LeafReader/releases/download/v[0-9.]+/LeafReader-[0-9.]+\.pkg\)#[Leaf Reader '"$VERSION"' pkg installer]('"$DOWNLOAD_URL"')#g' "$ROOT_DIR/README.md"
perl -0pi -e 's#Current version: `[^`]+`#Current version: `'"$VERSION"'`#g' "$ROOT_DIR/README.md"
perl -0pi -e 's#Git tag: `v[^`]+`#Git tag: `v'"$VERSION"'`#g' "$ROOT_DIR/README.md"
perl -0pi -e 's#\[Leaf Reader-[0-9.]+\.pkg\]\(https://github\.com/dowellhz/LeafReader/releases/download/v[0-9.]+/LeafReader-[0-9.]+\.pkg\)#[Leaf Reader-'"$VERSION"'.pkg]('"$DOWNLOAD_URL"')#g' "$ROOT_DIR/README.md"
perl -0pi -e 's#release/[0-9.]+/#release/'"$VERSION"'/#g' "$ROOT_DIR/README.md"
perl -0pi -e 's#release_pkg\.sh [0-9.]+#release_pkg.sh '"$VERSION"'#g' "$ROOT_DIR/README.md"

perl -0pi -e 's#<title>Leaf Reader [0-9.]+</title>#<title>Leaf Reader '"$VERSION"'</title>#g' "$ROOT_DIR/docs/index.html"
perl -0pi -e 's#Leaf Reader [0-9.]+ is a native macOS reader#Leaf Reader '"$VERSION"' is a native macOS reader#g' "$ROOT_DIR/docs/index.html"
perl -0pi -e 's#https://github\.com/dowellhz/LeafReader/releases/download/v[0-9.]+/LeafReader-[0-9.]+\.pkg#'"$DOWNLOAD_URL"'#g' "$ROOT_DIR/docs/index.html"
perl -0pi -e 's#下载 [0-9.]+#下载 '"$VERSION"'#g' "$ROOT_DIR/docs/index.html"
perl -0pi -e 's#当前版本 [0-9.]+#当前版本 '"$VERSION"'#g' "$ROOT_DIR/docs/index.html"
perl -0pi -e 's#<h2>Leaf Reader [0-9.]+</h2>#<h2>Leaf Reader '"$VERSION"'</h2>#g' "$ROOT_DIR/docs/index.html"

echo "Updated Leaf Reader version references to $VERSION"
check_version_references
