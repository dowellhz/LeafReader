# Word Highlights

Leaf Reader stores vocabulary words, explanations, source context, and visible highlights for PDF and web-rendered documents.

## Flow

```text
Select word
  -> Ask AI
  -> Word record
  -> SQLite store
  -> Restore
     -> PDF highlight
     -> Web highlight
```

## Files

- `ReaderWindowController+Vocabulary*.swift`: vocabulary UI, actions, review, export, and persistence.
- `WordRecordSQLiteStore.swift`: production SQLite store.
- `PDFWordRecordStore.swift`, `WebWordRecordStore.swift`: record models and wrappers.
- `StoredPDFWordRect.swift`: PDF highlight geometry.
- `mac-app/Resources/reader-web.js`: WebKit selection, text range lookup, word highlight restore, AI source underline restore.

## Notes

- PDF words store page index and PDF bounds.
- EPUB/DOCX words store text context, occurrence index, and scroll progress.
- Web text lookup normalizes whitespace to improve restore accuracy across rendered HTML.
