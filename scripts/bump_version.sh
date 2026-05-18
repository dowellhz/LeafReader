#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOWNLOAD_URL="https://github.com/dowellhz/LeafReader/releases/download/v$VERSION/LeafReader-$VERSION.pkg"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 1
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
