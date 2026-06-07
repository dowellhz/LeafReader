#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $0 <version|pkg-path> [expected-version]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="$1"
EXPECTED_VERSION="${2:-}"

if [[ -f "$INPUT" ]]; then
  PKG_PATH="$INPUT"
  if [[ -z "$EXPECTED_VERSION" ]]; then
    PKG_NAME="$(basename "$PKG_PATH")"
    EXPECTED_VERSION="$(sed -n 's/^LeafReader-\([0-9][0-9.]*\)\.pkg$/\1/p' <<< "$PKG_NAME")"
  fi
else
  EXPECTED_VERSION="$INPUT"
  PKG_PATH="$ROOT_DIR/release/$EXPECTED_VERSION/LeafReader-$EXPECTED_VERSION.pkg"
fi

if [[ -z "$EXPECTED_VERSION" ]]; then
  echo "Unable to infer expected version. Pass it as the second argument." >&2
  exit 1
fi

if [[ ! "$EXPECTED_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "Invalid expected version: $EXPECTED_VERSION" >&2
  exit 1
fi

if [[ ! -f "$PKG_PATH" ]]; then
  echo "Release pkg not found: $PKG_PATH" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-pkg-smoke.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "==> Checking package signature"
pkgutil --check-signature "$PKG_PATH" >/dev/null
spctl --assess --type install "$PKG_PATH" >/dev/null

echo "==> Expanding package payload"
pkgutil --expand-full "$PKG_PATH" "$TMP_DIR/pkg"

APP_PATH="$TMP_DIR/pkg/Payload/Applications/Leaf Reader.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/Leaf Reader"
ECDICT_DB="$APP_PATH/Contents/Resources/ECDICT/ecdict.db"
SPEECH_RUNTIMES="$APP_PATH/Contents/Resources/SpeechRuntimes"

[[ -d "$APP_PATH" ]] || {
  echo "Expanded app missing: $APP_PATH" >&2
  exit 1
}
[[ -f "$INFO_PLIST" ]] || {
  echo "Info.plist missing from expanded app" >&2
  exit 1
}
[[ -x "$EXECUTABLE" ]] || {
  echo "App executable missing or not executable: $EXECUTABLE" >&2
  exit 1
}
APP_ARCHS="$(lipo -archs "$EXECUTABLE")"
for expected_arch in arm64 x86_64; do
  if [[ " $APP_ARCHS " != *" $expected_arch "* ]]; then
    echo "Release app executable is missing $expected_arch architecture: $APP_ARCHS" >&2
    exit 1
  fi
done

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
[[ "$SHORT_VERSION" == "$EXPECTED_VERSION" ]] || {
  echo "CFBundleShortVersionString is $SHORT_VERSION, expected $EXPECTED_VERSION" >&2
  exit 1
}
[[ "$BUNDLE_VERSION" == "$EXPECTED_VERSION" ]] || {
  echo "CFBundleVersion is $BUNDLE_VERSION, expected $EXPECTED_VERSION" >&2
  exit 1
}

echo "==> Checking bundled resources"
[[ -f "$APP_PATH/Contents/Resources/AIPrompts.json" ]] || {
  echo "AIPrompts.json missing from expanded app" >&2
  exit 1
}
[[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]] || {
  echo "AppIcon.icns missing from expanded app" >&2
  exit 1
}
[[ -f "$ECDICT_DB" ]] || {
  echo "ECDICT database missing from expanded app" >&2
  exit 1
}
ECDICT_COUNT="$(sqlite3 "file:$ECDICT_DB?mode=ro&immutable=1" 'select count(*) from stardict;' 2>/dev/null || true)"
[[ "$ECDICT_COUNT" =~ ^[0-9]+$ && "$ECDICT_COUNT" -gt 0 ]] || {
  echo "ECDICT database has no stardict rows" >&2
  exit 1
}

for runtime in kittentts-rs-runtime piper-tts-runtime espeak-ng kokoro-coreml supertonic-coreml; do
  [[ -e "$SPEECH_RUNTIMES/$runtime" ]] || {
    echo "Speech runtime missing from expanded app: $runtime" >&2
    exit 1
  }
done

echo "==> Checking expanded app signature"
codesign --verify --deep --strict "$APP_PATH"

PKG_SIZE="$(du -h "$PKG_PATH" | awk '{print $1}')"
APP_SIZE="$(du -sh "$APP_PATH" | awk '{print $1}')"
echo "Release pkg smoke test passed."
echo "Version: $EXPECTED_VERSION"
echo "Package: $PKG_PATH ($PKG_SIZE)"
echo "Expanded app: $APP_SIZE"
echo "App architectures: $APP_ARCHS"
echo "ECDICT rows: $ECDICT_COUNT"
