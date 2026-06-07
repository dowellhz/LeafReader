#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM_REPO="${KITTENTTS_RS_REPO:-https://github.com/second-state/kitten_tts_rs.git}"
UPSTREAM_REF="${KITTENTTS_RS_REF:-2cdd79fdcf79781cec500d6e0a4f3bf08407208b}"
WORK_DIR="${KITTENTTS_RS_WORK_DIR:-${TMPDIR:-/tmp}/leafreader-kittentts-rs-build}"
INSTALL_DIR="${KITTEN_RUNTIME_DIR:-$HOME/.local/share/leafreader/kittentts-rs-runtime}"
PATCH_FILE="$ROOT_DIR/scripts/patches/kittentts-rs-leafreader-wav-only.patch"
SERVER_DIR="$INSTALL_DIR/kitten-tts-aarch64-macos"
SERVER_PATH="$SERVER_DIR/kitten-tts-server"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $0" >&2
  echo "Builds LeafReader's wav-only KittenTTS server runtime and installs it into:" >&2
  echo "  $SERVER_PATH" >&2
  exit 0
fi

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "Patch file missing: $PATCH_FILE" >&2
  exit 1
fi

rm -rf "$WORK_DIR"
git clone "$UPSTREAM_REPO" "$WORK_DIR"
git -C "$WORK_DIR" checkout "$UPSTREAM_REF"
git -C "$WORK_DIR" apply "$PATCH_FILE"

(
  cd "$WORK_DIR"
  RUSTFLAGS="-C opt-level=z -C codegen-units=1 -C panic=abort -C strip=symbols" \
    cargo build --release --bin kitten-tts-server --features coreml
)

mkdir -p "$SERVER_DIR"
if [[ -f "$SERVER_PATH" ]]; then
  backup_path="$SERVER_PATH.backup-$(date -u '+%Y%m%d%H%M%S')"
  cp "$SERVER_PATH" "$backup_path"
  echo "Backed up existing server: $backup_path"
fi

cp "$WORK_DIR/target/release/kitten-tts-server" "$SERVER_PATH"
chmod 755 "$SERVER_PATH"

echo "Installed $SERVER_PATH"
stat -f 'Size: %z bytes' "$SERVER_PATH"
