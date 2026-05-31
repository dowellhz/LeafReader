#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_SOURCE="$HOME/Library/Application Support/LeafReader/ECDICT/ecdict.db"
DEFAULT_DEST="$ROOT_DIR/mac-app/Resources/ECDICT/ecdict.db"
SOURCE_DB="${1:-$DEFAULT_SOURCE}"
DEST_DB="${2:-$DEFAULT_DEST}"
DEST_DIR="$(dirname "$DEST_DB")"

if [[ ! -f "$SOURCE_DB" ]]; then
  echo "Source ECDICT database not found: $SOURCE_DB" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
TMP_DB="$(mktemp "${TMPDIR:-/tmp}/leafreader-ecdict-lite.XXXXXX.db")"

sqlite3 "$TMP_DB" <<SQL
ATTACH DATABASE '$SOURCE_DB' AS src;

CREATE TABLE stardict (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word TEXT NOT NULL,
  sw TEXT NOT NULL,
  phonetic TEXT,
  definition TEXT,
  translation TEXT,
  pos TEXT,
  collins INTEGER,
  oxford INTEGER,
  tag TEXT,
  bnc INTEGER,
  frq INTEGER,
  exchange TEXT,
  detail TEXT,
  audio TEXT
);

INSERT INTO stardict
(word, sw, phonetic, definition, translation, pos, collins, oxford, tag, bnc, frq, exchange, detail, audio)
SELECT
  word,
  lower(replace(replace(word, ' ', ''), '-', '')),
  phonetic,
  definition,
  translation,
  pos,
  0,
  0,
  tag,
  bnc,
  frq,
  '',
  '',
  ''
FROM src.stardict
WHERE translation <> ''
  AND instr(trim(word), ' ') = 0
  AND (
    CAST(frq AS INTEGER) BETWEEN 1 AND 50000
    OR tag <> ''
  );

CREATE INDEX idx_stardict_word ON stardict(word);
CREATE INDEX idx_stardict_sw ON stardict(sw);
VACUUM;
SQL

cp "$TMP_DB" "$DEST_DB"
MULTI_WORD_COUNT="$(sqlite3 "$DEST_DB" "SELECT count(*) FROM stardict WHERE instr(trim(word), ' ') > 0;")"
EXCHANGE_COUNT="$(sqlite3 "$DEST_DB" "SELECT count(*) FROM stardict WHERE trim(exchange) <> '';")"
if [[ "$MULTI_WORD_COUNT" != "0" ]]; then
  echo "Lite ECDICT contains multi-word entries: $MULTI_WORD_COUNT" >&2
  exit 1
fi
if [[ "$EXCHANGE_COUNT" != "0" ]]; then
  echo "Lite ECDICT contains exchange lookup hints: $EXCHANGE_COUNT" >&2
  exit 1
fi
sqlite3 "$DEST_DB" "SELECT count(*) FROM stardict;"
du -sh "$DEST_DB"
echo "Built lite ECDICT database: $DEST_DB"
