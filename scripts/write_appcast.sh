#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <version> <download-url> <ed-signature> <pkg-length> <appcast-path>" >&2
  exit 1
fi

VERSION="$1"
DOWNLOAD_URL="$2"
ED_SIGNATURE="$3"
PKG_LENGTH="$4"
APPCAST_PATH="$5"
LEGACY_NOTES_FILE="${RELEASE_NOTES_LEGACY_HTML_FILE:-}"
EN_NOTES_FILE="${RELEASE_NOTES_EN_HTML_FILE:-$LEGACY_NOTES_FILE}"
ZH_NOTES_FILE="${RELEASE_NOTES_ZH_HTML_FILE:-}"

if [[ -n "$EN_NOTES_FILE" ]]; then
  NOTES_HTML_EN="$(cat "$EN_NOTES_FILE")"
else
  NOTES_HTML_EN="<ul><li>Leaf Reader $VERSION release.</li></ul>"
fi

if [[ -n "$ZH_NOTES_FILE" ]]; then
  NOTES_HTML_ZH="$(cat "$ZH_NOTES_FILE")"
else
  NOTES_HTML_ZH="<ul><li>Leaf Reader $VERSION 发布。</li></ul>"
fi

PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Leaf Reader Updates</title>
    <link>https://dowellhz.github.io/LeafReader/</link>
    <description>Leaf Reader macOS app updates.</description>
    <language>zh-CN</language>
    <item>
      <title>Leaf Reader $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
      <pubDate>$PUB_DATE</pubDate>
      <description xml:lang="zh"><![CDATA[
        $NOTES_HTML_ZH
      ]]></description>
      <description xml:lang="en"><![CDATA[
        $NOTES_HTML_EN
      ]]></description>
      <enclosure
        url="$DOWNLOAD_URL"
        sparkle:edSignature="$ED_SIGNATURE"
        length="$PKG_LENGTH"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

xmllint --noout "$APPCAST_PATH"
grep -q '<description xml:lang="zh">' "$APPCAST_PATH"
grep -q '<description xml:lang="en">' "$APPCAST_PATH"
