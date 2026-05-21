#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/Leaf Reader.app"
SPARKLE_HOME="${SPARKLE_HOME:-/opt/homebrew/Caskroom/sparkle/2.9.2}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-12.0}"
ARCHS="${ARCHS:-arm64 x86_64}"
KITTEN_RUNTIME_DIR="${KITTEN_RUNTIME_DIR:-$HOME/.local/share/leafreader/kittentts-rs-runtime}"
KITTEN_RUNTIME_ARCHIVE="${KITTEN_RUNTIME_ARCHIVE:-$ROOT_DIR/docs/tts/kitten-tts-rs-macos-arm64.tar.gz}"
KOKORO_RUNTIME="${KOKORO_RUNTIME:-$HOME/.local/share/leafreader/kokoro-coreml/fluidaudiocli}"
KOKORO_RUNTIME_ARCHIVE="${KOKORO_RUNTIME_ARCHIVE:-$ROOT_DIR/docs/tts/kokoro-coreml-macos-arm64.tar.gz}"
ESPEAK_NG_ROOT="${ESPEAK_NG_ROOT:-/opt/homebrew/opt/espeak-ng}"
PCAUDIOLIB_ROOT="${PCAUDIOLIB_ROOT:-/opt/homebrew/opt/pcaudiolib}"
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
elif [[ -f "$KITTEN_RUNTIME_ARCHIVE" ]]; then
  KITTEN_EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-kitten-runtime.XXXXXX")"
  tar -xzf "$KITTEN_RUNTIME_ARCHIVE" -C "$KITTEN_EXTRACT_DIR" ./kitten-tts-aarch64-macos/kitten-tts-server
  mkdir -p "$APP_PATH/Contents/Resources/SpeechRuntimes/kittentts-rs-runtime/kitten-tts-aarch64-macos"
  cp "$KITTEN_EXTRACT_DIR/kitten-tts-aarch64-macos/kitten-tts-server" \
    "$APP_PATH/Contents/Resources/SpeechRuntimes/kittentts-rs-runtime/kitten-tts-aarch64-macos/kitten-tts-server"
  rm -rf "$KITTEN_EXTRACT_DIR"
  chmod 755 \
    "$APP_PATH/Contents/Resources/SpeechRuntimes/kittentts-rs-runtime/kitten-tts-aarch64-macos/kitten-tts-server"
  strip -x "$APP_PATH/Contents/Resources/SpeechRuntimes/kittentts-rs-runtime/kitten-tts-aarch64-macos/kitten-tts-server" || true
else
  echo "Warning: KittenTTS runtime not bundled; missing $KITTEN_RUNTIME_DIR and $KITTEN_RUNTIME_ARCHIVE" >&2
fi
if [[ -x "$ESPEAK_NG_ROOT/bin/espeak-ng" \
      && -f "$ESPEAK_NG_ROOT/lib/libespeak-ng.1.dylib" \
      && -f "$PCAUDIOLIB_ROOT/lib/libpcaudio.0.dylib" \
      && -d "$ESPEAK_NG_ROOT/share/espeak-ng-data" ]]; then
  ESPEAK_NG_LIB_ID="$(otool -L "$ESPEAK_NG_ROOT/bin/espeak-ng" | awk '/libespeak-ng\.1\.dylib/{print $1; exit}')"
  PCAUDIOLIB_ID="$(otool -L "$ESPEAK_NG_ROOT/bin/espeak-ng" | awk '/libpcaudio\.0\.dylib/{print $1; exit}')"
  ESPEAK_NG_DEP_PCAUDIOLIB_ID="$(otool -L "$ESPEAK_NG_ROOT/lib/libespeak-ng.1.dylib" | awk '/libpcaudio\.0\.dylib/{print $1; exit}')"
  ESPEAK_BUNDLE_DIR="$APP_PATH/Contents/Resources/SpeechRuntimes/espeak-ng"
  mkdir -p "$ESPEAK_BUNDLE_DIR/bin" "$ESPEAK_BUNDLE_DIR/lib" "$ESPEAK_BUNDLE_DIR/share"
  cp "$ESPEAK_NG_ROOT/bin/espeak-ng" "$ESPEAK_BUNDLE_DIR/bin/espeak-ng"
  cp "$ESPEAK_NG_ROOT/lib/libespeak-ng.1.dylib" "$ESPEAK_BUNDLE_DIR/lib/libespeak-ng.1.dylib"
  cp "$PCAUDIOLIB_ROOT/lib/libpcaudio.0.dylib" "$ESPEAK_BUNDLE_DIR/lib/libpcaudio.0.dylib"
  cp -R "$ESPEAK_NG_ROOT/share/espeak-ng-data" "$ESPEAK_BUNDLE_DIR/share/espeak-ng-data"
  chmod 755 "$ESPEAK_BUNDLE_DIR/bin/espeak-ng"
  chmod 644 "$ESPEAK_BUNDLE_DIR/lib/libespeak-ng.1.dylib" "$ESPEAK_BUNDLE_DIR/lib/libpcaudio.0.dylib"
  if [[ -n "$ESPEAK_NG_LIB_ID" ]]; then
    install_name_tool -change "$ESPEAK_NG_LIB_ID" \
      "@executable_path/../lib/libespeak-ng.1.dylib" "$ESPEAK_BUNDLE_DIR/bin/espeak-ng"
  fi
  if [[ -n "$PCAUDIOLIB_ID" ]]; then
    install_name_tool -change "$PCAUDIOLIB_ID" \
      "@executable_path/../lib/libpcaudio.0.dylib" "$ESPEAK_BUNDLE_DIR/bin/espeak-ng"
  fi
  install_name_tool -id "@rpath/libespeak-ng.1.dylib" "$ESPEAK_BUNDLE_DIR/lib/libespeak-ng.1.dylib"
  if [[ -n "$ESPEAK_NG_DEP_PCAUDIOLIB_ID" ]]; then
    install_name_tool -change "$ESPEAK_NG_DEP_PCAUDIOLIB_ID" \
      "@loader_path/libpcaudio.0.dylib" "$ESPEAK_BUNDLE_DIR/lib/libespeak-ng.1.dylib"
  fi
  install_name_tool -id "@rpath/libpcaudio.0.dylib" "$ESPEAK_BUNDLE_DIR/lib/libpcaudio.0.dylib"
  strip -x "$ESPEAK_BUNDLE_DIR/bin/espeak-ng" || true
  strip -x "$ESPEAK_BUNDLE_DIR/lib/libespeak-ng.1.dylib" || true
  strip -x "$ESPEAK_BUNDLE_DIR/lib/libpcaudio.0.dylib" || true
else
  echo "Warning: espeak-ng not bundled; missing $ESPEAK_NG_ROOT or $PCAUDIOLIB_ROOT" >&2
fi
if [[ -x "$KOKORO_RUNTIME" ]]; then
  mkdir -p "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml"
  cp "$KOKORO_RUNTIME" "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli"
  chmod 755 "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli"
  strip -x "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli" || true
elif [[ -f "$KOKORO_RUNTIME_ARCHIVE" ]]; then
  KOKORO_EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leafreader-kokoro-runtime.XXXXXX")"
  tar -xzf "$KOKORO_RUNTIME_ARCHIVE" -C "$KOKORO_EXTRACT_DIR" ./fluidaudiocli
  mkdir -p "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml"
  cp "$KOKORO_EXTRACT_DIR/fluidaudiocli" "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli"
  rm -rf "$KOKORO_EXTRACT_DIR"
  chmod 755 "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli"
  strip -x "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli" || true
else
  echo "Warning: Kokoro runtime not bundled; missing $KOKORO_RUNTIME and $KOKORO_RUNTIME_ARCHIVE" >&2
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

RUNTIME_EXECUTABLES=(
  "$APP_PATH/Contents/Resources/SpeechRuntimes/kittentts-rs-runtime/kitten-tts-aarch64-macos/kitten-tts-server"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/espeak-ng/bin/espeak-ng"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/espeak-ng/lib/libespeak-ng.1.dylib"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/espeak-ng/lib/libpcaudio.0.dylib"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli"
)
for RUNTIME_EXECUTABLE in "${RUNTIME_EXECUTABLES[@]}"; do
  if [[ ! -f "$RUNTIME_EXECUTABLE" ]]; then
    continue
  fi
  if [[ "$APP_SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$RUNTIME_EXECUTABLE"
  else
    codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$RUNTIME_EXECUTABLE"
  fi
done

if [[ "$APP_SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_PATH"
else
  codesign --force --deep --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Built and signed: $APP_PATH"
