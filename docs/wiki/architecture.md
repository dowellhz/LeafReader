# Architecture

Leaf Reader is a native macOS reader built with Swift, PDFKit, WebKit, and Sparkle.

## Main Flow

```text
AppDelegate
  -> ReaderWindowController
     -> DocumentLoading
     -> PDFKit PDF View
     -> WebKit EPUB/DOCX View
     -> AIChatPanel
        -> AIClient
     -> SQLite and local stores
```

## Key Areas

- `AppDelegate*.swift`: app lifecycle, menu, help, update UI.
- `ReaderWindowController*.swift`: reader shell, document opening, navigation, search, AI integration, vocabulary, sessions.
- `DocumentLoading*.swift` and `DOCXPreparedCache.swift`: EPUB/DOCX archive handling, shared document helpers, and cancellable DOCX streaming preparation. DOCX preparation extracts only rendering dependencies; prepared output is cached by a content fingerprint, verified before reuse, bounded by entry and byte quotas, and published atomically so concurrent, stale, or interrupted loads cannot replace valid content.
- `ReaderContentBackend.swift`: typed PDFKit and WebKit adapters used by shared navigation and zoom commands while preserving renderer-native behavior.
- `ProcessRunner.swift`: bounded external process execution for archive helpers and other command-line runtimes.
- `PDFDocumentTextSnapshot.swift`: cancellable PDF text extraction and a verified, content-addressed cache reused by whole-document AI indexing. Background extraction and index construction pause briefly during reader interaction.
- `AIChatPanel*.swift`: AI chat UI, request lifecycle, bubble layout, selection handling.
- `AISettingsPanelController*.swift`: settings window, with focused builders for each page and separate speech selection/download extensions.
- `SpeechPlaybackCoordinator.swift`, `SpeechRuntimeResourceManager.swift`, and `RuntimeDownload.swift`: local TTS playback, runtime selection, compatibility, and model downloads.
- `SQLiteTransactionExecutor.swift`: shared checked transaction boundary used by SQLite-backed stores.
- `UserDataBackupService*.swift`: versioned user-data packages, live SQLite snapshots, credential-filtered preferences, integrity validation, and journaled cold-start restore/rollback.
- `AppDelegate+UserDataBackup.swift`: backup and restore menu workflow. Pending restores run before reader controllers and database singletons are created.
- `Resources/reader-web*.js`: focused WebKit reader modules for text, marks, search, TTS ranges, selection events, and bridge installation. Web marks share cached normalized text indexes and prefer CSS Custom Highlight ranges, with a DOM-span fallback for older WebKit versions.
- `RecentDocuments*.swift` and `RecentBookCardView.swift`: bookshelf panel and recent document UI.
- `DocumentIdentity.swift`: streaming content hashes and compatibility mappings that keep document state stable across moves while preventing equal-size, equal-timestamp replacements from inheriting old records.
- `NetworkConnectivityMonitor.swift`: coarse `NWPathMonitor` state for UI availability. Request fallback decisions use errors from the actual model endpoint; app startup performs no unrelated HTTP reachability probe.
- `WordRecordSQLiteStore.swift` and related stores: persistent word and conversation data.
- `TextQuoteAnchor.swift` and `ReaderWindowController+VocabularyHighlights.swift`: semantic PDF occurrence identity plus visible-page, bounded-batch annotation materialization. Stored rectangles remain the compatibility fallback for existing records.

## Design Rule

Large controllers are split by behavior into extensions or focused helper views. New work should prefer adding to an existing focused module instead of growing a general controller file.

Document opening prioritizes first visible content. PDF cover generation, table-of-contents construction, and persisted mark restoration start only after the reader surface is visible, and every asynchronous result is guarded by the active document generation.

Document content identity is calculated off the main thread before persistent state is attached. The same streaming pass calculates the historical MD5 needed to discover state after a move. A compatibility registry associates an existing namespace with its first observed content hash, while contradictory cached content proof prevents replacement bytes from claiming metadata-based state.

Reader selection and automatic background embedding work do not inspect Keychain credentials. Credentials are read only from explicit AI, diagnostics, connection-test, or settings actions. User-data backups exclude all current and legacy API-key preference fields and never copy or replace Keychain items.

## Related Files

- `mac-app/AppDelegate.swift`
- `mac-app/ReaderWindowController.swift`
- `mac-app/ReaderWindowController+UI.swift`
- `mac-app/DocumentLoading.swift`
- `mac-app/DOCXPreparedCache.swift`
- `mac-app/ReaderContentBackend.swift`
- `mac-app/ProcessRunner.swift`
- `mac-app/AIChatPanel.swift`
- `mac-app/SpeechPlaybackCoordinator.swift`
- `mac-app/SpeechRuntimeResourceManager.swift`
- `mac-app/SQLiteTransactionExecutor.swift`
- `mac-app/WordRecordSQLiteStore.swift`
