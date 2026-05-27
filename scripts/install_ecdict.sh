#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_DEST="$HOME/Library/Application Support/LeafReader/ECDICT"
DEST_DIR="${1:-$DEFAULT_DEST}"
SOURCE_URL="${ECDICT_URL:-https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv}"
CSV_PATH="$DEST_DIR/ecdict.csv"
DB_PATH="$DEST_DIR/ecdict.db"

mkdir -p "$DEST_DIR"

if [[ ! -f "$CSV_PATH" ]]; then
  echo "Downloading ECDICT CSV to: $CSV_PATH"
  curl -L --fail --continue-at - "$SOURCE_URL" -o "$CSV_PATH"
else
  echo "Using existing CSV: $CSV_PATH"
fi

echo "Converting ECDICT CSV to SQLite: $DB_PATH"
python3 "$ROOT_DIR/scripts/import_ecdict_csv.py" "$CSV_PATH" "$DB_PATH"
echo "Installed ECDICT dictionary: $DB_PATH"

