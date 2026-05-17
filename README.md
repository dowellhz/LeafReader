<p align="center">
  <img src="assets/leaf-reader-icon.png" alt="Leaf Reader icon" width="128">
</p>

# Leaf Reader

Leaf Reader is a native macOS reader for PDF, EPUB, and DOCX documents. It is built with Swift, PDFKit, and WebKit, and focuses on a quiet reading experience with fast navigation, document search, reading progress restore, light and dark reader themes, and an optional AI panel for working with selected passages.

## Screenshots

![Leaf Reader word learning in light mode](assets/reader-light-ai-word.png)

![Leaf Reader bookshelf](assets/reader-bookshelf.png)

![Leaf Reader settings](assets/reader-settings.png)

![Leaf Reader passage explanation in dark mode](assets/reader-dark-ai.png)

![Leaf Reader vocabulary book in dark mode](assets/reader-dark-vocabulary.png)

## Download

Download the latest macOS installer:

[Leaf Reader 1.4 pkg installer](https://github.com/dowellhz/LeafReader/releases/download/v1.4/LeafReader-1.4.pkg)

## Highlights

- Open local PDF, EPUB, and DOCX files in one macOS app.
- Restore the last opened document, page, zoom level, and reading position.
- Navigate PDFs with toolbar controls, keyboard paging, scroll paging, and direct page-number entry.
- Search documents with `Command+F`, next and previous result controls, and visible result positioning.
- Switch between light and dark reader themes for the document area, search overlay, recent files panel, and AI chat panel.
- Select text and ask the built-in AI assistant to explain, summarize, or translate passages.
- Configure model, API key, interface language, and reader theme from the in-app settings panel.
- Keep documents local; AI requests are only sent when the assistant is used with the configured API key.

## What's New in 1.4

- Reworked the book vocabulary panel with separate Learn, Review, New Words, and All tabs, paginated word lists, exports, and lower-case review cards.
- Moved word records to SQLite with incremental upsert/delete persistence and production SQLite regression tests.
- Improved drag-and-drop import behavior for one-book and multi-book drops, duplicate handling, bookshelf focus, and recent-reading sorting.
- Added AI conversation trimming, debounced saves, preserved linked word bubbles, and page-jump diagnostics for navigation troubleshooting.
- Fixed embedding provider defaults, SiliconFlow settings, provider-specific API keys, and faster vector scoring with cached embedding norms.
- Split large AI, settings, vocabulary, and storage files into focused modules with broader regression coverage.

## What's New in 1.3.1

- Added drag-and-drop opening for PDF, EPUB, and DOCX files directly in the reader window.
- Added optional AI conversation saving per book, including source page/location for non-vocabulary AI bubbles.
- Clicking saved non-vocabulary AI bubbles can jump back to the recorded page or reading position.
- Improved vector-index state reset when switching books so old cache status is not shown for the new document.
- Split the reader window controller into focused extensions for AI, document loading, embedding, navigation, sessions, UI, and vocabulary logic.

## What's New in 1.3

- Added a bookshelf view with higher-resolution covers, reading progress, add-file support, and contextual actions.
- Improved vocabulary workflows with word aggregation, Anki CSV export, source page/context, pronunciation playback, and safer failed-query handling.
- Added clearer embedding status in the bottom toolbar, including cached, idle, paused, and retry states.
- Improved background indexing so large books open faster and vector generation waits for reader idle time.
- Reworked modal focus handling for settings, bookshelf, and vocabulary panels.
- Added safer cache and word-record clearing with confirmation prompts.

## What's New in 1.2

- Renamed the assistant entry point to `学英语` and improved selected-word and short-phrase explanations.
- Added Markdown rendering for AI answers, reference bubbles, and the book vocabulary panel.
- Added PDF vector retrieval for document Q&A, with current-page priority, background indexing, cache reuse, and index progress in the bottom toolbar.
- Added separate embedding service settings, including OpenAI-compatible providers, local embedding endpoints, custom endpoints, and a separate embedding API key.
- Improved Chinese-to-English retrieval queries when asking Chinese questions about English books.
- Redesigned the settings panel with scrolling layout, clearer fields, and a more visible window edge.
- Reworked the book vocabulary panel into a scrollable card view.
- Improved app stability by replacing fragile sheet-based panels with child windows.

## Requirements

- macOS 12.0 or later.
- Swift toolchain with Cocoa, PDFKit, WebKit, and CryptoKit frameworks.
- An API key for AI features, configured inside the app settings.

## Run

Open a locally built app bundle:

```sh
open "Leaf Reader.app"
```

The app bundle is generated locally and is not committed to git.

## Build From Source

Create the app bundle directory if needed, then compile the Swift sources:

```sh
mkdir -p "Leaf Reader.app/Contents/MacOS" "Leaf Reader.app/Contents/Resources"
cp mac-app/Info.plist "Leaf Reader.app/Contents/Info.plist"
cp mac-app/AIPrompts.json "Leaf Reader.app/Contents/Resources/AIPrompts.json"
cp mac-app/AppIcon.icns "Leaf Reader.app/Contents/Resources/AppIcon.icns"
swiftc mac-app/*.swift \
  -o "Leaf Reader.app/Contents/MacOS/Leaf Reader" \
  -framework Cocoa \
  -framework PDFKit \
  -framework WebKit \
  -framework CryptoKit \
  -framework AVFoundation \
  -lsqlite3
```

Re-sign the rebuilt app:

```sh
codesign --force --deep --sign - "Leaf Reader.app"
```

Then run it:

```sh
open "Leaf Reader.app"
```

## Tests

Run the lightweight logic regression tests:

```sh
./tests/run.sh
```

## Project Layout

- `Leaf Reader.app` - generated macOS application bundle, ignored by git.
- `mac-app/*.swift` - native Swift source code.
- `tests/` - lightweight Swift logic regression tests.
- `mac-app/AIPrompts.json` - built-in AI prompt definitions.
- `mac-app/AppIcon.icns` - packaged app icon.
- `mac-app/AppIconSource.png` - source image for the app icon.
- `assets/leaf-reader-icon.png` - project icon used in this README.
- `assets/reader-light-ai-word.png` - light mode word-learning screenshot.
- `assets/reader-bookshelf.png` - bookshelf screenshot.
- `assets/reader-settings.png` - settings panel screenshot.
- `assets/reader-dark-ai.png` - dark mode AI reading screenshot.
- `assets/reader-dark-vocabulary.png` - dark mode vocabulary book screenshot.
- `release/` - local release artifacts when generated.

## Release

Current version: `1.4`

Git tag: `v1.4`

Latest installer:

[Leaf Reader-1.4.pkg](https://github.com/dowellhz/LeafReader/releases/download/v1.4/LeafReader-1.4.pkg)

Local release artifacts are expected under:

```text
release/1.4/
```

## Notes

- Bundle identifier: `com.linlu.leafreader`.
- PDF rendering uses PDFKit.
- EPUB and DOCX rendering uses WebKit. DOCX support is optimized for readable text extraction rather than exact Word layout fidelity.
- Search selections are kept separate from AI passage selection so search navigation does not accidentally populate the assistant.
- AI requests use the model, endpoint, language, and API key configured locally in the settings panel.
