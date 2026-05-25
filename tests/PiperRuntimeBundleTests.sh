#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/Leaf Reader.app}"
PIPER_BIN="$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime/piper/piper"
PIPER_LIB_DIR="$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime/piper-phonemize/lib"
PIPER_ESPEAK_DATA="$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime/piper-phonemize/share/espeak-ng-data"
EXPECTED_RPATH="@executable_path/../piper-phonemize/lib"
EXPECTED_GMW_LANGS=(en en-US en-GB-x-rp)

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

BACKUP_DYLIBS="$(find "$PIPER_LIB_DIR" -maxdepth 1 -type f \( -name '*.backup-*' -o -name '*.bak' -o -name '*~' \) -print)"
if [[ -n "$BACKUP_DYLIBS" ]]; then
  echo "Piper runtime bundle should not include backup libraries; found:" >&2
  echo "$BACKUP_DYLIBS" >&2
  exit 1
fi

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
