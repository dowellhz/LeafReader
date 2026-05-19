# Feature Map

Use this page when the task starts from a product feature instead of a file name.

## Reader Shell And Chrome

- `mac-app/ReaderWindowController.swift`: central reader state and shared controls.
- `mac-app/ReaderWindowController+UI.swift`: top toolbar, bottom bar, layout constraints.
- `mac-app/ReaderWindowController+Theme.swift`: light/dark reader chrome styling.
- `mac-app/ReaderChromeViews.swift`: custom chrome controls and clipped containers.
- `mac-app/ReaderWindow.swift`: window drag/drop behavior.

## PDF Reading And Page Turns

- `mac-app/PDFReaderView.swift`: PDFKit view subclass and edge paging events.
- `mac-app/PDFPagingPolicy.swift`: page turn thresholds and duplicate-turn guard.
- `mac-app/ReaderWindowController+Navigation.swift`: page navigation commands.
- `mac-app/ReaderWindowController+PageDiagnostics.swift`: page jump diagnostics.

## EPUB And DOCX Reading

- `mac-app/DocumentLoading.swift`: shared document model and loader entry point.
- `mac-app/DocumentLoading+EPUB.swift`: EPUB package, cover, TOC, and resources.
- `mac-app/DocumentLoading+DOCX.swift`: DOCX paragraph, table, and media rendering.
- `mac-app/DocumentLoading+HTML.swift`: generated HTML wrapper and rewriting.
- `mac-app/Resources/reader-web.js`: WebKit reader behavior, selection, and highlights.

## AI Chat

- `mac-app/AIChatPanel.swift`: AI panel state.
- `mac-app/AIChatPanel+Actions.swift`: summary, translation, explanation, follow-up actions.
- `mac-app/AIChatPanel+Requests.swift`: streaming request lifecycle and retry/cancel.
- `mac-app/AIClient.swift`: provider HTTP and streaming client.
- `mac-app/AIResponseTextFormatter.swift`: visible answer cleanup and translation formatting.
- `mac-app/AIPromptStore.swift` and `mac-app/AIPrompts.json`: built-in prompt templates.

## Whole-Book AI Analysis Cache

- `mac-app/ReaderWindowController+Embedding*.swift`: indexing lifecycle, progress, controls, and retrieval.
- `mac-app/PDFDocumentAgentIndex.swift`: PDF chunking and evidence retrieval.
- `mac-app/PDFEmbeddingStore.swift`: SQLite embedding cache.
- `mac-app/EmbeddingClient.swift`: embedding API calls.
- `mac-app/AISettingsPanelController+ModelEmbedding.swift`: embedding model settings.

## Vocabulary And Review

- `mac-app/ReaderWindowController+Vocabulary*.swift`: vocabulary capture, review UI, navigation, export, persistence.
- `mac-app/VocabularySRS.swift`: spaced repetition scoring.
- `mac-app/WordRecordSQLiteStore.swift`: persistent vocabulary record database.
- `mac-app/PDFWordRecordStore.swift` and `mac-app/WebWordRecordStore.swift`: document-specific word records.
- `mac-app/VocabularyExporter.swift`: Markdown and Anki CSV export.

## Bookshelf And Session Restore

- `mac-app/RecentDocumentsPanelController*.swift`: bookshelf UI and actions.
- `mac-app/RecentDocumentsStore.swift`: recent document persistence.
- `mac-app/ReaderWindowController+DocumentShelf.swift`: shelf presentation and document actions.
- `mac-app/ReaderSessionStore.swift` and `mac-app/ReaderWindowController+Session.swift`: reading position/session persistence.

## Release, Updates, And Website

- `mac-app/AppDelegate+Updates.swift`: Sparkle update UI and manual update checks.
- `mac-app/UpdateFailureClassifier.swift`: user-facing update failure classification.
- `docs/appcast.xml`: Sparkle feed.
- `docs/index.html`: public download page.
- `scripts/release_pkg.sh` and `scripts/publish_release.sh`: package and publish workflow.
- `scripts/update_wiki.sh`: Wiki generation and sync workflow.
