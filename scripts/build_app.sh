#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/Leaf Reader.app"
SPARKLE_HOME="${SPARKLE_HOME:-/opt/homebrew/Caskroom/sparkle/2.9.2}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}"

if [[ ! -d "$SPARKLE_HOME/Sparkle.framework" ]]; then
  echo "Sparkle.framework not found at $SPARKLE_HOME" >&2
  echo "Install Sparkle with: brew install --cask sparkle" >&2
  exit 1
fi

mkdir -p \
  "$APP_PATH/Contents/MacOS" \
  "$APP_PATH/Contents/Resources" \
  "$APP_PATH/Contents/Frameworks"

rm -rf "$APP_PATH/Contents/Frameworks/Sparkle.framework"
cp "$ROOT_DIR/mac-app/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/mac-app/AIPrompts.json" "$APP_PATH/Contents/Resources/AIPrompts.json"
cp "$ROOT_DIR/mac-app/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp -R "$SPARKLE_HOME/Sparkle.framework" "$APP_PATH/Contents/Frameworks/"

swiftc "$ROOT_DIR"/mac-app/*.swift \
  -F "$SPARKLE_HOME" \
  -o "$APP_PATH/Contents/MacOS/Leaf Reader" \
  -framework Cocoa \
  -framework PDFKit \
  -framework WebKit \
  -framework CryptoKit \
  -framework AVFoundation \
  -framework Sparkle \
  -lsqlite3 \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks

if [[ "$APP_SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_PATH"
else
  codesign --force --deep --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Built and signed: $APP_PATH"
