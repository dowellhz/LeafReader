#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/mac-app/Info.plist")"

URLS=(
  "https://leafreader.space/"
  "https://leafreader.space/manual/"
  "https://dowellhz.github.io/LeafReader/appcast.xml"
  "https://github.com/dowellhz/LeafReader"
  "https://github.com/dowellhz/LeafReader/releases/download/v$VERSION/LeafReader-$VERSION.pkg"
)

for url in "${URLS[@]}"; do
  echo "Checking $url"
  curl -I -L --max-time 20 --fail "$url" >/dev/null
done

echo "Docs external link checks passed."
