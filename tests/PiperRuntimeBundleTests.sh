#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/Leaf Reader.app}"
PIPER_RUNTIME_DIR="$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime"
PIPER_BIN="$PIPER_RUNTIME_DIR/piper/piper"
PIPER_LIB_DIR="$PIPER_RUNTIME_DIR/piper-phonemize/lib"
PIPER_ESPEAK_DATA="$PIPER_RUNTIME_DIR/piper-phonemize/share/espeak-ng-data"
KITTEN_ESPEAK_DATA="$APP_PATH/Contents/Resources/SpeechRuntimes/espeak-ng/share/espeak-ng-data"
EXPECTED_RPATH="@executable_path/../piper-phonemize/lib"
EXPECTED_MINOS="12.0"
EXPECTED_GMW_LANGS=(en en-US en-GB-x-rp)
EXPECTED_VOICE_VARIANTS=(f1 f2 f3 f4 f5 m1 m2 m3 m4 m5 m6 m7 m8)
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

assert_pruned_espeak_data() {
  local label="$1"
  local data_dir="$2"

  if [[ ! -f "$data_dir/en_dict" ]]; then
    echo "$label espeak-ng English dictionary missing: $data_dir/en_dict" >&2
    exit 1
  fi

  local extra_dicts
  extra_dicts="$(find "$data_dir" -maxdepth 1 -type f -name '*_dict' ! -name 'en_dict' -print)"
  if [[ -n "$extra_dicts" ]]; then
    echo "$label espeak-ng data should only bundle en_dict; found:" >&2
    echo "$extra_dicts" >&2
    exit 1
  fi

  local extra_lang_dirs
  extra_lang_dirs="$(find "$data_dir/lang" -mindepth 1 -maxdepth 1 -type d ! -name gmw -print)"
  if [[ -n "$extra_lang_dirs" ]]; then
    echo "$label espeak-ng data should only bundle the gmw language family; found:" >&2
    echo "$extra_lang_dirs" >&2
    exit 1
  fi

  for required_lang in "${EXPECTED_GMW_LANGS[@]}"; do
    if [[ ! -e "$data_dir/lang/gmw/$required_lang" ]]; then
      echo "$label espeak-ng language missing: $data_dir/lang/gmw/$required_lang" >&2
      exit 1
    fi
  done

  local extra_gmw_langs
  extra_gmw_langs="$(
    find "$data_dir/lang/gmw" -mindepth 1 -maxdepth 1 | while IFS= read -r lang_entry; do
      lang_name="$(basename "$lang_entry")"
      if ! array_contains "$lang_name" "${EXPECTED_GMW_LANGS[@]}"; then
        echo "$lang_entry"
      fi
    done
  )"
  if [[ -n "$extra_gmw_langs" ]]; then
    echo "$label espeak-ng gmw language data should only bundle English entries; found:" >&2
    echo "$extra_gmw_langs" >&2
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

assert_pruned_espeak_data "Piper" "$PIPER_ESPEAK_DATA"

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

if [[ -d "$APP_PATH/Contents/Resources/SpeechRuntimes/piper-tts-runtime/piper-phonemize/share/vim" ]]; then
  echo "Piper runtime bundle should not include vim syntax files" >&2
  exit 1
fi

if [[ -d "$KITTEN_ESPEAK_DATA" ]]; then
  assert_pruned_espeak_data "Kitten espeak" "$KITTEN_ESPEAK_DATA"
  if [[ -d "$KITTEN_ESPEAK_DATA/mbrola_ph" ]]; then
    echo "Kitten espeak-ng data should not include mbrola phoneme resources" >&2
    exit 1
  fi
  if [[ -d "$KITTEN_ESPEAK_DATA/voices/mb" ]]; then
    echo "Kitten espeak-ng data should not include MBROLA voices" >&2
    exit 1
  fi
  extra_voice_variants="$(
    find "$KITTEN_ESPEAK_DATA/voices/!v" -mindepth 1 -maxdepth 1 | while IFS= read -r voice_entry; do
      voice_name="$(basename "$voice_entry")"
      if ! array_contains "$voice_name" "${EXPECTED_VOICE_VARIANTS[@]}"; then
        echo "$voice_entry"
      fi
    done
  )"
  if [[ -n "$extra_voice_variants" ]]; then
    echo "Kitten espeak-ng voice variants should only bundle compact English variants; found:" >&2
    echo "$extra_voice_variants" >&2
    exit 1
  fi
fi

echo "Piper runtime bundle checks passed."
