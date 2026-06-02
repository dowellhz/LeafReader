# Word Highlights

关键词：背单词、词汇、复习、SRS、单词高亮、Anki CSV、导出。

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
- The vocabulary panel shows learning stats for the current book: total words, reviewed today, mastered words, estimated recall rate, and active review streak.
- The estimated recall rate is derived from SRS review and lapse counts; it is a compact progress signal, not a full per-review history.
- SQLite schema migrations use `SQLiteSchemaMigrator.ensureColumn` so new columns are added only when missing instead of relying on duplicate-column errors.

## Related Files

- `mac-app/ReaderWindowController+Vocabulary.swift`
- `mac-app/ReaderWindowController+VocabularyHighlights.swift`
- `mac-app/ReaderWindowController+VocabularyReviewUI.swift`
- `mac-app/ReaderWindowController+VocabularyReviewSRS.swift`
- `mac-app/WordRecordSQLiteStore.swift`
- `mac-app/VocabularyLearningStats.swift`
- `mac-app/SQLiteSchemaMigrator.swift`
- `mac-app/VocabularySRS.swift`
- `mac-app/VocabularyExporter.swift`
