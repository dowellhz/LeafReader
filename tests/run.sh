#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
swiftc \
  tests/SQLiteWordRecordStoreTests.swift \
  mac-app/VocabularySRS.swift \
  mac-app/PDFWordRecordStore.swift \
  mac-app/WebWordRecordStore.swift \
  mac-app/WordRecordSQLiteStore.swift \
  -framework Cocoa \
  -lsqlite3 \
  -o /tmp/leafreader-sqlite-word-tests
/tmp/leafreader-sqlite-word-tests
swift tests/LogicTests.swift
