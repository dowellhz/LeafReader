<p align="center">
  <img src="assets/leaf-reader-icon.png" alt="Leaf Reader icon" width="128">
</p>

# Leaf Reader

Leaf Reader is a native macOS document reader built with Swift, PDFKit, and WebKit. It supports PDF, EPUB, and DOCX reading with quick navigation, text selection, search, reading progress restore for PDFs, and an integrated AI assistant for explaining selected passages.

![Leaf Reader screenshot](assets/screenshot.png)

## Features

- Open and read local PDF, EPUB, and DOCX files.
- Navigate pages with toolbar buttons and keyboard paging.
- Search with the toolbar button or `Command+F`.
- Zoom in and out with a compact zoom control.
- Restore the last opened PDF, page, and zoom level.
- Select text and ask the built-in AI panel for explanations.
- Configure AI model, API key, and interface language from settings.

## Repository Layout

- `Leaf Reader.app` - built macOS app bundle.
- `mac-app/*.swift` - native Swift source code.
- `mac-app/AppIcon.icns` - packaged app icon.
- `mac-app/AppIconSource.png` - source image for the app icon.
- `assets/leaf-reader-icon.png` - project icon used in this README.
- `assets/screenshot.png` - screenshot used in this README.

## Run

```sh
open "Leaf Reader.app"
```

## Build

Compile the Swift source into the existing app bundle:

```sh
swiftc mac-app/*.swift \
  -o "Leaf Reader.app/Contents/MacOS/Leaf Reader" \
  -framework Cocoa \
  -framework PDFKit \
  -framework WebKit \
  -framework CryptoKit
```

Re-sign the app locally after rebuilding:

```sh
codesign --force --deep --sign - "Leaf Reader.app"
```

## Release

Version `1.0.1` is tagged as `v1.0.1`.

Local release artifacts are generated under:

```text
release/1.0.1/
```

## Requirements

- macOS 12.0 or later.
- Swift toolchain with Cocoa, PDFKit, WebKit, and CryptoKit frameworks.

## Notes

- Bundle identifier: `com.linlu.leafreader`.
- The checked-in app is ad-hoc signed for local testing and distribution.
- EPUB and DOCX are rendered through WebKit. DOCX support focuses on readable text content rather than exact Word layout.
- AI requests use the API key configured locally in the app settings.
