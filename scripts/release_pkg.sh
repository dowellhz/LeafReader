#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version> [release-notes-html-file]" >&2
  exit 1
fi

VERSION="$1"
NOTES_FILE="${2:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/Leaf Reader.app"
PKG_ROOT="/private/tmp/leafreader-pkg-root-$VERSION"
RELEASE_DIR="$ROOT_DIR/release/$VERSION"
UNSIGNED_PKG="$RELEASE_DIR/LeafReader-$VERSION-unsigned.pkg"
SIGNED_PKG="$RELEASE_DIR/LeafReader-$VERSION.pkg"
APPCAST_PATH="$ROOT_DIR/docs/appcast.xml"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_app.sh"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-Developer ID Application: lu lin (T84BKD53ZD)}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-Developer ID Installer: lu lin (T84BKD53ZD)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-leafreader-notary}"
SPARKLE_HOME="${SPARKLE_HOME:-/opt/homebrew/Caskroom/sparkle/2.9.2}"
SIGN_UPDATE="$SPARKLE_HOME/bin/sign_update"
DOWNLOAD_URL="https://github.com/dowellhz/LeafReader/releases/download/v$VERSION/LeafReader-$VERSION.pkg"

if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "Sparkle sign_update not found at $SIGN_UPDATE" >&2
  exit 1
fi

if [[ ! -x "$BUILD_SCRIPT" ]]; then
  echo "Build script not found or not executable: $BUILD_SCRIPT" >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$ROOT_DIR/mac-app/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$ROOT_DIR/mac-app/Info.plist"

APP_SIGN_IDENTITY="$APP_SIGN_IDENTITY" "$BUILD_SCRIPT"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications" "$RELEASE_DIR"
cp -R "$APP_PATH" "$PKG_ROOT/Applications/"

pkgbuild \
  --root "$PKG_ROOT" \
  --identifier com.linlu.leafreader \
  --version "$VERSION" \
  --install-location / \
  "$UNSIGNED_PKG"

productsign --sign "$INSTALLER_IDENTITY" "$UNSIGNED_PKG" "$SIGNED_PKG"
pkgutil --check-signature "$SIGNED_PKG"

xcrun notarytool submit "$SIGNED_PKG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$SIGNED_PKG"
xcrun stapler validate "$SIGNED_PKG"
spctl --assess --type install --verbose=4 "$SIGNED_PKG"

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  SIGN_OUTPUT="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$SIGNED_PKG")"
elif [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  SIGN_OUTPUT="$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$SIGNED_PKG")"
else
  SIGN_OUTPUT="$("$SIGN_UPDATE" "$SIGNED_PKG")"
fi

ED_SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<< "$SIGN_OUTPUT")"
PKG_LENGTH="$(sed -n 's/.*length="\([^"]*\)".*/\1/p' <<< "$SIGN_OUTPUT")"

if [[ -z "$ED_SIGNATURE" || -z "$PKG_LENGTH" ]]; then
  echo "Unable to parse Sparkle signature output: $SIGN_OUTPUT" >&2
  exit 1
fi

if [[ -n "$NOTES_FILE" ]]; then
  NOTES_HTML="$(cat "$NOTES_FILE")"
else
  NOTES_HTML="<ul><li>Leaf Reader $VERSION release.</li></ul>"
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
      <description><![CDATA[
        $NOTES_HTML
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
shasum -a 256 "$SIGNED_PKG"
echo "Release pkg: $SIGNED_PKG"
echo "Updated appcast: $APPCAST_PATH"
