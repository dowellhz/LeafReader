#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
KEEP_COUNT=8
APPLY=0

usage() {
  cat >&2 <<'USAGE'
Usage: ./scripts/cleanup_releases.sh [--keep N] [--apply]

Removes ignored generated artifacts from old release/<version> directories.
Defaults to a dry run and keeps the newest 8 versioned release directories.
Non-version directories such as release/size-test are always kept.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)
      [[ $# -ge 2 ]] || {
        echo "Missing value for --keep" >&2
        usage
        exit 1
      }
      KEEP_COUNT="$2"
      shift 2
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! "$KEEP_COUNT" =~ ^[0-9]+$ || "$KEEP_COUNT" -lt 1 ]]; then
  echo "--keep must be a positive integer" >&2
  exit 1
fi

cd "$ROOT_DIR"

if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "No release directory found: $RELEASE_DIR"
  exit 0
fi

versions=()
while IFS= read -r version; do
  versions+=("$version")
done < <(
  find "$RELEASE_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
    | awk '/^[0-9]+(\.[0-9]+)*$/ { print }' \
    | sort -V
)

if [[ "${#versions[@]}" -le "$KEEP_COUNT" ]]; then
  echo "Nothing to clean: ${#versions[@]} versioned release directories, keep $KEEP_COUNT."
  exit 0
fi

remove_count=$((${#versions[@]} - KEEP_COUNT))
remove_versions=("${versions[@]:0:$remove_count}")
keep_versions=("${versions[@]:$remove_count}")

echo "Release cleanup mode: $([[ "$APPLY" -eq 1 ]] && echo apply || echo dry-run)"
echo "Keeping newest $KEEP_COUNT versioned release directories:"
printf ' - %s\n' "${keep_versions[@]}"
echo "Cleaning ignored artifacts from older versioned release directories:"
printf ' - %s\n' "${remove_versions[@]}"

deleted_files=0
deleted_dirs=0

for version in "${remove_versions[@]}"; do
  version_dir="$RELEASE_DIR/$version"
  ignored_files=()
  while IFS= read -r ignored_file; do
    ignored_files+=("$ignored_file")
  done < <(
    find "$version_dir" -type f -print \
      | while IFS= read -r path; do
          if git check-ignore -q "$path"; then
            printf '%s\n' "$path"
          fi
        done
  )

  if [[ "${#ignored_files[@]}" -eq 0 ]]; then
    continue
  fi

  for path in "${ignored_files[@]}"; do
    rel_path="${path#$ROOT_DIR/}"
    if [[ "$APPLY" -eq 1 ]]; then
      rm -f "$path"
    fi
    echo "$([[ "$APPLY" -eq 1 ]] && echo removed || echo would remove): $rel_path"
    deleted_files=$((deleted_files + 1))
  done

  if [[ "$APPLY" -eq 1 ]]; then
    while IFS= read -r empty_dir; do
      rmdir "$empty_dir"
      echo "removed empty dir: ${empty_dir#$ROOT_DIR/}"
      deleted_dirs=$((deleted_dirs + 1))
    done < <(find "$version_dir" -depth -type d -empty)
  fi
done

if [[ "$APPLY" -eq 0 ]]; then
  echo "Dry run complete: $deleted_files file(s) would be removed."
  echo "Re-run with --apply to remove ignored generated artifacts."
else
  echo "Cleanup complete: removed $deleted_files file(s) and $deleted_dirs empty dir(s)."
fi
