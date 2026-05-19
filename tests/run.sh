#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
node --check mac-app/Resources/reader-web.js
node tests/ReaderWebScriptTests.js
swiftc \
  tests/SQLiteWordRecordStoreTests.swift \
  mac-app/VocabularySRS.swift \
  mac-app/StoredPDFWordRect.swift \
  mac-app/PDFWordRecordStore.swift \
  mac-app/WebWordRecordStore.swift \
  mac-app/WordRecordSQLiteStore.swift \
  -framework Cocoa \
  -lsqlite3 \
  -o /tmp/leafreader-sqlite-word-tests
/tmp/leafreader-sqlite-word-tests
swiftc \
  tests/PDFEmbeddingStoreTests.swift \
  mac-app/PDFEmbeddingStore.swift \
  -lsqlite3 \
  -o /tmp/leafreader-pdf-embedding-store-tests
/tmp/leafreader-pdf-embedding-store-tests
swiftc \
  mac-app/AIRequestState.swift \
  mac-app/MarkdownRenderer.swift \
  mac-app/DocumentIdentity.swift \
  mac-app/StoredPDFWordRect.swift \
  mac-app/AIConversationStore.swift \
  tests/RegressionTests.swift \
  -framework Cocoa \
  -o /tmp/leafreader-regression-tests
/tmp/leafreader-regression-tests
swiftc \
  mac-app/EmbeddingWarmupPolicy.swift \
  mac-app/EPUBPackageParser.swift \
  mac-app/EPUBPathResolver.swift \
  mac-app/EPUBHTMLSanitizer.swift \
  mac-app/EPUBTextDecoder.swift \
  tests/EPUBLogicTests.swift \
  tests/LogicTests.swift \
  -o /tmp/leafreader-logic-tests
/tmp/leafreader-logic-tests
