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

## Change Document Loading Or Web Marks

Start with:

- `mac-app/DocumentLoading.swift`
- `mac-app/DocumentLoading+Archive.swift`
- `mac-app/DocumentLoading+DOCXStreaming.swift`
- `mac-app/DocumentLoading+DOCXCache.swift`
- `mac-app/ReaderWindowController+DocumentLoading.swift`
- `mac-app/Resources/reader-web-text.js`
- `mac-app/Resources/reader-web-marks.js`
- `mac-app/Resources/reader-web-search.js`

Run:

```sh
./tests/run.sh
./scripts/check.sh --no-build
./scripts/build_app.sh
```

Watch for:

- A superseded EPUB or DOCX load mutating the current document or leaving temporary resources behind.
- Reusing prepared DOCX output after the source bytes change, even when path, size, or timestamp are unchanged.
- Publishing an incomplete DOCX cache entry after cancellation or extraction failure.
- Forgetting to invalidate normalized Web text indexes after a DOM text mutation.
- Relying on CSS Custom Highlight without retaining the DOM-span fallback required by older WebKit versions.
- Starting PDF table-of-contents, cover, or persisted-mark restoration before the first visible reader update.

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

## Change UI Controls Or Theme Styling

Start with the local surface that owns the controls, then check the shared theme helpers:

- `mac-app/ReaderTheme.swift`
- `mac-app/ReaderTheme+Palette.swift`
- `mac-app/ReaderWindowController+Theme.swift`
- `mac-app/AIChatPanel+BubbleStyling.swift`
- `mac-app/ReadingNotePanelController+Theme.swift`
- `mac-app/ReadingNotesPanelController.swift`
- `mac-app/AISettingsPanelController+Theme.swift`
- `mac-app/ExportPanelSupport.swift`

Run:

```sh
./scripts/check.sh --no-build
./scripts/check_ui_theme.sh --warnings-as-errors
./scripts/build_app.sh
```

`build_app.sh` defaults to `--debug --arm64` for faster daily iteration. Use `./scripts/build_app.sh --release --universal` only when checking release-style architecture output.

UI rule:

- Every new visible control must define or inherit colors for all reader modes: original, eyeCare, and dark.
- Icon-only buttons must set `contentTintColor` from the active theme, not a fixed system color.
- Controls created after startup must use the current theme at creation time and must also be updated by the surface's theme refresh path.
- If a control is inside a dynamic row, bubble, note, or popup accessory view, theme refresh must walk existing subviews and update it.
- Save panels and other macOS accessory views should hide irrelevant system fields, such as tags, when they are not part of the app workflow.
- `./scripts/check_ui_theme.sh` fails high-confidence icon tint misses by default; fixed `NSColor(...)` usage is reported as warning unless `--warnings-as-errors` is passed.

Watch for:

- Adding a button that looks correct on first render but does not change after switching to eyeCare or dark mode.
- Updating text colors but missing SF Symbol tint, border color, hover/background color, or disabled state.
- Styling only the app-level toolbar while leaving AI bubbles, reading notes, settings, or export panels on their previous colors.
- Introducing a new themed control without adding it to the relevant `setTheme`, `applyTheme`, or `restyle...` traversal.

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

## Change Read Aloud Or TTS Models

Start with:

- `mac-app/SpeechPlaybackCoordinator.swift`
- `mac-app/SpeechRuntimeResourceManager.swift`
- `mac-app/AISettingsPanelController+Speech.swift`
- `mac-app/AISettingsPanelController+Build.swift`
- `mac-app/ReaderWindowController+ReadAloud.swift`
- `mac-app/ReaderWindowController+ReadAloudProgress.swift`

Current model/runtime notes:

- Piper is the macOS 12+ local read-aloud runtime.
- Kokoro can be downloaded on older systems, but requires macOS 14+ to run.
- See `docs/wiki/tts.md` for the full TTS code map, runtime rules, and release packaging notes.

Run:

```sh
./tests/run.sh
./scripts/build_app.sh --release --universal
./scripts/audit_app_bundle.sh
```

Watch for:

- Letting users select a model that is downloaded but has no runnable backend.
- Reintroducing Python/MLX dependencies into the app bundle.
- Keeping more than one local TTS model loaded in memory.
- Breaking EPUB/PDF temporary read-aloud highlighting.

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
