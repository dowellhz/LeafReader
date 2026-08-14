#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUBLISH_SCRIPT="$ROOT_DIR/scripts/publish_release.sh"
PKG_SCRIPT="$ROOT_DIR/scripts/release_pkg.sh"
WORKFLOW="$ROOT_DIR/.github/workflows/app.yml"
failures=0

transaction_line_number() {
  local pattern="$1"
  awk -v pattern="$pattern" '
    /^publish_release_transaction\(\)/ { in_transaction = 1; next }
    in_transaction && index($0, pattern) { print NR; exit }
  ' "$PUBLISH_SCRIPT"
}

require_order() {
  local earlier_pattern="$1"
  local later_pattern="$2"
  local description="$3"
  local earlier
  local later
  earlier="$(transaction_line_number "$earlier_pattern")"
  later="$(transaction_line_number "$later_pattern")"
  if [[ -z "$earlier" || -z "$later" || "$earlier" -ge "$later" ]]; then
    echo "FAIL release automation: $description" >&2
    failures=$((failures + 1))
  fi
}

require_order 'create_draft_release "$release_notes"' 'verify_release_asset "$PKG_PATH"' \
  "the draft package must be uploaded before checksum verification"
require_order 'verify_release_asset "$PKG_PATH"' 'publish_draft_release' \
  "the uploaded package must be verified before publication"
require_order 'verify_public_package "$SHA256"' 'push_release_commit' \
  "the public package must be verified before the appcast commit reaches main"

if ! grep -Fq 'mktemp -d' "$PKG_SCRIPT" || ! grep -Fq 'trap cleanup_release_temp EXIT' "$PKG_SCRIPT"; then
  echo "FAIL release automation: package staging must use an owned temporary directory with an EXIT trap" >&2
  failures=$((failures + 1))
fi
if ! grep -Fq "trap 'exit 130' INT" "$PKG_SCRIPT" || ! grep -Fq "trap 'exit 143' TERM" "$PKG_SCRIPT"; then
  echo "FAIL release automation: package staging must clean up after interruption and termination" >&2
  failures=$((failures + 1))
fi
if grep -Eq 'PKG_ROOT="/private/tmp|COMPONENT_PLIST="/private/tmp' "$PKG_SCRIPT"; then
  echo "FAIL release automation: package staging paths must not be predictable" >&2
  failures=$((failures + 1))
fi
if git -C "$ROOT_DIR" ls-files | grep -Eq '\.(dmg|pkg|zip)$'; then
  echo "FAIL release automation: binary installers must be published as Release assets, not tracked by Git" >&2
  failures=$((failures + 1))
fi
if [[ ! -f "$WORKFLOW" ]] || ! grep -Fq './scripts/check.sh --no-build' "$WORKFLOW" \
    || ! grep -Fq 'brew install ripgrep' "$WORKFLOW" \
    || ! grep -Fq 'macos-15-intel' "$WORKFLOW" \
    || ! grep -Fq './scripts/build_app.sh --debug --archs' "$WORKFLOW" \
    || ! grep -Fq 'needs: architecture-build' "$WORKFLOW"; then
  echo "FAIL release automation: app CI must run standard checks and native ARM/Intel builds" >&2
  failures=$((failures + 1))
fi

failure_test_root="$(mktemp -d "${TMPDIR:-/private/tmp}/leafreader-release-failure-test.XXXXXX")"
failure_temp_log="$failure_test_root/workspace.txt"
unrelated_sentinel="$failure_test_root/unrelated"
touch "$unrelated_sentinel"
set +e
LEAFREADER_RELEASE_PKG_TEST_TEMP_LOG="$failure_temp_log" \
  LEAFREADER_RELEASE_PKG_INJECT_FAILURE=after-temp-setup \
  "$PKG_SCRIPT" 0.0-test >/dev/null 2>&1
failure_status=$?
set -e
if [[ "$failure_status" -ne 97 || ! -f "$failure_temp_log" ]]; then
  echo "FAIL release automation: injected package failure did not run as expected" >&2
  failures=$((failures + 1))
else
  failure_workspace="$(head -1 "$failure_temp_log")"
  if [[ -e "$failure_workspace" ]]; then
    echo "FAIL release automation: injected failure left its temporary workspace behind" >&2
    failures=$((failures + 1))
  fi
fi
if [[ ! -f "$unrelated_sentinel" ]]; then
  echo "FAIL release automation: package cleanup touched an unrelated path" >&2
  failures=$((failures + 1))
fi
rm -rf "$failure_test_root"

transaction_test_root="$(mktemp -d "${TMPDIR:-/private/tmp}/leafreader-publish-transaction-test.XXXXXX")"
for stage in release-creation package-upload asset-verification final-publish public-verification; do
  transaction_log="$transaction_test_root/$stage.log"
  set +e
  LEAFREADER_PUBLISH_DRY_RUN=1 \
    LEAFREADER_PUBLISH_TEST_LOG="$transaction_log" \
    LEAFREADER_PUBLISH_INJECT_FAILURE="$stage" \
    "$PUBLISH_SCRIPT" 0.0-test >/dev/null 2>&1
  transaction_status=$?
  set -e
  if [[ "$transaction_status" -ne 97 ]] \
      || ! grep -Fxq 'cleanup-release' "$transaction_log" \
      || ! grep -Fxq 'cleanup-tag' "$transaction_log" \
      || grep -Fxq 'main-pushed' "$transaction_log"; then
    echo "FAIL release automation: $stage failure did not preserve the current public appcast" >&2
    failures=$((failures + 1))
  fi
done

main_push_log="$transaction_test_root/main-push.log"
set +e
LEAFREADER_PUBLISH_DRY_RUN=1 \
  LEAFREADER_PUBLISH_TEST_LOG="$main_push_log" \
  LEAFREADER_PUBLISH_INJECT_FAILURE=main-push \
  "$PUBLISH_SCRIPT" 0.0-test >/dev/null 2>&1
main_push_status=$?
set -e
if [[ "$main_push_status" -ne 97 ]] \
    || ! grep -Fxq 'release-published' "$main_push_log" \
    || ! grep -Fxq 'public-package-verified' "$main_push_log" \
    || grep -Fxq 'cleanup-release' "$main_push_log" \
    || grep -Fxq 'main-pushed' "$main_push_log"; then
  echo "FAIL release automation: main-push failure did not leave a verified release with the old appcast" >&2
  failures=$((failures + 1))
fi

success_log="$transaction_test_root/success.log"
LEAFREADER_PUBLISH_DRY_RUN=1 \
  LEAFREADER_PUBLISH_TEST_LOG="$success_log" \
  "$PUBLISH_SCRIPT" 0.0-test >/dev/null
if ! grep -Fxq 'public-package-verified' "$success_log" \
    || ! grep -Fxq 'main-pushed' "$success_log" \
    || grep -Fxq 'cleanup-release' "$success_log"; then
  echo "FAIL release automation: successful dry run did not publish assets before main" >&2
  failures=$((failures + 1))
fi
rm -rf "$transaction_test_root"

if (( failures > 0 )); then
  echo "Release automation checks failed: $failures issue(s)." >&2
  exit 1
fi

echo "Release automation checks passed."
