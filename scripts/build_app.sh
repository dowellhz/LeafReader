#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/Leaf Reader.app"
SPARKLE_HOME="${SPARKLE_HOME:-/opt/homebrew/Caskroom/sparkle/2.9.2}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-12.0}"
ARCHS="${ARCHS:-arm64 x86_64}"
KITTEN_RUNTIME_DIR="${KITTEN_RUNTIME_DIR:-$HOME/.local/share/leafreader/kittentts-rs-runtime}"
KOKORO_RUNTIME="${KOKORO_RUNTIME:-$HOME/.local/share/leafreader/kokoro-coreml/fluidaudiocli}"
export COPYFILE_DISABLE=1

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
rm -rf "$APP_PATH/Contents/Resources"
mkdir -p "$APP_PATH/Contents/Resources"
cp "$ROOT_DIR/mac-app/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/mac-app/AIPrompts.json" "$APP_PATH/Contents/Resources/AIPrompts.json"
cp "$ROOT_DIR/mac-app/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ -d "$ROOT_DIR/mac-app/Resources" ]]; then
  cp -R "$ROOT_DIR/mac-app/Resources/." "$APP_PATH/Contents/Resources/"
fi
if [[ -d "$KITTEN_RUNTIME_DIR/kitten-tts-aarch64-macos" ]]; then
  mkdir -p "$APP_PATH/Contents/Resources/SpeechRuntimes/kittentts-rs-runtime"
  mkdir -p "$APP_PATH/Contents/Resources/SpeechRuntimes/kittentts-rs-runtime/kitten-tts-aarch64-macos"
  cp "$KITTEN_RUNTIME_DIR/kitten-tts-aarch64-macos/kitten-tts-server" \
    "$APP_PATH/Contents/Resources/SpeechRuntimes/kittentts-rs-runtime/kitten-tts-aarch64-macos/kitten-tts-server"
  chmod 755 \
    "$APP_PATH/Contents/Resources/SpeechRuntimes/kittentts-rs-runtime/kitten-tts-aarch64-macos/kitten-tts-server"
  strip -x "$APP_PATH/Contents/Resources/SpeechRuntimes/kittentts-rs-runtime/kitten-tts-aarch64-macos/kitten-tts-server" || true
else
  echo "Warning: KittenTTS runtime not bundled; missing $KITTEN_RUNTIME_DIR" >&2
fi
if [[ -x "$KOKORO_RUNTIME" ]]; then
  mkdir -p "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml"
  cp "$KOKORO_RUNTIME" "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli"
  chmod 755 "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli"
  strip -x "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli" || true
else
  echo "Warning: Kokoro runtime not bundled; missing $KOKORO_RUNTIME" >&2
fi
cp -R "$SPARKLE_HOME/Sparkle.framework" "$APP_PATH/Contents/Frameworks/"
find "$APP_PATH" -name '._*' -type f -delete
xattr -cr "$APP_PATH"
xattr -crs "$APP_PATH"

BINARY_PATH="$APP_PATH/Contents/MacOS/Leaf Reader"
TEMP_BINARIES=()
read -r -a BUILD_ARCHS <<< "$ARCHS"
for ARCH in "${BUILD_ARCHS[@]}"; do
  ARCH_BINARY="$APP_PATH/Contents/MacOS/Leaf Reader-$ARCH"
  swiftc "$ROOT_DIR"/mac-app/*.swift \
    -target "$ARCH-apple-macos$MACOS_DEPLOYMENT_TARGET" \
    -F "$SPARKLE_HOME" \
    -o "$ARCH_BINARY" \
    -framework Cocoa \
    -framework PDFKit \
    -framework WebKit \
    -framework CryptoKit \
    -framework AVFoundation \
    -framework Sparkle \
    -lsqlite3 \
    -Xlinker -rpath \
    -Xlinker @executable_path/../Frameworks
  TEMP_BINARIES+=("$ARCH_BINARY")
done

if [[ "${#TEMP_BINARIES[@]}" -eq 1 ]]; then
  mv "${TEMP_BINARIES[0]}" "$BINARY_PATH"
else
  lipo -create -output "$BINARY_PATH" "${TEMP_BINARIES[@]}"
  rm -f "${TEMP_BINARIES[@]}"
fi

xattr -cr "$APP_PATH"
xattr -crs "$APP_PATH"

if [[ "$APP_SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_PATH"
else
  codesign --force --deep --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Built and signed: $APP_PATH"
