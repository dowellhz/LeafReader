# Document Loading

Leaf Reader supports PDF, EPUB, and DOCX.

## Flow

```text
Open file
  -> Detect document kind
     -> PDF: show with PDFKit -> prepare reusable text snapshot in background
     -> EPUB: unpack EPUB cache -> build reader HTML -> render in WebKit
     -> DOCX: unpack temp DOCX -> build reader HTML -> render in WebKit
  -> ReaderWindowController
```

## Files

- `DocumentLoading.swift`: document kind, shared readable document types, loader entry point.
- `DocumentLoading+Archive.swift`: unzip, EPUB cache root, archive entry reads.
- `DocumentLoading+EPUB.swift`: EPUB package loading, cover, TOC, resource lookup.
- `DocumentLoading+DOCX.swift`, `DocumentLoading+DOCXStreaming.swift`, `DocumentLoading+DOCXCache.swift`: cancellable DOCX streaming preparation and verified prepared-output caching.
- `DocumentLoading+HTML.swift`: HTML rewriting, page wrapper, regex helpers.
- `PDFDocumentTextSnapshot.swift`: content-addressed PDF text snapshot cache and cancellable extraction pacing.
- `EPUBPackageParser.swift`, `EPUBPathResolver.swift`, `EPUBHTMLSanitizer.swift`, `EPUBTextDecoder.swift`: focused EPUB logic helpers.

## Notes

- EPUB unpacking is cached under the user cache directory.
- DOCX prepared output is cached by source-content fingerprint, verified before reuse, and published atomically.
- EPUB and DOCX are rendered through generated HTML in WebKit.
- PDF remains in PDFKit for page navigation and annotation support.
- PDF text extraction runs off the UI path, pauses briefly during reader interaction, and is shared by whole-document AI indexing.

## Related Files

- `mac-app/DocumentLoading.swift`
- `mac-app/DocumentLoading+Archive.swift`
- `mac-app/DocumentLoading+EPUB.swift`
- `mac-app/DocumentLoading+DOCX.swift`
- `mac-app/DocumentLoading+DOCXStreaming.swift`
- `mac-app/DocumentLoading+DOCXCache.swift`
- `mac-app/DocumentLoading+HTML.swift`
- `mac-app/PDFDocumentTextSnapshot.swift`
- `mac-app/ReaderDocumentKind.swift`
- `mac-app/Resources/reader-web.js`
