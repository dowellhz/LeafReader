#!/usr/bin/env bash
set -euo pipefail

ESPEAK_NG_VERSION="${ESPEAK_NG_VERSION:-1.52.0}"
PCAUDIOLIB_VERSION="${PCAUDIOLIB_VERSION:-1.3}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-12.0}"
PREFIX="${ESPEAK_NG_PREFIX:-$HOME/.local/share/leafreader/espeak-ng-macos12}"
WORK_DIR="${TMPDIR:-/tmp}/leafreader-espeak-ng-runtime"

if ! command -v autoconf >/dev/null \
  || ! command -v automake >/dev/null \
  || ! command -v glibtoolize >/dev/null \
  || ! command -v pkg-config >/dev/null; then
  echo "Missing build tools. Install them with: brew install autoconf automake libtool pkgconf" >&2
  exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$PREFIX"

PCAUDIOLIB_ARCHIVE="$WORK_DIR/pcaudiolib-$PCAUDIOLIB_VERSION.tar.gz"
ESPEAK_NG_ARCHIVE="$WORK_DIR/espeak-ng-$ESPEAK_NG_VERSION.tar.gz"

curl -L "https://github.com/espeak-ng/pcaudiolib/releases/download/$PCAUDIOLIB_VERSION/pcaudiolib-$PCAUDIOLIB_VERSION.tar.gz" \
  -o "$PCAUDIOLIB_ARCHIVE"
curl -L "https://github.com/espeak-ng/espeak-ng/archive/refs/tags/$ESPEAK_NG_VERSION.tar.gz" \
  -o "$ESPEAK_NG_ARCHIVE"

tar -xzf "$PCAUDIOLIB_ARCHIVE" -C "$WORK_DIR"
(
  cd "$WORK_DIR/pcaudiolib-$PCAUDIOLIB_VERSION"
  MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
    CFLAGS="-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET" \
    LDFLAGS="-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET" \
    ./configure --prefix="$PREFIX" --disable-silent-rules
  MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" make
  make install
)

tar -xzf "$ESPEAK_NG_ARCHIVE" -C "$WORK_DIR"
(
  cd "$WORK_DIR/espeak-ng-$ESPEAK_NG_VERSION"
  touch NEWS AUTHORS ChangeLog
  autoreconf --force --install --verbose
  MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
    CPPFLAGS="-I$PREFIX/include" \
    CFLAGS="-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET -fvisibility=default" \
    LDFLAGS="-L$PREFIX/lib -mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET" \
    ./configure --prefix="$PREFIX" --disable-silent-rules
  MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" make
  make install
)

vtool -show-build "$PREFIX/bin/espeak-ng"
vtool -show-build "$PREFIX/lib/libespeak-ng.1.dylib"
vtool -show-build "$PREFIX/lib/libpcaudio.0.dylib"
