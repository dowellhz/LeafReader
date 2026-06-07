#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
APP_PATH="$ROOT_DIR/Leaf Reader.app"
APPCAST_PATH="$ROOT_DIR/docs/appcast.xml"
ECDICT_DB="$ROOT_DIR/mac-app/Resources/ECDICT/ecdict.db"
BUILT_ECDICT_DB="$APP_PATH/Contents/Resources/ECDICT/ecdict.db"
INFO_PLIST="$ROOT_DIR/mac-app/Info.plist"

cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "OK: $*"
}

sqlite_count() {
  local db_path="$1"
  sqlite3 "file:$db_path?mode=ro&immutable=1" 'select count(*) from stardict;' 2>/dev/null || true
}

if [[ -n "$VERSION" && ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  fail "Invalid version: $VERSION"
fi

echo "==> Release preflight${VERSION:+ for $VERSION}"

[[ -z "$(git status --porcelain)" ]] && pass "working tree clean" || {
  git status --short
  fail "working tree is not clean"
}

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
if [[ -n "$VERSION" ]]; then
  [[ "$SHORT_VERSION" == "$VERSION" ]] || fail "CFBundleShortVersionString is $SHORT_VERSION, expected $VERSION"
  [[ "$BUNDLE_VERSION" == "$VERSION" ]] || fail "CFBundleVersion is $BUNDLE_VERSION, expected $VERSION"
fi
pass "Info.plist version $SHORT_VERSION ($BUNDLE_VERSION)"

[[ -f "$ECDICT_DB" ]] || fail "source ECDICT db missing: $ECDICT_DB"
ECDICT_COUNT="$(sqlite_count "$ECDICT_DB")"
[[ "$ECDICT_COUNT" =~ ^[0-9]+$ && "$ECDICT_COUNT" -gt 0 ]] || fail "source ECDICT db has no stardict rows"
pass "source ECDICT db: $ECDICT_COUNT rows, $(du -h "$ECDICT_DB" | awk '{print $1}')"

[[ -d "$APP_PATH" ]] || fail "built app missing: $APP_PATH"
[[ -f "$BUILT_ECDICT_DB" ]] || fail "built app ECDICT db missing: $BUILT_ECDICT_DB"
BUILT_ECDICT_COUNT="$(sqlite_count "$BUILT_ECDICT_DB")"
[[ "$BUILT_ECDICT_COUNT" == "$ECDICT_COUNT" ]] || fail "built ECDICT rows $BUILT_ECDICT_COUNT do not match source $ECDICT_COUNT"
pass "built app ECDICT db included"

codesign --verify --deep --strict "$APP_PATH"
pass "built app code signature verifies"

[[ -f "$APPCAST_PATH" ]] || fail "appcast missing: $APPCAST_PATH"
xmllint --noout "$APPCAST_PATH"
grep -q '<description xml:lang="zh">' "$APPCAST_PATH" || fail "appcast missing zh release notes"
grep -q '<description xml:lang="en">' "$APPCAST_PATH" || fail "appcast missing en release notes"
grep -q 'sparkle:edSignature=' "$APPCAST_PATH" || fail "appcast missing Sparkle edSignature"
pass "appcast XML and localized release notes"

if [[ -n "$VERSION" ]]; then
  PKG_PATH="$ROOT_DIR/release/$VERSION/LeafReader-$VERSION.pkg"
  if [[ -f "$PKG_PATH" ]]; then
    pkgutil --check-signature "$PKG_PATH" >/dev/null
    spctl --assess --type install "$PKG_PATH" >/dev/null
    pass "release pkg signature and Gatekeeper assessment"
    pass "release pkg size $(du -h "$PKG_PATH" | awk '{print $1}')"
  else
    echo "WARN: release pkg not found yet: $PKG_PATH"
  fi

  if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "WARN: local tag already exists: v$VERSION"
  else
    pass "local tag v$VERSION is available"
  fi
fi

pass "release preflight complete"
