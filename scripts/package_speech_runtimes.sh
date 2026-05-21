#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/docs/tts"
WORK_DIR="${TMPDIR:-/tmp}/leafreader-speech-runtime-packages"

KOKORO_RUNTIME="${KOKORO_RUNTIME:-$HOME/.local/share/leafreader/kokoro-coreml/fluidaudiocli}"
KOKORO_MODEL_CACHE="${KOKORO_MODEL_CACHE:-$HOME/.cache/fluidaudio/Models/kokoro}"
KITTEN_RUNTIME_DIR="${KITTEN_RUNTIME_DIR:-$HOME/.local/share/leafreader/kittentts-rs-runtime}"

mkdir -p "$OUT_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

if [[ -x "$KOKORO_RUNTIME" && -d "$KOKORO_MODEL_CACHE" ]]; then
  KOKORO_STAGE="$WORK_DIR/kokoro-coreml"
  mkdir -p "$KOKORO_STAGE/Models"
  cp "$KOKORO_RUNTIME" "$KOKORO_STAGE/fluidaudiocli"
  cp -R "$KOKORO_MODEL_CACHE" "$KOKORO_STAGE/Models/kokoro"
  chmod 755 "$KOKORO_STAGE/fluidaudiocli"
  tar -C "$KOKORO_STAGE" -czf "$OUT_DIR/kokoro-coreml-macos-arm64.tar.gz" .
  echo "Packaged $OUT_DIR/kokoro-coreml-macos-arm64.tar.gz"
else
  echo "Skipping Kokoro package; missing runtime or model cache." >&2
fi

if [[ -d "$KITTEN_RUNTIME_DIR/kitten-tts-aarch64-macos" && -d "$KITTEN_RUNTIME_DIR/kitten-tts-mini" ]]; then
  KITTEN_STAGE="$WORK_DIR/kitten-tts-rs"
  mkdir -p "$KITTEN_STAGE"
  cp -R "$KITTEN_RUNTIME_DIR/kitten-tts-aarch64-macos" "$KITTEN_STAGE/"
  cp -R "$KITTEN_RUNTIME_DIR/kitten-tts-mini" "$KITTEN_STAGE/"
  chmod 755 "$KITTEN_STAGE/kitten-tts-aarch64-macos/kitten-tts" "$KITTEN_STAGE/kitten-tts-aarch64-macos/kitten-tts-server"
  tar -C "$KITTEN_STAGE" -czf "$OUT_DIR/kitten-tts-rs-macos-arm64.tar.gz" .
  echo "Packaged $OUT_DIR/kitten-tts-rs-macos-arm64.tar.gz"
else
  echo "Skipping Kitten package; missing runtime or model directory." >&2
fi
