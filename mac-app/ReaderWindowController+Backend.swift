extension ReaderWindowController {
    var activeReaderBackend: ReaderContentBackend? {
        currentDocumentKind == .pdf ? pdfReaderBackend : webReaderBackend
    }

    var activePagedReaderBackend: ReaderPagedBackend? {
        activeReaderBackend as? ReaderPagedBackend
    }

    var activeContinuousReaderBackend: ReaderContinuousBackend? {
        activeReaderBackend as? ReaderContinuousBackend
    }
}
