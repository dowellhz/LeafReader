#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/Leaf Reader.app}"
PIPER_RUNTIME_DIR="$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime"
PIPER_BIN="$PIPER_RUNTIME_DIR/piper/piper"
PIPER_LIB_DIR="$PIPER_RUNTIME_DIR/piper-phonemize/lib"
PIPER_ESPEAK_DATA="$PIPER_RUNTIME_DIR/piper-phonemize/share/espeak-ng-data"
EXPECTED_RPATH="@executable_path/../piper-phonemize/lib"
EXPECTED_MINOS="12.0"
EXPECTED_GMW_LANGS=(en en-US en-GB-x-rp)
PIPER_MACHO_FILES=(
  "$PIPER_BIN"
  "$PIPER_LIB_DIR/libespeak-ng.1.52.0.1.dylib"
  "$PIPER_LIB_DIR/libonnxruntime.1.14.1.dylib"
  "$PIPER_LIB_DIR/libpiper_phonemize.1.2.0.dylib"
)

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

assert_macos_minos() {
  local path="$1"
  local minos

  minos="$(vtool -show-build "$path" | awk '/minos/{print $2; exit}')"
  if [[ "$minos" != "$EXPECTED_MINOS" ]]; then
    echo "Piper runtime file has unexpected minimum macOS version: $path" >&2
    echo "Expected minos $EXPECTED_MINOS, found ${minos:-unknown}" >&2
    exit 1
  fi
}

if [[ ! -x "$PIPER_BIN" ]]; then
  echo "Piper runtime executable missing: $PIPER_BIN" >&2
  exit 1
fi

if ! otool -l "$PIPER_BIN" | grep -Fq "path $EXPECTED_RPATH"; then
  echo "Piper runtime is missing required LC_RPATH: $EXPECTED_RPATH" >&2
  otool -l "$PIPER_BIN" | grep -A2 LC_RPATH >&2 || true
  exit 1
fi

if [[ ! -f "$PIPER_ESPEAK_DATA/en_dict" ]]; then
  echo "Piper espeak-ng English dictionary missing: $PIPER_ESPEAK_DATA/en_dict" >&2
  exit 1
fi

EXTRA_DICTS="$(find "$PIPER_ESPEAK_DATA" -maxdepth 1 -type f -name '*_dict' ! -name 'en_dict' -print)"
if [[ -n "$EXTRA_DICTS" ]]; then
  echo "Piper espeak-ng data should only bundle en_dict; found:" >&2
  echo "$EXTRA_DICTS" >&2
  exit 1
fi

BACKUP_FILES="$(find "$PIPER_RUNTIME_DIR" -type f \( -name '*.backup-*' -o -name '*.bak' -o -name '*~' \) -print)"
if [[ -n "$BACKUP_FILES" ]]; then
  echo "Piper runtime bundle should not include backup files; found:" >&2
  echo "$BACKUP_FILES" >&2
  exit 1
fi

for macho_file in "${PIPER_MACHO_FILES[@]}"; do
  if [[ ! -f "$macho_file" ]]; then
    echo "Piper runtime file missing: $macho_file" >&2
    exit 1
  fi
  assert_macos_minos "$macho_file"
done

EXTRA_LANG_DIRS="$(find "$PIPER_ESPEAK_DATA/lang" -mindepth 1 -maxdepth 1 -type d ! -name gmw -print)"
if [[ -n "$EXTRA_LANG_DIRS" ]]; then
  echo "Piper espeak-ng data should only bundle the gmw language family; found:" >&2
  echo "$EXTRA_LANG_DIRS" >&2
  exit 1
fi

for required_lang in "${EXPECTED_GMW_LANGS[@]}"; do
  if [[ ! -e "$PIPER_ESPEAK_DATA/lang/gmw/$required_lang" ]]; then
    echo "Piper espeak-ng language missing: $PIPER_ESPEAK_DATA/lang/gmw/$required_lang" >&2
    exit 1
  fi
done

EXTRA_GMW_LANGS="$(
  find "$PIPER_ESPEAK_DATA/lang/gmw" -mindepth 1 -maxdepth 1 | while IFS= read -r lang_entry; do
    lang_name="$(basename "$lang_entry")"
    if ! array_contains "$lang_name" "${EXPECTED_GMW_LANGS[@]}"; then
      echo "$lang_entry"
    fi
  done
)"
if [[ -n "$EXTRA_GMW_LANGS" ]]; then
  echo "Piper espeak-ng gmw language data should only bundle English entries; found:" >&2
  echo "$EXTRA_GMW_LANGS" >&2
  exit 1
fi

if [[ -d "$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime/piper-phonemize/share/vim" ]]; then
  echo "Piper runtime bundle should not include vim syntax files" >&2
  exit 1
fi

echo "Piper runtime bundle checks passed."
