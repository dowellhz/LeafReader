# Development Tasks

Use this page when the task is phrased as "I want to change X" and you need the likely files and checks.

## Change PDF Page Turning

Start with:

- `mac-app/PDFReaderView.swift`
- `mac-app/PDFPagingPolicy.swift`
- `mac-app/ReaderWindowController+Navigation.swift`

Run:

```sh
./scripts/check.sh --no-build
```

Watch for:

- Duplicate page turns after one scroll gesture.
- Losing native PDFKit scroll or rubber-band behavior.
- Thresholds that work for short pages but fail on long technical books.

## Change AI Translation Or Explanations

Start with:

- `mac-app/AIChatPanel+Actions.swift`
- `mac-app/AIChatPanel+Requests.swift`
- `mac-app/AIResponseTextFormatter.swift`
- `mac-app/AIPromptStore.swift`
- `mac-app/AIPrompts.json`

Run:

```sh
./scripts/check.sh --no-build
```

Watch for:

- Streaming text being rendered before hidden reasoning text is stripped.
- Long selected text producing oversized bubble titles.
- Translation chunks losing paragraph spacing or indentation.

## Change Whole-Book AI Analysis

Start with:

- `mac-app/ReaderWindowController+Embedding*.swift`
- `mac-app/PDFDocumentAgentIndex.swift`
- `mac-app/PDFEmbeddingStore.swift`
- `mac-app/EmbeddingClient.swift`
- `mac-app/AISettingsPanelController+ModelEmbedding.swift`

Run:

```sh
./scripts/check.sh --no-build
```

Watch for:

- Re-indexing too eagerly when cached chunks are still valid.
- UI status becoming stale after pause, cancel, failure, or theme change.
- Retrieval returning incomplete evidence without warning the user.

## Change Vocabulary Review

Start with:

- `mac-app/ReaderWindowController+VocabularyReviewUI.swift`
- `mac-app/ReaderWindowController+VocabularyReviewSRS.swift`
- `mac-app/ReaderWindowController+VocabularyReviewQueue.swift`
- `mac-app/VocabularySRS.swift`
- `mac-app/WordRecordSQLiteStore.swift`

Run:

```sh
./scripts/check.sh --no-build
```

Watch for:

- Accidentally deleting user vocabulary data.
- Review queue order changing without updating SRS tests.
- PDF and EPUB/DOCX records diverging.

## Change Bookshelf Or Recent Documents

Start with:

- `mac-app/RecentDocumentsPanelController.swift`
- `mac-app/RecentDocumentsPanelController+Actions.swift`
- `mac-app/RecentDocumentsPanelController+Cards.swift`
- `mac-app/RecentDocumentsStore.swift`
- `mac-app/ReaderWindowController+DocumentShelf.swift`

Run:

```sh
./scripts/check.sh --no-build
```

Watch for:

- Moved files losing stable identity.
- Sorting or import behavior changing without test coverage.
- Shelf actions clearing the wrong document data.

## Publish A New Version

Start with:

- `docs/wiki/release-checklist.md`
- `docs/wiki/release-runbook.md`
- `scripts/release_pkg.sh`
- `scripts/publish_release.sh`
- `docs/appcast.xml`
- `docs/index.html`

Run:

```sh
./scripts/check.sh
./scripts/update_wiki.sh --push
```

Watch for:

- Version references disagreeing between `Info.plist`, `README.md`, website, and appcast.
- Package signing or notarization failures.
- Sparkle update check failing after publishing.
