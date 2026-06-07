#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/docs/tts}"
WORK_DIR="${TMPDIR:-/tmp}/leafreader-speech-runtime-packages"
MANIFEST_PATH="$OUT_DIR/speech-models-manifest.json"

KOKORO_MODEL_CACHE_ROOT="${KOKORO_MODEL_CACHE_ROOT:-$HOME/.cache/fluidaudio/Models}"
KITTEN_RUNTIME_DIR="${KITTEN_RUNTIME_DIR:-$HOME/.local/share/leafreader/kittentts-rs-runtime}"
PIPER_VOICE_CACHE_ROOT="${PIPER_VOICE_CACHE_ROOT:-$HOME/.cache/leafreader/piper-voices}"
SUPERTONIC_RUNTIME="${SUPERTONIC_RUNTIME:-$HOME/.local/share/leafreader/supertonic-coreml/supertonic-mini}"
SUPERTONIC_MODEL_DIR="${SUPERTONIC_MODEL_DIR:-$HOME/.cache/fluidaudio/Models/supertonic-3}"

mkdir -p "$OUT_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
PACKAGED_ASSETS=()

if [[ -d "$KOKORO_MODEL_CACHE_ROOT/kokoro" && -d "$KOKORO_MODEL_CACHE_ROOT/kokoro-82m-coreml" ]]; then
  KOKORO_STAGE="$WORK_DIR/kokoro-coreml"
  mkdir -p "$KOKORO_STAGE/Models"
  cp -R "$KOKORO_MODEL_CACHE_ROOT/kokoro" "$KOKORO_STAGE/Models/kokoro"
  cp -R "$KOKORO_MODEL_CACHE_ROOT/kokoro-82m-coreml" "$KOKORO_STAGE/Models/kokoro-82m-coreml"
  find "$KOKORO_STAGE/Models/kokoro-82m-coreml" -type d -name '*.mlpackage' -prune -exec rm -rf {} +
  if [[ -d "$KOKORO_STAGE/Models/kokoro-82m-coreml/ANE" ]]; then
    find "$KOKORO_STAGE/Models/kokoro-82m-coreml/ANE" -maxdepth 1 -type f -name '*.bin' -delete
  fi
  if [[ -d "$KOKORO_STAGE/Models/kokoro-82m-coreml/ANE-zh/voices" ]]; then
    find "$KOKORO_STAGE/Models/kokoro-82m-coreml/ANE-zh/voices" -maxdepth 1 -type f -name '*.bin' -delete
  fi
  tar -C "$KOKORO_STAGE" -czf "$OUT_DIR/kokoro-coreml-macos-arm64.tar.gz" .
  echo "Packaged $OUT_DIR/kokoro-coreml-macos-arm64.tar.gz"
  PACKAGED_ASSETS+=("$OUT_DIR/kokoro-coreml-macos-arm64.tar.gz")
else
  echo "Skipping Kokoro package; missing model cache." >&2
fi

if [[ -d "$KITTEN_RUNTIME_DIR/kitten-tts-mini" ]]; then
  KITTEN_STAGE="$WORK_DIR/kitten-tts-rs"
  mkdir -p "$KITTEN_STAGE"
  cp -R "$KITTEN_RUNTIME_DIR/kitten-tts-mini" "$KITTEN_STAGE/"
  tar -C "$KITTEN_STAGE" -czf "$OUT_DIR/kitten-tts-rs-macos-arm64.tar.gz" .
  echo "Packaged $OUT_DIR/kitten-tts-rs-macos-arm64.tar.gz"
  PACKAGED_ASSETS+=("$OUT_DIR/kitten-tts-rs-macos-arm64.tar.gz")
else
  echo "Skipping Kitten package; missing model directory." >&2
fi

if [[ -f "$PIPER_VOICE_CACHE_ROOT/en_US-lessac-high.onnx" \
      && -f "$PIPER_VOICE_CACHE_ROOT/en_US-lessac-high.onnx.json" ]]; then
  PIPER_STAGE="$WORK_DIR/piper-tts"
  mkdir -p "$PIPER_STAGE/Voices"
  cp "$PIPER_VOICE_CACHE_ROOT/en_US-lessac-high.onnx" "$PIPER_STAGE/Voices/"
  cp "$PIPER_VOICE_CACHE_ROOT/en_US-lessac-high.onnx.json" "$PIPER_STAGE/Voices/"
  tar -C "$PIPER_STAGE" -czf "$OUT_DIR/piper-tts-macos-arm64.tar.gz" .
  echo "Packaged $OUT_DIR/piper-tts-macos-arm64.tar.gz"
  PACKAGED_ASSETS+=("$OUT_DIR/piper-tts-macos-arm64.tar.gz")
else
  echo "Skipping Piper package; missing voice cache." >&2
fi

if [[ -x "$SUPERTONIC_RUNTIME" && -d "$SUPERTONIC_MODEL_DIR" ]]; then
  SUPERTONIC_STAGE="$WORK_DIR/supertonic-coreml"
  mkdir -p "$SUPERTONIC_STAGE/Models"
  cp "$SUPERTONIC_RUNTIME" "$SUPERTONIC_STAGE/supertonic-mini"
  chmod 755 "$SUPERTONIC_STAGE/supertonic-mini"
  cp -R "$SUPERTONIC_MODEL_DIR" "$SUPERTONIC_STAGE/Models/supertonic-3"
  find "$SUPERTONIC_STAGE/Models/supertonic-3" -type d -name '*.mlpackage' -prune -exec rm -rf {} +
  tar -C "$SUPERTONIC_STAGE" -czf "$OUT_DIR/supertonic-coreml-macos-arm64.tar.gz" .
  echo "Packaged $OUT_DIR/supertonic-coreml-macos-arm64.tar.gz"
  PACKAGED_ASSETS+=("$OUT_DIR/supertonic-coreml-macos-arm64.tar.gz")
else
  echo "Skipping Supertonic package; missing runtime or model cache." >&2
fi

{
  echo "{"
  echo "  \"generatedAt\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
  echo "  \"assets\": ["
  for index in "${!PACKAGED_ASSETS[@]}"; do
    asset="${PACKAGED_ASSETS[$index]}"
    name="$(basename "$asset")"
    size="$(stat -f '%z' "$asset")"
    sha256="$(shasum -a 256 "$asset" | awk '{print $1}')"
    comma=","
    if [[ "$index" -eq $((${#PACKAGED_ASSETS[@]} - 1)) ]]; then
      comma=""
    fi
    echo "    {"
    echo "      \"name\": \"$name\","
    echo "      \"size\": $size,"
    echo "      \"sha256\": \"$sha256\""
    echo "    }$comma"
  done
  echo "  ]"
  echo "}"
} > "$MANIFEST_PATH"
echo "Wrote $MANIFEST_PATH"
