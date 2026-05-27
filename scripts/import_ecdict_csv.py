#!/usr/bin/env python3
import csv
import sqlite3
import sys
from pathlib import Path


FIELDS = [
    "word",
    "phonetic",
    "definition",
    "translation",
    "pos",
    "collins",
    "oxford",
    "tag",
    "bnc",
    "frq",
    "exchange",
    "detail",
    "audio",
]


def strip_word(word: str) -> str:
    return "".join(ch for ch in word if ch.isalnum()).lower()


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: import_ecdict_csv.py <ecdict.csv> <ecdict.db>", file=sys.stderr)
        return 2

    csv_path = Path(sys.argv[1])
    db_path = Path(sys.argv[2])
    if not csv_path.is_file():
        print(f"CSV not found: {csv_path}", file=sys.stderr)
        return 1

    tmp_path = db_path.with_suffix(db_path.suffix + ".tmp")
    if tmp_path.exists():
        tmp_path.unlink()

    connection = sqlite3.connect(tmp_path)
    try:
        connection.execute(
            """
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
            )
            """
        )
        connection.execute("CREATE INDEX idx_stardict_word ON stardict(word)")
        connection.execute("CREATE INDEX idx_stardict_sw ON stardict(sw)")

        with csv_path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            rows = []
            for row in reader:
                word = (row.get("word") or "").strip()
                if not word:
                    continue
                rows.append([
                    word,
                    strip_word(word),
                    *[(row.get(field) or "") for field in FIELDS[1:]],
                ])
                if len(rows) >= 5000:
                    insert_rows(connection, rows)
                    rows = []
            if rows:
                insert_rows(connection, rows)
        connection.commit()
    finally:
        connection.close()

    tmp_path.replace(db_path)
    return 0


def insert_rows(connection: sqlite3.Connection, rows: list[list[str]]) -> None:
    connection.executemany(
        """
        INSERT INTO stardict
        (word, sw, phonetic, definition, translation, pos, collins, oxford, tag, bnc, frq, exchange, detail, audio)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )


if __name__ == "__main__":
    raise SystemExit(main())

