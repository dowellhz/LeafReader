#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/Leaf Reader.app"
SPARKLE_HOME="${SPARKLE_HOME:-/opt/homebrew/Caskroom/sparkle/2.9.2}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-12.0}"
ARCHS="${ARCHS:-arm64 x86_64}"
REQUIRE_BUNDLED_SPEECH_RUNTIMES="${REQUIRE_BUNDLED_SPEECH_RUNTIMES:-0}"
KITTEN_RUNTIME_DIR="${KITTEN_RUNTIME_DIR:-$HOME/.local/share/leafreader/kittentts-rs-runtime}"
KITTEN_RUNTIME_ARCHIVE="${KITTEN_RUNTIME_ARCHIVE:-$ROOT_DIR/docs/tts/kitten-tts-rs-macos-arm64.tar.gz}"
KOKORO_RUNTIME="${KOKORO_RUNTIME:-$HOME/.local/share/leafreader/kokoro-coreml/fluidaudiocli}"
KOKORO_RUNTIME_ARCHIVE="${KOKORO_RUNTIME_ARCHIVE:-$ROOT_DIR/docs/tts/kokoro-coreml-macos-arm64.tar.gz}"
KOKORO_MODEL_CACHE_ROOT="${KOKORO_MODEL_CACHE_ROOT:-$HOME/.cache/fluidaudio/Models}"
SUPERTONIC_RUNTIME="${SUPERTONIC_RUNTIME:-$HOME/.local/share/leafreader/supertonic-coreml/supertonic-mini}"
PIPER_RUNTIME_DIR="${PIPER_RUNTIME_DIR:-$HOME/.local/share/leafreader/piper-tts-runtime}"
ESPEAK_NG_ROOT="${ESPEAK_NG_ROOT:-$HOME/.local/share/leafreader/espeak-ng-macos12}"
PCAUDIOLIB_ROOT="${PCAUDIOLIB_ROOT:-$ESPEAK_NG_ROOT}"
export COPYFILE_DISABLE=1

ESPEAK_BUNDLED_DICTS=(en_dict)
PIPER_ESPEAK_LANG_DIRS=(gmw)
PIPER_ESPEAK_GMW_LANGS=(en en-US en-GB-x-rp)
PIPER_ESPEAK_VOICE_VARIANTS=(f1 f2 f3 f4 f5 m1 m2 m3 m4 m5 m6 m7 m8)

array_contains() {
  local needle="$1"
  shift

  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

prune_directory_entries_except() {
  local directory="$1"
  shift

  [[ -d "$directory" ]] || return 0

  find "$directory" -mindepth 1 -maxdepth 1 | while IFS= read -r entry; do
    local entry_name
    entry_name="$(basename "$entry")"
    if ! array_contains "$entry_name" "$@"; then
      rm -rf "$entry"
    fi
  done
}

prune_espeak_data() {
  local data_dir="$1"

  find "$data_dir" -maxdepth 1 -type f -name '*_dict' | while IFS= read -r dict_path; do
    local dict_name

    dict_name="$(basename "$dict_path")"
    if ! array_contains "$dict_name" "${ESPEAK_BUNDLED_DICTS[@]}"; then
      rm -f "$dict_path"
    fi
  done
}

prune_piper_espeak_data() {
  local data_dir="$1"

  prune_espeak_data "$data_dir"
  rm -rf "$(dirname "$data_dir")/vim"
  prune_directory_entries_except "$data_dir/lang" "${PIPER_ESPEAK_LANG_DIRS[@]}"
  prune_directory_entries_except "$data_dir/lang/gmw" "${PIPER_ESPEAK_GMW_LANGS[@]}"
  prune_directory_entries_except "$data_dir/voices" '!v'
  prune_directory_entries_except "$data_dir/voices/!v" "${PIPER_ESPEAK_VOICE_VARIANTS[@]}"
}

missing_runtime() {
  local message="$1"
  if [[ "$REQUIRE_BUNDLED_SPEECH_RUNTIMES" == "1" ]]; then
    echo "Error: $message" >&2
    exit 1
  fi
  echo "Warning: $message" >&2
}

piper_runtime_complete() {
  local runtime_dir="$1"
  [[ -x "$runtime_dir/piper/piper" \
    && -d "$runtime_dir/piper-phonemize/lib" \
    && -d "$runtime_dir/piper-phonemize/share/espeak-ng-data" \
    && -f "$runtime_dir/piper-phonemize/lib/libespeak-ng.1.52.0.1.dylib" \
    && -f "$runtime_dir/piper-phonemize/lib/libonnxruntime.1.14.1.dylib" \
    && -f "$runtime_dir/piper-phonemize/lib/libpiper_phonemize.1.2.0.dylib" ]]
}

validate_piper_runtime() {
  if [[ ! -d "$PIPER_RUNTIME_DIR" ]]; then
    missing_runtime "Piper runtime not bundled; missing $PIPER_RUNTIME_DIR"
    return
  fi

  if ! piper_runtime_complete "$PIPER_RUNTIME_DIR"; then
    echo "Error: Piper runtime directory exists but is incomplete: $PIPER_RUNTIME_DIR" >&2
    echo "Expected piper/piper plus piper-phonemize lib and espeak-ng-data resources." >&2
    exit 1
  fi

  local piper_file_output
  piper_file_output="$(file "$PIPER_RUNTIME_DIR/piper/piper")"
  if [[ "$piper_file_output" != *"arm64"* ]]; then
    echo "Error: Piper runtime must include arm64: $PIPER_RUNTIME_DIR/piper/piper" >&2
    echo "$piper_file_output" >&2
    exit 1
  fi
}

if [[ ! -d "$SPARKLE_HOME/Sparkle.framework" ]]; then
  echo "Sparkle.framework not found at $SPARKLE_HOME" >&2
  echo "Install Sparkle with: brew install --cask sparkle" >&2
  exit 1
fi

validate_piper_runtime

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
KOKORO_ENGLISH_VOICES=(af_bella af_heart am_adam bf_emma bm_george)
KOKORO_CHINESE_VOICES=(zf_001 zf_002 zf_003 zf_004 zf_005 zm_009 zm_010 zm_011 zm_012 zm_013 af_maple af_sol bf_vale)
KOKORO_BUNDLE_ROOT="$APP_PATH/Contents/Resources/KokoroVoices"
mkdir -p "$KOKORO_BUNDLE_ROOT/English" "$KOKORO_BUNDLE_ROOT/Chinese"
for voice in "${KOKORO_ENGLISH_VOICES[@]}"; do
  source="$KOKORO_MODEL_CACHE_ROOT/kokoro-82m-coreml/ANE/$voice.bin"
  if [[ -f "$source" ]]; then
    cp "$source" "$KOKORO_BUNDLE_ROOT/English/$voice.bin"
  elif [[ ! -f "$KOKORO_BUNDLE_ROOT/English/$voice.bin" ]]; then
    echo "Warning: Kokoro English voice not bundled; missing $source" >&2
  fi
done
for voice in "${KOKORO_CHINESE_VOICES[@]}"; do
  source="$KOKORO_MODEL_CACHE_ROOT/kokoro-82m-coreml/ANE-zh/voices/$voice.bin"
  if [[ -f "$source" ]]; then
    cp "$source" "$KOKORO_BUNDLE_ROOT/Chinese/$voice.bin"
  else
    echo "Warning: Kokoro Chinese voice not bundled; missing $source" >&2
  fi
done
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
  missing_runtime "KittenTTS runtime not bundled; missing $KITTEN_RUNTIME_DIR and $KITTEN_RUNTIME_ARCHIVE"
fi
if piper_runtime_complete "$PIPER_RUNTIME_DIR"; then
  PIPER_BUNDLE_DIR="$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime"
  mkdir -p "$PIPER_BUNDLE_DIR"
  cp -R "$PIPER_RUNTIME_DIR/piper" "$PIPER_BUNDLE_DIR/piper"
  cp -R "$PIPER_RUNTIME_DIR/piper-phonemize" "$PIPER_BUNDLE_DIR/piper-phonemize"
  find "$PIPER_BUNDLE_DIR" -type f \( -name '*.backup-*' -o -name '*.bak' -o -name '*~' \) -delete
  prune_piper_espeak_data "$PIPER_BUNDLE_DIR/piper-phonemize/share/espeak-ng-data"
  find "$PIPER_BUNDLE_DIR" -type d -name '*.dSYM' -prune -exec rm -rf {} +
  chmod 755 "$PIPER_BUNDLE_DIR/piper/piper"
  find "$PIPER_BUNDLE_DIR/piper-phonemize/lib" -type f -name '*.dylib' -exec chmod 755 {} +
  strip -x "$PIPER_BUNDLE_DIR/piper/piper" || true
  install_name_tool -delete_rpath "@executable_path/../piper-phonemize/lib" "$PIPER_BUNDLE_DIR/piper/piper" 2>/dev/null || true
  install_name_tool -add_rpath "@executable_path/../piper-phonemize/lib" "$PIPER_BUNDLE_DIR/piper/piper"
  find "$PIPER_BUNDLE_DIR/piper-phonemize/lib" -type f -name '*.dylib' -exec strip -x {} \; || true
else
  missing_runtime "Piper runtime not bundled; missing $PIPER_RUNTIME_DIR"
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
  prune_espeak_data "$ESPEAK_BUNDLE_DIR/share/espeak-ng-data"
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
  missing_runtime "Kokoro runtime not bundled; missing $KOKORO_RUNTIME and $KOKORO_RUNTIME_ARCHIVE"
fi
if [[ -x "$SUPERTONIC_RUNTIME" ]]; then
  mkdir -p "$APP_PATH/Contents/Resources/SpeechRuntimes/supertonic-coreml"
  cp "$SUPERTONIC_RUNTIME" "$APP_PATH/Contents/Resources/SpeechRuntimes/supertonic-coreml/supertonic-mini"
  chmod 755 "$APP_PATH/Contents/Resources/SpeechRuntimes/supertonic-coreml/supertonic-mini"
  strip -x "$APP_PATH/Contents/Resources/SpeechRuntimes/supertonic-coreml/supertonic-mini" || true
else
  missing_runtime "Supertonic runtime not bundled; missing $SUPERTONIC_RUNTIME"
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
    -framework Network \
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
  "$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime/piper/piper"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime/piper-phonemize/lib/libespeak-ng.1.52.0.1.dylib"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime/piper-phonemize/lib/libonnxruntime.1.14.1.dylib"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime/piper-phonemize/lib/libpiper_phonemize.1.2.0.dylib"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/espeak-ng/bin/espeak-ng"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/espeak-ng/lib/libespeak-ng.1.dylib"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/espeak-ng/lib/libpcaudio.0.dylib"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/kokoro-coreml/fluidaudiocli"
  "$APP_PATH/Contents/Resources/SpeechRuntimes/supertonic-coreml/supertonic-mini"
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
